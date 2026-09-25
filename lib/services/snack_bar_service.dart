import 'package:flutter/material.dart';

/// Centralized SnackBar service to ensure consistent floating behavior,
/// non-sticky 3-second durations, and prevention of stacking/stuck snackbars.
class SnackBarService {
  /// Dismisses any currently visible or pending SnackBar on the given context
  static void hideCurrent(BuildContext context) {
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (_) {}
  }

  /// Displays a floating SnackBar with a 3-second duration after hiding any active SnackBar
  static void showFloating(
    BuildContext context, {
    required Widget content,
    Color backgroundColor = const Color(0xFF241C1A),
    SnackBarAction? action,
    Duration duration = const Duration(seconds: 3),
  }) {
    hideCurrent(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: content,
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: action,
      ),
    );
  }

  /// Specialized notification for study sessions logged/saved to the Journal
  static void showStudySessionSaved(
    BuildContext context, {
    required int durationMinutes,
    VoidCallback? onViewPressed,
  }) {
    hideCurrent(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Session notes saved to Journal (${durationMinutes}m)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.black,
          onPressed: onViewPressed ?? () {
            Navigator.of(context).pushNamed('/journal');
          },
        ),
      ),
    );
  }

  /// Displays standard success SnackBar
  static void showSuccess(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    hideCurrent(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        action: action,
      ),
    );
  }

  /// Displays standard error SnackBar
  static void showError(
    BuildContext context,
    String message,
  ) {
    hideCurrent(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  /// Displays standard informational SnackBar
  static void showInfo(
    BuildContext context,
    String message, {
    SnackBarAction? action,
  }) {
    hideCurrent(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF241C1A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
        ),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        action: action,
      ),
    );
  }
}
