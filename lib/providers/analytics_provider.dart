import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics_models.dart';
import '../services/timer_service.dart';

/// StreamProvider listening to live focus session records from Firestore: users/{uid}/focus_sessions
final focusSessionsStreamProvider = StreamProvider<List<StudySessionLog>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value(const <StudySessionLog>[]);
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('focus_sessions')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) {
    final rawLogs = snapshot.docs.map((doc) {
      final data = doc.data();

      DateTime date = DateTime.now();
      if (data['timestamp'] != null) {
        if (data['timestamp'] is Timestamp) {
          date = (data['timestamp'] as Timestamp).toDate();
        } else if (data['timestamp'] is String) {
          date = DateTime.tryParse(data['timestamp']) ?? DateTime.now();
        }
      } else if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
        date = (data['createdAt'] as Timestamp).toDate();
      }

      final durationSecs = (data['durationSeconds'] as num?)?.toInt() ?? 0;
      final durationMins = (data['durationMinutes'] as num?)?.toInt() ?? (durationSecs / 60).round();

      DateTime startTime = date.subtract(Duration(seconds: durationSecs > 0 ? durationSecs : durationMins * 60));
      if (data['startTime'] != null && data['startTime'] is Timestamp) {
        startTime = (data['startTime'] as Timestamp).toDate();
      }

      DateTime endTime = date;
      if (data['endTime'] != null && data['endTime'] is Timestamp) {
        endTime = (data['endTime'] as Timestamp).toDate();
      }

      final subject = data['subjectName'] as String? ?? (data['subject'] as String? ?? 'General Study');
      final courseCode = data['courseCode'] as String?;
      final courseTitle = data['courseTitle'] as String?;
      final sessionId = data['sessionId'] as String? ?? doc.id;

      return StudySessionLog(
        id: sessionId,
        date: date,
        durationInMinutes: durationMins,
        durationInSeconds: durationSecs,
        subjectId: subject,
        subjectName: subject,
        courseCode: courseCode,
        courseTitle: courseTitle,
        startTime: startTime,
        endTime: endTime,
      );
    }).toList();

    return deduplicateStudySessions<StudySessionLog>(
      sessions: rawLogs,
      getId: (s) => s.id,
      getCourseKey: (s) => s.courseCode?.isNotEmpty == true ? s.courseCode! : s.subjectName,
      getStartTime: (s) => s.startTime ?? s.date,
      getDurationSeconds: (s) => s.durationInSeconds > 0 ? s.durationInSeconds : s.durationInMinutes * 60,
    ).reversed.toList();
  });
});

/// Helper function to delete a specific focus session from Firestore
Future<void> deleteFocusSession(String sessionId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || sessionId.isEmpty) return;

  try {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('focus_sessions')
        .doc(sessionId)
        .delete();
    debugPrint('Deleted focus session: $sessionId from Firestore');
  } catch (e) {
    debugPrint('Error deleting focus session: $e');
  }
}

/// Fallback / Local Provider for study session logs (derived from live focusSessionsStreamProvider)
final studyLogsProvider = Provider<List<StudySessionLog>>((ref) {
  final asyncLogs = ref.watch(focusSessionsStreamProvider);
  return asyncLogs.asData?.value ?? const [];
});

/// Calculates today's total focus minutes from live Firestore focus sessions
final todaysFocusMinutesProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 0;

  final now = DateTime.now();
  final todayLogs = logs.where((log) =>
      log.date.year == now.year &&
      log.date.month == now.month &&
      log.date.day == now.day);

  return todayLogs.fold<int>(0, (sum, item) => sum + item.durationInMinutes);
});

/// Task 3: Checks if today's study duration exceeds the 12-hour (720 minutes) Burnout Guard threshold
final isBurnoutThresholdReachedProvider = Provider<bool>((ref) {
  final todayMinutes = ref.watch(todaysFocusMinutesProvider);
  return todayMinutes >= 720;
});

/// Calculates all-time total focus minutes from live Firestore focus sessions
final totalFocusMinutesProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 0;
  return logs.fold<int>(0, (sum, item) => sum + item.durationInMinutes);
});

/// Total study hours formatted
final totalStudyHoursProvider = Provider<double>((ref) {
  final totalMins = ref.watch(totalFocusMinutesProvider);
  return totalMins / 60.0;
});

