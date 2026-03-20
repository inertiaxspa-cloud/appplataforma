import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/test_state_provider.dart';
import '../../providers/live_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/status_badge.dart';
import '../../widgets/common/post_test_panel.dart';
import '../../widgets/test_tutorial.dart';

class MultiJumpScreen extends ConsumerWidget {
  const MultiJumpScreen({super.key});

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
    final mjResult = result is MultiJumpResult ? result : null;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Saltos Repetidos',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('Multi-salto con RSI',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(testStateProvider.notifier).stopTest();
            context.pop();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Ver tutorial Saltos Repetidos',
            onPressed: () => showTestTutorial(context, TestTutorials.multiJump),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instruction
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: Text(
              'Salta lo más fuerte y rápido posible, minimizando el tiempo '
              'en el suelo. El sistema detecta cada salto automáticamente.',
              style: TextStyle(color: AppColors.info, fontSize: 13),
            ),
          ),

          // Phase indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: PhaseIndicatorRow(currentPhase: test.phase.name),
          ),

          // Chart
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

          // Jump table (live updates)
          if (mjResult != null && mjResult.jumps.isNotEmpty)
            SizedBox(
              height: 140,
              child: _JumpTable(jumps: mjResult.jumps),
            ),

          // Summary row when active
          if (test.isActive && mjResult == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _LiveBadge(label: 'SALTOS', value: '0'),
                  _LiveBadge(label: 'ALTURA MEDIA', value: '-- cm'),
                  _LiveBadge(label: 'REACTIVIDAD PROM. (RSI)', value: '--'),
                ],
              ),
            ),

          // Status + buttons (or post-test panel)
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
                  Text(
                    test.statusMessage,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.col.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: test.isActive
                            ? OutlinedButton.icon(
                                icon: const Icon(Icons.stop, size: 18),
                                label: const Text('Terminar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.warning,
                                  side: const BorderSide(
                                      color: AppColors.warning),
                                ),
                                onPressed: () => ref
                                    .read(testStateProvider.notifier)
                                    .finishTest(),
                              )
                            : ElevatedButton.icon(
                                icon: const Icon(Icons.play_arrow, size: 20),
                                label: const Text('Iniciar'),
                                onPressed: () => ref
                                    .read(testStateProvider.notifier)
                                    .startTest(TestType.multiJump),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Live jump table ───────────────────────────────────────────────────────────

class _JumpTable extends StatelessWidget {
  final List<SingleJumpData> jumps;
  const _JumpTable({required this.jumps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.col.surface,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _TH('N°', flex: 1),
                _TH('Altura', flex: 2),
                _TH('T. Contacto', flex: 2),
                _TH('RSI', flex: 2),
              ],
            ),
          ),
          Divider(height: 1, color: context.col.border),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: jumps.length,
              itemBuilder: (_, i) {
                final j = jumps[i];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _TD(j.jumpNumber.toString(), flex: 1),
                      _TD('${j.heightCm.toStringAsFixed(1)} cm', flex: 2,
                          color: AppColors.forceTotal),
                      _TD('${j.contactTimeMs.toStringAsFixed(0)} ms', flex: 2),
                      _TD(j.rsiMod.toStringAsFixed(2), flex: 2,
                          color: AppColors.primary),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  final int flex;
  const _TH(this.text, {required this.flex});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: IXTextStyles.metricLabel.copyWith(fontSize: 10),
      textAlign: TextAlign.center),
  );
}

class _TD extends StatelessWidget {
  final String text;
  final int flex;
  final Color? color;
  const _TD(this.text, {required this.flex, this.color});
  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(text,
      style: GoogleFonts.robotoMono(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? context.col.textPrimary,
      ),
      textAlign: TextAlign.center),
  );
}

class _LiveBadge extends StatelessWidget {
  final String label;
  final String value;
  const _LiveBadge({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: IXTextStyles.metricLabel.copyWith(fontSize: 10)),
      const SizedBox(height: 2),
      Text(value, style: IXTextStyles.metricValue(color: AppColors.primary)
          .copyWith(fontSize: 16)),
    ],
  );
}
