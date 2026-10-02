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

/// Formats clean course and session titles without repeating codes or redundant prefixes.
/// E.g.
/// - ("MATH 157", "Differential Calculus") -> "MATH 157: Differential Calculus"
/// - ("MATH 157", "MATH 157 - Differential Calculus") -> "MATH 157: Differential Calculus"
/// - ("MATH 157", "MATH 157") -> "MATH 157"
/// - ("MATH 157", "") -> "MATH 157"
/// - ("", "MATH 157 - Calculus") -> "MATH 157: Calculus"
String formatCleanSessionTitle({
  String? courseCode,
  String? courseTitle,
  String? fallback,
}) {
  final code = (courseCode ?? '').trim();
  var title = (courseTitle ?? '').trim();
  final fb = (fallback ?? '').trim();

  if (code.isEmpty && title.isEmpty) {
    if (fb.isNotEmpty) {
      return formatCleanSessionTitle(courseTitle: fb);
    }
    return 'General Study';
  }

  if (code.isEmpty) {
    if (title.contains(' - ')) {
      final parts = title.split(' - ');
      final c = parts.first.trim();
      final rest = parts.sublist(1).join(' - ').trim();
      if (c.isNotEmpty && rest.isNotEmpty) {
        return '$c: $rest';
      }
    } else if (title.contains(': ')) {
      final parts = title.split(': ');
      final c = parts.first.trim();
      final rest = parts.sublist(1).join(': ').trim();
      if (c.isNotEmpty && rest.isNotEmpty) {
        return '$c: $rest';
      }
    }
    return title;
  }

  if (title.isEmpty) {
    return code;
  }

  if (title.toLowerCase() == code.toLowerCase()) {
    return code;
  }

  // Remove code from title if title starts with code
  if (title.toLowerCase().startsWith(code.toLowerCase())) {
    title = title.substring(code.length).trim();
    if (title.startsWith('-') || title.startsWith(':')) {
      title = title.substring(1).trim();
    }
  }

  if (title.isEmpty) {
    return code;
  }

  return '$code: $title';
}

/// Client-side deduplication filter for study session streams:
/// 1. Filters out duplicate session/document IDs.
/// 2. Overlap safeguard: if two sessions for the same user and course start within
///    90 seconds of each other with identical (or within 5s) durations, collapses
///    them into a single entry to suppress historical duplicates.
List<T> deduplicateStudySessions<T>({
  required List<T> sessions,
  required String Function(T) getId,
  required String Function(T) getCourseKey,
  required DateTime Function(T) getStartTime,
  required int Function(T) getDurationSeconds,
}) {
  if (sessions.isEmpty) return const [];

  final List<T> uniqueById = [];
  final Set<String> seenIds = {};

  for (final s in sessions) {
    final id = getId(s).trim();
    if (id.isNotEmpty) {
      if (seenIds.contains(id)) continue;
      seenIds.add(id);
    }
    uniqueById.add(s);
  }

  // Sort chronologically by start time
  uniqueById.sort((a, b) => getStartTime(a).compareTo(getStartTime(b)));

  final List<T> collapsed = [];
  for (final s in uniqueById) {
    if (collapsed.isEmpty) {
      collapsed.add(s);
      continue;
    }

    final prev = collapsed.last;
    final sameCourse = getCourseKey(prev).toLowerCase().trim() == getCourseKey(s).toLowerCase().trim();
    final timeDiffSecs = getStartTime(s).difference(getStartTime(prev)).inSeconds.abs();
    final durDiffSecs = (getDurationSeconds(s) - getDurationSeconds(prev)).abs();
    final durMinsPrev = (getDurationSeconds(prev) / 60).round();
    final durMinsCur = (getDurationSeconds(s) / 60).round();
    final sameDuration = durDiffSecs <= 5 || durMinsPrev == durMinsCur;

    if (sameCourse && timeDiffSecs <= 90 && sameDuration) {
      // Historical duplicate detected: collapse into single entry
      continue;
    }

    collapsed.add(s);
  }

  return collapsed;
}

/// Active Session snapshot model from `users/{uid}/active_session/current`
class ActiveSessionState {
  final String? sessionId;
  final String status; // "idle" | "running" | "paused"
  final String mode; // "focus" | "stopwatch" | "break"
  final String? courseId;
  final String? courseCode;
  final String? courseTitle;
  final String? topicId;
  final String? topicName;
  final int targetDurationSeconds;
  final int elapsedBeforePauseSeconds;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? lastHeartbeat;

  const ActiveSessionState({
    this.sessionId,
    required this.status,
    this.mode = 'focus',
    this.courseId,
    this.courseCode,
    this.courseTitle,
    this.topicId,
    this.topicName,
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
      sessionId: data['sessionId'] as String? ?? data['id'] as String?,
      status: (data['status'] as String?)?.toLowerCase() ?? 'idle',
      mode: (data['mode'] as String?)?.toLowerCase() ?? 'focus',
      courseId: data['courseId'] as String?,
      courseCode: data['courseCode'] as String?,
      courseTitle: data['courseTitle'] as String?,
      topicId: data['topicId'] as String?,
      topicName: data['topicName'] as String?,
      targetDurationSeconds: (data['targetDurationSeconds'] as num?)?.toInt() ?? 1500,
      elapsedBeforePauseSeconds: (data['elapsedBeforePauseSeconds'] as num?)?.toInt() ?? 0,
      startedAt: parseTimestamp(data['startedAt']),
      pausedAt: parseTimestamp(data['pausedAt']),
      lastHeartbeat: parseTimestamp(data['lastHeartbeat']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'status': status,
      'mode': mode,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'topicId': topicId,
      'topicName': topicName,
      'targetDurationSeconds': targetDurationSeconds,
      'elapsedBeforePauseSeconds': elapsedBeforePauseSeconds,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'pausedAt': pausedAt != null ? Timestamp.fromDate(pausedAt!) : null,
      'lastHeartbeat': lastHeartbeat != null ? Timestamp.fromDate(lastHeartbeat!) : null,
    };
  }

  @override
  String toString() =>
      'ActiveSessionState(sessionId: $sessionId, status: $status, mode: $mode, elapsedBeforePause: $elapsedBeforePauseSeconds, startedAt: $startedAt)';
}

/// TimerService manages:
/// 1. Real-time cross-device active session sync via `users/{uid}/active_session/current`
/// 2. Session completion persistence to `users/{uid}/study_sessions` and `users/{uid}/focus_sessions`
/// 3. In-memory concurrency mutex and deterministic idempotent document keys
/// 4. User aggregate statistics updates (`totalFocusSeconds`, `lastStudyDate`, `streakDays`)
class TimerService {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  bool _isSavingSession = false;

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

