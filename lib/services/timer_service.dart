import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Top-level Break Time Calculator
/// Dynamically computes break duration based on ACTUAL elapsed focus time
/// using the configured Focus:Rest cycle ratio (default 5:1 ratio).
int calculateBreakMinutes(int elapsedSeconds, {double ratio = 5.0}) {
  final elapsedMinutes = elapsedSeconds / 60.0;
  // Standard 5:1 ratio: 5 mins study = 1 min break; 25 mins study = 5 mins break; 50 mins study = 10 mins break
  int breakMinutes = (elapsedMinutes / ratio).round();

  // Realistic limits: minimum 2 minutes (if studied > 5 min), maximum 20 minutes
  if (elapsedMinutes < 5) return 1;
  if (breakMinutes < 2) return 2;
  if (breakMinutes > 20) return 20;
  return breakMinutes;
}

/// Active Session snapshot model from `users/{uid}/active_session/current`
class ActiveSessionState {
  final String status; // "idle" | "running" | "paused"
  final String mode; // "focus" | "stopwatch" | "break"
  final String? courseId;
  final String? courseCode;
  final String? topicId;
  final int targetDurationSeconds;
  final int elapsedBeforePauseSeconds;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? lastHeartbeat;

  const ActiveSessionState({
    required this.status,
    this.mode = 'focus',
    this.courseId,
    this.courseCode,
    this.topicId,
    this.targetDurationSeconds = 1500,
    this.elapsedBeforePauseSeconds = 0,
    this.startedAt,
    this.pausedAt,
    this.lastHeartbeat,
  });

  bool get isRunning => status == 'running';
  bool get isPaused => status == 'paused';
  bool get isIdle => status == 'idle';

  factory ActiveSessionState.fromMap(Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return ActiveSessionState(
      status: (data['status'] as String?)?.toLowerCase() ?? 'idle',
      mode: (data['mode'] as String?)?.toLowerCase() ?? 'focus',
      courseId: data['courseId'] as String?,
      courseCode: data['courseCode'] as String?,
      topicId: data['topicId'] as String?,
      targetDurationSeconds: (data['targetDurationSeconds'] as num?)?.toInt() ?? 1500,
      elapsedBeforePauseSeconds: (data['elapsedBeforePauseSeconds'] as num?)?.toInt() ?? 0,
      startedAt: parseTimestamp(data['startedAt']),
      pausedAt: parseTimestamp(data['pausedAt']),
      lastHeartbeat: parseTimestamp(data['lastHeartbeat']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status,
      'mode': mode,
      'courseId': courseId,
      'courseCode': courseCode,
      'topicId': topicId,
      'targetDurationSeconds': targetDurationSeconds,
      'elapsedBeforePauseSeconds': elapsedBeforePauseSeconds,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'pausedAt': pausedAt != null ? Timestamp.fromDate(pausedAt!) : null,
      'lastHeartbeat': lastHeartbeat != null ? Timestamp.fromDate(lastHeartbeat!) : null,
    };
  }

  @override
  String toString() =>
      'ActiveSessionState(status: $status, mode: $mode, elapsedBeforePause: $elapsedBeforePauseSeconds, startedAt: $startedAt)';
}

/// TimerService manages:
/// 1. Real-time cross-device active session sync via `users/{uid}/active_session/current`
/// 2. Session completion persistence to `users/{uid}/study_sessions` and `users/{uid}/focus_sessions`
/// 3. User aggregate statistics updates (`totalFocusSeconds`, `lastStudyDate`, `streakDays`)
class TimerService {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  TimerService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore,
        _auth = auth;

