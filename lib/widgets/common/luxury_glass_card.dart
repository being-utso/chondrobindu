import 'dart:ui';
import 'package:flutter/material.dart';

/// Reusable Apple-Style Glassmorphic Container (`LuxuryGlassCard`).
/// Implements subtle translucent blur with Graphite & Copper Ember gradient
/// and refined copper ember borders.
Widget buildGlassCard({
  required Widget child,
  BorderRadius? borderRadius,
  EdgeInsetsGeometry? padding,
  EdgeInsetsGeometry? margin,
  Color? borderColor,
  Border? border,
}) {
  return Container(
    margin: margin,
    child: ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF241C1A).withValues(alpha: 0.85),
                const Color(0xFF140F0E).withValues(alpha: 0.95),
              ],
            ),
            borderRadius: borderRadius ?? BorderRadius.circular(12),
            border: border ?? Border.all(
              color: borderColor ?? const Color(0xFFF2B78A).withValues(alpha: 0.25),
              width: borderColor != null ? 1.2 : 0.8,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );
}

/// Reusable Widget class implementing Apple-Style Glassmorphic Container
class LuxuryGlassCard extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Border? border;

  const LuxuryGlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.onTap,
    this.borderColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = buildGlassCard(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      borderColor: borderColor,
      border: border,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }

    return card;
  }
}
