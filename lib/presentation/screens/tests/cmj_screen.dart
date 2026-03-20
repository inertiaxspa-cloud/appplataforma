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

class CmjScreen extends ConsumerWidget {
  const CmjScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final test     = ref.watch(testStateProvider);
    final live     = ref.watch(liveDataProvider);
    final notifier = ref.read(testStateProvider.notifier);

    final isCompleted = test.status == TestStatus.completed && test.result != null;

    // Post-completion: show recorded full trace; otherwise show live rolling buffer
    final chartTimeS      = isCompleted ? notifier.lastTimeRelS : live.timeS;
    final chartForceTotal = isCompleted ? notifier.lastForceN   : live.forceTotalN;
    final chartForceLeft  = isCompleted ? notifier.lastForceAN  : live.forceLeftN;
    final chartForceRight = isCompleted ? notifier.lastForceBN  : live.forceRightN;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CMJ — Counter Movement Jump'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(testStateProvider.notifier).stopTest();
            context.pop();
          },
        ),
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
              onViewResult: () =>
                  context.push('/results/new', extra: test.result),
              onRepeat: () =>
                  ref.read(testStateProvider.notifier).stopTest(),
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
                        Text('PESO MEDIDO', style: IXTextStyles.metricLabel),
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
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger)),
                            onPressed: () =>
                                ref.read(testStateProvider.notifier).stopTest(),
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Iniciar CMJ'),
                            onPressed: () => ref
                                .read(testStateProvider.notifier)
                                .startTest(TestType.cmj),
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
