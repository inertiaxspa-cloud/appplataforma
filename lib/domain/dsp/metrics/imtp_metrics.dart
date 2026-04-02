import 'dart:math' as math;
import '../../../data/models/processed_sample.dart';
import '../../entities/test_result.dart';
import 'jump_metrics.dart';

/// Isometric Mid-Thigh Pull metrics.
///
/// Protocol:
///  1. Athlete setup: ~20° knee flexion, bar fixed overhead.
///  2. Settling phase: 2s tare to establish bodyweight.
///  3. On signal: max effort pull for 3–5 s.
///
/// Key metrics (matching [ImtpResult]):
///  - Peak force (N and × BW)
///  - Net impulse (N·s)
///  - RFD at 50, 100, 200 ms
///  - Time to peak force
///  - Symmetry (left/right or master/slave)
class ImtpMetrics {
  // ── Core ──────────────────────────────────────────────────────────────────

  static double peakForce(List<double> forceN) =>
      forceN.isEmpty ? 0.0 : forceN.reduce(math.max);

  /// Net impulse = ∫(F − BW) dt using trapezoid rule.
  static double netImpulse({
    required List<double> forceN,
    required double bodyWeightN,
    double dt = 0.001,
  }) {
    if (forceN.length < 2) return 0.0;
    var imp = 0.0;
    for (var i = 1; i < forceN.length; i++) {
      imp += ((forceN[i - 1] - bodyWeightN) + (forceN[i] - bodyWeightN)) / 2.0 * dt;
    }
    return math.max(0.0, imp);
  }

  /// Time from onset to peak force in ms.
  static double timeToPeakMs(List<double> forceN, {int samplingRateHz = 1000}) {
    if (forceN.isEmpty) return 0.0;
    var maxIdx = 0;
    var maxVal = forceN[0];
    for (var i = 1; i < forceN.length; i++) {
      if (forceN[i] > maxVal) { maxVal = forceN[i]; maxIdx = i; }
    }
    return maxIdx * 1000.0 / samplingRateHz;
  }

  /// Onset index: first sample exceeding BW + threshold (default 50 N).
  static int detectOnset({
    required List<double> forceN,
    required double bodyWeightN,
    double thresholdN = 50.0,
  }) {
    for (var i = 0; i < forceN.length; i++) {
      if (forceN[i] - bodyWeightN >= thresholdN) return i;
    }
    return 0;
  }

  /// RFD over a window starting at pull onset [N/s].
  static double rfdAtWindow({
    required List<double> forceN,
    required int windowMs,
    int samplingRateHz = 1000,
  }) {
    if (forceN.isEmpty) return 0.0;
    final endIdx = (windowMs * samplingRateHz / 1000).round().clamp(0, forceN.length - 1);
    if (endIdx == 0) return 0.0;
    final deltaF = forceN[endIdx] - forceN[0];
    final deltaT = endIdx / samplingRateHz;
    return deltaT > 0 ? deltaF / deltaT : 0.0;
  }

  // ── Build ImtpResult ──────────────────────────────────────────────────────

  static ImtpResult compute({
    required List<ProcessedSample> samples,
    required double bodyWeightN,
  }) {
    final platformCount = samples.isNotEmpty ? samples.first.platformCount : 1;
    final empty = ImtpResult(
      computedAt:        DateTime.now(),
      platformCount:     platformCount,
      peakForceN:        0,
      peakForceBW:       0,
      netImpulseNs:      0,
      rfdAt50ms:         0,
      rfdAt100ms:        0,
      rfdAt200ms:        0,
      timeToPeakForceMs: 0,
      symmetry: SymmetryResult(
        leftPercent: 50, rightPercent: 50,
        asymmetryIndexPct: 0, isTwoPlatform: false,
      ),
    );

    if (samples.isEmpty) return empty;

    final allForce = samples.map((s) => s.forceTotal).toList();
    final onsetIdx = detectOnset(forceN: allForce, bodyWeightN: bodyWeightN);
    final pull     = allForce.sublist(onsetIdx);
    if (pull.isEmpty) return empty;

    final peak     = peakForce(pull);
    final impulse  = netImpulse(forceN: pull, bodyWeightN: bodyWeightN);
    final ttpMs    = timeToPeakMs(pull);
    final r50      = rfdAtWindow(forceN: pull, windowMs: 50);
    final r100     = rfdAtWindow(forceN: pull, windowMs: 100);
    final r200     = rfdAtWindow(forceN: pull, windowMs: 200);

    // Symmetry from peak sample
    final peakIdx  = pull.indexOf(peak);
    final pkIdx    = (onsetIdx + peakIdx).clamp(0, samples.length - 1);
    final pkSample = samples[pkIdx];
    final sym = platformCount == 2
        ? JumpMetrics.symmetry2Platform(
            totalPlatformAN: pkSample.forcePlatformA,
            totalPlatformBN: pkSample.forcePlatformB,
          )
        : JumpMetrics.symmetry1Platform(
            masterSideN: pkSample.forcePlatformA,
            slaveSideN:  pkSample.forcePlatformB,
          );

    return ImtpResult(
      computedAt:        DateTime.now(),
      platformCount:     platformCount,
      peakForceN:        peak,
      peakForceBW:       bodyWeightN > 0 ? peak / bodyWeightN : 0,
      netImpulseNs:      impulse,
      rfdAt50ms:         r50,
      rfdAt100ms:        r100,
      rfdAt200ms:        r200,
      timeToPeakForceMs: ttpMs,
      symmetry:          sym,
    );
  }
}
