import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/exam_model.dart';
import '../models/journal_entry_model.dart';
import '../models/note_model.dart';
import '../models/routine_models.dart';
import '../providers/journal_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_preloader.dart';
import 'note_editor_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Type alias for JournalNotesScreen and JournalAndNotesScreen
typedef JournalNotesScreen = JournalScreen;
typedef JournalAndNotesScreen = JournalScreen;

final universityCoursesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('courses')
      .snapshots()
      .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final holidaySettingsStreamProvider = StreamProvider<HolidaySettings>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(HolidaySettings.defaultSettings);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('settings')
      .doc('holidays')
      .snapshots()
      .map((snap) {
        final data = snap.data();
        return data != null ? HolidaySettings.fromMap(data) : HolidaySettings.defaultSettings;
      });
});

abstract class JournalFeedItem {
  DateTime get date;
  bool get isPinned;
}

class NoteFeedItem implements JournalFeedItem {
  final NoteModel note;
  NoteFeedItem(this.note);

  @override
  DateTime get date => note.updatedAt;

  @override
  bool get isPinned => note.isPinned;
}

class ExamFeedItem implements JournalFeedItem {
  final ExamModel exam;
  ExamFeedItem(this.exam);

  @override
  DateTime get date => exam.date;

  @override
  bool get isPinned => false;
}

class StudySessionFeedItem implements JournalFeedItem {
  final StudyJournalEntry entry;
  StudySessionFeedItem(this.entry);

  @override
  DateTime get date => entry.timestamp;

  @override
  bool get isPinned => false;
}

class JournalScreen extends ConsumerStatefulWidget {
  final String? initialTag;
  final String? initialCourseFilter;
  const JournalScreen({super.key, this.initialTag, this.initialCourseFilter});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  bool _isGridView = true;
  final TextEditingController _searchController = TextEditingController();
  String _selectedJournalSegment = 'current'; // 'current' or 'archived'
  String? _selectedCourseFilter;

