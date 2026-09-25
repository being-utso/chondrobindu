import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import '../firebase_options.dart';
import '../models/syllabus_models.dart';
import 'home_widget_service.dart';
import 'notification_service.dart';

/// Top-level callback dispatcher for Workmanager background execution
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('Workmanager executing background task: $task');

    WidgetsFlutterBinding.ensureInitialized();

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
    } catch (e) {
      debugPrint('Firebase init error in background task: $e');
    }

    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint('NotificationService init error in background task: $e');
    }

    try {
      await BackgroundAuditService.performDailyAudit();
    } catch (e) {
      debugPrint('Error performing background audit: $e');
      return Future.value(false);
    }

    return Future.value(true);
  });
}

class BackgroundAuditService {
  static const String dailyAuditTaskName = 'chondrobindu_daily_audit_task';
  static const String periodicTaskUniqueName = 'chondrobindu_daily_audit_periodic';

  static const List<String> coreSubjects = [
    'Physics',
    'Chemistry',
    'Higher Mathematics',
    'Biology',
  ];

  /// Initializes Workmanager and registers the daily periodic background audit task
  static Future<void> initializeWorkmanager() async {
    try {
      await Workmanager().initialize(
        callbackDispatcher,
      );

      // Register daily periodic task with network and battery-saving constraints
      await Workmanager().registerPeriodicTask(
        periodicTaskUniqueName,
        dailyAuditTaskName,
        frequency: const Duration(hours: 24),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
      debugPrint('Workmanager daily audit task successfully registered.');
    } catch (e) {
      debugPrint('Error initializing Workmanager: $e');
    }
  }

  /// Groups 1st and 2nd papers into the 4 core subjects
  static bool matchesCoreSubject(String candidate, String coreSubject) {
    final cleanCandidate = candidate.toLowerCase().trim();
    final cleanCore = coreSubject.toLowerCase().trim();

    if (cleanCore == 'physics') {
      return cleanCandidate.contains('physics') || cleanCandidate.contains('পদার্থ');
    } else if (cleanCore == 'chemistry') {
      return cleanCandidate.contains('chem') || cleanCandidate.contains('রসায়ন');
    } else if (cleanCore == 'higher mathematics' || cleanCore == 'higher math') {
      return cleanCandidate.contains('higher math') ||
          cleanCandidate.contains('higher mathematics') ||
          cleanCandidate.contains('উচ্চতর গণিত') ||
          cleanCandidate.contains('math') ||
          cleanCandidate.contains('গণিত');
    } else if (cleanCore == 'biology') {
      return cleanCandidate.contains('bio') || cleanCandidate.contains('জীব');
    }

    return cleanCandidate.contains(cleanCore);
  }

  /// Extracts the most recent activity timestamp from Syllabus sections for a core subject
  static DateTime? getLatestSyllabusActivityForCore(
    List<Subject> subjects,
    String coreSubject,
  ) {
    DateTime? latest;

    for (final subject in subjects) {
      if (matchesCoreSubject(subject.title, coreSubject)) {
        if (subject.lastModified != null) {
          if (latest == null || subject.lastModified!.isAfter(latest)) {
            latest = subject.lastModified;
          }
        }
        for (final chapter in subject.chapters) {
          if (chapter.lastModified != null) {
            if (latest == null || chapter.lastModified!.isAfter(latest)) {
              latest = chapter.lastModified;
            }
          }
          for (final section in chapter.sections) {
            if (section.lastModified != null) {
              if (latest == null || section.lastModified!.isAfter(latest)) {
                latest = section.lastModified;
              }
            }
          }
        }
      }
    }

    return latest;
  }

  /// Evaluates the most recent timer focus session for a core subject
  static DateTime? getLatestTimerActivityForCore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> focusDocs,
    String coreSubject,
  ) {
    DateTime? latest;

    for (final doc in focusDocs) {
      final data = doc.data();
      final subj = (data['subjectName'] as String?) ?? (data['subject'] as String?) ?? '';

      if (matchesCoreSubject(subj, coreSubject)) {
        final dynamic rawTime = data['timestamp'] ?? data['startTime'] ?? data['endTime'] ?? data['createdAt'];
        DateTime? dt;
        if (rawTime is Timestamp) {
          dt = rawTime.toDate();
        } else if (rawTime is String) {
          dt = DateTime.tryParse(rawTime);
        }

        if (dt != null) {
          if (latest == null || dt.isAfter(latest)) {
            latest = dt;
          }
        }
      }
    }

    return latest;
  }

  /// Performs the full daily audit:
  /// Task 2: Syllabus Decay check for Physics, Chemistry, Higher Mathematics, Biology (> 14 days)
  /// Task 3: Weekly Wrap-Up (Sunday evening summary of past 7 days focus time)
  static Future<void> performDailyAudit({
    FirebaseFirestore? firestoreInstance,
    FirebaseAuth? authInstance,
    NotificationService? notificationServiceInstance,
    DateTime? mockNow,
  }) async {
    final auth = authInstance ?? FirebaseAuth.instance;
    final firestore = firestoreInstance ?? FirebaseFirestore.instance;
    final notif = notificationServiceInstance ?? NotificationService();
    final now = mockNow ?? DateTime.now();

    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      debugPrint('BackgroundAudit: User not logged in. Skipping background audit.');
      return;
    }

