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
  });
}

// ── Live data notifier ─────────────────────────────────────────────────────

class LiveDataNotifier extends StateNotifier<LiveDataState> {
  static const int _bufferSize = PhysicsConstants.chartBufferSize; // 5000

  final List<double> _t = [];
  final List<double> _fTotal = [];
  final List<double> _fLeft  = [];
  final List<double> _fRight = [];
  double _t0 = 0;

  final SignalProcessor _processor;

  LiveDataNotifier(this._processor) : super(const LiveDataState());

  void onRawSample(RawSample raw) {
    final processed = _processor.process(raw);
    if (processed == null) return;

    final tAbs = processed.timestampS;
    if (_t0 == 0) _t0 = tAbs;
    final tRel = tAbs - _t0;

    _t.add(tRel);
    _fTotal.add(processed.forceTotal);
    // Single platform → left=master board, right=slave board
    // Dual platform   → left=Platform A,   right=Platform B
    if (processed.platformCount == 1) {
      _fLeft.add(processed.forceMasterSide);
      _fRight.add(processed.forceSlaveSide);
    } else {
      _fLeft.add(processed.forcePlatformA);
      _fRight.add(processed.forcePlatformB);
    }

    while (_t.length > _bufferSize) {
      _t.removeAt(0);
      _fTotal.removeAt(0);
      _fLeft.removeAt(0);
      _fRight.removeAt(0);
    }

    final n = state.samplesReceived + 1;
    final nextState = LiveDataState(
      timeS:         n % 33 == 0 ? List.unmodifiable(_t)      : state.timeS,
      forceTotalN:   n % 33 == 0 ? List.unmodifiable(_fTotal) : state.forceTotalN,
      forceLeftN:    n % 33 == 0 ? List.unmodifiable(_fLeft)  : state.forceLeftN,
      forceRightN:   n % 33 == 0 ? List.unmodifiable(_fRight) : state.forceRightN,
      currentForceN:    processed.forceTotal,
      currentSmoothedN: processed.smoothedTotal,
      currentRawSum:    processed.rawSumA,
      platformCount:    processed.platformCount,
      leftPct:  processed.platformCount == 1
          ? processed.masterPercent : processed.leftPercent,
      rightPct: processed.platformCount == 1
          ? processed.slavePercent  : processed.rightPercent,
      samplesReceived:     n,
      currentForceALN:     processed.forceAL,
      currentForceARN:     processed.forceAR,
      currentForceMasterN: processed.forceMasterSide,
      currentForceSlaveN:  processed.forceSlaveSide,
      currentRawAML: processed.rawAML,
      currentRawAMR: processed.rawAMR,
      currentRawASL: processed.rawASL,
      currentRawASR: processed.rawASR,
    );
    state = nextState;
  }

  void reset() {
    _t.clear(); _fTotal.clear(); _fLeft.clear(); _fRight.clear();
    _t0 = 0;
    _processor.reset();
    state = const LiveDataState();
  }

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
