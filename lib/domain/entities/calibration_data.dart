import 'dart:convert';

enum CalibrationMode { linear, quadratic, cubic, segmented }

class LinearSegment {
  final double rawMin;
  final double rawMax;
  final double slope;
  final double intercept;
  const LinearSegment({
    required this.rawMin,
    required this.rawMax,
    required this.slope,
    required this.intercept,
  });
  Map<String, dynamic> toMap() => {
    'raw_min': rawMin, 'raw_max': rawMax,
    'slope': slope, 'intercept': intercept,
  };
  factory LinearSegment.fromMap(Map<String, dynamic> m) => LinearSegment(
    rawMin: (m['raw_min'] as num).toDouble(),
    rawMax: (m['raw_max'] as num).toDouble(),
    slope: (m['slope'] as num).toDouble(),
    intercept: (m['intercept'] as num).toDouble(),
  );
}

class CalibrationPoint {
  final double weightKg;
  final double rawSum;
  // Per-cell raw ADC values (negated, pre-offset). Zero if not captured.
  final double rawAML;  // -adcMasterL  Platform A
  final double rawAMR;  // -adcMasterR  Platform A
  final double rawASL;  // -adcSlaveL   Platform A
  final double rawASR;  // -adcSlaveR   Platform A

  const CalibrationPoint({
    required this.weightKg,
    required this.rawSum,
    this.rawAML = 0,
    this.rawAMR = 0,
    this.rawASL = 0,
    this.rawASR = 0,
  });
  Map<String, dynamic> toMap() => {
    'weight_kg': weightKg,
    'raw_sum': rawSum,
    'raw_aml': rawAML,
    'raw_amr': rawAMR,
    'raw_asl': rawASL,
    'raw_asr': rawASR,
  };
  factory CalibrationPoint.fromMap(Map<String, dynamic> m) => CalibrationPoint(
    weightKg: (m['weight_kg'] as num).toDouble(),
    rawSum: (m['raw_sum'] as num).toDouble(),
    rawAML: (m['raw_aml'] as num? ?? 0).toDouble(),
    rawAMR: (m['raw_amr'] as num? ?? 0).toDouble(),
    rawASL: (m['raw_asl'] as num? ?? 0).toDouble(),
    rawASR: (m['raw_asr'] as num? ?? 0).toDouble(),
  );
}

/// Keys used for per-cell calibration (Platform A individual ADC channels).
/// Platform B uses the same convention with 'B_' prefix.
///   A_ML = Platform A, Master Left  (-adcMasterL)
///   A_MR = Platform A, Master Right (-adcMasterR)
///   A_SL = Platform A, Slave Left   (-adcSlaveL)
///   A_SR = Platform A, Slave Right  (-adcSlaveR)
class CalibrationData {
  final int? id;
  final String name;
  final CalibrationMode mode;
  final List<double> coefficients;      // polynomial (descending) — used if !isPerCell
  final List<LinearSegment> segments;   // for segmented mode — used if !isPerCell
  /// Per-cell tare offsets. Keys: 'A_ML','A_MR','A_SL','A_SR','B_ML','B_MR','B_SL','B_SR'
  /// (legacy keys 'A_L','A_R','B_L','B_R' also accepted for backward compat).
  final Map<String, double> cellOffsets;
  /// Per-cell gain factors in N/ADC-count.
  /// Keys same as cellOffsets. Empty map = legacy mode (uses polynomial).
  final Map<String, double> cellGains;
  /// Per-cell polarity: +1 (normal) or -1 (bridge wired inverted).
  /// Applied before offset subtraction in [cellRawToNewton].
  /// Keys: 'A_ML','A_MR','A_SL','A_SR'. Missing key defaults to +1.
  final Map<String, int> cellPolarities;
  final List<CalibrationPoint> points;
  final bool isActive;
  final DateTime createdAt;

  const CalibrationData({
    this.id,
    required this.name,
    required this.mode,
    required this.coefficients,
    required this.segments,
    required this.cellOffsets,
    required this.cellGains,
    required this.cellPolarities,
    required this.points,
    required this.isActive,
    required this.createdAt,
  });

  /// True when this calibration uses per-cell (offset+gain) approach.
  /// False for legacy polynomial-on-sum approach.
  bool get isPerCell => cellGains.isNotEmpty && cellOffsets.containsKey('A_ML');

