import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Structured Skeleton Shimmer Placeholder matching exact layout geometry.
/// Replaces generic circular progress spinners with modern layout placeholders.
class AppSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  const AppSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.margin,
  });

  /// Standard card skeleton
  factory AppSkeleton.card({
    double height = 120,
    EdgeInsetsGeometry? margin,
  }) {
    return AppSkeleton(
      width: double.infinity,
      height: height,
      borderRadius: AppSpacing.borderRadiusCard,
      margin: margin,
    );
  }

  /// Single line text skeleton
  factory AppSkeleton.line({
    double width = double.infinity,
    double height = 14,
    EdgeInsetsGeometry? margin,
  }) {
    return AppSkeleton(
      width: width,
      height: height,
      borderRadius: BorderRadius.circular(4),
      margin: margin,
    );
  }

  /// Circle / Avatar skeleton
  factory AppSkeleton.circle({
    required double size,
    EdgeInsetsGeometry? margin,
  }) {
    return AppSkeleton(
      width: size,
      height: size,
      borderRadius: BorderRadius.circular(size / 2),
      margin: margin,
    );
  }

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? AppSpacing.borderRadiusButton;

    return Container(
      width: widget.width,
      height: widget.height,
      margin: widget.margin,
      child: ClipRRect(
        borderRadius: radius,
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, _) {
            return Container(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: AppColors.borderSubtle, width: 1.0),
                gradient: LinearGradient(
                  begin: Alignment(_animation.value - 1.0, 0),
                  end: Alignment(_animation.value, 0),
                  colors: const [
                    AppColors.surface,
                    AppColors.surfaceHighlight,
                    AppColors.surface,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
