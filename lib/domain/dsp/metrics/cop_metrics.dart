import 'dart:math' as math;
import '../../../data/models/processed_sample.dart';
import '../../entities/test_result.dart';

/// Centre of Pressure metrics for balance/postural stability tests.
///
/// Coordinate system:
///   X-axis → mediolateral  (negative = left, positive = right)
///   Y-axis → anteroposterior (negative = back, positive = front)
///
/// Single platform geometry (35 × 55 cm, cells at 5.5 cm from ML edges
/// and 3.5 cm from AP edges):
///   ML: forceAL (master_L + slave_L) vs forceAR (master_R + slave_R)
///       cell centres at ±(width/2 − 5.5 cm) from centreline
///       default ML half-span = 120 mm
///   AP: forceMasterSide (master_L + master_R) vs forceSlaveSide (slave_L + slave_R)
///       cell centres at ±(length/2 − 3.5 cm) from centreline
///       default AP half-span = 240 mm
///
/// Dual platform:
///   ML: forcePlatformA vs forcePlatformB  (platform separation)
///   AP: not available (Y = 0)
///
/// All distances are in mm to match [CoPResult] fields.
class CopMetrics {
  // ── CoP position ──────────────────────────────────────────────────────────

  /// Mediolateral CoP in mm.
  /// [halfSpanMm] = distance from platform centre to each cell centre in ML axis.
  static double copXMm({
    required double forceLeft_N,
    required double forceRight_N,
    double halfSpanMm = 120.0,
  }) {
    final total = forceLeft_N + forceRight_N;
    if (total < 1.0) return 0.0;
    // Positive = right side heavier
    return (forceRight_N - forceLeft_N) / total * halfSpanMm;
  }

  /// Anteroposterior CoP in mm.
  /// [halfSpanMm] = distance from platform centre to each cell centre in AP axis.
  static double copYMm({
    required double forceFront_N,
    required double forceBack_N,
    double halfSpanMm = 240.0,
  }) {
    final total = forceFront_N + forceBack_N;
    if (total < 1.0) return 0.0;
    // Positive = front/master side heavier
    return (forceFront_N - forceBack_N) / total * halfSpanMm;
  }

  // ── Trajectory smoother ────────────────────────────────────────────────────

  /// Simple moving average over [window] points.
  /// Applied to the CoP trajectory to suppress high-frequency noise before
  /// computing path length, range, area and frequency.
  /// (30-Hz sampling from liveDataProvider produces ~1–2 mm noise per sample;
  /// without smoothing the path length is 50× the true value.)
  static List<_Point> _smooth(List<_Point> pts, {int window = 5}) {
    if (pts.length <= window) return pts;
    final half = window ~/ 2;
    final out  = <_Point>[];
    for (int i = 0; i < pts.length; i++) {
      final lo = math.max(0, i - half);
      final hi = math.min(pts.length - 1, i + half);
      var sx = 0.0, sy = 0.0;
      final n = hi - lo + 1;
      for (int j = lo; j <= hi; j++) {
        sx += pts[j].x;
        sy += pts[j].y;
      }
      out.add(_Point(x: sx / n, y: sy / n));
    }
    return out;
  }

  // ── Sway statistics ───────────────────────────────────────────────────────

