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
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/post_test_panel.dart';
import '../../widgets/test_tutorial.dart';
import '../../../core/l10n/app_strings.dart';

class CmjScreen extends ConsumerStatefulWidget {
  const CmjScreen({super.key});

  @override
  ConsumerState<CmjScreen> createState() => _CmjScreenState();
}

class _CmjScreenState extends ConsumerState<CmjScreen> {
  bool _counting = false;
  int _countdownN = 3;
  Timer? _countdownTimer;

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
        ref.read(testStateProvider.notifier).startTest(TestType.cmj);
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

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CMJ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(AppStrings.get('cmj_subtitle'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            if (test.isActive) {
              final confirm = await showDialog<bool>(context: context,
                builder: (_) => AlertDialog(
                  title: Text(AppStrings.get('cancel_test')),
                  content: Text(AppStrings.get('cancel_test_confirm')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: Text(AppStrings.get('back'))),
                    TextButton(onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        child: Text(AppStrings.get('cancel_test'))),
                  ],
                ));
              if (confirm != true) return;
            }
            _cancel();
            if (context.mounted) context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: AppStrings.get('cmj_see_tutorial'),
            onPressed: () => showTestTutorial(context, TestTutorials.cmj),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Phase indicator ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: PhaseIndicatorRow(currentPhase: test.phase.name),
          ),

          // ── Force-time chart ─────────────────────────────────────────────
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

          // ── Bottom panel: post-test or active ────────────────────────────
          if (isCompleted)
            PostTestPanel(
              result: test.result!,
              onViewResult: () {
                if (!context.mounted) return;
                context.push('/results/new', extra: test.result);
              },
              onRepeat: () {
                ref.read(testStateProvider.notifier).stopTest();
                setState(() => _countdownN = 3);
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
          else
            Container(
              color: context.col.surface,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _StatusMessage(
                    message: test.statusMessage,
                    phase: test.phase,
                  ).animate().fadeIn(duration: 200.ms),

                  const SizedBox(height: 20),

                  if (test.bodyWeightN != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(AppStrings.get('measured_weight'), style: IXTextStyles.metricLabel),
                        const SizedBox(width: 12),
                        Text(
                          '${(test.bodyWeightN! / 9.81).toStringAsFixed(1)} kg',
                          style: IXTextStyles.metricValue(color: AppColors.success)
                              .copyWith(fontSize: 20),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],

                  SizedBox(
                    width: double.infinity,
                    child: test.isActive
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.stop, size: 18),
                            label: Text(AppStrings.get('cancel_test')),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger)),
                            onPressed: _cancel,
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: Text(AppStrings.get('start_cmj')),
                            onPressed: _startCountdown,
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  final String message;
  final JumpPhase phase;
  const _StatusMessage({required this.message, required this.phase});

  Color get _color {
    switch (phase) {
      case JumpPhase.flight:  return AppColors.success;
      case JumpPhase.landed:  return AppColors.warning;
      case JumpPhase.descent: return AppColors.info;
      default:                return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (phase == JumpPhase.flight)
          const Icon(Icons.arrow_upward, color: AppColors.success, size: 18),
        const SizedBox(width: 6),
        Text(
          message,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _color,
          ),
        ),
      ],
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
