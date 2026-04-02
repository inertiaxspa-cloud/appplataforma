import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/algorithm_settings.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/services/sound_service.dart';
import '../../data/datasources/local/database_helper.dart';
import '../../data/models/processed_sample.dart';
import '../../data/models/raw_sample.dart';
import '../../domain/dsp/butterworth_filter.dart';
import '../../domain/dsp/phase_detector.dart';
import '../../domain/dsp/metrics/jump_metrics.dart';
import '../../domain/dsp/signal_processor.dart';
import '../../domain/entities/calibration_data.dart';
import '../../domain/entities/test_result.dart';
import 'athlete_provider.dart';
import 'connection_provider.dart';
import 'calibration_provider.dart';
import 'live_data_provider.dart';
import '../screens/history/history_screen.dart';
import '../screens/settings/settings_screen.dart';

// ── Test state ─────────────────────────────────────────────────────────────

enum TestStatus { idle, settling, running, completed, failed }

class TestState {
  final TestType? testType;
  final TestStatus status;
  final JumpPhase phase;
  final double? bodyWeightN;
  final double elapsedSeconds;
  final String statusMessage;
  final TestResult? result;
  final String? error;

  const TestState({
    this.testType,
    this.status   = TestStatus.idle,
    this.phase    = JumpPhase.idle,
    this.bodyWeightN,
    this.elapsedSeconds = 0,
    this.statusMessage  = 'Listo',
    this.result,
    this.error,
  });

  TestState copyWith({
    TestType? testType,
    TestStatus? status,
    JumpPhase? phase,
    double? bodyWeightN,
    double? elapsedSeconds,
    String? statusMessage,
    TestResult? result,
    String? error,
  }) => TestState(
    testType:      testType      ?? this.testType,
    status:        status        ?? this.status,
    phase:         phase         ?? this.phase,
    bodyWeightN:   bodyWeightN   ?? this.bodyWeightN,
    elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
    statusMessage: statusMessage ?? this.statusMessage,
    result:        result        ?? this.result,
    error:         error,
  );

  bool get isActive =>
      status == TestStatus.settling || status == TestStatus.running;
}

// ── Test state notifier ────────────────────────────────────────────────────

class TestStateNotifier extends StateNotifier<TestState> {
  final Ref _ref;
  final PhaseDetector _phaseDetector = PhaseDetector();

  // Recorded data for metric calculation.
  final List<double> _forceData       = [];
  final List<double> _timeData        = [];
  final List<double> _forceAData      = [];
  final List<double> _forceBData      = [];
  // 1-platform symmetry: master board side vs slave board side (Platform A)
  // Symmetry fix: accumulate left/right column forces (not master/slave board).
  final List<double> _forceLeftData  = [];
  final List<double> _forceRightData = [];

  // Multi-jump tracking.
  final List<SingleJumpData> _jumps = [];
  double _mjContactStart = 0;
  int _platformCount = 1;

  ProviderSubscription<AsyncValue<RawSample>>? _rawSub;
  SignalProcessor? _processor;
  Timer? _postLandingTimer;

  TestStateNotifier(this._ref) : super(const TestState());

