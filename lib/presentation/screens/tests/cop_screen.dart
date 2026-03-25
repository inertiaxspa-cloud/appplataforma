import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../data/models/processed_sample.dart';
import '../../../domain/dsp/metrics/cop_metrics.dart';
import '../../providers/live_data_provider.dart';
import '../settings/settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards/symmetry_gauge.dart';
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/post_test_panel.dart';
import '../../widgets/test_tutorial.dart';
import '../../../domain/entities/test_result.dart';

// Duration of each CoP measurement window
const _testDurationS = 30;

class CopScreen extends ConsumerStatefulWidget {
  const CopScreen({super.key});

  @override
  ConsumerState<CopScreen> createState() => _CopScreenState();
}

class _CopScreenState extends ConsumerState<CopScreen> {
  _CopPhase _phase = _CopPhase.idle;
  _StanceMode _stance = _StanceMode.bipedal;
  _EyeCondition _eyes = _EyeCondition.open;
  int _remainingS = _testDurationS;
  Timer? _timer;
  DateTime? _measurementStart;

  // Collected samples for current run
  final List<ProcessedSample> _samples = [];
  ProviderSubscription<LiveDataState>? _liveSub;

  // Last computed result (shown in PostTestPanel)
  CoPResult? _lastResult;

  @override
  void dispose() {
    _timer?.cancel();
    _liveSub?.close();
    super.dispose();
  }

