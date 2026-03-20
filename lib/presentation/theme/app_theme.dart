import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

// ── Adaptive colour set (surface / text / border — vary per theme) ────────────

@immutable
class ThemeColors extends ThemeExtension<ThemeColors> {
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color divider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  const ThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
  });

  static const dark = ThemeColors(
    background:    Color(0xFF0D0F14),
    surface:       Color(0xFF161B22),
    surfaceHigh:   Color(0xFF1F2937),
    border:        Color(0xFF2D3748),
    divider:       Color(0xFF1A1F2E),
    textPrimary:   Color(0xFFE5E7EB),
    textSecondary: Color(0xFF9CA3AF),
    textDisabled:  Color(0xFF4B5563),
  );

  static const light = ThemeColors(
    background:    Color(0xFFF0F3F8),
    surface:       Color(0xFFFFFFFF),
    surfaceHigh:   Color(0xFFE8ECF3),
    border:        Color(0xFFD1D8E6),
    divider:       Color(0xFFD1D8E6),
    textPrimary:   Color(0xFF0D1120),
    textSecondary: Color(0xFF4A5568),
    textDisabled:  Color(0xFF9AA5B4),
  );

  @override
  ThemeColors copyWith({
    Color? background, Color? surface, Color? surfaceHigh,
    Color? border, Color? divider,
    Color? textPrimary, Color? textSecondary, Color? textDisabled,
  }) => ThemeColors(
    background:    background    ?? this.background,
    surface:       surface       ?? this.surface,
    surfaceHigh:   surfaceHigh   ?? this.surfaceHigh,
    border:        border        ?? this.border,
    divider:       divider       ?? this.divider,
    textPrimary:   textPrimary   ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textDisabled:  textDisabled  ?? this.textDisabled,
  );

  @override
  ThemeColors lerp(ThemeColors? other, double t) {
    if (other == null) return this;
    return ThemeColors(
      background:    Color.lerp(background,    other.background,    t)!,
      surface:       Color.lerp(surface,       other.surface,       t)!,
      surfaceHigh:   Color.lerp(surfaceHigh,   other.surfaceHigh,   t)!,
      border:        Color.lerp(border,        other.border,        t)!,
      divider:       Color.lerp(divider,       other.divider,       t)!,
      textPrimary:   Color.lerp(textPrimary,   other.textPrimary,   t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled:  Color.lerp(textDisabled,  other.textDisabled,  t)!,
    );
  }
}

extension ThemeColorsX on BuildContext {
  /// Access adaptive surface/text/border colours.
  ThemeColors get col => Theme.of(this).extension<ThemeColors>()!;
}

class AppTheme {
  AppTheme._();

  // ── Light theme ─────────────────────────────────────────────────────────────
  static ThemeData get light {
    const bgColor      = Color(0xFFF0F3F8);
    const surfaceColor = Color(0xFFFFFFFF);
    const surfaceHigh  = Color(0xFFE8ECF3);
    const borderColor  = Color(0xFFD1D8E6);
    const textPrimary  = Color(0xFF0D1120);
    const textSecondary = Color(0xFF4A5568);
    const textDisabled  = Color(0xFF9AA5B4);

    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      extensions: const [ThemeColors.light],
      scaffoldBackgroundColor: bgColor,
      colorScheme: const ColorScheme.light(
        primary:   AppColors.primary,
        secondary: AppColors.secondary,
        surface:   surfaceColor,
        error:     AppColors.danger,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      textTheme: _lightTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        iconTheme: const IconThemeData(color: textSecondary),
      ),
      cardTheme: CardTheme(
        color: surfaceColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: borderColor, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: textDisabled,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(fontSize: 14, color: textDisabled),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          side: const BorderSide(color: AppColors.primaryDark),
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: borderColor)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1F2937),
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Dark theme ──────────────────────────────────────────────────────────────
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      extensions: const [ThemeColors.dark],
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary:   AppColors.primary,
        secondary: AppColors.secondary,
        surface:   AppColors.surface,
        error:     AppColors.danger,
        onPrimary: AppColors.textOnPrimary,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: _textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      // Cards — radius 20, no elevation, custom shadow
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      // NavigationBar (bottom tabs)
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primary, size: 24);
          }
          return const IconThemeData(
              color: AppColors.textSecondary, size: 22);
        }),
      ),
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        hintStyle: GoogleFonts.inter(
            fontSize: 14, color: AppColors.textDisabled),
        labelStyle: GoogleFonts.inter(
            fontSize: 14, color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          minimumSize: const Size(120, 48),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      // Botones primarios — pill shape
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          minimumSize: const Size(double.infinity, 52),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, letterSpacing: 0.5),
        ),
      ),
      // Botones outlined — pill shape
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          minimumSize: const Size(double.infinity, 52),
          shape: const StadiumBorder(),
          textStyle:
              GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceHigh,
        labelStyle: GoogleFonts.inter(
            fontSize: 12, color: AppColors.textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      // Bottom sheets
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        backgroundColor: AppColors.surface,
        dragHandleColor: AppColors.textDisabled,
        dragHandleSize: Size(36, 4),
        showDragHandle: true,
      ),
      // Cupertino page transitions
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme get _lightTextTheme => _buildTextTheme(const Color(0xFF0D1120), const Color(0xFF4A5568), const Color(0xFF9AA5B4));

  static TextTheme get _textTheme => _buildTextTheme(AppColors.textPrimary, AppColors.textSecondary, AppColors.textDisabled);

  static TextTheme _buildTextTheme(Color primary, Color secondary, Color disabled) => TextTheme(
    displayLarge:  GoogleFonts.inter(fontSize: 48, fontWeight: FontWeight.w700, color: primary, letterSpacing: -1),
    displayMedium: GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w700, color: primary),
    displaySmall:  GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: primary),
    headlineLarge: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: primary),
    headlineMedium:GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: primary),
    headlineSmall: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w600, color: primary),
    titleLarge:    GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
    titleMedium:   GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: primary),
    titleSmall:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
    bodyLarge:     GoogleFonts.inter(fontSize: 16, color: primary),
    bodyMedium:    GoogleFonts.inter(fontSize: 14, color: primary),
    bodySmall:     GoogleFonts.inter(fontSize: 12, color: secondary),
    labelLarge:    GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: secondary, letterSpacing: 1.2),
    labelMedium:   GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: disabled,  letterSpacing: 1.0),
  );
}

/// Shared text styles used across metric cards and charts.
class IXTextStyles {
  IXTextStyles._();

  /// Large numeric value on metric cards (e.g., "38.4 cm").
  static TextStyle metricValue({Color color = AppColors.primary}) =>
      GoogleFonts.robotoMono(
        fontSize: 32,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: -0.5,
      );

  /// Small uppercase label below metric value.
  static TextStyle get metricLabel => GoogleFonts.robotoMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
      );

  /// Chart axis labels.
  static TextStyle get chartAxis => GoogleFonts.robotoMono(
        fontSize: 10,
        color: AppColors.textDisabled,
      );

  /// Section headers (e.g., "RESULTADOS", "ATLETAS").
  static TextStyle sectionHeader({Color color = AppColors.textSecondary}) =>
      GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 2.0,
      );
}