  Future<void> startTest(TestType type) async {
    final athlete = _ref.read(selectedAthleteProvider);
    if (athlete?.id == null) {
      state = TestState(
        testType: type,
        status: TestStatus.failed,
        error: AppStrings.get('select_athlete_first'),
      );
      return;
    }

    final cal = _ref.read(calibrationProvider).activeCalibration
        ?? CalibrationData.defaultCalibration();
    _processor = SignalProcessor(cal);

    // Pre-warm the Butterworth filter with the athlete's current body-weight
    // force from the live display. This eliminates the cold-start transient
    // (filter starts at 0 instead of BW) that corrupts the impulse-momentum
    // integral and causes grossly underestimated jump heights on Android.
    final currentForce = _ref.read(liveDataProvider).currentSmoothedN;
    if (currentForce > 50) _processor!.prewarmFilter(currentForce);

    // Apply algorithm settings to phase detector.
    final settings = _ref.read(settingsProvider);
    _phaseDetector.useAdaptiveThreshold = settings.useAdaptiveUnweight;

    _forceData.clear(); _timeData.clear();
    _forceAData.clear(); _forceBData.clear();
    _forceLeftData.clear(); _forceRightData.clear();
    _jumps.clear();
    _mjContactStart = 0;
    _phaseDetector.reset();

    // DJ uses a completely different protocol: platform starts EMPTY.
    // Athlete stands on a box, drops onto the platform, rebounds, lands.
    // BW comes from the athlete profile, not from settling.
    if (type == TestType.dropJump) {
      final athlete = _ref.read(selectedAthleteProvider);
      final bwKg = athlete?.bodyWeightKg ?? 0;
      final bwN = bwKg * 9.81;
      if (bwN < 50) {
        state = TestState(
          testType: type,
          status: TestStatus.failed,
          error: AppStrings.get('dj_configure_weight'),
        );
        return;
      }
      _phaseDetector.startDjWaiting(athleteBwN: bwN);
      if (settings.soundFeedback) SoundService.countdown();
      state = TestState(
        testType:      type,
        status:        TestStatus.running,
        phase:         JumpPhase.djWaiting,
        bodyWeightN:   bwN,
        statusMessage: AppStrings.get('dj_waiting_message'),
      );
    } else {
      _phaseDetector.startSettling();
      if (settings.soundFeedback) SoundService.countdown();
      state = TestState(
        testType:      type,
        status:        TestStatus.settling,
        phase:         JumpPhase.settling,
        statusMessage: 'Mídete quieto sobre la plataforma...',
      );
    }

    _rawSub?.close();
    _rawSub = _ref.listen<AsyncValue<RawSample>>(rawSampleStreamProvider,
        (_, next) {
          next.whenData(_onRawSample);
          // Si se pierde la conexión durante el test, marcarlo como fallido
          // en lugar de dejarlo congelado en estado 'running'.
          // A9 fix: also detect connection loss during settling (was: only running).
          if (next is AsyncError && (state.status == TestStatus.running || state.status == TestStatus.settling)) {
            state = state.copyWith(
              status: TestStatus.failed,
              statusMessage: 'Conexión perdida. Reconecta el dispositivo.',
            );
            _rawSub?.close();
            _rawSub = null;
          }
        });
  }

  void _onRawSample(RawSample raw) {
    final processor = _processor;
    if (processor == null) return;

    final processed = processor.process(raw);
    if (processed == null) return;

    _platformCount = processed.platformCount;
    final event = _phaseDetector.update(processed);

    if (state.status == TestStatus.settling ||
        state.status == TestStatus.running) {
      _forceData.add(processed.smoothedTotal);
      _timeData.add(processed.timestampS);
      _forceAData.add(processed.forcePlatformA);
      _forceBData.add(processed.forcePlatformB);
      // Symmetry: left column (masterL+slaveL), right column (masterR+slaveR)
      _forceLeftData.add(processed.forceAL);
      _forceRightData.add(processed.forceAR);
    }

    if (event != null) _handlePhaseEvent(event, processed);
  }

  void _handlePhaseEvent(PhaseEvent event, ProcessedSample processed) {
    switch (event.to) {
      case JumpPhase.waiting:
        _mjContactStart = processed.timestampS;
        if (_ref.read(settingsProvider).soundFeedback) SoundService.ready();
        state = state.copyWith(
          status:        TestStatus.running,
          phase:         JumpPhase.waiting,
          bodyWeightN:   event.bodyWeightN,
          statusMessage: state.testType == TestType.imtp
              ? 'Listo — tira con fuerza máxima'
              : 'Listo — realiza el salto',
        );

      case JumpPhase.descent:
        state = state.copyWith(
          phase:         JumpPhase.descent,
          statusMessage: 'Descendiendo...',
        );

      case JumpPhase.flight:
        if (_ref.read(settingsProvider).soundFeedback) SoundService.phase();
        HapticFeedback.mediumImpact();
        state = state.copyWith(
          phase:         JumpPhase.flight,
          statusMessage: '¡En vuelo!',
        );

      case JumpPhase.landed:
        // C10 fix: ignore duplicate landing events if already processing.
        if (state.phase == JumpPhase.landed) return;
        HapticFeedback.heavyImpact();
        if (state.testType == TestType.multiJump) {
          _recordMultiJump(processed);
        } else {
          // Wait 3 seconds of post-landing data before finishing (CMJ / SJ / DJ).
          final platformCount = processed.platformCount;
          state = state.copyWith(
            phase:         JumpPhase.landed,
            statusMessage: 'Aterrizando...',
          );
          _postLandingTimer?.cancel();
          _postLandingTimer = Timer(const Duration(seconds: 3), () {
            _computeAndFinish(platformCount);
          });
        }

      // ── DJ-specific phases ──────────────────────────────────────────────
      case JumpPhase.djWaiting:
        // Should not transition TO djWaiting via event, only via startDjWaiting.
        break;

      case JumpPhase.djContact:
        // Athlete has landed on platform from the box drop.
        if (_ref.read(settingsProvider).soundFeedback) SoundService.phase();
        HapticFeedback.heavyImpact();
        state = state.copyWith(
          phase:         JumpPhase.djContact,
          statusMessage: AppStrings.get('dj_contact_message'),
        );

      default:
        break;
    }
  }