  void _startMeasurement() {
    _samples.clear();
    _lastResult = null;
    _measurementStart = DateTime.now();
    _liveSub?.close();
    // Collect one ProcessedSample snapshot per liveDataProvider state update (~30 Hz)
    _liveSub = ref.listenManual<LiveDataState>(liveDataProvider, (_, next) {
      if (_phase != _CopPhase.measuring) return;
      if (next.currentForceN < 50) return; // skip near-zero (no one standing)
      final tS = DateTime.now()
              .difference(_measurementStart!)
              .inMilliseconds /
          1000.0;
      final fA = next.currentForceN * next.leftPct / 100.0;
      final fB = next.currentForceN * next.rightPct / 100.0;
      _samples.add(ProcessedSample(
        timestampS:      tS,
        // For 1-platform CoP: pass cell-level forces so cop_metrics can
        // compute both ML (forceAL vs forceAR) and AP (master vs slave) axes.
        forceAL:         next.currentForceALN,
        forceAR:         next.currentForceARN,
        forceBL:         0,
        forceBR:         0,
        forcePlatformA:  fA,
        forcePlatformB:  fB,
        forceTotal:      next.currentForceN,
        smoothedTotal:   next.currentSmoothedN,
        forceMasterSide: next.currentForceMasterN,
        forceSlaveSide:  next.currentForceSlaveN,
        rawSumA:         0,
        rawAML: next.currentRawAML,
        rawAMR: next.currentRawAMR,
        rawASL: next.currentRawASL,
        rawASR: next.currentRawASR,
        platformCount:   next.platformCount,
      ));
    });
    setState(() {
      _phase = _CopPhase.measuring;
      _remainingS = _testDurationS;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _remainingS--);
      if (_remainingS <= 0) {
        t.cancel();
        _finishMeasurement();
      }
    });
  }

  void _finishMeasurement() {
    _liveSub?.close();
    _liveSub = null;
    // Read platform separation from settings (cm → mm)
    final appSettings = ref.read(settingsProvider);
    final sepMm    = appSettings.platformSeparationCm * 10.0;
    final widthMm  = appSettings.platformWidthCm  * 10.0;
    final lengthMm = appSettings.platformLengthCm * 10.0;
    // Compute real CoP metrics from collected samples
    final result = CopMetrics.compute(
      samples:              _samples,
      durationS:            _testDurationS.toDouble(),
      condition:            _eyes == _EyeCondition.open ? 'OA' : 'OC',
      stance:               _stance.name,
      platformSeparationMm: sepMm,
      platformWidthMm:      widthMm,
      platformLengthMm:     lengthMm,
      useFftFrequency:      appSettings.useFftCopFreq,
    );
    setState(() {
      _lastResult = result;
      _phase = _CopPhase.done;
    });
  }

  void _cancel() {
    _liveSub?.close();
    _liveSub = null;
    _timer?.cancel();
    setState(() {
      _phase = _CopPhase.idle;
      _remainingS = _testDurationS;
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveDataProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('cop_title')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _cancel();
            if (context.mounted) context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: AppStrings.get('cop_see_tutorial'),
            onPressed: () => showTestTutorial(context, TestTutorials.cop),
          ),
        ],
      ),
      body: Column(
        children: [
          // Config panel (only visible when idle)
          if (_phase == _CopPhase.idle) _ConfigPanel(
            stance: _stance,
            eyes: _eyes,
            onStanceChanged: (s) => setState(() => _stance = s),
            onEyesChanged:   (e) => setState(() => _eyes = e),
          ),

          // Timer / status
          _TimerDisplay(
            phase: _phase,
            remainingS: _remainingS,
            totalS: _testDurationS,
          ),

          // Single-platform notice
          if (live.platformCount == 1)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(70)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 15, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Solo medición ML disponible (hardware 1D)',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // Force-time chart
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ForceTimeChart(
                timeS: live.timeS,
                forceTotalN: live.forceTotalN,
                forceLeftN: live.forceLeftN,
                forceRightN: live.forceRightN,
                bodyWeightN: null,
                showChannels: true,
              ),
            ),
          ),

          // Symmetry gauge (live) — only when not done
          if (_phase != _CopPhase.done)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SymmetryGauge(
                leftPercent: live.leftPct,
                leftLabel:   live.platformCount >= 2 ? 'IZQ' : 'IZQ',
                rightLabel:  live.platformCount >= 2 ? 'DER' : 'DER',
                isEstimated: live.platformCount == 1,
              ),
            ),

          // Bottom panel
          if (_phase == _CopPhase.done && _lastResult != null)
            PostTestPanel(
              result: _lastResult!,
              onViewResult: () =>
                  context.push('/results/new', extra: _lastResult),
              onRepeat: () => setState(() {
                _phase = _CopPhase.idle;
                _remainingS = _testDurationS;
                _lastResult = null;
              }),
            )
          else
            Container(
              color: context.col.surface,
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: _phase == _CopPhase.measuring
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Cancelar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: _cancel,
                      )
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.timer_outlined, size: 20),
                        label: Text(
                            _eyes == _EyeCondition.open
                                ? AppStrings.get('start_open_eyes')
                                : AppStrings.get('start_closed_eyes')),
                        onPressed: _startMeasurement,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _ConfigPanel extends StatelessWidget {
  final _StanceMode stance;
  final _EyeCondition eyes;
  final ValueChanged<_StanceMode> onStanceChanged;
  final ValueChanged<_EyeCondition> onEyesChanged;

  const _ConfigPanel({
    required this.stance,
    required this.eyes,
    required this.onStanceChanged,
    required this.onEyesChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.col.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.get('configuration'), style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.get('stance'), style: IXTextStyles.metricLabel),
                    const SizedBox(height: 6),
                    _SegmentedRow<_StanceMode>(
                      values: _StanceMode.values,
                      selected: stance,
                      label: (s) => s.label,
                      onChanged: onStanceChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.get('eyes'), style: IXTextStyles.metricLabel),
                    const SizedBox(height: 6),
                    _SegmentedRow<_EyeCondition>(
                      values: _EyeCondition.values,
                      selected: eyes,
                      label: (e) => e.label,
                      onChanged: onEyesChanged,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentedRow<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  const _SegmentedRow({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: values.map((v) {
        final isSelected = v == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withOpacity(0.2)
                    : context.col.background,
                border: Border.all(
                  color: isSelected ? AppColors.primary : context.col.border,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label(v),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.primary : context.col.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  final _CopPhase phase;
  final int remainingS;
  final int totalS;
  const _TimerDisplay({
    required this.phase,
    required this.remainingS,
    required this.totalS,
  });

  @override
  Widget build(BuildContext context) {
    if (phase == _CopPhase.idle) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('$totalS ${AppStrings.get('measurement_seconds')}',
            style: TextStyle(color: context.col.textSecondary, fontSize: 13)),
      );
    }

    final progress = remainingS / totalS;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text(
            '$remainingS s',
            style: IXTextStyles.metricValue(color: AppColors.primary)
                .copyWith(fontSize: 36),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: context.col.surface,
              color: progress > 0.3 ? AppColors.primary : AppColors.warning,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Enums ─────────────────────────────────────────────────────────────────────

enum _CopPhase { idle, measuring, done }

enum _StanceMode {
  bipedal,
  left,
  right;

  String get label {
    switch (this) {
      case _StanceMode.bipedal: return AppStrings.get('bipedal');
      case _StanceMode.left:    return AppStrings.get('left_foot');
      case _StanceMode.right:   return AppStrings.get('right_foot');
    }
  }
}

enum _EyeCondition {
  open,
  closed;

  String get label {
    switch (this) {
      case _EyeCondition.open:   return AppStrings.get('eyes_open');
      case _EyeCondition.closed: return AppStrings.get('eyes_closed');
    }
  }
}