/// Calculates total focus hours logged in the past 30 days for PDF progress report
final thirtyDayFocusHoursProvider = Provider<double>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 0.0;

  final now = DateTime.now();
  final thirtyDaysAgo = now.subtract(const Duration(days: 30));

  final recentLogs = logs.where((log) => log.date.isAfter(thirtyDaysAgo));
  final totalMins = recentLogs.fold<int>(0, (sum, log) => sum + log.durationInMinutes);
  return totalMins / 60.0;
});

/// Calculates current streak of continuous active study days up to today or yesterday.
final currentStreakProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return 0;

  final now = DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);

  // Set of dates with study logs
  final activeDates = logs.map((log) {
    return DateTime(log.date.year, log.date.month, log.date.day);
  }).toSet();

  int streak = 0;
  DateTime checkDate = todayDate;

  // If didn't study today yet, check if studied yesterday to keep streak alive
  if (!activeDates.contains(todayDate)) {
    checkDate = todayDate.subtract(const Duration(days: 1));
  }

  while (activeDates.contains(checkDate)) {
    streak++;
    checkDate = checkDate.subtract(const Duration(days: 1));
  }

  return streak;
});

/// Calculates average focus minutes per session over the last 7 days.
final averageFocusProvider = Provider<int>((ref) {
  final logs = ref.watch(studyLogsProvider);
  final now = DateTime.now();
  final sevenDaysAgo = DateTime(now.year, now.month, now.day - 7);

  final last7DaysLogs = logs.where((log) => log.date.isAfter(sevenDaysAgo)).toList();

  if (last7DaysLogs.isEmpty) return 0;

  final totalMinutes = last7DaysLogs.fold<int>(0, (sum, item) => sum + item.durationInMinutes);
  return (totalMinutes / last7DaysLogs.length).round();
});

class DailyStudyBarData {
  final String dayName;
  final DateTime date;
  final int totalMinutes;

  const DailyStudyBarData({
    required this.dayName,
    required this.date,
    required this.totalMinutes,
  });
}

/// Provides aggregated daily study minutes for the last 7 days (BarChart).
final weeklyTrendProvider = Provider<List<DailyStudyBarData>>((ref) {
  final logs = ref.watch(studyLogsProvider);
  final now = DateTime.now();

  final List<DailyStudyBarData> result = [];
  final List<String> weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  for (int i = 6; i >= 0; i--) {
    final targetDate = DateTime(now.year, now.month, now.day - i);
    final dayLogs = logs.where((log) {
      return log.date.year == targetDate.year &&
          log.date.month == targetDate.month &&
          log.date.day == targetDate.day;
    });

    final totalMins = dayLogs.fold<int>(0, (sum, log) => sum + log.durationInMinutes);
    final dayLabel = weekdays[targetDate.weekday - 1];

    result.add(DailyStudyBarData(
      dayName: dayLabel,
      date: targetDate,
      totalMinutes: totalMins,
    ));
  }

  return result;
});

class SubjectDistributionData {
  final String subjectName;
  final int totalMinutes;
  final double percentage;

  const SubjectDistributionData({
    required this.subjectName,
    required this.totalMinutes,
    required this.percentage,
  });
}

/// Task 3: Provides aggregated subject distribution for the last 7 days (PieChart).
final subjectDistributionProvider = Provider<List<SubjectDistributionData>>((ref) {
  final logs = ref.watch(studyLogsProvider);
  if (logs.isEmpty) return [];

  final now = DateTime.now();
  final sevenDaysAgo = now.subtract(const Duration(days: 7));

  final last7DaysLogs = logs.where((log) => log.date.isAfter(sevenDaysAgo)).toList();
  if (last7DaysLogs.isEmpty) return [];

  final Map<String, int> subjectTotals = {};
  int grandTotal = 0;

  for (final log in last7DaysLogs) {
    subjectTotals[log.subjectName] = (subjectTotals[log.subjectName] ?? 0) + log.durationInMinutes;
    grandTotal += log.durationInMinutes;
  }

  if (grandTotal == 0) return [];

  return subjectTotals.entries.map((entry) {
    final pct = (entry.value / grandTotal) * 100;
    return SubjectDistributionData(
      subjectName: entry.key,
      totalMinutes: entry.value,
      percentage: pct,
    );
  }).toList();
});
