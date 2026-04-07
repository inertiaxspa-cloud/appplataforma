import 'dart:convert';

import 'package:inertiax/core/l10n/app_strings.dart';

enum TestType { cmj, cmjArms, sj, dropJump, multiJump, cop, imtp, freeTest }

extension TestTypeExt on TestType {
  String get displayName {
    switch (this) {
      case TestType.cmj:       return AppStrings.get('test_cmj');
      case TestType.cmjArms:   return AppStrings.get('test_cmj_arms');
      case TestType.sj:        return AppStrings.get('test_sj');
      case TestType.dropJump:  return AppStrings.get('test_dj');
      case TestType.multiJump: return AppStrings.get('test_multijump');
      case TestType.cop:       return AppStrings.get('test_cop');
      case TestType.imtp:      return AppStrings.get('test_imtp');
      case TestType.freeTest:  return AppStrings.get('test_free');
    }
  }

  bool get requiresTwoPlatforms => this == TestType.cop;
  bool get isJumpTest => [TestType.cmj, TestType.cmjArms, TestType.sj,
                           TestType.dropJump, TestType.multiJump].contains(this);
}

// ─────────────────────────────────────────────────────────────────────────────
// Symmetry
// ─────────────────────────────────────────────────────────────────────────────

class SymmetryResult {
  final double leftPercent;
  final double rightPercent;
  final double asymmetryIndexPct;
  final bool isTwoPlatform;

  const SymmetryResult({
    required this.leftPercent,
    required this.rightPercent,
    required this.asymmetryIndexPct,
    required this.isTwoPlatform,
  });

  bool get isSymmetric => asymmetryIndexPct <= 10.0;

  Map<String, dynamic> toMap() => {
    'left_pct': leftPercent,
    'right_pct': rightPercent,
    'asymmetry_index_pct': asymmetryIndexPct,
    'two_platform': isTwoPlatform,
  };

  factory SymmetryResult.fromMap(Map<String, dynamic> m) => SymmetryResult(
    leftPercent: (m['left_pct'] as num?)?.toDouble() ?? 50.0,
    rightPercent: (m['right_pct'] as num?)?.toDouble() ?? 50.0,
    asymmetryIndexPct: (m['asymmetry_index_pct'] as num?)?.toDouble() ?? 0.0,
    isTwoPlatform: m['two_platform'] as bool? ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Base
// ─────────────────────────────────────────────────────────────────────────────

sealed class TestResult {
  final int? sessionId;
  final TestType testType;
  final DateTime computedAt;
  final int platformCount;

  const TestResult({
    this.sessionId,
    required this.testType,
    required this.computedAt,
    required this.platformCount,
  });

  Map<String, dynamic> toMap();

  static TestResult fromJson(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>?;
      if (map == null) throw const FormatException('Empty JSON');
      final typeIdx = map['test_type'] as int?;
      if (typeIdx == null || typeIdx < 0 || typeIdx >= TestType.values.length) {
        throw FormatException('Invalid test_type: $typeIdx');
      }
      final type = TestType.values[typeIdx];
      switch (type) {
        case TestType.cmj:
        case TestType.cmjArms:
        case TestType.sj:
          return JumpResult.fromMap(map);
        case TestType.dropJump:
          return DropJumpResult.fromMap(map);
        case TestType.multiJump:
          return MultiJumpResult.fromMap(map);
        case TestType.cop:
          return CoPResult.fromMap(map);
        case TestType.imtp:
          return ImtpResult.fromMap(map);
        case TestType.freeTest:
          return FreeTestResult.fromMap(map);
      }
    } catch (e) {
      throw FormatException('TestResult.fromJson failed: $e\nJSON: ${json.length > 200 ? json.substring(0, 200) : json}');
    }
  }

  String toJson() => jsonEncode(toMap());
}

// ─────────────────────────────────────────────────────────────────────────────
// Jump (CMJ / SJ)
// ─────────────────────────────────────────────────────────────────────────────

class JumpResult extends TestResult {
  final double jumpHeightCm;
  final double flightTimeMs;
  final double peakForceN;
  final double meanForceN;
  final double bodyWeightN;
  final double propulsiveImpulseNs;
  final double brakingImpulseNs;
  final double takeoffForceN;
  final double rfdAt50ms;
  final double rfdAt100ms;
  final double rfdAt200ms;
  final double timeToPeakForceMs;
  final double eccentricDurationMs;
  final double concentricDurationMs;
  final double peakPowerSayersW;
  final double peakPowerImpulseW;
  final SymmetryResult symmetry;
  final double jumpHeightFlightTimeCm;
  final double landingPeakForceN;

