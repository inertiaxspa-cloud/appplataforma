/// A single fused, calibrated sample emitted by [SignalProcessor].
///
/// Emitted once per Platform A arrival (1000 Hz), fusing both platforms.
class ProcessedSample {
  final double timestampS;      // seconds (converted from timestamp_us)

  // Per-channel forces in Newtons (calibrated)
  final double forceAL;         // Platform A, left cell (master_L side)
  final double forceAR;         // Platform A, right cell (master_R side)
  final double forceBL;         // Platform B, left cell (master_L side)
  final double forceBR;         // Platform B, right cell (master_R side)

  // Aggregates
  final double forcePlatformA;  // A_L + A_R
  final double forcePlatformB;  // B_L + B_R
  final double forceTotal;      // sum of all 4 channels
  final double smoothedTotal;   // moving-average filtered total

  // Single-platform symmetry (master board vs slave board, platform A)
  final double forceMasterSide; // adcMasterL + adcMasterR → calibrated
  final double forceSlaveSide;  // adcSlaveL  + adcSlaveR  → calibrated

  /// Raw pre-calibration ADC sum for platform A (legacy calibration wizard).
  final double rawSumA;

  // ── Per-cell raw ADC (negated, NOT offset-corrected) ──────────────────────
  /// Used by the calibration wizard to capture per-cell tare and gain points.
  final double rawAML;   // -adcMasterL   Platform A
  final double rawAMR;   // -adcMasterR   Platform A
  final double rawASL;   // -adcSlaveL    Platform A  (0 if slave timeout)
  final double rawASR;   // -adcSlaveR    Platform A  (0 if slave timeout)

  // Metadata
  final int platformCount;      // 1 or 2 platforms detected
  final bool hasSlaveBTimeout;  // platform B slave timeout
  final bool hasSlaveATimeout;  // platform A slave timeout

  const ProcessedSample({
    required this.timestampS,
    required this.forceAL,
    required this.forceAR,
    required this.forceBL,
    required this.forceBR,
    required this.forcePlatformA,
    required this.forcePlatformB,
    required this.forceTotal,
    required this.smoothedTotal,
    required this.forceMasterSide,
    required this.forceSlaveSide,
    required this.rawSumA,
    required this.rawAML,
    required this.rawAMR,
    required this.rawASL,
    required this.rawASR,
    required this.platformCount,
    this.hasSlaveBTimeout = false,
    this.hasSlaveATimeout = false,
  });

  /// Left/right symmetry for 2-platform mode (0–100% per side).
  double get leftPercent  => forceTotal > 0 ? forcePlatformA / forceTotal * 100 : 50;
  double get rightPercent => forceTotal > 0 ? forcePlatformB / forceTotal * 100 : 50;

  /// Left/right symmetry for 1-platform mode (master vs slave board).
  double get masterPercent {
    final total = forceMasterSide + forceSlaveSide;
    return total > 0 ? forceMasterSide / total * 100 : 50;
  }
  double get slavePercent {
    final total = forceMasterSide + forceSlaveSide;
    return total > 0 ? forceSlaveSide / total * 100 : 50;
  }

  /// Asymmetry index % (absolute difference from balanced).
  double get asymmetryIndex2P => (leftPercent - 50).abs();
  double get asymmetryIndex1P => (masterPercent - 50).abs();
}
