import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Font resolution engine providing Geist and GeistMono (or JetBrains Mono).
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

  /// Standard UI labels, titles, descriptions, and button texts (Geist)
  static TextStyle geist({
    TextStyle? textStyle,
    Color? color = AppColors.textPrimary,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    if (isTestEnvironment) {
      return TextStyle(
        fontFamily: 'Geist',
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
      return GoogleFonts.getFont(
        'Geist',
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

  /// Technical / numerical data font (GeistMono or JetBrains Mono)
  static TextStyle geistMono({
    TextStyle? textStyle,
    Color? color = AppColors.primary,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) {
    if (isTestEnvironment) {
      return TextStyle(
        fontFamily: 'GeistMono',
        fontFamilyFallback: const ['JetBrains Mono', 'monospace'],
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

  /// Alias for JetBrains Mono
  static TextStyle jetbrainsMono({
    TextStyle? textStyle,
    Color? color = AppColors.primary,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? letterSpacing,
    double? height,
    TextDecoration? decoration,
  }) =>
      geistMono(
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

/// Typography Hierarchy for Chondrobindu (Graphite & Copper Ember Design System).
/// Multi-font scale leveraging Geist for human-readable content and GeistMono for technical/numerical telemetry.
abstract class AppTypography {
  // --- Helper Methods ---
  static TextStyle geist({
    TextStyle? textStyle,
    Color? color = AppColors.textPrimary,
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
    Color? color = AppColors.primary,
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

  static TextStyle jetbrainsMono({
    TextStyle? textStyle,
    Color? color = AppColors.primary,
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

  // =========================================================================
  // TASK 2: SPECIFIED MULTI-FONT SCALE HIERARCHY
  // =========================================================================

  /// Page Titles & AppBars: 20sp, FontWeight.w600 (SemiBold), Color(0xFFFFFFFF)
  static TextStyle get pageTitle => AppFonts.geist(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: const Color(0xFFFFFFFF),
    letterSpacing: -0.2,
  );

  static TextStyle get appBarTitle => AppFonts.geist(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: const Color(0xFFFFFFFF),
    letterSpacing: -0.2,
  );

  /// Section Headers: 13sp, FontWeight.w600, Color(0xFFABA093) (with subtle letter-spacing)
  static TextStyle get sectionHeader => AppFonts.geist(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: const Color(0xFFABA093),
    letterSpacing: 0.5,
  );

  /// Card Titles: 15sp, FontWeight.w600, Color(0xFFFFFFFF)
  static TextStyle get cardTitle => AppFonts.geist(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: const Color(0xFFFFFFFF),
    letterSpacing: -0.1,
  );

  /// Body Text & Descriptions: 13sp, FontWeight.w400, Color(0xFFD8CFC7)
  static TextStyle get bodyText => AppFonts.geist(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: const Color(0xFFD8CFC7),
    height: 1.45,
  );

  /// Subtext & Taglines: 11sp, FontWeight.w500, Color(0xFFABA093)
  static TextStyle get subtext => AppFonts.geist(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABA093),
  );

  // --- Numerical & Technical Data (GeistMono / JetBrains Mono) ---

  /// CGPA Display: 24sp - 32sp, FontWeight.w700, Color(0xFFF2B78A)
  static TextStyle get cgpaDisplay => AppFonts.geistMono(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: const Color(0xFFF2B78A),
    letterSpacing: -0.5,
  );

  /// Attendance Counts (e.g. "10/12 HELD", "83.3%"): 11sp, FontWeight.w500
  static TextStyle get attendanceCount => AppFonts.geistMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABA093),
    letterSpacing: 0.2,
  );

  /// Time Slots (e.g. "02:00 PM"): 11sp, FontWeight.w500
  static TextStyle get timeSlot => AppFonts.geistMono(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFABA093),
  );

  /// Course Codes (e.g. "EEE 254"): 14sp, FontWeight.w700
  static TextStyle get courseCode => AppFonts.geistMono(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: const Color(0xFFF2B78A),
    letterSpacing: 0.5,
  );

  // =========================================================================
  // MATERIAL 3 TOKENS (Geist-Powered)
  // =========================================================================

  static TextStyle get displayLarge => AppFonts.geist(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get displayMedium => AppFonts.geist(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleLarge => AppFonts.geist(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleMedium => AppFonts.geist(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  static TextStyle get titleSmall => AppFonts.geist(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyLarge => AppFonts.geist(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get bodyMedium => AppFonts.geist(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: const Color(0xFFD8CFC7),
  );

  static TextStyle get bodySmall => AppFonts.geist(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  static TextStyle get labelLarge => AppFonts.geist(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelMedium => AppFonts.geist(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.textSecondary,
  );

  static TextStyle get labelSmall => AppFonts.geistMono(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );
}
