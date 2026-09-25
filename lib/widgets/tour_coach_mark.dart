import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/tour_service.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Model representing a single spotlight step in an onboarding tour
class TourStep {
  final GlobalKey key;
  final String title;
  final String description;
  final ShapeBorder shapeBorder;
  final EdgeInsets targetPadding;

  const TourStep({
    required this.key,
    required this.title,
    required this.description,
    this.shapeBorder = const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    ),
    this.targetPadding = const EdgeInsets.all(6),
  });

  /// Factory for circular spotlights (e.g. icon buttons or circular dials)
  factory TourStep.circle({
    required GlobalKey key,
    required String title,
    required String description,
    EdgeInsets targetPadding = const EdgeInsets.all(6),
  }) {
    return TourStep(
      key: key,
      title: title,
      description: description,
      shapeBorder: const CircleBorder(),
      targetPadding: targetPadding,
    );
  }
}

/// Custom Notion/Linear-styled coach mark tooltip widget.
/// Styled strictly with dark espresso surface, warm peach accents,
/// subtle step indicator, skip button, and haptic feedback.
class TourTooltipCard extends StatelessWidget {
  final String title;
  final String description;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const TourTooltipCard({
    super.key,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF241C1A);
    const borderColor = Color(0xFF4A3830);
    const accentColor = Color(0xFFF2B78A);
    final isLast = stepIndex >= totalSteps;

    return Container(
      width: 292,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title + Step Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$stepIndex/$totalSteps',
                  style: const TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Description
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFD8CFC7),
              fontSize: 12.2,
              height: 1.38,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 12),

          // Actions Row: Skip + Next/Got It
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Subtle Skip Text Button
              GestureDetector(
                onTap: () {
                  SafeHaptics.selectionClick();
                  onSkip();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(
                    'Skip tour',
                    style: TextStyle(
                      color: Colors.blueGrey.shade400,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // Got It / Next Button
              InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  onNext();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isLast ? 'Got it' : 'Next',
                    style: const TextStyle(
                      color: Color(0xFF140F0E),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Helper widget to wrap any UI widget in a premium Showcase spotlight
class TourShowcaseItem extends StatelessWidget {
  final TourStep step;
  final int stepIndex;
  final int totalSteps;
  final TourSection section;
  final Widget child;

  const TourShowcaseItem({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.section,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Showcase.withWidget(
      key: step.key,
      width: 292,
      height: 142,
      container: TourTooltipCard(
        title: step.title,
        description: step.description,
        stepIndex: stepIndex,
        totalSteps: totalSteps,
        onNext: () {
          if (stepIndex >= totalSteps) {
            ShowCaseWidget.of(context).dismiss();
            TourService().markTourSeen(section);
            TourService().endTour(section);
          } else {
            ShowCaseWidget.of(context).next();
          }
        },
        onSkip: () {
          ShowCaseWidget.of(context).dismiss();
          TourService().markTourSeen(section);
          TourService().endTour(section);
        },
      ),
      targetShapeBorder: step.shapeBorder,
      targetPadding: step.targetPadding,
      overlayColor: const Color(0xFF110D0C),
      overlayOpacity: 0.82,
      blurValue: 2.0,
      child: child,
    );
  }
}

/// Helper method to safely verify that all keys have attached, non-zero render boxes,
/// scroll into view if necessary, and trigger startShowCase.
void triggerTourSafely({
  required BuildContext context,
  required TourSection section,
  required List<GlobalKey> keys,
  VoidCallback? onStarted,
  VoidCallback? onSkippedOrEmpty,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) {
      onSkippedOrEmpty?.call();
      return;
    }

    // Check if another tour is currently active
    if (TourService().isTourActive) {
      onSkippedOrEmpty?.call();
      return;
    }

    final seen = await TourService().hasSeenTour(section);
    if (seen || !context.mounted) {
      onSkippedOrEmpty?.call();
      return;
    }

    if (TourService().isTourActive) {
      onSkippedOrEmpty?.call();
      return;
    }

    // Filter keys that currently have valid non-zero render boxes in the tree
    // and verify they are NOT offstage (vital for IndexedStack inactive tabs)
    List<GlobalKey> extractValidKeys() {
      return keys.where((k) {
        final ctx = k.currentContext;
        if (ctx == null || !ctx.mounted) return false;

        // Strict check for Offstage ancestor (vital for IndexedStack)
        final offstage = ctx.findAncestorWidgetOfExactType<Offstage>();
        if (offstage != null && offstage.offstage) return false;

        final rb = ctx.findRenderObject() as RenderBox?;
        return rb != null && rb.hasSize && rb.size.height > 0 && rb.size.width > 0;
      }).toList();
    }

    var validKeys = extractValidKeys();

    // If keys are not rendered yet (e.g. during IndexedStack tab switch transition),
    // give the engine one extra frame to settle before abandoning
    if (validKeys.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (!context.mounted) {
        onSkippedOrEmpty?.call();
        return;
      }
      validKeys = extractValidKeys();
    }

    if (validKeys.isEmpty || !context.mounted) {
      onSkippedOrEmpty?.call();
      return;
    }

    try {
      // Ensure the first target is visible in the viewport before starting
      final firstCtx = validKeys.first.currentContext;
      if (firstCtx != null && firstCtx.mounted) {
        try {
          Scrollable.ensureVisible(
            firstCtx,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOutCubic,
            alignment: 0.5,
          );
        } catch (_) {
          // Ignore scroll errors if firstCtx is not inside a Scrollable
        }
      }

      // Lock the active tour in TourService with dismiss callback
      TourService().startTour(section, () {
        if (context.mounted) {
          try {
            ShowCaseWidget.of(context).dismiss();
          } catch (_) {}
        }
      });

      ShowCaseWidget.of(context).startShowCase(validKeys);
      onStarted?.call();
    } catch (e) {
      TourService().endTour(section);
      debugPrint('[TourHelper] Failed to start showcase for ${section.id}: $e');
      onSkippedOrEmpty?.call();
    }
  });
}