  const JumpResult({
    super.sessionId,
    required super.testType,
    required super.computedAt,
    required super.platformCount,
    required this.jumpHeightCm,
    required this.flightTimeMs,
    required this.peakForceN,
    required this.meanForceN,
    required this.bodyWeightN,
    required this.propulsiveImpulseNs,
    required this.brakingImpulseNs,
    required this.takeoffForceN,
    required this.rfdAt50ms,
    required this.rfdAt100ms,
    required this.rfdAt200ms,
    required this.timeToPeakForceMs,
    required this.eccentricDurationMs,
    required this.concentricDurationMs,
    required this.peakPowerSayersW,
    required this.peakPowerImpulseW,
    required this.symmetry,
    required this.jumpHeightFlightTimeCm,
    required this.landingPeakForceN,
  });

  @override
  Map<String, dynamic> toMap() => {
    'test_type': testType.index,
    'computed_at': computedAt.toIso8601String(),
    'platform_count': platformCount,
    'jump_height_cm': jumpHeightCm,
    'flight_time_ms': flightTimeMs,
    'peak_force_n': peakForceN,
    'mean_force_n': meanForceN,
    'body_weight_n': bodyWeightN,
    'propulsive_impulse_ns': propulsiveImpulseNs,
    'braking_impulse_ns': brakingImpulseNs,
    'takeoff_force_n': takeoffForceN,
    'rfd_50ms': rfdAt50ms,
    'rfd_100ms': rfdAt100ms,
    'rfd_200ms': rfdAt200ms,
    'time_to_peak_force_ms': timeToPeakForceMs,
    'eccentric_duration_ms': eccentricDurationMs,
    'concentric_duration_ms': concentricDurationMs,
    'peak_power_sayers_w': peakPowerSayersW,
    'peak_power_impulse_w': peakPowerImpulseW,
    'symmetry': symmetry.toMap(),
    'jump_height_ft_cm': jumpHeightFlightTimeCm,
    'landing_peak_force_n': landingPeakForceN,
  };