  // ── MultiJump: record one jump and continue ──────────────────────────────

  void _recordMultiJump(ProcessedSample processed) {
    final takeoffT    = _phaseDetector.takeoffTime;
    final flightTimeS = _phaseDetector.flightTimeS ?? 0;

    double contactTimeMs = 200;
    if (takeoffT != null && _mjContactStart > 0) {
      contactTimeMs =
          ((takeoffT - _mjContactStart) * 1000).clamp(50.0, 5000.0);
    }

    final heightM  = JumpMetrics.jumpHeightFromFlightTime(flightTimeS);
    final heightCm = heightM * 100;
    final rsiMod   = contactTimeMs > 0 ? heightM / (contactTimeMs / 1000) : 0.0;

    _jumps.add(SingleJumpData(
      jumpNumber:    _jumps.length + 1,
      heightCm:      heightCm,
      contactTimeMs: contactTimeMs,
      flightTimeMs:  flightTimeS * 1000,
      rsiMod:        rsiMod,
    ));

    _mjContactStart = processed.timestampS;
    _phaseDetector.resetToWaiting();

    state = state.copyWith(
      phase:         JumpPhase.waiting,
      statusMessage: '${_jumps.length} salto(s) — continúa',
      result:        _buildMultiJumpResult(),
    );
  }

  MultiJumpResult _buildMultiJumpResult() {
    if (_jumps.isEmpty) {
      return MultiJumpResult(
        computedAt: DateTime.now(), platformCount: _platformCount,
        jumpCount: 0, jumps: const [],
        meanHeightCm: 0, meanContactTimeMs: 0, meanRsiMod: 0,
        fatiguePercent: 0, variabilityPercent: 0,
        meanPowerW: 0.0,
      );
    }
    final n      = _jumps.length;
    final meanH  = _jumps.fold(0.0, (s, j) => s + j.heightCm) / n;
    final meanCT = _jumps.fold(0.0, (s, j) => s + j.contactTimeMs) / n;
    final meanRS = _jumps.fold(0.0, (s, j) => s + j.rsiMod) / n;

    double fatigue = 0;
    if (n >= 3) {
      final k     = (n / 3).ceil();
      final first = _jumps.take(k).map((j) => j.heightCm).toList();
      final last  = _jumps.skip(n - k).map((j) => j.heightCm).toList();
      final fMean = first.fold(0.0, (s, v) => s + v) / first.length;
      final lMean = last.fold(0.0, (s, v) => s + v) / last.length;
      fatigue = fMean > 0
          ? ((fMean - lMean) / fMean * 100).clamp(0.0, 100.0)
          : 0;
    }
    double variability = 0;
    if (n >= 2) {
      final variance = _jumps.fold(
              0.0, (s, j) => s + (j.heightCm - meanH) * (j.heightCm - meanH)) /
          n;
      final sd = _sqrt(variance);
      variability = meanH > 0 ? (sd / meanH * 100) : 0;
    }

    return MultiJumpResult(
      computedAt: DateTime.now(), platformCount: _platformCount,
      jumpCount: n, jumps: List.unmodifiable(_jumps),
      meanHeightCm: meanH, meanContactTimeMs: meanCT, meanRsiMod: meanRS,
      fatiguePercent: fatigue, variabilityPercent: variability,
      meanPowerW: 0.0,
    );
  }

  // ── CMJ / SJ / DJ finish ─────────────────────────────────────────────────

