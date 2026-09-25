import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/syllabus_factory.dart';

/// Riverpod Provider for Syllabus State
final syllabusProvider = StateNotifierProvider<SyllabusNotifier, List<Subject>>((ref) {
  return SyllabusNotifier();
});

class SyllabusNotifier extends StateNotifier<List<Subject>> {
  SyllabusNotifier() : super([]); // Start empty, no legacy mock data

  void toggleSubjectExpansion(String subjectId) {
    state = state.map((subject) {
      if (subject.id == subjectId) {
        return subject.copyWith(isExpanded: !subject.isExpanded);
      }
      return subject;
    }).toList();
  }

  void toggleSectionCompletion(String subjectId, String chapterId, String sectionId) {
    state = state.map((subject) {
      if (subject.id != subjectId) return subject;

      final updatedChapters = subject.chapters.map((chapter) {
        if (chapter.id != chapterId) return chapter;

        final updatedSections = chapter.sections.map((section) {
          if (section.id != sectionId) return section;
          return section.copyWith(isCompleted: !section.isCompleted);
        }).toList();

        return chapter.copyWith(sections: updatedSections);
      }).toList();

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void addChapterToSubject(String subjectId, String chapterTitle, List<String> sectionTitles) {
    if (chapterTitle.trim().isEmpty) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final newChapterId = 'chap_${timestamp}_${(1000 + (timestamp % 9000))}';

    final validSections = sectionTitles
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final newSections = validSections.asMap().entries.map((entry) {
      final idx = entry.key;
      final title = entry.value;
      return StudySection(
        id: 'sec_${timestamp}_${idx}_${(1000 + ((timestamp + idx) % 9000))}',
        title: title,
        isCompleted: false,
      );
    }).toList();

    state = state.map((subject) {
      if (subject.id != subjectId) return subject;

      final updatedChapters = [
        ...subject.chapters,
        Chapter(
          id: newChapterId,
          title: chapterTitle.trim(),
          sections: List<StudySection>.from(newSections),
        ),
      ];

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void editChapter(String subjectId, String chapterId, String newTitle, List<String> sectionTitles) {
    if (newTitle.trim().isEmpty) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final validSections = sectionTitles
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    state = state.map((subject) {
      if (subject.id != subjectId) return subject;

      final updatedChapters = subject.chapters.map((chapter) {
        if (chapter.id != chapterId) return chapter;

        final newSections = validSections.asMap().entries.map((entry) {
          final idx = entry.key;
          final title = entry.value;
          return StudySection(
            id: 'sec_${timestamp}_${idx}_${(1000 + ((timestamp + idx) % 9000))}',
            title: title,
            isCompleted: false,
          );
        }).toList();

        return chapter.copyWith(
          title: newTitle.trim(),
          sections: List<StudySection>.from(newSections),
        );
      }).toList();

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void deleteChapter(String subjectId, String chapterId) {
    state = state.map((subject) {
      if (subject.id != subjectId) return subject;

      final updatedChapters = subject.chapters.where((c) => c.id != chapterId).toList();
      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void addSubject(String title) {
    if (title.trim().isEmpty) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final newSubject = Subject(
      id: 'subj_$timestamp',
      title: title.trim(),
      isExpanded: true,
      chapters: const [],
    );

    state = [...state, newSubject];
  }

  void editSubject(String subjectId, String newTitle) {
    if (newTitle.trim().isEmpty) return;

    state = state.map((subject) {
      if (subject.id != subjectId) return subject;
      return subject.copyWith(title: newTitle.trim());
    }).toList();
  }

  void deleteSubject(String subjectId) {
    state = state.where((s) => s.id != subjectId).toList();
  }

  void addCustomSectionToChapter(String subjectId, String chapterId, String sectionName) {
    if (sectionName.trim().isEmpty) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final newSectionId = 'sec_${timestamp}_${(1000 + (timestamp % 9000))}';

    state = state.map((subject) {
      if (subject.id != subjectId) return subject;

      final updatedChapters = subject.chapters.map((chapter) {
        if (chapter.id != chapterId) return chapter;

        final updatedSections = [
          ...chapter.sections,
          StudySection(
            id: newSectionId,
            title: sectionName.trim(),
            isCompleted: false,
          ),
        ];

        return chapter.copyWith(sections: List<StudySection>.from(updatedSections));
      }).toList();

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void setSubjects(List<Subject> subjects) {
    state = List<Subject>.from(subjects);
  }

  void applyGlobalSection({
    required String sectionName,
    required bool isAdd,
    required Set<String> subjectIds,
  }) {
    final cleanName = sectionName.trim();
    if (cleanName.isEmpty || subjectIds.isEmpty) return;

    final timestamp = DateTime.now().microsecondsSinceEpoch;

    state = state.map((subject) {
      if (!subjectIds.contains(subject.id)) return subject;

      final updatedChapters = subject.chapters.map((chapter) {
        if (isAdd) {
          final alreadyExists = chapter.sections.any(
            (s) => s.title.trim().toLowerCase() == cleanName.toLowerCase(),
          );
          if (alreadyExists) return chapter;

          final newSecId = 'sec_${timestamp}_${chapter.id}_${(1000 + (timestamp % 9000))}';
          return chapter.copyWith(
            sections: [
              ...chapter.sections,
              StudySection(id: newSecId, title: cleanName, isCompleted: false),
            ],
          );
        } else {
          final updatedSections = chapter.sections.where(
            (s) => s.title.trim().toLowerCase() != cleanName.toLowerCase(),
          ).toList();
          return chapter.copyWith(sections: updatedSections);
        }
      }).toList();

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void bulkDeleteSections(Set<String> sectionIdsOrCompositeKeys) {
    if (sectionIdsOrCompositeKeys.isEmpty) return;

    state = state.map((subject) {
      final updatedChapters = subject.chapters.map((chapter) {
        final updatedSections = chapter.sections.where((section) {
          final compositeKey = '${subject.id}|${chapter.id}|${section.id}';
          return !sectionIdsOrCompositeKeys.contains(compositeKey) &&
                 !sectionIdsOrCompositeKeys.contains(section.id);
        }).toList();

        return chapter.copyWith(sections: updatedSections);
      }).toList();

      return subject.copyWith(chapters: updatedChapters);
    }).toList();
  }

  void setDynamicSyllabus(String target) {
    state = SyllabusFactory.generateSyllabus(target);
  }
}