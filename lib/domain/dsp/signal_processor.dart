import '../../core/constants/physics_constants.dart';
import '../../data/models/processed_sample.dart';
import '../../data/models/raw_sample.dart';
import '../entities/calibration_data.dart';
import '../entities/cell_mapping.dart';
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
  CellMapping _mappingA;
  CellMapping _mappingB;
  int _platformCount = 0; // 0 = unknown, 1 or 2

  // Held B values until platform A arrives
  int _lastRawBML = 0, _lastRawBMR = 0, _lastRawBSL = 0, _lastRawBSR = 0;
  double _lastBTimestamp = -1;
  double _firstATimestamp = -1;   // timestamp of first Platform A sample received
  bool _lastBSlaveTimeout = false;

  final ButterworthOnline _bw = ButterworthOnline();

  SignalProcessor(this._calibration)
      : _mappingA = CellMapping.defaultForA(),
        _mappingB = CellMapping.defaultForB();

  void updateCalibration(CalibrationData cal) => _calibration = cal;

  void updateCellMapping(CellMapping a, [CellMapping? b]) {
    _mappingA = a;
    if (b != null) _mappingB = b;
  }

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

    // C1 fix: removed unreachable `if (_platformCount == 2)` inner branch.
    if (_platformCount == 0) {
      if (_lastBTimestamp >= 0) {
        _platformCount = 2;
      } else if ((nowS - _firstATimestamp) * 1000 > _platformBTimeoutMs) {
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

      // Route calibrated cell forces through the corner mapping.
      // This handles platform rotation: the mapping tells us which ADC
      // channel is physically at each corner (FL, FR, RL, RR).
      final cellForces = {'A_ML': forceAML, 'A_MR': forceAMR, 'A_SL': forceASL, 'A_SR': forceASR};
      forceAL = _mappingA.forceLeft(cellForces);   // ML-left column
      forceAR = _mappingA.forceRight(cellForces);  // ML-right column
      forcePlatformA = forceAL + forceAR;

      forceMasterSide = _mappingA.forceFront(cellForces);  // AP-front row
      forceSlaveSide  = _mappingA.forceRear(cellForces);   // AP-rear row
    } else {
      // ── Legacy polynomial calibration ────────────────────────────────────
      final offsets = cal.cellOffsets;
      final al_raw = sample.rawLeft  - (offsets['A_L'] ?? 0.0);
      final ar_raw = sample.rawRight - (offsets['A_R'] ?? 0.0);

      forceAL = cal.rawToNewton(al_raw);
      forceAR = cal.rawToNewton(ar_raw);
      forcePlatformA = cal.rawToNewton(al_raw + ar_raw);

      final aMasterRaw = -(sample.adcMasterL + sample.adcMasterR)
          - (offsets['A_ML'] ?? offsets['A_L'] ?? 0.0)
          - (offsets['A_MR'] ?? offsets['A_R'] ?? 0.0);
      // C3 fix: apply slave-board offsets (were missing — caused asymmetry bias).
      final aSlaveRaw  = sample.hasSlaveTimeout ? 0.0
          : -(sample.adcSlaveL + sample.adcSlaveR).toDouble()
              - (offsets['A_SL'] ?? 0.0) - (offsets['A_SR'] ?? 0.0);
      forceMasterSide = cal.rawToNewton(aMasterRaw);
      forceSlaveSide  = cal.rawToNewton(aSlaveRaw);
    }

    // ── Platform B ──────────────────────────────────────────────────────────
    double forceBL = 0, forceBR = 0, forcePlatformB = 0;
    // C2 fix: discard stale B data if no B sample received within timeout.
    final bStale = _platformCount == 2 && _lastBTimestamp >= 0
        && (nowS - _lastBTimestamp) > _platformBTimeoutMs / 1000.0;
    if (_platformCount == 2 && !bStale) {
      final rawBML = (-_lastRawBML).toDouble();
      final rawBMR = (-_lastRawBMR).toDouble();
      final rawBSL = _lastBSlaveTimeout ? 0.0 : (-_lastRawBSL).toDouble();
      final rawBSR = _lastBSlaveTimeout ? 0.0 : (-_lastRawBSR).toDouble();

      if (cal.isPerCell && cal.cellOffsets.containsKey('B_ML')) {
        final forceBML = cal.cellRawToNewton('B_ML', rawBML);
        final forceBMR = cal.cellRawToNewton('B_MR', rawBMR);
        final forceBSL = cal.cellRawToNewton('B_SL', rawBSL);
        final forceBSR = cal.cellRawToNewton('B_SR', rawBSR);
        final bCellForces = {'B_ML': forceBML, 'B_MR': forceBMR, 'B_SL': forceBSL, 'B_SR': forceBSR};
        forceBL = _mappingB.forceLeft(bCellForces);
        forceBR = _mappingB.forceRight(bCellForces);
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

    // ── Spike / outlier rejection ────────────────────────────────────────────
    // At 921600 baud over Android USB-OTG, occasional framing errors produce
    // corrupted CSV lines whose ADC values are astronomically large.  A single
    // such sample contaminates the Butterworth state for hundreds of subsequent
    // samples.  Reject any sample that exceeds the physical maximum for a
    // human on a force platform (two 100-kg athletes jumping simultaneously
    // = ~20 kN; set guard at 30 kN to leave ample headroom).
    // The filter is NOT updated, so its state stays clean.
    const double _kMaxForceN = 30000.0;
    if (forceTotal.isNaN || forceTotal.isInfinite || forceTotal > _kMaxForceN || forceTotal < -1000.0) {
      return null;
    }

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
      rawBML: _platformCount == 2 ? (-_lastRawBML).toDouble() : 0,
      rawBMR: _platformCount == 2 ? (-_lastRawBMR).toDouble() : 0,
      rawBSL: _platformCount == 2 && !_lastBSlaveTimeout ? (-_lastRawBSL).toDouble() : 0,
      rawBSR: _platformCount == 2 && !_lastBSlaveTimeout ? (-_lastRawBSR).toDouble() : 0,
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
