import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inertiax/presentation/providers/live_data_provider.dart';
import 'package:inertiax/domain/dsp/signal_processor.dart';
import 'package:inertiax/domain/entities/calibration_data.dart';
import 'package:inertiax/data/models/raw_sample.dart';

// Helper: build a Platform A RawSample.
RawSample _rawA({
  required int timestampUs,
  int adcMasterL = -100,
  int adcMasterR = -100,
  int adcSlaveL  = -100,
  int adcSlaveR  = -100,
}) =>
    RawSample(
      timestampUs:     timestampUs,
      platformId:      1,
      seqNum:          0,
      adcMasterL:      adcMasterL,
      adcMasterR:      adcMasterR,
      adcSlaveL:       adcSlaveL,
      adcSlaveR:       adcSlaveR,
      flags:           0,
      seqJump:         0,
      packetsLostTotal: 0,
    );

// Build a per-cell CalibrationData so the processor produces non-zero forces.
CalibrationData _testCal({double gain = 1.0}) => CalibrationData(
      name: 'test',
      mode: CalibrationMode.linear,
      coefficients: [1.0 / 9.81, 0.0],
      segments: [],
      cellOffsets: {
        'A_ML': 0.0, 'A_MR': 0.0, 'A_SL': 0.0, 'A_SR': 0.0,
      },
      cellGains: {
        'A_ML': gain, 'A_MR': gain, 'A_SL': gain, 'A_SR': gain,
      },
      cellPolarities: {},
      points: [],
      isActive: true,
      createdAt: DateTime.now(),
    );

void main() {
  group('LiveDataState initial values', () {
    test('default state has sensible zero values', () {
      const state = LiveDataState();
      expect(state.timeS,           isEmpty);
      expect(state.forceTotalN,     isEmpty);
      expect(state.currentForceN,   equals(0.0));
      expect(state.currentSmoothedN, equals(0.0));
      expect(state.platformCount,   equals(1));
      expect(state.leftPct,         equals(50.0));
      expect(state.rightPct,        equals(50.0));
      expect(state.samplesReceived, equals(0));
    });
  });

  group('LiveDataNotifier.onRawSample', () {
    late SignalProcessor processor;
    late LiveDataNotifier notifier;

    setUp(() {
      processor = SignalProcessor(_testCal(gain: 1.0));
      notifier  = LiveDataNotifier(processor);
    });

    test('samplesReceived increments after each processed sample', () {
      expect(notifier.state.samplesReceived, equals(0));
      notifier.onRawSample(_rawA(timestampUs: 1000000));
      expect(notifier.state.samplesReceived, equals(1));
      notifier.onRawSample(_rawA(timestampUs: 2000000));
      expect(notifier.state.samplesReceived, equals(2));
    });

    test('Platform B sample is ignored (samplesReceived stays 0)', () {
      final bSample = RawSample(
        timestampUs:     1000000,
        platformId:      2,
        seqNum:          0,
        adcMasterL:      -100,
        adcMasterR:      -100,
        adcSlaveL:       -100,
        adcSlaveR:       -100,
        flags:           0,
        seqJump:         0,
        packetsLostTotal: 0,
      );
      notifier.onRawSample(bSample);
      expect(notifier.state.samplesReceived, equals(0));
    });

    test('currentForceN is updated after processing a sample', () {
      // gain=1 → each cell = 100 N → total = 400 N
      notifier.onRawSample(_rawA(
          timestampUs: 1000000,
          adcMasterL: -100, adcMasterR: -100,
          adcSlaveL: -100,  adcSlaveR: -100));
      expect(notifier.state.currentForceN, closeTo(400.0, 1.0));
    });

    test('leftPct and rightPct sum to 100', () {
      notifier.onRawSample(_rawA(
          timestampUs: 1000000,
          adcMasterL: -150, adcMasterR: -150,
          adcSlaveL:  -50,  adcSlaveR:  -50));
      final sum = notifier.state.leftPct + notifier.state.rightPct;
      expect(sum, closeTo(100.0, 0.001));
    });

    test('currentRawSum is non-zero', () {
      notifier.onRawSample(_rawA(
          timestampUs: 1000000,
          adcMasterL: -100, adcMasterR: -100,
          adcSlaveL:  -100, adcSlaveR:  -100));
      expect(notifier.state.currentRawSum, greaterThan(0.0));
    });
  });

  group('LiveDataNotifier.reset', () {
    test('reset clears all accumulated data', () {
      final processor = SignalProcessor(_testCal(gain: 1.0));
      final notifier  = LiveDataNotifier(processor);

      // Add some samples
      for (var i = 0; i < 10; i++) {
        notifier.onRawSample(_rawA(timestampUs: (i + 1) * 1000000));
      }
      expect(notifier.state.samplesReceived, greaterThan(0));

      notifier.reset();
      expect(notifier.state.samplesReceived, equals(0));
      expect(notifier.state.currentForceN,   equals(0.0));
      expect(notifier.state.timeS,           isEmpty);
    });
  });

  group('LiveDataNotifier buffer capping', () {
    test('buffer does not grow beyond chartBufferSize (5000 samples)', () {
      final processor = SignalProcessor(_testCal(gain: 1.0));
      final notifier  = LiveDataNotifier(processor);

      // Send 5100 samples — the internal lists should be capped at 5000
      for (var i = 0; i < 5100; i++) {
        notifier.onRawSample(_rawA(timestampUs: (i + 1) * 1000));
      }
      expect(notifier.state.samplesReceived, equals(5100));
      // The time/force lists are updated every 33 samples; check the latest snapshot
      // is not longer than bufferSize=5000.
      if (notifier.state.timeS.isNotEmpty) {
        expect(notifier.state.timeS.length, lessThanOrEqualTo(5000));
      }
    });
  });

  group('LiveDataState cell-level forces', () {
    test('currentForceALN and currentForceARN are set', () {
      final processor = SignalProcessor(_testCal(gain: 1.0));
      final notifier  = LiveDataNotifier(processor);
      notifier.onRawSample(_rawA(
          timestampUs: 1000000,
          adcMasterL: -120, adcMasterR: -80,
          adcSlaveL:  -120, adcSlaveR:  -80));
      // gain=1: forceAL = masterL+slaveL = 120+120 = 240 N
      //         forceAR = masterR+slaveR =  80+ 80 = 160 N
      expect(notifier.state.currentForceALN, closeTo(240.0, 1.0));
      expect(notifier.state.currentForceARN, closeTo(160.0, 1.0));
    });
  });
}
