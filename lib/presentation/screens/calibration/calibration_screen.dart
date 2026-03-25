import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/calibration_data.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/live_data_provider.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart';

// Collection phase state machine
enum _CalPhase { idle, collectingTare, collectingPoint }

// Calibration method: per-cell (recommended) or legacy polynomial (app.py style)
enum _CalMethod { perCell, polynomial }

class CalibrationScreen extends ConsumerStatefulWidget {
  const CalibrationScreen({super.key});

  @override
  ConsumerState<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends ConsumerState<CalibrationScreen> {
  int _step = 0;
  final _weightCtrl = TextEditingController();
  final _nameCtrl   = TextEditingController(text: 'Calibración');
  bool _saving = false;
  CalibrationMode _mode   = CalibrationMode.segmented;
  _CalMethod      _method = _CalMethod.perCell;

  // ── Per-cell polarity: +1 normal, -1 bridge wired inverted ─────────────────
  // Persisted in SharedPreferences so it survives app restarts.
  Map<String, int> _polarities = {
    'A_ML': 1, 'A_MR': 1, 'A_SL': 1, 'A_SR': 1,
  };

  // ── Live display buffer — 3 s at 30 Hz ────────────────────────────────────
  final List<double> _readings = [];
  final List<double> _rawSums  = [];
  ProviderSubscription<LiveDataState>? _liveSub;

  // Live-display means (last 90 samples at 30 Hz)
  final List<double> _liveAML = [], _liveAMR = [], _liveASL = [], _liveASR = [];
  static const int _bufferSize = 90; // 3 s

  // ── Batch-collection buffers ───────────────────────────────────────────────
  // Collecting at full hardware rate (up to 1000 Hz).
  // 2000 samples ≈ 2 s → SEM ≈ raw_std / √2000 ≈ 0.05 % → mayor precisión.
  static const int _collectSamples = 2000;
  _CalPhase _phase = _CalPhase.idle;
  final List<double> _cAML = [], _cAMR = [], _cASL = [], _cASR = [];

  // ── Helpers ───────────────────────────────────────────────────────────────
  static double _mean(List<double> l) =>
      l.isEmpty ? 0 : l.fold(0.0, (s, v) => s + v) / l.length;

  static double _std(List<double> l) {
    if (l.length < 2) return 0;
    final m = _mean(l);
    final variance = l.fold(0.0, (s, x) => s + (x - m) * (x - m)) / l.length;
    if (variance <= 0) return 0;
    double g = variance / 2;
    for (int i = 0; i < 20; i++) g = (g + variance / g) / 2;
    return g;
  }

  double get _liveSmoothedN => _mean(_readings);
  double get _liveMeanAML   => _mean(_liveAML);
  double get _liveMeanAMR   => _mean(_liveAMR);
  double get _liveMeanASL   => _mean(_liveASL);
  double get _liveMeanASR   => _mean(_liveASR);

  double get _liveCvPct {
    if (_rawSums.length < 2) return 100;
    final m = _mean(_rawSums);
    final s = _std(_rawSums);
    // Step 1 (tare/vacío): mean ≈ tare offset, often small relative to noise.
    // Use absolute std normalized to a fixed scale (500 counts) so the empty
    // platform doesn't show artificially high CV%.
    // Step 2+ (with person): mean >> 500, so CV formula gives correct result.
    final scale = m.abs() < 500 ? 500.0 : m.abs();
    return s / scale * 100;
  }

  int get _collectProgress => _cAML.length;

  // Apply polarity correction inline
  double _p(String cell, double v) => v * (_polarities[cell] ?? 1);

  void _addToLiveBuffer(LiveDataState s) {
    final aml = _p('A_ML', s.currentRawAML);
    final amr = _p('A_MR', s.currentRawAMR);
    final asl = _p('A_SL', s.currentRawASL);
    final asr = _p('A_SR', s.currentRawASR);
    _readings.add(s.currentSmoothedN);
    _rawSums.add(aml + amr + asl + asr);
    _liveAML.add(aml); _liveAMR.add(amr);
    _liveASL.add(asl); _liveASR.add(asr);
    if (_readings.length > _bufferSize) {
      _readings.removeAt(0); _rawSums.removeAt(0);
      _liveAML.removeAt(0);  _liveAMR.removeAt(0);
      _liveASL.removeAt(0);  _liveASR.removeAt(0);
    }
  }

  void _clearCollectBuf() {
    _cAML.clear(); _cAMR.clear(); _cASL.clear(); _cASR.clear();
  }

  void _addToCollectBuf(LiveDataState s) {
    _cAML.add(_p('A_ML', s.currentRawAML));
    _cAMR.add(_p('A_MR', s.currentRawAMR));
    _cASL.add(_p('A_SL', s.currentRawASL));
    _cASR.add(_p('A_SR', s.currentRawASR));
  }

  // ── Polarity persistence ───────────────────────────────────────────────────

  Future<void> _loadPolarities() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _polarities = {
        'A_ML': prefs.getInt('pol_A_ML') ?? 1,
        'A_MR': prefs.getInt('pol_A_MR') ?? 1,
        'A_SL': prefs.getInt('pol_A_SL') ?? 1,
        'A_SR': prefs.getInt('pol_A_SR') ?? 1,
      };
    });
  }

  Future<void> _togglePolarity(String cell) async {
    final next = (_polarities[cell] ?? 1) == 1 ? -1 : 1;
    setState(() => _polarities[cell] = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('pol_$cell', next);
    // Clear live buffers so they rebuild with new polarity
    _readings.clear(); _rawSums.clear();
    _liveAML.clear();  _liveAMR.clear();
    _liveASL.clear();  _liveASR.clear();
  }

  @override
  void initState() {
    super.initState();
    _loadPolarities();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Always start a fresh calibration session — discard any leftover
      // pending points from a previous (possibly incomplete) visit.
      ref.read(calibrationProvider.notifier).clearPendingPoints();

      _liveSub = ref.listenManual<LiveDataState>(
        liveDataProvider,
        (_, next) {
          if (_phase == _CalPhase.idle) {
            // Live display throttled to ~30 Hz
            if (next.samplesReceived % 33 == 0) {
              setState(() => _addToLiveBuffer(next));
            }
          } else {
            // Batch collection at full hardware rate — no setState per sample
            _addToCollectBuf(next);

            // Progress bar refresh at ~10 Hz
            if (next.samplesReceived % 100 == 0) {
              setState(() {});
            }

            if (_collectProgress >= _collectSamples) {
              setState(() => _finishCollection());
            }
          }
        },
      );
    });
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _nameCtrl.dispose();
    _liveSub?.close();
    super.dispose();
  }

  // ── Collection lifecycle ───────────────────────────────────────────────────

  void _startCollectTare() {
    _clearCollectBuf();
    setState(() => _phase = _CalPhase.collectingTare);
  }

  void _startCollectPoint() {
    final kg = double.tryParse(_weightCtrl.text);
    if (kg == null || kg <= 0) return;
    _clearCollectBuf();
    setState(() => _phase = _CalPhase.collectingPoint);
  }

  void _finishCollection() {
    final aml = _mean(_cAML), amr = _mean(_cAMR);
    final asl = _mean(_cASL), asr = _mean(_cASR);
    final n   = _cAML.length;
    _clearCollectBuf();

    if (_phase == _CalPhase.collectingTare) {
      ref.read(calibrationProvider.notifier).recordTare(
        rawAML: aml, rawAMR: amr, rawASL: asl, rawASR: asr,
      );
      _phase = _CalPhase.idle;
      _step  = 1;
    } else if (_phase == _CalPhase.collectingPoint) {
      final kg = double.tryParse(_weightCtrl.text) ?? 0;
      final rawSum = aml + amr + asl + asr;
      ref.read(calibrationProvider.notifier).addPoint(
        kg, rawSum,
        rawAML: aml, rawAMR: amr, rawASL: asl, rawASR: asr,
      );
      _weightCtrl.clear();
      _phase = _CalPhase.idle;
      debugPrint('CalibrationScreen: tare captured from $n samples');
    }
  }

  void _cancelCollection() {
    _clearCollectBuf();
    setState(() => _phase = _CalPhase.idle);
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _compute() async {
    setState(() => _saving = true);
    await ref.read(calibrationProvider.notifier).computeAndSave(
      name: _nameCtrl.text.trim().isEmpty ? 'Calibración' : _nameCtrl.text.trim(),
      mode: _mode,
      cellOffsets: _method == _CalMethod.polynomial ? {} : null,
      cellPolarities: Map.of(_polarities),
    );
    if (mounted) {
      setState(() { _saving = false; _step = 0; });
      if (ref.read(calibrationProvider).isCalibrated) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cal = ref.watch(calibrationProvider);
    final col = context.col;
    final isCollecting = _phase != _CalPhase.idle;
    final isEngineer = ref.watch(settingsProvider).engineerMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('calibration_title')),
        actions: [
          if (cal.activeCalibration != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.successDim,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    cal.activeCalibration!.isPerCell
                        ? 'Calibrado (por celda)'
                        : 'Calibrado',
                    style: IXTextStyles.metricLabel
                        .copyWith(color: AppColors.success),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Live reading card ────────────────────────────────────────
            _LiveReadingCard(
              smoothedN:    _liveSmoothedN,
              cvPct:        _liveCvPct,
              sampleCount:  _rawSums.length,
              rawAML:       _liveMeanAML,
              rawAMR:       _liveMeanAMR,
              rawASL:       _liveMeanASL,
              rawASR:       _liveMeanASR,
              engineerMode: isEngineer,
            ),
            const SizedBox(height: 12),

            // ── Polarity panel (advanced, collapsed by default) ──────────
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Row(children: [
                  Icon(Icons.tune, size: 14, color: context.col.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    'Opciones avanzadas de hardware',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.col.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ]),
                children: [
                  const SizedBox(height: 6),
                  _PolarityPanel(
                    polarities: _polarities,
                    liveMeans: {
                      'A_ML': _liveMeanAML,
                      'A_MR': _liveMeanAMR,
                      'A_SL': _liveMeanASL,
                      'A_SR': _liveMeanASR,
                    },
                    onToggle: _togglePolarity,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Collection progress overlay ──────────────────────────────
            if (isCollecting) ...[
              _CollectionProgressCard(
                phase:    _phase,
                progress: _collectProgress,
                total:    _collectSamples,
                onCancel: _cancelCollection,
              ),
              const SizedBox(height: 16),
            ],

            // ── Step 1: Tare ─────────────────────────────────────────────
            _StepCard(
              step: 0, currentStep: _step,
              title: AppStrings.get('step_1'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.get('empty_platform_instruction'),
                    style: TextStyle(color: col.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.sensors, size: 18),
                      label: Text(AppStrings.get('calibrate_empty')),
                      onPressed: (!isCollecting && _step == 0)
                          ? _startCollectTare
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 2: Add weights ───────────────────────────────────────
            _StepCard(
              step: 1, currentStep: _step,
              title: AppStrings.get('step_2'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coloca el peso sobre la plataforma, espera que deje de '
                    'oscilar, ingresa el valor en kg y presiona "Agregar".',
                    style: TextStyle(color: col.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 8),

                  // Recorded weight points
                  ...cal.pendingPoints.where((p) => p.weightKg > 0).map((p) =>
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.circle,
                              size: 8, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('${p.weightKg.toStringAsFixed(1)} kg',
                              style: TextStyle(
                                  color: col.textPrimary, fontSize: 13)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'A-I:${p.rawAML.toStringAsFixed(0)} '
                              'A-D:${p.rawAMR.toStringAsFixed(0)} '
                              'B-I:${p.rawASL.toStringAsFixed(0)} '
                              'B-D:${p.rawASR.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: col.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _weightCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: AppStrings.get('weight_label'),
                            suffixText: 'kg',
                            hintText: AppStrings.get('weight_hint'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.sensors, size: 16),
                        label: Text(AppStrings.get('add_point')),
                        onPressed: (!isCollecting && _step == 1)
                            ? _startCollectPoint
                            : null,
                      ),
                    ],
                  ),

                  if (cal.pendingPoints
                      .where((p) => p.weightKg > 0)
                      .isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.arrow_forward, size: 16),
                        label: Text(
                          'Continuar con '
                          '${cal.pendingPoints.where((p) => p.weightKg > 0).length} '
                          'punto(s)',
                        ),
                        onPressed: !isCollecting
                            ? () => setState(() => _step = 2)
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Step 3: Compute & save ────────────────────────────────────
            _StepCard(
              step: 2, currentStep: _step,
              title: AppStrings.get('step_3'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name field
                  TextField(
                    controller: _nameCtrl,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('calibration_name'),
                      hintText: AppStrings.get('calibration_hint'),
                      prefixIcon: const Icon(Icons.label_outline, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Method selector label
                  Text(AppStrings.get('calibration_method'),
                      style: IXTextStyles.metricLabel),
                  const SizedBox(height: 8),

                  // Per-cell card
                  _MethodCard(
                    selected: _method == _CalMethod.perCell,
                    icon: Icons.grid_4x4,
                    title: 'Estándar (recomendado)',
                    subtitle: 'Calibra cada sensor individualmente. '
                        'Ideal para todo tipo de superficie.',
                    badge: 'ESTÁNDAR',
                    badgeColor: AppColors.success,
                    onTap: () => setState(() => _method = _CalMethod.perCell),
                  ),
                  const SizedBox(height: 8),

                  // Polynomial card
                  _MethodCard(
                    selected: _method == _CalMethod.polynomial,
                    icon: Icons.show_chart,
                    title: 'Avanzado (polinomial)',
                    subtitle: 'Calibración global con ajuste de curva. '
                        'Para usuarios con experiencia técnica.',
                    badge: 'CLÁSICO',
                    badgeColor: AppColors.warning,
                    onTap: () => setState(() => _method = _CalMethod.polynomial),
                  ),

                  // Polynomial sub-selector
                  if (_method == _CalMethod.polynomial) ...[
                    const SizedBox(height: 12),
                    Text('TIPO DE AJUSTE',
                        style: IXTextStyles.metricLabel),
                    const SizedBox(height: 8),
                    _PolyModeSelector(
                      current: _mode,
                      onChange: (m) => setState(() => _mode = m),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_saving
                          ? 'Guardando...'
                          : 'Guardar Calibración'),
                      onPressed: _step == 2 && !_saving && !isCollecting
                          ? _compute
                          : null,
                    ),
                  ),
                ],
              ),
            ),

            if (cal.error != null) ...[
              const SizedBox(height: 16),
              Text(cal.error!,
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Live reading card ─────────────────────────────────────────────────────────

class _LiveReadingCard extends StatelessWidget {
  final double smoothedN;
  final double cvPct;
  final int sampleCount;
  final double rawAML, rawAMR, rawASL, rawASR;
  final bool engineerMode;

  const _LiveReadingCard({
    required this.smoothedN,
    required this.cvPct,
    required this.sampleCount,
    required this.rawAML,
    required this.rawAMR,
    required this.rawASL,
    required this.rawASR,
    this.engineerMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    // Cells flagged if negative (polarity inversion detected)
    final amlBad = rawAML < 0;
    final amrBad = rawAMR < 0;
    final aslBad = rawASL < 0;
    final asrBad = rawASR < 0;
    final anyBad = amlBad || amrBad || aslBad || asrBad;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total force + noise info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LECTURA EN VIVO', style: IXTextStyles.metricLabel),
                  const SizedBox(height: 4),
                  Text(
                    smoothedN.toStringAsFixed(1),
                    style: IXTextStyles.metricValue(color: AppColors.primary),
                  ),
                  Tooltip(
                    message: 'Estabilidad (%): menor % = medición más estable',
                    child: Text(
                      'Estabilidad: ${cvPct.toStringAsFixed(1)}%'
                      '${cvPct > 3.0 ? '  ⚠ Espera que se estabilice' : '  ✓'}',
                      style: TextStyle(
                        fontSize: 10,
                        color: cvPct > 3.0
                            ? AppColors.warning
                            : col.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              Text('N',
                  style: IXTextStyles.metricLabel
                      .copyWith(color: AppColors.primary, fontSize: 20)),
            ],
          ),

          const SizedBox(height: 14),
          Divider(height: 1, color: col.border),
          const SizedBox(height: 10),

          // Per-cell badges
          Text(
            engineerMode
                ? 'SENSORES POR ZONA (A_ML · A_MR · A_SL · A_SR)'
                : 'SENSORES POR ZONA',
            style: IXTextStyles.metricLabel,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _CellBadge(label: 'A—Izq', techLabel: 'A_ML', value: rawAML, warn: amlBad, engineerMode: engineerMode),
              const SizedBox(width: 8),
              _CellBadge(label: 'A—Der', techLabel: 'A_MR', value: rawAMR, warn: amrBad, engineerMode: engineerMode),
              const SizedBox(width: 8),
              _CellBadge(label: 'B—Izq', techLabel: 'A_SL', value: rawASL, warn: aslBad, engineerMode: engineerMode),
              const SizedBox(width: 8),
              _CellBadge(label: 'B—Der', techLabel: 'A_SR', value: rawASR, warn: asrBad, engineerMode: engineerMode),
            ],
          ),

          if (anyBad) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 13, color: AppColors.warning),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Sensor(es) con valor negativo — despliega "Opciones avanzadas '
                  'de hardware" y activa la corrección del sensor afectado.',
                  style: TextStyle(fontSize: 10, color: AppColors.warning),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 6),
          Text(
            'A—Izq / A—Der = Plataforma A  ·  B—Izq / B—Der = Plataforma B',
            style: TextStyle(fontSize: 9, color: col.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ── Polarity panel ────────────────────────────────────────────────────────────

class _PolarityPanel extends StatelessWidget {
  final Map<String, int> polarities;
  final Map<String, double> liveMeans;
  final void Function(String cell) onToggle;

  const _PolarityPanel({
    required this.polarities,
    required this.liveMeans,
    required this.onToggle,
  });

  static const _cells = [
    ('A_ML', 'A — Izq', 'Plataforma A — Izquierda'),
    ('A_MR', 'A — Der', 'Plataforma A — Derecha'),
    ('A_SL', 'B — Izq', 'Plataforma B — Izquierda'),
    ('A_SR', 'B — Der', 'Plataforma B — Derecha'),
  ];

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final anyInverted = polarities.values.any((v) => v == -1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: anyInverted
              ? AppColors.warning.withOpacity(0.5)
              : col.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Icon(Icons.swap_vert, size: 14,
                color: anyInverted ? AppColors.warning : col.textSecondary),
            const SizedBox(width: 6),
            Text('CORRECCIÓN DE SENSORES', style: IXTextStyles.metricLabel),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Invierte el signo de un sensor si su lectura es negativa',
                style: TextStyle(fontSize: 9, color: col.textDisabled),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // One row per cell
          for (final (key, short, full) in _cells) ...[
            _PolarityRow(
              cellKey:  key,
              shortLabel: short,
              fullLabel:  full,
              polarity: polarities[key] ?? 1,
              liveMean: liveMeans[key] ?? 0,
              onToggle: () => onToggle(key),
            ),
            if (key != 'A_SR') const SizedBox(height: 6),
          ],

          if (anyInverted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, size: 12, color: AppColors.warning),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Corrección de sensor activa. Se guardará automáticamente con la calibración.',
                    style: TextStyle(fontSize: 10, color: AppColors.warning),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

class _PolarityRow extends StatelessWidget {
  final String cellKey;
  final String shortLabel;
  final String fullLabel;
  final int polarity;
  final double liveMean;
  final VoidCallback onToggle;

  const _PolarityRow({
    required this.cellKey,
    required this.shortLabel,
    required this.fullLabel,
    required this.polarity,
    required this.liveMean,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final isInverted = polarity == -1;
    // After polarity is applied, the mean should be positive
    final correctedMean = liveMean; // already corrected upstream
    final stillBad = correctedMean < 0;

    return Row(children: [
      // Cell label
      SizedBox(
        width: 28,
        child: Text(
          shortLabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isInverted ? AppColors.warning : col.textPrimary,
          ),
        ),
      ),
      const SizedBox(width: 4),
      // Full label
      SizedBox(
        width: 80,
        child: Text(
          fullLabel,
          style: TextStyle(fontSize: 10, color: col.textSecondary),
        ),
      ),
      // Live mean value
      SizedBox(
        width: 70,
        child: Text(
          correctedMean == 0.0 ? '—' : correctedMean.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 11,
            color: stillBad
                ? AppColors.danger
                : isInverted
                    ? AppColors.warning
                    : col.textPrimary,
          ),
          textAlign: TextAlign.right,
        ),
      ),
      const Spacer(),
      // Status chip + toggle button
      if (stillBad)
        const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(Icons.error_outline, size: 13, color: AppColors.danger),
        ),
      GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isInverted
                ? AppColors.warning.withOpacity(0.15)
                : col.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isInverted
                  ? AppColors.warning.withOpacity(0.6)
                  : col.border,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              isInverted ? Icons.sync_alt : Icons.check_circle_outline,
              size: 12,
              color: isInverted ? AppColors.warning : col.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              isInverted ? 'CORREGIDO' : 'Normal',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isInverted ? AppColors.warning : col.textSecondary,
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

// ── Collection progress card ──────────────────────────────────────────────────

class _CollectionProgressCard extends StatelessWidget {
  final _CalPhase phase;
  final int progress;
  final int total;
  final VoidCallback onCancel;

  const _CollectionProgressCard({
    required this.phase,
    required this.progress,
    required this.total,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (progress / total).clamp(0.0, 1.0);
    final label = phase == _CalPhase.collectingTare
        ? 'Midiendo... espera'
        : 'Midiendo... espera';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
              TextButton(
                onPressed: onCancel,
                child: Text(AppStrings.get('cancel_calibration'),
                    style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(pct * 100).toStringAsFixed(0)}% completado',
            style: TextStyle(fontSize: 11, color: context.col.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Cell badge ────────────────────────────────────────────────────────────────

class _CellBadge extends StatelessWidget {
  final String label;
  final String techLabel;
  final double value;
  final bool warn;
  final bool engineerMode;
  const _CellBadge({
    required this.label,
    required this.techLabel,
    required this.value,
    this.warn = false,
    this.engineerMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: warn
              ? AppColors.danger.withOpacity(0.08)
              : col.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: warn ? AppColors.danger.withOpacity(0.5) : col.border),
        ),
        child: Column(
          children: [
            if (engineerMode) ...[
              Text(techLabel,
                  style: TextStyle(
                      fontSize: 8,
                      color: warn ? AppColors.danger : AppColors.textSecondary,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 1),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 9,
                    color: warn ? AppColors.danger : AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: warn ? AppColors.danger : col.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Method selector card ──────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _MethodCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.06)
              : col.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary.withOpacity(0.6)
                : col.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.15)
                    : col.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: 18,
                  color: selected ? AppColors.primary : col.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? AppColors.primary : col.textPrimary,
                        )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(badge,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: badgeColor)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: col.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              size: 18,
              color: selected ? AppColors.primary : col.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Polynomial mode sub-selector ──────────────────────────────────────────────

class _PolyModeSelector extends StatelessWidget {
  final CalibrationMode current;
  final void Function(CalibrationMode) onChange;

  const _PolyModeSelector({required this.current, required this.onChange});

  static const _options = [
    (CalibrationMode.linear,    'Lineal',    'Grado 1 — mínimo 1 punto'),
    (CalibrationMode.quadratic, 'Cuadrático','Grado 2 — mínimo 3 puntos'),
    (CalibrationMode.cubic,     'Cúbico',    'Grado 3 — mínimo 4 puntos'),
    (CalibrationMode.segmented, 'Segmentado','Tramos lineales — máxima precisión'),
  ];

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options.map((opt) {
        final (mode, label, hint) = opt;
        final isSelected = current == mode;
        return GestureDetector(
          onTap: () => onChange(mode),
          child: Tooltip(
            message: hint,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.warning.withOpacity(0.12)
                    : col.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected
                      ? AppColors.warning.withOpacity(0.7)
                      : col.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? AppColors.warning : col.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Step card ─────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final int step;
  final int currentStep;
  final String title;
  final Widget child;
  const _StepCard({
    required this.step,
    required this.currentStep,
    required this.title,
    required this.child,
  });

  bool get isActive   => step == currentStep;
  bool get isComplete => step < currentStep;

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? col.surface : col.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withOpacity(0.5)
              : isComplete
                  ? AppColors.success.withOpacity(0.3)
                  : col.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isComplete
                    ? AppColors.success
                    : isActive ? AppColors.primary : col.border,
              ),
              child: Icon(
                isComplete ? Icons.check : Icons.circle,
                size: 14,
                color: isComplete || isActive
                    ? Colors.black
                    : col.textDisabled,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive
                      ? col.textPrimary
                      : col.textSecondary,
                ),
              ),
            ),
          ]),
          if (isActive) ...[
            const SizedBox(height: 16),
            child,
          ],
        ],
      ),
    );
  }
}
