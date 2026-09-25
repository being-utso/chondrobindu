import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  /// Syncs days remaining and event title to native Android/iOS Home Screen widgets.
  static Future<void> updateHomeWidget({
    String? targetEventName,
    DateTime? targetEventDate,
  }) async {
    try {
      if (targetEventName != null && targetEventName.trim().isNotEmpty && targetEventDate != null) {
        final now = DateTime.now();
        final todayDate = DateTime(now.year, now.month, now.day);
        final targetDate = DateTime(targetEventDate.year, targetEventDate.month, targetEventDate.day);
        int daysRemaining = targetDate.difference(todayDate).inDays;
        if (daysRemaining < 0) daysRemaining = 0;

        await HomeWidget.saveWidgetData<String>('days_remaining', '$daysRemaining Days');
        await HomeWidget.saveWidgetData<String>('event_name', 'until $targetEventName');
      } else {
        await HomeWidget.saveWidgetData<String>('days_remaining', '-- Days');
        await HomeWidget.saveWidgetData<String>('event_name', 'Tap to set goal 🎯');
      }

      await HomeWidget.updateWidget(
        name: 'CountdownWidgetProvider',
        androidName: 'CountdownWidgetProvider',
      );
    } catch (e) {
      debugPrint('Error updating home widget: $e');
    }
  }
}
