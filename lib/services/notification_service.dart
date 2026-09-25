import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  static const int timerNotificationId = 1001;
  static const int breakAlertNotificationId = 1002;
  static const int abandonedPauseNotificationId = 1003;
  static const int examReminderBaseId = 2000;
  static const int postExamNudgeBaseId = 3000;
  static const int streakProtectorNotificationId = 4001;
  static const int syllabusDecayBaseId = 5000;
  static const int weeklyWrapUpNotificationId = 6001;
  static const int burnoutGuardNotificationId = 7001;

  static const String timerChannelId = 'chondrobindu_timer';
  static const String timerChannelName = 'Study Timer';
  static const String timerChannelDescription = 'Active focus timer persistent notifications';

  static const String breakChannelId = 'chondrobindu_break_alert';
  static const String breakChannelName = 'Break Alerts';
  static const String breakChannelDescription = 'Alerts when focus target is reached and break time begins';

  static const String timerNudgeChannelId = 'chondrobindu_timer_nudges';
  static const String timerNudgeChannelName = 'Timer Nudges';
  static const String timerNudgeChannelDescription = 'Alerts for paused timers and abandoned study sessions';

  static const String examChannelId = 'chondrobindu_exam_reminders';
  static const String examChannelName = 'Exam Reminders';
  static const String examChannelDescription = 'Scheduled reminders for upcoming exams';

  static const String examNudgeChannelId = 'chondrobindu_exam_nudges';
  static const String examNudgeChannelName = 'Exam Score Nudges';
  static const String examNudgeChannelDescription = 'Reminders to log marks for completed exams';

  static const String streakChannelId = 'chondrobindu_streak_reminders';
  static const String streakChannelName = 'Streak Reminders';
  static const String streakChannelDescription = 'Daily rolling streak protector reminders';

  static const String syllabusNudgeChannelId = 'chondrobindu_syllabus_nudges';
  static const String syllabusNudgeChannelName = 'Syllabus Nudges';
  static const String syllabusNudgeChannelDescription = 'Reminders for untouched core subjects';

  static const String weeklyWrapUpChannelId = 'chondrobindu_weekly_wrapup';
  static const String weeklyWrapUpChannelName = 'Weekly Wrap-Up';
  static const String weeklyWrapUpChannelDescription = 'Weekly study summary and focus wrap-up insights';

  static const String burnoutGuardChannelId = 'chondrobindu_burnout_guard';
  static const String burnoutGuardChannelName = 'Burnout Guard';
  static const String burnoutGuardChannelDescription = 'Daily wellness alerts when focus duration exceeds 12 hours';

  /// Initialize timezone data & local notification plugin
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
      } catch (_) {
        try {
          tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error initializing timezones: $e');
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _notificationsPlugin.initialize(initSettings);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize NotificationService: $e');
    }
  }

  /// Explicitly request notification permissions on Android 13+ (Tiramisu) and iOS
  Future<bool?> requestPermissions() async {
    if (!_isInitialized) await init();

    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidImplementation?.requestNotificationsPermission();
      debugPrint('Notification permission request result: $granted');
      return granted;
    } catch (e) {
      debugPrint('Error requesting Android notification permission: $e');
      return null;
    }
  }

  /// Persistent, low-priority ongoing notification showing "Focus Timer is Active"
  Future<void> showTimerNotification({
    required String timeRemaining,
    required String subject,
    required bool isRunning,
    bool isBreakMode = false,
  }) async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      timerChannelId,
      timerChannelName,
      channelDescription: timerChannelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    String title;
    if (isBreakMode) {
      title = isRunning ? 'Break Time is Active' : 'Break Time is Active (Paused)';
    } else {
      title = isRunning ? 'Focus Timer is Active' : 'Focus Timer is Active (Paused)';
    }

    final body = '$timeRemaining • $subject';

    try {
      await _notificationsPlugin.show(
        timerNotificationId,
        title,
        body,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error updating timer notification: $e');
    }
  }

  /// Local alert notification triggered the exact moment Focus target is reached
  Future<void> showBreakAlertNotification() async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      breakChannelId,
      breakChannelName,
      channelDescription: breakChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        breakAlertNotificationId,
        '🎉 Focus Target Reached!',
        'Break Time has started! Take a well-deserved rest & recharge.',
        notificationDetails,
      );
    } catch (e) {
      debugPrint('Error triggering break alert notification: $e');
    }
  }

  /// The "Abandoned Pause" Nudge (Triggered if timer paused for 15+ minutes)
  Future<void> showAbandonedPauseNudge() async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      timerNudgeChannelId,
      timerNudgeChannelName,
      channelDescription: timerNudgeChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        abandonedPauseNotificationId,
        'Extended Break? 🛑',
        'Your timer has been paused for a while. Ready to dive back in?',
        notificationDetails,
      );
      debugPrint('Fired Abandoned Pause Nudge notification');
    } catch (e) {
      debugPrint('Error triggering abandoned pause nudge: $e');
    }
  }

  /// Cancels abandoned pause nudge notification
  Future<void> cancelAbandonedPauseNudge() async {
    try {
      await _notificationsPlugin.cancel(abandonedPauseNotificationId);
    } catch (e) {
      debugPrint('Error canceling abandoned pause nudge: $e');
    }
  }

  /// Dismisses active persistent timer notification
  Future<void> cancelTimerNotification() async {
    try {
      await _notificationsPlugin.cancel(timerNotificationId);
    } catch (e) {
      debugPrint('Error canceling timer notification: $e');
    }
  }

  /// Schedule a notification exactly 24 hours before the assessment date
  Future<void> scheduleAssessmentReminder({
    required String assessmentName,
    required String courseName,
    required DateTime date,
    String? id,
  }) async {
    if (!_isInitialized) await init();

    final reminderTime = date.subtract(const Duration(hours: 24));
    try {
      final scheduledDate = tz.TZDateTime.from(reminderTime, tz.local);
      if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
        final notifId = ((id ?? '$courseName$assessmentName').hashCode.abs() % 1000000) + examReminderBaseId;

        const androidDetails = AndroidNotificationDetails(
          examChannelId,
          examChannelName,
          channelDescription: examChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

        const darwinDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        const notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
        );

        await _notificationsPlugin.zonedSchedule(
          notifId,
          'Assessment Reminder 🔔',
          'Reminder: $assessmentName for $courseName is tomorrow!',
          scheduledDate,
          notificationDetails,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('Scheduled assessment reminder for $assessmentName ($courseName) on $scheduledDate');
      }
    } catch (e) {
      debugPrint('Error scheduling assessment reminder: $e');
    }
  }

  /// Automatically schedule a local notification for 6:00 PM the day before the exam date
  Future<void> scheduleExamReminder({
    required String examId,
    required String subject,
    required DateTime examDate,
  }) async {
    if (!_isInitialized) await init();

    final dayBefore = examDate.subtract(const Duration(days: 1));
    final targetDateTime = DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18, 0, 0);

    try {
      final scheduledDate = tz.TZDateTime.from(targetDateTime, tz.local);

      if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
        final notifId = (examId.hashCode.abs() % 1000000) + examReminderBaseId;

        const androidDetails = AndroidNotificationDetails(
          examChannelId,
          examChannelName,
          channelDescription: examChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

        const darwinDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        const notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
        );

        await _notificationsPlugin.zonedSchedule(
          notifId,
          'Exam Reminder',
          "Don't forget your $subject exam tomorrow!",
          scheduledDate,
          notificationDetails,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('Scheduled exam reminder for $subject on $scheduledDate (ID: $notifId)');
      }
    } catch (e) {
      debugPrint('Error scheduling exam reminder: $e');
    }
  }

  /// Post-Exam "Score Log" Nudge (10-Day Delay at 10:00 AM)
  Future<void> schedulePostExamScoreNudge({
    required String examId,
    required String subject,
    required DateTime examDate,
  }) async {
    if (!_isInitialized) await init();

    final tenDaysAfter = examDate.add(const Duration(days: 10));
    final targetDateTime = DateTime(tenDaysAfter.year, tenDaysAfter.month, tenDaysAfter.day, 10, 0, 0);

    try {
      final scheduledDate = tz.TZDateTime.from(targetDateTime, tz.local);

      if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
        final notifId = (examId.hashCode.abs() % 1000000) + postExamNudgeBaseId;

        const androidDetails = AndroidNotificationDetails(
          examNudgeChannelId,
          examNudgeChannelName,
          channelDescription: examNudgeChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

        const darwinDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        const notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
        );

        await _notificationsPlugin.zonedSchedule(
          notifId,
          'How did the exam go? 📝',
          'Your $subject exam results might be out! Tap here to log your marks.',
          scheduledDate,
          notificationDetails,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('Scheduled post-exam score nudge for $subject on $scheduledDate (ID: $notifId)');
      }
    } catch (e) {
      debugPrint('Error scheduling post-exam score nudge: $e');
    }
  }

  /// Cancels post-exam score log nudge
  Future<void> cancelPostExamScoreNudge(String examId) async {
    final notifId = (examId.hashCode.abs() % 1000000) + postExamNudgeBaseId;
    try {
      await _notificationsPlugin.cancel(notifId);
    } catch (e) {
      debugPrint('Error canceling post-exam score nudge: $e');
    }
  }

  /// Cancels scheduled exam reminder
  Future<void> cancelExamReminder(String examId) async {
    final notifId = (examId.hashCode.abs() % 1000000) + examReminderBaseId;
    try {
      await _notificationsPlugin.cancel(notifId);
    } catch (e) {
      debugPrint('Error canceling exam reminder: $e');
    }
  }

  /// The Streak Protector (Rolling Schedule at 9:00 PM the following day)
  Future<void> scheduleStreakProtectorReminder() async {
    if (!_isInitialized) await init();

    try {
      await _notificationsPlugin.cancel(streakProtectorNotificationId);

      final now = DateTime.now();
      final followingDay = now.add(const Duration(days: 1));
      final targetDateTime = DateTime(followingDay.year, followingDay.month, followingDay.day, 21, 0, 0);

      final scheduledDate = tz.TZDateTime.from(targetDateTime, tz.local);

      if (scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) {
        const androidDetails = AndroidNotificationDetails(
          streakChannelId,
          streakChannelName,
          channelDescription: streakChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        );

        const darwinDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

        const notificationDetails = NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
        );

        await _notificationsPlugin.zonedSchedule(
          streakProtectorNotificationId,
          'Keep the momentum going! 🔥',
          'Your study streak is at risk. A quick review session will keep it alive.',
          scheduledDate,
          notificationDetails,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        debugPrint('Scheduled rolling streak protector for $scheduledDate');
      }
    } catch (e) {
      debugPrint('Error scheduling streak protector: $e');
    }
  }

  /// Task 2: Syllabus "Decay" Nudge (Triggered when neither paper of a core subject has been touched in 14+ days)
  Future<void> showSyllabusDecayNudge(String coreSubject) async {
    if (!_isInitialized) await init();

    final notifId = syllabusDecayBaseId + (coreSubject.hashCode.abs() % 1000);

    const androidDetails = AndroidNotificationDetails(
      syllabusNudgeChannelId,
      syllabusNudgeChannelName,
      channelDescription: syllabusNudgeChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        notifId,
        'Dust off your notes 📚',
        "You haven't tracked any progress in $coreSubject in 2 weeks. Time for a review?",
        notificationDetails,
      );
      debugPrint('Triggered Syllabus Decay Nudge for $coreSubject');
    } catch (e) {
      debugPrint('Error triggering syllabus decay nudge: $e');
    }
  }

  /// Task 3: The Weekly Wrap-Up Notification (Triggered Sunday evening with 7-day focus totals)
  Future<void> showWeeklyWrapUpNotification(double totalHours) async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      weeklyWrapUpChannelId,
      weeklyWrapUpChannelName,
      channelDescription: weeklyWrapUpChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      final hoursFormatted = totalHours.toStringAsFixed(1);
      await _notificationsPlugin.show(
        weeklyWrapUpNotificationId,
        'Your Weekly Insights are Ready 📊',
        'You logged $hoursFormatted hours of focus time this week. Tap to see your top subject!',
        notificationDetails,
      );
      debugPrint('Triggered Weekly Wrap-Up Notification ($hoursFormatted hrs)');
    } catch (e) {
      debugPrint('Error triggering weekly wrap-up notification: $e');
    }
  }

  /// Task 2: Burnout Guard Notification (Triggered once per day when total focus time exceeds 12 hours)
  Future<void> showBurnoutGuardNotification() async {
    if (!_isInitialized) await init();

    const androidDetails = AndroidNotificationDetails(
      burnoutGuardChannelId,
      burnoutGuardChannelName,
      channelDescription: burnoutGuardChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    try {
      await _notificationsPlugin.show(
        burnoutGuardNotificationId,
        'Time to rest. 🛑',
        "You've logged over 12 hours of focus time today! Great work, but your brain needs rest to retain this info. Get some sleep!",
        notificationDetails,
      );
      debugPrint('Triggered Burnout Guard Notification (12+ hours today)');
    } catch (e) {
      debugPrint('Error triggering burnout guard notification: $e');
    }
  }
}
