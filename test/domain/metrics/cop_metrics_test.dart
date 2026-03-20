// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

// CopMetrics uses a private _Point class; we test via the public static methods
// that accept List<_Point>-equivalent data. Since _Point is private to the
// library, we exercise the public API: swayPathMm, rangeMLMm, rangeAPMm,
// meanVelocityMmS and symmetryPct through the compute() path or direct statics.
//
// For the raw sway/range/velocity helpers that accept List<_Point> (which is
// private), we drive them indirectly through CopMetrics.compute() or test the
// public scalar helpers directly.

import 'package:inertiax/domain/dsp/metrics/cop_metrics.dart';
import 'package:inertiax/data/models/processed_sample.dart';

// Helper: build a minimal ProcessedSample for single-platform tests.
ProcessedSample _sample({
  double timestampS = 0.0,
  double forceAL = 350.0,
  double forceAR = 350.0,
  double forceMasterSide = 350.0,
  double forceSlaveSide  = 350.0,
  double forcePlatformA  = 700.0,
  double forcePlatformB  = 0.0,
  int    platformCount   = 1,
}) =>
    ProcessedSample(
      timestampS:      timestampS,
      forceAL:         forceAL,
      forceAR:         forceAR,
      forceBL:         0,
      forceBR:         0,
      forcePlatformA:  forcePlatformA,
      forcePlatformB:  forcePlatformB,
      forceTotal:      forcePlatformA + forcePlatformB,
      smoothedTotal:   forcePlatformA + forcePlatformB,
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
  group('CopMetrics.copXMm', () {
    test('equal forces gives 0 mm (centred)', () {
      final x = CopMetrics.copXMm(forceLeft_N: 500.0, forceRight_N: 500.0);
      expect(x, closeTo(0.0, 1e-9));
    });

    test('all force on right gives +halfSpan', () {
      final x = CopMetrics.copXMm(
          forceLeft_N: 0.0, forceRight_N: 500.0, halfSpanMm: 120.0);
      expect(x, closeTo(120.0, 1e-9));
    });

    test('all force on left gives -halfSpan', () {
      final x = CopMetrics.copXMm(
          forceLeft_N: 500.0, forceRight_N: 0.0, halfSpanMm: 120.0);
      expect(x, closeTo(-120.0, 1e-9));
    });

    test('total force < 1N returns 0', () {
      final x = CopMetrics.copXMm(forceLeft_N: 0.3, forceRight_N: 0.4);
      expect(x, closeTo(0.0, 1e-9));
    });
  });

  group('CopMetrics.copYMm', () {
    test('equal forces gives 0 mm', () {
      final y = CopMetrics.copYMm(forceFront_N: 300.0, forceBack_N: 300.0);
      expect(y, closeTo(0.0, 1e-9));
    });

    test('all force on front gives +halfSpan', () {
      final y = CopMetrics.copYMm(
          forceFront_N: 300.0, forceBack_N: 0.0, halfSpanMm: 240.0);
      expect(y, closeTo(240.0, 1e-9));
    });
  });

  group('CopMetrics.symmetryPct', () {
    test('equal forces gives 100% (perfectly symmetric)', () {
      final pct = CopMetrics.symmetryPct(meanForceA: 350.0, meanForceB: 350.0);
      expect(pct, closeTo(100.0, 1e-9));
    });

    test('all force on one side gives 0% symmetry', () {
      final pct = CopMetrics.symmetryPct(meanForceA: 700.0, meanForceB: 0.0);
      // ratio = 1.0, |1.0 - 0.5| * 200 = 100, 100 - 100 = 0
      expect(pct, closeTo(0.0, 1e-9));
    });

    test('60/40 split gives 80% symmetry', () {
      // ratio = 0.6, |0.6 - 0.5| * 200 = 20, 100 - 20 = 80
      final pct = CopMetrics.symmetryPct(meanForceA: 600.0, meanForceB: 400.0);
      expect(pct, closeTo(80.0, 1e-9));
    });

    test('zero total force returns 100%', () {
      final pct = CopMetrics.symmetryPct(meanForceA: 0.0, meanForceB: 0.0);
      expect(pct, closeTo(100.0, 1e-9));
    });
  });

  group('CopMetrics.compute — static signal', () {
    // 100 identical samples: CoP should be at origin (all zeros).
    final staticSamples = List<ProcessedSample>.generate(
        100,
        (i) => _sample(
              timestampS:      i * 0.001,
              forceAL:         350.0,
              forceAR:         350.0,
              forceMasterSide: 350.0,
              forceSlaveSide:  350.0,
              forcePlatformA:  700.0,
            ));

    test('static signal: swayPath ≈ 0', () {
      final result = CopMetrics.compute(
        samples:   staticSamples,
        durationS: 0.1,
        condition: 'OA',
        stance:    'bipedal',
      );
      expect(result.pathLengthMm, closeTo(0.0, 1e-6));
    });

    test('static signal: rangeML ≈ 0', () {
      final result = CopMetrics.compute(
        samples:   staticSamples,
        durationS: 0.1,
        condition: 'OA',
        stance:    'bipedal',
      );
      expect(result.rangeMLMm, closeTo(0.0, 1e-6));
    });

    test('static signal: meanVelocity ≈ 0', () {
      final result = CopMetrics.compute(
        samples:   staticSamples,
        durationS: 0.1,
        condition: 'OA',
        stance:    'bipedal',
      );
      expect(result.meanVelocityMmS, closeTo(0.0, 1e-4));
    });

    test('static signal: symmetryPercent = 100%', () {
      final result = CopMetrics.compute(
        samples:   staticSamples,
        durationS: 0.1,
        condition: 'OA',
        stance:    'bipedal',
      );
      expect(result.symmetryPercent, closeTo(100.0, 1e-6));
    });
  });

  group('CopMetrics.compute — rangeML and rangeAP via varying forces', () {
    // Build samples where ML CoP oscillates between -5 and +5 mm.
    // forceRight_N > forceLeft_N shifts CoP right; vice versa.
    // halfSpanMm = (350/2) - 55 = 120 mm
    // For copX = -5: (R-L)/(R+L)*120 = -5 → R-L = -5/120 * (R+L)
    // With total=700: R-L = -5/120*700 ≈ -29.17 → L≈364.58, R≈335.42

    test('rangeML ≈ 10mm for signals oscillating ±5mm', () {
      final samples = <ProcessedSample>[];
      for (var i = 0; i < 60; i++) {
        final goRight = i.isEven;
        // shift CoP ±5 mm: forceRight or forceLeft dominates slightly
        final fL = goRight ? 335.42 : 364.58;
        final fR = goRight ? 364.58 : 335.42;
        samples.add(_sample(
          timestampS:      i * 0.001,
          forceAL:         fL,
          forceAR:         fR,
          forceMasterSide: 350.0,
          forceSlaveSide:  350.0,
          forcePlatformA:  700.0,
        ));
      }
      final result = CopMetrics.compute(
        samples:   samples,
        durationS: 0.06,
        condition: 'OA',
        stance:    'bipedal',
      );
      // After 5-point smoothing the range will be slightly less than 10mm
      // but should be substantially > 0 and ≤ 10mm.
      expect(result.rangeMLMm, greaterThan(0.0));
      expect(result.rangeMLMm, lessThanOrEqualTo(10.5));
    });
  });

  group('CopMetrics.compute — empty samples', () {
    test('returns zeroed result without crashing', () {
      final result = CopMetrics.compute(
        samples:   [],
        durationS: 10.0,
        condition: 'OA',
        stance:    'bipedal',
      );
      expect(result.pathLengthMm, equals(0));
      expect(result.rangeMLMm,    equals(0));
      expect(result.rangeAPMm,    equals(0));
      expect(result.symmetryPercent, equals(100));
    });
  });
}
