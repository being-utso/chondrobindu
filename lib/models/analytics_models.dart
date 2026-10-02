import '../services/timer_service.dart';

/// Data model for a single completed focus study session
class StudySessionLog {
  final String id;
  final DateTime date;
  final int durationInMinutes;
  final int durationInSeconds;
  final String subjectId;
  final String subjectName;
  final String? courseCode;
  final String? courseTitle;
  final DateTime? startTime;
  final DateTime? endTime;

  const StudySessionLog({
    required this.id,
    required this.date,
    required this.durationInMinutes,
    this.durationInSeconds = 0,
    required this.subjectId,
    this.subjectName = 'General Study',
    this.courseCode,
    this.courseTitle,
    this.startTime,
    this.endTime,
  });

  @override
  String toString() => '$cleanTitle ($durationInMinutes mins)';

  int get durationMinutes => durationInMinutes;
  String get subject => subjectName;

  String get cleanTitle => formatCleanSessionTitle(
        courseCode: courseCode,
        courseTitle: courseTitle,
        fallback: subjectName,
      );

  StudySessionLog copyWith({
    String? id,
    DateTime? date,
    int? durationInMinutes,
    int? durationInSeconds,
    String? subjectId,
    String? subjectName,
    String? courseCode,
    String? courseTitle,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return StudySessionLog(
      id: id ?? this.id,
      date: date ?? this.date,
      durationInMinutes: durationInMinutes ?? this.durationInMinutes,
      durationInSeconds: durationInSeconds ?? this.durationInSeconds,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      courseCode: courseCode ?? this.courseCode,
      courseTitle: courseTitle ?? this.courseTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

/// Alias for backward and architectural compatibility
typedef FocusSession = StudySessionLog;