  // ── Per-cell force computation ─────────────────────────────────────────────

  /// Convert one raw ADC channel (already negated, NOT offset-corrected) to Newtons.
  /// [cell] must be a key like 'A_ML', 'A_MR', 'A_SL', 'A_SR'.
  /// Applies per-cell polarity before offset subtraction.
  double cellRawToNewton(String cell, double rawAdc) {
    final polarity = cellPolarities[cell] ?? 1;
    final offset   = cellOffsets[cell] ?? 0.0;
    final gain     = cellGains[cell]   ?? 1.0;
    return (rawAdc * polarity - offset) * gain;
  }

  // ── Legacy polynomial computation ─────────────────────────────────────────

  /// Convert raw ADC sum → kg using the stored polynomial/segmented calibration.
  double rawToKg(double raw) {
    switch (mode) {
      case CalibrationMode.linear:
      case CalibrationMode.quadratic:
      case CalibrationMode.cubic:
        return _polyval(coefficients, raw);
      case CalibrationMode.segmented:
        return _segmentedLinear(raw);
    }
  }

  double rawToNewton(double raw) => rawToKg(raw) * 9.81;

  double _polyval(List<double> coeffs, double x) {
    double result = 0;
    for (final c in coeffs) {
      result = result * x + c;
    }
    return result;
  }

  double _segmentedLinear(double raw) {
    for (final seg in segments) {
      if (raw >= seg.rawMin && raw <= seg.rawMax) {
        return seg.slope * raw + seg.intercept;
      }
    }
    if (segments.isEmpty) return raw / 1000.0;
    if (raw < segments.first.rawMin) {
      final s = segments.first;
      return s.slope * raw + s.intercept;
    }
    final s = segments.last;
    return s.slope * raw + s.intercept;
  }

  // ── Serialisation ──────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'mode': mode.index,
    'coefficients_json':   jsonEncode(coefficients),
    'cell_offsets_json':   jsonEncode(cellOffsets),
    'cell_gains_json':     jsonEncode(cellGains),
    'cell_polarities_json': jsonEncode(cellPolarities),
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
  };

  factory CalibrationData.fromMap(Map<String, dynamic> map) {
    final coeffs = (jsonDecode(map['coefficients_json'] as String) as List)
        .map((e) => (e as num).toDouble())
        .toList();
    final offsets = (jsonDecode(map['cell_offsets_json'] as String) as Map)
        .map((k, v) => MapEntry(k as String, (v as num).toDouble()));

    // cell_gains_json is new; old rows won't have it → default empty (legacy mode).
    Map<String, double> gains = {};
    final gainsRaw = map['cell_gains_json'];
    if (gainsRaw != null && gainsRaw is String && gainsRaw.isNotEmpty) {
      try {
        gains = (jsonDecode(gainsRaw) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble()));
      } catch (_) {}
    }

    // cell_polarities_json: new in v3; old rows default to all +1 (empty map).
    Map<String, int> polarities = {};
    final polRaw = map['cell_polarities_json'];
    if (polRaw != null && polRaw is String && polRaw.isNotEmpty) {
      try {
        polarities = (jsonDecode(polRaw) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toInt()));
      } catch (_) {}
    }

    return CalibrationData(
      id: map['id'] as int?,
      name: map['name'] as String,
      mode: CalibrationMode.values[map['mode'] as int],
      coefficients: coeffs,
      segments: [],
      cellOffsets: offsets,
      cellGains: gains,
      cellPolarities: polarities,
      points: [],
      isActive: (map['is_active'] as int) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static CalibrationData defaultCalibration() => CalibrationData(
    name: 'Default (sin calibrar)',
    mode: CalibrationMode.linear,
    // coefficient = 1/9.81 → rawToNewton(x) = x  (1 ADC count ≈ 1 N)
    coefficients: [1.0 / 9.81, 0.0],
    segments: [],
    cellOffsets: {'A_L': 0.0, 'A_R': 0.0, 'B_L': 0.0, 'B_R': 0.0},
    cellGains: {},
    cellPolarities: {},
    points: [],
    isActive: true,
    createdAt: DateTime.now(),
  );
}