    // 0. Update Native Home Screen Countdown Widget with current days remaining
    try {
      final userDoc = await firestore.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (userDoc.exists && data != null) {
        final eventName = data['target_event_name'] as String?;
        final rawDate = data['target_event_date'];
        DateTime? eventDate;
        if (rawDate is Timestamp) {
          eventDate = rawDate.toDate();
        } else if (rawDate is String) {
          eventDate = DateTime.tryParse(rawDate);
        }

        await HomeWidgetService.updateHomeWidget(
          targetEventName: eventName,
          targetEventDate: eventDate,
        );
      }
    } catch (e) {
      debugPrint('BackgroundAudit: Error updating HomeWidget in background: $e');
    }

    // 1. Fetch user syllabus state
    List<Subject> allSyllabusSubjects = [];
    try {
      final syllabusSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('syllabus_state')
          .get();

      for (final doc in syllabusSnap.docs) {
        final data = doc.data();
        if (data['subjects'] != null && data['subjects'] is List) {
          final rawList = data['subjects'] as List<dynamic>;
          for (final item in rawList) {
            if (item is Map) {
              allSyllabusSubjects.add(Subject.fromMap(Map<String, dynamic>.from(item)));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('BackgroundAudit: Error reading syllabus from Firestore: $e');
    }

    // 2. Fetch user focus sessions
    List<QueryDocumentSnapshot<Map<String, dynamic>>> focusDocs = [];
    try {
      final sessionsSnap = await firestore
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .orderBy('timestamp', descending: true)
          .limit(300)
          .get();
      focusDocs = sessionsSnap.docs;
    } catch (e) {
      debugPrint('BackgroundAudit: Error reading focus sessions from Firestore: $e');
    }

    // Task 2: Audit Syllabus Decay for Grouped Papers (> 14 Days)
    await auditSyllabusDecay(
      allSyllabusSubjects: allSyllabusSubjects,
      focusDocs: focusDocs,
      notificationService: notif,
      now: now,
    );

    // Task 3: Weekly Wrap-Up (On Sunday)
    if (now.weekday == DateTime.sunday) {
      await auditWeeklyWrapUp(
        focusDocs: focusDocs,
        notificationService: notif,
        now: now,
      );
    }
  }

  /// Task 2: Checks if neither paper for Physics, Chemistry, Higher Mathematics, or Biology has been touched in 14+ days
  static Future<void> auditSyllabusDecay({
    required List<Subject> allSyllabusSubjects,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> focusDocs,
    required NotificationService notificationService,
    required DateTime now,
  }) async {
    for (final core in coreSubjects) {
      // 1. Check if this core subject exists in the user's Syllabus
      final hasInSyllabus = allSyllabusSubjects.any((s) => matchesCoreSubject(s.title, core));
      if (!hasInSyllabus) continue;

      // 2. Determine last activity timestamp from Syllabus and Focus Timer
      final latestSyllabus = getLatestSyllabusActivityForCore(allSyllabusSubjects, core);
      final latestTimer = getLatestTimerActivityForCore(focusDocs, core);

      DateTime? latestActivity;
      if (latestSyllabus != null && latestTimer != null) {
        latestActivity = latestSyllabus.isAfter(latestTimer) ? latestSyllabus : latestTimer;
      } else {
        latestActivity = latestSyllabus ?? latestTimer;
      }

      // 3. If neither paper has been touched in over 14 days, trigger Syllabus Decay Nudge
      if (latestActivity != null) {
        final daysSince = now.difference(latestActivity).inDays;
        if (daysSince >= 14) {
          await notificationService.showSyllabusDecayNudge(core);
        }
      }
    }
  }

  /// Task 3: Aggregates focus sessions over the past 7 days on Sunday and fires weekly wrap-up notification
  static Future<void> auditWeeklyWrapUp({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> focusDocs,
    required NotificationService notificationService,
    required DateTime now,
  }) async {
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    int totalMinutes = 0;

    for (final doc in focusDocs) {
      final data = doc.data();
      final dynamic rawTime = data['timestamp'] ?? data['startTime'] ?? data['date'];
      DateTime? dt;

      if (rawTime is Timestamp) {
        dt = rawTime.toDate();
      } else if (rawTime is String) {
        dt = DateTime.tryParse(rawTime);
      }

      if (dt != null && dt.isAfter(sevenDaysAgo)) {
        final mins = (data['durationMinutes'] as num?)?.toInt() ??
            (((data['durationSeconds'] as num?)?.toInt() ?? 0) / 60).round();
        totalMinutes += mins;
      }
    }

    final totalHours = totalMinutes / 60.0;
    await notificationService.showWeeklyWrapUpNotification(totalHours);
  }
}
