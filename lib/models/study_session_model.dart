import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/timer_service.dart';

/// Completed Study Session Model inside `/users/{uid}/study_sessions/{sessionId}`
class StudySession {
  final String id;
  final String? _sessionId;
  String get sessionId => _sessionId?.isNotEmpty == true ? _sessionId! : id;
  final String courseId;
  final String courseCode;
  final String? courseTitle;
  final List<String> topicIds;
  final List<String> topicTitles;
  final int durationSeconds;
  final int overtimeSeconds;
  final DateTime startedAt;
  final DateTime endedAt;
  final String? focusNotes;
  final int focusRating; // 1 to 5 stars

  const StudySession({
    required this.id,
    String? sessionId,
    required this.courseId,
    required this.courseCode,
    this.courseTitle,
    this.topicIds = const [],
    this.topicTitles = const [],
    required this.durationSeconds,
    this.overtimeSeconds = 0,
    required this.startedAt,
    required this.endedAt,
    this.focusNotes,
    this.focusRating = 5,
  }) : _sessionId = sessionId;

  String get cleanTitle => formatCleanSessionTitle(
        courseCode: courseCode,
        courseTitle: courseTitle,
      );

  int get totalSeconds => durationSeconds + overtimeSeconds;
  double get durationMinutes => durationSeconds / 60.0;
  double get durationHours => durationSeconds / 3600.0;

  factory StudySession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return StudySession.fromMap(data, doc.id);
  }

  factory StudySession.fromMap(Map<String, dynamic> map, [String? docId]) {
    final id = docId ?? map['id'] as String? ?? '';
    final sessionId = map['sessionId'] as String? ?? id;
    final courseId = map['courseId'] as String? ?? map['subjectId'] as String? ?? '';
    final courseCode = map['courseCode'] as String? ?? map['subjectName'] as String? ?? '';

    final tIds = (map['topicIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];
    final tTitles = (map['topicTitles'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [];

    final dur = (map['durationSeconds'] as num?)?.toInt() ??
        (((map['durationInMinutes'] as num?)?.toInt() ?? 0) * 60);
    final over = (map['overtimeSeconds'] as num?)?.toInt() ?? 0;

    DateTime start = DateTime.now();
    if (map['startedAt'] != null) {
      if (map['startedAt'] is Timestamp) {
        start = (map['startedAt'] as Timestamp).toDate();
      } else if (map['startedAt'] is String) {
        start = DateTime.tryParse(map['startedAt'] as String) ?? start;
      }
    } else if (map['startTime'] != null) {
      if (map['startTime'] is Timestamp) {
        start = (map['startTime'] as Timestamp).toDate();
      } else if (map['startTime'] is String) {
        start = DateTime.tryParse(map['startTime'] as String) ?? start;
      }
    } else if (map['timestamp'] != null) {
      if (map['timestamp'] is Timestamp) {
        start = (map['timestamp'] as Timestamp).toDate();
      } else if (map['timestamp'] is String) {
        start = DateTime.tryParse(map['timestamp'] as String) ?? start;
      }
    } else if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        start = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        start = DateTime.tryParse(map['date'] as String) ?? start;
      }
    }

    DateTime end = start.add(Duration(seconds: dur + over));
    if (map['endedAt'] != null) {
      if (map['endedAt'] is Timestamp) {
        end = (map['endedAt'] as Timestamp).toDate();
      } else if (map['endedAt'] is String) {
        end = DateTime.tryParse(map['endedAt'] as String) ?? end;
      }
    } else if (map['endTime'] != null) {
      if (map['endTime'] is Timestamp) {
        end = (map['endTime'] as Timestamp).toDate();
      } else if (map['endTime'] is String) {
        end = DateTime.tryParse(map['endTime'] as String) ?? end;
      }
    }

    final notes = map['focusNotes'] as String? ?? map['notes'] as String?;
    final rating = (map['focusRating'] as num?)?.toInt() ?? 5;

    final courseTitle = map['courseTitle'] as String? ?? map['subjectTitle'] as String? ?? map['title'] as String?;

    return StudySession(
      id: id,
      sessionId: sessionId,
      courseId: courseId,
      courseCode: courseCode,
      courseTitle: courseTitle,
      topicIds: tIds,
      topicTitles: tTitles,
      durationSeconds: dur,
      overtimeSeconds: over,
      startedAt: start,
      endedAt: end,
      focusNotes: notes,
      focusRating: rating,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sessionId': sessionId,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'cleanTitle': cleanTitle,
      'topicIds': topicIds,
      'topicTitles': topicTitles,
      'durationSeconds': durationSeconds,
      'overtimeSeconds': overtimeSeconds,
      'startedAt': Timestamp.fromDate(startedAt),
      'endedAt': Timestamp.fromDate(endedAt),
      'timestamp': Timestamp.fromDate(startedAt),
      'startTime': Timestamp.fromDate(startedAt),
      'endTime': Timestamp.fromDate(endedAt),
      'focusNotes': focusNotes,
      'focusRating': focusRating,
      // Compatibility fields with legacy StudySessionLog
      'subject': courseCode,
      'subjectId': courseId,
      'subjectName': courseCode,
      'durationMinutes': (durationSeconds / 60).round(),
      'durationInMinutes': (durationSeconds / 60).round(),
      'date': Timestamp.fromDate(startedAt),
    };
  }

  StudySession copyWith({
    String? id,
    String? sessionId,
    String? courseId,
    String? courseCode,
    String? courseTitle,
    List<String>? topicIds,
    List<String>? topicTitles,
    int? durationSeconds,
    int? overtimeSeconds,
    DateTime? startedAt,
    DateTime? endedAt,
    String? focusNotes,
    int? focusRating,
  }) {
    return StudySession(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      courseId: courseId ?? this.courseId,
      courseCode: courseCode ?? this.courseCode,
      courseTitle: courseTitle ?? this.courseTitle,
      topicIds: topicIds ?? this.topicIds,
      topicTitles: topicTitles ?? this.topicTitles,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      focusNotes: focusNotes ?? this.focusNotes,
      focusRating: focusRating ?? this.focusRating,
    );
  }
}
