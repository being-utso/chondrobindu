import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
export 'app_shadows.dart';

/// Centralized Theme Engine for Chondrobindu (Graphite & Copper Ember Design System).
/// Provides a unified Material 3 theme with deep graphite surfaces, glowing ember copper accents,
/// elevated borders, and Apple-style glassmorphism hierarchy.
abstract class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.scaffoldBackground,
      canvasColor: AppColors.canvas,

      // --- Color Scheme ---
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFF2B78A),
        onPrimary: Color(0xFF140F0E),
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: Colors.white,
        secondary: Color(0xFFABA093),
        onSecondary: Color(0xFF140F0E),
        secondaryContainer: AppColors.primaryContainer,
        surface: Color(0xFF241C1A),
        onSurface: Color(0xFFFFFFFF),
        error: AppColors.error,
        onError: Colors.white,
        errorContainer: AppColors.errorContainer,
        outline: Color(0xFF4A3830),
        outlineVariant: AppColors.borderSubtle,
      ),

      // --- Card Theme ---
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusCard,
          side: const BorderSide(color: AppColors.borderMedium, width: 1.0),
        ),
      ),

      // --- AppBar Theme ---
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.scaffoldBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.scaffoldBackground,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 20),
        titleTextStyle: AppTypography.appBarTitle,
      ),

      // --- Slider Theme (Active Sliders: Gradient Color(0xFF4A3830) to Color(0xFFF2B78A) with Ember Copper Thumb) ---
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.borderMedium,
        thumbColor: AppColors.primary,
        overlayColor: Color(0x3DF2B78A),
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.5),
        trackShape: GradientSliderTrackShape(),
        trackHeight: 4.0,
      ),

      // --- Segmented Button Theme ---
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return AppColors.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF140F0E);
            }
            return AppColors.textSecondary;
          }),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderMedium, width: 0.8)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)))),
        ),
      ),

      // --- Bottom Navigation Bar Theme ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF140F0E),
        elevation: 0,
        height: 64,
        indicatorColor: const Color(0xFFF2B78A).withValues(alpha: 0.2),
        indicatorShape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusPill),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: Color(0xFFF2B78A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: Color(0xFFABA093),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: Color(0xFFF2B78A), size: 22);
          }
          return const IconThemeData(color: Color(0xFFABA093), size: 22);
        }),
      ),

      // --- Switch Theme ---
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? const Color(0xFFF2B78A) : const Color(0xFFABA093)),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? const Color(0xFFF2B78A).withValues(alpha: 0.4) : const Color(0xFF241C1A)),
      ),

      // --- Popup Menu Theme ---
      popupMenuTheme: const PopupMenuThemeData(
        color: Color(0xFF1C1412),
        surfaceTintColor: Colors.transparent,
      ),

      // --- Input Decoration Theme ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.borderMedium, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.borderMedium, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.error, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusButton,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      // --- Button Themes ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: const Color(0xFF140F0E),
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: AppColors.borderMedium, width: 1.0),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusButton),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // --- Floating Action Button Theme ---
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Color(0xFF140F0E),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
          textStyle: AppTypography.labelLarge,
        ),
      ),

      // --- Chip Theme ---
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryContainer,
        side: const BorderSide(color: AppColors.borderMedium, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusBadge),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      ),

      // --- Dialog Theme ---
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusModal,
          side: const BorderSide(color: AppColors.borderMedium, width: 1.0),
        ),
      ),

      // --- Divider Theme ---
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1.0,
        space: 1.0,
      ),
    );
  }
}

/// Custom Slider Track Shape with an active gradient from Color(0xFF4A3830) to Color(0xFFF2B78A).
class GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  final LinearGradient gradient;

  const GradientSliderTrackShape({
    this.gradient = const LinearGradient(
      colors: [Color(0xFF4A3830), Color(0xFFF2B78A)],
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
      ..color = sliderTheme.inactiveTrackColor ?? const Color(0xFF4A3830);

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