  void _computeAndFinish(int platformCount) {
    _rawSub?.close();
    _rawSub = null;

    // C6 fix: CoP results are computed in cop_screen.dart, not here.
    if (state.testType == TestType.cop) return;

    if (_forceData.isEmpty || _timeData.isEmpty) {
      if (_ref.read(settingsProvider).soundFeedback) SoundService.error();
      state = state.copyWith(
          status: TestStatus.failed, error: 'Sin datos suficientes');
      return;
    }

    final settings = _ref.read(settingsProvider);
    final bwN      = _phaseDetector.bodyWeightN;

    // Validate body weight was properly detected during settling phase.
    if (bwN < 50) {
      if (settings.soundFeedback) SoundService.error();
      state = state.copyWith(
        status: TestStatus.failed,
        error: 'Peso corporal no detectado. Repite el test sobre la plataforma.',
      );
      return;
    }
    final bwKg     = bwN / 9.81;
    final useLsi   = settings.useLsiSymmetry;

    // ── Zero-phase filter for all metric computations ─────────────────────
    // ButterworthFilter.filtfilt: 4th-order LP 50 Hz, forward+backward pass.
    // Eliminates phase distortion, greatly improves RFD and velocity accuracy.
    // Phase-detection indices (_descentIdx, _takeoffIdx) remain valid because
    // filtfilt preserves array length.
    final forceFiltered = ButterworthFilter.filtfilt(_forceData);
    if (forceFiltered.isEmpty) {
      if (settings.soundFeedback) SoundService.error();
      state = state.copyWith(
        status: TestStatus.failed,
        error: 'Filtrado produjo datos vacíos. Repite el test.',
      );
      return;
    }

    // ── Flight-time height (always computed — used for MultiJump and as fallback)
    final flightTimeS = _phaseDetector.flightTimeS ?? 0;
    final heightFlightM  = JumpMetrics.jumpHeightFromFlightTime(flightTimeS);

    // ── Phase indices into force arrays ───────────────────────────────────
    final descentT = _phaseDetector.descentStartTime;
    final takeoffT = _phaseDetector.takeoffTime;

    // descentIdx: first sample at/after descent start.
    int descentIdx = 0;
    if (descentT != null) {
      for (int i = 0; i < _timeData.length; i++) {
        if (_timeData[i] >= descentT) { descentIdx = i; break; }
      }
    }

    // roughTakeoffIdx: the sample the phase detector labelled "takeoff".
    // NOTE: the phase detector fires AFTER a 10-sample debounce, so this index
    // is 10 ms into the flight phase (force ≈ 0–20 N). Do NOT use it directly
    // as the takeoff boundary for metric computations.
    int roughTakeoffIdx = forceFiltered.length - 1;
    if (takeoffT != null) {
      for (int i = _timeData.length - 1; i >= 0; i--) {
        if (_timeData[i] <= takeoffT) { roughTakeoffIdx = i; break; }
      }
    }

    // ── STEP 1 — Propulsive peak: global max in [descentIdx, roughTakeoffIdx]
    // This must come FIRST because the 10-sample debounce means roughTakeoffIdx
    // is already in the flight phase (force ≈ 0), making any minimum-first
    // search land in the flight region and corrupt every subsequent index.
    int peakForceIdx = descentIdx;
    double peakF = forceFiltered.isNotEmpty ? forceFiltered[descentIdx] : 0.0;
    for (int i = descentIdx + 1; i <= roughTakeoffIdx && i < forceFiltered.length; i++) {
      if (forceFiltered[i] > peakF) { peakF = forceFiltered[i]; peakForceIdx = i; }
    }
    // Sanity: if propulsive peak is implausibly low (< 50% BW) fall back to
    // the global maximum of the whole recording (excludes nothing from noise).
    if (peakF < bwN * 0.5 && forceFiltered.isNotEmpty) {
      peakF = forceFiltered.reduce((a, b) => a > b ? a : b);
    }

    // ── STEP 2 — True takeoff: last sample ABOVE flight threshold after peak
    // Walk forward from peakForceIdx; takeoffIdx is the last sample ≥ threshold.
    final flightThr = _phaseDetector.effectiveFlightThresholdN;
    int takeoffIdx = peakForceIdx; // conservative: at least at the peak
    for (int i = peakForceIdx; i <= roughTakeoffIdx && i < forceFiltered.length; i++) {
      if (forceFiltered[i] >= flightThr) takeoffIdx = i;
    }

    // ── STEP 3 — Squat bottom: minimum in [descentIdx, peakForceIdx]
    // Searching only up to peakForceIdx prevents the flight-phase near-zero
    // from being selected as the "minimum" (which was the root cause of
    // peakForce = 19 N and concentricDuration = 0 ms).
    int minIdx = descentIdx;
    double minF = forceFiltered.isNotEmpty ? forceFiltered[descentIdx] : 0.0;
    for (int i = descentIdx + 1; i <= peakForceIdx && i < forceFiltered.length; i++) {
      if (forceFiltered[i] < minF) { minF = forceFiltered[i]; minIdx = i; }
    }

    // ── Impulse-momentum height ───────────────────────────────────────────
    // v = 0 at startIdx = 0 (beginning of settling, athlete at rest).
    // Use the corrected takeoffIdx (last above-threshold sample, not debounced).
    final heightImpulseM = JumpMetrics.jumpHeightFromImpulse(
      forceN:      forceFiltered,
      timeS:       _timeData,
      bodyWeightN: bwN,
      startIdx:    0,
      takeoffIdx:  takeoffIdx,
    );

    // Sanity check: impulse height must be plausible vs. flight-time height.
    // If impulse gives <60% of flight-time height (and we had a real jump),
    // the integration is suspect — fall back to flight-time unconditionally.
    // (60% threshold: normal impulse vs flight-time difference is <15%.)
    final bool impulseIsPlausible = flightTimeS < 0.10 ||
        (heightFlightM <= 0) ||
        (heightImpulseM >= heightFlightM * 0.60);

    final double heightM  = (settings.useImpulseHeight && impulseIsPlausible)
        ? heightImpulseM
        : heightFlightM;
    final double heightCm = heightM * 100;

    // ── Peak / mean force ─────────────────────────────────────────────────
    final peakForceN = peakF;
    // Mean force over the concentric phase only [minIdx, takeoffIdx].
    double meanForceN = 0;
    if (takeoffIdx > minIdx) {
      double sum = 0;
      for (int i = minIdx; i <= takeoffIdx && i < forceFiltered.length; i++) {
        sum += forceFiltered[i];
      }
      meanForceN = sum / (takeoffIdx - minIdx + 1);
    }

    // ── RFD / TTP: onset = first sample past minIdx exceeding BW + 20 N ──
    int onsetIdx = minIdx;
    for (int i = minIdx; i <= takeoffIdx && i < forceFiltered.length; i++) {
      if (forceFiltered[i] > bwN + 20) { onsetIdx = i; break; }
    }
    final rfd50  = JumpMetrics.rfdAtWindow(
        forceN: forceFiltered, timeS: _timeData,
        onsetIdx: onsetIdx, windowS: 0.05);
    final rfd100 = JumpMetrics.rfdAtWindow(
        forceN: forceFiltered, timeS: _timeData,
        onsetIdx: onsetIdx, windowS: 0.10);
    final rfd200 = JumpMetrics.rfdAtWindow(
        forceN: forceFiltered, timeS: _timeData,
        onsetIdx: onsetIdx, windowS: 0.20);
    // TTP: onset → propulsive peak (NOT global max, which could be landing spike)
    final ttp = (onsetIdx < peakForceIdx && peakForceIdx < _timeData.length)
        ? (_timeData[peakForceIdx] - _timeData[onsetIdx]) * 1000
        : 0.0;

    // ── Peak power ────────────────────────────────────────────────────────
    // Velocity signal (needed for impulse-based power).
    final velSignal = JumpMetrics.velocityFromForce(
      forceN:      forceFiltered,
      timeS:       _timeData,
      bodyWeightN: bwN,
      startIdx:    0,
    );
    final peakPowerImpulse = JumpMetrics.peakPowerFromImpulse(
      forceN:     forceFiltered,
      velocityMS: velSignal,
      startIdx:   minIdx,
      endIdx:     takeoffIdx,
    );

    // Regression power: always Sayers or Harman — never impulseBased here.
    // peakPowerSayersW and peakPowerImpulseW are stored independently so
    // the PDF can always show both rows with their correct values.
    final double peakPowerRegression = settings.algo.peakPower == PeakPowerMethod.harman
        ? JumpMetrics.peakPowerHarman(heightCm, bwKg)
        : JumpMetrics.peakPowerSayers(heightCm, bwKg);

    // ── Braking / propulsive impulse ──────────────────────────────────────
    final dt = _timeData.length > 1
        ? (_timeData.last - _timeData.first) / (_timeData.length - 1)
        : 0.001;
    double brakingImpulse = 0, propulsiveImpulse = 0;
    for (int i = descentIdx; i <= minIdx && i < forceFiltered.length; i++) {
      final net = bwN - forceFiltered[i];
      if (net > 0) brakingImpulse += net * dt;
    }
    for (int i = minIdx; i <= takeoffIdx && i < forceFiltered.length; i++) {
      final net = forceFiltered[i] - bwN;
      if (net > 0) propulsiveImpulse += net * dt;
    }

    final concentricMs = (minIdx < takeoffIdx && takeoffIdx < _timeData.length)
        ? (_timeData[takeoffIdx] - _timeData[minIdx]) * 1000
        : 0.0;
    // True eccentric = descent onset → bottom of squat (minIdx).
    // _phaseDetector.eccentricDurationS = descentStart → takeoff (ecc + con combined),
    // so derive it from the data array indices instead for accuracy.
    final eccentric = (descentIdx < minIdx && minIdx < _timeData.length)
        ? _timeData[minIdx] - _timeData[descentIdx]
        : (_phaseDetector.eccentricDurationS ?? 0);

    // ── Symmetry ──────────────────────────────────────────────────────────
    final totalA = _forceAData.isEmpty
        ? 0.0
        : _forceAData.fold(0.0, (s, f) => s + f) / _forceAData.length;
    final totalB = _forceBData.isEmpty
        ? 0.0
        : _forceBData.fold(0.0, (s, f) => s + f) / _forceBData.length;

    final symmetry = platformCount >= 2
        ? JumpMetrics.symmetry2Platform(
            totalPlatformAN: totalA, totalPlatformBN: totalB, useLsi: useLsi)
        // Symmetry fix: use actual L/R column data (not master/slave board).
        : JumpMetrics.symmetry1Platform(
            masterSideN: _forceLeftData.isEmpty ? 0.0
                : _forceLeftData.fold(0.0, (s, f) => s + f) / _forceLeftData.length,
            slaveSideN: _forceRightData.isEmpty ? 0.0
                : _forceRightData.fold(0.0, (s, f) => s + f) / _forceRightData.length,
            useLsi: useLsi);

    _rawSub?.close();
    final testType = state.testType ?? TestType.cmj;

    if (testType == TestType.dropJump) {
      // DJ uses real ground contact time (impact → takeoff) from phase detector,
      // NOT eccentric duration (which is meaningless for DJ).
      final djContactS = _phaseDetector.djContactTimeS;
      if (djContactS == null) {
        if (settings.soundFeedback) SoundService.error();
        state = state.copyWith(
          status: TestStatus.failed,
          error: AppStrings.get('dj_no_contact'),
        );
        return;
      }
      final contactMs = (djContactS * 1000).clamp(50.0, 2000.0);
      final rsi = heightM > 0 && contactMs > 0
          ? heightM / (contactMs / 1000)
          : 0.0;

      // Peak landing force: the maximum force during the contact phase.
      // For DJ, peak force during contact IS the peak landing force.
      final peakLandingForceN = peakForceN;

      state = state.copyWith(
        status: TestStatus.completed,
        phase:  JumpPhase.landed,
        result: DropJumpResult(
          testType: testType, computedAt: DateTime.now(),
          platformCount: platformCount,
          jumpHeightCm: heightCm, flightTimeMs: flightTimeS * 1000,
          peakForceN: peakForceN, meanForceN: meanForceN,
          bodyWeightN: bwN,
          propulsiveImpulseNs: propulsiveImpulse,
          brakingImpulseNs:    brakingImpulse,
          takeoffForceN: peakForceN,
          rfdAt50ms: rfd50, rfdAt100ms: rfd100, rfdAt200ms: rfd200,
          timeToPeakForceMs: ttp,
          eccentricDurationMs: eccentric * 1000,
          concentricDurationMs: concentricMs,
          peakPowerSayersW:  peakPowerRegression,
          peakPowerImpulseW: peakPowerImpulse,
          symmetry: symmetry,
          jumpHeightFlightTimeCm: heightFlightM * 100,
          landingPeakForceN: peakLandingForceN,
          contactTimeMs: contactMs, rsiMod: rsi,
        ),
        statusMessage: AppStrings.get('dj_completed'),
      );
      if (settings.soundFeedback) SoundService.success();
      _autoSaveResult(state.result);
      return;
    }

    if (settings.soundFeedback) SoundService.success();
    state = state.copyWith(
      status: TestStatus.completed,
      phase:  JumpPhase.landed,
      result: JumpResult(
        testType: testType, computedAt: DateTime.now(),
        platformCount: platformCount,
        jumpHeightCm: heightCm, flightTimeMs: flightTimeS * 1000,
        peakForceN: peakForceN, meanForceN: meanForceN,
        bodyWeightN: bwN,
        propulsiveImpulseNs: propulsiveImpulse,
        brakingImpulseNs:    brakingImpulse,
        takeoffForceN: peakForceN,
        rfdAt50ms: rfd50, rfdAt100ms: rfd100, rfdAt200ms: rfd200,
        timeToPeakForceMs: ttp,
        eccentricDurationMs:  eccentric * 1000,
        concentricDurationMs: concentricMs,
        peakPowerSayersW:  peakPowerRegression,
        peakPowerImpulseW: peakPowerImpulse,
        symmetry: symmetry,
        jumpHeightFlightTimeCm: heightFlightM * 100,
        landingPeakForceN: 0.0,
      ),
      statusMessage: 'Salto completado',
    );
    _autoSaveResult(state.result);
  }

