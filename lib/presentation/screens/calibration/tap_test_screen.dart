import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../domain/entities/cell_mapping.dart';
import '../../providers/live_data_provider.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart';

// ── State machine ────────────────────────────────────────────────────────────

enum _TapPhase { idle, baseline, waitingForTap, detecting, result, complete }

class TapTestScreen extends ConsumerStatefulWidget {
  /// 'A' or 'B' — which platform to identify.
  final String platform;
  const TapTestScreen({super.key, this.platform = 'A'});

  @override
  ConsumerState<TapTestScreen> createState() => _TapTestScreenState();
}

class _TapTestScreenState extends ConsumerState<TapTestScreen> {
  _TapPhase _phase = _TapPhase.idle;
  bool _manualMode = false;

  // Corners to identify, in order
  static const _corners = [
    CornerPosition.frontLeft,
    CornerPosition.frontRight,
    CornerPosition.rearLeft,
    CornerPosition.rearRight,
  ];
  int _currentCornerIdx = 0;

  // Results: channel → corner
  final Map<String, CornerPosition> _results = {};

  // ADC monitoring
  final Map<String, List<double>> _baselineADC = {};
  final Map<String, double> _peakADC = {};
  Timer? _phaseTimer;
  ProviderSubscription<LiveDataState>? _liveSub;

  // Manual mode selections
  final Map<CornerPosition, String?> _manualSelections = {
    CornerPosition.frontLeft: null,
    CornerPosition.frontRight: null,
    CornerPosition.rearLeft: null,
    CornerPosition.rearRight: null,
  };

