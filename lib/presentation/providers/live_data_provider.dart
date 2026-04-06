import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/physics_constants.dart';
import '../../data/models/raw_sample.dart';
import '../../domain/dsp/signal_processor.dart';
import 'connection_provider.dart';
import 'calibration_provider.dart';
import '../../domain/entities/calibration_data.dart';

// ── Live data state ────────────────────────────────────────────────────────

class LiveDataState {
  final List<double> timeS;
  final List<double> forceTotalN;
  final List<double> forceLeftN;
  final List<double> forceRightN;
  final double currentForceN;
  final double currentSmoothedN;
  /// Raw pre-calibration ADC sum (platform A). Use this in the calibration wizard.
  final double currentRawSum;
  final int platformCount;
  final double leftPct;
  final double rightPct;
  final int samplesReceived;

  // ── Cell-level forces (single platform CoP) ───────────────────────────────
  /// ML-left column: master_L + slave_L (single platform only).
  final double currentForceALN;
  /// ML-right column: master_R + slave_R (single platform only).
  final double currentForceARN;
  /// AP-front row: master board side (master_L + master_R).
  final double currentForceMasterN;
  /// AP-back row: slave board side (slave_L + slave_R).
  final double currentForceSlaveN;

  // ── Per-cell raw ADC (negated, NOT offset-corrected) — for calibration ─────
  final double currentRawAML;   // -adcMasterL  Platform A
  final double currentRawAMR;   // -adcMasterR  Platform A
  final double currentRawASL;   // -adcSlaveL   Platform A  (0 if timeout)
  final double currentRawASR;   // -adcSlaveR   Platform A  (0 if timeout)

  // ── Per-cell raw ADC for Platform B ─────────────────────────────────────
  final double currentRawBML;   // -adcMasterL  Platform B  (0 if no B)
  final double currentRawBMR;   // -adcMasterR  Platform B  (0 if no B)
  final double currentRawBSL;   // -adcSlaveL   Platform B  (0 if no B or timeout)
  final double currentRawBSR;   // -adcSlaveR   Platform B  (0 if no B or timeout)

  const LiveDataState({
    this.timeS            = const [],
    this.forceTotalN      = const [],
    this.forceLeftN       = const [],
    this.forceRightN      = const [],
    this.currentForceN    = 0,
    this.currentSmoothedN = 0,
    this.currentRawSum    = 0,
    this.platformCount    = 1,
    this.leftPct          = 50,
    this.rightPct         = 50,
    this.samplesReceived  = 0,
    this.currentForceALN  = 0,
    this.currentForceARN  = 0,
    this.currentForceMasterN = 0,
    this.currentForceSlaveN  = 0,
    this.currentRawAML    = 0,
    this.currentRawAMR    = 0,
    this.currentRawASL    = 0,
    this.currentRawASR    = 0,
    this.currentRawBML    = 0,
    this.currentRawBMR    = 0,
    this.currentRawBSL    = 0,
    this.currentRawBSR    = 0,
  });
}

// ── Live data notifier ─────────────────────────────────────────────────────

class LiveDataNotifier extends StateNotifier<LiveDataState> {
  static const int _bufferSize = PhysicsConstants.chartBufferSize; // 5000
  // Chart update interval: publish new chart data every N samples.
  // 50 samples @ 1000 Hz = 50 ms ≈ 20 fps — smooth on mobile, low CPU.
  static const int _chartUpdateEvery = 50;

  // ListQueue gives O(1) addLast + removeFirst — avoids the O(n) shift
  // that List.removeAt(0) causes at 1000 samples/second.
  final ListQueue<double> _t      = ListQueue(_bufferSize + 1);
  final ListQueue<double> _fTotal = ListQueue(_bufferSize + 1);
  final ListQueue<double> _fLeft  = ListQueue(_bufferSize + 1);
  final ListQueue<double> _fRight = ListQueue(_bufferSize + 1);
  double _t0 = 0;
  bool _disposed = false;

  final SignalProcessor _processor;

  LiveDataNotifier(this._processor) : super(const LiveDataState());

