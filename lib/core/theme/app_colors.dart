import 'package:flutter/material.dart';

/// Chondrobindu Dual-Theme Design System
/// Light Mode: "Lime Wash & Indigo Dye"
/// Dark Mode: "Indigo Slate & Luminous Rust"
abstract class AppColors {
  // =========================================================================
  // LIGHT THEME TOKENS ("Lime Wash & Indigo Dye")
  // =========================================================================
  /// Canvas Background: #EDEAE0
  static const Color lightBackground = Color(0xFFEDEAE0);

  /// Elevated Card Surface: #F7F5F0 (with 1px solid #DCD7C8 border)
  static const Color lightSurface = Color(0xFFF7F5F0);
  static const Color lightBorder = Color(0xFFDCD7C8);

  /// Recessed Inputs: #E5E1D5
  static const Color lightRecessed = Color(0xFFE5E1D5);

  /// Primary Text: #1F2A3A
  static const Color lightTextPrimary = Color(0xFF1F2A3A);

  /// Muted Text: #5A6578
  static const Color lightTextMuted = Color(0xFF5A6578);

  /// Primary Accent (Indigo): #2F4A6D
  static const Color lightPrimary = Color(0xFF2F4A6D);

  /// Secondary Accent (Rust): #A5673F
  static const Color lightSecondary = Color(0xFFA5673F);

  /// Success / Moss Green: #3B7A57
  static const Color lightSuccess = Color(0xFF3B7A57);

  // =========================================================================
  // DARK THEME TOKENS ("Indigo Slate & Luminous Rust")
  // =========================================================================
  /// Canvas Background: #171C24
  static const Color darkBackground = Color(0xFF171C24);

  /// Elevated Card Surface: #202733 (with 1px solid #2E3846 border)
  static const Color darkSurface = Color(0xFF202733);
  static const Color darkBorder = Color(0xFF2E3846);

  /// Recessed Inputs: #13171E
  static const Color darkRecessed = Color(0xFF13171E);

  /// Primary Text: #EDEAE0
  static const Color darkTextPrimary = Color(0xFFEDEAE0);

  /// Muted Text: #94A3B8
  static const Color darkTextMuted = Color(0xFF94A3B8);

  /// Primary Accent (Indigo): #8FA8C8
  static const Color darkPrimary = Color(0xFF8FA8C8);

  /// Secondary Accent (Rust): #C88256
  static const Color darkSecondary = Color(0xFFC88256);

  /// Success / Moss Green: #4E9F72
  static const Color darkSuccess = Color(0xFF4E9F72);

  // =========================================================================
  // ACTIVE DEFAULT TOKENS (Defaulting to Dark Theme)
  // =========================================================================
  /// Canvas Background
  static const Color scaffoldBackground = darkBackground;
  static const Color background = darkBackground;
  static const Color canvas = darkBackground;

  /// Elevated Card Surface
  static const Color surface = darkSurface;
  static const Color surfaceElevated = darkSurface;
  static const Color surfaceHighlight = Color(0xFF252A33);

  /// Recessed Inputs
  static const Color recessed = darkRecessed;

  /// Borders & Structural Lines (1px solid #2E3846 Dark / #DCD7C8 Light)
  static const Color borderSubtle = darkBorder;
  static const Color borderMedium = darkBorder;
  static const Color borderStrong = Color(0xFF3E4A5C);
  static const Color divider = darkBorder;

  /// Typography & Text Hierarchies
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextMuted;
  static const Color textMuted = darkTextMuted;
  static const Color textTertiary = Color(0xFF64748B);
  static const Color textBody = darkTextPrimary;
  static const Color textDisabled = Color(0xFF475569);

  /// Primary Accent (Indigo)
  static const Color primary = darkPrimary;
  static const Color primaryDark = Color(0xFF2F4A6D);
  static const Color primaryLight = Color(0xFFAFC9EA);
  static const Color primaryContainer = Color(0x338FA8C8);
  static const Color indigo = darkPrimary;

