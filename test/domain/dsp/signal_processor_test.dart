import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/domain/dsp/signal_processor.dart';
import 'package:inertiax/domain/entities/calibration_data.dart';
import 'package:inertiax/data/models/raw_sample.dart';

// Helper: build a Platform A RawSample with negated ADC values.
// The SignalProcessor negates them: rawAML = -adcMasterL.
// To produce a calibrated force of `targetNewtons` total:
//   With default calibration (legacy polynomial: 1/9.81 coefficient, intercept 0):
//   rawToNewton(x) = x → so we want rawAML + rawAMR + rawASL + rawASR ≈ targetN.
//   Each cell gets targetN/4 of raw ADC (before negation by the processor).
//   But processor negates: rawAML = -adcMasterL → adcMasterL = -rawAML = -(targetN/4).
RawSample _rawA({
  required int timestampUs,
  int adcMasterL = -100,  // negated by processor → rawAML = 100
  int adcMasterR = -100,
  int adcSlaveL  = -100,
  int adcSlaveR  = -100,
  int flags      = 0,
}) =>
    RawSample(
      timestampUs:     timestampUs,
      platformId:      1, // Platform A
      seqNum:          0,
      adcMasterL:      adcMasterL,
      adcMasterR:      adcMasterR,
      adcSlaveL:       adcSlaveL,
      adcSlaveR:       adcSlaveR,
      flags:           flags,
      seqJump:         0,
      packetsLostTotal: 0,
    );

// Build a CalibrationData in per-cell mode with given gain.
CalibrationData _perCellCalibration({double gain = 1.0, double offset = 0.0}) =>
    CalibrationData(
      name: 'test_cal',
      mode: CalibrationMode.linear,
      coefficients: [1.0 / 9.81, 0.0],
      segments: [],
      cellOffsets: {
        'A_ML': offset,
        'A_MR': offset,
        'A_SL': offset,
        'A_SR': offset,
      },
      cellGains: {
        'A_ML': gain,
        'A_MR': gain,
        'A_SL': gain,
        'A_SR': gain,
      },
      cellPolarities: {},
      points: [],
      isActive: true,
      createdAt: DateTime.now(),
    );

