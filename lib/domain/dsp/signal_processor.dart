import '../../core/constants/physics_constants.dart';
import '../../data/models/processed_sample.dart';
import '../../data/models/raw_sample.dart';
import '../entities/calibration_data.dart';
import 'butterworth_filter.dart';

/// Fuses raw samples from platform A and B, applies calibration,
/// and produces [ProcessedSample]s at ~1000 Hz.
///
/// Supports two calibration modes:
///   1. Per-cell (offset + gain per ADC channel) — new, preferred.
///   2. Polynomial on ADC sum — legacy backward compat.
///
/// Smoothing: 4th-order causal Butterworth LP at 50 Hz.
class SignalProcessor {
  static const int _platformBTimeoutMs = PhysicsConstants.platformBTimeoutMs;

  CalibrationData _calibration;
  int _platformCount = 0; // 0 = unknown, 1 or 2

  // Held B values until platform A arrives
  int _lastRawBML = 0, _lastRawBMR = 0, _lastRawBSL = 0, _lastRawBSR = 0;
  double _lastBTimestamp = -1;
  double _firstATimestamp = -1;   // timestamp of first Platform A sample received
  bool _lastBSlaveTimeout = false;

  final ButterworthOnline _bw = ButterworthOnline();

  SignalProcessor(this._calibration);

  void updateCalibration(CalibrationData cal) => _calibration = cal;