  List<String> get _channelKeys => widget.platform == 'B'
      ? ['B_ML', 'B_MR', 'B_SL', 'B_SR']
      : ['A_ML', 'A_MR', 'A_SL', 'A_SR'];

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _liveSub?.close();
    super.dispose();
  }

  String _cornerName(CornerPosition c) => switch (c) {
    CornerPosition.frontLeft  => AppStrings.get('front_left'),
    CornerPosition.frontRight => AppStrings.get('front_right'),
    CornerPosition.rearLeft   => AppStrings.get('rear_left'),
    CornerPosition.rearRight  => AppStrings.get('rear_right'),
  };

  double _readChannel(LiveDataState s, String ch) {
    if (widget.platform == 'B') {
      return switch (ch) {
        'B_ML' => s.currentRawBML,
        'B_MR' => s.currentRawBMR,
        'B_SL' => s.currentRawBSL,
        'B_SR' => s.currentRawBSR,
        _ => 0,
      };
    }
    return switch (ch) {
      'A_ML' => s.currentRawAML,
      'A_MR' => s.currentRawAMR,
      'A_SL' => s.currentRawASL,
      'A_SR' => s.currentRawASR,
      _ => 0,
    };
  }

  // ── Tap test flow ──────────────────────────────────────────────────────────

  void _startTest() {
    setState(() {
      _phase = _TapPhase.baseline;
      _currentCornerIdx = 0;
      _results.clear();
    });
    _recordBaseline();
  }

  void _recordBaseline() {
    // Collect ADC readings for 1 second to establish baseline
    _baselineADC.clear();
    for (final ch in _channelKeys) {
      _baselineADC[ch] = [];
    }

    _liveSub?.close();
    _liveSub = ref.listenManual<LiveDataState>(liveDataProvider, (_, next) {
      if (_phase != _TapPhase.baseline) return;
      for (final ch in _channelKeys) {
        _baselineADC[ch]!.add(_readChannel(next, ch).abs());
      }
    });

    _phaseTimer?.cancel();
    _phaseTimer = Timer(const Duration(seconds: 1), () {
      // Compute baseline means
      final means = <String, double>{};
      for (final ch in _channelKeys) {
        final vals = _baselineADC[ch]!;
        means[ch] = vals.isEmpty ? 0 : vals.reduce((a, b) => a + b) / vals.length;
      }
      _baselineADC.clear();
      for (final ch in _channelKeys) {
        _baselineADC[ch] = [means[ch]!]; // store baseline mean as single entry
      }
      setState(() => _phase = _TapPhase.waitingForTap);
      _startDetection();
    });
  }

  void _startDetection() {
    _peakADC.clear();
    for (final ch in _channelKeys) {
      _peakADC[ch] = 0;
    }

    _liveSub?.close();
    _liveSub = ref.listenManual<LiveDataState>(liveDataProvider, (_, next) {
      if (_phase != _TapPhase.waitingForTap && _phase != _TapPhase.detecting) return;
      bool anySpike = false;
      for (final ch in _channelKeys) {
        final val = _readChannel(next, ch).abs();
        final baseline = _baselineADC[ch]?.first ?? 0;
        final delta = (val - baseline).abs();
        if (delta > (_peakADC[ch] ?? 0)) {
          _peakADC[ch] = delta;
        }
        if (delta > 300) anySpike = true;
      }
      if (anySpike && _phase == _TapPhase.waitingForTap) {
        setState(() => _phase = _TapPhase.detecting);
      }
    });

    // Timeout: 5 seconds to tap
    _phaseTimer?.cancel();
    _phaseTimer = Timer(const Duration(seconds: 5), () {
      _evaluateTap();
    });
  }

  void _evaluateTap() {
    _liveSub?.close();
    _liveSub = null;

    // Find channel with highest delta
    String? bestChannel;
    double bestDelta = 0;
    double secondDelta = 0;
    for (final ch in _channelKeys) {
      final d = _peakADC[ch] ?? 0;
      if (d > bestDelta) {
        secondDelta = bestDelta;
        bestDelta = d;
        bestChannel = ch;
      } else if (d > secondDelta) {
        secondDelta = d;
      }
    }

    // Validation: delta > 500 AND > 2× second highest
    // Also: channel not already assigned to another corner
    final alreadyUsed = _results.keys.toSet();
    if (bestChannel != null &&
        bestDelta > 500 &&
        (secondDelta == 0 || bestDelta > secondDelta * 1.5) &&
        !alreadyUsed.contains(bestChannel)) {
      _results[bestChannel] = _corners[_currentCornerIdx];
      setState(() => _phase = _TapPhase.result);
    } else {
      // Detection failed
      setState(() => _phase = _TapPhase.waitingForTap);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.get('tap_harder'))),
        );
      }
      // Allow retry
      _startDetection();
    }
  }

  void _nextCorner() {
    if (_currentCornerIdx + 1 >= _corners.length) {
      setState(() => _phase = _TapPhase.complete);
    } else {
      _currentCornerIdx++;
      setState(() => _phase = _TapPhase.baseline);
      _recordBaseline();
    }
  }

  void _saveMapping() {
    final mapping = CellMapping(
      platform: widget.platform,
      channelToCorner: Map.from(_results),
    );
    if (!mapping.isValid) return;

    final notifier = ref.read(settingsProvider.notifier);
    if (widget.platform == 'B') {
      notifier.update((s) => s.copyWith(cellMappingB: mapping));
    } else {
      notifier.update((s) => s.copyWith(cellMappingA: mapping));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.get('tap_test_saved'))),
    );
    if (context.mounted) context.pop();
  }

  void _saveManual() {
    // Build mapping from manual selections
    final map = <String, CornerPosition>{};
    for (final entry in _manualSelections.entries) {
      if (entry.value == null) return; // incomplete
      map[entry.value!] = entry.key;
    }
    // Validate uniqueness
    if (map.keys.toSet().length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Each channel must be assigned to a unique corner')),
      );
      return;
    }

    final mapping = CellMapping(platform: widget.platform, channelToCorner: map);
    final notifier = ref.read(settingsProvider.notifier);
    if (widget.platform == 'B') {
      notifier.update((s) => s.copyWith(cellMappingB: mapping));
    } else {
      notifier.update((s) => s.copyWith(cellMappingA: mapping));
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppStrings.get('tap_test_saved'))),
    );
    if (context.mounted) context.pop();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final col = context.col;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.get('tap_test_title')),
        actions: [
          TextButton.icon(
            icon: Icon(_manualMode ? Icons.touch_app : Icons.edit, size: 16),
            label: Text(_manualMode
                ? AppStrings.get('tap_corner')
                : AppStrings.get('manual_assignment'),
                style: const TextStyle(fontSize: 12)),
            onPressed: () => setState(() {
              _manualMode = !_manualMode;
              _phase = _TapPhase.idle;
              _phaseTimer?.cancel();
              _liveSub?.close();
            }),
          ),
        ],
      ),
      body: _manualMode ? _buildManualMode(col) : _buildTapMode(col),
    );
  }

  Widget _buildTapMode(dynamic col) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Platform diagram
          Expanded(child: _PlatformDiagram(
            currentCorner: _phase == _TapPhase.idle || _phase == _TapPhase.complete
                ? null : _corners[_currentCornerIdx],
            results: _results,
            cornerName: _cornerName,
          )),

          const SizedBox(height: 16),

          // Status text
          Text(
            switch (_phase) {
              _TapPhase.idle     => AppStrings.get('tap_test_start'),
              _TapPhase.baseline => AppStrings.get('recording_baseline'),
              _TapPhase.waitingForTap => '${AppStrings.get('tap_corner')}: ${_cornerName(_corners[_currentCornerIdx])}',
              _TapPhase.detecting => AppStrings.get('detecting_tap'),
              _TapPhase.result   => '${AppStrings.get('cell_detected')}: ${_results.entries.last.key}',
              _TapPhase.complete => AppStrings.get('tap_test_complete'),
            },
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _phase == _TapPhase.complete ? AppColors.success : col.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Progress indicator
          if (_phase != _TapPhase.idle && _phase != _TapPhase.complete)
            LinearProgressIndicator(
              value: (_currentCornerIdx + (_phase == _TapPhase.result ? 1 : 0.5)) / 4,
              backgroundColor: col.border,
              color: AppColors.primary,
            ),

          const SizedBox(height: 16),

          // Action button
          SizedBox(
            width: double.infinity,
            child: switch (_phase) {
              _TapPhase.idle => ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(AppStrings.get('start')),
                onPressed: _startTest,
              ),
              _TapPhase.result => ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(_currentCornerIdx + 1 >= _corners.length
                    ? AppStrings.get('finish')
                    : AppStrings.get('tap_corner')),
                onPressed: _nextCorner,
              ),
              _TapPhase.complete => ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(AppStrings.get('save')),
                onPressed: _saveMapping,
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildManualMode(dynamic col) {
    final usedChannels = _manualSelections.values.whereType<String>().toSet();
    final allAssigned = _manualSelections.values.every((v) => v != null) &&
        usedChannels.length == 4;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ..._corners.map((corner) {
            final available = _channelKeys.where((ch) =>
                !usedChannels.contains(ch) || _manualSelections[corner] == ch).toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(_cornerName(corner),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                            color: col.textPrimary)),
                  ),
                  const Icon(Icons.arrow_forward, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _manualSelections[corner],
                      hint: Text(AppStrings.get('select_channel')),
                      items: available.map((ch) => DropdownMenuItem(
                        value: ch,
                        child: Text(ch, style: const TextStyle(fontSize: 14)),
                      )).toList(),
                      onChanged: (v) => setState(() => _manualSelections[corner] = v),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(AppStrings.get('save')),
              onPressed: allAssigned ? _saveManual : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Platform Diagram ─────────────────────────────────────────────────────────

class _PlatformDiagram extends StatelessWidget {
  final CornerPosition? currentCorner;
  final Map<String, CornerPosition> results;
  final String Function(CornerPosition) cornerName;

  const _PlatformDiagram({
    this.currentCorner,
    required this.results,
    required this.cornerName,
  });

  @override
  Widget build(BuildContext context) {
    final col = context.col;
    final assignedCorners = results.values.toSet();

    Widget cornerWidget(CornerPosition pos, Alignment align) {
      final isCurrent = pos == currentCorner;
      final isDone = assignedCorners.contains(pos);
      final channel = results.entries
          .where((e) => e.value == pos)
          .map((e) => e.key)
          .firstOrNull;

      return Align(
        alignment: align,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 90,
          height: 60,
          decoration: BoxDecoration(
            color: isDone
                ? AppColors.successDim
                : isCurrent
                    ? AppColors.primary.withOpacity(0.15)
                    : col.surface,
            border: Border.all(
              color: isDone
                  ? AppColors.success
                  : isCurrent
                      ? AppColors.primary
                      : col.border,
              width: isCurrent ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cornerName(pos).split('-').last.trim(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDone ? AppColors.success : col.textSecondary,
                ),
              ),
              if (isDone && channel != null)
                Text(channel,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.success)),
              if (isCurrent && !isDone)
                const Icon(Icons.touch_app, size: 18, color: AppColors.primary),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: col.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: col.border),
      ),
      child: Stack(
        children: [
          // Platform outline
          Center(
            child: Container(
              width: 200,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: col.textDisabled, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('PLATFORM ${currentCorner != null ? "" : ""}',
                    style: TextStyle(fontSize: 10, color: col.textDisabled)),
              ),
            ),
          ),
          // 4 corners
          Positioned(top: 0, left: 0, child: cornerWidget(CornerPosition.frontLeft, Alignment.topLeft)),
          Positioned(top: 0, right: 0, child: cornerWidget(CornerPosition.frontRight, Alignment.topRight)),
          Positioned(bottom: 0, left: 0, child: cornerWidget(CornerPosition.rearLeft, Alignment.bottomLeft)),
          Positioned(bottom: 0, right: 0, child: cornerWidget(CornerPosition.rearRight, Alignment.bottomRight)),
          // Subject direction arrow
          Positioned(
            top: 4,
            left: 0, right: 0,
            child: Center(
              child: Text('FRENTE ↑',
                  style: TextStyle(fontSize: 9, color: col.textDisabled,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