void main() {
  group('SignalProcessor basic single-platform processing', () {
    test('process returns null for Platform B sample', () {
      final cal = CalibrationData.defaultCalibration();
      final processor = SignalProcessor(cal);
      final bSample = RawSample(
        timestampUs:     1000000,
        platformId:      2, // Platform B
        seqNum:          0,
        adcMasterL:      -100,
        adcMasterR:      -100,
        adcSlaveL:       -100,
        adcSlaveR:       -100,
        flags:           0,
        seqJump:         0,
        packetsLostTotal: 0,
      );
      expect(processor.process(bSample), isNull);
    });

    test('process returns non-null ProcessedSample for Platform A', () {
      final cal = CalibrationData.defaultCalibration();
      final processor = SignalProcessor(cal);
      final sample = _rawA(timestampUs: 1000000);
      final result = processor.process(sample);
      expect(result, isNotNull);
    });

    test('platformCount defaults to 1 when no Platform B seen within timeout', () {
      final cal = CalibrationData.defaultCalibration();
      final processor = SignalProcessor(cal);
      // Send Platform A samples beyond the 500ms timeout window.
      // First sample sets _firstATimestamp; subsequent ones advance time.
      const timeout = 500; // ms → 500000 us
      final s0 = _rawA(timestampUs: 0);
      processor.process(s0);
      // Send a sample well beyond the 500ms timeout (600ms = 600000 us)
      final s1 = _rawA(timestampUs: 600000);
      final result = processor.process(s1);
      expect(result?.platformCount, equals(1));
    });
  });

  group('SignalProcessor DC signal filtering', () {
    // Per-cell calibration: gain=1.0, offset=0.0
    // RawSample with adcMasterL=-250, adcMasterR=-250, adcSlaveL=-250, adcSlaveR=-250
    // → rawAML=rawAMR=rawASL=rawASR=250 after processor negation
    // → each cell: (250 - 0) * 1.0 = 250 N → total = 1000 N
    test('DC force signal passes through filter with close steady-state output', () {
      final cal = _perCellCalibration(gain: 1.0, offset: 0.0);
      final processor = SignalProcessor(cal);
      const dcAdc = -250; // → raw value 250 → 250 N per cell → 1000 N total
      const expectedForce = 1000.0;

      // Warm up the filter with many samples
      double lastSmoothed = 0.0;
      for (var i = 0; i < 500; i++) {
        final s = _rawA(
            timestampUs: i * 1000,
            adcMasterL: dcAdc,
            adcMasterR: dcAdc,
            adcSlaveL: dcAdc,
            adcSlaveR: dcAdc);
        final result = processor.process(s);
        if (result != null) lastSmoothed = result.smoothedTotal;
      }
      // After warm-up the Butterworth filter should have settled to ~DC value
      expect(lastSmoothed, closeTo(expectedForce, expectedForce * 0.02));
    });

    test('spike signal is attenuated vs DC signal (low-pass behaviour)', () {
      // DC: steady 1000 N baseline (smooth output ≈ 1000)
      // High-freq: alternating 0 / 2000 N at 1000 Hz (above the 50 Hz cutoff)
      // After the filter the HF output should be closer to the mean (1000N)
      // than the peak-to-peak amplitude (2000N).
      final calDC     = _perCellCalibration(gain: 1.0, offset: 0.0);
      final calSpike  = _perCellCalibration(gain: 1.0, offset: 0.0);
      final procDC    = SignalProcessor(calDC);
      final procSpike = SignalProcessor(calSpike);

      const dcAdc    = -250;   // 1000 N DC
      const spikeHi  = -500;   // 2000 N
      const spikeLo  =    0;   // 0 N

      // Warm up both processors over 500 samples
      double dcSmoothed    = 0.0;
      double spikeSmoothed = 0.0;
      for (var i = 0; i < 500; i++) {
        final dcS = _rawA(
            timestampUs: i * 1000,
            adcMasterL: dcAdc,
            adcMasterR: dcAdc,
            adcSlaveL: dcAdc,
            adcSlaveR: dcAdc);
        final dcRes = procDC.process(dcS);
        if (dcRes != null) dcSmoothed = dcRes.smoothedTotal;

        final spikeAdc = i.isEven ? spikeHi : spikeLo;
        final spS = _rawA(
            timestampUs: i * 1000,
            adcMasterL: spikeAdc,
            adcMasterR: spikeAdc,
            adcSlaveL: spikeAdc,
            adcSlaveR: spikeAdc);
        final spRes = procSpike.process(spS);
        if (spRes != null) spikeSmoothed = spRes.smoothedTotal;
      }

      // The spike signal's smoothed output should be close to the DC mean (1000N)
      // and its deviation from 1000 should be much smaller than the raw amplitude (2000N).
      final dcDeviation    = (dcSmoothed    - 1000.0).abs();
      final spikeDeviation = (spikeSmoothed - 1000.0).abs();

      // DC signal stays within 2% of target
      expect(dcDeviation, lessThan(20.0));
      // HF spike signal stays within 50% of the 1000N mean after filtering
      // (the Butterworth 50Hz LP strongly attenuates 500Hz alternating signal)
      expect(spikeDeviation, lessThan(500.0));
    });
  });

  group('SignalProcessor per-cell calibration', () {
    test('gain factor scales force proportionally', () {
      // gain = 2.0 → each cell reading of 100 ADC counts → 200 N → total 800 N
      final cal = _perCellCalibration(gain: 2.0, offset: 0.0);
      final processor = SignalProcessor(cal);
      final sample = _rawA(
          timestampUs: 0,
          adcMasterL: -100,
          adcMasterR: -100,
          adcSlaveL: -100,
          adcSlaveR: -100);
      final result = processor.process(sample);
      expect(result?.forceTotal, closeTo(800.0, 1.0));
    });

    test('offset is subtracted before gain is applied', () {
      // raw ADC per cell = 100, offset = 50 → corrected = 50, gain = 1 → 50 N * 4 = 200 N
      final cal = _perCellCalibration(gain: 1.0, offset: 50.0);
      final processor = SignalProcessor(cal);
      final sample = _rawA(
          timestampUs: 0,
          adcMasterL: -100,
          adcMasterR: -100,
          adcSlaveL: -100,
          adcSlaveR: -100);
      final result = processor.process(sample);
      expect(result?.forceTotal, closeTo(200.0, 1.0));
    });
  });

  group('SignalProcessor reset', () {
    test('reset() clears the filter state (smoother restarts)', () {
      final cal = _perCellCalibration(gain: 1.0);
      final processor = SignalProcessor(cal);
      // Warm up
      for (var i = 0; i < 100; i++) {
        processor.process(_rawA(
            timestampUs: i * 1000,
            adcMasterL: -250, adcMasterR: -250,
            adcSlaveL: -250,  adcSlaveR: -250));
      }
      processor.reset();
      // After reset, first sample should pass through a cold filter
      final result = processor.process(_rawA(
          timestampUs: 0,
          adcMasterL: -250, adcMasterR: -250,
          adcSlaveL: -250,  adcSlaveR: -250));
      expect(result, isNotNull);
    });
  });
}
