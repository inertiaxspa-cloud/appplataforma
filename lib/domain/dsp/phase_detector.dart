import 'dart:math' as math;
import '../../core/constants/physics_constants.dart';
import '../../data/models/processed_sample.dart';

enum JumpPhase {
  idle,
  settling,     // measuring body weight (CMJ/SJ/IMTP/MultiJump)
  waiting,      // waiting for movement (CMJ/SJ)
  descent,      // eccentric phase
  flight,       // airborne
  landed,       // post-landing
  djWaiting,    // DJ: platform empty, waiting for drop impact
  djContact,    // DJ: ground contact (landing→takeoff)
}

/// Event emitted when a significant phase transition occurs.
class PhaseEvent {
  final JumpPhase from;
  final JumpPhase to;
  final double timestamp;
  final double? bodyWeightN;    // set on settling→waiting
  final double? takeoffForceN;  // set on descent→flight
  final double? landingForceN;  // set on flight→landed

  const PhaseEvent({
    required this.from,
    required this.to,
    required this.timestamp,
    this.bodyWeightN,
    this.takeoffForceN,
    this.landingForceN,
  });
}

/// Sample-by-sample state machine for jump phase detection.
class PhaseDetector {
  JumpPhase _phase = JumpPhase.idle;
  JumpPhase get phase => _phase;

  // ── Adaptive threshold control ───────────────────────────────────────────

  /// When true, the unweighting threshold is computed after settling as
  /// max(5 × bodyWeightStd, 20 N), adapting to each athlete's quiet-standing
  /// variability (Owen et al., 2014).
  /// When false, the fixed 80 N threshold from [PhysicsConstants] is used.
  bool useAdaptiveThreshold = true;

  // Effective unweighting delta, computed after settling.
  double _effectiveUnweightDelta = PhysicsConstants.cmjWeightThreshold;

  // Dynamic flight/landing thresholds — recalculated after settling as % BW.
  double _effectiveFlightThreshold = 20.0;  // se recalcula tras settling
  double _effectiveLandThreshold   = 50.0;  // se recalcula tras settling

  // Debounce counters
  int _consecutiveFlightSamples = 0;
  int _consecutiveLandSamples   = 0;
  static const int _minFlightSamples = 10;
  static const int _minLandSamples   = 12;

  // Settling / body weight estimation
  final List<double> _settlingSamples = [];
  double? _settleStartTime;
  double bodyWeightN = 0;
  double bodyWeightStd = 0;
  int _settleAttempts = 0;
  static const int _maxSettleAttempts = 5; // ~5s max before forcing acceptance

  // Phase timestamps
  double? _descentStartTime;
  double? _takeoffTime;
  double? _landingTime;

  // Fixed thresholds
  static const double _settleDuration = PhysicsConstants.settleDurationS;
  static const double _stdOk          = PhysicsConstants.stdThreshold;

  // DJ-specific: impact detection threshold (empty platform → first contact)
  static const double _djImpactThreshold = 20.0; // N — any force above = impact
  double? _djContactStartTime;  // timestamp of first impact

  /// Feed a processed sample. Returns a [PhaseEvent] on transition, else null.
  PhaseEvent? update(ProcessedSample sample) {
    final t = sample.timestampS;
    // C9 fix: clamp negative forces to 0 — calibration errors or ADC drift
    // can produce slightly negative values that corrupt settling and thresholds.
    final f = sample.smoothedTotal < 0 ? 0.0 : sample.smoothedTotal;

    switch (_phase) {
      case JumpPhase.idle:
        return null;

      case JumpPhase.settling:
        _settlingSamples.add(f);
        if (_settleStartTime == null) _settleStartTime = t;
        if (t - _settleStartTime! >= _settleDuration) {
          bodyWeightN   = _mean(_settlingSamples);
          bodyWeightStd = _std(_settlingSamples);
          _settleAttempts++;
          final forceAccept = _settleAttempts >= _maxSettleAttempts;
          if ((bodyWeightStd < _stdOk && bodyWeightN > 50) ||
              (forceAccept && bodyWeightN > 50)) {
            // Accepted: either stable enough or max attempts reached.
            _effectiveUnweightDelta = useAdaptiveThreshold
                // Adaptive: 5×SD with a meaningful floor.
                // Floor = max(30 N, 2.5% BW) so quiet-standing micro-shifts
                // (which the 50 Hz filter suppresses to <5 N RMS) never
                // accidentally trigger descent detection.
                ? math.max(5.0 * bodyWeightStd,
                    math.max(30.0, bodyWeightN * 0.025))
                : PhysicsConstants.cmjWeightThreshold;   // fixed: 80 N

            // Compute dynamic flight/landing thresholds as % of body weight.
            _effectiveFlightThreshold = math.max(
                bodyWeightN * PhysicsConstants.flightThresholdFactor, 20.0);
            _effectiveLandThreshold = math.max(
                bodyWeightN * PhysicsConstants.landingThresholdFactor, 50.0);

            return _transition(JumpPhase.waiting, t, bodyWeightN: bodyWeightN);
          } else {
            // Athlete not stable yet — restart window.
            _settlingSamples.clear();
            _settleStartTime = t;
          }
        }
        return null;

      case JumpPhase.waiting:
        if (f < bodyWeightN - _effectiveUnweightDelta) {
          _descentStartTime = t;
          return _transition(JumpPhase.descent, t);
        }
        return null;

      case JumpPhase.descent:
        if (f < _effectiveFlightThreshold) {
          _consecutiveFlightSamples++;
          if (_consecutiveFlightSamples >= _minFlightSamples) {
            _consecutiveFlightSamples = 0;
            return _transition(JumpPhase.flight, t, takeoffForceN: f);
          }
        } else {
          _consecutiveFlightSamples = 0;
        }
        return null;

      case JumpPhase.flight:
        if (f > _effectiveLandThreshold) {
          _consecutiveLandSamples++;
          if (_consecutiveLandSamples >= _minLandSamples) {
            _consecutiveLandSamples = 0;
            return _transition(JumpPhase.landed, t, landingForceN: f);
          }
        } else {
          _consecutiveLandSamples = 0;
        }
        return null;

      case JumpPhase.landed:
        return null;

      // ── DROP JUMP specific phases ───────────────────────────────────────
      // DJ starts with empty platform. Athlete drops from a box.
      // Sequence: djWaiting → djContact → flight → landed

      case JumpPhase.djWaiting:
        // Platform is empty (~0 N). Wait for first impact (force > threshold).
        // Use a fixed 20 N threshold — any force above this is an impact.
        if (f > _djImpactThreshold) {
          _consecutiveLandSamples++;
          if (_consecutiveLandSamples >= 3) { // 3 ms debounce for impact
            _consecutiveLandSamples = 0;
            _descentStartTime = t; // marks the start of ground contact
            return _transition(JumpPhase.djContact, t, landingForceN: f);
          }
        } else {
          _consecutiveLandSamples = 0;
        }
        return null;

      case JumpPhase.djContact:
        // Ground contact phase: athlete absorbs landing + pushes off.
        // Ends when force drops below flight threshold for 10 samples (takeoff).
        if (f < _effectiveFlightThreshold) {
          _consecutiveFlightSamples++;
          if (_consecutiveFlightSamples >= _minFlightSamples) {
            _consecutiveFlightSamples = 0;
            return _transition(JumpPhase.flight, t, takeoffForceN: f);
          }
        } else {
          _consecutiveFlightSamples = 0;
        }
        return null;
    }
  }

