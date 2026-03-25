import 'package:flutter/foundation.dart';

// ── Algorithm selection enums ────────────────────────────────────────────────

/// Jump height calculation method.
enum JumpHeightMethod {
  /// h = g·tf²/8  —  fast, works for all tests (flight-time based).
  flightTime,

  /// v = ∫(F−BW)dt / m,  h = v²/(2g)  —  gold standard (Linthorne, 2001).
  impulseMomentum,
}

/// Peak power estimation method.
enum PeakPowerMethod {
  /// PP = 60.7·h_cm + 45.3·BW_kg − 2055  (Sayers et al., 1999).
  sayers,

  /// PP = 61.9·h_cm + 36.0·BW_kg − 1822  (Harman et al., 1991).
  harman,

  /// P = F × v  (max over propulsive phase — direct impulse method).
  impulseBased,
}

/// Symmetry / asymmetry index method.
enum SymmetryMethod {
  /// AI = |left% − 50%|  — deviation from perfect 50/50.
  asymmetryIndex,

  /// LSI = min/max × 100  — Limb Symmetry Index (Robinson et al., 1987).
  /// Expressed as (1 − LSI/100) × 100 so that 0 = symmetric, 100 = max asymmetry.
  limbSymmetryIndex,
}

/// IMTP pull-onset detection method.
enum ImtpOnsetMethod {
  /// First sample exceeding BW + 50 N.
  fixedThreshold,

  /// First sample exceeding BW + 5 × SD_baseline  (Brady et al., 2020).
  statisticalSD,
}

/// Unweighting threshold for CMJ/SJ descent detection.
enum UnweightingMethod {
  /// Force drops 80 N below BW (fixed).
  fixed80N,

  /// Force drops 5 × SD_settling below BW  (Owen et al., 2014).
  adaptive5SD,
}

/// CoP dominant-frequency estimation method.
enum CopFrequencyMethod {
  /// Zero-crossing rate on the ML signal — fast approximation.
  zeroCrossing,

  /// f95: frequency below which 95 % of spectral power lies (DFT).
  /// Reference: Prieto et al. (1996).
  fft95,
}

// ── AlgorithmSettings data class ─────────────────────────────────────────────

@immutable
class AlgorithmSettings {
  final JumpHeightMethod   jumpHeight;
  final PeakPowerMethod    peakPower;
  final SymmetryMethod     symmetry;
  final ImtpOnsetMethod    imtpOnset;
  final UnweightingMethod  unweighting;
  final CopFrequencyMethod copFrequency;

  const AlgorithmSettings({
    this.jumpHeight   = JumpHeightMethod.flightTime,
    this.peakPower    = PeakPowerMethod.sayers,
    this.symmetry     = SymmetryMethod.asymmetryIndex,
    this.imtpOnset    = ImtpOnsetMethod.statisticalSD,
    this.unweighting  = UnweightingMethod.adaptive5SD,
    this.copFrequency = CopFrequencyMethod.fft95,
  });

  AlgorithmSettings copyWith({
    JumpHeightMethod?   jumpHeight,
    PeakPowerMethod?    peakPower,
    SymmetryMethod?     symmetry,
    ImtpOnsetMethod?    imtpOnset,
    UnweightingMethod?  unweighting,
    CopFrequencyMethod? copFrequency,
  }) => AlgorithmSettings(
    jumpHeight:   jumpHeight   ?? this.jumpHeight,
    peakPower:    peakPower    ?? this.peakPower,
    symmetry:     symmetry     ?? this.symmetry,
    imtpOnset:    imtpOnset    ?? this.imtpOnset,
    unweighting:  unweighting  ?? this.unweighting,
    copFrequency: copFrequency ?? this.copFrequency,
  );
}
