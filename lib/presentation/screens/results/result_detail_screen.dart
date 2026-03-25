import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/algorithm_settings.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/datasources/local/database_helper.dart';
import '../../../domain/entities/test_result.dart';
import '../../../domain/services/pdf_report_service.dart';
import '../../providers/athlete_provider.dart';
import '../../providers/calibration_provider.dart';
import '../../providers/test_state_provider.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/cards/symmetry_gauge.dart';

// ── Provider: most recent SJ height for an athlete ───────────────────────────

final _latestSjHeightProvider =
    FutureProvider.autoDispose.family<double?, int>((ref, athleteId) async {
  final rows = await DatabaseHelper.instance
      .getSessionsForAthleteAndType(athleteId, TestType.sj.name);
  if (rows.isEmpty) return null;
  // rows are sorted ASC — take the last (most recent).
  final json = rows.last['result_json'] as String?;
  if (json == null) return null;
  try {
    final result = TestResult.fromJson(json);
    if (result is JumpResult) return result.jumpHeightCm;
  } catch (_) {}
  return null;
});

/// Displays full results after a completed test.
/// Receives the [TestResult] via GoRouter extra parameter.
/// Auto-saves the result to SQLite on first display (when sessionId == null).
class ResultDetailScreen extends ConsumerStatefulWidget {
  final TestResult result;
  const ResultDetailScreen({super.key, required this.result});

  @override
  ConsumerState<ResultDetailScreen> createState() => _ResultDetailScreenState();
}

class _ResultDetailScreenState extends ConsumerState<ResultDetailScreen> {
  // Process-level deduplication: tracks ISO-8601 timestamps of results that
  // have already been saved in this app session.  Prevents double-insertion
  // when the widget is destroyed and recreated (e.g. back-navigation) while
  // the TestResult object still reports sessionId == null (it is immutable).
  static final Set<String> _savedTimestamps = {};

  @override
  void initState() {
    super.initState();
    final key = widget.result.computedAt.toIso8601String();
    if (widget.result.sessionId == null && !_savedTimestamps.contains(key)) {
      _savedTimestamps.add(key);
      WidgetsBinding.instance.addPostFrameCallback((_) => _saveResult());
    }
  }

