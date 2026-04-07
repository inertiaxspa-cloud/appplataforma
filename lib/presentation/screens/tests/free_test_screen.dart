import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/test_result.dart';
import '../../providers/test_state_provider.dart';
import '../../providers/live_data_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cards/metric_card.dart';
import '../../widgets/charts/force_time_chart.dart';
import '../../widgets/common/post_test_panel.dart';

class FreeTestScreen extends ConsumerStatefulWidget {
  const FreeTestScreen({super.key});

  @override
  ConsumerState<FreeTestScreen> createState() => _FreeTestScreenState();
}

class _FreeTestScreenState extends ConsumerState<FreeTestScreen> {
  final _labelCtrl = TextEditingController();
  int? _timerDuration; // null = free mode, else seconds
  bool _settling = false;

  static const _durations = [null, 5, 10, 15, 30, 60];

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _start() {
    ref.read(testStateProvider.notifier).startFreeTest(
      label: _labelCtrl.text.trim(),
      durationS: _timerDuration,
    );
    setState(() => _settling = true);
  }

  void _stop() {
    ref.read(testStateProvider.notifier).finishFreeTest();
  }

  void _cancel() {
    ref.read(testStateProvider.notifier).stopTest();
    setState(() => _settling = false);
  }

  @override
  Widget build(BuildContext context) {
    final test = ref.watch(testStateProvider);
    final live = ref.watch(liveDataProvider);
    final notifier = ref.read(testStateProvider.notifier);
    final col = context.col;

    final isCompleted = test.status == TestStatus.completed && test.result != null;
    final isRunning = test.status == TestStatus.running;
    final chartTimeS = isCompleted ? notifier.lastTimeRelS : live.timeS;
    final chartForce = isCompleted ? notifier.lastForceN : live.forceTotalN;
    final chartLeft = isCompleted ? notifier.lastForceAN : live.forceLeftN;
    final chartRight = isCompleted ? notifier.lastForceBN : live.forceRightN;

    final freeResult = test.result is FreeTestResult ? test.result as FreeTestResult : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('test_free'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _cancel();
            if (context.mounted) context.pop();
          },
        ),
      ),
      body: Column(
        children: [
          // ── Pre-test config (label + timer) ──────────────────────────────
          if (!test.isActive && !isCompleted && !_settling)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                      labelText: AppStrings.get('movement_label'),
                      hintText: AppStrings.get('movement_label_hint'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLength: 50,
                  ),
                  const SizedBox(height: 8),
                  Text(AppStrings.get('test_duration'), style: IXTextStyles.metricLabel),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: _durations.map((d) {
                      final isSelected = d == _timerDuration;
                      final label = d == null ? AppStrings.get('mode_free') : '${d}s';
                      return ChoiceChip(
                        label: Text(label, style: TextStyle(fontSize: 12,
                            color: isSelected ? Colors.white : col.textSecondary)),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        onSelected: (_) => setState(() => _timerDuration = d),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

          // ── Chart ────────────────────────────────────────────────────────
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ForceTimeChart(
                timeS: chartTimeS,
                forceTotalN: chartForce,
                forceLeftN: chartLeft,
                forceRightN: chartRight,
                bodyWeightN: test.bodyWeightN,
                showChannels: true,
              ),
            ),
          ),

          // ── Post-test panel ──────────────────────────────────────────────
          if (isCompleted && freeResult != null)
            Column(
              children: [
                // Metrics preview
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      if (freeResult.label.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(freeResult.label,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                  color: col.textPrimary)),
                        ),
                      Row(
                        children: [
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('peak_force'), value: freeResult.peakForceN.toStringAsFixed(0), unit: 'N')),
                          const SizedBox(width: 6),
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('mean_force'), value: freeResult.meanForceN.toStringAsFixed(0), unit: 'N')),
                          const SizedBox(width: 6),
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('duration_label'), value: freeResult.durationS.toStringAsFixed(1), unit: 's')),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('total_impulse'), value: freeResult.totalImpulseNs.toStringAsFixed(0), unit: 'N·s')),
                          const SizedBox(width: 6),
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('peak_rfd'), value: (freeResult.peakRfdNs / 1000).toStringAsFixed(1), unit: 'kN/s')),
                          const SizedBox(width: 6),
                          Expanded(child: CompactMetricTile(
                            label: AppStrings.get('symmetry_index'), value: '${(100 - freeResult.symmetry.asymmetryIndexPct).toStringAsFixed(0)}', unit: '%')),
                        ],
                      ),
                    ],
                  ),
                ),
                PostTestPanel(
                  result: freeResult,
                  onViewResult: () {
                    if (!context.mounted) return;
                    context.push('/results/new', extra: test.result);
                  },
                  onRepeat: () {
                    ref.read(testStateProvider.notifier).stopTest();
                    setState(() => _settling = false);
                  },
                ),
              ],
            )
          else if (test.status == TestStatus.failed)
            Container(
              color: col.surface,
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(test.error ?? AppStrings.get('test_failed'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: AppColors.danger)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(AppStrings.get('retry')),
                  onPressed: _cancel,
                ),
              ]),
            )
          else
            Container(
              color: col.surface,
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(test.statusMessage,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                        color: isRunning ? AppColors.success : col.textSecondary))
                    .animate().fadeIn(duration: 200.ms),
                if (isRunning) ...[
                  const SizedBox(height: 8),
                  Text('${AppStrings.get('peak_force')}: ${live.currentForceN.toStringAsFixed(0)} N',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: isRunning
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.stop, size: 20),
                          label: Text(AppStrings.get('finish')),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                          onPressed: _stop,
                        )
                      : test.isActive
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.close, size: 18),
                              label: Text(AppStrings.get('cancel')),
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger,
                                  side: const BorderSide(color: AppColors.danger)),
                              onPressed: _cancel,
                            )
                          : ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow, size: 20),
                              label: Text(AppStrings.get('start')),
                              onPressed: _start,
                            ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
