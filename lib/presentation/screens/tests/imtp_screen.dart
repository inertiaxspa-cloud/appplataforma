import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/live_data_provider.dart';
import '../../providers/test_state_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/post_test_panel.dart';
import '../../widgets/test_tutorial.dart';

// Pull duration limit
const _maxPullS = 6;

class ImtpScreen extends ConsumerStatefulWidget {
  const ImtpScreen({super.key});

  @override
  ConsumerState<ImtpScreen> createState() => _ImtpScreenState();
}

class _ImtpScreenState extends ConsumerState<ImtpScreen> {
  _ImtpPhase _phase = _ImtpPhase.idle;
  int _countdownN = 3;
  int _elapsedS = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _phase = _ImtpPhase.countdown;
      _countdownN = 3;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdownN > 1) {
        setState(() => _countdownN--);
      } else {
        t.cancel();
        _startPull();
      }
    });
  }

  void _startPull() {
    _elapsedS = 0;
    setState(() => _phase = _ImtpPhase.pulling);
    ref.read(testStateProvider.notifier).startTest(TestType.imtp);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _elapsedS++);
      if (_elapsedS >= _maxPullS) {
        t.cancel();
        _finishPull();
      }
    });
  }

  void _finishPull() {
    _timer?.cancel();
    // finishTest() computes IMTP metrics and emits TestStatus.completed
    ref.read(testStateProvider.notifier).finishTest();
    setState(() => _phase = _ImtpPhase.done);
  }

  void _cancel() {
    _timer?.cancel();
    ref.read(testStateProvider.notifier).stopTest();
    setState(() {
      _phase = _ImtpPhase.idle;
      _countdownN = 3;
      _elapsedS = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveDataProvider);
    final test = ref.watch(testStateProvider);

    final notifier = ref.read(testStateProvider.notifier);
    final isCompleted = _phase == _ImtpPhase.done && test.result != null;
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
            const Text('IMTP', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(AppStrings.get('imtp_subtitle'),
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
            tooltip: AppStrings.get('imtp_see_tutorial'),
            onPressed: () => showTestTutorial(context, TestTutorials.imtp),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          if (_phase == _ImtpPhase.idle) _Instructions(),

          // Countdown overlay
          if (_phase == _ImtpPhase.countdown)
            _CountdownDisplay(n: _countdownN),

          // Pull timer bar
          if (_phase == _ImtpPhase.pulling)
            _PullProgressBar(elapsedS: _elapsedS, maxS: _maxPullS),

          // Chart — always shown; recorded trace after completion
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(8),
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

          // Live peak force during pull
          if (_phase == _ImtpPhase.pulling)
            _LivePeakForce(forceN: live.currentForceN),

          // Bottom: post-test panel or action button
          if (isCompleted)
            PostTestPanel(
              result: test.result!,
              onViewResult: () =>
                  context.push('/results/new', extra: test.result),
              onRepeat: () {
                ref.read(testStateProvider.notifier).stopTest();
                setState(() {
                  _phase = _ImtpPhase.idle;
                  _countdownN = 3;
                  _elapsedS = 0;
                });
              },
            )
          else
            Container(
              color: context.col.surface,
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: _actionButton(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionButton() {
    switch (_phase) {
      case _ImtpPhase.idle:
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow, size: 20),
          label: Text(AppStrings.get('start_test')),
          onPressed: _startCountdown,
        );
      case _ImtpPhase.countdown:
        return OutlinedButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: Text(AppStrings.get('cancel')),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.col.textSecondary,
            side: BorderSide(color: context.col.border),
          ),
          onPressed: _cancel,
        );
      case _ImtpPhase.pulling:
        return OutlinedButton.icon(
          icon: const Icon(Icons.stop, size: 18),
          label: Text(AppStrings.get('finish_now')),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.warning,
            side: const BorderSide(color: AppColors.warning),
          ),
          onPressed: _finishPull,
        );
      case _ImtpPhase.done:
        // Handled by PostTestPanel above
        return const SizedBox.shrink();
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Instructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final steps = [
      AppStrings.get('imtp_step1'),
      AppStrings.get('imtp_step2'),
      AppStrings.get('imtp_step3'),
      AppStrings.get('imtp_step4'),
    ];
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
          Text(AppStrings.get('imtp_instructions'), style: IXTextStyles.sectionHeader()),
          const SizedBox(height: 10),
          ...steps.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s,
                    style: TextStyle(
                        color: context.col.textSecondary, fontSize: 13)),
              )),
        ],
      ),
    );
  }
}

class _CountdownDisplay extends StatelessWidget {
  final int n;
  const _CountdownDisplay({required this.n});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        '$n',
        style: IXTextStyles.metricValue(color: AppColors.warning)
            .copyWith(fontSize: 80),
      ).animate(key: ValueKey(n)).scale(
            begin: const Offset(1.4, 1.4),
            end: const Offset(1.0, 1.0),
            duration: 400.ms,
            curve: Curves.easeOut,
          ),
    );
  }
}

class _PullProgressBar extends StatelessWidget {
  final int elapsedS;
  final int maxS;
  const _PullProgressBar({required this.elapsedS, required this.maxS});

  @override
  Widget build(BuildContext context) {
    final progress = elapsedS / maxS;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Text(
            '${AppStrings.get('pull_action')} ${maxS - elapsedS} s',
            style: IXTextStyles.metricValue(color: AppColors.danger)
                .copyWith(fontSize: 24),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: context.col.surface,
              color: AppColors.danger,
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePeakForce extends StatelessWidget {
  final double forceN;
  const _LivePeakForce({required this.forceN});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppStrings.get('applied_force'), style: IXTextStyles.metricLabel),
          const SizedBox(width: 12),
          Text(
            '${forceN.toStringAsFixed(0)} N',
            style: IXTextStyles.metricValue(color: AppColors.danger)
                .copyWith(fontSize: 28),
          ),
        ],
      ),
    );
  }
}

enum _ImtpPhase { idle, countdown, pulling, done }