  ProcessedSample? process(RawSample sample) {
    if (sample.platformId == 2) {
      _lastRawBML = sample.adcMasterL;
      _lastRawBMR = sample.adcMasterR;
      _lastRawBSL = sample.adcSlaveL;
      _lastRawBSR = sample.adcSlaveR;
      _lastBTimestamp = sample.timestampUs / 1e6;
      _lastBSlaveTimeout = sample.hasSlaveTimeout;
      if (_platformCount == 0) _platformCount = 2;
      return null;
    }

    // Platform A arrived
    final nowS = sample.timestampUs / 1e6;
    if (_firstATimestamp < 0) _firstATimestamp = nowS;

    if (_platformCount == 0) {
      if (_platformCount == 2) {
        // Already detected via Platform B packet — nothing to do.
      } else if (_lastBTimestamp >= 0) {
        // Platform B has arrived at least once — 2-platform mode.
        _platformCount = 2;
      } else if ((nowS - _firstATimestamp) * 1000 > _platformBTimeoutMs) {
        // No Platform B received within timeout — 1-platform mode.
        _platformCount = 1;
      }
    }

    final cal = _calibration;

    // ── Raw ADC values (negated per firmware convention) ────────────────────
    final rawAML = (-sample.adcMasterL).toDouble();
    final rawAMR = (-sample.adcMasterR).toDouble();
    final rawASL = sample.hasSlaveTimeout ? 0.0 : (-sample.adcSlaveL).toDouble();
    final rawASR = sample.hasSlaveTimeout ? 0.0 : (-sample.adcSlaveR).toDouble();

    double forceAL, forceAR, forcePlatformA, forceMasterSide, forceSlaveSide;

    if (cal.isPerCell) {
      // ── Per-cell calibration ─────────────────────────────────────────────
      final forceAML = cal.cellRawToNewton('A_ML', rawAML);
      final forceAMR = cal.cellRawToNewton('A_MR', rawAMR);
      final forceASL = cal.cellRawToNewton('A_SL', rawASL);
      final forceASR = cal.cellRawToNewton('A_SR', rawASR);

      // L column = masterL + slaveL,  R column = masterR + slaveR
      forceAL = forceAML + forceASL;
      forceAR = forceAMR + forceASR;
      forcePlatformA = forceAL + forceAR;

      // Master side (front) vs Slave side (back)
      forceMasterSide = forceAML + forceAMR;
      forceSlaveSide  = forceASL + forceASR;
    } else {
      // ── Legacy polynomial calibration ────────────────────────────────────
      final offsets = cal.cellOffsets;
      final al_raw = sample.rawLeft  - (offsets['A_L'] ?? 0.0);
      final ar_raw = sample.rawRight - (offsets['A_R'] ?? 0.0);

      forceAL = cal.rawToNewton(al_raw);
      forceAR = cal.rawToNewton(ar_raw);
      forcePlatformA = cal.rawToNewton(al_raw + ar_raw);

      final aMasterRaw = -(sample.adcMasterL + sample.adcMasterR)
          - (offsets['A_L'] ?? 0.0) - (offsets['A_R'] ?? 0.0);
      final aSlaveRaw  = sample.hasSlaveTimeout ? 0.0
          : -(sample.adcSlaveL + sample.adcSlaveR).toDouble();
      forceMasterSide = cal.rawToNewton(aMasterRaw);
      forceSlaveSide  = cal.rawToNewton(aSlaveRaw);
    }

    // ── Platform B ──────────────────────────────────────────────────────────
    double forceBL = 0, forceBR = 0, forcePlatformB = 0;
    if (_platformCount == 2) {
      final rawBML = (-_lastRawBML).toDouble();
      final rawBMR = (-_lastRawBMR).toDouble();
      final rawBSL = _lastBSlaveTimeout ? 0.0 : (-_lastRawBSL).toDouble();
      final rawBSR = _lastBSlaveTimeout ? 0.0 : (-_lastRawBSR).toDouble();

      if (cal.isPerCell && cal.cellOffsets.containsKey('B_ML')) {
        final forceBML = cal.cellRawToNewton('B_ML', rawBML);
        final forceBMR = cal.cellRawToNewton('B_MR', rawBMR);
        final forceBSL = cal.cellRawToNewton('B_SL', rawBSL);
        final forceBSR = cal.cellRawToNewton('B_SR', rawBSR);
        forceBL = forceBML + forceBSL;
        forceBR = forceBMR + forceBSR;
        forcePlatformB = forceBL + forceBR;
      } else {
        // Legacy for platform B
        final offsets = cal.cellOffsets;
        final bl_raw = (rawBML + rawBSL) - (offsets['B_L'] ?? 0.0);
        final br_raw = (rawBMR + rawBSR) - (offsets['B_R'] ?? 0.0);
        forceBL = cal.rawToNewton(bl_raw);
        forceBR = cal.rawToNewton(br_raw);
        forcePlatformB = cal.rawToNewton(bl_raw + br_raw);
      }
    }

    // ── Total force & smoothing ─────────────────────────────────────────────
    final forceTotal = forcePlatformA + forcePlatformB;
    final smoothed   = _bw.process(forceTotal);

    return ProcessedSample(
      timestampS: nowS,
      forceAL: forceAL,
      forceAR: forceAR,
      forceBL: forceBL,
      forceBR: forceBR,
      forcePlatformA: forcePlatformA,
      forcePlatformB: forcePlatformB,
      forceTotal: forceTotal,
      smoothedTotal: smoothed,
      forceMasterSide: forceMasterSide,
      forceSlaveSide: forceSlaveSide,
      rawSumA: rawAML + rawAMR + rawASL + rawASR,
      rawAML: rawAML,
      rawAMR: rawAMR,
      rawASL: rawASL,
      rawASR: rawASR,
      platformCount: _platformCount == 0 ? 1 : _platformCount,
      hasSlaveBTimeout: _lastBSlaveTimeout,
      hasSlaveATimeout: sample.hasSlaveTimeout,
    );
  }

  int get platformCount => _platformCount == 0 ? 1 : _platformCount;

  /// Pre-warm the internal Butterworth filter to steady-state for [forceN].
  /// Call this right after creating a new [SignalProcessor] for a test,
  /// passing the athlete's current body-weight force from the live display.
  /// This prevents the cold-start transient from corrupting the impulse-
  /// momentum height calculation.
  void prewarmFilter(double forceN) {
    if (forceN > 20) _bw.prewarm(forceN);
  }

  void reset() {
    _bw.reset();
    _lastRawBML = _lastRawBMR = _lastRawBSL = _lastRawBSR = 0;
    _lastBTimestamp = -1;
    _platformCount = 0;
  }
}
