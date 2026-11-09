import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
export 'app_shadows.dart';

/// Centralized Dual-Theme Engine for Chondrobindu.
/// Light Mode: "Lime Wash & Indigo Dye"
/// Dark Mode: "Indigo Slate & Luminous Rust"
abstract class AppTheme {
  // =========================================================================
  // DARK THEME ("Indigo Slate & Luminous Rust")
  // =========================================================================
  static ThemeData get darkTheme {
    final textTheme = AppTypography.textTheme(Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      canvasColor: AppColors.darkBackground,

      // --- Color Scheme ---
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary, // #8FA8C8
        onPrimary: AppColors.darkBackground, // #171C24
        primaryContainer: Color(0xFF243B57),
        onPrimaryContainer: AppColors.darkTextPrimary,
        secondary: AppColors.darkSecondary, // #C88256
        onSecondary: AppColors.darkBackground,
        secondaryContainer: Color(0xFF713B15),
        onSecondaryContainer: Color(0xFFF3A778),
        surface: AppColors.darkSurface, // #202733
        onSurface: AppColors.darkTextPrimary, // #EDEAE0
        surfaceDim: AppColors.darkBackground, // #171C24
        surfaceContainer: AppColors.darkRecessed, // #13171E
        surfaceContainerHighest: AppColors.darkBorder, // #2E3846
        error: Color(0xFFFFB4AB),
        onError: Color(0xFF690005),
        errorContainer: Color(0xFF93000A),
        outline: AppColors.darkBorder, // #2E3846
        outlineVariant: AppColors.darkRecessed,
      ),

      // --- Text Theme ---
      textTheme: textTheme,

      // --- Card Theme (1px solid #2E3846) ---
      cardTheme: CardThemeData(
        color: AppColors.darkSurface, // #202733
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusCard,
          side: const BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
      ),

      // --- AppBar Theme ---
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.darkBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary, size: 20),
        titleTextStyle: AppTypography.appBarTitle.copyWith(color: AppColors.darkTextPrimary),
      ),

      // --- Slider Theme ---
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.darkPrimary,
        inactiveTrackColor: AppColors.darkBorder,
        thumbColor: AppColors.darkPrimary,
        overlayColor: Color(0x338FA8C8),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.5),
        trackShape: GradientSliderTrackShape(
          gradient: LinearGradient(
            colors: [AppColors.darkBorder, AppColors.darkPrimary],
          ),
        ),
        trackHeight: 4.0,
      ),

      // --- Segmented Button Theme ---
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.darkPrimary;
            }
            return AppColors.darkSurface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.darkBackground;
            }
            return AppColors.darkTextMuted;
          }),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.darkBorder, width: 1.0)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
      ),

      // --- Navigation Bar Theme ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.darkPrimary.withValues(alpha: 0.2),
        indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.darkPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.darkPrimary, size: 22);
          }
          return const IconThemeData(color: AppColors.darkTextMuted, size: 22);
        }),
      ),

      // --- Switch Theme ---
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.darkPrimary : AppColors.darkTextMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.darkPrimary.withValues(alpha: 0.4)
                : AppColors.darkSurface),
      ),

      // --- Popup Menu Theme ---
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // --- Input Decoration Theme (Recessed: #13171E) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkRecessed, // #13171E
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: const TextStyle(color: AppColors.darkTextMuted, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.darkTextMuted, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: Color(0xFFFFB4AB), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: Color(0xFFFFB4AB), width: 1.5),
        ),
      ),

      // --- Button Themes ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkBackground,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.darkTextPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.darkBorder, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.darkSecondary,
        foregroundColor: AppColors.darkBackground,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.darkPrimary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // --- Chip Theme ---
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: AppColors.darkPrimary.withValues(alpha: 0.2),
        side: const BorderSide(color: AppColors.darkBorder, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
        labelStyle: const TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: AppColors.darkPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      ),

      // --- Dialog Theme ---
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusModal,
          side: const BorderSide(color: AppColors.darkBorder, width: 1.0),
        ),
      ),

      // --- Divider Theme ---
      dividerTheme: const DividerThemeData(
        color: AppColors.darkBorder,
        thickness: 1.0,
        space: 1.0,
      ),

      // --- Dual-Theme Semantic Extensions ---
      extensions: const [
        ChondrobinduThemeColors.dark,
      ],
    );
  }

  // =========================================================================
  // LIGHT THEME ("Lime Wash & Indigo Dye")
  // =========================================================================
  static ThemeData get lightTheme {
    final textTheme = AppTypography.textTheme(Brightness.light);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground, // #EDEAE0
      canvasColor: AppColors.lightBackground,

      // --- Color Scheme ---
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary, // #2F4A6D
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD3E3FF),
        onPrimaryContainer: Color(0xFF001C39),
        secondary: AppColors.lightSecondary, // #A5673F
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFFEB385),
        onSecondaryContainer: Color(0xFF79431E),
        surface: AppColors.lightSurface, // #F7F5F0
        onSurface: AppColors.lightTextPrimary, // #1F2A3A
        surfaceDim: AppColors.lightBackground, // #EDEAE0
        surfaceContainer: AppColors.lightRecessed, // #E5E1D5
        surfaceContainerHighest: AppColors.lightBorder, // #DCD7C8
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: Color(0xFFFFDAD6),
        outline: AppColors.lightBorder, // #DCD7C8
        outlineVariant: AppColors.lightRecessed,
      ),

      // --- Text Theme ---
      textTheme: textTheme,

      // --- Card Theme (1px solid #DCD7C8) ---
      cardTheme: CardThemeData(
        color: AppColors.lightSurface, // #F7F5F0
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusCard,
          side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
      ),

      // --- AppBar Theme ---
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppColors.lightBackground,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary, size: 20),
        titleTextStyle: AppTypography.appBarTitle.copyWith(color: AppColors.lightTextPrimary),
      ),

      // --- Slider Theme ---
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.lightPrimary,
        inactiveTrackColor: AppColors.lightBorder,
        thumbColor: AppColors.lightPrimary,
        overlayColor: Color(0x332F4A6D),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.5),
        trackShape: GradientSliderTrackShape(
          gradient: LinearGradient(
            colors: [AppColors.lightBorder, AppColors.lightPrimary],
          ),
        ),
        trackHeight: 4.0,
      ),

      // --- Segmented Button Theme ---
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.lightPrimary;
            }
            return AppColors.lightSurface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return AppColors.lightTextMuted;
          }),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.lightBorder, width: 1.0)),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
      ),

      // --- Navigation Bar Theme ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.lightBackground,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.lightPrimary.withValues(alpha: 0.15),
        indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: AppColors.lightPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: AppColors.lightTextMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.lightPrimary, size: 22);
          }
          return const IconThemeData(color: AppColors.lightTextMuted, size: 22);
        }),
      ),

      // --- Switch Theme ---
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.lightPrimary : AppColors.lightTextMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.lightPrimary.withValues(alpha: 0.35)
                : AppColors.lightRecessed),
      ),

      // --- Popup Menu Theme ---
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
      ),

      // --- Input Decoration Theme (Recessed: #E5E1D5) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightRecessed, // #E5E1D5
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: const TextStyle(color: AppColors.lightTextMuted, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.lightTextMuted, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: Color(0xFFBA1A1A), width: 1.5),
        ),
      ),

      // --- Button Themes ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.lightPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.lightTextPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.lightSecondary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.lightPrimary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // --- Chip Theme ---
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedColor: AppColors.lightPrimary.withValues(alpha: 0.15),
        side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
        labelStyle: const TextStyle(color: AppColors.lightTextMuted, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: AppColors.lightPrimary, fontSize: 12, fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      ),

      // --- Dialog Theme ---
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusModal,
          side: const BorderSide(color: AppColors.lightBorder, width: 1.0),
        ),
      ),

      // --- Divider Theme ---
      dividerTheme: const DividerThemeData(
        color: AppColors.lightBorder,
        thickness: 1.0,
        space: 1.0,
      ),

      // --- Dual-Theme Semantic Extensions ---
      extensions: const [
        ChondrobinduThemeColors.light,
      ],
    );
  }
}

/// Custom Slider Track Shape with an active gradient
class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  final LinearGradient gradient;

  const GradientSliderTrackShape({
    this.gradient = const LinearGradient(
      colors: [AppColors.darkBorder, AppColors.darkPrimary],
    ),
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final activeTrackRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top - (additionalActiveTrackHeight / 2),
      thumbCenter.dx,
      trackRect.bottom + (additionalActiveTrackHeight / 2),
    );

    final inactiveTrackRect = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );

    final Paint activePaint = Paint()
      ..shader = gradient.createShader(activeTrackRect);

    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? AppColors.darkBorder;

    // Draw inactive track
    if (inactiveTrackRect.right > inactiveTrackRect.left) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(inactiveTrackRect, const Radius.circular(4)),
        inactivePaint,
      );
    }

    // Draw active track with gradient
    if (activeTrackRect.right > activeTrackRect.left) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeTrackRect, const Radius.circular(4)),
        activePaint,
      );
    }
  }
}
