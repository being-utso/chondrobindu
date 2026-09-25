class ExamRecord {
  final String id;
  final String examName;
  final String subject;
  final double marks;
  final double totalMarks;
  final int meritPosition;
  final DateTime date;
  final bool isAbsent;

  const ExamRecord({
    required this.id,
    required this.examName,
    required this.subject,
    required this.marks,
    this.totalMarks = 100.0,
    required this.meritPosition,
    required this.date,
    this.isAbsent = false,
  });

  double get percentage => totalMarks > 0 ? (marks / totalMarks) * 100 : 0;

  @override
  String toString() => isAbsent ? '$examName ($subject) - Absent' : '$examName ($subject): ${marks.toStringAsFixed(1)}/$totalMarks';

  ExamRecord copyWith({
    String? id,
    String? examName,
    String? subject,
    double? marks,
    double? totalMarks,
    int? meritPosition,
    DateTime? date,
    bool? isAbsent,
  }) {
    return ExamRecord(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      subject: subject ?? this.subject,
      marks: marks ?? this.marks,
      totalMarks: totalMarks ?? this.totalMarks,
      meritPosition: meritPosition ?? this.meritPosition,
      date: date ?? this.date,
      isAbsent: isAbsent ?? this.isAbsent,
    );
  }
}

class UpcomingExam {
  final String id;
  final String examName;
  final String subject;
  final double totalMarks;
  final DateTime targetDate;
  final String recurringType; // 'None', 'Weekly', 'Monthly'
  final String? recurringGroupId;
  final int? occurrenceIndex;
  final int? totalOccurrences;
  final bool isAbsent;
  final bool isCompleted;

  const UpcomingExam({
    required this.id,
    required this.examName,
    this.subject = 'General',
    this.totalMarks = 100.0,
    required this.targetDate,
    this.recurringType = 'None',
    this.recurringGroupId,
    this.occurrenceIndex,
    this.totalOccurrences,
    this.isAbsent = false,
    this.isCompleted = false,
  });

  bool get isRecurring => recurringType != 'None' && recurringGroupId != null;

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final diff = target.difference(today).inDays;
    return diff < 0 ? 0 : diff;
  }

  @override
  String toString() => examName;

  UpcomingExam copyWith({
    String? id,
    String? examName,
    String? subject,
    double? totalMarks,
    DateTime? targetDate,
    String? recurringType,
    String? recurringGroupId,
    int? occurrenceIndex,
    int? totalOccurrences,
    bool? isAbsent,
    bool? isCompleted,
  }) {
    return UpcomingExam(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      subject: subject ?? this.subject,
      totalMarks: totalMarks ?? this.totalMarks,
      targetDate: targetDate ?? this.targetDate,
      recurringType: recurringType ?? this.recurringType,
      recurringGroupId: recurringGroupId ?? this.recurringGroupId,
      occurrenceIndex: occurrenceIndex ?? this.occurrenceIndex,
      totalOccurrences: totalOccurrences ?? this.totalOccurrences,
      isAbsent: isAbsent ?? this.isAbsent,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}
