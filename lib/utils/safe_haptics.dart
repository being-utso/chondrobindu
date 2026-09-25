import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SafeHaptics {
  /// Safe light click vibration for standard buttons and tour interactions
  static void selectionClick() {
    if (!kIsWeb) {
      HapticFeedback.selectionClick();
    }
  }

  /// Safe light impact for minor events, card taps, or micro-interactions
  static void lightImpact() {
    if (!kIsWeb) {
      HapticFeedback.lightImpact();
    }
  }

  /// Safe medium impact for timer actions, completions, or confirmations
  static void mediumImpact() {
    if (!kIsWeb) {
      HapticFeedback.mediumImpact();
    }
  }

  /// Safe heavier feedback for warnings or deletions
  static void heavyImpact() {
    if (!kIsWeb) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Safe generic vibration
  static void vibrate() {
    if (!kIsWeb) {
      HapticFeedback.vibrate();
    }
  }
}
