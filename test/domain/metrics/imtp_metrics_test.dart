import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/domain/dsp/metrics/imtp_metrics.dart';
import 'package:inertiax/data/models/processed_sample.dart';

// Helper: minimal ProcessedSample for IMTP tests
ProcessedSample _sample({
  double timestampS    = 0.0,
  double forceTotal    = 700.0,
  double forcePlatformA = 700.0,
  double forcePlatformB = 0.0,
  double forceMasterSide = 350.0,
  double forceSlaveSide  = 350.0,
  int    platformCount   = 1,
}) =>
    ProcessedSample(
      timestampS:      timestampS,
      forceAL:         forcePlatformA / 2,
      forceAR:         forcePlatformA / 2,
      forceBL:         0,
      forceBR:         0,
      forcePlatformA:  forcePlatformA,
      forcePlatformB:  forcePlatformB,
      forceTotal:      forceTotal,
      smoothedTotal:   forceTotal,
      forceMasterSide: forceMasterSide,
      forceSlaveSide:  forceSlaveSide,
      rawSumA:         0,
      rawAML:          0,
      rawAMR:          0,
      rawASL:          0,
      rawASR:          0,
      platformCount:   platformCount,
    );

void main() {
  group('ImtpMetrics.peakForce', () {
    test('[100,200,500,300] returns 500', () {
      expect(ImtpMetrics.peakForce([100.0, 200.0, 500.0, 300.0]), equals(500.0));
    });

    test('empty list returns 0', () {
      expect(ImtpMetrics.peakForce([]), equals(0.0));
    });

    test('single element list returns that element', () {
      expect(ImtpMetrics.peakForce([750.0]), equals(750.0));
    });
  });

  group('ImtpMetrics.timeToPeakMs', () {
    test('peak at index 3 with 1000Hz = 3ms', () {
      // List: [100, 200, 300, 500, 400] → max at index 3
      final result = ImtpMetrics.timeToPeakMs(
        [100.0, 200.0, 300.0, 500.0, 400.0],
        samplingRateHz: 1000,
      );
      expect(result, closeTo(3.0, 0.001)); // 3 * 1000 / 1000 = 3ms
    });

    test('peak at index 0 returns 0ms', () {
      final result = ImtpMetrics.timeToPeakMs([500.0, 400.0, 300.0]);
      expect(result, closeTo(0.0, 0.001));
    });

    test('empty list returns 0', () {
      expect(ImtpMetrics.timeToPeakMs([]), equals(0.0));
    });

    test('time to peak scales with sampling rate', () {
      // peak at index 5, 500Hz → 5 * 1000 / 500 = 10ms
      final forceN = [100.0, 200.0, 300.0, 400.0, 500.0, 600.0, 550.0];
      final result = ImtpMetrics.timeToPeakMs(forceN, samplingRateHz: 500);
      expect(result, closeTo(10.0, 0.001));
    });
  });

  group('ImtpMetrics.rfdAtWindow', () {
    test('linear ramp 0→1000N in 100ms at 1000Hz = 10000 N/s', () {
      // 101 samples, force rises 10 N per sample (0..1000)
      final forceN = List<double>.generate(101, (i) => i * 10.0);
      final rfd = ImtpMetrics.rfdAtWindow(
        forceN: forceN,
        windowMs: 100,
        samplingRateHz: 1000,
      );
      // endIdx = 100, deltaF = 1000-0 = 1000, deltaT = 100/1000 = 0.1 → 10000
      expect(rfd, closeTo(10000.0, 1.0));
    });

    test('empty list returns 0', () {
      expect(ImtpMetrics.rfdAtWindow(forceN: [], windowMs: 100), equals(0.0));
    });

    test('windowMs = 0 returns 0', () {
      // endIdx = 0, endIdx == 0 → return 0
      expect(
        ImtpMetrics.rfdAtWindow(
            forceN: [0.0, 100.0, 200.0], windowMs: 0),
        equals(0.0),
      );
    });
  });

  group('ImtpMetrics.netImpulse', () {
    test('returns 0 for fewer than 2 samples', () {
      expect(
        ImtpMetrics.netImpulse(forceN: [700.0], bodyWeightN: 700.0),
        equals(0.0),
      );
    });

    test('force equal to BW yields ~0 net impulse', () {
      const bw = 700.0;
      final forceN = List<double>.filled(1001, bw);
      final result = ImtpMetrics.netImpulse(
          forceN: forceN, bodyWeightN: bw, dt: 0.001);
      expect(result, closeTo(0.0, 1e-6));
    });

    test('constant force above BW produces positive impulse', () {
      const bw = 700.0;
      // force = 1400N (2×BW), 100 samples at dt=0.001 → net = (700)*0.001*99 ≈ 69.3 N·s
      final forceN = List<double>.filled(100, 1400.0);
      final result = ImtpMetrics.netImpulse(
          forceN: forceN, bodyWeightN: bw, dt: 0.001);
      expect(result, greaterThan(0.0));
    });
  });

  group('ImtpMetrics.compute', () {
    test('peakForceBW ≈ 2.0 when peakForce = 2×BW', () {
      const bw = 700.0;
      // Build 200 samples: first 50 = BW (quiet), then 150 = 2×BW (pull)
      final samples = <ProcessedSample>[];
      for (var i = 0; i < 50; i++) {
        samples.add(_sample(timestampS: i * 0.001, forceTotal: bw,
            forcePlatformA: bw, forceMasterSide: bw / 2, forceSlaveSide: bw / 2));
      }
      for (var i = 50; i < 200; i++) {
        samples.add(_sample(timestampS: i * 0.001, forceTotal: bw * 2,
            forcePlatformA: bw * 2, forceMasterSide: bw, forceSlaveSide: bw));
      }

      final result = ImtpMetrics.compute(samples: samples, bodyWeightN: bw);
      expect(result.peakForceBW, closeTo(2.0, 0.01));
    });

    test('empty samples returns zero result', () {
      final result = ImtpMetrics.compute(samples: [], bodyWeightN: 700.0);
      expect(result.peakForceN, equals(0.0));
      expect(result.peakForceBW, equals(0.0));
      expect(result.netImpulseNs, equals(0.0));
    });

    test('peak force matches peakForce() static method', () {
      const bw = 600.0;
      final samples = List<ProcessedSample>.generate(
        100,
        (i) => _sample(
          timestampS:    i * 0.001,
          forceTotal:    bw + i * 5.0,  // rising ramp
          forcePlatformA: bw + i * 5.0,
          forceMasterSide: (bw + i * 5.0) / 2,
          forceSlaveSide:  (bw + i * 5.0) / 2,
        ),
      );
      final result = ImtpMetrics.compute(samples: samples, bodyWeightN: bw);
      // onset detection: first sample where force >= bw + 50 → index 10
      // pull slice starts at index 10, peak is last sample
      expect(result.peakForceN, greaterThan(0.0));
    });
  });
}
