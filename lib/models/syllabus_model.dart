import 'package:cloud_firestore/cloud_firestore.dart';

/// Atomic Subtopic Model (e.g. 1.1.1 Lecture note, 1.1.2 Ref book, 1.1.3 Prev question)
class SyllabusSubtopic {
  final String id;
  final String subtopicIndex; // e.g. "1.1.1"
  final String title;         // e.g. "Lecture note"
  final bool isCompleted;
  final String? resourceUrl;

  const SyllabusSubtopic({
    required this.id,
    required this.subtopicIndex,
    required this.title,
    this.isCompleted = false,
    this.resourceUrl,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subtopicIndex': subtopicIndex,
    'title': title,
    'isCompleted': isCompleted,
    if (resourceUrl != null && resourceUrl!.isNotEmpty) 'resourceUrl': resourceUrl,
  };

  factory SyllabusSubtopic.fromMap(Map<String, dynamic> map, [String? docId]) => SyllabusSubtopic(
    id: docId ?? map['id'] as String? ?? '',
    subtopicIndex: map['subtopicIndex'] as String? ?? map['index'] as String? ?? '',
    title: map['title'] as String? ?? '',
    isCompleted: map['isCompleted'] as bool? ?? false,
    resourceUrl: map['resourceUrl'] as String?,
  );

  SyllabusSubtopic copyWith({
    String? id,
    String? subtopicIndex,
    String? title,
    bool? isCompleted,
    String? resourceUrl,
  }) {
    return SyllabusSubtopic(
      id: id ?? this.id,
      subtopicIndex: subtopicIndex ?? this.subtopicIndex,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      resourceUrl: resourceUrl ?? this.resourceUrl,
    );
  }
}

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
  final String? resourceUrl;
  final List<SyllabusSubtopic> subtopics;

  const SyllabusTopic({
    required this.id,
    required this.chapterTitle,
    this.chapterOrder = 1,
    required this.topicIndex,
    required this.title,
    this.isCompleted = false,
    this.isInProgress = false,
    this.completedAt,
    this.resourceUrl,
    this.subtopics = const [],
  });

  bool get hasSubtopics => subtopics.isNotEmpty;
  int get totalSubtopicsCount => subtopics.length;
  int get completedSubtopicsCount => subtopics.where((s) => s.isCompleted).length;
  double get progressFraction => subtopics.isNotEmpty
      ? (completedSubtopicsCount / totalSubtopicsCount)
      : (isCompleted ? 1.0 : 0.0);

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

    final resourceUrl = map['resourceUrl'] as String?;

    final rawSubtopics = (map['subtopics'] as List<dynamic>?) ?? [];
    final parsedSubtopics = rawSubtopics
        .whereType<Map>()
        .map((m) => SyllabusSubtopic.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    return SyllabusTopic(
      id: id,
      chapterTitle: chapterTitle,
      chapterOrder: chapterOrder,
      topicIndex: topicIndex,
      title: title,
      isCompleted: isCompleted,
      isInProgress: isInProgress,
      completedAt: completedTime,
      resourceUrl: resourceUrl,
      subtopics: parsedSubtopics,
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
      if (resourceUrl != null && resourceUrl!.isNotEmpty) 'resourceUrl': resourceUrl,
      if (subtopics.isNotEmpty) 'subtopics': subtopics.map((s) => s.toMap()).toList(),
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
    String? resourceUrl,
    List<SyllabusSubtopic>? subtopics,
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
      resourceUrl: resourceUrl ?? this.resourceUrl,
      subtopics: subtopics ?? this.subtopics,
    );
  }
}
