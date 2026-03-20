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

class DjScreen extends ConsumerWidget {
  const DjScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        title: const Text('Drop Jump'),
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
          // Height selector
          _HeightSelector(
            enabled: !test.isActive,
            selected: _dropHeightFromState(test),
          ),

          // Phase indicator row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: PhaseIndicatorRow(currentPhase: test.phase.name),
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
              onRepeat: () =>
                  ref.read(testStateProvider.notifier).stopTest(),
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
                        label: 'Altura',
                        value: djResult.jumpHeightCm.toStringAsFixed(1),
                        unit: 'cm',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactMetricTile(
                        label: 'Contacto',
                        value: djResult.contactTimeMs.toStringAsFixed(0),
                        unit: 'ms',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CompactMetricTile(
                        label: 'RSImod',
                        value: djResult.rsiMod.toStringAsFixed(2),
                        unit: '',
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
                            label: const Text('Cancelar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                            ),
                            onPressed: () =>
                                ref.read(testStateProvider.notifier).stopTest(),
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Iniciar Drop Jump'),
                            onPressed: () => ref
                                .read(testStateProvider.notifier)
                                .startTest(TestType.dropJump),
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

  double _dropHeightFromState(TestState test) => 0.30; // 30cm default
}

// ── Drop Height Selector ──────────────────────────────────────────────────────

class _HeightSelector extends StatelessWidget {
  final bool enabled;
  final double selected;
  const _HeightSelector({required this.enabled, required this.selected});

  static const _heights = [0.20, 0.30, 0.40, 0.50, 0.60];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ALTURA DE CAÍDA', style: IXTextStyles.metricLabel),
          const SizedBox(height: 8),
          Row(
            children: _heights.map((h) {
              final isSelected = (h - selected).abs() < 0.01;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
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
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