  /// Total sway path length in mm.
  static double swayPathMm(List<_Point> pts) {
    if (pts.length < 2) return 0.0;
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final dx = pts[i].x - pts[i - 1].x;
      final dy = pts[i].y - pts[i - 1].y;
      total += math.sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  /// Mean velocity (mm/s).
  static double meanVelocityMmS(List<_Point> pts, double durationS) {
    if (durationS <= 0) return 0.0;
    return swayPathMm(pts) / durationS;
  }

  /// Range (peak-to-peak) on the X (mediolateral) axis in mm.
  static double rangeMLMm(List<_Point> pts) {
    if (pts.length < 2) return 0.0;
    final xs = pts.map((p) => p.x);
    return xs.reduce(math.max) - xs.reduce(math.min);
  }

  /// Range (peak-to-peak) on the Y (anteroposterior) axis in mm.
  static double rangeAPMm(List<_Point> pts) {
    if (pts.length < 2) return 0.0;
    final ys = pts.map((p) => p.y);
    return ys.reduce(math.max) - ys.reduce(math.min);
  }

  /// 95 % confidence ellipse area in mm².
  ///
  /// When only mediolateral (X) data are available (Y = 0 always, i.e. hardware
  /// provides only Fz on two platforms), the 2-D covariance degenerates to 1-D.
  /// In that case the function returns the area of an equivalent circle whose
  /// radius equals the 95 % ML confidence half-width:
  ///   area₁D = π × χ²(0.95, df=1) × λ₁  where χ²(0.95,1) = 3.841
  ///
  /// This gives a meaningful, non-zero "sway area proxy" for single-axis systems.
  /// Reference for 2-D formula: Schubert & Kirchner (2014); Prieto et al. (1996).
  static double ellipseAreaMm2(List<_Point> pts) {
    if (pts.length < 3) return 0.0;
    final n = pts.length;
    var mx = 0.0, my = 0.0;
    for (final p in pts) { mx += p.x; my += p.y; }
    mx /= n; my /= n;

    var cxx = 0.0, cyy = 0.0, cxy = 0.0;
    for (final p in pts) {
      final dx = p.x - mx;
      final dy = p.y - my;
      cxx += dx * dx;
      cyy += dy * dy;
      cxy += dx * dy;
    }
    cxx /= (n - 1);
    cyy /= (n - 1);
    cxy /= (n - 1);

    final trace = cxx + cyy;
    final det   = cxx * cyy - cxy * cxy;
    final disc  = math.sqrt(math.max(0, trace * trace / 4.0 - det));
    final lam1  = trace / 2.0 + disc;
    final lam2  = trace / 2.0 - disc;

    // 1-D degenerate case (hardware measures ML only):
    // Y = 0 → λ₂ ≈ 0. Use 1-D equivalent circle area.
    if (lam2.abs() < 1e-6) {
      // χ²(0.95, df=1) = 3.841
      const chi2df1 = 3.841;
      return math.pi * chi2df1 * lam1;
    }

    // Full 2-D ellipse: χ²(0.95, df=2) = 5.991
    const chi2 = 5.991;
    return math.pi * chi2 *
        math.sqrt(math.max(0, lam1)) *
        math.sqrt(math.max(0, lam2));
  }

  // ── Dominant frequency ────────────────────────────────────────────────────

  /// Dominant frequency via zero-crossing rate on the ML axis.
  /// Fast approximation; use [dominantFrequencyHzFft] for greater accuracy.
  static double dominantFrequencyHz(List<_Point> pts, double durationS) {
    if (pts.length < 4 || durationS <= 0) return 0.0;
    var crossings = 0;
    final mx = pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length;
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1].x - mx;
      final curr = pts[i].x - mx;
      if (prev * curr < 0) crossings++;
    }
    final freq = crossings / (2.0 * durationS);
    return freq.isFinite ? freq : 0.0;
  }

  /// Dominant frequency via DFT power spectrum.
  ///
  /// Returns f₉₅: the frequency below which 95 % of the total spectral power
  /// lies (Prieto et al., 1996).  Signal is downsampled to ~100 Hz before
  /// analysis; frequencies analysed up to 10 Hz (relevant range for postural
  /// sway).  A Hanning window is applied to reduce spectral leakage.
  static double dominantFrequencyHzFft(List<_Point> pts, double durationS) {
    if (pts.length < 10 || durationS <= 0) return 0.0;

    // Downsample to ~100 Hz to limit computation.
    const targetHz = 100.0;
    final actualHz = pts.length / durationS;
    final step = math.max(1, (actualHz / targetHz).round());
    final xRaw = <double>[];
    for (var i = 0; i < pts.length; i += step) {
      xRaw.add(pts[i].x);
    }
    final n = xRaw.length;
    if (n < 4) return 0.0;

    // Effective sample rate and frequency resolution after downsampling.
    final fs  = n / durationS;              // Hz
    final df  = 1.0 / durationS;            // Hz per bin
    final maxAnalysisHz = math.min(fs / 2.0, 10.0);  // analyse 0–10 Hz only
    final numBins = (maxAnalysisHz / df).floor() + 1;
    if (numBins < 2) return 0.0;

    // Remove mean.
    final mean = xRaw.fold(0.0, (s, v) => s + v) / n;
    final xc = xRaw.map((v) => v - mean).toList();

    // Apply Hanning window to reduce spectral leakage.
    for (var t = 0; t < n; t++) {
      xc[t] *= 0.5 * (1.0 - math.cos(2.0 * math.pi * t / (n - 1)));
    }

    // Compute DFT magnitude² at each frequency bin (0 … maxAnalysisHz).
    final wBase  = 2.0 * math.pi / n;
    final power  = List<double>.filled(numBins, 0.0);
    for (var k = 0; k < numBins; k++) {
      final wk = wBase * k;
      var re = 0.0, im = 0.0;
      for (var t = 0; t < n; t++) {
        final phase = wk * t;
        re += xc[t] * math.cos(phase);
        im -= xc[t] * math.sin(phase);
      }
      power[k] = re * re + im * im;
    }

    // Find f₉₅: cumulative power threshold.
    final totalPower = power.fold(0.0, (s, v) => s + v);
    if (totalPower <= 0) return 0.0;
    var cumPower = 0.0;
    for (var k = 0; k < numBins; k++) {
      cumPower += power[k];
      if (cumPower >= 0.95 * totalPower) return k * df;
    }
    return maxAnalysisHz;
  }

  /// Symmetry percentage: how close is weight distribution to 50/50.
  static double symmetryPct({
    required double meanForceA,
    required double meanForceB,
  }) {
    final total = meanForceA + meanForceB;
    if (total <= 0) return 100.0;
    final ratio = meanForceA / total;
    final result = 100.0 - (ratio - 0.5).abs() * 200.0;
    return math.max(0.0, math.min(100.0, result));
  }

  // ── Build CoPResult ───────────────────────────────────────────────────────

  /// Compute all CoP metrics from a list of [ProcessedSample]s.
  ///
  /// Platform geometry (single platform):
  ///   [platformWidthMm]  — ML extent (default 350 mm for 35 cm platform)
  ///   [platformLengthMm] — AP extent (default 550 mm for 55 cm platform)
  ///   Cells are located 55 mm from ML edges → ML half-span = width/2 − 55
  ///   Cells are located 35 mm from AP edges → AP half-span = length/2 − 35
  ///
  /// Set [useFftFrequency] = true to use the DFT-based f₉₅ method instead of
  /// zero-crossing rate (slower but more accurate).
  static CoPResult compute({
    required List<ProcessedSample> samples,
    required double durationS,
    required String condition,   // 'OA' or 'OC'
    required String stance,      // 'bipedal', 'left', 'right'
    CoPResult? eyesOpenResult,
    double platformSeparationMm = 300.0,
    double platformWidthMm      = 350.0,
    double platformLengthMm     = 550.0,
    bool useFftFrequency = false,
  }) {
    final platformCount = samples.isNotEmpty ? samples.first.platformCount : 1;

    if (samples.isEmpty) {
      return CoPResult(
        computedAt:       DateTime.now(),
        platformCount:    platformCount,
        condition:        condition,
        stance:           stance,
        testDurationS:    durationS,
        areaEllipseMm2:   0,
        pathLengthMm:     0,
        meanVelocityMmS:  0,
        rangeMLMm:        0,
        rangeAPMm:        0,
        symmetryPercent:  100,
        frequency95Hz:    0,
        rombergQuotient:  null,
      );
    }

    // ── Derive cell spans from platform dimensions ──────────────────────────
    // Cell offset from ML edge = 55 mm → ML half-span = width/2 − 55
    // Cell offset from AP edge = 35 mm → AP half-span = length/2 − 35
    final mlHalfSpan = (platformWidthMm  / 2.0) - 55.0;   // mm
    final apHalfSpan = (platformLengthMm / 2.0) - 35.0;   // mm
    // Dual-platform ML uses centre-to-centre separation
    final dualMlHalfSpan = platformSeparationMm / 2.0;

    // ── Build CoP trajectory ────────────────────────────────────────────────
    final pts = <_Point>[];
    var sumA = 0.0, sumB = 0.0;

    for (final s in samples) {
      final fA = s.forcePlatformA;
      final fB = s.forcePlatformB;
      double x, y;

      if (platformCount >= 2) {
        // Dual platform: ML from A vs B platforms; AP not available
        x = (fA + fB > 1.0)
            ? copXMm(
                forceLeft_N:  fA,
                forceRight_N: fB,
                halfSpanMm:   dualMlHalfSpan,
              )
            : 0.0;
        y = 0.0;
      } else {
        // Single platform: ML from forceAL vs forceAR,
        //                  AP from forceMasterSide vs forceSlaveSide
        final fAL = s.forceAL;
        final fAR = s.forceAR;
        final fMs = s.forceMasterSide;
        final fSs = s.forceSlaveSide;

        x = (fAL + fAR > 1.0)
            ? copXMm(
                forceLeft_N:  fAL,
                forceRight_N: fAR,
                halfSpanMm:   mlHalfSpan,
              )
            : 0.0;
        y = (fMs + fSs > 1.0)
            ? copYMm(
                forceFront_N: fMs,
                forceBack_N:  fSs,
                halfSpanMm:   apHalfSpan,
              )
            : 0.0;
      }

      sumA += fA;
      sumB += fB;
      pts.add(_Point(x: x, y: y));
    }

    // ── Smooth trajectory (5-point MA) to suppress 30-Hz sampling noise ────
    // Without smoothing, path length is inflated ~50× by sample-to-sample noise.
    final smoothed = _smooth(pts, window: 5);

    final n        = samples.length;
    final area     = ellipseAreaMm2(smoothed);
    final path     = swayPathMm(smoothed);
    final velocity = meanVelocityMmS(smoothed, durationS);
    final rML      = rangeMLMm(smoothed);
    final rAP      = rangeAPMm(smoothed);
    final freq     = useFftFrequency
        ? dominantFrequencyHzFft(smoothed, durationS)
        : dominantFrequencyHz(smoothed, durationS);
    final symPct   = (sumA + sumB > 0)
        ? symmetryPct(meanForceA: sumA / n, meanForceB: sumB / n)
        : 100.0;

    double? romberg;
    if (eyesOpenResult != null && eyesOpenResult.areaEllipseMm2 > 0) {
      romberg = area / eyesOpenResult.areaEllipseMm2;
    }

    return CoPResult(
      computedAt:      DateTime.now(),
      platformCount:   platformCount,
      condition:       condition,
      stance:          stance,
      testDurationS:   durationS,
      areaEllipseMm2:  area,
      pathLengthMm:    path,
      meanVelocityMmS: velocity,
      rangeMLMm:       rML,
      rangeAPMm:       rAP,
      symmetryPercent: symPct,
      frequency95Hz:   freq,
      rombergQuotient: romberg,
    );
  }
}

class _Point {
  final double x, y;
  const _Point({required this.x, required this.y});
}
