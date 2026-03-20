import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/domain/dsp/metrics/jump_metrics.dart';
import 'package:inertiax/core/constants/physics_constants.dart';

void main() {
  const double g = PhysicsConstants.gravity; // 9.81 m/s²

  group('JumpMetrics.jumpHeightFromFlightTime', () {
    test('600ms flight time yields ~44.1 cm', () {
      const flightTimeS = 0.6;
      final height = JumpMetrics.jumpHeightFromFlightTime(flightTimeS);
      // h = 0.125 * 9.81 * 0.6² = 0.125 * 9.81 * 0.36 ≈ 0.4414 m = 44.14 cm
      expect(height, closeTo(0.4414, 0.002));
    });

    test('zero flight time returns 0', () {
      expect(JumpMetrics.jumpHeightFromFlightTime(0.0), equals(0.0));
    });

    test('negative flight time returns 0 (squared makes it positive)', () {
      // (-0.6)^2 = 0.36 → still positive height; formula doesn't guard negatives
      final height = JumpMetrics.jumpHeightFromFlightTime(-0.6);
      expect(height, closeTo(0.4414, 0.002));
    });
  });

  group('JumpMetrics.velocityFromForce', () {
    test('empty forceN list returns list of zeros', () {
      final result = JumpMetrics.velocityFromForce(
        forceN: [],
        timeS: [],
        bodyWeightN: 700.0,
      );
      expect(result, isEmpty);
    });

    test('zero bodyWeightN returns all-zeros list', () {
      final result = JumpMetrics.velocityFromForce(
        forceN: [800.0, 850.0, 900.0],
        timeS: [0.0, 0.001, 0.002],
        bodyWeightN: 0.0,
      );
      expect(result, everyElement(equals(0.0)));
    });

    test('constant force equal to BW yields zero velocity (no net impulse)', () {
      const bw = 700.0;
      final forceN = List<double>.filled(101, bw);
      final timeS = List<double>.generate(101, (i) => i * 0.001);
      final vel = JumpMetrics.velocityFromForce(
        forceN: forceN,
        timeS: timeS,
        bodyWeightN: bw,
      );
      for (final v in vel) {
        expect(v, closeTo(0.0, 1e-9));
      }
    });
  });

  group('JumpMetrics.rfdAtWindow', () {
    test('linear ramp 0→1000N in 100ms yields ~10000 N/s', () {
      // 101 samples at 1ms spacing: force goes linearly from 0 to 1000 N
      const n = 101;
      final forceN = List<double>.generate(n, (i) => i * 10.0); // 0,10,...,1000
      final timeS  = List<double>.generate(n, (i) => i * 0.001);

      final rfd = JumpMetrics.rfdAtWindow(
        forceN: forceN,
        timeS: timeS,
        onsetIdx: 0,
        windowS: 0.1, // 100ms
      );
      // At 100ms, forceN[100] = 1000, forceN[0] = 0, dt = 0.1s → RFD = 10000 N/s
      expect(rfd, closeTo(10000.0, 1.0));
    });

    test('onsetIdx beyond list returns 0', () {
      final rfd = JumpMetrics.rfdAtWindow(
        forceN: [100.0, 200.0],
        timeS: [0.0, 0.001],
        onsetIdx: 5,
        windowS: 0.1,
      );
      expect(rfd, equals(0.0));
    });
  });

  group('JumpMetrics.fatiguePercent', () {
    test('[40,42,41, 35,34,36] yields ~14% fatigue', () {
      // first3 mean = (40+42+41)/3 = 41.0
      // last3 mean  = (35+34+36)/3 = 35.0
      // fatigue = (41 - 35) / 41 * 100 ≈ 14.63%
      final result = JumpMetrics.fatiguePercent([40, 42, 41, 35, 34, 36]);
      expect(result, closeTo(14.63, 0.1));
    });

    test('fewer than 6 values returns 0', () {
      expect(JumpMetrics.fatiguePercent([40.0, 42.0, 41.0]), equals(0.0));
    });

    test('identical heights yields 0% fatigue', () {
      expect(JumpMetrics.fatiguePercent([40.0, 40.0, 40.0, 40.0, 40.0, 40.0]),
          closeTo(0.0, 1e-9));
    });
  });

  group('JumpMetrics.elasticityIndex', () {
    test('CMJ=42cm SJ=35cm yields ~20%', () {
      // (42 - 35) / 35 * 100 = 20.0%
      final result = JumpMetrics.elasticityIndex(
        cmjHeightCm: 42.0,
        sjHeightCm: 35.0,
      );
      expect(result, closeTo(20.0, 0.01));
    });

    test('sjHeightCm=0 returns 0', () {
      expect(JumpMetrics.elasticityIndex(cmjHeightCm: 42.0, sjHeightCm: 0.0),
          equals(0.0));
    });

    test('equal heights yields 0%', () {
      expect(JumpMetrics.elasticityIndex(cmjHeightCm: 35.0, sjHeightCm: 35.0),
          closeTo(0.0, 1e-9));
    });
  });

  group('JumpMetrics.symmetry2Platform', () {
    test('500N vs 500N yields 50/50 split and 0% asymmetry', () {
      final result = JumpMetrics.symmetry2Platform(
        totalPlatformAN: 500.0,
        totalPlatformBN: 500.0,
      );
      expect(result.leftPercent, closeTo(50.0, 0.001));
      expect(result.rightPercent, closeTo(50.0, 0.001));
      expect(result.asymmetryIndexPct, closeTo(0.0, 0.001));
      expect(result.isTwoPlatform, isTrue);
    });

    test('600N vs 400N yields ~20% asymmetry index (|left% - 50|)', () {
      // total = 1000, leftPct = 60%, asymIdx = |60-50| = 10%
      final result = JumpMetrics.symmetry2Platform(
        totalPlatformAN: 600.0,
        totalPlatformBN: 400.0,
      );
      expect(result.leftPercent, closeTo(60.0, 0.001));
      expect(result.rightPercent, closeTo(40.0, 0.001));
      expect(result.asymmetryIndexPct, closeTo(10.0, 0.001));
    });

    test('600N vs 400N with LSI = true yields ~(1-40/60)*100 ≈ 33.3%', () {
      final result = JumpMetrics.symmetry2Platform(
        totalPlatformAN: 600.0,
        totalPlatformBN: 400.0,
        useLsi: true,
      );
      // LSI = (1 - min/max) * 100 = (1 - 40/60) * 100 ≈ 33.33%
      expect(result.asymmetryIndexPct, closeTo(33.33, 0.1));
    });

    test('zero total force returns 50/50 default', () {
      final result = JumpMetrics.symmetry2Platform(
        totalPlatformAN: 0.0,
        totalPlatformBN: 0.0,
      );
      expect(result.leftPercent, equals(50.0));
      expect(result.rightPercent, equals(50.0));
    });
  });

  group('JumpMetrics.peakPowerFromImpulse', () {
    test('returns positive value with positive force and velocity', () {
      final forceN    = [500.0, 700.0, 900.0, 800.0, 600.0];
      final velocityMS = [0.1,  0.3,  0.5,  0.6,   0.4];
      final result = JumpMetrics.peakPowerFromImpulse(
        forceN: forceN,
        velocityMS: velocityMS,
        startIdx: 0,
        endIdx: 4,
      );
      // max(F*v): 500*0.1=50, 700*0.3=210, 900*0.5=450, 800*0.6=480, 600*0.4=240
      expect(result, closeTo(480.0, 0.001));
    });

    test('empty range returns 0', () {
      final result = JumpMetrics.peakPowerFromImpulse(
        forceN: [500.0, 700.0],
        velocityMS: [0.1, 0.3],
        startIdx: 0,
        endIdx: -1, // endIdx < startIdx → loop never executes
      );
      expect(result, equals(0.0));
    });
  });

  group('JumpMetrics.jumpHeightFromImpulse', () {
    test('returns non-negative height with valid data', () {
      // Simulate a simple propulsive phase: 100 samples, force = 2*BW
      const bw = 700.0;
      const n = 100;
      final forceN = List<double>.filled(n, bw * 2.0);
      final timeS  = List<double>.generate(n, (i) => i * 0.001);
      final height = JumpMetrics.jumpHeightFromImpulse(
        forceN: forceN,
        timeS: timeS,
        bodyWeightN: bw,
        startIdx: 0,
        takeoffIdx: n - 1,
      );
      expect(height, greaterThanOrEqualTo(0.0));
    });

    test('takeoffIdx <= startIdx returns 0', () {
      final height = JumpMetrics.jumpHeightFromImpulse(
        forceN: [700.0, 700.0],
        timeS: [0.0, 0.001],
        bodyWeightN: 700.0,
        startIdx: 1,
        takeoffIdx: 0,
      );
      expect(height, equals(0.0));
    });
  });
}
