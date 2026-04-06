import 'dart:convert';

/// Physical orientation of the force platform(s).
enum PlatformOrientation {
  /// Single platform with long axis horizontal (aligned with shoulders).
  /// Long axis (55 cm) = ML, short axis (35 cm) = AP.
  singleHorizontal,

  /// Dual platforms with long axis vertical (perpendicular to shoulders).
  /// Each platform: long axis (55 cm) = AP, short axis (35 cm) = ML.
  /// One foot per platform.
  dualVertical,
}

/// Physical corner position on the force platform relative to the subject.
enum CornerPosition { frontLeft, frontRight, rearLeft, rearRight }

/// Maps ADC channel keys (e.g. A_ML, A_MR, A_SL, A_SR) to physical
/// corner positions on the platform.
///
/// The default (identity) mapping assumes:
///   master_L → front-left,  master_R → front-right
///   slave_L  → rear-left,   slave_R  → rear-right
///
/// When the platform is rotated or wired differently, the user runs
/// the tap-test wizard (or manual assignment) to establish the correct
/// channel-to-corner mapping.
class CellMapping {
  final String platform; // 'A' or 'B'
  final Map<String, CornerPosition> channelToCorner;

  const CellMapping({required this.platform, required this.channelToCorner});

  // ── Defaults ─────────────────────────────────────────────────────────────

  factory CellMapping.defaultForA() => const CellMapping(
    platform: 'A',
    channelToCorner: {
      'A_ML': CornerPosition.frontLeft,
      'A_MR': CornerPosition.frontRight,
      'A_SL': CornerPosition.rearLeft,
      'A_SR': CornerPosition.rearRight,
    },
  );

  factory CellMapping.defaultForB() => const CellMapping(
    platform: 'B',
    channelToCorner: {
      'B_ML': CornerPosition.frontLeft,
      'B_MR': CornerPosition.frontRight,
      'B_SL': CornerPosition.rearLeft,
      'B_SR': CornerPosition.rearRight,
    },
  );

  // ── Lookups ──────────────────────────────────────────────────────────────

  /// Returns the ADC channel key for a given physical corner.
  String? channelForCorner(CornerPosition corner) {
    for (final e in channelToCorner.entries) {
      if (e.value == corner) return e.key;
    }
    return null;
  }

  /// Returns the calibrated force value for a given physical corner.
  /// [cellForces] maps channel keys to their calibrated force (N).
  double forceAtCorner(CornerPosition corner, Map<String, double> cellForces) {
    final channel = channelForCorner(corner);
    return channel != null ? (cellForces[channel] ?? 0.0) : 0.0;
  }

  // ── Aggregate force helpers ──────────────────────────────────────────────

  /// ML-left column = front-left + rear-left.
  double forceLeft(Map<String, double> cellForces) =>
      forceAtCorner(CornerPosition.frontLeft, cellForces) +
      forceAtCorner(CornerPosition.rearLeft, cellForces);

  /// ML-right column = front-right + rear-right.
  double forceRight(Map<String, double> cellForces) =>
      forceAtCorner(CornerPosition.frontRight, cellForces) +
      forceAtCorner(CornerPosition.rearRight, cellForces);

  /// AP-front row = front-left + front-right.
  double forceFront(Map<String, double> cellForces) =>
      forceAtCorner(CornerPosition.frontLeft, cellForces) +
      forceAtCorner(CornerPosition.frontRight, cellForces);

  /// AP-rear row = rear-left + rear-right.
  double forceRear(Map<String, double> cellForces) =>
      forceAtCorner(CornerPosition.rearLeft, cellForces) +
      forceAtCorner(CornerPosition.rearRight, cellForces);

  // ── Validation ───────────────────────────────────────────────────────────

  bool get isValid {
    if (channelToCorner.length != 4) return false;
    final corners = channelToCorner.values.toSet();
    return corners.length == 4; // all 4 corners assigned to unique channels
  }

  // ── Serialization ────────────────────────────────────────────────────────

  String toJson() => jsonEncode({
    'platform': platform,
    'mapping': channelToCorner.map((k, v) => MapEntry(k, v.name)),
  });

  factory CellMapping.fromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final mapping = (m['mapping'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, CornerPosition.values.byName(v as String)),
    );
    return CellMapping(
      platform: m['platform'] as String? ?? 'A',
      channelToCorner: mapping,
    );
  }
}
