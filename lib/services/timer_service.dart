import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/study_session_model.dart';
import '../models/analytics_models.dart';
import '../utils/client_identity.dart';

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

/// Bulletproof UI deduplication filter (Inspection & Collapse):
/// Does NOT rely solely on string equality. Checks for TIME OVERLAP (within 180s and duration within 120s)
/// and cross-matches courseCode and courseTitle.
List<StudySession> collapseDuplicateSessions(List<StudySession> sessions) {
  if (sessions.isEmpty) return [];

  // Sort chronologically descending
  final sorted = List<StudySession>.from(sessions)
    ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  final List<StudySession> merged = [];

  for (final candidate in sorted) {
    int existingIndex = -1;

    for (int i = 0; i < merged.length; i++) {
      final existing = merged[i];

      // 1. Same explicit ID or sessionId
      if ((candidate.id.isNotEmpty && candidate.id == existing.id) ||
          (candidate.sessionId.isNotEmpty && candidate.sessionId == existing.sessionId)) {
        existingIndex = i;
        break;
      }

      // 2. Overlapping time intervals (started within 3 minutes of each other OR identical duration)
      final startDiff = (candidate.startedAt.difference(existing.startedAt).inSeconds).abs();
      final durationDiff = (candidate.durationSeconds - existing.durationSeconds).abs();

      // Check if course matches via code OR title cross-match
      final cCode1 = candidate.courseCode.toLowerCase().replaceAll(' ', '');
      final cCode2 = existing.courseCode.toLowerCase().replaceAll(' ', '');
      final cTitle1 = candidate.courseTitle?.toLowerCase() ?? '';
      final cTitle2 = existing.courseTitle?.toLowerCase() ?? '';

      final bool isSameCourse = (cCode1.isNotEmpty && (cCode1 == cCode2 || (cTitle2.isNotEmpty && cTitle2.contains(cCode1)))) ||
                                (cCode2.isNotEmpty && (cCode2 == cCode1 || (cTitle1.isNotEmpty && cTitle1.contains(cCode2)))) ||
                                (cTitle1.isNotEmpty && cTitle1 == cTitle2) ||
                                (candidate.courseId.isNotEmpty && candidate.courseId == existing.courseId);

      // If intervals overlap or start within 180 seconds with matching course
      if (isSameCourse && startDiff <= 180 && durationDiff <= 120) {
        existingIndex = i;
        break;
      }
    }

    if (existingIndex != -1) {
      // Keep the version that has more complete details (e.g. topic tags or detailed notes)
      final existing = merged[existingIndex];
      final bool candidateHasMoreInfo = (candidate.topicName.isNotEmpty && existing.topicName.isEmpty) ||
                                       ((candidate.courseTitle?.length ?? 0) > (existing.courseTitle?.length ?? 0)) ||
                                       (candidate.topicIds.length > existing.topicIds.length);
      if (candidateHasMoreInfo) {
        merged[existingIndex] = candidate;
      }
    } else {
      merged.add(candidate);
    }
  }

  return merged;
}

/// Backward compatibility alias for collapseDuplicateSessions
List<StudySession> deduplicateSessions(List<StudySession> sessions) => collapseDuplicateSessions(sessions);