  /// Secondary Accent (Rust)
  static const Color secondary = darkSecondary;
  static const Color rust = darkSecondary;
  static const Color secondaryContainer = Color(0x33C88256);
  static const Color copper = darkSecondary;
  static const Color ember = darkSecondary;
  static const Color amber = darkSecondary;
  static const Color amberContainer = Color(0x33C88256);

  static const Color ctaText = Color(0xFF171C24);
  static const Color ctaDarkText = Color(0xFF171C24);

  // Status & Semantic Tokens
  /// Success / Moss Green
  static const Color success = darkSuccess;
  static const Color successContainer = Color(0x334E9F72);
  static const Color present = darkSuccess;
  static const Color presentBg = Color(0x264E9F72);
  static const Color presentText = darkTextPrimary;

  /// Error / Danger Tokens
  static const Color error = Color(0xFFFFB4AB);
  static const Color errorContainer = Color(0x33BA1A1A);
  static const Color missed = Color(0xFFFFB4AB);
  static const Color missedBg = Color(0x26FFB4AB);

  /// Warning / Postponed
  static const Color warning = darkSecondary;
  static const Color warningContainer = Color(0x33C88256);
  static const Color postponed = darkSecondary;
  static const Color postponedBg = Color(0x26C88256);

  static const Color neutral = darkTextMuted;
  static const Color neutralContainer = Color(0x2694A3B8);

  static const Color rose = Color(0xFFF43F5E);
  static const Color roseContainer = Color(0x26F43F5E);
  static const Color purple = Color(0xFFA855F7);
  static const Color purpleContainer = Color(0x26A855F7);

  /// Resolves the current [ChondrobinduThemeColors] extension from context
  static ChondrobinduThemeColors of(BuildContext context) {
    return Theme.of(context).extension<ChondrobinduThemeColors>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ChondrobinduThemeColors.dark
            : ChondrobinduThemeColors.light);
  }
}

/// ThemeExtension allowing any widget to query runtime semantic colors based on active theme
@immutable
class ChondrobinduThemeColors extends ThemeExtension<ChondrobinduThemeColors> {
  final Color background;
  final Color surface;
  final Color surfaceBorder;
  final Color recessed;
  final Color textPrimary;
  final Color textMuted;
  final Color primary;
  final Color secondary;
  final Color success;

  Color get textSecondary => textMuted;
  Color get border => surfaceBorder;

  const ChondrobinduThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceBorder,
    required this.recessed,
    required this.textPrimary,
    required this.textMuted,
    required this.primary,
    required this.secondary,
    required this.success,
  });

  static const light = ChondrobinduThemeColors(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceBorder: AppColors.lightBorder,
    recessed: AppColors.lightRecessed,
    textPrimary: AppColors.lightTextPrimary,
    textMuted: AppColors.lightTextMuted,
    primary: AppColors.lightPrimary,
    secondary: AppColors.lightSecondary,
    success: AppColors.lightSuccess,
  );

  static const dark = ChondrobinduThemeColors(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceBorder: AppColors.darkBorder,
    recessed: AppColors.darkRecessed,
    textPrimary: AppColors.darkTextPrimary,
    textMuted: AppColors.darkTextMuted,
    primary: AppColors.darkPrimary,
    secondary: AppColors.darkSecondary,
    success: AppColors.darkSuccess,
  );

  @override
  ChondrobinduThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceBorder,
    Color? recessed,
    Color? textPrimary,
    Color? textMuted,
    Color? primary,
    Color? secondary,
    Color? success,
  }) {
    return ChondrobinduThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceBorder: surfaceBorder ?? this.surfaceBorder,
      recessed: recessed ?? this.recessed,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      success: success ?? this.success,
    );
  }

  @override
  ChondrobinduThemeColors lerp(ThemeExtension<ChondrobinduThemeColors>? other, double t) {
    if (other is! ChondrobinduThemeColors) return this;
    return ChondrobinduThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceBorder: Color.lerp(surfaceBorder, other.surfaceBorder, t)!,
      recessed: Color.lerp(recessed, other.recessed, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}
