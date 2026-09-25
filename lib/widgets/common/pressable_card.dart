import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_spacing.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// A modern, tactile Card component for Chondrobindu.
/// Features a strict 16px radius, subtle 1px border stroke,
/// diffused ambient drop shadow, and a smooth 0.98 press scale micro-interaction.
class PressableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final bool enableFeedback;
  final bool isElevated;

  const PressableCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = AppSpacing.cardPadding,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = AppSpacing.radiusCard,
    this.enableFeedback = true,
    this.isElevated = false,
  });

  @override
  State<PressableCard> createState() => _PressableCardState();
}

class _PressableCardState extends State<PressableCard> with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap != null || widget.onLongPress != null) {
      setState(() => _isPressed = true);
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? (widget.isElevated ? AppColors.surfaceElevated : AppColors.surface);
    final border = Border.all(
      color: widget.borderColor ?? (widget.isElevated ? AppColors.borderMedium : AppColors.borderSubtle),
      width: 1.0,
    );

    final card = Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: border,
        boxShadow: [
          widget.isElevated ? AppShadows.elevatedShadow : AppShadows.cardShadow,
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: Colors.transparent,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.enableFeedback) SafeHaptics.lightImpact();
                  widget.onTap!();
                },
          onLongPress: widget.onLongPress == null
              ? null
              : () {
                  if (widget.enableFeedback) SafeHaptics.mediumImpact();
                  widget.onLongPress!();
                },
          child: Padding(
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );

    if (widget.onTap == null && widget.onLongPress == null) {
      return card;
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: card,
      ),
    );
  }
}