/// Bulletproof UI deduplication filter for StudySessionLog / FocusSession:
List<StudySessionLog> collapseDuplicateSessionLogs(List<StudySessionLog> sessions) {
  if (sessions.isEmpty) return [];

  final sorted = List<StudySessionLog>.from(sessions)
    ..sort((a, b) => (b.startTime ?? b.date).compareTo(a.startTime ?? a.date));

  final List<StudySessionLog> merged = [];

  for (final candidate in sorted) {
    int existingIndex = -1;

    final candidateStart = candidate.startTime ?? candidate.date;
    final candidateDur = candidate.durationInSeconds > 0 ? candidate.durationInSeconds : candidate.durationInMinutes * 60;

    for (int i = 0; i < merged.length; i++) {
      final existing = merged[i];

      if (candidate.id.isNotEmpty && candidate.id == existing.id) {
        existingIndex = i;
        break;
      }

      final existingStart = existing.startTime ?? existing.date;
      final existingDur = existing.durationInSeconds > 0 ? existing.durationInSeconds : existing.durationInMinutes * 60;

      final startDiff = candidateStart.difference(existingStart).inSeconds.abs();
      final durationDiff = (candidateDur - existingDur).abs();

      final cCode1 = (candidate.courseCode ?? candidate.subjectName).toLowerCase().replaceAll(' ', '');
      final cCode2 = (existing.courseCode ?? existing.subjectName).toLowerCase().replaceAll(' ', '');
      final cTitle1 = (candidate.courseTitle ?? candidate.subjectName).toLowerCase();
      final cTitle2 = (existing.courseTitle ?? existing.subjectName).toLowerCase();

      final bool isSameCourse = (cCode1.isNotEmpty && (cCode1 == cCode2 || (cTitle2.isNotEmpty && cTitle2.contains(cCode1)))) ||
                                (cCode2.isNotEmpty && (cCode2 == cCode1 || (cTitle1.isNotEmpty && cTitle1.contains(cCode2)))) ||
                                (cTitle1.isNotEmpty && cTitle1 == cTitle2) ||
                                (candidate.subjectId.isNotEmpty && candidate.subjectId == existing.subjectId);

      if (isSameCourse && startDiff <= 180 && durationDiff <= 120) {
        existingIndex = i;
        break;
      }
    }

    if (existingIndex != -1) {
      final existing = merged[existingIndex];
      final bool candidateHasMoreInfo = ((candidate.topicName?.isNotEmpty ?? false) && (existing.topicName?.isEmpty ?? true)) ||
                                       ((candidate.courseTitle?.length ?? 0) > (existing.courseTitle?.length ?? 0));
      if (candidateHasMoreInfo) {
        merged[existingIndex] = candidate;
      }
    } else {
      merged.add(candidate);
    }
  }

  return merged;
}

/// Backward compatibility alias for collapseDuplicateSessionLogs
List<StudySessionLog> deduplicateSessionLogs(List<StudySessionLog> sessions) => collapseDuplicateSessionLogs(sessions);

