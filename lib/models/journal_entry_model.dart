import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for study session journal entries stored under `users/{uid}/journal/`
class StudyJournalEntry {
  final String id;
  final String type; // 'study_session'
  final String title;
  final String content;
  final String? topicsCovered;
  final String? reflections;
  final int durationMinutes;
  final String subjectOrCourseId;
  final DateTime timestamp;
  final String mode; // 'university' or 'admission'

  const StudyJournalEntry({
    required this.id,
    this.type = 'study_session',
    required this.title,
    required this.content,
    this.topicsCovered,
    this.reflections,
    required this.durationMinutes,
    required this.subjectOrCourseId,
    required this.timestamp,
    this.mode = 'admission',
  });

  bool get isStudySession => type.toLowerCase() == 'study_session';

  StudyJournalEntry copyWith({
    String? id,
    String? type,
    String? title,
    String? content,
    String? topicsCovered,
    String? reflections,
    int? durationMinutes,
    String? subjectOrCourseId,
    DateTime? timestamp,
    String? mode,
  }) {
    return StudyJournalEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      topicsCovered: topicsCovered ?? this.topicsCovered,
      reflections: reflections ?? this.reflections,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      subjectOrCourseId: subjectOrCourseId ?? this.subjectOrCourseId,
      timestamp: timestamp ?? this.timestamp,
      mode: mode ?? this.mode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'content': content,
      if (topicsCovered != null && topicsCovered!.isNotEmpty)
        'topicsCovered': topicsCovered,
      if (reflections != null && reflections!.isNotEmpty)
        'reflections': reflections,
      'durationMinutes': durationMinutes,
      'subjectOrCourseId': subjectOrCourseId,
      'timestamp': Timestamp.fromDate(timestamp),
      'mode': mode,
      'createdAt': Timestamp.fromDate(timestamp),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory StudyJournalEntry.fromMap(Map<String, dynamic> map, [String? docId]) {
    DateTime parseDate(dynamic dateVal) {
      if (dateVal is Timestamp) return dateVal.toDate();
      if (dateVal is String) return DateTime.tryParse(dateVal) ?? DateTime.now();
      if (dateVal is int) return DateTime.fromMillisecondsSinceEpoch(dateVal);
      return DateTime.now();
    }

    return StudyJournalEntry(
      id: docId ?? (map['id'] as String? ?? ''),
      type: map['type'] as String? ?? 'study_session',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      topicsCovered: map['topicsCovered'] as String?,
      reflections: map['reflections'] as String?,
      durationMinutes: (map['durationMinutes'] as num?)?.toInt() ?? 0,
      subjectOrCourseId: map['subjectOrCourseId'] as String? ?? '',
      timestamp: parseDate(map['timestamp'] ?? map['createdAt']),
      mode: map['mode'] as String? ?? 'admission',
    );
  }
}
