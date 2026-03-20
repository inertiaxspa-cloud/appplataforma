/// 4th-order Butterworth low-pass filter — fs = 1000 Hz, fc = 50 Hz.
///
/// Implemented as two cascaded biquad (SOS) sections derived via the
/// bilinear transform with frequency pre-warping.
///
/// References:
///   Oppenheim & Schafer, "Discrete-Time Signal Processing", 3rd ed.
///   Winter, "Biomechanics and Motor Control of Human Movement", 4th ed.
///
/// Two usage modes:
///   • [ButterworthOnline]  – causal, sample-by-sample (live processing).
///   • [ButterworthFilter.filtfilt] – zero-phase forward-backward pass
///     (post-processing: jump height, RFD, velocity signal).
class ButterworthFilter {
  ButterworthFilter._();

  // ── Pre-computed SOS coefficients ──────────────────────────────────────────
  // fs = 1000 Hz, fc = 50 Hz, 4th-order Butterworth.
  // Designed via bilinear transform with pre-warping:
  //   k = tan(π·fc/fs) = tan(π/20) ≈ 0.158384
  //
  // Section 1  Q₁ = 1/(2·sin(π/8)) = 1.3066 → 2/Q₁ = 0.7654
  static const List<double> _b1 = [0.021884, 0.043768, 0.021884];
  static const List<double> _a1 = [1.0, -1.700950, 0.788490];

  // Section 2  Q₂ = 1/(2·sin(3π/8)) = 0.5412 → 2/Q₂ = 1.8478
  static const List<double> _b2 = [0.019038, 0.038076, 0.019038];
  static const List<double> _a2 = [1.0, -1.479600, 0.555746];

  // ── Direct-form II biquad step ─────────────────────────────────────────────
  // w[0]=w[n-1], w[1]=w[n-2]  (mutable state passed by caller)
  static double _biquad(
    double x,
    List<double> b,
    List<double> a,
    List<double> w,
  ) {
    final w0 = x - a[1] * w[0] - a[2] * w[1];
    final y  = b[0] * w0 + b[1] * w[0] + b[2] * w[1];
    w[1] = w[0];
    w[0] = w0;
    return y;
  }

  // Steady-state initial condition for a biquad section given a DC input x.
  // For a constant input x, the steady-state internal state w satisfies:
  //   w = x / (1 + a[1] + a[2])   (Direct-Form II)
  static List<double> _initDC(double x, List<double> a) {
    final denom = 1.0 + a[1] + a[2];
    final w = denom.abs() > 1e-12 ? x / denom : 0.0;
    return [w, w];
  }

  // Single causal forward pass through both SOS sections.
  // [initVal] pre-warms the filter state to steady-state for that constant,
  // eliminating the startup transient that would otherwise corrupt the
  // first ~100 samples (critical for correct phase-index finding).
  static List<double> _forwardPass(List<double> x, {double initVal = 0.0}) {
    final w1 = _initDC(initVal, _a1);
    final w2 = _initDC(initVal, _a2);
    final out = List<double>.filled(x.length, 0.0);
    for (int i = 0; i < x.length; i++) {
      out[i] = _biquad(_biquad(x[i], _b1, _a1, w1), _b2, _a2, w2);
    }
    return out;
  }

  // ── Offline zero-phase filter (filtfilt equivalent) ────────────────────────

  /// Applies a zero-phase 4th-order Butterworth LP filter (50 Hz / 1000 Hz).
  ///
  /// Equivalent to SciPy `sosfiltfilt` — forward + backward pass doubles the
  /// effective roll-off to 8th order and eliminates all phase distortion.
  /// Both passes are pre-warmed to steady-state to avoid edge transients.
  ///
  /// Use this for post-processing (jump height, RFD, velocity signal).
  /// Returns a new [List<double>] of the same length as [signal].
  static List<double> filtfilt(List<double> signal) {
    if (signal.length < 6) return List.of(signal);

    // Forward pass — pre-warm to signal.first to avoid leading transient
    final fwd = _forwardPass(signal, initVal: signal.first);

    // Backward pass: reverse → filter → reverse
    // Pre-warm to fwd.last (= signal.last after forward) to avoid trailing transient
    final rev = List<double>.generate(fwd.length, (i) => fwd[fwd.length - 1 - i]);
    final bwd = _forwardPass(rev, initVal: rev.first);

    return List<double>.generate(bwd.length, (i) => bwd[bwd.length - 1 - i]);
  }
}

// ── Online causal instance ───────────────────────────────────────────────────

/// Stateful 4th-order Butterworth LP filter for sample-by-sample processing.
///
/// Create one instance per signal channel. Not thread-safe — for use inside
/// a single Dart Isolate.
class ButterworthOnline {
  // Biquad section states: [w[n-1], w[n-2]]
  final List<double> _w1 = [0.0, 0.0];
  final List<double> _w2 = [0.0, 0.0];

  /// Feed one sample; returns the filtered value.
  double process(double x) {
    final y1 = ButterworthFilter._biquad(
        x, ButterworthFilter._b1, ButterworthFilter._a1, _w1);
    return ButterworthFilter._biquad(
        y1, ButterworthFilter._b2, ButterworthFilter._a2, _w2);
  }

  /// Reset internal state (call when starting a new test or after a gap).
  void reset() {
    _w1[0] = _w1[1] = 0.0;
    _w2[0] = _w2[1] = 0.0;
  }
}