/// One-time historical database purge and merge utility:
/// Fetches all documents in users/{uid}/study_sessions and users/{uid}/focus_sessions.
/// Groups documents that share overlapping start/end times (+/- 3 minutes) and the same course.
/// Keeps the document with the most metadata and deletes duplicate documents via WriteBatch.
Future<int> purgeHistoricalSessionDuplicates(String uid) async {
  if (uid.isEmpty) return 0;
  final db = FirebaseFirestore.instance;
  int totalDeleted = 0;

  try {
    // 1. Purge study_sessions collection
    final studySnap = await db.collection('users').doc(uid).collection('study_sessions').get();
    if (studySnap.docs.isNotEmpty) {
      final sessions = studySnap.docs.map((d) => StudySession.fromFirestore(d)).toList();

      // Group overlapping documents
      final List<StudySession> survivors = [];
      final Set<String> idsToDelete = {};

      for (final s in sessions) {
        int matchIdx = -1;
        for (int i = 0; i < survivors.length; i++) {
          final ex = survivors[i];
          final startDiff = s.startedAt.difference(ex.startedAt).inSeconds.abs();
          final durationDiff = (s.durationSeconds - ex.durationSeconds).abs();

          final cCode1 = s.courseCode.toLowerCase().replaceAll(' ', '');
          final cCode2 = ex.courseCode.toLowerCase().replaceAll(' ', '');
          final cTitle1 = s.courseTitle?.toLowerCase() ?? '';
          final cTitle2 = ex.courseTitle?.toLowerCase() ?? '';

          final bool sameCourse = (cCode1.isNotEmpty && (cCode1 == cCode2 || (cTitle2.isNotEmpty && cTitle2.contains(cCode1)))) ||
                                  (cCode2.isNotEmpty && (cCode2 == cCode1 || (cTitle1.isNotEmpty && cTitle1.contains(cCode2)))) ||
                                  (cTitle1.isNotEmpty && cTitle1 == cTitle2) ||
                                  (s.courseId.isNotEmpty && s.courseId == ex.courseId);

          if (sameCourse && startDiff <= 180 && durationDiff <= 120) {
            matchIdx = i;
            break;
          }
        }

        if (matchIdx != -1) {
          final ex = survivors[matchIdx];
          final bool sHasMoreInfo = (s.topicName.isNotEmpty && ex.topicName.isEmpty) ||
                                    ((s.courseTitle?.length ?? 0) > (ex.courseTitle?.length ?? 0)) ||
                                    (s.topicIds.length > ex.topicIds.length);
          if (sHasMoreInfo) {
            idsToDelete.add(ex.id);
            survivors[matchIdx] = s;
          } else {
            idsToDelete.add(s.id);
          }
        } else {
          survivors.add(s);
        }
      }

      if (idsToDelete.isNotEmpty) {
        // Firestore batch max size is 500
        final batches = <List<String>>[];
        final idList = idsToDelete.toList();
        for (var i = 0; i < idList.length; i += 400) {
          batches.add(idList.sublist(i, (i + 400 > idList.length) ? idList.length : i + 400));
        }

        for (final chunk in batches) {
          final batch = db.batch();
          for (final id in chunk) {
            batch.delete(db.collection('users').doc(uid).collection('study_sessions').doc(id));
            batch.delete(db.collection('users').doc(uid).collection('focus_sessions').doc(id));
          }
          await batch.commit();
        }
        totalDeleted = idsToDelete.length;
        debugPrint('purgeHistoricalSessionDuplicates: deleted $totalDeleted duplicate records for user $uid');
      }
    }
  } catch (e) {
    debugPrint('purgeHistoricalSessionDuplicates error: $e');
  }

  return totalDeleted;
}

/// Active Session snapshot model from `users/{uid}/active_session/current`
class ActiveSessionState {
  final String? sessionId;
  final String? leadClientId;
  final String status; // "idle" | "running" | "paused"
  final String mode; // "focus" | "stopwatch" | "break"
  final String? courseId;
  final String? courseCode;
  final String? courseTitle;
  final String? topicId;
  final String? topicName;
  final int targetDurationSeconds;
  final int elapsedBeforePauseSeconds;
  final bool isFinalized;
  final DateTime? startedAt;
  final DateTime? pausedAt;
  final DateTime? endedAt;
  final DateTime? lastHeartbeat;

  const ActiveSessionState({
    this.sessionId,
    this.leadClientId,
    required this.status,
    this.mode = 'focus',
    this.courseId,
    this.courseCode,
    this.courseTitle,
    this.topicId,
    this.topicName,
    this.targetDurationSeconds = 1500,
    this.elapsedBeforePauseSeconds = 0,
    this.isFinalized = false,
    this.startedAt,
    this.pausedAt,
    this.endedAt,
    this.lastHeartbeat,
  });

  int get targetSeconds => targetDurationSeconds;
  int get elapsedSeconds => elapsedBeforePauseSeconds;
  bool get isRunning => status == 'running' && !isFinalized;
  bool get isPaused => status == 'paused' && !isFinalized;
  bool get isIdle => status == 'idle' || isFinalized;