  factory JumpResult.fromMap(Map<String, dynamic> m) => JumpResult(
    testType: TestType.values[m['test_type'] as int? ?? 0],
    computedAt: DateTime.parse(m['computed_at'] as String? ?? DateTime.now().toIso8601String()),
    platformCount: m['platform_count'] as int? ?? 1,
    jumpHeightCm: (m['jump_height_cm'] as num?)?.toDouble() ?? 0.0,
    flightTimeMs: (m['flight_time_ms'] as num?)?.toDouble() ?? 0.0,
    peakForceN: (m['peak_force_n'] as num?)?.toDouble() ?? 0.0,
    meanForceN: (m['mean_force_n'] as num?)?.toDouble() ?? 0.0,
    bodyWeightN: (m['body_weight_n'] as num?)?.toDouble() ?? 0.0,
    propulsiveImpulseNs: (m['propulsive_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    brakingImpulseNs: (m['braking_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    takeoffForceN: (m['takeoff_force_n'] as num?)?.toDouble() ?? 0.0,
    rfdAt50ms: (m['rfd_50ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt100ms: (m['rfd_100ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt200ms: (m['rfd_200ms'] as num?)?.toDouble() ?? 0.0,
    timeToPeakForceMs: (m['time_to_peak_force_ms'] as num?)?.toDouble() ?? 0.0,
    eccentricDurationMs: (m['eccentric_duration_ms'] as num?)?.toDouble() ?? 0.0,
    concentricDurationMs: (m['concentric_duration_ms'] as num?)?.toDouble() ?? 0.0,
    peakPowerSayersW: (m['peak_power_sayers_w'] as num?)?.toDouble() ?? 0.0,
    peakPowerImpulseW: (m['peak_power_impulse_w'] as num?)?.toDouble() ?? 0.0,
    symmetry: m['symmetry'] is Map<String, dynamic>
        ? SymmetryResult.fromMap(m['symmetry'] as Map<String, dynamic>)
        : const SymmetryResult(leftPercent: 50, rightPercent: 50, asymmetryIndexPct: 0, isTwoPlatform: false),
    jumpHeightFlightTimeCm: (m['jump_height_ft_cm'] as num? ?? 0.0).toDouble(),
    landingPeakForceN: (m['landing_peak_force_n'] as num? ?? 0.0).toDouble(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Drop Jump
// ─────────────────────────────────────────────────────────────────────────────

class DropJumpResult extends JumpResult {
  final double contactTimeMs;
  final double rsiMod;
  /// True when the athlete returned to the box (no flight/landing on platform).
  final bool isBoxReturn;
  /// Height of the drop box in cm (used for RSI reactive analysis).
  final double dropHeightCm;

  const DropJumpResult({
    super.sessionId,
    required super.testType,
    required super.computedAt,
    required super.platformCount,
    required super.jumpHeightCm,
    required super.flightTimeMs,
    required super.peakForceN,
    required super.meanForceN,
    required super.bodyWeightN,
    required super.propulsiveImpulseNs,
    required super.brakingImpulseNs,
    required super.takeoffForceN,
    required super.rfdAt50ms,
    required super.rfdAt100ms,
    required super.rfdAt200ms,
    required super.timeToPeakForceMs,
    required super.eccentricDurationMs,
    required super.concentricDurationMs,
    required super.peakPowerSayersW,
    required super.peakPowerImpulseW,
    required super.symmetry,
    required super.jumpHeightFlightTimeCm,
    required super.landingPeakForceN,
    required this.contactTimeMs,
    required this.rsiMod,
    this.isBoxReturn = false,
    this.dropHeightCm = 0,
  });

  @override
  Map<String, dynamic> toMap() => {
    ...super.toMap(),
    'contact_time_ms': contactTimeMs,
    'rsi_mod': rsiMod,
    'is_box_return': isBoxReturn,
    'drop_height_cm': dropHeightCm,
  };

  factory DropJumpResult.fromMap(Map<String, dynamic> m) => DropJumpResult(
    testType: TestType.values[m['test_type'] as int? ?? 0],
    computedAt: DateTime.parse(m['computed_at'] as String? ?? DateTime.now().toIso8601String()),
    platformCount: m['platform_count'] as int? ?? 1,
    jumpHeightCm: (m['jump_height_cm'] as num?)?.toDouble() ?? 0.0,
    flightTimeMs: (m['flight_time_ms'] as num?)?.toDouble() ?? 0.0,
    peakForceN: (m['peak_force_n'] as num?)?.toDouble() ?? 0.0,
    meanForceN: (m['mean_force_n'] as num?)?.toDouble() ?? 0.0,
    bodyWeightN: (m['body_weight_n'] as num?)?.toDouble() ?? 0.0,
    propulsiveImpulseNs: (m['propulsive_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    brakingImpulseNs: (m['braking_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    takeoffForceN: (m['takeoff_force_n'] as num?)?.toDouble() ?? 0.0,
    rfdAt50ms: (m['rfd_50ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt100ms: (m['rfd_100ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt200ms: (m['rfd_200ms'] as num?)?.toDouble() ?? 0.0,
    timeToPeakForceMs: (m['time_to_peak_force_ms'] as num?)?.toDouble() ?? 0.0,
    eccentricDurationMs: (m['eccentric_duration_ms'] as num?)?.toDouble() ?? 0.0,
    concentricDurationMs: (m['concentric_duration_ms'] as num?)?.toDouble() ?? 0.0,
    peakPowerSayersW: (m['peak_power_sayers_w'] as num?)?.toDouble() ?? 0.0,
    peakPowerImpulseW: (m['peak_power_impulse_w'] as num?)?.toDouble() ?? 0.0,
    symmetry: m['symmetry'] is Map<String, dynamic>
        ? SymmetryResult.fromMap(m['symmetry'] as Map<String, dynamic>)
        : const SymmetryResult(leftPercent: 50, rightPercent: 50, asymmetryIndexPct: 0, isTwoPlatform: false),
    jumpHeightFlightTimeCm: (m['jump_height_ft_cm'] as num? ?? 0.0).toDouble(),
    landingPeakForceN: (m['landing_peak_force_n'] as num? ?? 0.0).toDouble(),
    contactTimeMs: (m['contact_time_ms'] as num?)?.toDouble() ?? 0.0,
    rsiMod: (m['rsi_mod'] as num?)?.toDouble() ?? 0.0,
    isBoxReturn: m['is_box_return'] as bool? ?? false,
    dropHeightCm: (m['drop_height_cm'] as num?)?.toDouble() ?? 0.0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Single jump data (for multi-jump)
// ─────────────────────────────────────────────────────────────────────────────

class SingleJumpData {
  final int jumpNumber;
  final double heightCm;
  final double contactTimeMs;
  final double flightTimeMs;
  final double rsiMod;
  const SingleJumpData({
    required this.jumpNumber,
    required this.heightCm,
    required this.contactTimeMs,
    required this.flightTimeMs,
    required this.rsiMod,
  });
  Map<String, dynamic> toMap() => {
    'n': jumpNumber,
    'h': heightCm,
    'ct': contactTimeMs,
    'ft': flightTimeMs,
    'rsi': rsiMod,
  };
  factory SingleJumpData.fromMap(Map<String, dynamic> m) => SingleJumpData(
    jumpNumber: m['n'] as int,
    heightCm: (m['h'] as num).toDouble(),
    contactTimeMs: (m['ct'] as num).toDouble(),
    flightTimeMs: (m['ft'] as num).toDouble(),
    rsiMod: (m['rsi'] as num).toDouble(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Multi-Jump / RSI Map
// ─────────────────────────────────────────────────────────────────────────────

class MultiJumpResult extends TestResult {
  final int jumpCount;
  final List<SingleJumpData> jumps;
  final double meanHeightCm;
  final double meanContactTimeMs;
  final double meanRsiMod;
  final double fatiguePercent;
  final double variabilityPercent;
  final double meanPowerW;

  const MultiJumpResult({
    super.sessionId,
    required super.computedAt,
    required super.platformCount,
    required this.jumpCount,
    required this.jumps,
    required this.meanHeightCm,
    required this.meanContactTimeMs,
    required this.meanRsiMod,
    required this.fatiguePercent,
    required this.variabilityPercent,
    required this.meanPowerW,
  }) : super(testType: TestType.multiJump);

  @override
  Map<String, dynamic> toMap() => {
    'test_type': testType.index,
    'computed_at': computedAt.toIso8601String(),
    'platform_count': platformCount,
    'jump_count': jumpCount,
    'jumps': jumps.map((j) => j.toMap()).toList(),
    'mean_height_cm': meanHeightCm,
    'mean_contact_time_ms': meanContactTimeMs,
    'mean_rsi_mod': meanRsiMod,
    'fatigue_pct': fatiguePercent,
    'variability_pct': variabilityPercent,
    'mean_power_w': meanPowerW,
  };

  factory MultiJumpResult.fromMap(Map<String, dynamic> m) => MultiJumpResult(
    computedAt: DateTime.parse(m['computed_at'] as String),
    platformCount: m['platform_count'] as int,
    jumpCount: m['jump_count'] as int,
    jumps: (m['jumps'] as List)
        .map((j) => SingleJumpData.fromMap(j as Map<String, dynamic>))
        .toList(),
    meanHeightCm: (m['mean_height_cm'] as num).toDouble(),
    meanContactTimeMs: (m['mean_contact_time_ms'] as num).toDouble(),
    meanRsiMod: (m['mean_rsi_mod'] as num).toDouble(),
    fatiguePercent: (m['fatigue_pct'] as num).toDouble(),
    variabilityPercent: (m['variability_pct'] as num).toDouble(),
    meanPowerW: (m['mean_power_w'] as num? ?? 0.0).toDouble(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CoP / Balance
// ─────────────────────────────────────────────────────────────────────────────

class CoPResult extends TestResult {
  final String condition;      // 'OA' (eyes open) or 'OC' (eyes closed)
  final String stance;         // 'bipedal', 'left', 'right'
  final double testDurationS;
  final double areaEllipseMm2;
  final double pathLengthMm;
  final double meanVelocityMmS;
  final double rangeMLMm;
  final double rangeAPMm;
  final double symmetryPercent;
  final double frequency95Hz;
  final double? rombergQuotient;

  const CoPResult({
    super.sessionId,
    required super.computedAt,
    required super.platformCount,
    required this.condition,
    required this.stance,
    required this.testDurationS,
    required this.areaEllipseMm2,
    required this.pathLengthMm,
    required this.meanVelocityMmS,
    required this.rangeMLMm,
    required this.rangeAPMm,
    required this.symmetryPercent,
    required this.frequency95Hz,
    this.rombergQuotient,
  }) : super(testType: TestType.cop);

  @override
  Map<String, dynamic> toMap() => {
    'test_type': testType.index,
    'computed_at': computedAt.toIso8601String(),
    'platform_count': platformCount,
    'condition': condition,
    'stance': stance,
    'test_duration_s': testDurationS,
    'area_ellipse_mm2': areaEllipseMm2,
    'path_length_mm': pathLengthMm,
    'mean_velocity_mms': meanVelocityMmS,
    'range_ml_mm': rangeMLMm,
    'range_ap_mm': rangeAPMm,
    'symmetry_pct': symmetryPercent,
    'frequency_95hz': frequency95Hz,
    'romberg_quotient': rombergQuotient,
  };

  factory CoPResult.fromMap(Map<String, dynamic> m) => CoPResult(
    computedAt: DateTime.parse(m['computed_at'] as String),
    platformCount: m['platform_count'] as int,
    condition: m['condition'] as String,
    stance: m['stance'] as String,
    testDurationS: (m['test_duration_s'] as num).toDouble(),
    areaEllipseMm2: (m['area_ellipse_mm2'] as num).toDouble(),
    pathLengthMm: (m['path_length_mm'] as num).toDouble(),
    meanVelocityMmS: (m['mean_velocity_mms'] as num).toDouble(),
    rangeMLMm: (m['range_ml_mm'] as num).toDouble(),
    rangeAPMm: (m['range_ap_mm'] as num).toDouble(),
    symmetryPercent: (m['symmetry_pct'] as num).toDouble(),
    frequency95Hz: (m['frequency_95hz'] as num).toDouble(),
    rombergQuotient: m['romberg_quotient'] != null
        ? (m['romberg_quotient'] as num).toDouble()
        : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// IMTP
// ─────────────────────────────────────────────────────────────────────────────

class ImtpResult extends TestResult {
  final double peakForceN;
  final double peakForceBW;
  final double netImpulseNs;
  final double rfdAt50ms;
  final double rfdAt100ms;
  final double rfdAt200ms;
  final double timeToPeakForceMs;
  final SymmetryResult symmetry;

  const ImtpResult({
    super.sessionId,
    required super.computedAt,
    required super.platformCount,
    required this.peakForceN,
    required this.peakForceBW,
    required this.netImpulseNs,
    required this.rfdAt50ms,
    required this.rfdAt100ms,
    required this.rfdAt200ms,
    required this.timeToPeakForceMs,
    required this.symmetry,
  }) : super(testType: TestType.imtp);

  @override
  Map<String, dynamic> toMap() => {
    'test_type': testType.index,
    'computed_at': computedAt.toIso8601String(),
    'platform_count': platformCount,
    'peak_force_n': peakForceN,
    'peak_force_bw': peakForceBW,
    'net_impulse_ns': netImpulseNs,
    'rfd_50ms': rfdAt50ms,
    'rfd_100ms': rfdAt100ms,
    'rfd_200ms': rfdAt200ms,
    'time_to_peak_ms': timeToPeakForceMs,
    'symmetry': symmetry.toMap(),
  };

  factory ImtpResult.fromMap(Map<String, dynamic> m) => ImtpResult(
    computedAt: DateTime.parse(m['computed_at'] as String? ?? DateTime.now().toIso8601String()),
    platformCount: m['platform_count'] as int? ?? 1,
    peakForceN: (m['peak_force_n'] as num?)?.toDouble() ?? 0.0,
    peakForceBW: (m['peak_force_bw'] as num?)?.toDouble() ?? 0.0,
    netImpulseNs: (m['net_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    rfdAt50ms: (m['rfd_50ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt100ms: (m['rfd_100ms'] as num?)?.toDouble() ?? 0.0,
    rfdAt200ms: (m['rfd_200ms'] as num?)?.toDouble() ?? 0.0,
    timeToPeakForceMs: (m['time_to_peak_ms'] as num?)?.toDouble() ?? 0.0,
    symmetry: m['symmetry'] is Map<String, dynamic>
        ? SymmetryResult.fromMap(m['symmetry'] as Map<String, dynamic>)
        : const SymmetryResult(leftPercent: 50, rightPercent: 50, asymmetryIndexPct: 0, isTwoPlatform: false),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Free Test — open-ended test with generic metrics
// ─────────────────────────────────────────────────────────────────────────────

class FreeTestResult extends TestResult {
  final double peakForceN;
  final double meanForceN;
  final double durationS;
  final double totalImpulseNs;
  final double peakRfdNs;   // peak rate of force development (N/s)
  final SymmetryResult symmetry;
  final String label;       // user label (e.g. "squat", "press")

  const FreeTestResult({
    super.sessionId,
    super.testType = TestType.freeTest,
    required super.computedAt,
    required super.platformCount,
    required this.peakForceN,
    required this.meanForceN,
    required this.durationS,
    required this.totalImpulseNs,
    required this.peakRfdNs,
    required this.symmetry,
    this.label = '',
  });

  @override
  Map<String, dynamic> toMap() => {
    'type': 'freeTest',
    'test_type': TestType.freeTest.index,
    'computed_at': computedAt.toIso8601String(),
    'platform_count': platformCount,
    'peak_force_n': peakForceN,
    'mean_force_n': meanForceN,
    'duration_s': durationS,
    'total_impulse_ns': totalImpulseNs,
    'peak_rfd_ns': peakRfdNs,
    'symmetry': symmetry.toMap(),
    'label': label,
  };

  factory FreeTestResult.fromMap(Map<String, dynamic> m) => FreeTestResult(
    computedAt: DateTime.parse(m['computed_at'] as String? ?? DateTime.now().toIso8601String()),
    platformCount: m['platform_count'] as int? ?? 1,
    peakForceN: (m['peak_force_n'] as num?)?.toDouble() ?? 0.0,
    meanForceN: (m['mean_force_n'] as num?)?.toDouble() ?? 0.0,
    durationS: (m['duration_s'] as num?)?.toDouble() ?? 0.0,
    totalImpulseNs: (m['total_impulse_ns'] as num?)?.toDouble() ?? 0.0,
    peakRfdNs: (m['peak_rfd_ns'] as num?)?.toDouble() ?? 0.0,
    symmetry: m['symmetry'] is Map<String, dynamic>
        ? SymmetryResult.fromMap(m['symmetry'] as Map<String, dynamic>)
        : const SymmetryResult(leftPercent: 50, rightPercent: 50, asymmetryIndexPct: 0, isTwoPlatform: false),
    label: m['label'] as String? ?? '',
  );

  @override
  String toJson() => jsonEncode(toMap());
}
