import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

enum AppBadgeVariant {
  primary,
  amber,
  rose,
  success,
  neutral,
  purple,
  present,
  postpone,
  absent,
  unmarked,
}

/// A standardized rounded status badge / action chip component.
/// Provides consistent typography, border stroke, and Graphite & Copper Ember styling.
class AppBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final AppBadgeVariant variant;
  final Color? customColor;
  final Color? customBackgroundColor;
  final Color? customBorderColor;
  final Color? customTextColor;
  final VoidCallback? onTap;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.variant = AppBadgeVariant.primary,
    this.customColor,
    this.customBackgroundColor,
    this.customBorderColor,
    this.customTextColor,
    this.onTap,
  });

  /// Factory for Present status badge (Translucent slate/emerald, 1px border, crisp text)
  factory AppBadge.present({
    Key? key,
    String label = 'Present',
    IconData? icon = Icons.check_circle_outline_rounded,
    VoidCallback? onTap,
  }) =>
      AppBadge(
        key: key,
        label: label,
        icon: icon,
        variant: AppBadgeVariant.present,
        onTap: onTap,
      );

  /// Factory for Postpone status badge (Translucent copper, 1px border, copper text)
  factory AppBadge.postpone({
    Key? key,
    String label = 'Postponed',
    IconData? icon = Icons.schedule_rounded,
    VoidCallback? onTap,
  }) =>
      AppBadge(
        key: key,
        label: label,
        icon: icon,
        variant: AppBadgeVariant.postpone,
        onTap: onTap,
      );

  /// Factory for Absent status badge (Surface fill 0xFF170F0D, border 0xFF4A3830)
  factory AppBadge.absent({
    Key? key,
    String label = 'Absent',
    IconData? icon = Icons.cancel_outlined,
    VoidCallback? onTap,
  }) =>
      AppBadge(
        key: key,
        label: label,
        icon: icon,
        variant: AppBadgeVariant.absent,
        onTap: onTap,
      );

  /// Factory for Unmarked status badge (Surface fill 0xFF170F0D, border 0xFF4A3830)
  factory AppBadge.unmarked({
    Key? key,
    String label = 'Unmarked',
    IconData? icon = Icons.radio_button_unchecked_rounded,
    VoidCallback? onTap,
  }) =>
      AppBadge(
        key: key,
        label: label,
        icon: icon,
        variant: AppBadgeVariant.unmarked,
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color textColor;

    switch (variant) {
      case AppBadgeVariant.present:
        bg = customBackgroundColor ?? const Color(0xFF06D6A0).withValues(alpha: 0.18);
        border = customBorderColor ?? const Color(0xFF06D6A0).withValues(alpha: 0.4);
        textColor = customTextColor ?? const Color(0xFFFFFFFF);
        break;
      case AppBadgeVariant.postpone:
        bg = customBackgroundColor ?? const Color(0xFFF2B78A).withValues(alpha: 0.15);
        border = customBorderColor ?? const Color(0xFFF2B78A).withValues(alpha: 0.4);
        textColor = customTextColor ?? const Color(0xFFF2B78A);
        break;
      case AppBadgeVariant.absent:
      case AppBadgeVariant.unmarked:
        bg = customBackgroundColor ?? const Color(0xFF170F0D);
        border = customBorderColor ?? const Color(0xFF4A3830);
        textColor = customTextColor ?? const Color(0xFFABA093);
        break;
      default:
        final base = customColor ?? _resolveBaseColor(variant);
        bg = customBackgroundColor ?? base.withValues(alpha: 0.12);
        border = customBorderColor ?? base.withValues(alpha: 0.3);
        textColor = customTextColor ?? base;
    }

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.borderRadiusBadge,
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        borderRadius: AppSpacing.borderRadiusBadge,
        onTap: onTap,
        child: badge,
      );
    }

    return badge;
  }

  Color _resolveBaseColor(AppBadgeVariant v) {
    switch (v) {
      case AppBadgeVariant.primary:
        return AppColors.primary;
      case AppBadgeVariant.amber:
        return AppColors.amber;
      case AppBadgeVariant.rose:
        return AppColors.rose;
      case AppBadgeVariant.success:
        return AppColors.success;
      case AppBadgeVariant.neutral:
        return AppColors.textSecondary;
      case AppBadgeVariant.purple:
        return AppColors.purple;
      case AppBadgeVariant.present:
        return AppColors.present;
      case AppBadgeVariant.postpone:
        return AppColors.postponed;
      case AppBadgeVariant.absent:
      case AppBadgeVariant.unmarked:
        return AppColors.textSecondary;
    }
  }
}