  factory ActiveSessionState.fromMap(Map<String, dynamic> data) {
    DateTime? parseTimestamp(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final rawTarget = data['targetSeconds'] ?? data['targetDurationSeconds'];
    final rawElapsed = data['elapsedSeconds'] ?? data['elapsedBeforePauseSeconds'];

    return ActiveSessionState(
      sessionId: data['sessionId'] as String? ?? data['id'] as String?,
      leadClientId: data['leadClientId'] as String?,
      status: (data['status'] as String?)?.toLowerCase() ?? 'idle',
      mode: (data['mode'] as String?)?.toLowerCase() ?? 'focus',
      courseId: data['courseId'] as String?,
      courseCode: data['courseCode'] as String?,
      courseTitle: data['courseTitle'] as String?,
      topicId: data['topicId'] as String?,
      topicName: data['topicName'] as String?,
      targetDurationSeconds: (rawTarget as num?)?.toInt() ?? 1500,
      elapsedBeforePauseSeconds: (rawElapsed as num?)?.toInt() ?? 0,
      isFinalized: data['isFinalized'] == true,
      startedAt: parseTimestamp(data['startedAt']),
      pausedAt: parseTimestamp(data['pausedAt']),
      endedAt: parseTimestamp(data['endedAt']),
      lastHeartbeat: parseTimestamp(data['lastHeartbeat']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'leadClientId': leadClientId,
      'status': status,
      'mode': mode,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'topicId': topicId,
      'topicName': topicName,
      'targetSeconds': targetDurationSeconds,
      'targetDurationSeconds': targetDurationSeconds,
      'elapsedSeconds': elapsedBeforePauseSeconds,
      'elapsedBeforePauseSeconds': elapsedBeforePauseSeconds,
      'isFinalized': isFinalized,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'pausedAt': pausedAt != null ? Timestamp.fromDate(pausedAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'lastHeartbeat': lastHeartbeat != null ? Timestamp.fromDate(lastHeartbeat!) : null,
    };
  }

  @override
  String toString() =>
      'ActiveSessionState(sessionId: $sessionId, leader: $leadClientId, status: $status, mode: $mode, elapsedBeforePause: $elapsedBeforePauseSeconds, startedAt: $startedAt)';
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

  /// Writes START state transition to Firestore with idempotent sessionId and leadClientId
  Future<void> startActiveSession({
    required String uid,
    required String mode, // 'focus' | 'stopwatch' | 'break'
    String? sessionId,
    String? leadClientId,
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
        : ClientIdentity.newSessionId();
    final clientId = (leadClientId != null && leadClientId.isNotEmpty)
        ? leadClientId
        : ClientIdentity.instanceId;

    try {
      await docRef.set({
        'sessionId': sId,
        'leadClientId': clientId,
        'courseId': courseId ?? '',
        'courseCode': courseCode ?? 'General Study',
        'courseTitle': courseTitle ?? courseCode ?? 'General Study',
        'topicId': topicId ?? '',
        'topicName': topicName ?? '',
        'status': 'running',
        'mode': mode,
        'startedAt': FieldValue.serverTimestamp(),
        'targetSeconds': targetDurationSeconds,
        'targetDurationSeconds': targetDurationSeconds,
        'elapsedSeconds': 0,
        'elapsedBeforePauseSeconds': 0,
        'isFinalized': false,
        'pausedAt': null,
        'endedAt': null,
        'lastHeartbeat': FieldValue.serverTimestamp(),
      });
      debugPrint('Active session STARTED in Firestore for user $uid (sessionId: $sId, leader: $clientId, mode: $mode)');
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
        'elapsedSeconds': currentElapsedSeconds,
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

  /// Resets active session document to status 'idle' and marks finalized
  Future<void> resetActiveSession(String uid) async {
    final docRef = _activeSessionDoc(uid);
    if (docRef == null) return;

    try {
      await docRef.set({
        'sessionId': null,
        'leadClientId': null,
        'status': 'idle',
        'mode': 'focus',
        'courseId': null,
        'courseCode': null,
        'courseTitle': null,
        'topicId': null,
        'topicName': null,
        'targetSeconds': 0,
        'targetDurationSeconds': 0,
        'elapsedSeconds': 0,
        'elapsedBeforePauseSeconds': 0,
        'isFinalized': true,
        'startedAt': null,
        'pausedAt': null,
        'endedAt': null,
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
  /// 1. Single Persistence Leader via Atomic Firestore Transaction on `users/{uid}/active_session/current`:
  ///    Ensures that when both Android and Web attempt to stop/complete at the same time,
  ///    only ONE client wins the transaction and executes the write.
  /// 2. Deterministic Idempotent Document Key: uses `.doc(finalSessionId).set(..., SetOptions(merge: true))`
  ///    guaranteeing exactly ONE document in Firestore across all devices.
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

      final docRef = _activeSessionDoc(uid);
      if (docRef == null) return false;

      bool transactionCommitted = false;
      int committedDurationSeconds = finalElapsedSeconds;
      String committedSessionId = sessionId ?? '';

      try {
        await db.runTransaction((transaction) async {
          final snapshot = await transaction.get(docRef);

          if (!snapshot.exists || snapshot.data() == null) {
            // No active session doc in Firestore; skip transaction and allow fallback write
            return;
          }

          final data = snapshot.data()!;
          if (data['isFinalized'] == true || data['status'] == 'idle') {
            debugPrint('Transaction: Session already finalized by another leader client, skipping duplicate write');
            return; // Already processed by the other device
          }

          // Mark finalized immediately within the transaction
          transaction.update(docRef, {
            'isFinalized': true,
            'status': 'idle',
            'endedAt': FieldValue.serverTimestamp(),
            'lastHeartbeat': FieldValue.serverTimestamp(),
          });

          final String finalSessionId = (data['sessionId'] as String?)?.isNotEmpty == true
              ? (data['sessionId'] as String)
              : ((sessionId != null && sessionId.isNotEmpty)
                  ? sessionId
                  : ClientIdentity.newSessionId());
          committedSessionId = finalSessionId;

          // Calculate final duration:
          int finalCalculatedSeconds = finalElapsedSeconds;
          DateTime resolvedStartTime = sessionStartTime;
          final startedAtRaw = data['startedAt'];
          if (startedAtRaw is Timestamp) {
            resolvedStartTime = startedAtRaw.toDate();
            final diff = DateTime.now().difference(resolvedStartTime).inSeconds;
            if (diff > 0 && finalCalculatedSeconds <= 0) {
              finalCalculatedSeconds = diff;
            }
          }
          if (finalCalculatedSeconds < 60) {
            finalCalculatedSeconds = finalElapsedSeconds >= 60 ? finalElapsedSeconds : 60;
          }
          committedDurationSeconds = finalCalculatedSeconds;

          final resolvedCourseCode = (data['courseCode'] as String?) ?? courseCode ?? 'General Study';
          final resolvedCourseTitle = (data['courseTitle'] as String?) ?? courseTitle ?? resolvedCourseCode;

          final cleanTitle = formatCleanSessionTitle(
            courseCode: resolvedCourseCode,
            courseTitle: resolvedCourseTitle,
          );

          final mins = (finalCalculatedSeconds / 60).round().clamp(1, 100000);

          final sessionRef = db
              .collection('users')
              .doc(uid)
              .collection('study_sessions')
              .doc(finalSessionId);

          // Write the one single completed study_session using the deterministic ID
          transaction.set(sessionRef, {
            'sessionId': finalSessionId,
            'id': finalSessionId,
            'courseId': data['courseId'] ?? courseId ?? '',
            'courseCode': resolvedCourseCode,
            'courseTitle': resolvedCourseTitle,
            'cleanTitle': cleanTitle,
            'topicId': data['topicId'] ?? topicId ?? '',
            'topicName': data['topicName'] ?? topicName ?? '',
            'durationSeconds': finalCalculatedSeconds,
            'durationMinutes': mins,
            'mode': data['mode'] ?? mode,
            'startedAt': data['startedAt'] ?? Timestamp.fromDate(resolvedStartTime),
            'endedAt': FieldValue.serverTimestamp(),
            'completedAt': DateTime.now().toIso8601String(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'completed': true,
          }, SetOptions(merge: true));

          // Also idempotently write to focus_sessions for analytics stream
          final focusRef = db
              .collection('users')
              .doc(uid)
              .collection('focus_sessions')
              .doc(finalSessionId);

          transaction.set(focusRef, {
            'sessionId': finalSessionId,
            'id': finalSessionId,
            'subject': resolvedCourseCode,
            'subjectName': resolvedCourseCode,
            'courseId': data['courseId'] ?? courseId ?? '',
            'courseCode': resolvedCourseCode,
            'courseTitle': resolvedCourseTitle,
            'cleanTitle': cleanTitle,
            'topicId': data['topicId'] ?? topicId ?? '',
            'topicName': data['topicName'] ?? topicName ?? '',
            'durationSeconds': finalCalculatedSeconds,
            'durationMinutes': mins,
            'startTime': data['startedAt'] ?? Timestamp.fromDate(resolvedStartTime),
            'endTime': FieldValue.serverTimestamp(),
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          transactionCommitted = true;
        });
      } catch (txErr) {
        debugPrint('Transaction execution warning: $txErr');
      }

      if (!transactionCommitted) {
        // Check if doc exists and was already finalized by other device
        try {
          final snap = await docRef.get();
          if (snap.exists && snap.data()?['isFinalized'] == true) {
            debugPrint('TimerService: Confirmed session was finalized by other device, skipping local duplicate write.');
            return true;
          }
        } catch (_) {}

        // Fallback for offline / direct completion without active session doc:
        final fallbackSessionId = (sessionId != null && sessionId.isNotEmpty)
            ? sessionId
            : ClientIdentity.newSessionId();
        committedSessionId = fallbackSessionId;
        final cleanTitle = formatCleanSessionTitle(
          courseCode: courseCode,
          courseTitle: courseTitle,
        );
        final mins = (finalElapsedSeconds / 60).round().clamp(1, 100000);
        final now = sessionEndTime ?? DateTime.now();

        await db
            .collection('users')
            .doc(uid)
            .collection('study_sessions')
            .doc(fallbackSessionId)
            .set({
          'sessionId': fallbackSessionId,
          'id': fallbackSessionId,
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
          'completedAt': DateTime.now().toIso8601String(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'completed': true,
        }, SetOptions(merge: true));

        await db
            .collection('users')
            .doc(uid)
            .collection('focus_sessions')
            .doc(fallbackSessionId)
            .set({
          'sessionId': fallbackSessionId,
          'id': fallbackSessionId,
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

        await resetActiveSession(uid);
      }

      // Update User Aggregate Stats in users/{uid}
      final userRef = db.collection('users').doc(uid);
      try {
        final now = sessionEndTime ?? DateTime.now();
        final mins = (committedDurationSeconds / 60).round().clamp(1, 100000);
        final userSnap = await userRef.get();
        final userData = userSnap.data() ?? {};

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
          'totalFocusSeconds': FieldValue.increment(committedDurationSeconds),
          'totalFocusMinutes': FieldValue.increment(mins),
          'todaysFocusMinutes': FieldValue.increment(mins),
          'lastStudyDate': Timestamp.fromDate(today),
          'lastStudiedAt': Timestamp.fromDate(now),
          'streakDays': currentStreak,
        }, SetOptions(merge: true));
        debugPrint('Updated user aggregate stats: +$committedDurationSeconds s, streak: $currentStreak');
      } catch (e) {
        debugPrint('Error updating user aggregate stats: $e');
      }

      debugPrint('Successfully persisted study session ($committedSessionId) via leader transaction for user $uid');
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