  /// Writes START state transition to Firestore with idempotent sessionId
  Future<void> startActiveSession({
    required String uid,
    required String mode, // 'focus' | 'stopwatch' | 'break'
    String? sessionId,
    String? courseId,
    String? courseCode,
    String? courseTitle,
    String? topicId,
    String? topicName,
    int targetDurationSeconds = 1500,
  }) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    final sId = (sessionId != null && sessionId.isNotEmpty)
        ? sessionId
        : 'session_${DateTime.now().millisecondsSinceEpoch}_$uid';

    try {
      await docRef.set({
        'sessionId': sId,
        'status': 'running',
        'mode': mode,
        'courseId': courseId,
        'courseCode': courseCode,
        'courseTitle': courseTitle,
        'topicId': topicId,
        'topicName': topicName,
        'targetDurationSeconds': targetDurationSeconds,
        'elapsedBeforePauseSeconds': 0,
        'startedAt': FieldValue.serverTimestamp(),
        'pausedAt': null,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('Active session STARTED in Firestore for user $uid (sessionId: $sId, mode: $mode)');
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
        'sessionId': null,
        'status': 'idle',
        'mode': 'focus',
        'courseId': null,
        'courseCode': null,
        'courseTitle': null,
        'topicId': null,
        'topicName': null,
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

  /// Persists completed session to `study_sessions`, updates user stats, and resets active session.
  ///
  /// CRITICAL ARCHITECTURAL SAFEGUARDS:
  /// 1. Save Execution Lock (in-memory mutex `_isSavingSession`) to prevent concurrent saves.
  /// 2. Deterministic Idempotent Document Key: uses `.doc(sessionId).set(..., SetOptions(merge: true))`
  ///    instead of `.add()`, guaranteeing exactly ONE document in Firestore across all devices.
  Future<bool> completeSession({
    required String uid,
    String? sessionId,
    String? courseId,
    String? courseCode,
    String? courseTitle,
    String? topicId,
    String? topicName,
    required int finalElapsedSeconds,
    required String mode, // 'focus' or 'stopwatch'
    required DateTime sessionStartTime,
    DateTime? sessionEndTime,
  }) async {
    if (_isSavingSession) {
      debugPrint('TimerService: completeSession already in progress, ignoring concurrent save');
      return false;
    }
    _isSavingSession = true;

    try {
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

      // Deterministic session ID ensures idempotent writes across devices
      final resolvedSessionId = (sessionId != null && sessionId.isNotEmpty)
          ? sessionId
          : 'session_${sessionStartTime.millisecondsSinceEpoch}_$uid';

      final cleanTitle = formatCleanSessionTitle(
        courseCode: courseCode,
        courseTitle: courseTitle,
      );

      // 1. Idempotently write to users/{uid}/study_sessions/{sessionId}
      final studySessionData = {
        'sessionId': resolvedSessionId,
        'id': resolvedSessionId,
        'courseId': courseId ?? '',
        'courseCode': courseCode ?? 'General Study',
        'courseTitle': courseTitle ?? courseCode ?? 'General Study',
        'cleanTitle': cleanTitle,
        'topicId': topicId ?? '',
        'topicName': topicName ?? '',
        'durationSeconds': finalElapsedSeconds,
        'durationMinutes': mins,
        'mode': mode,
        'startedAt': Timestamp.fromDate(sessionStartTime),
        'endedAt': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'completed': true,
      };

      await db
          .collection('users')
          .doc(uid)
          .collection('study_sessions')
          .doc(resolvedSessionId)
          .set(studySessionData, SetOptions(merge: true));

      // Also idempotently write to users/{uid}/focus_sessions/{sessionId} for analytics & live Insights stream
      await db
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .doc(resolvedSessionId)
          .set({
        'sessionId': resolvedSessionId,
        'id': resolvedSessionId,
        'subject': courseCode ?? 'General Study',
        'subjectName': courseCode ?? 'General Study',
        'courseId': courseId ?? '',
        'courseCode': courseCode ?? 'General Study',
        'courseTitle': courseTitle ?? courseCode ?? 'General Study',
        'cleanTitle': cleanTitle,
        'topicId': topicId ?? '',
        'topicName': topicName ?? '',
        'durationSeconds': finalElapsedSeconds,
        'durationMinutes': mins,
        'startTime': Timestamp.fromDate(sessionStartTime),
        'endTime': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

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
      debugPrint('Successfully persisted study session ($resolvedSessionId, $mins mins) for user $uid');
      return true;
    } catch (e) {
      debugPrint('Error completing study session: $e');
      await resetActiveSession(uid);
      return false;
    } finally {
      _isSavingSession = false;
    }
  }
}