  FirebaseFirestore? get firestore {
    if (_firestore != null) return _firestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get auth {
    if (_auth != null) return _auth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  DocumentReference<Map<String, dynamic>>? _activeSessionDoc(String uid) {
    final db = firestore;
    if (db == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid).collection('active_session').doc('current');
  }

  /// Real-time stream of the active session state from Firestore
  Stream<ActiveSessionState> watchActiveSession(String uid) {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) {
      return Stream.value(const ActiveSessionState(status: 'idle'));
    }

    return docRef.snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return const ActiveSessionState(status: 'idle');
      }
      return ActiveSessionState.fromMap(snapshot.data()!);
    }).handleError((err) {
      debugPrint('Error streaming active_session: $err');
      return const ActiveSessionState(status: 'idle');
    });
  }

  /// Writes START state transition to Firestore
  Future<void> startActiveSession({
    required String uid,
    required String mode, // 'focus' | 'stopwatch' | 'break'
    String? courseId,
    String? courseCode,
    String? topicId,
    int targetDurationSeconds = 1500,
  }) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    try {
      await docRef.set({
        'status': 'running',
        'mode': mode,
        'courseId': courseId,
        'courseCode': courseCode,
        'topicId': topicId,
        'targetDurationSeconds': targetDurationSeconds,
        'elapsedBeforePauseSeconds': 0,
        'startedAt': FieldValue.serverTimestamp(),
        'pausedAt': null,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Active session STARTED in Firestore for user $uid (mode: $mode)');
    } catch (e) {
      debugPrint('Error starting active session: $e');
    }
  }

  /// Writes PAUSE state transition to Firestore with accumulated elapsed seconds
  Future<void> pauseActiveSession({
    required String uid,
    required int currentElapsedSeconds,
  }) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    try {
      await docRef.set({
        'status': 'paused',
        'elapsedBeforePauseSeconds': currentElapsedSeconds,
        'pausedAt': FieldValue.serverTimestamp(),
        'lastHeartbeat': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Active session PAUSED in Firestore for user $uid (elapsed: ${currentElapsedSeconds}s)');
    } catch (e) {
      debugPrint('Error pausing active session: $e');
    }
  }

  /// Writes RESUME state transition to Firestore
  Future<void> resumeActiveSession(String uid) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    try {
      await docRef.set({
        'status': 'running',
        'startedAt': FieldValue.serverTimestamp(),
        'pausedAt': null,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Active session RESUMED in Firestore for user $uid');
    } catch (e) {
      debugPrint('Error resuming active session: $e');
    }
  }

  /// Resets active session document to status 'idle'
  Future<void> resetActiveSession(String uid) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    try {
      await docRef.set({
        'status': 'idle',
        'mode': 'focus',
        'courseId': null,
        'courseCode': null,
        'topicId': null,
        'targetDurationSeconds': 0,
        'elapsedBeforePauseSeconds': 0,
        'startedAt': null,
        'pausedAt': null,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
      debugPrint('Active session reset to IDLE in Firestore for user $uid');
    } catch (e) {
      debugPrint('Error resetting active session: $e');
    }
  }

  /// Persists completed session to `study_sessions`, updates user stats, and resets active session
  Future<bool> completeSession({
    required String uid,
    String? courseId,
    String? courseCode,
    String? topicId,
    required int finalElapsedSeconds,
    required String mode, // 'focus' or 'stopwatch'
    required DateTime sessionStartTime,
    DateTime? sessionEndTime,
  }) async {
    final db = firestore;
    if (db == null || uid.isEmpty) return false;

    // Minimum threshold check: Only persist sessions with duration >= 60 seconds (1 minute)
    if (finalElapsedSeconds < 60) {
      debugPrint('Session discarded: duration ($finalElapsedSeconds s) below 60s minimum threshold');
      await resetActiveSession(uid);
      return false;
    }

    final now = sessionEndTime ?? DateTime.now();
    final mins = (finalElapsedSeconds / 60).round().clamp(1, 100000);

    try {
      // 1. Add document to users/{uid}/study_sessions
      final studySessionData = {
        'courseId': courseId ?? '',
        'courseCode': courseCode ?? 'General Study',
        'topicId': topicId ?? '',
        'durationSeconds': finalElapsedSeconds,
        'durationMinutes': mins,
        'mode': mode,
        'startedAt': Timestamp.fromDate(sessionStartTime),
        'endedAt': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'completed': true,
      };

      await db
          .collection('users')
          .doc(uid)
          .collection('study_sessions')
          .add(studySessionData);

      // Also add to users/{uid}/focus_sessions for analytics & live Insights stream
      await db
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .add({
        'subject': courseCode ?? 'General Study',
        'subjectName': courseCode ?? 'General Study',
        'durationSeconds': finalElapsedSeconds,
        'durationMinutes': mins,
        'startTime': Timestamp.fromDate(sessionStartTime),
        'endTime': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 2. Update User Aggregate Stats in users/{uid}
      final userRef = db.collection('users').doc(uid);
      try {
        final userSnap = await userRef.get();
        final userData = userSnap.data() ?? {};

        // Calculate Streak
        DateTime? lastStudied;
        final lastStudiedRaw = userData['lastStudyDate'] ?? userData['lastStudiedAt'];
        if (lastStudiedRaw is Timestamp) {
          lastStudied = lastStudiedRaw.toDate();
        } else if (lastStudiedRaw is String) {
          lastStudied = DateTime.tryParse(lastStudiedRaw);
        }

        int currentStreak = (userData['streakDays'] as num?)?.toInt() ?? 0;
        final today = DateTime(now.year, now.month, now.day);

        if (lastStudied == null) {
          currentStreak = 1;
        } else {
          final lastDay = DateTime(lastStudied.year, lastStudied.month, lastStudied.day);
          final diffDays = today.difference(lastDay).inDays;
          if (diffDays == 1) {
            currentStreak += 1;
          } else if (diffDays > 1) {
            currentStreak = 1;
          } else if (diffDays == 0 && currentStreak == 0) {
            currentStreak = 1;
          }
        }

        await userRef.set({
          'totalFocusSeconds': FieldValue.increment(finalElapsedSeconds),
          'totalFocusMinutes': FieldValue.increment(mins),
          'todaysFocusMinutes': FieldValue.increment(mins),
          'lastStudyDate': Timestamp.fromDate(today),
          'lastStudiedAt': Timestamp.fromDate(now),
          'streakDays': currentStreak,
        }, SetOptions(merge: true));
        debugPrint('Updated user aggregate stats: +$finalElapsedSeconds s, streak: $currentStreak');
      } catch (e) {
        debugPrint('Error updating user aggregate stats: $e');
      }

      // 3. Reset users/{uid}/active_session/current to status: 'idle'
      await resetActiveSession(uid);
      debugPrint('Successfully persisted study session ($mins mins, $finalElapsedSeconds s) for user $uid');
      return true;
    } catch (e) {
      debugPrint('Error completing study session: $e');
      await resetActiveSession(uid);
      return false;
    }
  }
}
