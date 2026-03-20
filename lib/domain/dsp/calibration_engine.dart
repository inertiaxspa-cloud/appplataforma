import '../entities/calibration_data.dart';

/// Per-cell raw readings captured at a single calibration weight step.
class CellRawReading {
  final double weightKg;
  final double rawAML;   // -adcMasterL  (offset already subtracted)
  final double rawAMR;   // -adcMasterR
  final double rawASL;   // -adcSlaveL   (0 if slave timeout)
  final double rawASR;   // -adcSlaveR
  const CellRawReading({
    required this.weightKg,
    required this.rawAML,
    required this.rawAMR,
    required this.rawASL,
    required this.rawASR,
  });
}

/// Polynomial fitting using the normal equations (pure Dart, no scipy).
///
/// Equivalent to numpy.polyfit — returns coefficients in descending order.
class CalibrationEngine {
  /// Fit a polynomial of given [degree] to (x, y) data points.
  /// Returns coefficients in descending order: [a_n, ..., a_1, a_0]
  static List<double> polyfit(List<double> x, List<double> y, int degree) {
    assert(x.length == y.length, 'x and y must have same length');
    assert(x.length > degree, 'Need more points than polynomial degree');

    final n = x.length;
    final p = degree + 1;

    // Build Vandermonde matrix A (n × p)
    final A = List.generate(n, (i) =>
        List.generate(p, (j) => _pow(x[i], degree - j)));

    // Normal equations: (A^T * A) * c = A^T * y
    final At  = _transpose(A);
    final AtA = _matMul(At, A);
    final Aty = _matVecMul(At, y);

    return _gaussianElimination(AtA, Aty);
  }

  /// Compute per-cell gain factors (N / ADC-count) from calibration readings.
  ///
  /// All 4 cells on a platform share the same sensitivity because they use
  /// identical load cell hardware. The gain is computed from the total platform
  /// sum at each known weight and averaged across all calibration points:
  ///
  ///   gain = mean( weightKg_i × 9.81 / Σ corrected_cells_i )
  ///
  /// Per-cell offsets (tare) already handle terrain irregularities; the gain
  /// only accounts for ADC-count → Newton conversion.
  ///
  /// [readings] must have offsets already subtracted.
  /// Returns map with keys 'A_ML','A_MR','A_SL','A_SR'.
  static Map<String, double> computeCellGains(
      List<CellRawReading> readings, int platformCells) {
    if (readings.isEmpty) return {};

    double gainSum = 0;
    int count = 0;

    for (final r in readings) {
      if (r.weightKg <= 0) continue;
      final totalCorrected = r.rawAML + r.rawAMR + r.rawASL + r.rawASR;
      if (totalCorrected < 1.0) continue; // guard against near-zero divide
      gainSum += (r.weightKg * 9.81) / totalCorrected;
      count++;
    }

    final gain = count > 0 ? gainSum / count : 1.0;
    if (gain <= 0 || gain.isInfinite || gain.isNaN) {
      throw Exception(
          'Calibración inválida: ganancia calculada = $gain. '
          'Verifica que los pesos y lecturas ADC sean correctos.');
    }
    return {'A_ML': gain, 'A_MR': gain, 'A_SL': gain, 'A_SR': gain};
  }

  /// Build segmented linear calibration from sorted calibration points.
  static List<LinearSegment> buildSegments(List<CalibrationPoint> points) {
    if (points.length < 2) return [];
    final sorted = List<CalibrationPoint>.from(points)
      ..sort((a, b) => a.rawSum.compareTo(b.rawSum));
    final segments = <LinearSegment>[];
    for (int i = 0; i < sorted.length - 1; i++) {
      final dx = sorted[i + 1].rawSum - sorted[i].rawSum;
      if (dx.abs() < 1e-9) continue;
      final slope     = (sorted[i + 1].weightKg - sorted[i].weightKg) / dx;
      final intercept = sorted[i].weightKg - slope * sorted[i].rawSum;
      segments.add(LinearSegment(
        rawMin: sorted[i].rawSum,
        rawMax: sorted[i + 1].rawSum,
        slope: slope,
        intercept: intercept,
      ));
    }
    return segments;
  }

  // ── Linear algebra helpers ─────────────────────────────────────────────────

  static List<List<double>> _transpose(List<List<double>> m) {
    final rows = m.length, cols = m[0].length;
    return List.generate(cols, (j) => List.generate(rows, (i) => m[i][j]));
  }

  static List<List<double>> _matMul(
      List<List<double>> a, List<List<double>> b) {
    final rows = a.length, cols = b[0].length, inner = b.length;
    return List.generate(rows, (i) => List.generate(cols, (j) {
      double s = 0;
      for (int k = 0; k < inner; k++) s += a[i][k] * b[k][j];
      return s;
    }));
  }

  static List<double> _matVecMul(List<List<double>> a, List<double> v) {
    return List.generate(a.length, (i) {
      double s = 0;
      for (int j = 0; j < v.length; j++) s += a[i][j] * v[j];
      return s;
    });
  }

  static List<double> _gaussianElimination(
      List<List<double>> a, List<double> b) {
    final n = b.length;
    // Build augmented matrix [A | b]
    final aug = List.generate(n, (i) => List<double>.from([...a[i], b[i]]));

    for (int col = 0; col < n; col++) {
      // Partial pivot: find row with max absolute value in this column
      int maxRow = col;
      for (int r = col + 1; r < n; r++) {
        if (aug[r][col].abs() > aug[maxRow][col].abs()) maxRow = r;
      }
      final swap = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = swap;

      if (aug[col][col].abs() < 1e-12) continue;

      // Eliminate all other rows
      for (int r = 0; r < n; r++) {
        if (r == col) continue;
        final factor = aug[r][col] / aug[col][col];
        for (int c = col; c <= n; c++) {
          aug[r][c] -= factor * aug[col][c];
        }
      }
    }

    return List.generate(n, (i) =>
        aug[i][i].abs() < 1e-12 ? 0.0 : aug[i][n] / aug[i][i]);
  }

  static double _pow(double base, int exp) {
    if (exp == 0) return 1.0;
    double result = 1.0;
    for (int i = 0; i < exp; i++) result *= base;
    return result;
  }
}
