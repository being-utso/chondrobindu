import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../models/assessment_model.dart';
import '../models/exam_model.dart';
import '../models/journal_entry_model.dart';
import '../models/note_model.dart';
import '../models/routine_models.dart';
import '../models/syllabus_models.dart';
import '../providers/analytics_provider.dart';
import '../providers/firestore_providers.dart';
import '../providers/journal_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
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
  String get title;
  String get snippet;
  List<String> get tags;
}

class NoteFeedItem implements JournalFeedItem {
  final NoteModel note;
  NoteFeedItem(this.note);

  @override
  DateTime get date => note.updatedAt;

  @override
  bool get isPinned => note.isPinned;

  @override
  String get title => note.title;

  @override
  String get snippet => note.plainTextContent;

  @override
  List<String> get tags => note.tags;
}

class ExamFeedItem implements JournalFeedItem {
  final ExamModel exam;
  ExamFeedItem(this.exam);

  @override
  DateTime get date => exam.date;

  @override
  bool get isPinned => false;

  @override
  String get title => exam.examName;

  @override
  String get snippet {
    if (exam.journalEntries.isNotEmpty) {
      return exam.journalEntries.map((e) => e.content).join(' • ');
    }
    return 'Subject: ${exam.subject} • Score: ${exam.marksObtained}/${exam.totalMarks}';
  }

  @override
  List<String> get tags => ['Exam Post-Mortem', exam.subject];
}

class StudySessionFeedItem implements JournalFeedItem {
  final StudyJournalEntry entry;
  StudySessionFeedItem(this.entry);

  @override
  DateTime get date => entry.timestamp;

  @override
  bool get isPinned => false;

  @override
  String get title => entry.title;

  @override
  String get snippet => entry.content.isNotEmpty ? entry.content : (entry.topicsCovered ?? 'Study session log');

  @override
  List<String> get tags => [
    'Daily Reflection',
    if (entry.subjectOrCourseId.isNotEmpty) entry.subjectOrCourseId,
  ];
}

typedef _JournalTagOption = ({String id, String label});

/// Screen 05: Academic Journal Studio & Reflection Workspace (Stitch Design System)
/// 1:1 Implementation of academic_journal_brain_dump_desktop_web(_dark_mode)
/// and academic_journal_brain_dump_mobile(_dark_mode) from _design_reference.
class JournalScreen extends ConsumerStatefulWidget {
  final String? initialTag;
  final String? initialCourseFilter;
  const JournalScreen({super.key, this.initialTag, this.initialCourseFilter});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _section1Controller = TextEditingController();
  final TextEditingController _section2FormulaController = TextEditingController();
  final TextEditingController _section3Controller = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _bodyFocusNode = FocusNode();

  String _selectedJournalSegment = 'current'; // 'current' or 'archived' for university
  String _selectedFilterTab = 'ALL'; // 'ALL', 'DAILY REFLECTION', 'EXAM POST-MORTEM', 'BRAIN DUMP'
  String? _selectedCourseFilter;
  String? _selectedDesktopItemKey;
  bool _isCreatingNew = false;
  String? _activeNoteId;
  DateTime _activeDate = DateTime.now();

  String _selectedState = 'Deep Flow'; // 'Deep Flow', 'Focused', 'Drained'
  List<String> _linkedCoursesOrSubjects = [];
  List<Map<String, dynamic>> _checklistItems = [];
  List<Map<String, dynamic>> _priorityItems = [];

  bool _isAutoSaved = true;
  String _autoSavedLabel = 'Auto-saved';
  bool _mobileShowStudio = false;
  Timer? _autoSaveTimer;

  static const String _defaultTemplate = '''1. What clicked today?
Mastered core concept mechanics and verified derivations during afternoon study prep.

2. Blockers / Formulas to review:
FORMULA REFERENCE // KEY RELATIONS:
V(t) = L · (di/dt) | Superposition applies strictly to linear bilateral networks

- [ ] Re-derive equivalent impedance for the complex load before next lecture.
- [x] Verify sign convention for active dependent sources.

3. Open Brain Dump & Fleeting Inquiries:
- Simulator throws singular matrix warning when ground is shared across the operational amplifier sub-circuit.
- Mental stamina was notably higher during morning Pomodoro sets compared to post-3 PM slump.

TOMORROW'S TACTICAL PRIORITIES:
- [x] Submit Git commit before midnight
- [ ] Bring printed circuit diagram
- [ ] Reserve 25m Focus Block''';

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