  Future<void> _saveResult() async {
    if (!ref.read(settingsProvider).autoSaveTests) return;
    final athlete = ref.read(selectedAthleteProvider);
    if (athlete?.id == null) return;

    final calId = ref.read(calibrationProvider).activeCalibration?.id;
    double bwKg = athlete?.bodyWeightKg ?? 0;
    if (widget.result is JumpResult) {
      final jr = widget.result as JumpResult;
      if (jr.bodyWeightN > 0) bwKg = jr.bodyWeightN / 9.81;
    }

    try {
      await DatabaseHelper.instance.insertTestSession({
        'athlete_id':     athlete!.id,
        'test_type':      widget.result.testType.name,
        'performed_at':   widget.result.computedAt.toIso8601String(),
        'body_weight_kg': bwKg,
        'calibration_id': calId,
        'platform_count': widget.result.platformCount,
        'result_json':    widget.result.toJson(),
        'sync_status':    'pending',
      });
      if (mounted) ref.invalidate(sessionHistoryProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.get('error_saving_result')}: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    // For CMJ results, try to load the most recent SJ height for elasticity index.
    final athlete = ref.watch(selectedAthleteProvider);
    final sjHeightAsync = (widget.result is JumpResult &&
            widget.result.testType == TestType.cmj &&
            athlete?.id != null)
        ? ref.watch(_latestSjHeightProvider(athlete!.id!))
        : null;
    final sjHeightCm = sjHeightAsync?.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.result.testType.displayName),
        actions: [_PdfExportButton(result: widget.result)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: switch (widget.result) {
          DropJumpResult r  => _JumpResultView(result: r, settings: settings),
          JumpResult r      => _JumpResultView(
              result: r, settings: settings,
              sjHeightCm: r.testType == TestType.cmj ? sjHeightCm : null,
            ),
          CoPResult r       => _CoPResultView(result: r, engineerMode: settings.engineerMode),
          ImtpResult r      => _ImtpResultView(result: r, engineerMode: settings.engineerMode),
          MultiJumpResult r => _MultiJumpResultView(result: r, engineerMode: settings.engineerMode),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Jump result (CMJ / SJ / Drop Jump)
// ─────────────────────────────────────────────────────────────────────────────

class _JumpResultView extends StatelessWidget {
  final JumpResult result;
  final AppSettings settings;
  /// SJ jump height in cm from the most recent SJ test (used for elasticity index on CMJ).
  final double? sjHeightCm;
  const _JumpResultView({
    required this.result,
    required this.settings,
    this.sjHeightCm,
  });

  // ── Dynamic labels based on selected algorithms ───────────────────────────

  String get _heightMethodNote => settings.useImpulseHeight
      ? AppStrings.get('height_method_impulse')
      : AppStrings.get('height_method_flight');

  String get _powerPrimaryLabel => AppStrings.get('peak_power_label');

  String get _symmetryLabel => settings.useLsiSymmetry
      ? AppStrings.get('symmetry_lsi')
      : AppStrings.get('asymmetry_pct');

  bool get _showImpulsePowerCard =>
      settings.algo.peakPower != PeakPowerMethod.impulseBased &&
      result.peakPowerImpulseW > 0;

  /// Elasticity index = (CMJ − SJ) / SJ × 100
  /// Only meaningful when sjHeightCm is available and > 0.
  double? get _elasticityIndex {
    final sj = sjHeightCm;
    if (sj == null || sj <= 0) return null;
    return (result.jumpHeightCm - sj) / sj * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Hero: jump height ──────────────────────────────────────────────
        _HeroMetric(
          value: result.jumpHeightCm.toStringAsFixed(1),
          unit: 'cm',
          label: AppStrings.get('jump_height_hero'),
          note: _heightMethodNote,
        ),
        const SizedBox(height: 24),

        // ── Performance grid ───────────────────────────────────────────────
        Text(AppStrings.get('performance_section'), style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(
            label: AppStrings.get('flight_time_label'),
            value: result.flightTimeMs.toStringAsFixed(0),
            unit: 'ms',
          ),
          MetricCard(
            label: AppStrings.get('peak_force_label'),
            value: result.peakForceN.toStringAsFixed(0),
            unit: 'N',
            valueColor: AppColors.warning,
          ),
          MetricCard(
            label: AppStrings.get('mean_force_label'),
            value: result.meanForceN.toStringAsFixed(0),
            unit: 'N',
          ),
          // Primary power — label reflects the selected algorithm
          MetricCard(
            label: _powerPrimaryLabel,
            value: result.peakPowerSayersW.toStringAsFixed(0),
            unit: 'W',
            valueColor: AppColors.secondary,
            isHighlighted: true,
          ),
          // Impulse-based power — only shown when a regression method is active
          if (_showImpulsePowerCard)
            MetricCard(
              label: AppStrings.get('power_fv_label'),
              value: result.peakPowerImpulseW.toStringAsFixed(0),
              unit: 'W',
              valueColor: AppColors.secondary,
            ),
        ]),
        const SizedBox(height: 20),

        // ── RFD ───────────────────────────────────────────────────────────
        Text(AppStrings.get('explosivity_section'),
            style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(
            label: AppStrings.get('rfd_50ms'),
            value: (result.rfdAt50ms / 1000).toStringAsFixed(1),
            unit: 'kN/s',
            valueColor: AppColors.forceLeft,
          ),
          MetricCard(
            label: AppStrings.get('rfd_100ms'),
            value: (result.rfdAt100ms / 1000).toStringAsFixed(1),
            unit: 'kN/s',
            valueColor: AppColors.forceLeft,
          ),
          MetricCard(
            label: AppStrings.get('rfd_200ms'),
            value: (result.rfdAt200ms / 1000).toStringAsFixed(1),
            unit: 'kN/s',
            valueColor: AppColors.forceLeft,
          ),
          MetricCard(
            label: AppStrings.get('ttp_label'),
            value: result.timeToPeakForceMs.toStringAsFixed(0),
            unit: 'ms',
          ),
        ]),
        const SizedBox(height: 20),

        // ── Phases ────────────────────────────────────────────────────────
        Text(AppStrings.get('phases_section'), style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(
            label: AppStrings.get('eccentric_phase'),
            value: result.eccentricDurationMs.toStringAsFixed(0),
            unit: 'ms',
            valueColor: AppColors.forceRight,
          ),
          MetricCard(
            label: AppStrings.get('concentric_phase'),
            value: result.concentricDurationMs.toStringAsFixed(0),
            unit: 'ms',
            valueColor: AppColors.primary,
          ),
        ]),

        // ── Symmetry ─────────────────────────────────────────────────────
        if (result.symmetry.leftPercent != 50 || result.platformCount >= 1) ...[
          const SizedBox(height: 20),
          Text('${AppStrings.get('symmetry_section')}  ·  $_symmetryLabel',
              style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.col.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.col.border),
            ),
            child: SymmetryGauge(
              leftPercent:  result.symmetry.leftPercent,
              leftLabel:   result.symmetry.isTwoPlatform ? 'IZQ'    : 'MASTER',
              rightLabel:  result.symmetry.isTwoPlatform ? 'DER'    : 'SLAVE',
              isEstimated: !result.symmetry.isTwoPlatform,
            ),
          ),
        ],

