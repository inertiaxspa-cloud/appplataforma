import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../../../core/l10n/app_strings.dart';

class MultiJumpScreen extends ConsumerStatefulWidget {
  const MultiJumpScreen({super.key});

  @override
  ConsumerState<MultiJumpScreen> createState() => _MultiJumpScreenState();
}

class _MultiJumpScreenState extends ConsumerState<MultiJumpScreen> {
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
        ref.read(testStateProvider.notifier).startTest(TestType.multiJump);
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
    final mjResult = result is MultiJumpResult ? result : null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.get('multijump_title'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(AppStrings.get('multijump_subtitle'),
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
            tooltip: AppStrings.get('multijump_see_tutorial'),
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
              AppStrings.get('multijump_instruction'),
              style: const TextStyle(color: AppColors.info, fontSize: 13),
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
                  _LiveBadge(label: AppStrings.get('jump_count_label'), value: '0'),
                  _LiveBadge(label: AppStrings.get('avg_height_label'), value: '-- cm'),
                  _LiveBadge(label: AppStrings.get('avg_rsi_label'), value: '--'),
                ],
              ),
            ),

          // Status + buttons (or post-test panel)
          if (isCompleted)
            PostTestPanel(
              result: test.result!,
              onViewResult: () =>
                  context.push('/results/new', extra: test.result),
              onRepeat: () {
                ref.read(testStateProvider.notifier).stopTest();
              },
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
                                label: Text(AppStrings.get('finish_multijump')),
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
                                label: Text(AppStrings.get('start_multijump')),
                                onPressed: _startCountdown,
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
                _TH(AppStrings.get('table_header_n'), flex: 1),
                _TH(AppStrings.get('table_header_height'), flex: 2),
                _TH(AppStrings.get('table_header_contact'), flex: 2),
                _TH(AppStrings.get('table_header_rsi'), flex: 2),
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
