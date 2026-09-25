import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for an individual entry (mistake or tip/trick) logged in an exam journal.
class JournalEntry {
  final String type; // "mistake" or "tip"
  final String content;

  const JournalEntry({
    required this.type,
    required this.content,
  });

  bool get isMistake => type.toLowerCase() == 'mistake';
  bool get isTip => type.toLowerCase() == 'tip';

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'content': content,
    };
  }

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    return JournalEntry(
      type: map['type'] as String? ?? 'tip',
      content: map['content'] as String? ?? '',
    );
  }
}

/// Data model representing a student's admission prep exam entry.
class ExamModel {
  final String id;
  final String examName;
  final String subject;
  final DateTime date;
  final double totalMarks;
  final double marksObtained;
  final int meritPosition;
  final bool isCompleted;
  final bool isAbsent;
  final List<JournalEntry> journalEntries;

  const ExamModel({
    required this.id,
    required this.examName,
    required this.subject,
    required this.date,
    required this.totalMarks,
    this.marksObtained = 0.0,
    this.meritPosition = 0,
    this.isCompleted = false,
    this.isAbsent = false,
    this.journalEntries = const [],
  });

  /// Percentage score (0.0 to 100.0)
  double get scorePercentage =>
      totalMarks > 0 ? ((marksObtained / totalMarks) * 100).clamp(0.0, 100.0) : 0.0;

  /// Whether score has been logged
  bool get hasLoggedScore => (isCompleted && !isAbsent) || marksObtained > 0;

  /// Whether exam contains journal entries
  bool get hasJournalEntries => journalEntries.any((e) => e.content.trim().isNotEmpty);

  @override
  String toString() => examName;

  ExamModel copyWith({
    String? id,
    String? examName,
    String? subject,
    DateTime? date,
    double? totalMarks,
    double? marksObtained,
    int? meritPosition,
    bool? isCompleted,
    bool? isAbsent,
    List<JournalEntry>? journalEntries,
  }) {
    return ExamModel(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      subject: subject ?? this.subject,
      date: date ?? this.date,
      totalMarks: totalMarks ?? this.totalMarks,
      marksObtained: marksObtained ?? this.marksObtained,
      meritPosition: meritPosition ?? this.meritPosition,
      isCompleted: isCompleted ?? this.isCompleted,
      isAbsent: isAbsent ?? this.isAbsent,
      journalEntries: journalEntries ?? this.journalEntries,
    );
  }

  /// Convert to Firestore Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'examName': examName,
      'subject': subject,
      'date': Timestamp.fromDate(date),
      'totalMarks': totalMarks,
      'marksObtained': marksObtained,
      'meritPosition': meritPosition,
      'isCompleted': isCompleted,
      'isAbsent': isAbsent,
      'journal_entries': journalEntries.map((e) => e.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Create from Firestore Map
  factory ExamModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parsedDate = DateTime.now();
    if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        parsedDate = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        parsedDate = DateTime.tryParse(map['date'] as String) ?? DateTime.now();
      }
    }

    List<JournalEntry> parsedJournalEntries = [];
    if (map['journal_entries'] != null && map['journal_entries'] is List) {
      parsedJournalEntries = (map['journal_entries'] as List)
          .map((item) => JournalEntry.fromMap(Map<String, dynamic>.from(item as Map)))
          .where((e) => e.content.trim().isNotEmpty)
          .toList();
    }

    return ExamModel(
      id: docId,
      examName: map['examName'] as String? ?? 'Untitled Exam',
      subject: map['subject'] as String? ?? 'General',
      date: parsedDate,
      totalMarks: (map['totalMarks'] as num?)?.toDouble() ?? 100.0,
      marksObtained: (map['marksObtained'] as num?)?.toDouble() ?? 0.0,
      meritPosition: (map['meritPosition'] as num?)?.toInt() ?? 0,
      isCompleted: map['isCompleted'] as bool? ?? false,
      isAbsent: map['isAbsent'] as bool? ?? false,
      journalEntries: parsedJournalEntries,
    );
  }
}