  static const List<String> tagFilters = [
    'All',
    'Notes',
    'Study Sessions',
    'Exam Journal',
    'Brain Dump',
    'Formula',
    'Mistake',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialCourseFilter != null && widget.initialCourseFilter!.trim().isNotEmpty) {
      _selectedCourseFilter = widget.initialCourseFilter!.trim();
    }
    if (widget.initialTag != null && widget.initialTag!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(selectedNoteTagProvider.notifier).state = widget.initialTag!;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1 && now.day == dt.day) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);

    final userProfile = ref.watch(userProfileProvider);
    final selectedTag = ref.watch(selectedNoteTagProvider);
    final searchQuery = ref.watch(noteSearchQueryProvider).trim().toLowerCase();
    final notesAsync = ref.watch(notesStreamProvider);
    final examsAsync = ref.watch(examsStreamProvider);
    final journalAsync = ref.watch(journalStreamProvider);

    // Active university courses & holiday settings for term filtering
    final coursesList = ref.watch(universityCoursesStreamProvider).value ?? [];
    final activeCourseIds = <String>{};
    final activeCourseNames = <String>{};
    for (final c in coursesList) {
      final id = (c['id'] ?? '').toString().trim().toLowerCase();
      final code = (c['courseCode'] ?? c['code'] ?? '').toString().trim().toLowerCase();
      final name = (c['courseName'] ?? c['name'] ?? '').toString().trim().toLowerCase();
      if (id.isNotEmpty) activeCourseIds.add(id);
      if (code.isNotEmpty) activeCourseNames.add(code);
      if (name.isNotEmpty) activeCourseNames.add(name);
    }
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).value ?? HolidaySettings.defaultSettings;

    // 1. Process standard notes (exclude Exam Journal and Study Session tags to avoid duplicate feed entries)
    final rawNotes = notesAsync.value ?? [];
    final seenIds = <String>{};
    final uniqueNotes = rawNotes.where((n) => n.id.isNotEmpty ? seenIds.add(n.id) : true).toList();
    final standardNotes = uniqueNotes
        .where((n) => !n.tags.contains('Exam Journal') && !n.tags.contains('Study Session'))
        .toList();

    // 2. Process completed exams with journal entries
    final completedExamsWithJournal = (examsAsync.value ?? [])
        .where((e) => e.isCompleted && e.journalEntries.isNotEmpty)
        .toList();

    // 3. Process study session journal logs
    final studySessionEntries = (journalAsync.value ?? [])
        .where((entry) => entry.isStudySession)
        .toList();

    // Available filter tags
    final tagFilters = [
      'All',
      'Notes',
      'Exam Journal',
      'Study Sessions',
      'Pinned',
      'Formulas',
      'Brain Dump',
      'Mistake',
    ];

    bool isCurrentTermNote(NoteModel note) {
      final text = '${note.title} ${note.plainTextContent} ${note.tags.join(' ')}'.toLowerCase();
      for (final id in activeCourseIds) {
        if (text.contains(id)) return true;
      }
      for (final code in activeCourseNames) {
        if (text.contains(code)) return true;
      }
      if (holidaySettings.semesterStart != null || holidaySettings.semesterEnd != null) {
        return holidaySettings.isWithinSemester(note.updatedAt);
      }
      return true;
    }

    bool isCurrentTermStudySession(StudyJournalEntry entry) {
      final subj = entry.subjectOrCourseId.toLowerCase().trim();
      if (activeCourseIds.contains(subj) || activeCourseNames.contains(subj)) return true;
      if (entry.mode.toLowerCase() == 'university') return true;
      if (entry.mode.toLowerCase() == 'admission') return false;
      if (holidaySettings.semesterStart != null || holidaySettings.semesterEnd != null) {
        return holidaySettings.isWithinSemester(entry.timestamp);
      }
      return true;
    }

    // Apply Active / Archived segregation if user is university student
    List<NoteModel> filteredNotes;
    List<ExamModel> filteredExams;
    List<StudyJournalEntry> filteredStudySessions;

    if (userProfile.isUniversityStudent) {
      if (_selectedJournalSegment == 'current') {
        filteredNotes = standardNotes.where(isCurrentTermNote).toList();
        filteredExams = []; // Admission model tests are legacy
        filteredStudySessions = studySessionEntries.where(isCurrentTermStudySession).toList();
      } else {
        filteredNotes = standardNotes.where((n) => !isCurrentTermNote(n)).toList();
        filteredExams = completedExamsWithJournal; // Display legacy model test reflections
        filteredStudySessions = studySessionEntries.where((s) => !isCurrentTermStudySession(s)).toList();
      }
    } else {
      filteredNotes = standardNotes;
      filteredExams = completedExamsWithJournal;
      filteredStudySessions = studySessionEntries;
    }

    final courseFilter = _selectedCourseFilter?.trim().toLowerCase();
    if (courseFilter != null && courseFilter.isNotEmpty) {
      filteredNotes = filteredNotes.where((note) {
        final text = '${note.title} ${note.plainTextContent} ${note.tags.join(' ')}'.toLowerCase();
        return text.contains(courseFilter);
      }).toList();

      filteredExams = filteredExams.where((exam) {
        final text = '${exam.examName} ${exam.subject}'.toLowerCase();
        return text.contains(courseFilter);
      }).toList();

      filteredStudySessions = filteredStudySessions.where((entry) {
        final text = '${entry.subjectOrCourseId} ${entry.title} ${entry.content} ${entry.topicsCovered ?? ''}'.toLowerCase();
        return text.contains(courseFilter);
      }).toList();
    }

    // 4. Build unified feed items based on active tag & search
    final List<JournalFeedItem> feedItems = [];

    final includeNotes = selectedTag == 'All' ||
        selectedTag == 'Notes' ||
        (selectedTag != 'Exam Journal' && selectedTag != 'Study Sessions' && selectedTag != 'All');

    final includeExams = selectedTag == 'All' ||
        selectedTag == 'Exam Journal' ||
        selectedTag == 'Mistake';

    final includeStudySessions = selectedTag == 'All' || selectedTag == 'Study Sessions';

    if (includeNotes) {
      for (final note in filteredNotes) {
        bool matchesTag = true;
        if (selectedTag == 'Pinned') {
          matchesTag = note.isPinned;
        } else if (selectedTag != 'All' && selectedTag != 'Notes') {
          matchesTag = note.tags.contains(selectedTag);
        }

        if (!matchesTag) continue;

        if (searchQuery.isNotEmpty) {
          final matchesTitle = note.title.toLowerCase().contains(searchQuery);
          final matchesContent = note.plainTextContent.toLowerCase().contains(searchQuery);
          if (!matchesTitle && !matchesContent) continue;
        }

        feedItems.add(NoteFeedItem(note));
      }
    }

    if (includeExams) {
      for (final exam in filteredExams) {
        if (selectedTag == 'Mistake') {
          final hasMistakes = exam.journalEntries.any((e) => e.type == 'mistake');
          if (!hasMistakes) continue;
        }

        if (searchQuery.isNotEmpty) {
          final matchesName = exam.examName.toLowerCase().contains(searchQuery);
          final matchesSubj = exam.subject.toLowerCase().contains(searchQuery);
          final matchesEntries = exam.journalEntries.any((e) => e.content.toLowerCase().contains(searchQuery));
          if (!matchesName && !matchesSubj && !matchesEntries) continue;
        }

        feedItems.add(ExamFeedItem(exam));
      }
    }

    if (includeStudySessions) {
      for (final entry in filteredStudySessions) {
        if (searchQuery.isNotEmpty) {
          final matchesTitle = entry.title.toLowerCase().contains(searchQuery);
          final matchesContent = entry.content.toLowerCase().contains(searchQuery);
          final matchesTopics = entry.topicsCovered?.toLowerCase().contains(searchQuery) ?? false;
          final matchesReflections = entry.reflections?.toLowerCase().contains(searchQuery) ?? false;
          final matchesSubj = entry.subjectOrCourseId.toLowerCase().contains(searchQuery);
          if (!matchesTitle && !matchesContent && !matchesTopics && !matchesReflections && !matchesSubj) {
            continue;
          }
        }

        feedItems.add(StudySessionFeedItem(entry));
      }
    }

    // Sort feed: pinned items first, then by date descending
    feedItems.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.date.compareTo(a.date);
    });

    final isLoading = notesAsync.isLoading || examsAsync.isLoading || journalAsync.isLoading;
    final hasError = notesAsync.hasError || examsAsync.hasError || journalAsync.hasError;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: Row(
          children: [
            const AppLogo(size: 28),
            const SizedBox(width: 10),
            Text(
              'Journal & Notes',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: Colors.white,
            ),
            tooltip: _isGridView ? 'List View' : 'Grid View',
            onPressed: () {
              SafeHaptics.lightImpact();
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Segment Filter for University Students [Current Term | Admission / Archived]
          if (userProfile.isUniversityStudent) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Container(
                height: 42,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1412),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          SafeHaptics.selectionClick();
                          setState(() => _selectedJournalSegment = 'current');
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedJournalSegment == 'current'
                                ? accentColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.school_rounded,
                                size: 15,
                                color: _selectedJournalSegment == 'current'
                                    ? const Color(0xFF140F0E)
                                    : const Color(0xFFABA093),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Current Term',
                                style: GoogleFonts.plusJakartaSans(
                                  color: _selectedJournalSegment == 'current'
                                      ? const Color(0xFF140F0E)
                                      : const Color(0xFFABA093),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          SafeHaptics.selectionClick();
                          setState(() => _selectedJournalSegment = 'archived');
                        },
                        borderRadius: BorderRadius.circular(9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedJournalSegment == 'archived'
                                ? accentColor
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_rounded,
                                size: 15,
                                color: _selectedJournalSegment == 'archived'
                                    ? const Color(0xFF140F0E)
                                    : const Color(0xFFABA093),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Admission / Archived',
                                style: GoogleFonts.plusJakartaSans(
                                  color: _selectedJournalSegment == 'archived'
                                      ? const Color(0xFF140F0E)
                                      : const Color(0xFFABA093),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                ref.read(noteSearchQueryProvider.notifier).state = val;
              },
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search notes, formulas, exam reflections...',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13.5),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFABA093), size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: Color(0xFFABA093), size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(noteSearchQueryProvider.notifier).state = '';
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1C1412),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderColor, width: 0.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: borderColor, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: accentColor, width: 1.2),
                ),
              ),
            ),
          ),

          // Course Scope Filter Badge
          if (_selectedCourseFilter != null && _selectedCourseFilter!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_rounded, color: accentColor, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Course: $_selectedCourseFilter',
                          style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            SafeHaptics.lightImpact();
                            setState(() => _selectedCourseFilter = null);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close_rounded, color: accentColor, size: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // 2. Filter Tag Chips
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              itemCount: tagFilters.length,
              itemBuilder: (context, index) {
                final tag = tagFilters[index];
                final isSelected = selectedTag == tag;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(tag),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        SafeHaptics.lightImpact();
                        ref.read(selectedNoteTagProvider.notifier).state = tag;
                      }
                    },
                    selectedColor: accentColor,
                    backgroundColor: const Color(0xFF1C1412),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isSelected ? accentColor : borderColor,
                        width: 0.8,
                      ),
                    ),
                    labelStyle: GoogleFonts.plusJakartaSans(
                      color: isSelected ? const Color(0xFF140F0E) : const Color(0xFFABA093),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 3. Unified Feed (Mix of Grid Notes & Full-Width Aggregated Exam Cards)
          Expanded(
            child: isLoading
                ? const Center(
                    child: AppPreloader(size: 44),
                  )
                : hasError
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Text(
                            'Error loading journal entries',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444)),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _buildFeedView(context, feedItems),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: const Color(0xFF140F0E),
        elevation: 3,
        icon: const Icon(Icons.add_rounded, color: Color(0xFF140F0E), size: 22),
        label: Text(
          'New Note',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF140F0E), fontWeight: FontWeight.bold),
        ),
        onPressed: () {
          SafeHaptics.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
          );
        },
      ),
    );
  }

  /// Builds a responsive mixed Slivers layout where Exam Cards take full width and Notes grid in 2 columns
  Widget _buildFeedView(BuildContext context, List<JournalFeedItem> items) {
    if (items.isEmpty) {
      return _buildEmptyState(context);
    }

    final List<Widget> slivers = [];
    List<NoteModel> noteChunk = [];

    void flushNoteChunk() {
      if (noteChunk.isEmpty) return;

      final chunk = List<NoteModel>.from(noteChunk);
      if (_isGridView) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildNoteCard(chunk[index]),
                childCount: chunk.length,
              ),
            ),
          ),
        );
      } else {
        slivers.add(
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildNoteCard(chunk[index]),
              ),
              childCount: chunk.length,
            ),
          ),
        );
      }
      noteChunk = [];
    }

    for (final item in items) {
      if (item is ExamFeedItem) {
        flushNoteChunk();
        slivers.add(
          SliverToBoxAdapter(
            child: _buildAggregatedExamJournalCard(item.exam),
          ),
        );
      } else if (item is StudySessionFeedItem) {
        flushNoteChunk();
        slivers.add(
          SliverToBoxAdapter(
            child: _buildStudySessionCard(item.entry),
          ),
        );
      } else if (item is NoteFeedItem) {
        noteChunk.add(item.note);
      }
    }
    flushNoteChunk();

    return Padding(
  padding: const EdgeInsets.all(16),
  child: CustomScrollView(
    physics: const BouncingScrollPhysics(),
    slivers: slivers,
  ),
);
  }

  /// Study Session Log Card with distinct badge and organized structure
  Widget _buildStudySessionCard(StudyJournalEntry entry) {
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);
    final dateStr = _formatDate(entry.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Distinct Badge + Mode + Date + More Menu
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              // Distinct Study Session Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⏱️', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 5),
                    Text(
                      'Study Session • ${entry.durationMinutes} mins',
                      style: GoogleFonts.plusJakartaSans(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140F0E),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor, width: 0.6),
                    ),
                    child: Text(
                      entry.mode == 'university' ? 'University' : 'Admission',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dateStr,
                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 11),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFABA093), size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onSelected: (val) async {
                      if (val == 'delete') {
                        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                        await ref.read(journalServiceProvider).deleteJournalEntry(uid, entry.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Study log removed from Journal.', style: GoogleFonts.plusJakartaSans()),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 8),
                            Text('Delete Log', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            entry.title,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          // Topics Covered / Keywords
          if (entry.topicsCovered != null && entry.topicsCovered!.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF140F0E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tag_rounded, size: 16, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOPICS COVERED',
                          style: GoogleFonts.plusJakartaSans(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.topicsCovered!,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Quick Notes / Reflections
          if (entry.reflections != null && entry.reflections!.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1412),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUICK NOTES & REFLECTIONS',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFF59E0B),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.reflections!,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 12.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else if (entry.topicsCovered == null || entry.topicsCovered!.trim().isEmpty) ...[
            Text(
              entry.content,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  /// Aggregated Exam Journal Card grouping all mistakes and tips for a single exam
  Widget _buildAggregatedExamJournalCard(ExamModel exam) {
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);

    final pct = exam.totalMarks > 0
        ? ((exam.marksObtained / exam.totalMarks) * 100).toInt()
        : 0;

    final dateStr = _formatDate(exam.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row with Exam Info & Score Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Exam Journal',
                            style: GoogleFonts.plusJakartaSans(
                              color: accentColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      exam.examName,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      exam.subject,
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF140F0E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor, width: 0.8),
                ),
                child: Column(
                  children: [
                    Text(
                      '${exam.marksObtained.toInt()} / ${exam.totalMarks.toInt()}',
                      style: GoogleFonts.jetBrainsMono(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFFABA093),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: borderColor, height: 1),
          const SizedBox(height: 14),

          // Grouped Journal Entries
          ...exam.journalEntries.map((entry) {
            final isMistake = entry.type == 'mistake';
            final badgeColor = isMistake ? const Color(0xFFEF4444) : const Color(0xFF06D6A0);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF140F0E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(isMistake ? '🔴' : '💡', style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Text(
                        isMistake ? 'MISTAKE REASON' : 'KEY TIP / TRICK',
                        style: GoogleFonts.plusJakartaSans(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.content,
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    const accentColor = Color(0xFFF2B78A);
    final search = ref.watch(noteSearchQueryProvider);
    final tag = ref.watch(selectedNoteTagProvider);

    String message = 'No notes saved yet.\nTap the + button to capture your thoughts!';
    if (search.isNotEmpty) {
      message = 'No notes matching "$search"';
    } else if (tag == 'Exam Journal') {
      message = 'No exam reflections recorded yet.\nRecord exam scores with mistakes or tips to view them here!';
    } else if (tag == 'Study Sessions') {
      message = 'No study session notes recorded yet.\nFinish a timer session to auto-save your topics and reflections!';
    } else if (tag != 'All') {
      message = 'No notes found under "$tag"';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF241C1A),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
              ),
              child: Icon(
                search.isNotEmpty ? Icons.search_off_rounded : Icons.auto_stories_rounded,
                color: accentColor,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 14, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCard(NoteModel note) {
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);

    final tagText = note.tags.isNotEmpty ? note.tags.first : 'General';

    return GestureDetector(
      onTap: () {
        SafeHaptics.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: note.isPinned ? accentColor : borderColor,
            width: note.isPinned ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tagText,
                        style: GoogleFonts.plusJakartaSans(
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (note.isPinned)
                      const Icon(Icons.push_pin_rounded, color: accentColor, size: 16),
                  ],
                ),
                const SizedBox(height: 10),

                Text(
                  note.title.isNotEmpty ? note.title : 'Untitled Note',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                Text(
                  note.plainTextContent,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFABA093),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(note.updatedAt),
                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 10.5),
                  ),
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      color: note.isPinned ? accentColor : const Color(0xFFABA093),
                      size: 16,
                    ),
                    tooltip: note.isPinned ? 'Unpin' : 'Pin',
                    onPressed: () {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null) {
                        ref.read(noteServiceProvider).togglePinNote(uid, note.id, note.isPinned);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
