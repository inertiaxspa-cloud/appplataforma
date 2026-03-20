import 'package:flutter_test/flutter_test.dart';
import 'package:inertiax/domain/dsp/phase_detector.dart';
import 'package:inertiax/data/models/processed_sample.dart';
import 'package:inertiax/core/constants/physics_constants.dart';

// Helper: minimal ProcessedSample
ProcessedSample _ps({required double t, required double force}) =>
    ProcessedSample(
      timestampS:      t,
      forceAL:         force / 2,
      forceAR:         force / 2,
      forceBL:         0,
      forceBR:         0,
      forcePlatformA:  force,
      forcePlatformB:  0,
      forceTotal:      force,
      smoothedTotal:   force,   // PhaseDetector reads smoothedTotal
      forceMasterSide: force / 2,
      forceSlaveSide:  force / 2,
      rawSumA:         0,
      rawAML:          0,
      rawAMR:          0,
      rawASL:          0,
      rawASR:          0,
      platformCount:   1,
    );

// Drives the detector through the settling phase.
// Sends [nSamples] at [force] starting at timestamp [tStart] with [dt] spacing.
// settleDuration = 1.0s, so at 500Hz we need 500 samples per window.
// std must be < stdThreshold (10 N) and BW > 50 N to be accepted.
List<PhaseEvent?> _sendSamples(
  PhaseDetector detector, {
  required int n,
  required double force,
  required double tStart,
  double dt = 0.002, // 500 Hz
}) {
  final events = <PhaseEvent?>[];
  for (var i = 0; i < n; i++) {
    final event = detector.update(_ps(t: tStart + i * dt, force: force));
    events.add(event);
  }
  return events;
}

