import 'package:cloud_firestore/cloud_firestore.dart';

/// Atomic Syllabus Topic Model inside `/users/{uid}/courses/{courseId}/topics/{topicId}`
class SyllabusTopic {
  final String id;
  final String chapterTitle;  // e.g. "Chapter 3: Continuous-Time Signals"
  final int chapterOrder;
  final String topicIndex;    // e.g. "3.3"
  final String title;         // e.g. "Time Shifting and Scaling"
  final bool isCompleted;
  final bool isInProgress;
  final DateTime? completedAt;

  const SyllabusTopic({
    required this.id,
    required this.chapterTitle,
    this.chapterOrder = 1,
    required this.topicIndex,
    required this.title,
    this.isCompleted = false,
    this.isInProgress = false,
    this.completedAt,
  });

  String get chapter => chapterTitle;
  String get topicCode => topicIndex;

  factory SyllabusTopic.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return SyllabusTopic.fromMap(data, doc.id);
  }

  factory SyllabusTopic.fromMap(Map<String, dynamic> map, [String? docId]) {
    final id = docId ?? map['id'] as String? ?? '';
    final chapterTitle = map['chapterTitle'] as String? ?? 'General';
    final chapterOrder = (map['chapterOrder'] as num?)?.toInt() ?? 1;
    final topicIndex = map['topicIndex'] as String? ?? '';
    final title = map['title'] as String? ?? '';
    final isCompleted = map['isCompleted'] as bool? ?? false;
    final isInProgress = map['isInProgress'] as bool? ?? false;

    DateTime? completedTime;
    if (map['completedAt'] != null) {
      if (map['completedAt'] is Timestamp) {
        completedTime = (map['completedAt'] as Timestamp).toDate();
      } else if (map['completedAt'] is String) {
        completedTime = DateTime.tryParse(map['completedAt'] as String);
      }
    }

    return SyllabusTopic(
      id: id,
      chapterTitle: chapterTitle,
      chapterOrder: chapterOrder,
      topicIndex: topicIndex,
      title: title,
      isCompleted: isCompleted,
      isInProgress: isInProgress,
      completedAt: completedTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chapterTitle': chapterTitle,
      'chapterOrder': chapterOrder,
      'topicIndex': topicIndex,
      'title': title,
      'isCompleted': isCompleted,
      'isInProgress': isInProgress,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
    };
  }

  SyllabusTopic copyWith({
    String? id,
    String? chapterTitle,
    int? chapterOrder,
    String? topicIndex,
    String? title,
    bool? isCompleted,
    bool? isInProgress,
    DateTime? completedAt,
  }) {
    return SyllabusTopic(
      id: id ?? this.id,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      chapterOrder: chapterOrder ?? this.chapterOrder,
      topicIndex: topicIndex ?? this.topicIndex,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      isInProgress: isInProgress ?? this.isInProgress,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
