import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';

/// Modern Frosted Glass App Bar for Chondrobindu.
/// Features backdrop blur filter, subtle bottom 1px border stroke,
/// and responsive touch targets for leading and action buttons.
class SleekAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget? titleWidget;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool showBottomBorder;
  final double blurAmount;

  const SleekAppBar({
    super.key,
    this.titleWidget,
    this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.bottom,
    this.showBottomBorder = true,
    this.blurAmount = 14.0,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (showBottomBorder ? 1.0 : 0.0) + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.scaffoldBackground.withValues(alpha: 0.82),
            border: showBottomBorder
                ? const Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 1.0))
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: kToolbarHeight - 2,
                    maxHeight: kToolbarHeight,
                  ),
                  child: NavigationToolbar(
                    leading: leading != null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Center(child: leading),
                          )
                        : (Navigator.canPop(context)
                            ? IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 20),
                                onPressed: () => Navigator.pop(context),
                              )
                            : null),
                    middle: titleWidget ??
                        (title != null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title!,
                                    style: AppTypography.titleMedium,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitle != null && subtitle!.isNotEmpty)
                                    Text(
                                      subtitle!,
                                      style: AppTypography.labelSmall.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              )
                            : null),
                    trailing: actions != null
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions!,
                            ),
                          )
                        : null,
                    middleSpacing: AppSpacing.sm,
                  ),
                ),
                if (bottom != null) bottom!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
