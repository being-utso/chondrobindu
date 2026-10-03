import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/study_session_model.dart';
import '../services/timer_service.dart';

class StudySessionRepository {
  final FirebaseFirestore? _firestore;

  StudySessionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  CollectionReference<Map<String, dynamic>>? _sessionsRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('focus_sessions');

  DocumentReference<Map<String, dynamic>>? _userRef(String uid) =>
      _firestore?.collection('users').doc(uid);

  Stream<List<StudySession>> watchSessionsForDate(String uid, DateTime date) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    return _sessionsRef(uid)!.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => StudySession.fromFirestore(doc))
          .where((s) => !s.startedAt.isBefore(startOfDay) && s.startedAt.isBefore(endOfDay))
          .toList();
      return deduplicateSessions(list);
    });
  }

  Stream<List<StudySession>> watchSessionsRange(String uid, DateTime start, DateTime end) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _sessionsRef(uid)!.snapshots().map((snapshot) {
      final list = snapshot.docs
          .map((doc) => StudySession.fromFirestore(doc))
          .where((s) => !s.startedAt.isBefore(start) && !s.startedAt.isAfter(end))
          .toList();
      return deduplicateSessions(list);
    });
  }

  Stream<List<StudySession>> watchRecentSessions(String uid, {int limit = 50}) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _sessionsRef(uid)!.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => StudySession.fromFirestore(doc)).toList();
      final deduplicated = deduplicateSessions(list);
      return deduplicated.take(limit).toList();
    });
  }

  Future<void> logCompletedSession(String uid, StudySession session) async {
    if (_firestore == null || uid.isEmpty) return;

    final sessionDoc = _sessionsRef(uid)!.doc(session.id);
    await sessionDoc.set(session.toMap(), SetOptions(merge: true));

    // Also update topics if attached
    if (session.courseId.isNotEmpty && session.topicIds.isNotEmpty) {
      final topicsRef = _firestore!
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(session.courseId)
          .collection('topics');

      for (final tId in session.topicIds) {
        try {
          await topicsRef.doc(tId).update({
            'isCompleted': true,
            'completedAt': Timestamp.fromDate(session.endedAt),
          });
        } catch (_) {}
      }

      // Update parent course completed topics count
      try {
        final allTopicsSnap = await topicsRef.get();
        final completed = allTopicsSnap.docs.where((d) => d.data()['isCompleted'] == true).length;
        await _firestore!
            .collection('users')
            .doc(uid)
            .collection('courses')
            .doc(session.courseId)
            .update({
          'completedTopicsCount': completed,
          'totalTopicsCount': allTopicsSnap.docs.length,
        });
      } catch (_) {}
    }

    // Update User Profile metrics & calculate streak
    try {
      final userDocSnap = await _userRef(uid)!.get();
      final userData = userDocSnap.data() ?? {};

      final lastStudiedRaw = userData['lastStudiedAt'];
      DateTime? lastStudied;
      if (lastStudiedRaw is Timestamp) {
        lastStudied = lastStudiedRaw.toDate();
      }

      final now = session.startedAt;
      int currentStreak = (userData['streakDays'] as num?)?.toInt() ?? 0;

      if (lastStudied == null) {
        currentStreak = 1;
      } else {
        final lastDay = DateTime(lastStudied.year, lastStudied.month, lastStudied.day);
        final today = DateTime(now.year, now.month, now.day);
        final differenceInDays = today.difference(lastDay).inDays;

        if (differenceInDays == 1) {
          currentStreak += 1;
        } else if (differenceInDays > 1) {
          currentStreak = 1;
        }
      }

      final sessionMinutes = (session.durationSeconds / 60).round();

      await _userRef(uid)!.set({
        'streakDays': currentStreak,
        'lastStudiedAt': Timestamp.fromDate(now),
        'totalFocusMinutes': FieldValue.increment(sessionMinutes),
        'todaysFocusMinutes': FieldValue.increment(sessionMinutes),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
