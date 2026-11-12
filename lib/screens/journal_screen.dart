import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../models/exam_model.dart';
import '../models/journal_entry_model.dart';
import '../models/note_model.dart';
import '../models/routine_models.dart';
import '../models/syllabus_models.dart';
import '../providers/firestore_providers.dart';
import '../providers/journal_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../widgets/app_preloader.dart';
import 'note_editor_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Type alias for JournalNotesScreen and JournalAndNotesScreen
typedef JournalNotesScreen = JournalScreen;
typedef JournalAndNotesScreen = JournalScreen;

final universityCoursesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
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
  if (Firebase.apps.isEmpty) return Stream.value(HolidaySettings.defaultSettings);
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

typedef _JournalTagTargetOption = ({String id, String label});

/// Screen 05: Academic Journal & Reflection Workspace (Stitch Design System)
/// 1:1 Reference Implementation of academic_journal_brain_dump_desktop_web(_dark_mode)
/// and academic_journal_brain_dump_mobile(_dark_mode) from _design_reference.
class JournalScreen extends ConsumerStatefulWidget {
  final String? initialTag;
  final String? initialCourseFilter;
  const JournalScreen({super.key, this.initialTag, this.initialCourseFilter});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  bool _isGridView = false;
  final TextEditingController _searchController = TextEditingController();
  String _selectedJournalSegment = 'current'; // 'current' or 'archived'
  String? _selectedCourseFilter;
  String? _selectedDesktopItemKey;

