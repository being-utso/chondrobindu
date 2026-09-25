import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';

/// Shadow, Elevation, and Border Presets for Chondrobindu.
/// Provides soft, diffused elevation with subtle 1px border strokes.
abstract class AppShadows {
  // --- Diffused Drop Shadows (Opacity < 8-25%, Blur 12-28px) ---
  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x1A000000), // 10% black
    blurRadius: 16.0,
    offset: Offset(0, 4),
    spreadRadius: 0,
  );

  static const BoxShadow elevatedShadow = BoxShadow(
    color: Color(0x33000000), // 20% black
    blurRadius: 24.0,
    offset: Offset(0, 8),
    spreadRadius: -2,
  );

  static const BoxShadow floatingShadow = BoxShadow(
    color: Color(0x4D000000), // 30% black
    blurRadius: 32.0,
    offset: Offset(0, 12),
    spreadRadius: -4,
  );

  static const BoxShadow glowPrimary = BoxShadow(
    color: Color(0x3DF2B78A), // Ember copper glow
    blurRadius: 18.0,
    offset: Offset(0, 2),
  );

  // --- 1px Border Stroke Presets ---
  static final Border cardBorder = Border.all(
    color: AppColors.borderSubtle,
    width: 1.0,
  );

  static final Border elevatedBorder = Border.all(
    color: AppColors.borderMedium,
    width: 1.0,
  );

  static final Border focusBorder = Border.all(
    color: AppColors.primary,
    width: 1.2,
  );

  // --- Complete Standard Card Decorations ---
  static final BoxDecoration cardDecoration = BoxDecoration(
    color: AppColors.surface,
    borderRadius: AppSpacing.borderRadiusCard,
    border: cardBorder,
    boxShadow: const [cardShadow],
  );

  static final BoxDecoration elevatedCardDecoration = BoxDecoration(
    color: AppColors.surfaceElevated,
    borderRadius: AppSpacing.borderRadiusCard,
    border: elevatedBorder,
    boxShadow: const [elevatedShadow],
  );

  static final BoxDecoration frostedBarDecoration = BoxDecoration(
    color: AppColors.scaffoldBackground.withValues(alpha: 0.85),
    border: const Border(
      bottom: BorderSide(color: AppColors.borderSubtle, width: 1.0),
    ),
  );
}
