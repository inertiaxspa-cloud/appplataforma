import 'dart:math' as math;
import '../../entities/test_result.dart';
import '../../../core/constants/physics_constants.dart';

/// All jump-related metric calculations.
class JumpMetrics {
  JumpMetrics._();

  static const double g = PhysicsConstants.gravity;

  // ── Jump height ────────────────────────────────────────────────────────────

  /// Gold-standard: impulse-momentum method.
  /// v_takeoff = ∫(F − BW) dt / m  over the movement phase (v=0 at startIdx).
  /// h = v² / (2g).
  /// Reference: Linthorne (2001).
  static double jumpHeightFromImpulse({
    required List<double> forceN,
    required List<double> timeS,
    required double bodyWeightN,
    required int startIdx,   // index where v = 0 (start of quiet standing)
    required int takeoffIdx, // last sample before airborne
  }) {
    if (takeoffIdx <= startIdx) return 0;
    final mass = bodyWeightN / g;
    double velocity = 0.0;
    for (int i = startIdx + 1; i <= takeoffIdx; i++) {
      final dt = timeS[i] - timeS[i - 1];
      final netForce = (forceN[i] + forceN[i - 1]) / 2 - bodyWeightN;
      velocity += netForce * dt / mass;
    }
    return math.max(0, (velocity * velocity) / (2 * g));
  }

  /// From flight time: h = g·tf² / 8.
  static double jumpHeightFromFlightTime(double flightTimeS) =>
      0.125 * g * flightTimeS * flightTimeS;

  // ── Velocity ───────────────────────────────────────────────────────────────

  /// Cumulative trapezoidal integration of net force → velocity signal [m/s].
  static List<double> velocityFromForce({
    required List<double> forceN,
    required List<double> timeS,
    required double bodyWeightN,
    int startIdx = 0,
  }) {
    final mass = bodyWeightN / g;
    final vel = List<double>.filled(forceN.length, 0.0);
    for (int i = math.max(1, startIdx); i < forceN.length; i++) {
      final dt = timeS[i] - timeS[i - 1];
      vel[i] = vel[i - 1] +
          ((forceN[i] + forceN[i - 1]) / 2 - bodyWeightN) * dt / mass;
    }
    return vel;
  }

  // ── RFD ───────────────────────────────────────────────────────────────────

  /// Rate of Force Development [N/s] over a fixed time window from force onset.
  static double rfdAtWindow({
    required List<double> forceN,
    required List<double> timeS,
    required int onsetIdx,
    required double windowS,
  }) {
    if (onsetIdx >= forceN.length) return 0;
    final targetTime = timeS[onsetIdx] + windowS;
    int endIdx = forceN.length - 1;
    for (int i = onsetIdx; i < forceN.length; i++) {
      if (timeS[i] >= targetTime) { endIdx = i; break; }
    }
    final dt = timeS[endIdx] - timeS[onsetIdx];
    if (dt < 1e-6) return 0;
    return (forceN[endIdx] - forceN[onsetIdx]) / dt;
  }

  // ── Power ──────────────────────────────────────────────────────────────────

  /// Sayers equation: PP = 60.7·h_cm + 45.3·BW_kg − 2055.
  /// Reference: Sayers et al. (1999).
  static double peakPowerSayers(double heightCm, double bodyWeightKg) =>
      60.7 * heightCm + 45.3 * bodyWeightKg - 2055;

  /// Harman equation: PP = 61.9·h_cm + 36.0·BW_kg − 1822.
  /// Reference: Harman et al. (1991).
  static double peakPowerHarman(double heightCm, double bodyWeightKg) =>
      61.9 * heightCm + 36.0 * bodyWeightKg - 1822;

  /// Impulse-based peak power: max(F × v) over the propulsive phase.
  static double peakPowerFromImpulse({
    required List<double> forceN,
    required List<double> velocityMS,
    required int startIdx,
    required int endIdx,
  }) {
    double maxPower = 0.0;
    for (int i = startIdx; i <= endIdx && i < forceN.length; i++) {
      final p = forceN[i] * velocityMS[i];
      if (p > maxPower) maxPower = p;
    }
    return maxPower;
  }

  // ── Impulse ────────────────────────────────────────────────────────────────

  /// Total impulse via trapezoidal integration over [startIdx, endIdx].
  static double impulse({
    required List<double> forceN,
    required List<double> timeS,
    required int startIdx,
    required int endIdx,
  }) {
    double sum = 0;
    for (int i = startIdx + 1; i <= endIdx && i < forceN.length; i++) {
      sum += (forceN[i] + forceN[i - 1]) / 2 * (timeS[i] - timeS[i - 1]);
    }
    return sum;
  }

  /// Net impulse (subtracts body-weight contribution).
  static double netImpulse({
    required List<double> forceN,
    required List<double> timeS,
    required double bodyWeightN,
    required int startIdx,
    required int endIdx,
  }) {
    double sum = 0;
    for (int i = startIdx + 1; i <= endIdx && i < forceN.length; i++) {
      final dt = timeS[i] - timeS[i - 1];
      sum += ((forceN[i] + forceN[i - 1]) / 2 - bodyWeightN) * dt;
    }
    return sum;
  }

  // ── Time to peak force ────────────────────────────────────────────────────