  static const List<String> _tagFilters = [
    'All',
    'Notes',
    'Exam Journal',
    'Study Sessions',
    'Pinned',
    'Formulas',
    'Brain Dump',
    'Mistake',
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

  String _itemKey(JournalFeedItem item) {
    if (item is NoteFeedItem) return 'note_${item.note.id}_${item.note.title}';
    if (item is ExamFeedItem) return 'exam_${item.exam.id}_${item.exam.examName}';
    if (item is StudySessionFeedItem) return 'session_${item.entry.id}_${item.entry.title}';
    return item.hashCode.toString();
  }

  String _formatCardDate(DateTime dt) {
    return DateFormat('dd MMM yyyy • EEE').format(dt).toUpperCase();
  }

  String _formatTime(DateTime dt) {
    return DateFormat('hh:mm a').format(dt);
  }

  String _formatHeaderDate(DateTime dt) {
    return '${DateFormat('EEEE, dd MMM yyyy').format(dt)} • ${DateFormat('hh:mm a').format(dt)}';
  }

  String _buildTrackOverline(UserProfile profile) {
    if (profile.isUniversityStudent) {
      final lvl = profile.level?.trim() ?? '';
      final trm = profile.term?.trim() ?? '';
      if (lvl.isNotEmpty && trm.isNotEmpty) {
        return 'UNIVERSITY TRACK // $lvl • $trm'.toUpperCase();
      }
      return 'UNIVERSITY TRACK // ACADEMIC JOURNAL';
    }
    final target = profile.primaryTarget.trim();
    if (target.toLowerCase().contains('hsc') || (profile.collegeClass?.trim().isNotEmpty ?? false)) {
      return 'COLLEGE / HSC TRACK // STUDY LOG & REFLECTIONS';
    }
    if (target.isNotEmpty) {
      return 'ADMISSION TRACK // ${target.toUpperCase()}';
    }
    return 'ACADEMIC JOURNAL // REFLECTIONS & LOGS';
  }

  List<_JournalTagTargetOption> _resolveTagTargets({
    required bool isUniversity,
    required List<Map<String, dynamic>> rawCourses,
    required List<Subject> streamSubjects,
    required List<Subject> memorySubjects,
  }) {
    final List<_JournalTagTargetOption> result = [];
    final Set<String> seen = {};

    if (isUniversity) {
      for (final c in rawCourses) {
        if (c['isArchived'] == true) continue;
        final code = (c['courseCode'] ?? c['code'] ?? '').toString().trim();
        final name = (c['courseName'] ?? c['title'] ?? c['name'] ?? '').toString().trim();
        final label = (code.isNotEmpty && name.isNotEmpty && code != name)
            ? '$code • $name'
            : (code.isNotEmpty ? code : name);
        final value = code.isNotEmpty ? code : label;
        if (value.isNotEmpty && seen.add(value)) {
          result.add((id: value, label: label));
        }
      }
      return result;
    }

    final primary = streamSubjects.isNotEmpty ? streamSubjects : memorySubjects;
    for (final s in primary) {
      final title = s.title.trim();
      if (title.isNotEmpty && seen.add(title)) {
        result.add((id: title, label: title));
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 900;

    final userProfile = ref.watch(userProfileProvider);
    final isUniversity = userProfile.isUniversityStudent;
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

    if (isUniversity) {
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
          final matchesTags = note.tags.any((t) => t.toLowerCase().contains(searchQuery));
          if (!matchesTitle && !matchesContent && !matchesTags) continue;
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
      backgroundColor: colors.background,
      floatingActionButton: isWide
          ? null
          : FloatingActionButton.extended(
              backgroundColor: colors.secondary,
              foregroundColor: Colors.white,
              elevation: 3,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                'New Entry',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () => _showReflectionComposerModal(context),
            ),
      body: SafeArea(
        child: isWide
            ? _buildDesktopLayout(
                context: context,
                colors: colors,
                isDark: isDark,
                userProfile: userProfile,
                isUniversity: isUniversity,
                selectedTag: selectedTag,
                feedItems: feedItems,
                isLoading: isLoading,
                hasError: hasError,
              )
            : _buildMobileLayout(
                context: context,
                colors: colors,
                isDark: isDark,
                userProfile: userProfile,
                isUniversity: isUniversity,
                selectedTag: selectedTag,
                feedItems: feedItems,
                isLoading: isLoading,
                hasError: hasError,
              ),
      ),
    );
  }

  // ===========================================================================
  // DESKTOP / WEB DUAL-PANE LAYOUT (Stitch 1:1 Reference)
  // ===========================================================================
  Widget _buildDesktopLayout({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required UserProfile userProfile,
    required bool isUniversity,
    required String selectedTag,
    required List<JournalFeedItem> feedItems,
    required bool isLoading,
    required bool hasError,
  }) {
    final selectedItem = feedItems.isEmpty
        ? null
        : feedItems.firstWhere(
            (item) => _itemKey(item) == _selectedDesktopItemKey,
            orElse: () => feedItems.first,
          );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Utility Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.auto_stories_outlined, size: 16, color: colors.secondary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _buildTrackOverline(userProfile),
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUniversity) ...[
                        _buildUniversitySegmentBar(colors, isDark, compact: true),
                        const SizedBox(width: 12),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Text(
                          '${feedItems.length} ${feedItems.length == 1 ? 'ENTRY' : 'ENTRIES'} INDEXED',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Dual-Pane Split: Left Chronological Feed (340px) + Right Active Reader / Composer
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Pane (340px)
                    SizedBox(
                      width: 340,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Primary + New Entry Button + Open Rich Editor icon
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: colors.primary,
                                      foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                    onPressed: () => _showReflectionComposerModal(context),
                                    icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                                    label: Text(
                                      'New Entry',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Tooltip(
                                message: 'Open Rich Text Editor',
                                child: InkWell(
                                  onTap: () {
                                    SafeHaptics.lightImpact();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    height: 44,
                                    width: 44,
                                    decoration: BoxDecoration(
                                      color: colors.surface,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: colors.surfaceBorder),
                                    ),
                                    child: Icon(Icons.edit_note_rounded, color: colors.textPrimary, size: 20),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // 48px Search Bar
                          _buildSearchField(colors),

                          if (_selectedCourseFilter != null && _selectedCourseFilter!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildScopeFilterBadge(colors, isUniversity),
                          ],

                          const SizedBox(height: 10),

                          // Filter Tag Chips
                          _buildFilterChipsRow(colors, isDark, selectedTag),

                          const SizedBox(height: 12),

                          // Chronological Entry Cards
                          Expanded(
                            child: isLoading
                                ? const Center(child: AppPreloader(size: 36))
                                : hasError
                                    ? _buildErrorBanner(colors)
                                    : feedItems.isEmpty
                                        ? _buildEmptyStateCard(context, colors, isCompact: true)
                                        : ListView.separated(
                                            itemCount: feedItems.length,
                                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                                            itemBuilder: (ctx, idx) {
                                              final item = feedItems[idx];
                                              final key = _itemKey(item);
                                              final isSelected = selectedItem != null && _itemKey(selectedItem) == key;
                                              return _buildSidebarEntryCard(
                                                item: item,
                                                isSelected: isSelected,
                                                colors: colors,
                                                onTap: () {
                                                  SafeHaptics.selectionClick();
                                                  setState(() => _selectedDesktopItemKey = key);
                                                },
                                              );
                                            },
                                          ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Right Pane: Active Entry Reader & Actions (or Empty State)
                    Expanded(
                      child: isLoading
                          ? const Center(child: AppPreloader(size: 44))
                          : hasError
                              ? _buildErrorBanner(colors)
                              : selectedItem == null
                                  ? _buildEmptyStateCard(context, colors)
                                  : _buildDesktopDetailPane(
                                      context: context,
                                      item: selectedItem,
                                      colors: colors,
                                      isDark: isDark,
                                      userProfile: userProfile,
                                      isUniversity: isUniversity,
                                    ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MOBILE LAYOUT (Stitch 1:1 Reference)
  // ===========================================================================
  Widget _buildMobileLayout({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required UserProfile userProfile,
    required bool isUniversity,
    required String selectedTag,
    required List<JournalFeedItem> feedItems,
    required bool isLoading,
    required bool hasError,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact Mobile Header Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Journal & Notes',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${feedItems.length} ${feedItems.length == 1 ? 'ENTRY' : 'ENTRIES'}',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: _isGridView ? 'List View' : 'Grid View',
                    child: InkWell(
                      onTap: () {
                        SafeHaptics.lightImpact();
                        setState(() => _isGridView = !_isGridView);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Icon(
                          _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                          color: colors.textPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Open Rich Text Editor',
                    child: InkWell(
                      onTap: () {
                        SafeHaptics.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Icon(Icons.edit_note_rounded, color: colors.textPrimary, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Top Segment Filter for University Students [Current Term | Admission / Archived]
        if (isUniversity)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _buildUniversitySegmentBar(colors, isDark),
          ),

        // 48px Search Field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: _buildSearchField(colors),
        ),

        // Course / Subject Scope Filter Badge
        if (_selectedCourseFilter != null && _selectedCourseFilter!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: _buildScopeFilterBadge(colors, isUniversity),
          ),

        // Horizontal Filter Chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: _buildFilterChipsRow(colors, isDark, selectedTag),
        ),

        // Unified Chronological Feed
        Expanded(
          child: isLoading
              ? const Center(child: AppPreloader(size: 44))
              : hasError
                  ? _buildErrorBanner(colors)
                  : _buildMobileFeedView(context, feedItems, colors),
        ),
      ],
    );
  }

  Widget _buildUniversitySegmentBar(ChondrobinduThemeColors colors, bool isDark, {bool compact = false}) {
    Widget buildSeg(String label, String value, IconData icon) {
      final isSelected = _selectedJournalSegment == value;
      return InkWell(
        onTap: () {
          SafeHaptics.selectionClick();
          setState(() => _selectedJournalSegment = value);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 5 : 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? (isDark ? const Color(0xFF171C24) : Colors.white)
                    : colors.textMuted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    color: isSelected
                        ? (isDark ? const Color(0xFF171C24) : Colors.white)
                        : colors.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 11.5 : 12.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildSeg('Current Term', 'current', Icons.school_rounded),
                const SizedBox(width: 4),
                buildSeg('Admission / Archived', 'archived', Icons.inventory_2_rounded),
              ],
            )
          : Row(
              children: [
                Expanded(child: buildSeg('Current Term', 'current', Icons.school_rounded)),
                const SizedBox(width: 4),
                Expanded(child: buildSeg('Admission / Archived', 'archived', Icons.inventory_2_rounded)),
              ],
            ),
    );
  }

  Widget _buildSearchField(ChondrobinduThemeColors colors) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        onChanged: (val) {
          ref.read(noteSearchQueryProvider.notifier).state = val;
        },
        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'Search notes, formulas, reflections...',
          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
          prefixIcon: Icon(Icons.search_rounded, color: colors.textMuted, size: 18),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: colors.textMuted, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(noteSearchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          filled: true,
          fillColor: colors.recessed,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.surfaceBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: colors.primary),
          ),
        ),
      ),
    );
  }

  Widget _buildScopeFilterBadge(ChondrobinduThemeColors colors, bool isUniversity) {
    final prefix = isUniversity ? 'Course' : 'Subject';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, color: colors.primary, size: 14),
              const SizedBox(width: 6),
              Text(
                '$prefix: $_selectedCourseFilter',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  SafeHaptics.lightImpact();
                  setState(() => _selectedCourseFilter = null);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, color: colors.primary, size: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChipsRow(ChondrobinduThemeColors colors, bool isDark, String selectedTag) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tagFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, idx) {
          final tag = _tagFilters[idx];
          final isSelected = selectedTag == tag;
          return InkWell(
            onTap: () {
              SafeHaptics.lightImpact();
              ref.read(selectedNoteTagProvider.notifier).state = tag;
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : colors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: isSelected ? colors.primary : colors.surfaceBorder),
              ),
              child: Text(
                tag,
                style: GoogleFonts.plusJakartaSans(
                  color: isSelected
                      ? (isDark ? const Color(0xFF171C24) : Colors.white)
                      : colors.textMuted,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebarEntryCard({
    required JournalFeedItem item,
    required bool isSelected,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    String badgeLabel;
    Color badgeColor;
    String title;
    String preview;
    List<String> chips = const [];

    if (item is NoteFeedItem) {
      final n = item.note;
      badgeLabel = n.tags.isNotEmpty ? n.tags.first : 'Note';
      badgeColor = colors.secondary;
      title = n.title.isNotEmpty ? n.title : 'Untitled Note';
      preview = n.plainTextContent;
      chips = n.tags.take(2).toList();
    } else if (item is StudySessionFeedItem) {
      final e = item.entry;
      badgeLabel = '${e.durationMinutes}m Session';
      badgeColor = colors.primary;
      title = e.title;
      preview = e.topicsCovered?.trim().isNotEmpty == true ? e.topicsCovered! : e.content;
      if (e.subjectOrCourseId.trim().isNotEmpty) chips = [e.subjectOrCourseId.trim()];
    } else if (item is ExamFeedItem) {
      final ex = item.exam;
      final pct = ex.totalMarks > 0 ? ((ex.marksObtained / ex.totalMarks) * 100).round() : 0;
      badgeLabel = 'Exam $pct%';
      badgeColor = const Color(0xFF4E9F72);
      title = ex.examName;
      preview = ex.journalEntries.map((j) => j.content).join(' • ');
      if (ex.subject.trim().isNotEmpty) chips = [ex.subject.trim()];
    } else {
      badgeLabel = 'Entry';
      badgeColor = colors.primary;
      title = '';
      preview = '';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colors.primary
                : (item.isPinned ? colors.secondary : colors.surfaceBorder),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatCardDate(item.date),
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    badgeLabel,
                    style: GoogleFonts.plusJakartaSans(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (preview.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                preview,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: chips.map((c) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.recessed,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Text(
                          '#$c',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.primary,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                Text(
                  _formatTime(item.date),
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopDetailPane({
    required BuildContext context,
    required JournalFeedItem item,
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required UserProfile userProfile,
    required bool isUniversity,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item is NoteFeedItem) ...[
              _buildDesktopNoteDetail(context, item.note, colors, isDark, userProfile),
            ] else if (item is StudySessionFeedItem) ...[
              _buildStudySessionCard(item.entry, colors, isUniversity, embedded: true),
            ] else if (item is ExamFeedItem) ...[
              _buildAggregatedExamJournalCard(item.exam, colors, isUniversity, embedded: true),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopNoteDetail(
    BuildContext context,
    NoteModel note,
    ChondrobinduThemeColors colors,
    bool isDark,
    UserProfile userProfile,
  ) {
    final body = note.plainTextContent;
    final wordCount = body.trim().isEmpty ? 0 : body.trim().split(RegExp(r'\s+')).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Meta Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _formatHeaderDate(note.updatedAt),
                      style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    color: note.isPinned ? colors.secondary : colors.textMuted,
                    size: 18,
                  ),
                  tooltip: note.isPinned ? 'Unpin' : 'Pin',
                  onPressed: () {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      ref.read(noteServiceProvider).togglePinNote(uid, note.id, note.isPinned);
                    }
                  },
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.primary,
                    side: BorderSide(color: colors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: () {
                    SafeHaptics.lightImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: Text(
                    'Edit Note',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Tag Pills
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: note.tags.map((tag) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Text(
                '#$tag',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        Text(
          _buildTrackOverline(userProfile),
          style: GoogleFonts.jetBrainsMono(
            color: colors.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          note.title.isNotEmpty ? note.title : 'Untitled Note',
          style: GoogleFonts.plusJakartaSans(
            color: colors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.25,
          ),
        ),

        const SizedBox(height: 16),
        Divider(color: colors.surfaceBorder, height: 1),
        const SizedBox(height: 18),

        Text(
          body.isNotEmpty ? body : 'No content recorded for this note yet.',
          style: GoogleFonts.plusJakartaSans(
            color: body.isNotEmpty ? colors.textPrimary : colors.textMuted,
            fontSize: 14.5,
            height: 1.65,
          ),
        ),

        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$wordCount WORDS • ${body.length} CHARS',
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
              Text(
                'SYNCED',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF4E9F72),
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // MOBILE FEED VIEW
  // ===========================================================================
  Widget _buildMobileFeedView(
    BuildContext context,
    List<JournalFeedItem> items,
    ChondrobinduThemeColors colors,
  ) {
    if (items.isEmpty) {
      return _buildEmptyStateCard(context, colors);
    }

    final isUniversity = ref.read(userProfileProvider).isUniversityStudent;
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
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.86,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildNoteCard(chunk[index], colors),
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
                child: _buildNoteCard(chunk[index], colors),
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
            child: _buildAggregatedExamJournalCard(item.exam, colors, isUniversity),
          ),
        );
      } else if (item is StudySessionFeedItem) {
        flushNoteChunk();
        slivers.add(
          SliverToBoxAdapter(
            child: _buildStudySessionCard(item.entry, colors, isUniversity),
          ),
        );
      } else if (item is NoteFeedItem) {
        noteChunk.add(item.note);
      }
    }
    flushNoteChunk();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  /// Study Session Log Card
  Widget _buildStudySessionCard(
    StudyJournalEntry entry,
    ChondrobinduThemeColors colors,
    bool isUniversity, {
    bool embedded = false,
  }) {
    final dateStr = _formatCardDate(entry.timestamp);
    final timeStr = _formatTime(entry.timestamp);
    final modeLabel = entry.mode.toLowerCase() == 'university'
        ? 'University'
        : (isUniversity ? 'Admission' : 'Study Log');

    return Container(
      margin: embedded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(embedded ? 0 : 16),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 13, color: colors.secondary),
                    const SizedBox(width: 5),
                    Text(
                      'Study Session • ${entry.durationMinutes} mins',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.secondary,
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
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Text(
                      modeLabel,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$dateStr • $timeStr',
                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, color: colors.textMuted, size: 18),
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

          Text(
            entry.title,
            style: GoogleFonts.plusJakartaSans(
              color: colors.textPrimary,
              fontSize: embedded ? 20 : 15.5,
              fontWeight: FontWeight.bold,
            ),
          ),

          if (entry.subjectOrCourseId.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Text(
                '#${entry.subjectOrCourseId.trim()}',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          if (entry.topicsCovered != null && entry.topicsCovered!.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tag_rounded, size: 16, color: colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOPICS COVERED',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.topicsCovered!,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 13,
                            height: 1.4,
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

          if (entry.reflections != null && entry.reflections!.trim().isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.secondary.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 16, color: colors.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'QUICK NOTES & REFLECTIONS',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.reflections!,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 13,
                            height: 1.4,
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
              style: GoogleFonts.plusJakartaSans(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Aggregated Exam Journal Card grouping mistakes and tips for a single exam
  Widget _buildAggregatedExamJournalCard(
    ExamModel exam,
    ChondrobinduThemeColors colors,
    bool isUniversity, {
    bool embedded = false,
  }) {
    final pct = exam.totalMarks > 0 ? ((exam.marksObtained / exam.totalMarks) * 100).toInt() : 0;
    final dateStr = _formatCardDate(exam.date);

    return Container(
      margin: embedded ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(embedded ? 0 : 16),
      decoration: embedded
          ? null
          : BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                            color: colors.secondary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Exam Journal',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.secondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dateStr,
                            style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      exam.examName,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: embedded ? 20 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      exam.subject,
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  children: [
                    Text(
                      '${exam.marksObtained.toInt()} / ${exam.totalMarks.toInt()}',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$pct%',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
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
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 14),

          ...exam.journalEntries.map((entry) {
            final isMistake = entry.type == 'mistake';
            final badgeColor = isMistake ? const Color(0xFFFF8075) : const Color(0xFF4E9F72);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMistake ? Icons.error_outline_rounded : Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isMistake ? 'MISTAKE REASON' : 'KEY TIP / TRICK',
                        style: GoogleFonts.jetBrainsMono(
                          color: badgeColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.content,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
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

  Widget _buildNoteCard(NoteModel note, ChondrobinduThemeColors colors) {
    final tagText = note.tags.isNotEmpty ? note.tags.first : 'General';

    return InkWell(
      onTap: () {
        SafeHaptics.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: note.isPinned ? colors.secondary : colors.surfaceBorder,
            width: note.isPinned ? 1.3 : 1,
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
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.secondary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          tagText,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.secondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (note.isPinned)
                      Icon(Icons.push_pin_rounded, color: colors.secondary, size: 15),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  note.title.isNotEmpty ? note.title : 'Untitled Note',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
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
                    color: colors.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatCardDate(note.updatedAt),
                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
                  ),
                  InkWell(
                    onTap: () {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null) {
                        ref.read(noteServiceProvider).togglePinNote(uid, note.id, note.isPinned);
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        note.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                        color: note.isPinned ? colors.secondary : colors.textMuted,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard(
    BuildContext context,
    ChondrobinduThemeColors colors, {
    bool isCompact = false,
  }) {
    final search = ref.watch(noteSearchQueryProvider);
    final tag = ref.watch(selectedNoteTagProvider);

    String message = 'No journal entries yet.\nCapture a study reflection, formula, or brain dump to get started.';
    if (search.isNotEmpty) {
      message = 'No entries matching "$search".';
    } else if (tag == 'Exam Journal') {
      message = 'No exam reflections recorded yet.\nRecord exam scores with mistakes or tips to view them here.';
    } else if (tag == 'Study Sessions') {
      message = 'No study session logs recorded yet.\nFinish a focus timer session to save your topics and reflections.';
    } else if (tag != 'All') {
      message = 'No entries found under "$tag".';
    }

    return Container(
      padding: EdgeInsets.all(isCompact ? 20 : 32),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 18),
              decoration: BoxDecoration(
                color: colors.recessed,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Icon(
                search.isNotEmpty ? Icons.search_off_rounded : Icons.auto_stories_outlined,
                color: colors.primary,
                size: isCompact ? 28 : 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                color: colors.textMuted,
                fontSize: isCompact ? 12.5 : 13.5,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            if (!isCompact) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF171C24)
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showReflectionComposerModal(context),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(
                  'New Journal Entry',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF8075).withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          'Unable to load journal entries right now.',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFFF8075), fontSize: 13.5),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // ===========================================================================
  // TRACK-AWARE REFLECTION COMPOSER MODAL (48px Inputs, Stitch Tokens)
  // ===========================================================================
  void _showReflectionComposerModal(BuildContext context) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String selectedCategory = 'Brain Dump';
    String? selectedTargetId;
    bool isSaving = false;

    const categories = ['General', 'Brain Dump', 'Formulas', 'Mistake'];

    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, modalRef, _) {
          final userProfile = modalRef.watch(userProfileProvider);
          final isUniversity = userProfile.isUniversityStudent;
          final rawCourses = modalRef.watch(universityCoursesStreamProvider).valueOrNull ?? [];
          final streamSubjects = modalRef.watch(activeSyllabusSubjectsStreamProvider).valueOrNull ?? [];
          final memSubjects = modalRef.watch(syllabusProvider);
          final targets = _resolveTagTargets(
            isUniversity: isUniversity,
            rawCourses: rawCourses,
            streamSubjects: streamSubjects,
            memorySubjects: memSubjects,
          );
          final effectiveTargetId = targets.any((t) => t.id == selectedTargetId) ? selectedTargetId : null;

          return StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.surfaceBorder),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'New Journal Reflection',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
                      );
                    },
                    icon: Icon(Icons.edit_note_rounded, size: 16, color: colors.primary),
                    label: Text(
                      'Rich Editor',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Category Pills
                      Text(
                        'Entry Category',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: categories.map((cat) {
                          final isSelected = selectedCategory == cat;
                          return InkWell(
                            onTap: () => setDialogState(() => selectedCategory = cat),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.secondary.withValues(alpha: 0.16) : colors.recessed,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? colors.secondary : colors.surfaceBorder,
                                ),
                              ),
                              child: Text(
                                cat,
                                style: GoogleFonts.plusJakartaSans(
                                  color: isSelected ? colors.secondary : colors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 14),

                      // Track-Aware Course / Subject Tag Selector
                      Text(
                        isUniversity ? 'Link Course (Optional)' : 'Link Subject (Optional)',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: colors.recessed,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: effectiveTargetId,
                            isExpanded: true,
                            dropdownColor: colors.surface,
                            hint: Text(
                              isUniversity ? 'Select course' : 'Select subject',
                              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                            ),
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: Text(
                                  isUniversity ? 'No course linked' : 'No subject linked',
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                                ),
                              ),
                              ...targets.map((t) {
                                return DropdownMenuItem<String?>(
                                  value: t.id,
                                  child: Text(
                                    t.label,
                                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) => setDialogState(() => selectedTargetId = val),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Title Input (48px)
                      Text(
                        'Title',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: titleCtrl,
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'e.g., Key takeaways from today’s practice',
                            hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                            filled: true,
                            fillColor: colors.recessed,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: colors.surfaceBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: colors.primary),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Reflection Body
                      Text(
                        'Reflection / Notes',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: bodyCtrl,
                        maxLines: 5,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5, height: 1.45),
                        decoration: InputDecoration(
                          hintText: 'Write what clicked, blockers, formulas, or mistakes to review...',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          filled: true,
                          fillColor: colors.recessed,
                          isDense: true,
                          contentPadding: const EdgeInsets.all(12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.surfaceBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          final title = titleCtrl.text.trim();
                          final body = bodyCtrl.text.trim();
                          if (title.isEmpty && body.isEmpty) return;

                          setDialogState(() => isSaving = true);
                          final tags = <String>[
                            selectedCategory,
                            if (selectedTargetId != null && selectedTargetId!.isNotEmpty) selectedTargetId!,
                          ];
                          final uid = Firebase.apps.isNotEmpty ? (FirebaseAuth.instance.currentUser?.uid ?? '') : '';
                          if (uid.isNotEmpty) {
                            await ref.read(noteServiceProvider).addNote(
                                  uid,
                                  NoteModel(
                                    id: '',
                                    title: title.isNotEmpty ? title : selectedCategory,
                                    content: body,
                                    createdAt: DateTime.now(),
                                    updatedAt: DateTime.now(),
                                    tags: tags,
                                  ),
                                );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  child: Text(
                    isSaving ? 'Saving...' : 'Save Entry',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
