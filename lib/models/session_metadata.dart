/// Immutable snapshot of session context ensuring strict course context isolation
class SessionMetadata {
  final String? sessionId;
  final String courseId;
  final String courseCode;
  final String courseTitle;
  final int totalDurationSeconds;
  final DateTime sessionStartTime;
  final DateTime sessionEndTime;

  const SessionMetadata({
    this.sessionId,
    required this.courseId,
    required this.courseCode,
    required this.courseTitle,
    required this.totalDurationSeconds,
    required this.sessionStartTime,
    required this.sessionEndTime,
  });

  int get durationMinutes {
    int mins = (totalDurationSeconds / 60).round();
    if (mins == 0 && totalDurationSeconds >= 15) return 1;
    return mins > 0 ? mins : 1;
  }

  Map<String, dynamic> toMap() {
    return {
      if (sessionId != null) 'sessionId': sessionId,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'totalDurationSeconds': totalDurationSeconds,
      'sessionStartTime': sessionStartTime.toIso8601String(),
      'sessionEndTime': sessionEndTime.toIso8601String(),
    };
  }

  factory SessionMetadata.fromMap(Map<String, dynamic> map) {
    return SessionMetadata(
      sessionId: map['sessionId'] as String?,
      courseId: map['courseId'] as String? ?? '',
      courseCode: map['courseCode'] as String? ?? '',
      courseTitle: map['courseTitle'] as String? ?? '',
      totalDurationSeconds: (map['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      sessionStartTime: map['sessionStartTime'] != null
          ? DateTime.tryParse(map['sessionStartTime'] as String) ?? DateTime.now()
          : DateTime.now(),
      sessionEndTime: map['sessionEndTime'] != null
          ? DateTime.tryParse(map['sessionEndTime'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  factory SessionMetadata.fromSubject(
    String subject, {
    String? sessionId,
    required int totalDurationSeconds,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
    String? courseId,
  }) {
    final clean = subject.trim();
    String code = clean;
    String title = clean;

    if (clean.contains(' - ')) {
      final parts = clean.split(' - ');
      code = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    } else if (clean.contains(': ')) {
      final parts = clean.split(': ');
      code = parts[0].trim();
      title = parts.sublist(1).join(': ').trim();
    }

    final resolvedId = courseId ??
        code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_').replaceAll(RegExp(r'_+'), '_');

    final end = sessionEndTime ?? DateTime.now();
    final start = sessionStartTime ?? end.subtract(Duration(seconds: totalDurationSeconds));

    return SessionMetadata(
      sessionId: sessionId,
      courseId: resolvedId.isNotEmpty ? resolvedId : 'general_study',
      courseCode: code,
      courseTitle: title.isNotEmpty ? title : code,
      totalDurationSeconds: totalDurationSeconds,
      sessionStartTime: start,
      sessionEndTime: end,
    );
  }
}

