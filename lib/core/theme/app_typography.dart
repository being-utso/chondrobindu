import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Font resolution engine providing Plus Jakarta Sans and JetBrains Mono.
class AppFonts {
  static bool isTestMode = false;

  static bool get isTestEnvironment {
    if (isTestMode) return true;
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      if (bindingName.contains('Test')) return true;
    } catch (_) {}
    return false;
  }

  /// Headings & Primary UI Text (Plus Jakarta Sans)
  static TextStyle plusJakartaSans({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    if (isTestEnvironment) {
      return TextStyle(
        fontFamily: 'Plus Jakarta Sans',
        fontFamilyFallback: const ['Inter', 'sans-serif'],
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
    }
    try {
      return GoogleFonts.plusJakartaSans(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
    } catch (_) {
      return GoogleFonts.inter(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
    }
  }

  /// Monospace Data, Badges, & Telemetry (JetBrains Mono)
  static TextStyle jetbrainsMono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    if (isTestEnvironment) {
      return TextStyle(
        fontFamily: 'JetBrains Mono',
        fontFamilyFallback: const ['monospace'],
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
    }
    return GoogleFonts.jetBrainsMono(
      textStyle: textStyle,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
    );
  }

  /// Backward-compatible alias for primary UI text
  static TextStyle geist({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      plusJakartaSans(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  /// Backward-compatible alias for monospace telemetry
  static TextStyle geistMono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      jetbrainsMono(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );
}

/// Typography Hierarchy for Chondrobindu (Dual-Theme Design System).
/// Multi-font scale leveraging Plus Jakarta Sans for UI/Headings and JetBrains Mono for telemetry/data.
abstract class AppTypography {
  // --- Core Font Builders ---
  static TextStyle plusJakartaSans({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      AppFonts.plusJakartaSans(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  static TextStyle jetbrainsMono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      AppFonts.jetbrainsMono(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  static TextStyle geist({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      AppFonts.geist(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  static TextStyle geistMono({
    TextStyle? textStyle,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      AppFonts.geistMono(
        textStyle: textStyle,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        letterSpacing: letterSpacing,
        height: height,
        decoration: decoration,
      );

  // =========================================================================
  // APP UI TYPOGRAPHY SCALE (Plus Jakarta Sans)
  // =========================================================================

  /// Page Titles & AppBars: 20sp, FontWeight.w600 (SemiBold)
  static TextStyle get pageTitle => AppFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static TextStyle get appBarTitle => AppFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  /// Section Headers: 13sp, FontWeight.w600, subtle letter-spacing
  static TextStyle get sectionHeader => AppFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 0.5,
  );

  /// Card Titles: 15sp, FontWeight.w600
  static TextStyle get cardTitle => AppFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.1,
  );

  /// Body Text & Descriptions: 13sp, FontWeight.w400
  static TextStyle get bodyText => AppFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.45,
  );

  /// Subtext & Taglines: 11sp, FontWeight.w500
  static TextStyle get subtext => AppFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  // =========================================================================
  // MONOSPACE DATA, BADGES & TELEMETRY (JetBrains Mono)
  // =========================================================================

  /// CGPA Display: 28sp, FontWeight.w700
  static TextStyle get cgpaDisplay => AppFonts.jetbrainsMono(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.secondary,
    letterSpacing: -0.5,
  );

  /// Attendance Counts: 11sp, FontWeight.w500
  static TextStyle get attendanceCount => AppFonts.jetbrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
    letterSpacing: 0.2,
  );

  /// Time Slots: 11sp, FontWeight.w500
  static TextStyle get timeSlot => AppFonts.jetbrainsMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  /// Course Codes: 14sp, FontWeight.w700
  static TextStyle get courseCode => AppFonts.jetbrainsMono(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
    letterSpacing: 0.5,
  );

  /// Timer Display: 48sp, FontWeight.w600
  static TextStyle get timerDisplay => AppFonts.jetbrainsMono(
    fontSize: 48,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.04,
  );

  // =========================================================================
  // MATERIAL 3 TEXT THEME SCALE (Plus Jakarta Sans + JetBrains Mono)
  // =========================================================================

  static TextStyle get displayLarge => AppFonts.plusJakartaSans(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get displayMedium => AppFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static TextStyle get displaySmall => AppFonts.plusJakartaSans(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineLarge => AppFonts.plusJakartaSans(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.25,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineMedium => AppFonts.plusJakartaSans(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineSmall => AppFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.15,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleLarge => AppFonts.plusJakartaSans(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleMedium => AppFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleSmall => AppFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyLarge => AppFonts.plusJakartaSans(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyMedium => AppFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodySmall => AppFonts.plusJakartaSans(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textMuted,
  );

  static TextStyle get labelLarge => AppFonts.plusJakartaSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelMedium => AppFonts.plusJakartaSans(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.textMuted,
  );

  /// Monospace Label / Telemetry Badge: JetBrains Mono
  static TextStyle get labelSmall => AppFonts.jetbrainsMono(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.textMuted,
  );

  /// Creates a Material 3 [TextTheme] tuned for the given brightness.
  static TextTheme textTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    return TextTheme(
      displayLarge: AppFonts.plusJakartaSans(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        color: primary,
      ),
      displayMedium: AppFonts.plusJakartaSans(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: primary,
      ),
      displaySmall: AppFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      headlineLarge: AppFonts.plusJakartaSans(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.25,
        color: primary,
      ),
      headlineMedium: AppFonts.plusJakartaSans(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      headlineSmall: AppFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.15,
        color: primary,
      ),
      titleLarge: AppFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleMedium: AppFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleSmall: AppFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: AppFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: primary,
      ),
      bodyMedium: AppFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: primary,
      ),
      bodySmall: AppFonts.plusJakartaSans(
        fontSize: 11.5,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: muted,
      ),
      labelLarge: AppFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: AppFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
      labelSmall: AppFonts.jetbrainsMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: muted,
      ),
    );
  }
}