  // ── finishTest: called by IMTP and MultiJump "Done" buttons ──────────────

  void finishTest() {
    _postLandingTimer?.cancel();
    _postLandingTimer = null;
    _rawSub?.close();
    final type = state.testType;
    if (type == TestType.imtp) {
      _computeImtp();
    } else if (type == TestType.multiJump && _jumps.isNotEmpty) {
      if (_ref.read(settingsProvider).soundFeedback) SoundService.success();
      state = state.copyWith(
        status:        TestStatus.completed,
        result:        _buildMultiJumpResult(),
        statusMessage: 'Multi-salto completado',
      );
      _autoSaveResult(state.result);
    } else {
      state = const TestState();
    }
  }

  void _computeImtp() {
    final settings = _ref.read(settingsProvider);
    final bwN      = _phaseDetector.bodyWeightN;
    final bwStd    = _phaseDetector.bodyWeightStd;
    final useLsi   = settings.useLsiSymmetry;

    if (_forceData.isEmpty) {
      state = state.copyWith(status: TestStatus.failed, error: 'Sin datos');
      return;
    }

    // Zero-phase filter before metric computation (improves RFD accuracy).
    final forceFiltered = ButterworthFilter.filtfilt(_forceData);

    // Onset detection: fixed (BW + 50 N) or statistical (BW + 5×SD_baseline).
    final onsetThreshold = settings.useStatImtpOnset
        ? bwN + 5.0 * bwStd
        : bwN + 50.0;

    int onsetIdx = 0;
    for (int i = 0; i < forceFiltered.length; i++) {
      if (forceFiltered[i] > onsetThreshold) { onsetIdx = i; break; }
    }

    final pullForce = forceFiltered.sublist(onsetIdx);
    final pullTime  = _timeData.sublist(onsetIdx);

    if (pullForce.isEmpty) {
      state = state.copyWith(
          status: TestStatus.failed, error: 'Sin tirón detectado');
      return;
    }

    final peakForce = pullForce.reduce((a, b) => a > b ? a : b);
    final rfd50     = JumpMetrics.rfdAtWindow(
        forceN: pullForce, timeS: pullTime, onsetIdx: 0, windowS: 0.05);
    final rfd100    = JumpMetrics.rfdAtWindow(
        forceN: pullForce, timeS: pullTime, onsetIdx: 0, windowS: 0.10);
    final rfd200    = JumpMetrics.rfdAtWindow(
        forceN: pullForce, timeS: pullTime, onsetIdx: 0, windowS: 0.20);
    final ttp       = JumpMetrics.timeToPeakForce(
        forceN: pullForce, timeS: pullTime, startIdx: 0);

    final dt = pullTime.length > 1
        ? (pullTime.last - pullTime.first) / (pullTime.length - 1)
        : 0.001;
    double impulse = 0;
    for (final f in pullForce) {
      final net = f - bwN;
      if (net > 0) impulse += net * dt;
    }

    // Symmetry from a window around peak force (more robust than single sample).
    int peakIdx = 0;
    double peakVal = pullForce[0];
    for (int i = 1; i < pullForce.length; i++) {
      if (pullForce[i] > peakVal) { peakVal = pullForce[i]; peakIdx = i; }
    }
    final actualPeak = onsetIdx + peakIdx;

    SymmetryResult symmetry;
    if (_platformCount >= 2 &&
        _forceAData.length > actualPeak &&
        _forceBData.length > actualPeak) {
      // Average forces over ±100ms around peak for stability.
      const halfWin = 100; // samples
      final lo = (actualPeak - halfWin).clamp(0, _forceAData.length - 1);
      final hi = (actualPeak + halfWin).clamp(0, _forceAData.length - 1);
      double sumA = 0, sumB = 0;
      final count = hi - lo + 1;
      for (int i = lo; i <= hi; i++) {
        sumA += _forceAData[i];
        sumB += _forceBData[i];
      }
      symmetry = JumpMetrics.symmetry2Platform(
        totalPlatformAN: sumA / count,
        totalPlatformBN: sumB / count,
        useLsi: useLsi,
      );
    } else {
      symmetry = SymmetryResult(
        leftPercent: 50, rightPercent: 50,
        asymmetryIndexPct: 0, isTwoPlatform: false,
      );
    }

    state = state.copyWith(
      status: TestStatus.completed,
      result: ImtpResult(
        computedAt:        DateTime.now(),
        platformCount:     _platformCount,
        peakForceN:        peakForce,
        peakForceBW:       bwN > 0 ? peakForce / bwN : 0,
        netImpulseNs:      impulse,
        rfdAt50ms:         rfd50,
        rfdAt100ms:        rfd100,
        rfdAt200ms:        rfd200,
        timeToPeakForceMs: ttp,
        symmetry:          symmetry,
      ),
      statusMessage: 'IMTP completado',
    );
    _autoSaveResult(state.result);
  }

