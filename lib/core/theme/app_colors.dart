import 'package:flutter/material.dart';

/// Production-ready Color System for Chondrobindu: Graphite & Copper Ember.
/// Apple-style sleek dark aesthetic combining deep graphite surfaces
/// with glowing ember copper accents and refined structural lines.
abstract class AppColors {
  // --- Backgrounds & Surfaces ---
  /// Scaffold / Canvas Background: Color(0xFF110D0C) (or Color(0xFF140F0E))
  static const Color scaffoldBackground = Color(0xFF110D0C);
  static const Color background = Color(0xFF140F0E);
  static const Color canvas = Color(0xFF110D0C);

  /// Card / Container Base Surface: Color(0xFF241C1A)
  static const Color surface = Color(0xFF241C1A);
  static const Color surfaceElevated = Color(0xFF2E2422);
  static const Color surfaceHighlight = Color(0xFF3B2E2A);

  // --- Elevated Borders / Dividers / Structural Lines: Color(0xFF4A3830) ---
  static const Color borderSubtle = Color(0xFF4A3830);
  static const Color borderMedium = Color(0xFF4A3830);
  static const Color borderStrong = Color(0xFF634D43);
  static const Color divider = Color(0xFF4A3830);

  // --- Typography & Text Hierarchies ---
  /// Primary Headings & Crisp Body: Color(0xFFFFFFFF)
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary Muted Text & Subtitles: Color(0xFFABA093)
  static const Color textSecondary = Color(0xFFABA093);
  static const Color textTertiary = Color(0xFF8C8276);

  /// Body Text & Descriptions: Color(0xFFD8CFC7)
  static const Color textBody = Color(0xFFD8CFC7);
  static const Color textMuted = Color(0xFFABA093);
  static const Color textDisabled = Color(0xFF6B6258);

  // --- Hero Brand / Primary CTA / Active Sliders / Score Accents: Color(0xFFF2B78A) (Ember Copper) ---
  static const Color primary = Color(0xFFF2B78A);
  static const Color primaryDark = Color(0xFFD99B6C);
  static const Color primaryLight = Color(0xFFFFD4B2);
  static const Color primaryContainer = Color(0x3DF2B78A); // ~24% opacity
  static const Color copper = Color(0xFFF2B78A);
  static const Color ember = Color(0xFFF2B78A);
  static const Color ctaText = Color(0xFF140F0E);
  static const Color ctaDarkText = Color(0xFF140F0E);

  // Secondary Accents
  static const Color amber = Color(0xFFF2B78A);
  static const Color amberContainer = Color(0x26F2B78A);
  static const Color rose = Color(0xFFF43F5E);
  static const Color roseContainer = Color(0x26F43F5E);
  static const Color purple = Color(0xFFA855F7);
  static const Color purpleContainer = Color(0x26A855F7);

  // --- Semantic Status Tokens ---
  /// Success / Present: Color(0xFF06D6A0) or Color(0xFFABA093).withOpacity(0.2) with Color(0xFFFFFFFF) text
  static const Color success = Color(0xFF06D6A0);
  static const Color successContainer = Color(0x3306D6A0);
  static const Color present = Color(0xFF06D6A0);
  static const Color presentBg = Color(0x33ABA093); // Color(0xFFABA093).withOpacity(0.2)
  static const Color presentText = Color(0xFFFFFFFF);

  /// Danger / Missed: Color(0xFFEF4444).withOpacity(0.15) with Color(0xFFF87171) text
  static const Color error = Color(0xFFF87171);
  static const Color errorContainer = Color(0x26EF4444); // Color(0xFFEF4444).withOpacity(0.15)
  static const Color missed = Color(0xFFF87171);
  static const Color missedBg = Color(0x26EF4444);

  /// Warning / Postponed: Color(0xFFF2B78A).withOpacity(0.15) with Color(0xFFF2B78A) text
  static const Color warning = Color(0xFFF2B78A);
  static const Color warningContainer = Color(0x26F2B78A); // Color(0xFFF2B78A).withOpacity(0.15)
  static const Color postponed = Color(0xFFF2B78A);
  static const Color postponedBg = Color(0x26F2B78A);

  static const Color neutral = Color(0xFFABA093);
  static const Color neutralContainer = Color(0x26ABA093);
}
