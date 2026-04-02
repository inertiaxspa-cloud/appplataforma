import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/dsp/phase_detector.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/test_state_provider.dart';
import '../../providers/live_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/post_test_panel.dart';
import '../../widgets/test_tutorial.dart';
import '../../../core/l10n/app_strings.dart';

class DjScreen extends ConsumerStatefulWidget {
  const DjScreen({super.key});

  @override
  ConsumerState<DjScreen> createState() => _DjScreenState();
}

class _DjScreenState extends ConsumerState<DjScreen> {
  bool _counting = false;
  int _countdownN = 3;
  Timer? _countdownTimer;
  double _selectedDropHeight = 0.30; // metres

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _counting = true;
      _countdownN = 3;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownN > 1) {
        setState(() => _countdownN--);
      } else {
        t.cancel();
        setState(() => _counting = false);
        ref.read(testStateProvider.notifier).startTest(TestType.dropJump);
      }
    });
  }

  void _cancel() {
    _countdownTimer?.cancel();
    setState(() {
      _counting = false;
      _countdownN = 3;
    });
    ref.read(testStateProvider.notifier).stopTest();
  }

  @override
  Widget build(BuildContext context) {
    final test     = ref.watch(testStateProvider);
    final live     = ref.watch(liveDataProvider);
    final notifier = ref.read(testStateProvider.notifier);

    final isCompleted = test.status == TestStatus.completed && test.result != null;
    final chartTimeS      = isCompleted ? notifier.lastTimeRelS : live.timeS;
    final chartForceTotal = isCompleted ? notifier.lastForceN   : live.forceTotalN;
    final chartForceLeft  = isCompleted ? notifier.lastForceAN  : live.forceLeftN;
    final chartForceRight = isCompleted ? notifier.lastForceBN  : live.forceRightN;

    final result = test.result;
    final djResult = result is DropJumpResult ? result : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('DJ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(AppStrings.get('dj_subtitle'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
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
            tooltip: AppStrings.get('dj_see_tutorial'),
            onPressed: () => showTestTutorial(context, TestTutorials.dj),
          ),
        ],
      ),
      body: Column(
        children: [
          // Height selector
          _HeightSelector(
            enabled: !test.isActive && !_counting,
            selected: _selectedDropHeight,
            onChanged: (h) => setState(() => _selectedDropHeight = h),
          ),

          // Phase indicator row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PhaseIndicatorRow(currentPhase: test.phase.name, testType: 'dropJump'),
          ),

          // Chart
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ForceTimeChart(
                timeS: chartTimeS,
                forceTotalN: chartForceTotal,
                forceLeftN: chartForceLeft,
                forceRightN: chartForceRight,
                bodyWeightN: test.bodyWeightN,
                showChannels: true,
              ),
            ),
          ),

          // Bottom panel: post-test or active
          if (isCompleted)
            PostTestPanel(
              result: test.result!,
              onViewResult: () =>
                  context.push('/results/new', extra: test.result),
              onRepeat: () {
                ref.read(testStateProvider.notifier).stopTest();
              },
            )
          else if (test.status == TestStatus.failed)
            Container(
              color: context.col.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                  const SizedBox(height: 12),
                  Text(
                    test.error ?? AppStrings.get('test_failed'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.danger),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(AppStrings.get('retry')),
                    onPressed: () => ref.read(testStateProvider.notifier).stopTest(),
                  ),
                ],
              ),
            )
          else if (_counting)
            _CountdownOverlay(
              countdownN: _countdownN,
              onCancel: _cancel,
            )
          else ...[
            // Live RSImod preview (once landed, before completed)
            if (djResult != null && !isCompleted)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: CompactMetricTile(
                        label: AppStrings.get('height_label_short'),
                        value: djResult.jumpHeightCm.toStringAsFixed(1),
                        unit: 'cm',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactMetricTile(
                        label: AppStrings.get('contact_label_short'),
                        value: djResult.contactTimeMs.toStringAsFixed(0),
                        unit: 'ms',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactMetricTile(
                        label: AppStrings.get('reactivity_rsi_label'),
                        value: djResult.rsiMod.toStringAsFixed(2),
                        unit: '',
                        subtitle: AppStrings.get('higher_value_better'),
                      ),
                    ),
                  ],
                ),
              ),

            Container(
              color: context.col.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    test.statusMessage,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: test.phase == JumpPhase.flight
                          ? AppColors.success
                          : context.col.textSecondary,
                    ),
                  ).animate().fadeIn(duration: 200.ms),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: test.isActive
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.stop, size: 18),
                            label: Text(AppStrings.get('cancel_test')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                            ),
                            onPressed: _cancel,
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: Text(AppStrings.get('start_dj')),
                            onPressed: _startCountdown,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ── Drop Height Selector ──────────────────────────────────────────────────────

class _HeightSelector extends StatelessWidget {
  final bool enabled;
  final double selected;
  final ValueChanged<double>? onChanged;
  const _HeightSelector({required this.enabled, required this.selected, this.onChanged});

  static const _heights = [0.20, 0.30, 0.40, 0.50, 0.60];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.get('drop_height'), style: IXTextStyles.metricLabel),
          const SizedBox(height: 8),
          Row(
            children: _heights.map((h) {
              final isSelected = (h - selected).abs() < 0.01;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                  onTap: enabled ? () => onChanged?.call(h) : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withOpacity(0.2)
                          : context.col.surface,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : context.col.border,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${(h * 100).toInt()} cm',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : context.col.textSecondary,
                      ),
                    ),
                  ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Countdown overlay ────────────────────────────────────────────────────────

class _CountdownOverlay extends StatelessWidget {
  final int countdownN;
  final VoidCallback onCancel;
  const _CountdownOverlay({required this.countdownN, required this.onCancel});

  Color get _color => countdownN > 0 ? AppColors.warning : AppColors.success;

  @override
  Widget build(BuildContext context) {
    final label = countdownN > 0 ? '$countdownN' : AppStrings.get('quiet');
    return Container(
      color: context.col.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Text(
            AppStrings.get('get_ready'),
            style: TextStyle(
              fontSize: 14,
              color: context.col.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: _color,
            ),
          ).animate(key: ValueKey(countdownN)).scale(
                begin: const Offset(1.4, 1.4),
                end: const Offset(1.0, 1.0),
                duration: 400.ms,
                curve: Curves.easeOut,
              ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: Text(AppStrings.get('cancel')),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.col.textSecondary,
                side: BorderSide(color: context.col.border),
              ),
              onPressed: onCancel,
            ),
          ),
        ],
      ),
    );
  }
}