  void onRawSample(RawSample raw) {
    if (_disposed) return;
    final processed = _processor.process(raw);
    if (processed == null) return;

    final tAbs = processed.timestampS;
    if (_t0 == 0) _t0 = tAbs;
    final tRel = tAbs - _t0;

    _t.addLast(tRel);
    _fTotal.addLast(processed.forceTotal);
    // Symmetry fix: use actual Left/Right columns (not front/back board).
    // Single platform → left column (masterL+slaveL), right column (masterR+slaveR)
    // Dual platform   → left=Platform A, right=Platform B
    if (processed.platformCount == 1) {
      _fLeft.addLast(processed.forceAL);
      _fRight.addLast(processed.forceAR);
    } else {
      _fLeft.addLast(processed.forcePlatformA);
      _fRight.addLast(processed.forcePlatformB);
    }

    // O(1) removal from the front — critical at 1000 Hz.
    while (_t.length > _bufferSize) {
      _t.removeFirst();
      _fTotal.removeFirst();
      _fLeft.removeFirst();
      _fRight.removeFirst();
    }

    final n = state.samplesReceived + 1;
    final bool doChartUpdate = n % _chartUpdateEvery == 0;
    final nextState = LiveDataState(
      timeS:         doChartUpdate ? List<double>.from(_t)      : state.timeS,
      forceTotalN:   doChartUpdate ? List<double>.from(_fTotal) : state.forceTotalN,
      forceLeftN:    doChartUpdate ? List<double>.from(_fLeft)  : state.forceLeftN,
      forceRightN:   doChartUpdate ? List<double>.from(_fRight) : state.forceRightN,
      currentForceN:    processed.forceTotal,
      currentSmoothedN: processed.smoothedTotal,
      currentRawSum:    processed.rawSumA,
      platformCount:    processed.platformCount,
      // Symmetry fix: use left/right column percentages (not master/slave).
      leftPct: (() {
        if (processed.platformCount == 1) {
          final t = processed.forceAL + processed.forceAR;
          return t > 0 ? processed.forceAL / t * 100 : 50.0;
        }
        return processed.leftPercent;
      })(),
      rightPct: (() {
        if (processed.platformCount == 1) {
          final t = processed.forceAL + processed.forceAR;
          return t > 0 ? processed.forceAR / t * 100 : 50.0;
        }
        return processed.rightPercent;
      })(),
      samplesReceived:     n,
      currentForceALN:     processed.forceAL,
      currentForceARN:     processed.forceAR,
      currentForceMasterN: processed.forceMasterSide,
      currentForceSlaveN:  processed.forceSlaveSide,
      currentRawAML: processed.rawAML,
      currentRawAMR: processed.rawAMR,
      currentRawASL: processed.rawASL,
      currentRawASR: processed.rawASR,
      currentRawBML: processed.rawBML,
      currentRawBMR: processed.rawBMR,
      currentRawBSL: processed.rawBSL,
      currentRawBSR: processed.rawBSR,
    );
    state = nextState;
  }

  @override
  void dispose() {
    _disposed = true;
    _t.clear(); _fTotal.clear(); _fLeft.clear(); _fRight.clear();
    super.dispose();
  }

  void reset() {
    _t.clear(); _fTotal.clear(); _fLeft.clear(); _fRight.clear();
    _t0 = 0;
    _processor.reset();
    state = const LiveDataState();
  }

  /// Current processor instance — exposed so [TestStateNotifier] can
  /// read the latest smoothed force for ButterworthOnline pre-warming.
  SignalProcessor get processor => _processor;

}

final liveDataProvider =
    StateNotifierProvider<LiveDataNotifier, LiveDataState>((ref) {
  final cal = ref.watch(calibrationProvider).activeCalibration
      ?? CalibrationData.defaultCalibration();
  final processor = SignalProcessor(cal);
  final notifier = LiveDataNotifier(processor);
  // Use ref.listen (non-deprecated) instead of .stream to receive raw samples.
  // Guardar la suscripción y cerrarla al invalidar el provider.
  final sub = ref.listen<AsyncValue<RawSample>>(rawSampleStreamProvider, (_, next) {
    next.whenData(notifier.onRawSample);
  });
  ref.onDispose(sub.close);
  return notifier;
});