  // ── Auto-save result to SQLite immediately on completion ─────────────────

  Future<void> _autoSaveResult(TestResult? result) async {
    if (result == null) return;
    final settings = _ref.read(settingsProvider);
    if (!settings.autoSaveTests) return;
    final athlete = _ref.read(selectedAthleteProvider);
    if (athlete?.id == null) return;

    final calId = _ref.read(calibrationProvider).activeCalibration?.id;
    double bwKg = athlete?.bodyWeightKg ?? 0;
    if (result is JumpResult && result.bodyWeightN > 0) {
      bwKg = result.bodyWeightN / 9.81;
    }

    try {
      await DatabaseHelper.instance.insertTestSession({
        'athlete_id':     athlete!.id,
        'test_type':      result.testType.name,
        'performed_at':   result.computedAt.toIso8601String(),
        'body_weight_kg': bwKg,
        'calibration_id': calId,
        'platform_count': result.platformCount,
        'result_json':    result.toJson(),
        'sync_status':    'pending',
      });
      // Invalidate history provider so the history screen shows the new result.
      _ref.invalidate(sessionHistoryProvider);
      debugPrint('[TestState] Auto-saved result to SQLite');
    } catch (e) {
      debugPrint('[TestState] Auto-save failed: $e');
    }
  }

