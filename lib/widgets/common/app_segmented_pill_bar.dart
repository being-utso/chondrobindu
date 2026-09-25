import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// A sleek Cupertino-style pill bar / segmented control component.
/// Uses Color(0xFF241C1A) base surface with an Ember Copper Color(0xFFF2B78A) active indicator.
class AppSegmentedPillBar<T> extends StatelessWidget {
  final List<T> segments;
  final T selectedSegment;
  final ValueChanged<T> onSegmentSelected;
  final String Function(T item)? labelBuilder;
  final IconData? Function(T item)? iconBuilder;
  final EdgeInsetsGeometry? padding;
  final double height;

  const AppSegmentedPillBar({
    super.key,
    required this.segments,
    required this.selectedSegment,
    required this.onSegmentSelected,
    this.labelBuilder,
    this.iconBuilder,
    this.padding,
    this.height = 42.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding ?? const EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        color: AppColors.surface, // Color(0xFF241C1A)
        borderRadius: AppSpacing.borderRadiusActionContainer, // BorderRadius.circular(12)
        border: Border.all(
          color: AppColors.borderMedium, // Color(0xFF4A3830)
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: segments.map((item) {
          final isSelected = item == selectedSegment;
          final label = labelBuilder != null ? labelBuilder!(item) : item.toString();
          final icon = iconBuilder != null ? iconBuilder!(item) : null;

          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (!isSelected) {
                  SafeHaptics.selectionClick();
                  onSegmentSelected(item);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent, // Color(0xFFF2B78A)
                  borderRadius: BorderRadius.circular(9.0),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 14,
                        color: isSelected ? const Color(0xFF140F0E) : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.geist(
                        fontSize: 12.0,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? const Color(0xFF140F0E) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