        // ── Elasticity index (CMJ vs SJ) ──────────────────────────────────
        if (_elasticityIndex != null) ...[
          const SizedBox(height: 20),
          Text(AppStrings.get('elasticity_index'), style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.col.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.secondary.withAlpha(77)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.secondary.withAlpha(13),
                  context.col.surface,
                ],
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _elasticityIndex!.toStringAsFixed(1),
                      style: IXTextStyles.metricValue(color: AppColors.secondary)
                          .copyWith(fontSize: 40),
                    ),
                    const SizedBox(width: 4),
                    Text('%',
                        style: IXTextStyles.metricLabel
                            .copyWith(fontSize: 16, color: AppColors.secondary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'CMJ ${result.jumpHeightCm.toStringAsFixed(1)} cm  −  SJ ${sjHeightCm!.toStringAsFixed(1)} cm',
                      style: TextStyle(
                          fontSize: 12, color: context.col.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '(CMJ − SJ) / SJ × 100',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.col.textDisabled,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Drop Jump extras ──────────────────────────────────────────────
        if (result is DropJumpResult) ...[
          const SizedBox(height: 20),
          Text(AppStrings.get('drop_jump_section'), style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 12),
          _MetricGrid(children: [
            MetricCard(
              label: AppStrings.get('contact_time_label'),
              value: (result as DropJumpResult).contactTimeMs.toStringAsFixed(0),
              unit: 'ms',
              valueColor: AppColors.warning,
            ),
            MetricCard(
              label: AppStrings.get('reactivity_rsi'),
              value: (result as DropJumpResult).rsiMod.toStringAsFixed(2),
              unit: '',
              valueColor: AppColors.success,
              isHighlighted: true,
            ),
          ]),
        ],

        // ── Metadata ──────────────────────────────────────────────────────
        const SizedBox(height: 24),
        _Metadata(
          computedAt:    result.computedAt,
          platformCount: result.platformCount,
          bodyWeightN:   result.bodyWeightN,
          engineerMode:  settings.engineerMode,
          algoNotes: [
            'Altura: ${settings.useImpulseHeight ? "Impulso-Momento" : "Tiempo vuelo"}',
            'Potencia: ${switch (settings.algo.peakPower) {
              PeakPowerMethod.sayers       => "Fórmula regresión A",
              PeakPowerMethod.harman       => "Fórmula regresión B",
              PeakPowerMethod.impulseBased => "F×v impulso",
            }}',
            'Simetría: ${settings.useLsiSymmetry ? "LSI" : "AI"}',
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CoP result
// ─────────────────────────────────────────────────────────────────────────────

class _CoPResultView extends StatelessWidget {
  final CoPResult result;
  final bool engineerMode;
  const _CoPResultView({required this.result, this.engineerMode = false});

  bool get _is1D => result.platformCount < 2;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // ── Hero: sway area ───────────────────────────────────────────────
        // Label and note adapt to hardware capability (1D vs 2D).
        _HeroMetric(
          value: result.areaEllipseMm2.toStringAsFixed(0),
          unit:  'mm²',
          label: _is1D ? AppStrings.get('cop_area_estimated') : AppStrings.get('cop_area_95'),
        ),

        // ── 1D notice chip ────────────────────────────────────────────────
        if (_is1D) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(30),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.warning.withAlpha(100)),
              ),
              child: Text(
                AppStrings.get('cop_1d_note'),
                style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // ── Stability grid ────────────────────────────────────────────────
        Text(AppStrings.get('stability_section'), style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(
            label: AppStrings.get('path_length_label'),
            value: result.pathLengthMm.toStringAsFixed(0),
            unit: 'mm',
          ),
          MetricCard(
            label: AppStrings.get('mean_velocity_label'),
            value: result.meanVelocityMmS.toStringAsFixed(1),
            unit: 'mm/s',
          ),
          MetricCard(
            label: AppStrings.get('ml_range_label'),
            value: result.rangeMLMm.toStringAsFixed(1),
            unit: 'mm',
            valueColor: AppColors.forceLeft,
          ),
          // Rango AP only meaningful with 2-platform (moment-based) hardware.
          if (!_is1D)
            MetricCard(
              label: AppStrings.get('ap_range_label'),
              value: result.rangeAPMm.toStringAsFixed(1),
              unit: 'mm',
              valueColor: AppColors.forceRight,
            ),
          MetricCard(
            label: AppStrings.get('osc_freq_label'),
            value: result.frequency95Hz.toStringAsFixed(2),
            unit: 'Hz',
          ),
          if (!_is1D && result.symmetryPercent < 100)
            MetricCard(
              label: AppStrings.get('weight_symmetry_label'),
              value: result.symmetryPercent.toStringAsFixed(1),
              unit: '%',
              valueColor: result.symmetryPercent > 85
                  ? AppColors.success
                  : AppColors.warning,
            ),
        ]),

        // ── Romberg quotient ──────────────────────────────────────────────
        if (result.rombergQuotient != null) ...[
          const SizedBox(height: 20),
          Text(AppStrings.get('romberg_section'), style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 12),
          MetricCard(
            label: AppStrings.get('romberg_index'),
            value: result.rombergQuotient!.toStringAsFixed(2),
            unit: '',
            isHighlighted: true,
          ),
        ],

        const SizedBox(height: 20),
        _Metadata(
          computedAt:    result.computedAt,
          platformCount: result.platformCount,
          bodyWeightN:   null,
          engineerMode:  engineerMode,
          algoNotes: [
            'Frec: ${_is1D ? "Frecuencia de oscilación (Izq-Der)" : "Frecuencia de oscilación 2D"}',
            if (_is1D) 'Área: Estimación con 1 plataforma',
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMTP result
// ─────────────────────────────────────────────────────────────────────────────

class _ImtpResultView extends StatelessWidget {
  final ImtpResult result;
  final bool engineerMode;
  const _ImtpResultView({required this.result, this.engineerMode = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroMetric(
          value: result.peakForceN.toStringAsFixed(0),
          unit:  'N',
          label: AppStrings.get('imtp_peak_force_hero'),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '${result.peakForceBW.toStringAsFixed(2)} ${AppStrings.get('times_bw')}',
            style: TextStyle(
                fontSize: 15, color: context.col.textSecondary),
          ),
        ),
        const SizedBox(height: 24),
        Text(AppStrings.get('explosivity_rfd_section'), style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(label: AppStrings.get('rfd_50ms'),
              value: (result.rfdAt50ms / 1000).toStringAsFixed(1),
              unit: 'kN/s', valueColor: AppColors.forceLeft),
          MetricCard(label: AppStrings.get('rfd_100ms'),
              value: (result.rfdAt100ms / 1000).toStringAsFixed(1),
              unit: 'kN/s', valueColor: AppColors.forceLeft),
          MetricCard(label: AppStrings.get('rfd_200ms'),
              value: (result.rfdAt200ms / 1000).toStringAsFixed(1),
              unit: 'kN/s', valueColor: AppColors.forceLeft),
          MetricCard(label: AppStrings.get('ttp_label'),
              value: result.timeToPeakForceMs.toStringAsFixed(0), unit: 'ms'),
        ]),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color:        context.col.surface,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: context.col.border)),
          child: SymmetryGauge(
            leftPercent:  result.symmetry.leftPercent,
            leftLabel:   result.symmetry.isTwoPlatform ? 'IZQ'    : 'IZQ',
            rightLabel:  result.symmetry.isTwoPlatform ? 'DER'    : 'DER',
            isEstimated: !result.symmetry.isTwoPlatform,
          ),
        ),
        const SizedBox(height: 20),
        _Metadata(
          computedAt:    result.computedAt,
          platformCount: result.platformCount,
          bodyWeightN:   null,
          engineerMode:  engineerMode,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-jump result
// ─────────────────────────────────────────────────────────────────────────────

class _MultiJumpResultView extends StatelessWidget {
  final MultiJumpResult result;
  final bool engineerMode;
  const _MultiJumpResultView({required this.result, this.engineerMode = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroMetric(
          value: result.meanRsiMod.toStringAsFixed(2),
          unit:  '',
          label: AppStrings.get('reactivity_section'),
        ),
        const SizedBox(height: 24),
        Text(AppStrings.get('summary_section'), style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        _MetricGrid(children: [
          MetricCard(label: AppStrings.get('mean_height_label'),
              value: result.meanHeightCm.toStringAsFixed(1), unit: 'cm'),
          MetricCard(label: AppStrings.get('mean_contact_label'),
              value: result.meanContactTimeMs.toStringAsFixed(0), unit: 'ms'),
          MetricCard(label: AppStrings.get('fatigue_index'),
              value: result.fatiguePercent.toStringAsFixed(1), unit: '%',
              valueColor: result.fatiguePercent > 10
                  ? AppColors.danger : AppColors.success),
          MetricCard(label: AppStrings.get('variability_label'),
              value: result.variabilityPercent.toStringAsFixed(1), unit: '%'),
        ]),
        const SizedBox(height: 20),
        Text('${AppStrings.get('per_jump_section')} (${result.jumpCount})',
            style: IXTextStyles.sectionHeader()),
        const SizedBox(height: 12),
        ...result.jumps.map((j) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.col.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.col.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('#${j.jumpNumber}',
                    style: TextStyle(
                        color: context.col.textSecondary, fontSize: 13)),
                Text('${j.heightCm.toStringAsFixed(1)} cm',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                Text('${j.contactTimeMs.toStringAsFixed(0)}ms CT',
                    style: TextStyle(
                        color: context.col.textSecondary, fontSize: 12)),
                Text('React. ${j.rsiMod.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        )),
        const SizedBox(height: 20),
        _Metadata(
          computedAt:    result.computedAt,
          platformCount: result.platformCount,
          bodyWeightN:   null,
          engineerMode:  engineerMode,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Large hero metric with optional method note below the value.
class _HeroMetric extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final String? note;   // small italic line, e.g. "Método: Impulso-Momento" (optional)
  const _HeroMetric({
    required this.value,
    required this.unit,
    required this.label,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: context.col.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withAlpha(77)),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withAlpha(13),
            context.col.surface,
          ],
        ),
      ),
      child: Column(
        children: [
          Text(label, style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style:
                      IXTextStyles.metricValue().copyWith(fontSize: 52)),
              const SizedBox(width: 6),
              Text(unit,
                  style: IXTextStyles.metricLabel
                      .copyWith(fontSize: 18, color: AppColors.primary)),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(
              note!,
              style: TextStyle(
                color:     context.col.textDisabled,
                fontSize:  11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<Widget> children;
  const _MetricGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   2,
        mainAxisSpacing:  8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
      ),
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
    );
  }
}

class _Metadata extends StatelessWidget {
  final DateTime computedAt;
  final int platformCount;
  final double? bodyWeightN;
  final List<String> algoNotes;
  final bool engineerMode;

  const _Metadata({
    required this.computedAt,
    required this.platformCount,
    this.bodyWeightN,
    this.algoNotes = const [],
    this.engineerMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: col.border),
      ),
      child: Column(
        children: [
          _Row(AppStrings.get('date_label'),         _formatDate(computedAt),  col),
          if (bodyWeightN != null)
            _Row(AppStrings.get('body_weight_label'),
                '${(bodyWeightN! / 9.81).toStringAsFixed(1)} kg', col),
          _Row(AppStrings.get('platforms_label'), '$platformCount',          col),
          // Algorithm notes — only shown in engineer mode
          if (engineerMode) ...[
            for (final note in algoNotes)
              _Row(
                note.split(':').first.trim(),
                note.contains(':') ? note.split(':').last.trim() : note,
                col,
                isAlgo: true,
              ),
          ],
        ],
      ),
    );
  }

  Widget _Row(String label, String value, ThemeColors col,
      {bool isAlgo = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: isAlgo ? col.textDisabled : col.textSecondary)),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    color: isAlgo ? col.textDisabled : col.textPrimary,
                    fontWeight:
                        isAlgo ? FontWeight.w400 : FontWeight.w500,
                    fontStyle:
                        isAlgo ? FontStyle.italic : FontStyle.normal)),
          ],
        ),
      );

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/'
      '${dt.month.toString().padLeft(2, '0')}/'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// PDF Export Button
// ─────────────────────────────────────────────────────────────────────────────

class _PdfExportButton extends ConsumerStatefulWidget {
  final TestResult result;
  const _PdfExportButton({required this.result});

  @override
  ConsumerState<_PdfExportButton> createState() => _PdfExportButtonState();
}

class _PdfExportButtonState extends ConsumerState<_PdfExportButton> {
  bool _loading = false;

  Future<void> _export() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final athlete   = ref.read(selectedAthleteProvider);
      final notifier  = ref.read(testStateProvider.notifier);
      final forceData = notifier.lastForceN;
      final timeData  = notifier.lastTimeS;
      await PdfReportService.generateAndShare(
        result:    widget.result,
        athlete:   athlete,
        rawForceN: forceData.isNotEmpty ? forceData : null,
        rawTimeS:  timeData.isNotEmpty  ? timeData  : null,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:         Text('${AppStrings.get('error_pdf')}: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }
    return IconButton(
      icon:    const Icon(Icons.picture_as_pdf_outlined),
      tooltip: AppStrings.get('export_pdf'),
      onPressed: _export,
    );
  }
}