  PhaseEvent _transition(JumpPhase to, double t, {
    double? bodyWeightN,
    double? takeoffForceN,
    double? landingForceN,
  }) {
    final from = _phase;
    _phase = to;
    if (to == JumpPhase.djContact) _djContactStartTime = t;
    if (to == JumpPhase.flight) _takeoffTime = t;
    if (to == JumpPhase.landed) _landingTime = t;
    return PhaseEvent(
      from: from,
      to: to,
      timestamp: t,
      bodyWeightN: bodyWeightN,
      takeoffForceN: takeoffForceN,
      landingForceN: landingForceN,
    );
  }

  void startSettling() {
    _phase = JumpPhase.settling;
    _settlingSamples.clear();
    _settleStartTime = null;
    _settleAttempts = 0;
  }

  /// Start DJ mode: platform is empty, waiting for the athlete to drop from a box.
  /// [athleteBwN] is the body weight from the athlete profile (used for thresholds).
  void startDjWaiting({required double athleteBwN}) {
    _phase = JumpPhase.djWaiting;
    bodyWeightN = athleteBwN;
    bodyWeightStd = 0;
    _djContactStartTime = null;
    _descentStartTime = null;
    _takeoffTime = null;
    _landingTime = null;
    _consecutiveFlightSamples = 0;
    _consecutiveLandSamples = 0;

    // Set thresholds based on athlete's known BW.
    _effectiveFlightThreshold = math.max(athleteBwN * 0.05, 20.0);
    _effectiveLandThreshold   = math.max(athleteBwN * 0.20, 50.0);
  }

  /// After a multi-jump landing, reset to waiting while keeping bodyWeight.
  void resetToWaiting() {
    _phase = JumpPhase.waiting;
    _descentStartTime = null;
    _takeoffTime = null;
    _landingTime = null;
    _consecutiveFlightSamples = 0;
    _consecutiveLandSamples = 0;
  }

  void reset() {
    _phase = JumpPhase.idle;
    _settlingSamples.clear();
    _settleStartTime = null;
    _settleAttempts = 0;
    _descentStartTime = null;
    _takeoffTime = null;
    _landingTime = null;
    _djContactStartTime = null;
    bodyWeightN = 0;
    bodyWeightStd = 0;
    _effectiveUnweightDelta = PhysicsConstants.cmjWeightThreshold;
    _consecutiveFlightSamples = 0;
    _consecutiveLandSamples = 0;
    _effectiveFlightThreshold = 20.0;
    _effectiveLandThreshold = 50.0;
  }

  double? get flightTimeS {
    if (_takeoffTime == null || _landingTime == null) return null;
    return _landingTime! - _takeoffTime!;
  }

  double? get eccentricDurationS =>
      _descentStartTime != null && _takeoffTime != null
          ? _takeoffTime! - _descentStartTime!
          : null;

  double? get descentStartTime    => _descentStartTime;
  double? get takeoffTime         => _takeoffTime;
  double? get landingTime         => _landingTime;
  double? get djContactStartTime  => _djContactStartTime;

  /// DJ ground contact time: first impact → takeoff (seconds).
  double? get djContactTimeS {
    if (_djContactStartTime == null || _takeoffTime == null) return null;
    return _takeoffTime! - _djContactStartTime!;
  }

  /// Effective unweighting threshold in use (N below body weight).
  double get effectiveUnweightDeltaN => _effectiveUnweightDelta;

  /// Effective flight threshold (N). Force below this = airborne.
  double get effectiveFlightThresholdN => _effectiveFlightThreshold;

  static double _mean(List<double> v) {
    if (v.isEmpty) return 0;
    return v.fold(0.0, (s, x) => s + x) / v.length;
  }

  static double _std(List<double> v) {
    if (v.length < 2) return 0;
    final m = _mean(v);
    final variance =
        v.fold(0.0, (s, x) => s + (x - m) * (x - m)) / (v.length - 1);
    return math.sqrt(variance);
  }
}
