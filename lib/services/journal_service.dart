import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/journal_entry_model.dart';

/// Service managing study session journal entries stored in `users/{uid}/journal/`
class JournalService {
  final FirebaseFirestore _firestore;

  JournalService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _userJournalRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('journal');
  }

  /// Saves a study session journal entry to `users/{uid}/journal/`
  /// and synchronizes it to `users/{uid}/notes` for full cross-view visibility.
  Future<String> saveStudySessionJournal({
    required String uid,
    String? entryId,
    required String subjectOrCourse,
    required String subjectOrCourseId,
    required int durationMinutes,
    required String topicsCovered,
    String? reflections,
    required String mode,
  }) async {
    if (uid.isEmpty) return '';

    final docRef = (entryId != null && entryId.isNotEmpty)
        ? _userJournalRef(uid).doc(entryId)
        : _userJournalRef(uid).doc();
    final title = 'Study Log: $subjectOrCourse';

    // Combine topics and reflections into content
    final contentBuffer = StringBuffer();
    if (topicsCovered.trim().isNotEmpty) {
      contentBuffer.writeln('Topics: ${topicsCovered.trim()}');
    }
    if (reflections != null && reflections.trim().isNotEmpty) {
      if (contentBuffer.isNotEmpty) contentBuffer.writeln();
      contentBuffer.writeln('Notes: ${reflections.trim()}');
    }
    final content = contentBuffer.toString().trim();

    final now = DateTime.now();
    final entry = StudyJournalEntry(
      id: docRef.id,
      type: 'study_session',
      title: title,
      content: content.isNotEmpty ? content : 'Study session completed.',
      topicsCovered: topicsCovered.trim().isNotEmpty ? topicsCovered.trim() : null,
      reflections: reflections?.trim().isNotEmpty == true ? reflections!.trim() : null,
      durationMinutes: durationMinutes,
      subjectOrCourseId: subjectOrCourseId,
      timestamp: now,
      mode: mode,
    );

    await docRef.set(entry.toMap(), SetOptions(merge: true));

    // Also sync to notes collection with 'Study Session' tag so it appears wherever notes are queried
    try {
      final noteRef = _firestore.collection('users').doc(uid).collection('notes').doc(docRef.id);
      await noteRef.set({
        'id': docRef.id,
        'title': title,
        'content': content.isNotEmpty ? content : 'Study session completed.',
        'createdAt': Timestamp.fromDate(now),
        'updatedAt': Timestamp.fromDate(now),
        'isPinned': false,
        'tags': ['Study Session', if (mode == 'university') 'University' else 'Admission'],
        'type': 'study_session',
        'durationMinutes': durationMinutes,
        'subjectOrCourseId': subjectOrCourseId,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing journal note: $e');
    }

    return docRef.id;
  }

  /// Real-time stream of journal entries from `users/{uid}/journal`
  Stream<List<StudyJournalEntry>> getJournalStream(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    return _userJournalRef(uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => StudyJournalEntry.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Delete a journal entry
  Future<void> deleteJournalEntry(String uid, String entryId) async {
    if (uid.isEmpty || entryId.isEmpty) return;
    try {
      await _userJournalRef(uid).doc(entryId).delete();
      await _firestore.collection('users').doc(uid).collection('notes').doc(entryId).delete();
    } catch (e) {
      debugPrint('Error deleting journal entry: $e');
    }
  }
}