  // ── stopTest: cancel ──────────────────────────────────────────────────────

  void stopTest() {
    _postLandingTimer?.cancel();
    _postLandingTimer = null;
    _rawSub?.close();
    _phaseDetector.reset();
    _jumps.clear();
    state = const TestState();
  }

  @override
  void dispose() {
    _postLandingTimer?.cancel();
    _rawSub?.close();
    super.dispose();
  }

  // ── Post-test data access (for PDF export) ───────────────────────────────

  /// Whether a countermovement was detected during an SJ test (warning only).
  bool get countermovementDetected => _phaseDetector.countermovementDetected;

  /// Filtered force signal from the last completed test (N).
  /// Remains available until the next [startTest] call.
  List<double> get lastForceN => List.unmodifiable(_forceData);

  /// Timestamps for [lastForceN] (seconds).
  List<double> get lastTimeS  => List.unmodifiable(_timeData);

  /// Relative timestamps starting from 0 (seconds). Use for post-test chart display.
  List<double> get lastTimeRelS {
    if (_timeData.isEmpty) return const [];
    final t0 = _timeData.first;
    return List.unmodifiable(_timeData.map((t) => t - t0).toList());
  }

  /// Platform A force signal from the last completed test (N).
  List<double> get lastForceAN => List.unmodifiable(_forceAData);

  /// Platform B force signal from the last completed test (N).
  List<double> get lastForceBN => List.unmodifiable(_forceBData);

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double g = x / 2;
    for (int i = 0; i < 20; i++) g = (g + x / g) / 2;
    return g;
  }
}

final testStateProvider =
    StateNotifierProvider<TestStateNotifier, TestState>((ref) {
  return TestStateNotifier(ref);
});
