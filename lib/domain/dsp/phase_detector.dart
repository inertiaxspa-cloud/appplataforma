import 'dart:math' as math;
import '../../core/constants/physics_constants.dart';
import '../../data/models/processed_sample.dart';

enum JumpPhase {
  idle,
  settling,     // measuring body weight
  waiting,      // waiting for movement (CMJ/DJ)
  descent,      // eccentric phase
  flight,       // airborne
  landed,       // post-landing
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

  /// Feed a processed sample. Returns a [PhaseEvent] on transition, else null.
  PhaseEvent? update(ProcessedSample sample) {
    final t = sample.timestampS;
    final f = sample.smoothedTotal;

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
                ? math.max(5.0 * bodyWeightStd, 20.0)   // floor: 20 N
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
    }
  }

  PhaseEvent _transition(JumpPhase to, double t, {
    double? bodyWeightN,
    double? takeoffForceN,
    double? landingForceN,
  }) {
    final from = _phase;
    _phase = to;
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

  double? get descentStartTime => _descentStartTime;
  double? get takeoffTime      => _takeoffTime;
  double? get landingTime      => _landingTime;

  /// Effective unweighting threshold in use (N below body weight).
  double get effectiveUnweightDeltaN => _effectiveUnweightDelta;

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