void main() {
  group('PhaseDetector initial state', () {
    test('starts in idle phase', () {
      final detector = PhaseDetector();
      expect(detector.phase, equals(JumpPhase.idle));
    });

    test('update() in idle returns null', () {
      final detector = PhaseDetector();
      final event = detector.update(_ps(t: 0.0, force: 700.0));
      expect(event, isNull);
    });
  });

  group('PhaseDetector settling → waiting', () {
    test('stable samples during settling emit idle→waiting event', () {
      final detector = PhaseDetector();
      detector.startSettling();
      expect(detector.phase, equals(JumpPhase.settling));

      // Send 600 samples (1.2s) at exactly 700N → std=0, mean=700 > 50
      // settleDuration = 1.0s; first window completes at sample 500 (0-indexed)
      const bw = 700.0;
      PhaseEvent? transitionEvent;
      for (var i = 0; i < 600; i++) {
        final ev = detector.update(_ps(t: i * 0.002, force: bw));
        if (ev != null) {
          transitionEvent = ev;
          break;
        }
      }
      expect(transitionEvent, isNotNull);
      expect(transitionEvent!.from, equals(JumpPhase.settling));
      expect(transitionEvent.to,   equals(JumpPhase.waiting));
      expect(transitionEvent.bodyWeightN, closeTo(bw, 1.0));
    });

    test('bodyWeightN is set after settling', () {
      final detector = PhaseDetector();
      detector.startSettling();
      for (var i = 0; i < 600; i++) {
        detector.update(_ps(t: i * 0.002, force: 650.0));
      }
      expect(detector.bodyWeightN, closeTo(650.0, 5.0));
    });
  });

  group('PhaseDetector waiting → descent', () {
    test('force drops below BW - threshold triggers descent', () {
      final detector = PhaseDetector();
      detector.startSettling();
      const bw = 700.0;
      // Settle first
      PhaseEvent? settlingEvent;
      for (var i = 0; i < 600; i++) {
        final ev = detector.update(_ps(t: i * 0.002, force: bw));
        if (ev != null) { settlingEvent = ev; break; }
      }
      expect(settlingEvent?.to, equals(JumpPhase.waiting));

      // After settling, force drops by > effectiveUnweightDelta (≥20N) below BW
      // effectiveUnweightDelta = max(5*std, 20) = 20 (std=0 after constant BW)
      const dropForce = bw - 100.0; // 100N below BW — well below any threshold
      PhaseEvent? descentEvent;
      for (var i = 0; i < 10; i++) {
        final ev = detector.update(
            _ps(t: 600 * 0.002 + i * 0.002, force: dropForce));
        if (ev != null) { descentEvent = ev; break; }
      }
      expect(descentEvent, isNotNull);
      expect(descentEvent!.from, equals(JumpPhase.waiting));
      expect(descentEvent.to,   equals(JumpPhase.descent));
    });
  });

  group('PhaseDetector descent → flight', () {
    test('10 consecutive near-zero samples trigger flight', () {
      final detector = PhaseDetector();
      detector.startSettling();
      const bw = 700.0;

      // Settle
      for (var i = 0; i < 600; i++) {
        detector.update(_ps(t: i * 0.002, force: bw));
        if (detector.phase == JumpPhase.waiting) break;
      }
      // Descend
      for (var i = 0; i < 5; i++) {
        detector.update(_ps(t: 1.2 + i * 0.002, force: bw - 200.0));
        if (detector.phase == JumpPhase.descent) break;
      }

      // The effective flight threshold = max(12% * BW, 20) = max(84, 20) = 84N
      // Send 15 samples at 10N (well below threshold) to trigger flight
      const airborneForce = 10.0;
      PhaseEvent? flightEvent;
      for (var i = 0; i < 20; i++) {
        final ev = detector.update(
            _ps(t: 1.21 + i * 0.001, force: airborneForce));
        if (ev != null && ev.to == JumpPhase.flight) {
          flightEvent = ev;
          break;
        }
      }
      expect(flightEvent, isNotNull);
      expect(flightEvent!.from, equals(JumpPhase.descent));
      expect(flightEvent.to,   equals(JumpPhase.flight));
    });
  });

  group('PhaseDetector flight → landed', () {
    test('12 consecutive high-force samples trigger landing', () {
      final detector = PhaseDetector();
      detector.startSettling();
      const bw = 700.0;

      // Run through full cycle to reach flight
      // Settle
      for (var i = 0; i < 600; i++) {
        detector.update(_ps(t: i * 0.002, force: bw));
        if (detector.phase == JumpPhase.waiting) break;
      }
      // Descend
      for (var i = 0; i < 5; i++) {
        detector.update(_ps(t: 1.2 + i * 0.002, force: bw - 200.0));
        if (detector.phase == JumpPhase.descent) break;
      }
      // Flight
      for (var i = 0; i < 20; i++) {
        detector.update(_ps(t: 1.21 + i * 0.001, force: 5.0));
        if (detector.phase == JumpPhase.flight) break;
      }

      // Now send high-force samples to trigger landing
      // effectiveLandThreshold = max(30% * 700, 50) = max(210, 50) = 210N
      const landForce = 500.0;
      PhaseEvent? landEvent;
      for (var i = 0; i < 20; i++) {
        final ev = detector.update(
            _ps(t: 1.25 + i * 0.001, force: landForce));
        if (ev != null && ev.to == JumpPhase.landed) {
          landEvent = ev;
          break;
        }
      }
      expect(landEvent, isNotNull);
      expect(landEvent!.from, equals(JumpPhase.flight));
      expect(landEvent.to,   equals(JumpPhase.landed));
    });
  });

  group('PhaseDetector reset', () {
    test('reset() returns to idle with zero bodyWeight', () {
      final detector = PhaseDetector();
      detector.startSettling();
      detector.reset();
      expect(detector.phase, equals(JumpPhase.idle));
      expect(detector.bodyWeightN, equals(0.0));
    });

    test('startSettling() clears previous settling data', () {
      final detector = PhaseDetector();
      detector.startSettling();
      // Partially settle
      detector.update(_ps(t: 0.0, force: 700.0));
      // Restart
      detector.startSettling();
      expect(detector.phase, equals(JumpPhase.settling));
    });
  });

  group('PhaseDetector flightTimeS', () {
    test('returns null before any jump completes', () {
      final detector = PhaseDetector();
      expect(detector.flightTimeS, isNull);
    });
  });
}
