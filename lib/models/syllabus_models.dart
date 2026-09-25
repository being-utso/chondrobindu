enum ChapterStatus {
  notStarted,
  inProgress,
  completed,
}

class StudySection {
  final String id;
  final String title;
  final bool isCompleted;
  final DateTime? lastModified;

  const StudySection({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.lastModified,
  });

  @override
  String toString() => title;

  StudySection copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    DateTime? lastModified,
  }) {
    return StudySection(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
    };
  }

  factory StudySection.fromMap(Map<String, dynamic> map) {
    DateTime? parsedTime;
    if (map['lastModified'] != null) {
      if (map['lastModified'] is String) {
        parsedTime = DateTime.tryParse(map['lastModified'] as String);
      }
    }
    return StudySection(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      isCompleted: map['isCompleted'] ?? false,
      lastModified: parsedTime,
    );
  }
}

class Chapter {
  final String id;
  final String title;
  final List<StudySection> sections;
  final DateTime? lastModified;

  const Chapter({
    required this.id,
    required this.title,
    required this.sections,
    this.lastModified,
  });

  @override
  String toString() => title;

  /// Automatically calculates status based on completed sections
  ChapterStatus get status {
    if (sections.isEmpty) return ChapterStatus.notStarted;
    final completedCount = sections.where((s) => s.isCompleted).length;
    if (completedCount == 0) {
      return ChapterStatus.notStarted;
    } else if (completedCount == sections.length) {
      return ChapterStatus.completed;
    } else {
      return ChapterStatus.inProgress;
    }
  }

  /// Percentage of sections completed (0.0 to 1.0)
  double get progress {
    if (sections.isEmpty) return 0.0;
    final completedCount = sections.where((s) => s.isCompleted).length;
    return completedCount / sections.length;
  }

  Chapter copyWith({
    String? id,
    String? title,
    List<StudySection>? sections,
    DateTime? lastModified,
  }) {
    return Chapter(
      id: id ?? this.id,
      title: title ?? this.title,
      sections: sections ?? this.sections,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      'sections': sections.map((s) => s.toMap()).toList(),
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    DateTime? parsedTime;
    if (map['lastModified'] != null && map['lastModified'] is String) {
      parsedTime = DateTime.tryParse(map['lastModified'] as String);
    }
    return Chapter(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      lastModified: parsedTime,
      sections: (map['sections'] as List<dynamic>?)
              ?.map((s) => StudySection.fromMap(Map<String, dynamic>.from(s)))
              .toList() ??
          [],
    );
  }
}

class Subject {
  final String id;
  final String title;
  final List<Chapter> chapters;
  final bool isExpanded;
  final String iconName;
  final DateTime? lastModified;

  const Subject({
    required this.id,
    required this.title,
    required this.chapters,
    this.isExpanded = false,
    this.iconName = 'book',
    this.lastModified,
  });

  @override
  String toString() => title;

  /// Alias for title ensuring compatibility with subjectName references
  String get subjectName => title;

  /// Total progress across all chapters in this subject
  double get totalProgress {
    if (chapters.isEmpty) return 0.0;
    final totalSections = chapters.fold<int>(0, (sum, c) => sum + c.sections.length);
    if (totalSections == 0) return 0.0;
    final completedSections = chapters.fold<int>(
      0,
      (sum, c) => sum + c.sections.where((s) => s.isCompleted).length,
    );
    return completedSections / totalSections;
  }

  Subject copyWith({
    String? id,
    String? title,
    List<Chapter>? chapters,
    bool? isExpanded,
    String? iconName,
    DateTime? lastModified,
  }) {
    return Subject(
      id: id ?? this.id,
      title: title ?? this.title,
      chapters: chapters ?? this.chapters,
      isExpanded: isExpanded ?? this.isExpanded,
      iconName: iconName ?? this.iconName,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'iconName': iconName,
      'isExpanded': isExpanded,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      'chapters': chapters.map((c) => c.toMap()).toList(),
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map) {
    DateTime? parsedTime;
    if (map['lastModified'] != null && map['lastModified'] is String) {
      parsedTime = DateTime.tryParse(map['lastModified'] as String);
    }
    return Subject(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      iconName: map['iconName'] ?? 'book',
      isExpanded: map['isExpanded'] ?? false,
      lastModified: parsedTime,
      chapters: (map['chapters'] as List<dynamic>?)
              ?.map((c) => Chapter.fromMap(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
    );
  }
}