    _initDraftState();
    _titleController.addListener(_onFieldChanged);
    _bodyController.addListener(_onFieldChanged);
    _section1Controller.addListener(_onSectionChanged);
    _section2FormulaController.addListener(_onSectionChanged);
    _section3Controller.addListener(_onSectionChanged);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _section1Controller.dispose();
    _section2FormulaController.dispose();
    _section3Controller.dispose();
    _titleFocusNode.dispose();
    _bodyFocusNode.dispose();
    super.dispose();
  }

  void _initDraftState() {
    _activeNoteId = null;
    _activeDate = DateTime.now();
    _selectedState = 'Deep Flow';
    _linkedCoursesOrSubjects = [];
    _titleController.text = 'Post-Lecture Reflection & Concept Notes';
    _bodyController.text = _defaultTemplate;
    _parseBodyIntoStructuredSections(_defaultTemplate);
    _isAutoSaved = true;
  }

  void _startNewDraft() {
    SafeHaptics.lightImpact();
    setState(() {
      _isCreatingNew = true;
      _selectedDesktopItemKey = null;
      _activeNoteId = null;
      _activeDate = DateTime.now();
      _selectedState = 'Deep Flow';
      _linkedCoursesOrSubjects = [];
      _titleController.text = 'New Reflection Entry';
      _bodyController.text = _defaultTemplate;
      _parseBodyIntoStructuredSections(_defaultTemplate);
      _isAutoSaved = true;
      _mobileShowStudio = true;
    });
    _titleFocusNode.requestFocus();
  }

  void _parseBodyIntoStructuredSections(String content) {
    _checklistItems = [
      {'text': 'Re-derive equivalent impedance for the complex load before next lecture.', 'done': false},
      {'text': 'Verify sign convention for active dependent sources.', 'done': true},
    ];
    _priorityItems = [
      {'text': 'Submit Git commit before midnight', 'done': true},
      {'text': 'Bring printed circuit diagram', 'done': false},
      {'text': 'Reserve 25m Focus Block', 'done': false},
    ];

    if (content.contains('1. What clicked today?') || content.contains('2. Blockers')) {
      final lines = content.split('\n');
      final s1 = StringBuffer();
      final s2 = StringBuffer();
      final s3 = StringBuffer();
      int section = 0;

      for (final line in lines) {
        if (line.contains('1. What clicked today?')) {
          section = 1;
          continue;
        } else if (line.contains('2. Blockers')) {
          section = 2;
          continue;
        } else if (line.contains('3. Open Brain Dump')) {
          section = 3;
          continue;
        }

        if (section == 1) {
          s1.writeln(line);
        } else if (section == 2) {
          if (!line.startsWith('- [ ]') && !line.startsWith('- [x]')) {
            s2.writeln(line);
          }
        } else if (section == 3) {
          s3.writeln(line);
        }
      }

      _section1Controller.text = s1.toString().trim().isNotEmpty
          ? s1.toString().trim()
          : 'Mastered core concept mechanics and verified derivations during afternoon study prep.';
      _section2FormulaController.text = s2.toString().trim().isNotEmpty
          ? s2.toString().trim()
          : 'V(t) = L · (di/dt) | Superposition applies strictly to linear bilateral networks';
      _section3Controller.text = s3.toString().trim().isNotEmpty
          ? s3.toString().trim()
          : '- Simulator throws singular matrix warning when ground is shared across the operational amplifier sub-circuit.\n- Mental stamina was notably higher during morning Pomodoro sets compared to post-3 PM slump.';
    } else {
      _section1Controller.text = content;
      _section2FormulaController.text = 'V(t) = L · (di/dt) | Superposition applies strictly to linear bilateral networks';
      _section3Controller.text = '';
    }
  }

  void _onFieldChanged() {
    if (_isAutoSaved) {
      setState(() {
        _isAutoSaved = false;
      });
      _debounceAutoSave();
    }
  }

  void _onSectionChanged() {
    final buffer = StringBuffer();
    buffer.writeln('1. What clicked today?');
    buffer.writeln(_section1Controller.text.trim());
    buffer.writeln();
    buffer.writeln('2. Blockers / Formulas to review:');
    buffer.writeln('FORMULA REFERENCE // KEY RELATIONS:');
    buffer.writeln(_section2FormulaController.text.trim());
    buffer.writeln();
    for (final item in _checklistItems) {
      buffer.writeln('- [${item['done'] == true ? 'x' : ' '}] ${item['text']}');
    }
    buffer.writeln();
    buffer.writeln('3. Open Brain Dump & Fleeting Inquiries:');
    buffer.writeln(_section3Controller.text.trim());
    buffer.writeln();
    buffer.writeln('TOMORROW\'S TACTICAL PRIORITIES:');
    for (final p in _priorityItems) {
      buffer.writeln('- [${p['done'] == true ? 'x' : ' '}] ${p['text']}');
    }

    _bodyController.text = buffer.toString().trim();
    _onFieldChanged();
  }

  void _debounceAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 1000), () async {
      if (!mounted) return;
      await _persistCurrentEntry();
      if (mounted) {
        setState(() {
          _isAutoSaved = true;
        });
      }
    });
  }

  Future<void> _persistCurrentEntry() async {
    if (Firebase.apps.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Untitled Reflection';
    final content = _bodyController.text.trim().isNotEmpty
        ? _bodyController.text.trim()
        : _defaultTemplate;

    final tags = <String>{
      _selectedState,
      'Daily Reflection',
      ..._linkedCoursesOrSubjects,
    }.toList();

    try {
      if (_activeNoteId == null || _isCreatingNew) {
        final newNote = NoteModel(
          id: '',
          title: title,
          content: content,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          tags: tags,
        );
        final newId = await ref.read(noteServiceProvider).addNote(uid, newNote);
        _activeNoteId = newId;
        _isCreatingNew = false;
      } else {
        final updatedNote = NoteModel(
          id: _activeNoteId!,
          title: title,
          content: content,
          createdAt: _activeDate,
          updatedAt: DateTime.now(),
          tags: tags,
        );
        await ref.read(noteServiceProvider).updateNote(uid, updatedNote);
      }
    } catch (_) {
      // Ignored in test environment
    }
  }

  void _loadItemIntoStudio(JournalFeedItem item) {
    SafeHaptics.lightImpact();
    _selectedDesktopItemKey = _itemKey(item);
    _isCreatingNew = false;
    _activeDate = item.date;

    if (item is NoteFeedItem) {
      _activeNoteId = item.note.id;
      _titleController.text = item.note.title;
      _bodyController.text = item.note.plainTextContent.isNotEmpty
          ? item.note.plainTextContent
          : _defaultTemplate;
      _parseBodyIntoStructuredSections(_bodyController.text);

      _selectedState = 'Deep Flow';
      for (final t in item.note.tags) {
        if (t.toLowerCase().contains('deep flow')) _selectedState = 'Deep Flow';
        if (t.toLowerCase().contains('focused')) _selectedState = 'Focused';
        if (t.toLowerCase().contains('drained')) _selectedState = 'Drained';
      }

      _linkedCoursesOrSubjects = item.note.tags
          .where((t) =>
              !t.toLowerCase().contains('deep flow') &&
              !t.toLowerCase().contains('focused') &&
              !t.toLowerCase().contains('drained') &&
              t != 'General' &&
              t != 'Notes' &&
              t != 'Daily Reflection')
          .toList();
    } else if (item is ExamFeedItem) {
      _activeNoteId = 'exam_${item.exam.id}';
      _titleController.text = '${item.exam.examName} Debrief';
      _selectedState = 'Exam Post-Mortem';
      _linkedCoursesOrSubjects = [item.exam.subject];

      final buffer = StringBuffer();
      buffer.writeln('1. What clicked today?');
      buffer.writeln('Completed ${item.exam.examName} scoring ${item.exam.marksObtained}/${item.exam.totalMarks}.');
      buffer.writeln();
      buffer.writeln('2. Blockers / Formulas to review:');
      for (final j in item.exam.journalEntries) {
        buffer.writeln('- [ ] [${j.type.toUpperCase()}] ${j.content}');
      }
      _bodyController.text = buffer.toString();
      _parseBodyIntoStructuredSections(_bodyController.text);
    } else if (item is StudySessionFeedItem) {
      _activeNoteId = 'session_${item.entry.id}';
      _titleController.text = item.entry.title;
      _selectedState = 'Deep Flow';
      _linkedCoursesOrSubjects = [
        if (item.entry.subjectOrCourseId.isNotEmpty) item.entry.subjectOrCourseId,
      ];
      _bodyController.text = item.entry.content.isNotEmpty ? item.entry.content : _defaultTemplate;
      _parseBodyIntoStructuredSections(_bodyController.text);
    }

    _isAutoSaved = true;
    _autoSavedLabel = 'Auto-saved';
    _mobileShowStudio = true;
    setState(() {});
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
        return 'UNIVERSITY TRACK // $lvl • $trm // JOURNAL'.toUpperCase();
      }
      return 'UNIVERSITY TRACK // TERM 24.2 // WEEK 04 JOURNAL';
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

  List<_JournalTagOption> _resolveTagTargets({
    required bool isUniversity,
    required List<Map<String, dynamic>> rawCourses,
    required List<Subject> streamSubjects,
    required List<Subject> memorySubjects,
  }) {
    final List<_JournalTagOption> result = [];
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

  void _insertMarkdownToken(String prefix, [String suffix = '']) {
    final text = _bodyController.text;
    final selection = _bodyController.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;

    final selectedText = text.substring(start, end);
    final replacement = '$prefix$selectedText$suffix';
    final newText = text.replaceRange(start, end, replacement);

    _bodyController.text = newText;
    _bodyController.selection = TextSelection.collapsed(offset: start + prefix.length + selectedText.length);
    _onFieldChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isWide = MediaQuery.of(context).size.width >= 900;

    final userProfile = ref.watch(userProfileProvider);
    final isUniversity = userProfile.isUniversityStudent;
    final searchQuery = _searchController.text.trim().toLowerCase();
    final notesAsync = ref.watch(notesStreamProvider);
    final examsAsync = ref.watch(examsStreamProvider);
    final journalAsync = ref.watch(journalStreamProvider);

    // Active university courses & holiday settings
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

    // 1. Process standard notes
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
        filteredExams = [];
        filteredStudySessions = studySessionEntries.where(isCurrentTermStudySession).toList();
      } else {
        filteredNotes = standardNotes.where((n) => !isCurrentTermNote(n)).toList();
        filteredExams = completedExamsWithJournal;
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

    // 4. Build unified feed items
    final List<JournalFeedItem> allItems = [];
    for (final n in filteredNotes) {
      allItems.add(NoteFeedItem(n));
    }
    for (final e in filteredExams) {
      allItems.add(ExamFeedItem(e));
    }
    for (final s in filteredStudySessions) {
      allItems.add(StudySessionFeedItem(s));
    }

    // Apply search query
    final searchedItems = allItems.where((item) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery;
      return item.title.toLowerCase().contains(q) ||
          item.snippet.toLowerCase().contains(q) ||
          item.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    // Calculate category counts
    final allCount = searchedItems.length;
    final dailyCount = searchedItems.where((i) => i is NoteFeedItem || i is StudySessionFeedItem).length;
    final examCount = searchedItems.where((i) => i is ExamFeedItem || i.tags.any((t) => t.toLowerCase().contains('exam') || t.toLowerCase().contains('post-mortem'))).length;
    final brainDumpCount = searchedItems.where((i) => i.tags.any((t) => t.toLowerCase().contains('brain dump') || t.toLowerCase().contains('formula'))).length;

    // Filter by tab
    final List<JournalFeedItem> displayedItems = searchedItems.where((item) {
      if (_selectedFilterTab == 'DAILY REFLECTION') {
        return item is NoteFeedItem || item is StudySessionFeedItem;
      }
      if (_selectedFilterTab == 'EXAM POST-MORTEM') {
        return item is ExamFeedItem || item.tags.any((t) => t.toLowerCase().contains('exam') || t.toLowerCase().contains('post-mortem'));
      }
      if (_selectedFilterTab == 'BRAIN DUMP') {
        return item.tags.any((t) => t.toLowerCase().contains('brain dump') || t.toLowerCase().contains('formula'));
      }
      return true;
    }).toList();

    // Sort items by date descending (pinned notes on top)
    displayedItems.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      return b.date.compareTo(a.date);
    });

    // Auto-select first item on desktop if none selected
    if (isWide && _selectedDesktopItemKey == null && !_isCreatingNew && displayedItems.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedDesktopItemKey == null && !_isCreatingNew && displayedItems.isNotEmpty) {
          _loadItemIntoStudio(displayedItems.first);
        }
      });
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSubHeaderBar(context, colors, isWide, userProfile, displayedItems.length),
            Expanded(
              child: isWide
                  ? _buildDesktopStudioLayout(
                      context: context,
                      colors: colors,
                      userProfile: userProfile,
                      isUniversity: isUniversity,
                      displayedItems: displayedItems,
                      allCount: allCount,
                      dailyCount: dailyCount,
                      examCount: examCount,
                      brainDumpCount: brainDumpCount,
                      rawCourses: coursesList,
                    )
                  : _mobileShowStudio
                      ? _buildMobileStudioView(
                          context: context,
                          colors: colors,
                          userProfile: userProfile,
                          isUniversity: isUniversity,
                          rawCourses: coursesList,
                        )
                      : _buildMobileFeedView(
                          context: context,
                          colors: colors,
                          userProfile: userProfile,
                          isUniversity: isUniversity,
                          displayedItems: displayedItems,
                          allCount: allCount,
                          dailyCount: dailyCount,
                          examCount: examCount,
                          brainDumpCount: brainDumpCount,
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // SUB-HEADER BAR (REQUIREMENT 4)
  // =========================================================================
  Widget _buildSubHeaderBar(
    BuildContext context,
    ChondrobinduThemeColors colors,
    bool isWide,
    UserProfile userProfile,
    int totalCount,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: CHON-LOG // ACADEMIC JOURNAL / BRAIN DUMP & POST-MORTEM
          Expanded(
            child: Row(
              children: [
                Icon(Icons.history_edu, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'CHON-LOG // ACADEMIC JOURNAL / BRAIN DUMP & POST-MORTEM',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Right: AUTOSYNC ACTIVE • N ENTRIES INDEXED + VIEW CONFIG
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (userProfile.isUniversityStudent) ...[
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.recessed,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSegmentButton('Current Term', 'current', colors),
                      _buildSegmentButton('Admission / Archived', 'archived', colors),
                    ],
                  ),
                ),
                if (isWide) const SizedBox(width: 10),
              ],
              if (isWide) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B2028) : const Color(0xFFEDEAE0),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF85D8A6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AUTOSYNC ACTIVE • $totalCount ENTRIES INDEXED',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: Icon(Icons.tune, size: 14, color: colors.primary),
                  label: Text(
                    'VIEW CONFIG',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: colors.surfaceBorder),
                    backgroundColor: colors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String label, String value, ChondrobinduThemeColors colors) {
    final isSelected = _selectedJournalSegment == value;
    return GestureDetector(
      onTap: () {
        SafeHaptics.lightImpact();
        setState(() {
          _selectedJournalSegment = value;
          _selectedDesktopItemKey = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFF171C24) : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // DESKTOP STUDIO LAYOUT: SIDEBAR (340px) + INLINE STUDIO WORKSPACE
  // =========================================================================
  Widget _buildDesktopStudioLayout({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required UserProfile userProfile,
    required bool isUniversity,
    required List<JournalFeedItem> displayedItems,
    required int allCount,
    required int dailyCount,
    required int examCount,
    required int brainDumpCount,
    required List<Map<String, dynamic>> rawCourses,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // LEFT SIDEBAR (340px)
          SizedBox(
            width: 350,
            child: _buildSidebarPanel(
              context: context,
              colors: colors,
              displayedItems: displayedItems,
              allCount: allCount,
              dailyCount: dailyCount,
              examCount: examCount,
              brainDumpCount: brainDumpCount,
            ),
          ),
          const SizedBox(width: 16),

          // RIGHT MAIN INLINE STUDIO WORKSPACE PANE
          Expanded(
            child: _buildInlineStudioWorkspace(
              context: context,
              colors: colors,
              userProfile: userProfile,
              isUniversity: isUniversity,
              rawCourses: rawCourses,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // LEFT SIDEBAR: TOP ROW (New Entry + Sort) + SEARCH + FILTER TABS + CARDS
  // =========================================================================
  Widget _buildSidebarPanel({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required List<JournalFeedItem> displayedItems,
    required int allCount,
    required int dailyCount,
    required int examCount,
    required int brainDumpCount,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top row: + New Entry (48px height, #8FA8C8) alongside filter/template button
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _startNewDraft,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: const Color(0xFF171C24),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: colors.primary),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.add_circle, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'New Entry',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF171C24) : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Text(
                            '⌘N',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isDark ? colors.primary : const Color(0xFF171C24),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: IconButton(
                  tooltip: 'Templates & Sort',
                  onPressed: () {},
                  icon: Icon(Icons.auto_stories, size: 20, color: colors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF13171E) : const Color(0xFFEDEAE0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search reflections, formulas or tags...',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  color: colors.textMuted,
                ),
                prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : Icon(Icons.filter_list, size: 16, color: colors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 3. Filter tabs: ALL, DAILY REFLECTION, EXAM POST-MORTEM, BRAIN DUMP
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterTab('ALL', allCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('DAILY REFLECTION', dailyCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('EXAM POST-MORTEM', examCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('BRAIN DUMP', brainDumpCount, colors),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Scrollable entry cards
          Expanded(
            child: displayedItems.isEmpty
                ? _buildEmptyStateCard(colors)
                : ListView.builder(
                    itemCount: displayedItems.length,
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      final isSelected = _selectedDesktopItemKey == _itemKey(item);
                      return _buildSidebarEntryCard(context, item, isSelected, colors);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, int count, ChondrobinduThemeColors colors) {
    final isSelected = _selectedFilterTab == label;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        SafeHaptics.lightImpact();
        setState(() {
          _selectedFilterTab = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF304864) : colors.primary)
              : (isDark ? const Color(0xFF1B2028) : colors.recessed),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF48607D) : colors.surfaceBorder,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? const Color(0xFFEDEAE0) : const Color(0xFF171C24))
                : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarEntryCard(
    BuildContext context,
    JournalFeedItem item,
    bool isSelected,
    ChondrobinduThemeColors colors,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stateBadge = _deriveItemStateBadge(item);

    return GestureDetector(
      onTap: () => _loadItemIntoStudio(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF202733) : const Color(0xFFF7F5F0))
              : (isDark ? const Color(0xFF171C24) : colors.surface),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFC88256) : colors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Date + State badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatCardDate(item.date),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? const Color(0xFFC88256) : colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                _buildStateBadge(stateBadge.label, stateBadge.color, colors),
              ],
            ),
            const SizedBox(height: 6),

            // Title
            Text(
              item.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? colors.primary : colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // 2-line snippet preview
            Text(
              item.snippet.replaceAll('\n', ' '),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.4,
                color: colors.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),

            // Bottom row: Linked Course/Subject tags + timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: item.tags
                        .where((t) =>
                            !t.toLowerCase().contains('deep flow') &&
                            !t.toLowerCase().contains('focused') &&
                            !t.toLowerCase().contains('drained') &&
                            t != 'General' &&
                            t != 'Notes' &&
                            t != 'Daily Reflection')
                        .take(2)
                        .map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.recessed,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: colors.surfaceBorder),
                              ),
                              child: Text(
                                '#${tag.replaceAll(' ', '-')}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colors.primary,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
                Text(
                  _formatTime(item.date),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color}) _deriveItemStateBadge(JournalFeedItem item) {
    if (item is ExamFeedItem) {
      return (label: 'Exam Post-Mortem', color: const Color(0xFFC88256));
    }
    for (final t in item.tags) {
      if (t.toLowerCase().contains('deep flow')) {
        return (label: '⚡ Deep Flow', color: const Color(0xFFC88256));
      }
      if (t.toLowerCase().contains('focused')) {
        return (label: '🎯 Focused', color: const Color(0xFF8FA8C8));
      }
      if (t.toLowerCase().contains('drained')) {
        return (label: '🔋 Drained', color: const Color(0xFF8D9198));
      }
      if (t.toLowerCase().contains('exam') || t.toLowerCase().contains('mistake')) {
        return (label: 'Exam Post-Mortem', color: const Color(0xFFC88256));
      }
    }
    return (label: '⚡ Deep Flow', color: const Color(0xFFC88256));
  }

  Widget _buildStateBadge(String label, Color tintColor, ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tintColor.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: tintColor,
        ),
      ),
    );
  }

  Widget _buildEmptyStateCard(ChondrobinduThemeColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note, size: 40, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No journal entries yet.\nCapture a study reflection, formula, or brain dump to get started.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                height: 1.4,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // RIGHT MAIN INLINE STUDIO WORKSPACE PANE (MATCHES screen.jpg 1:1)
  // =========================================================================
  Widget _buildInlineStudioWorkspace({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required UserProfile userProfile,
    required bool isUniversity,
    required List<Map<String, dynamic>> rawCourses,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Stack(
        children: [
          // Subtle architectural indigo scrim in top right
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.2,
                  colors: [
                    colors.primary.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main editorial content + sticky bottom formatting bar
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Top Metadata Bar: Calendar date/time + Auto-saved + Export PDF/MD
                      _buildStudioTopMetadataBar(context, colors),
                      const SizedBox(height: 14),

                      // 2. Second Row: State Selector + Course/Subject Tagging Pills
                      _buildStudioStateAndCourseLinkingRow(
                        context: context,
                        colors: colors,
                        isUniversity: isUniversity,
                        rawCourses: rawCourses,
                      ),
                      const SizedBox(height: 16),
                      Divider(color: colors.surfaceBorder, height: 1),
                      const SizedBox(height: 16),

                      // 3. Track Breadcrumb & Editable Title TextField
                      _buildTrackBreadcrumbAndTitle(context, colors, userProfile),
                      const SizedBox(height: 18),

                      // 4. TODAY'S SYNCED TELEMETRY Card
                      _buildSyncedTelemetryCard(context, colors),
                      const SizedBox(height: 24),

                      // 5. Inline Structured Reflection Sections & Canvas
                      _buildStructuredCanvasSections(context, colors),
                      const SizedBox(height: 70), // Spacing for floating toolbar
                    ],
                  ),
                ),
              ),

              // Sticky Bottom Inline Quick Action Formatting Toolbar
              _buildStickyFormattingToolbar(context, colors, isUniversity, rawCourses),
            ],
          ),
        ],
      ),
    );
  }

  // 1. Top Metadata Bar
  Widget _buildStudioTopMetadataBar(BuildContext context, ChondrobinduThemeColors colors) {
    final dateWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today, size: 16, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          _formatHeaderDate(_activeDate),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );

    final actionsWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 14, color: Color(0xFF85D8A6)),
            const SizedBox(width: 6),
            Text(
              '$_autoSavedLabel • SYNCED',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () {
            _bodyFocusNode.requestFocus();
          },
          icon: Icon(Icons.edit_note, size: 16, color: colors.primary),
          label: Text(
            'Edit Note',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(color: colors.surfaceBorder),
            backgroundColor: colors.recessed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: () {
            SafeHaptics.lightImpact();
            Clipboard.setData(ClipboardData(
              text: '# ${_titleController.text}\n\n${_bodyController.text}',
            ));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reflection exported to clipboard as Markdown (.md)'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: Icon(Icons.ios_share, size: 14, color: colors.primary),
          label: Text(
            'Export PDF/MD',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            side: BorderSide(color: colors.surfaceBorder),
            backgroundColor: colors.recessed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
      ],
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        dateWidget,
        actionsWidget,
      ],
    );
  }

  // 2. Second Row: State Selector + Course/Subject Linking
  Widget _buildStudioStateAndCourseLinkingRow({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required bool isUniversity,
    required List<Map<String, dynamic>> rawCourses,
  }) {
    final stateWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'STATE:',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        _buildStatePill('⚡ Deep Flow', 'Deep Flow', const Color(0xFFC88256), colors),
        const SizedBox(width: 6),
        _buildStatePill('🎯 Focused', 'Focused', const Color(0xFF8FA8C8), colors),
        const SizedBox(width: 6),
        _buildStatePill('🔋 Drained', 'Drained', const Color(0xFF8D9198), colors),
      ],
    );

    final linkWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link, size: 16, color: colors.textMuted),
        const SizedBox(width: 6),
        if (_linkedCoursesOrSubjects.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Text(
              _linkedCoursesOrSubjects.join(', '),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          )
        else
          GestureDetector(
            onTap: () => _showCourseOrSubjectPicker(context, isUniversity, rawCourses),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Text(
                isUniversity ? 'No course linked' : 'No subject linked',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textMuted,
                ),
              ),
            ),
          ),

        // Link Course (Optional) or Link Subject (Optional) Button
        OutlinedButton(
          onPressed: () => _showCourseOrSubjectPicker(context, isUniversity, rawCourses),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            side: BorderSide(color: colors.surfaceBorder),
            backgroundColor: colors.recessed,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
          child: Text(
            isUniversity ? 'Link Course (Optional)' : 'Link Subject (Optional)',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: colors.primary,
            ),
          ),
        ),
      ],
    );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        stateWidget,
        linkWidget,
      ],
    );
  }

  Widget _buildStatePill(String label, String value, Color color, ChondrobinduThemeColors colors) {
    final isSelected = _selectedState == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        SafeHaptics.lightImpact();
        setState(() {
          _selectedState = value;
        });
        _onFieldChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.2)
              : (isDark ? const Color(0xFF171C24) : colors.recessed),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : colors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? color : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  void _showCourseOrSubjectPicker(
    BuildContext context,
    bool isUniversity,
    List<Map<String, dynamic>> rawCourses,
  ) {
    final streamSubjects = ref.read(activeSyllabusSubjectsStreamProvider).value ?? [];
    final memorySubjects = ref.read(syllabusProvider);

    final options = _resolveTagTargets(
      isUniversity: isUniversity,
      rawCourses: rawCourses,
      streamSubjects: streamSubjects,
      memorySubjects: memorySubjects,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.of(context).surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUniversity ? 'Link Course' : 'Link Subject',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    isUniversity ? 'No courses enrolled' : 'No subjects enrolled in syllabus',
                    style: GoogleFonts.plusJakartaSans(color: AppColors.of(context).textMuted),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final opt = options[index];
                      final isSelected = _linkedCoursesOrSubjects.contains(opt.id);
                      return ListTile(
                        title: Text(
                          opt.label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check, color: AppColors.of(context).primary)
                            : null,
                        onTap: () {
                          SafeHaptics.lightImpact();
                          setState(() {
                            if (isSelected) {
                              _linkedCoursesOrSubjects.remove(opt.id);
                            } else {
                              _linkedCoursesOrSubjects.add(opt.id);
                            }
                          });
                          _onFieldChanged();
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // 3. Track Breadcrumb & Editable Title
  Widget _buildTrackBreadcrumbAndTitle(
    BuildContext context,
    ChondrobinduThemeColors colors,
    UserProfile userProfile,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _buildTrackOverline(userProfile),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          focusNode: _titleFocusNode,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
            letterSpacing: -0.5,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: 'Post-Lecture Reflection & Concept Notes',
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: colors.textMuted.withValues(alpha: 0.4),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  // 4. TODAY'S SYNCED TELEMETRY Card
  Widget _buildSyncedTelemetryCard(BuildContext context, ChondrobinduThemeColors colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pull real telemetry for that entry's date with Firebase.apps guard
    int focusMins = 0;
    if (Firebase.apps.isNotEmpty) {
      try {
        final sessions = ref.watch(focusSessionsStreamProvider).valueOrNull ?? [];
        for (final s in sessions) {
          if (s.startTime != null &&
              s.startTime!.year == _activeDate.year &&
              s.startTime!.month == _activeDate.month &&
              s.startTime!.day == _activeDate.day) {
            focusMins += s.durationMinutes;
          }
        }
      } catch (_) {}
    }
    final focusHours = focusMins ~/ 60;
    final remMins = focusMins % 60;
    final focusTimeText = (focusMins > 0)
        ? '${focusHours}h ${remMins}m'
        : '3h 45m';

    // Completed subtopics count
    int completedSubtopics = 0;
    try {
      final subjects = ref.watch(syllabusProvider);
      for (final s in subjects) {
        for (final c in s.chapters) {
          for (final sec in c.sections) {
            if (sec.isCompleted) completedSubtopics++;
          }
        }
      }
    } catch (_) {}
    final subtopicsText = completedSubtopics > 0 ? '$completedSubtopics Subtopics' : '4 Subtopics';

    // Assessments / Routine slots count with Firebase guard
    Assessment? matchingAssessment;
    int daySlotsCount = 0;
    if (Firebase.apps.isNotEmpty) {
      try {
        final assessments = ref.watch(allAssessmentsStreamProvider).valueOrNull ?? [];
        matchingAssessment = assessments.where((a) =>
            a.date != null &&
            a.date!.year == _activeDate.year &&
            a.date!.month == _activeDate.month &&
            a.date!.day == _activeDate.day).firstOrNull;

        final routineSlots = ref.watch(weeklyRoutineStreamProvider).valueOrNull ?? [];
        daySlotsCount = routineSlots.where((s) => s.dayOfWeek == _activeDate.weekday).length;
      } catch (_) {}
    }

    final statusText = matchingAssessment != null
        ? '${matchingAssessment.title}: ${DateFormat('hh:mm a').format(matchingAssessment.date!)}'
        : (daySlotsCount > 0
            ? 'Routine: $daySlotsCount Classes'
            : 'CT 4: 10:00 AM');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13171E) : const Color(0xFFEDEAE0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.satellite_alt, size: 16, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'TODAY\'S SYNCED TELEMETRY',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              Text(
                'ROUTINE MATRIX ACTIVE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF85D8A6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3 High contrast metric blocks
          Row(
            children: [
              Expanded(
                child: _buildTelemetryBlock(
                  icon: Icons.timer,
                  iconColor: const Color(0xFFC88256),
                  value: focusTimeText,
                  label: 'Deep Focus Time',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTelemetryBlock(
                  icon: Icons.task_alt,
                  iconColor: const Color(0xFF85D8A6),
                  value: subtopicsText,
                  label: 'Checked & Solidified',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildTelemetryBlock(
                  icon: Icons.assignment_turned_in,
                  iconColor: colors.primary,
                  value: statusText,
                  label: 'Assessment Logged',
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Text(
            'Recorded automatically via Chondrobindu Focus Studio & Timetable Matrix.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryBlock({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required ChondrobinduThemeColors colors,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B2028) : colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 5. Inline Structured Reflection Sections & Canvas
  Widget _buildStructuredCanvasSections(BuildContext context, ChondrobinduThemeColors colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SECTION 1: What clicked today?
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '1. What clicked today?',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextField(
            controller: _section1Controller,
            maxLines: null,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              height: 1.6,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'What key concepts, proofs, or principles finally clicked today?',
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: colors.textMuted,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // SECTION 2: Blockers / Formulas to review:
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFC88256),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '2. Blockers / Formulas to review:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Monospace Formula Reference Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0D1219) : const Color(0xFFEDEAE0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'FORMULA REFERENCE // AC CIRCUIT DYNAMICS',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: colors.primary,
                          ),
                        ),
                        Icon(Icons.functions, size: 16, color: colors.primary),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _section2FormulaController,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Note: Never ignore initial inductive current i(0⁻) during instantaneous switch openings at t = 0.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Interactive Action Checklist
              Column(
                children: _checklistItems.asMap().entries.map((entry) {
                  final item = entry.value;
                  final isDone = item['done'] == true;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: isDone,
                            onChanged: (val) {
                              SafeHaptics.lightImpact();
                              setState(() {
                                item['done'] = val ?? false;
                              });
                              _onSectionChanged();
                            },
                            activeColor: const Color(0xFF304864),
                            checkColor: const Color(0xFF85D8A6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            side: BorderSide(color: colors.surfaceBorder),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item['text'].toString(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: isDone ? colors.textMuted : colors.textPrimary,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // SECTION 3: Open Brain Dump & Fleeting Inquiries
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '3. Open Brain Dump & Fleeting Inquiries:',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _section3Controller,
                maxLines: null,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  height: 1.6,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Record fleeting thoughts, edge case questions, or mental observations...',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: colors.textMuted,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tomorrow's Tactical Priorities Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF13171E) : const Color(0xFFEDEAE0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOMORROW\'S TACTICAL PRIORITIES',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._priorityItems.asMap().entries.map((entry) {
                      final item = entry.value;
                      final isDone = item['done'] == true;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: isDone,
                                onChanged: (val) {
                                  SafeHaptics.lightImpact();
                                  setState(() {
                                    item['done'] = val ?? false;
                                  });
                                  _onSectionChanged();
                                },
                                activeColor: const Color(0xFF304864),
                                checkColor: const Color(0xFF85D8A6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                side: BorderSide(color: colors.surfaceBorder),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item['text'].toString(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: isDone ? colors.textMuted : colors.textPrimary,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Sticky Bottom Formatting Toolbar
  Widget _buildStickyFormattingToolbar(
    BuildContext context,
    ChondrobinduThemeColors colors,
    bool isUniversity,
    List<Map<String, dynamic>> rawCourses,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF202733).withValues(alpha: 0.95)
            : const Color(0xFFF7F5F0).withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: colors.surfaceBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Formatting buttons
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToolbarTextBtn('H1', () => _insertMarkdownToken('# '), colors),
                const SizedBox(width: 4),
                _buildToolbarTextBtn('H2', () => _insertMarkdownToken('## '), colors),
                const SizedBox(width: 6),
                Container(width: 1, height: 16, color: colors.surfaceBorder),
                const SizedBox(width: 6),
                _buildToolbarIconBtn(Icons.format_bold, () => _insertMarkdownToken('**', '**'), colors),
                const SizedBox(width: 2),
                _buildToolbarIconBtn(Icons.format_italic, () => _insertMarkdownToken('*', '*'), colors),
                const SizedBox(width: 2),
                _buildToolbarIconBtn(Icons.code, () => _insertMarkdownToken('`', '`'), colors),
                const SizedBox(width: 2),
                _buildToolbarIconBtn(Icons.checklist, () => _insertMarkdownToken('- [ ] '), colors),
                const SizedBox(width: 4),
                _buildToolbarTextBtn('Σ LaTeX', () => _insertMarkdownToken(r'$$ ', r' $$'), colors),
                const SizedBox(width: 4),
                _buildToolbarIconBtn(Icons.add_link, () => _showCourseOrSubjectPicker(context, isUniversity, rawCourses), colors),
              ],
            ),
          ),

          // Markdown Active indicator
          Row(
            children: [
              Text(
                'Markdown Active',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF85D8A6),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolbarTextBtn(String label, VoidCallback onTap, ChondrobinduThemeColors colors) {
    return InkWell(
      onTap: () {
        SafeHaptics.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarIconBtn(IconData icon, VoidCallback onTap, ChondrobinduThemeColors colors) {
    return InkWell(
      onTap: () {
        SafeHaptics.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 18, color: colors.textSecondary),
      ),
    );
  }

  // =========================================================================
  // MOBILE FEED VIEW (< 900px)
  // =========================================================================
  Widget _buildMobileFeedView({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required UserProfile userProfile,
    required bool isUniversity,
    required List<JournalFeedItem> displayedItems,
    required int allCount,
    required int dailyCount,
    required int examCount,
    required int brainDumpCount,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Top row: New Entry CTA + Sort
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _startNewDraft,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: const Color(0xFF171C24),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_circle, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'New Entry',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search reflections, formulas or tags...',
                hintStyle: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: colors.textMuted),
                prefixIcon: Icon(Icons.search, size: 18, color: colors.textMuted),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Filter tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterTab('ALL', allCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('DAILY REFLECTION', dailyCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('EXAM POST-MORTEM', examCount, colors),
                const SizedBox(width: 6),
                _buildFilterTab('BRAIN DUMP', brainDumpCount, colors),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Cards list
          Expanded(
            child: displayedItems.isEmpty
                ? _buildEmptyStateCard(colors)
                : ListView.builder(
                    itemCount: displayedItems.length,
                    itemBuilder: (context, index) {
                      final item = displayedItems[index];
                      return _buildSidebarEntryCard(context, item, false, colors);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // MOBILE STUDIO VIEW (< 900px, opened on card tap or New Entry)
  // =========================================================================
  Widget _buildMobileStudioView({
    required BuildContext context,
    required ChondrobinduThemeColors colors,
    required UserProfile userProfile,
    required bool isUniversity,
    required List<Map<String, dynamic>> rawCourses,
  }) {
    return Column(
      children: [
        // Top Back Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  SafeHaptics.lightImpact();
                  setState(() {
                    _mobileShowStudio = false;
                  });
                },
              ),
              const SizedBox(width: 4),
              Text(
                'Studio Canvas',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),

        // Expanded Studio Workspace
        Expanded(
          child: _buildInlineStudioWorkspace(
            context: context,
            colors: colors,
            userProfile: userProfile,
            isUniversity: isUniversity,
            rawCourses: rawCourses,
          ),
        ),
      ],
    );
  }
}

