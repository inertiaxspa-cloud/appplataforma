import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const Color background   = Color(0xFF0D0F14);
  static const Color surface      = Color(0xFF161B22);
  static const Color surfaceHigh  = Color(0xFF1F2937);
  static const Color border       = Color(0xFF2D3748);
  static const Color divider      = Color(0xFF1A1F2E);

  // ── Brand / Accent ────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF00C9FF);
  static const Color primaryDark  = Color(0xFF007ACC);
  static const Color secondary    = Color(0xFF7B2FBE);

  // ── Semantic ──────────────────────────────────────────────────────────────
  static const Color success      = Color(0xFF22C55E);
  static const Color successDim   = Color(0x3322C55E);
  static const Color warning      = Color(0xFFF59E0B);
  static const Color warningDim   = Color(0x33F59E0B);
  static const Color danger       = Color(0xFFEF4444);
  static const Color dangerDim    = Color(0x33EF4444);
  static const Color info         = Color(0xFF3B82F6);

  // ── Force channels ────────────────────────────────────────────────────────
  static const Color forceTotal   = Color(0xFF22C55E);
  static const Color forceLeft    = Color(0xFFFF6B6B);   // Platform A / left
  static const Color forceRight   = Color(0xFF4ECDC4);   // Platform B / right
  static const Color forceAL      = Color(0xFFFF6B6B);
  static const Color forceAR      = Color(0xFFFF9F9F);
  static const Color forceBL      = Color(0xFF4ECDC4);
  static const Color forceBR      = Color(0xFF95E1D3);

  // ── Phase overlays (semi-transparent) ────────────────────────────────────
  static const Color phaseSettle     = Color(0x22FFFFFF);
  static const Color phaseDescent    = Color(0x330099FF);
  static const Color phaseFlight     = Color(0x3300FF00);
  static const Color phaseLanding    = Color(0x33FF9900);
  static const Color phaseContact    = Color(0x33FF0000);
  static const Color phasePropulsion = Color(0x3300C9FF);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFE5E7EB);
  static const Color textSecondary  = Color(0xFF9CA3AF);
  static const Color textDisabled   = Color(0xFF4B5563);
  static const Color textOnPrimary  = Color(0xFF0D0F14);

  // ── Status badges ─────────────────────────────────────────────────────────
  static const Color connected    = Color(0xFF22C55E);
  static const Color disconnected = Color(0xFFEF4444);
  static const Color calibrated   = Color(0xFF00C9FF);
  static const Color uncalibrated = Color(0xFFF59E0B);
}