  static double timeToPeakForce({
    required List<double> forceN,
    required List<double> timeS,
    required int startIdx,
  }) {
    int peakIdx = startIdx;
    double peakVal = forceN[startIdx];
    for (int i = startIdx + 1; i < forceN.length; i++) {
      if (forceN[i] > peakVal) { peakVal = forceN[i]; peakIdx = i; }
    }
    return (timeS[peakIdx] - timeS[startIdx]) * 1000; // ms
  }

  // ── Phase detection helpers ───────────────────────────────────────────────

  static int findTakeoffIndex(
      List<double> forceN, double threshold, int searchFrom) {
    for (int i = searchFrom; i < forceN.length; i++) {
      if (forceN[i] < threshold) return i;
    }
    return forceN.length - 1;
  }

  static int findLandingIndex(
      List<double> forceN, double threshold, int searchFrom) {
    for (int i = searchFrom; i < forceN.length; i++) {
      if (forceN[i] > threshold) return i;
    }
    return forceN.length - 1;
  }

  static int findDescentOnset(
      List<double> forceN, double bodyWeightN, int searchFrom) {
    final threshold = bodyWeightN - PhysicsConstants.cmjWeightThreshold;
    for (int i = searchFrom; i < forceN.length; i++) {
      if (forceN[i] < threshold) return i;
    }
    return searchFrom;
  }

  // ── Symmetry ──────────────────────────────────────────────────────────────

  /// Build [SymmetryResult] for 2-platform mode.
  ///
  /// [useLsi] = true selects the Limb Symmetry Index (Robinson et al., 1987).
  /// [useLsi] = false (default) uses Asymmetry Index = |left% − 50%|.
  static SymmetryResult symmetry2Platform({
    required double totalPlatformAN,
    required double totalPlatformBN,
    bool useLsi = false,
  }) {
    final total    = totalPlatformAN + totalPlatformBN;
    final leftPct  = total > 0 ? totalPlatformAN / total * 100 : 50.0;
    final rightPct = 100.0 - leftPct;

    final asymIdx = useLsi
        ? _lsiAsymmetry(leftPct, rightPct)
        : (leftPct - 50.0).abs();

    return SymmetryResult(
      leftPercent:      leftPct,
      rightPercent:     rightPct,
      asymmetryIndexPct: asymIdx,
      isTwoPlatform:    true,
    );
  }

  /// Build [SymmetryResult] for 1-platform mode (master vs slave board side).
  static SymmetryResult symmetry1Platform({
    required double masterSideN,
    required double slaveSideN,
    bool useLsi = false,
  }) {
    final total      = masterSideN + slaveSideN;
    final masterPct  = total > 0 ? masterSideN / total * 100 : 50.0;
    final slavePct   = 100.0 - masterPct;

    final asymIdx = useLsi
        ? _lsiAsymmetry(masterPct, slavePct)
        : (masterPct - 50.0).abs();

    return SymmetryResult(
      leftPercent:      masterPct,   // convention: master = left
      rightPercent:     slavePct,
      asymmetryIndexPct: asymIdx,
      isTwoPlatform:    false,
    );
  }

  // ── Landing peak force ────────────────────────────────────────────────────

  /// Pico de fuerza en ventana de [windowMs] ms después del aterrizaje.
  static double landingPeakForce({
    required List<double> forceN,
    required int landingIdx,
    int windowMs = 200,
    int samplingRateHz = 1000,
  }) {
    if (forceN.isEmpty || landingIdx >= forceN.length) return 0.0;
    final endIdx = math.min(forceN.length, landingIdx + windowMs * samplingRateHz ~/ 1000);
    var peak = 0.0;
    for (var i = landingIdx; i < endIdx; i++) {
      if (forceN[i] > peak) peak = forceN[i];
    }
    return peak;
  }

  // ── Multi-jump analytics ──────────────────────────────────────────────────

  /// Índice de fatiga: (mean(first3) - mean(last3)) / mean(first3) × 100.
  static double fatiguePercent(List<double> heights) {
    if (heights.length < 6) return 0.0;
    final first3 = heights.take(3).fold(0.0, (s, v) => s + v) / 3.0;
    final last3  = heights.skip(heights.length - 3).fold(0.0, (s, v) => s + v) / 3.0;
    if (first3 <= 0) return 0.0;
    return math.max(0.0, (first3 - last3) / first3 * 100.0);
  }

  /// Variabilidad CV% de alturas.
  static double variabilityCV(List<double> heights) {
    if (heights.length < 2) return 0.0;
    final mean = heights.fold(0.0, (s, v) => s + v) / heights.length;
    if (mean <= 0) return 0.0;
    final variance = heights.fold(0.0, (s, v) => s + (v - mean) * (v - mean)) / heights.length;
    return math.sqrt(variance) / mean * 100.0;
  }

  // ── Elasticity ────────────────────────────────────────────────────────────

  /// Índice de elasticidad CMJ vs SJ.
  static double elasticityIndex({
    required double cmjHeightCm,
    required double sjHeightCm,
  }) {
    if (sjHeightCm <= 0) return 0.0;
    return (cmjHeightCm - sjHeightCm) / sjHeightCm * 100.0;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// LSI asymmetry = (1 − min/max) × 100.
  /// Returns 0 when perfectly symmetric, increases with asymmetry.
  static double _lsiAsymmetry(double pctA, double pctB) {
    final maxPct = pctA >= pctB ? pctA : pctB;
    final minPct = pctA <  pctB ? pctA : pctB;
    if (maxPct < 1e-6) return 0.0;
    return (1.0 - minPct / maxPct) * 100.0;
  }
}
