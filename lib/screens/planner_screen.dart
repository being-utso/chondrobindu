import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/theme/app_colors.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../models/exam_model.dart';
import '../models/routine_models.dart';
import '../models/routine_slot_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../utils/safe_haptics.dart';
import '../widgets/assessment_card.dart';
import 'journal_screen.dart' show holidaySettingsStreamProvider;
import 'routine_screen.dart';

enum _PlannerViewTab { agenda, attendanceLedger }

enum _MobilePlannerView { agenda, weekGrid, calendar, attendanceLedger }

enum _AcademicTrack { university, collegeHsc, admission }

typedef _AssessmentTypeOption = ({String label, String value});

/// Screen 04: Academic Planner & Routine Workspace (Stitch Design System)
/// 1:1 Strict Reference Implementation of academic_planner_routine_desktop_web_dark_mode
/// and academic_planner_routine_mobile_dark_mode from _design_reference.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  _PlannerViewTab _currentTab = _PlannerViewTab.agenda;
  _MobilePlannerView _mobileView = _MobilePlannerView.agenda;

  static _AcademicTrack _resolveAcademicTrack(UserProfile profile) {
    if (profile.isUniversityStudent) {
      return _AcademicTrack.university;
    }
    final target = profile.primaryTarget.toLowerCase().trim();
    if (target.contains('hsc') ||
        target.contains('board') ||
        target == 'undergraduate' ||
        target.isEmpty ||
        (profile.collegeClass?.trim().isNotEmpty ?? false)) {
      return _AcademicTrack.collegeHsc;
    }
    if (profile.isAdmissionCandidate ||
        target.contains('engineering') ||
        target.contains('medical') ||
        target.contains('varsity') ||
        target.contains('admission') ||
        target.contains('buet') ||
        target.contains('ckruet')) {
      return _AcademicTrack.admission;
    }
    return _AcademicTrack.collegeHsc;
  }

  static String _buildProfilePeriodLabel(UserProfile profile) {
    final track = _resolveAcademicTrack(profile);
    switch (track) {
      case _AcademicTrack.university:
        final lvl = profile.level?.trim() ?? '';
        final trm = profile.term?.trim() ?? '';
        final hasLvl = lvl.isNotEmpty;
        final hasTrm = trm.isNotEmpty;
        final lvlLabel = hasLvl
            ? (lvl.toLowerCase().contains('level') ? lvl : 'Level $lvl')
            : '';
        final trmLabel = hasTrm
            ? (trm.toLowerCase().contains('term') ||
                    trm.toLowerCase().contains('semester') ||
                    trm.toLowerCase().contains('fall') ||
                    trm.toLowerCase().contains('spring') ||
                    trm.toLowerCase().contains('summer')
                ? trm
                : 'Term $trm')
            : '';
        if (hasLvl && hasTrm) return '$lvlLabel • $trmLabel';
        if (hasTrm) return trmLabel;
        if (hasLvl) return lvlLabel;
        return 'Current Semester';
      case _AcademicTrack.collegeHsc:
        final cls = profile.collegeClass?.trim() ?? '';
        final b = profile.hscBatch.trim().isNotEmpty
            ? profile.hscBatch.trim()
            : profile.batch.trim();
        final hscLabel = b.isEmpty
            ? ''
            : (b.toUpperCase().contains('HSC') ? b : 'HSC $b');
        if (cls.isNotEmpty && hscLabel.isNotEmpty) return '$cls • $hscLabel';
        if (hscLabel.isNotEmpty) return hscLabel;
        if (cls.isNotEmpty) return cls;
        return 'HSC Academic Year';
      case _AcademicTrack.admission:
        final rawTarget = profile.primaryTarget.trim();
        if (rawTarget.isEmpty) return 'Admission Track';
        final lower = rawTarget.toLowerCase();
        if (lower.contains('track')) return rawTarget;
        if (lower.startsWith('engineering')) return 'Engineering Track';
        if (lower.startsWith('medical')) return 'Medical Track';
        if (lower.startsWith('varsity')) return 'Varsity Track';
        return '$rawTarget Track';
    }
  }

  static String? _computeWeekLabel(HolidaySettings holidaySettings, DateTime referenceDate) {
    final start = holidaySettings.semesterStart;
    if (start == null) return null;
    final startDay = DateTime(start.year, start.month, start.day);
    final refDay = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);
    final diffDays = refDay.difference(startDay).inDays;
    if (diffDays < 0) return null;
    final weekNum = (diffDays ~/ 7) + 1;
    return 'WEEK ${weekNum.toString().padLeft(2, '0')}';
  }

  static List<_AssessmentTypeOption> _getAssessmentTypeOptions(
    _AcademicTrack track,
    Course? course,
  ) {
    switch (track) {
      case _AcademicTrack.university:
        if (course != null && course.isSessional) {
          return const [
            (label: 'Lab Quiz', value: 'lab_quiz'),
            (label: 'Lab Report / Assignment', value: 'lab_report'),
            (label: 'Project / Model Defense', value: 'project'),
            (label: 'Lab Final / Viva Voce', value: 'lab_final'),
            (label: 'Continuous Assessment', value: 'performance'),
          ];
        }
        return const [
          (label: 'Class Test (CT)', value: 'CT'),
          (label: 'Quiz', value: 'quiz'),
          (label: 'Mid-Term Exam', value: 'midterm'),
          (label: 'Term Final Exam', value: 'final'),
          (label: 'Assignment / Presentation', value: 'assignment'),
        ];
      case _AcademicTrack.collegeHsc:
        return const [
          (label: 'Class Test', value: 'CT'),
          (label: 'Monthly Exam', value: 'monthly_exam'),
          (label: 'Half Yearly', value: 'half_yearly'),
          (label: 'Year End', value: 'year_end'),
          (label: 'Pretest', value: 'pretest'),
          (label: 'Test Exam', value: 'test_exam'),
          (label: 'Practical Exam', value: 'practical_exam'),
        ];
      case _AcademicTrack.admission:
        return const [
          (label: 'Weekly Exam', value: 'weekly_exam'),
          (label: 'Monthly Exam', value: 'monthly_exam'),
          (label: 'Paper Final', value: 'paper_final'),
          (label: 'Subject Final', value: 'subject_final'),
          (label: 'Model Test', value: 'model_test'),
        ];
    }
  }

  static String getWeekdayShort(int day) => switch (day) {
        DateTime.saturday => 'Sat',
        DateTime.sunday => 'Sun',
        DateTime.monday => 'Mon',
        DateTime.tuesday => 'Tue',
        DateTime.wednesday => 'Wed',
        DateTime.thursday => 'Thu',
        DateTime.friday => 'Fri',
        _ => 'Day',
      };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 900;
    final userProfile = ref.watch(userProfileProvider);

    final assessmentsAsync = ref.watch(allAssessmentsStreamProvider);
    final allAssessments = assessmentsAsync.valueOrNull ?? [];

    final routineAsync = ref.watch(weeklyRoutineStreamProvider);
    final allSlots = routineAsync.valueOrNull ?? [];

    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = coursesAsync.valueOrNull ?? [];

    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.valueOrNull ?? [];

    final holidaySettingsAsync = ref.watch(holidaySettingsStreamProvider);
    final holidaySettings = holidaySettingsAsync.valueOrNull ?? HolidaySettings.defaultSettings;

    final attendanceRecordsAsync = ref.watch(attendanceRecordsStreamProvider);
    final allAttendanceRecords = attendanceRecordsAsync.valueOrNull ?? [];

    final Map<String, String> courseCodeMap = {for (final c in courses) c.id: c.code};
    final Map<String, String> courseTitleMap = {for (final c in courses) c.id: c.title};

    // Filter active courses
    final Set<String>? activeCourseIds = courses.isNotEmpty
        ? courses.where((c) => !c.isArchived).map((c) => c.id).toSet()
        : null;

    // Academic calendar status for selected date
    final isHoliday = holidaySettings.isHolidayOrBreak(_selectedDate);
    final isExamPeriod = holidaySettings.isExamPeriod(_selectedDate);
    final isWithinSemester = holidaySettings.isWithinSemester(_selectedDate);
    final isClassSuppressed = !isWithinSemester || isHoliday || isExamPeriod;

    // Assessments for selected day
    final selectedDayAssessments = allAssessments.where((a) {
      final d = a.dueDate ?? a.date;
      if (d == null) return false;
      return d.year == _selectedDate.year &&
          d.month == _selectedDate.month &&
          d.day == _selectedDate.day;
    }).toList();

    // Routine slots for selected day
    final selectedDaySlots = allSlots.where((s) {
      if (s.dayOfWeek != _selectedDate.weekday) return false;
      if (activeCourseIds != null && s.courseId.isNotEmpty && !activeCourseIds.contains(s.courseId)) {
        return false;
      }
      return s.isActiveOnDate(_selectedDate);
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final uid = Firebase.apps.isNotEmpty ? (FirebaseAuth.instance.currentUser?.uid ?? '') : '';

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: isWide
          ? null
          : FloatingActionButton(
              backgroundColor: colors.secondary,
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: () => _showAddPlannerItemDialog(context),
              child: const Icon(Icons.add_rounded, size: 24),
            ),
      body: SafeArea(
        child: isWide
            ? _buildDesktopStudio(
                colors: colors,
                isDark: isDark,
                userProfile: userProfile,
                allAssessments: allAssessments,
                allSlots: allSlots,
                courses: courses,
                allExams: allExams,
                holidaySettings: holidaySettings,
                allAttendanceRecords: allAttendanceRecords,
                activeCourseIds: activeCourseIds,
                selectedDayAssessments: selectedDayAssessments,
                selectedDaySlots: selectedDaySlots,
                courseCodeMap: courseCodeMap,
                courseTitleMap: courseTitleMap,
                isClassSuppressed: isClassSuppressed,
                isHoliday: isHoliday,
                isExamPeriod: isExamPeriod,
                uid: uid,
              )
            : _buildMobilePlanner(
                colors: colors,
                isDark: isDark,
                userProfile: userProfile,
                allAssessments: allAssessments,
                allSlots: allSlots,
                courses: courses,
                allExams: allExams,
                holidaySettings: holidaySettings,
                allAttendanceRecords: allAttendanceRecords,
                activeCourseIds: activeCourseIds,
                selectedDayAssessments: selectedDayAssessments,
                selectedDaySlots: selectedDaySlots,
                courseCodeMap: courseCodeMap,
                courseTitleMap: courseTitleMap,
                isClassSuppressed: isClassSuppressed,
                isHoliday: isHoliday,
                isExamPeriod: isExamPeriod,
                uid: uid,
              ),
      ),
    );
  }

  // ===========================================================================
  // 1. DESKTOP / WEB STUDIO DUAL-PANE VIEW (1:1 with _design_reference)
  // ===========================================================================
  Widget _buildDesktopStudio({
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required UserProfile userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required List<ExamModel> allExams,
    required HolidaySettings holidaySettings,
    required List<AttendanceRecord> allAttendanceRecords,
    required Set<String>? activeCourseIds,
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required bool isClassSuppressed,
    required bool isHoliday,
    required bool isExamPeriod,
    required String uid,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1360),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -------------------------------------------------------------
              // LEFT COLUMN (~45% width): Academic Timetable Calendar & Cards
              // -------------------------------------------------------------
              SizedBox(
                width: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Main Academic Timetable Monthly Card
                    _buildCalendarCard(
                      userProfile: userProfile,
                      allAssessments: allAssessments,
                      allSlots: allSlots,
                      holidaySettings: holidaySettings,
                      activeCourseIds: activeCourseIds,
                      colors: colors,
                      isDark: isDark,
                    ),

                    const SizedBox(height: 16),

                    // Upcoming Milestone Focus Card (e.g. Mid-Term Prep in 14 Days)
                    _buildUpcomingMilestoneCard(colors),
                  ],
                ),
              ),

              const SizedBox(width: 24),

              // -------------------------------------------------------------
              // RIGHT COLUMN (~55% width): Day Agenda, Assessments & Routine
              // -------------------------------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Right Header: Date, Active Day View Pill, Switcher, + Schedule
                    _buildRightStudioHeader(
                      selectedDayAssessments: selectedDayAssessments,
                      selectedDaySlots: selectedDaySlots,
                      colors: colors,
                      isDark: isDark,
                    ),

                    const SizedBox(height: 18),

                    // Dynamic Tab Content: Agenda vs Attendance Ledger
                    if (_currentTab == _PlannerViewTab.agenda) ...[
                      // SECTION A: Assessments & Deadlines
                      if (selectedDayAssessments.isNotEmpty) ...[
                        _buildAssessmentsSection(
                          assessments: selectedDayAssessments,
                          courseCodeMap: courseCodeMap,
                          courseTitleMap: courseTitleMap,
                          colors: colors,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // SECTION B: Class Routine
                      _buildClassRoutineSection(
                        slots: selectedDaySlots,
                        courseCodeMap: courseCodeMap,
                        courseTitleMap: courseTitleMap,
                        isClassSuppressed: isClassSuppressed,
                        isHoliday: isHoliday,
                        colors: colors,
                      ),

                      const SizedBox(height: 18),

                      // Bottom Daily Scholar Footnote
                      _buildScholarFootnote(colors),
                    ] else ...[
                      // ATTENDANCE LEDGER VIEW
                      _buildAttendanceLedgerView(
                        courses: courses,
                        allAttendanceRecords: allAttendanceRecords,
                        allSlots: allSlots,
                        holidaySettings: holidaySettings,
                        colors: colors,
                        uid: uid,
                      ),
                    ],
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
  // 2. MOBILE VIEW (1:1 with _design_reference)
  // ===========================================================================
  Widget _buildMobilePlanner({
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required UserProfile userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required List<ExamModel> allExams,
    required HolidaySettings holidaySettings,
    required List<AttendanceRecord> allAttendanceRecords,
    required Set<String>? activeCourseIds,
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required bool isClassSuppressed,
    required bool isHoliday,
    required bool isExamPeriod,
    required String uid,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Mobile Header + Weekly Day Strip + Segmented Switcher (Always visible!)
          _buildMobileHeader(
            userProfile: userProfile,
            allAssessments: allAssessments,
            allSlots: allSlots,
            holidaySettings: holidaySettings,
            activeCourseIds: activeCourseIds,
            selectedDayAssessments: selectedDayAssessments,
            selectedDaySlots: selectedDaySlots,
            colors: colors,
            isDark: isDark,
          ),

          const SizedBox(height: 16),

          if (_mobileView == _MobilePlannerView.agenda) ...[
            // Section A: Assessments & Quizzes
            if (selectedDayAssessments.isNotEmpty) ...[
              _buildAssessmentsSection(
                assessments: selectedDayAssessments,
                courseCodeMap: courseCodeMap,
                courseTitleMap: courseTitleMap,
                colors: colors,
                isMobile: true,
              ),
              const SizedBox(height: 20),
            ],

            // Section B: Class Schedule (or clean empty state inside lower feed)
            _buildClassRoutineSection(
              slots: selectedDaySlots,
              courseCodeMap: courseCodeMap,
              courseTitleMap: courseTitleMap,
              isClassSuppressed: isClassSuppressed,
              isHoliday: isHoliday,
              colors: colors,
              isMobile: true,
            ),

            const SizedBox(height: 18),

            // Scholar's Notebook Quote
            _buildScholarFootnote(colors, isMobile: true),
          ] else if (_mobileView == _MobilePlannerView.weekGrid) ...[
            _buildMobileWeekGridSection(
              allSlots: allSlots,
              activeCourseIds: activeCourseIds,
              courseCodeMap: courseCodeMap,
              courseTitleMap: courseTitleMap,
              colors: colors,
            ),
          ] else if (_mobileView == _MobilePlannerView.calendar) ...[
            // Full Month Calendar View (with exam/holiday dots regardless of routine count)
            _buildCalendarCard(
              userProfile: userProfile,
              allAssessments: allAssessments,
              allSlots: allSlots,
              holidaySettings: holidaySettings,
              activeCourseIds: activeCourseIds,
              colors: colors,
              isDark: isDark,
              isMobile: true,
            ),

            const SizedBox(height: 16),

            if (selectedDayAssessments.isNotEmpty) ...[
              _buildAssessmentsSection(
                assessments: selectedDayAssessments,
                courseCodeMap: courseCodeMap,
                courseTitleMap: courseTitleMap,
                colors: colors,
                isMobile: true,
              ),
              const SizedBox(height: 16),
            ],

            _buildClassRoutineSection(
              slots: selectedDaySlots,
              courseCodeMap: courseCodeMap,
              courseTitleMap: courseTitleMap,
              isClassSuppressed: isClassSuppressed,
              isHoliday: isHoliday,
              colors: colors,
              isMobile: true,
            ),
          ] else ...[
            // Attendance Ledger
            _buildAttendanceLedgerView(
              courses: courses,
              allAttendanceRecords: allAttendanceRecords,
              allSlots: allSlots,
              holidaySettings: holidaySettings,
              colors: colors,
              uid: uid,
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Calendar Card (Stitch Surface #202733, 1px Border #2E3846, 8px Radius)
  // ===========================================================================
  Widget _buildCalendarCard({
    required UserProfile userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required ChondrobinduThemeColors colors,
    required bool isDark,
    bool isMobile = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Overline + Month Title + Navigation Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ACADEMIC TIMETABLE',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.secondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy').format(_focusedMonth),
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // TODAY pill button
                  InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      final now = DateTime.now();
                      setState(() {
                        _selectedDate = now;
                        _focusedMonth = now;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Text(
                        'TODAY',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // < and > Chevrons
                  Container(
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.chevron_left_rounded, color: colors.textPrimary, size: 18),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            SafeHaptics.selectionClick();
                            setState(() {
                              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                            });
                          },
                        ),
                        Container(width: 1, height: 16, color: colors.surfaceBorder),
                        IconButton(
                          icon: Icon(Icons.chevron_right_rounded, color: colors.textPrimary, size: 18),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            SafeHaptics.selectionClick();
                            setState(() {
                              _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Dynamic Profile Term & Week Monospace Capsule Pill
          Builder(
            builder: (_) {
              final periodLabel = _buildProfilePeriodLabel(userProfile);
              final weekLabel = _computeWeekLabel(holidaySettings, _selectedDate);
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.surfaceBorder.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        periodLabel,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (weekLabel != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Text(
                          weekLabel,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // 7-Column Calendar Grid starting with Saturday
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedMonth,
            startingDayOfWeek: StartingDayOfWeek.saturday,
            calendarFormat: CalendarFormat.month,
            headerVisible: false,
            daysOfWeekHeight: 24,
            rowHeight: 40,
            selectedDayPredicate: (day) => isSameDay(day, _selectedDate),
            onDaySelected: (selectedDay, focusedDay) {
              SafeHaptics.selectionClick();
              setState(() {
                _selectedDate = selectedDay;
                _focusedMonth = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedMonth = focusedDay);
            },
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (date, locale) => getWeekdayShort(date.weekday).toUpperCase(),
              weekdayStyle: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              weekendStyle: GoogleFonts.jetBrainsMono(
                color: colors.secondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, date, focusedDay) => _buildCalendarCell(
                date: date,
                isSelected: false,
                isToday: isSameDay(date, DateTime.now()),
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
                isDark: isDark,
              ),
              todayBuilder: (context, date, focusedDay) => _buildCalendarCell(
                date: date,
                isSelected: isSameDay(date, _selectedDate),
                isToday: true,
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
                isDark: isDark,
              ),
              selectedBuilder: (context, date, focusedDay) => _buildCalendarCell(
                date: date,
                isSelected: true,
                isToday: isSameDay(date, DateTime.now()),
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
                isDark: isDark,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 4-Tier Visual Indicators Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CALENDAR CONVENTIONS',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildLegendItem(const Color(0xFF4E9F72), 'Class Routine', colors, isDot: true)),
                    Expanded(child: _buildLegendItem(colors.secondary, 'Exam Window', colors, isBox: true)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: _buildLegendItem(colors.secondary, 'Exam / CT Day', colors, isRing: true)),
                    Expanded(child: _buildLegendItem(const Color(0xFFFF8075), 'Holiday / Break', colors, isDot: true)),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Academic Stats Footer
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Teaching Days: 22',
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
              Text('•', style: GoogleFonts.jetBrainsMono(color: colors.surfaceBorder)),
              Text(
                'Quizzes: 3',
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
              Text('•', style: GoogleFonts.jetBrainsMono(color: colors.surfaceBorder)),
              Text(
                'Lab Finals: 1',
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
              Text('•', style: GoogleFonts.jetBrainsMono(color: colors.surfaceBorder)),
              Text(
                'Breaks: 4d',
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label, ChondrobinduThemeColors colors, {bool isDot = false, bool isRing = false, bool isBox = false}) {
    Widget indicator;
    if (isRing) {
      indicator = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 1.8)),
      );
    } else if (isBox) {
      indicator = Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2)),
      );
    } else {
      indicator = Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        indicator,
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: Calendar Day Cell Builder
  // ===========================================================================
  Widget _buildCalendarCell({
    required DateTime date,
    required bool isSelected,
    required bool isToday,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required ChondrobinduThemeColors colors,
    required bool isDark,
  }) {
    final dayAssessments = allAssessments.where((a) {
      final d = a.dueDate ?? a.date;
      return d != null && d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList();

    final isExamPeriod = holidaySettings.isExamPeriod(date);
    final isHoliday = holidaySettings.isHolidayOrBreak(date);
    final isWithinSemester = holidaySettings.isWithinSemester(date);
    final hasExamDay = dayAssessments.isNotEmpty;

    final hasSlot = (!isHoliday && !isExamPeriod && isWithinSemester) &&
        allSlots.any((s) =>
            s.dayOfWeek == date.weekday &&
            s.isActiveOnDate(date) &&
            (activeCourseIds == null || !s.courseId.isNotEmpty || activeCourseIds.contains(s.courseId)));

    if (isSelected) {
      return Center(
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: colors.primary.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
          child: Center(
            child: Text(
              '${date.day}'.padLeft(2, '0'),
              style: GoogleFonts.jetBrainsMono(
                color: isDark ? const Color(0xFF171C24) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      );
    }

    if (hasExamDay) {
      return Center(
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.secondary, width: 1.8),
          ),
          child: Center(
            child: Text(
              '${date.day}'.padLeft(2, '0'),
              style: GoogleFonts.jetBrainsMono(
                color: colors.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: isExamPeriod
          ? BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}'.padLeft(2, '0'),
              style: GoogleFonts.jetBrainsMono(
                color: isHoliday
                    ? const Color(0xFFFF8075)
                    : (isToday ? colors.primary : colors.textPrimary),
                fontSize: 12,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            if (hasSlot)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF4E9F72),
                  shape: BoxShape.circle,
                ),
              )
            else if (isHoliday)
              Container(
                margin: const EdgeInsets.only(top: 2),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF8075),
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Mid-Term Prep / Upcoming Milestone Card
  // ===========================================================================
  Widget _buildUpcomingMilestoneCard(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.event_note_rounded, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mid-Term Prep in 14 Days',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Recommended focus: Oscillations & Differential Eq.',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.primary,
              side: BorderSide(color: colors.surfaceBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () {
              SafeHaptics.selectionClick();
              ref.read(navigationIndexProvider.notifier).state = 1; // Switch to Courses tab
            },
            child: Text(
              'SYLLABUS',
              style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Right Studio Header (Desktop)
  // ===========================================================================
  Widget _buildRightStudioHeader({
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required ChondrobinduThemeColors colors,
    required bool isDark,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active Day View Capsule Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.secondary.withValues(alpha: 0.4)),
              ),
              child: Text(
                'ACTIVE DAY VIEW • ${selectedDayAssessments.length} Assessments • ${selectedDaySlots.length} Classes',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.secondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Agenda: ${DateFormat('dd MMM (EEEE)').format(_selectedDate)}',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Switcher: [ Agenda ] / [ Attendance Ledger ]
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabPill('Agenda', _PlannerViewTab.agenda, colors),
                  _buildTabPill('Attendance Ledger', _PlannerViewTab.attendanceLedger, colors),
                ],
              ),
            ),

            // + Schedule Button
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showAddPlannerItemDialog(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                '+ Schedule',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: Mobile Header, Weekly Day Strip & Segmented Switcher
  // ===========================================================================
  Widget _buildMobileHeader({
    required UserProfile userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required ChondrobinduThemeColors colors,
    required bool isDark,
  }) {
    final periodLabel = _buildProfilePeriodLabel(userProfile);
    final weekLabel = _computeWeekLabel(holidaySettings, _selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Title + Schedule CTA
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Agenda: ${DateFormat('dd MMM (EEE)').format(_selectedDate)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${selectedDayAssessments.length} ASSESSMENTS • ${selectedDaySlots.length} LECTURES',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.secondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: () => _showAddPlannerItemDialog(context),
              icon: const Icon(Icons.add_rounded, size: 14),
              label: Text('+ SCHEDULE', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Persistent Weekly Day Picker Strip (SAT -> FRI + Today button)
        _buildMobileWeeklyStrip(
          periodLabel: periodLabel,
          weekLabel: weekLabel,
          allAssessments: allAssessments,
          allSlots: allSlots,
          holidaySettings: holidaySettings,
          activeCourseIds: activeCourseIds,
          colors: colors,
          isDark: isDark,
        ),

        const SizedBox(height: 12),

        // Segmented Switcher (Agenda, Week Grid, Calendar, Attendance)
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: [
              Expanded(child: _buildMobileTabPill('Agenda', _MobilePlannerView.agenda, colors)),
              Expanded(child: _buildMobileTabPill('Week Grid', _MobilePlannerView.weekGrid, colors)),
              Expanded(child: _buildMobileTabPill('Calendar', _MobilePlannerView.calendar, colors)),
              Expanded(child: _buildMobileTabPill('Attendance', _MobilePlannerView.attendanceLedger, colors)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileWeeklyStrip({
    required String periodLabel,
    required String? weekLabel,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required ChondrobinduThemeColors colors,
    required bool isDark,
  }) {
    final daysFromSat = switch (_selectedDate.weekday) {
      DateTime.saturday => 0,
      DateTime.sunday => 1,
      _ => _selectedDate.weekday + 1,
    };
    final weekStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    ).subtract(Duration(days: daysFromSat));

    final now = DateTime.now();
    const dayNames = ['SAT', 'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(_selectedDate),
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            periodLabel,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (weekLabel != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• $weekLabel',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      final today = DateTime.now();
                      setState(() {
                        _selectedDate = today;
                        _focusedMonth = today;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Text(
                        'TODAY',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _selectedDate = _selectedDate.subtract(const Duration(days: 7));
                        _focusedMonth = _selectedDate;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.chevron_left_rounded, size: 18, color: colors.textMuted),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _selectedDate = _selectedDate.add(const Duration(days: 7));
                        _focusedMonth = _selectedDate;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.chevron_right_rounded, size: 18, color: colors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(7, (idx) {
              final day = weekStart.add(Duration(days: idx));
              final isSelected = isSameDay(day, _selectedDate);
              final isToday = isSameDay(day, now);
              final isHol = holidaySettings.isHolidayOrBreak(day);

              final hasAssessment = allAssessments.any((a) {
                final d = a.dueDate ?? a.date;
                return d != null && isSameDay(d, day);
              });
              final hasClass = !isHol &&
                  allSlots.any((s) =>
                      (activeCourseIds == null || s.courseId.isEmpty || activeCourseIds.contains(s.courseId)) &&
                      s.isActiveOnDate(day));

              return Expanded(
                child: InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() {
                      _selectedDate = day;
                      _focusedMonth = day;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.primary
                          : (isToday ? colors.recessed : Colors.transparent),
                      borderRadius: BorderRadius.circular(8),
                      border: isToday && !isSelected
                          ? Border.all(color: colors.primary.withValues(alpha: 0.5))
                          : null,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dayNames[idx],
                          style: GoogleFonts.jetBrainsMono(
                            color: isSelected
                                ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                : (day.weekday == DateTime.friday ? colors.secondary : colors.textMuted),
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${day.day}',
                          style: GoogleFonts.jetBrainsMono(
                            color: isSelected
                                ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                : colors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        SizedBox(
                          height: 5,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasAssessment)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                        : colors.secondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasClass)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                        : const Color(0xFF4E9F72),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (isHol)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFFF8075),
                                    shape: BoxShape.circle,
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
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTabPill(String label, _MobilePlannerView tab, ChondrobinduThemeColors colors) {
    final isSelected = _mobileView == tab;
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _mobileView = tab);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: colors.surfaceBorder) : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: isSelected ? colors.textPrimary : colors.textMuted,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileWeekGridSection({
    required List<RoutineSlot> allSlots,
    required Set<String>? activeCourseIds,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required ChondrobinduThemeColors colors,
  }) {
    const weekdayOrder = [
      DateTime.saturday,
      DateTime.sunday,
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ];
    const weekdayNames = {
      DateTime.saturday: 'Saturday',
      DateTime.sunday: 'Sunday',
      DateTime.monday: 'Monday',
      DateTime.tuesday: 'Tuesday',
      DateTime.wednesday: 'Wednesday',
      DateTime.thursday: 'Thursday',
      DateTime.friday: 'Friday',
    };

    final filteredSlots = allSlots.where((s) {
      if (activeCourseIds != null && s.courseId.isNotEmpty && !activeCourseIds.contains(s.courseId)) {
        return false;
      }
      return true;
    }).toList();

    if (filteredSlots.isEmpty) {
      return _buildEmptyRoutineFeedCard(
        message: 'No weekly routine uploaded yet — add a class slot or import your routine.',
        colors: colors,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: weekdayOrder.map((weekday) {
        final daySlots = filteredSlots.where((s) => s.dayOfWeek == weekday).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        if (daySlots.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    weekdayNames[weekday]!.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Divider(color: colors.surfaceBorder, height: 1)),
                  const SizedBox(width: 8),
                  Text(
                    '${daySlots.length} ${daySlots.length == 1 ? 'class' : 'classes'}',
                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...daySlots.map((slot) => _buildRoutineSlotCard(
                    slot,
                    courseCodeMap,
                    courseTitleMap,
                    colors,
                  )),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTabPill(String label, _PlannerViewTab tab, ChondrobinduThemeColors colors, {bool isMobile = false}) {
    final isSelected = _currentTab == tab;
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _currentTab = tab);
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: colors.surfaceBorder) : null,
        ),
        child: Center(
          child: Text(
            label,
            style: isMobile
                ? GoogleFonts.jetBrainsMono(
                    color: isSelected ? colors.textPrimary : colors.textMuted,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  )
                : GoogleFonts.plusJakartaSans(
                    color: isSelected ? colors.textPrimary : colors.textMuted,
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION A: Assessments & Deadlines (2-column on Desktop, vertical on Mobile)
  // ===========================================================================
  Widget _buildAssessmentsSection({
    required List<Assessment> assessments,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required ChondrobinduThemeColors colors,
    bool isMobile = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: colors.secondary),
                const SizedBox(width: 6),
                Text(
                  'Assessments & Deadlines',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${assessments.length}',
                    style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            Text(
              'CRITICAL PATH EVALUATION',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Grid on wide screens, column on mobile
        if (isMobile)
          ...assessments.map((a) {
            final cCode = courseCodeMap[a.courseId] ?? a.courseId;
            final cTitle = courseTitleMap[a.courseId] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: AssessmentCard(
                assessment: a,
                courseCode: cCode,
                courseTitle: cTitle,
                cardColor: colors.surface,
                accentColor: colors.secondary,
                onEditDetails: () => _showEditAssessmentDialog(a),
                onEditMarks: () => _showEditAssessmentDialog(a),
                onAttended: () => _updateAssessmentStatus(a, 'Attended'),
                onMissed: () => _updateAssessmentStatus(a, 'Missed'),
                onDelete: () => _deleteAssessment(a),
              ),
            );
          })
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: assessments.map((a) {
              final cCode = courseCodeMap[a.courseId] ?? a.courseId;
              final cTitle = courseTitleMap[a.courseId] ?? '';
              return SizedBox(
                width: 420,
                child: AssessmentCard(
                  assessment: a,
                  courseCode: cCode,
                  courseTitle: cTitle,
                  cardColor: colors.surface,
                  accentColor: colors.secondary,
                  onEditDetails: () => _showEditAssessmentDialog(a),
                  onEditMarks: () => _showEditAssessmentDialog(a),
                  onAttended: () => _updateAssessmentStatus(a, 'Attended'),
                  onMissed: () => _updateAssessmentStatus(a, 'Missed'),
                  onDelete: () => _deleteAssessment(a),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  // ===========================================================================
  // SECTION B: Class Routine Schedule
  // ===========================================================================
  Widget _buildClassRoutineSection({
    required List<RoutineSlot> slots,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required bool isClassSuppressed,
    required bool isHoliday,
    required ChondrobinduThemeColors colors,
    bool isMobile = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Class Routine',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Regular Scheduled Lectures & Sessionals',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isClassSuppressed) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF8075).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFF8075).withValues(alpha: 0.3)),
                ),
                child: Text(
                  isHoliday ? 'HOLIDAY' : 'EXAM SUPPRESSION ACTIVE',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFFF8075),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        // Auto-suppression Banner (matching screen.png)
        if (isClassSuppressed)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.secondary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined, size: 18, color: colors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      children: [
                        TextSpan(
                          text: 'Auto-suppression active on Exam Windows: ',
                          style: TextStyle(color: colors.secondary, fontWeight: FontWeight.bold),
                        ),
                        TextSpan(
                          text: isHoliday
                              ? 'Regular class lectures are suspended for official holiday.'
                              : 'Morning Theory Lectures suspended for CT & Lab Final Exam protocol.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Routine Slot Cards Stack
        if (slots.isEmpty && !isClassSuppressed)
          _buildEmptyRoutineFeedCard(
            message: 'No classes scheduled for ${DateFormat('EEEE').format(_selectedDate)} — add a class slot or import your routine.',
            colors: colors,
          )
        else
          ...slots.map((slot) => _buildRoutineSlotCard(
                slot,
                courseCodeMap,
                courseTitleMap,
                colors,
                isSuspended: isClassSuppressed,
              )),
      ],
    );
  }

  Widget _buildEmptyRoutineFeedCard({
    required String message,
    required ChondrobinduThemeColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_busy_rounded, size: 28, color: colors.textMuted),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.background == AppColors.darkBackground
                      ? const Color(0xFF171C24)
                      : Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showAddRoutineSlotDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text('Add Class Slot', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12.5)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.secondary,
                  side: BorderSide(color: colors.secondary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoutineScreen()),
                  );
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: Text('Import Routine', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Routine Slot Card (Strict Design Reference)
  // ===========================================================================
  Widget _buildRoutineSlotCard(
    RoutineSlot slot,
    Map<String, String> courseCodeMap,
    Map<String, String> courseTitleMap,
    ChondrobinduThemeColors colors, {
    bool isSuspended = false,
  }) {
    final isLab = slot.slotType == CourseType.sessional || slot.slotType == CourseType.practical;
    final accent = isSuspended
        ? colors.surfaceBorder
        : (isLab ? const Color(0xFF4E9F72) : colors.primary);

    // Calculate duration in minutes if possible
    int durationMinutes = isLab ? 150 : 50;
    try {
      final sParts = slot.startTime.replaceAll(RegExp(r'[^\d:]'), '').split(':');
      final eParts = slot.endTime.replaceAll(RegExp(r'[^\d:]'), '').split(':');
      if (sParts.isNotEmpty && eParts.isNotEmpty) {
        int sH = int.parse(sParts[0]);
        int sM = sParts.length > 1 ? int.parse(sParts[1]) : 0;
        int eH = int.parse(eParts[0]);
        int eM = eParts.length > 1 ? int.parse(eParts[1]) : 0;
        if (slot.startTime.toLowerCase().contains('pm') && sH < 12) sH += 12;
        if (slot.endTime.toLowerCase().contains('pm') && eH < 12) eH += 12;
        final diff = (eH * 60 + eM) - (sH * 60 + sM);
        if (diff > 0 && diff < 360) durationMinutes = diff;
      }
    } catch (_) {}

    final durationLabel = isLab
        ? 'LAB BLOCK ($durationMinutes MIN)'
        : 'PERIOD ($durationMinutes MIN)';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _showSlotDetails(slot),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: isSuspended ? colors.recessed.withValues(alpha: 0.7) : colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Stack(
              children: [
                // 4px Left Accent Stripe
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 4,
                  child: Container(color: accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Time block in JetBrains Mono + Duration caps
                      SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${slot.startTime} – ${slot.endTime}',
                              style: GoogleFonts.jetBrainsMono(
                                color: isSuspended ? colors.textMuted : colors.textPrimary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                decoration: isSuspended ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              durationLabel,
                              style: GoogleFonts.plusJakartaSans(
                                color: isSuspended
                                    ? colors.textMuted
                                    : (isLab ? const Color(0xFF4E9F72) : colors.textMuted),
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Center Course details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  slot.courseCode,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: isSuspended ? colors.textMuted : accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    decoration: isSuspended ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: (isLab ? const Color(0xFF4E9F72) : colors.primary).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: (isLab ? const Color(0xFF4E9F72) : colors.primary).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    isLab ? 'LAB SESSIONAL' : 'THEORY',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: isLab ? const Color(0xFF4E9F72) : colors.primary,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              slot.courseTitle.isNotEmpty ? slot.courseTitle : slot.courseCode,
                              style: GoogleFonts.plusJakartaSans(
                                color: isSuspended ? colors.textMuted : colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: isSuspended ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (slot.room.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: colors.recessed,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: colors.surfaceBorder),
                                    ),
                                    child: Text(
                                      slot.room.toUpperCase().contains('RM') ? slot.room : 'RM ${slot.room}',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: colors.textMuted,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty)
                                  Flexible(
                                    child: Text(
                                      slot.teacherBadge!,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textMuted,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Right Action Icon Button
                      IconButton(
                        icon: Icon(Icons.more_vert_rounded, color: colors.textMuted, size: 18),
                        onPressed: () => _showSlotDetails(slot),
                        tooltip: 'Slot Details',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Daily Scholar Footnote
  // ===========================================================================
  Widget _buildScholarFootnote(ChondrobinduThemeColors colors, {bool isMobile = false}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.format_quote_rounded, size: 20, color: colors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Scholar Footnote',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '"The analytical engine weaves algebraical patterns just as the Jacquard loom weaves flowers and leaves."',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 12),
            Row(
              children: [
                _buildKbdPill('J', 'Next Day', colors),
                const SizedBox(width: 8),
                _buildKbdPill('K', 'Prev Day', colors),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKbdPill(String keyLabel, String actionLabel, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Text(
            keyLabel,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(actionLabel, style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10.5)),
      ],
    );
  }

  // ===========================================================================
  // SECTION: Attendance Ledger View (Live Data + Interactive Session Log)
  // ===========================================================================
  static String _attendanceDateKey(DateTime d) =>
      '${d.year}_${d.month.toString().padLeft(2, '0')}_${d.day.toString().padLeft(2, '0')}';

  static ({int allowedMisses, int neededClasses, String label}) _computeAttendanceBuffer(
    int attended,
    int validTotal,
  ) {
    if (validTotal <= 0) {
      return (
        allowedMisses: 0,
        neededClasses: 0,
        label: 'No recorded sessions yet — tap a course to log attendance.',
      );
    }
    final pct = (attended / validTotal) * 100.0;
    if (pct >= 75.0) {
      final allowed = ((4 * attended - 3 * validTotal) / 3).floor().clamp(0, 999);
      return (
        allowedMisses: allowed,
        neededClasses: 0,
        label: allowed > 0
            ? 'Buffer headroom: +$allowed ${allowed == 1 ? 'class' : 'classes'} allowed before dropping below 75.0%.'
            : 'On threshold: missing the next class drops below 75.0%.',
      );
    }
    final needed = (3 * validTotal - 4 * attended).clamp(1, 999);
    return (
      allowedMisses: 0,
      neededClasses: needed,
      label: 'Deficit alert: attend next $needed ${needed == 1 ? 'class' : 'classes'} consecutively to recover 75.0%.',
    );
  }

  Widget _buildAttendanceLedgerView({
    required List<Course> courses,
    required List<AttendanceRecord> allAttendanceRecords,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required ChondrobinduThemeColors colors,
    required String uid,
  }) {
    final activeCourses = courses.where((c) => !c.isArchived).toList();
    final displayCourses = activeCourses.isNotEmpty ? activeCourses : courses;

    int cumulativeAttended = 0;
    int cumulativeValid = 0;

    final courseEntries = displayCourses.map((course) {
      final records = allAttendanceRecords
          .where((rec) => RoutineCourseSyncService.recordMatchesCourse(
                record: rec,
                courseId: course.id,
                courseCode: course.code,
                courseName: course.title,
              ))
          .toList();

      final stats = RoutineCourseSyncService.computeCourseAttendance(
        courseRecords: records,
        useManualAttendanceOverride: course.useManualAttendanceOverride,
        manualAttendedClasses: course.manualAttendedClasses,
        manualTotalClasses: course.manualTotalClasses,
      );

      final attendedCount = stats.attended + stats.extra;
      final validCount = stats.validClassesCount;
      cumulativeAttended += attendedCount;
      cumulativeValid += validCount;

      return (
        course: course,
        records: records,
        stats: stats,
        attended: attendedCount,
        valid: validCount,
      );
    }).toList();

    final hasCumulativeLogs = cumulativeValid > 0;
    final cumulativePct = hasCumulativeLogs ? (cumulativeAttended / cumulativeValid) * 100.0 : 0.0;
    final cumulativeBuffer = _computeAttendanceBuffer(cumulativeAttended, cumulativeValid);

    final Color dangerColor = colors.background == AppColors.darkBackground
        ? const Color(0xFFFF8075)
        : const Color(0xFFC62828);

    final Color bannerAccent;
    final Color bannerBg;
    final Color bannerText;
    final String statusTag;
    if (!hasCumulativeLogs) {
      bannerAccent = colors.primary;
      bannerBg = colors.recessed;
      bannerText = colors.textMuted;
      statusTag = 'UNRECORDED';
    } else if (cumulativePct >= 75.0) {
      bannerAccent = const Color(0xFF4E9F72);
      bannerBg = const Color(0xFF1D3B2A);
      bannerText = const Color(0xFF85D8A6);
      statusTag = 'SAFE STATUS';
    } else {
      bannerAccent = dangerColor;
      bannerBg = dangerColor.withValues(alpha: 0.14);
      bannerText = dangerColor;
      statusTag = 'AT RISK';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Metric Banner Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: bannerBg,
                  shape: BoxShape.circle,
                  border: Border.all(color: bannerAccent.withValues(alpha: 0.45)),
                ),
                child: Center(
                  child: Text(
                    hasCumulativeLogs ? '${cumulativePct.toStringAsFixed(0)}%' : '--',
                    style: GoogleFonts.plusJakartaSans(
                      color: hasCumulativeLogs ? bannerText : colors.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'CUMULATIVE ATTENDANCE',
                          style: GoogleFonts.plusJakartaSans(
                            color: bannerAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: bannerBg,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: bannerAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            statusTag,
                            style: GoogleFonts.jetBrainsMono(
                              color: hasCumulativeLogs ? bannerText : colors.textMuted,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasCumulativeLogs
                          ? '$cumulativeAttended of $cumulativeValid Academic Sessions Attended'
                          : '0 of 0 Academic Sessions Logged',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cumulativeBuffer.label,
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        if (courseEntries.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Center(
              child: Text(
                'No active courses found. Add a course to begin tracking attendance.',
                style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final double cardWidth = constraints.maxWidth >= 780
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: courseEntries.map((entry) {
                  final course = entry.course;
                  final hasLogs = entry.valid > 0;
                  final double pct = hasLogs ? entry.stats.percentage : 0.0;
                  final bool isCourseSafe = !hasLogs || pct >= 75.0;
                  final Color statusColor = !hasLogs
                      ? colors.textMuted
                      : (isCourseSafe ? const Color(0xFF4E9F72) : dangerColor);
                  final buffer = _computeAttendanceBuffer(entry.attended, entry.valid);
                  final String bufferShort = !hasLogs
                      ? 'Tap to log'
                      : (pct >= 75.0
                          ? '+${buffer.allowedMisses} buffer'
                          : 'Need +${buffer.neededClasses}');

                  return SizedBox(
                    width: cardWidth,
                    child: Material(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _showCourseAttendanceSheet(
                          course: course,
                          initialRecords: entry.records,
                          allSlots: allSlots,
                          holidaySettings: holidaySettings,
                          uid: uid,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.recessed,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: colors.surfaceBorder),
                                    ),
                                    child: Text(
                                      course.code,
                                      style: GoogleFonts.jetBrainsMono(
                                        color: colors.primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      course.title,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    hasLogs ? '${pct.toStringAsFixed(0)}%' : '--',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: statusColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: hasLogs ? (pct / 100.0).clamp(0.0, 1.0) : 0.0,
                                  minHeight: 5,
                                  backgroundColor: colors.recessed,
                                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    hasLogs
                                        ? 'Attended: ${entry.attended} / ${entry.valid}'
                                        : 'Attended: 0 / 0',
                                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Min Req: 75% • $bufferShort',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: hasLogs && !isCourseSafe ? dangerColor : colors.textMuted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.chevron_right_rounded, size: 15, color: colors.textMuted),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  Future<void> _persistCourseAttendanceRecord({
    required String uid,
    required Course course,
    required DateTime date,
    required AttendanceStatus newStatus,
    RoutineSlot? slot,
  }) async {
    final dateKey = _attendanceDateKey(date);
    final routineKey = slot?.id ?? 'extra';
    final docId = '${course.id}_${routineKey}_$dateKey';

    if (Firebase.apps.isEmpty || uid.isEmpty) return;

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attendance_records')
        .doc(docId);

    try {
      if (newStatus == AttendanceStatus.unmarked) {
        await docRef.delete();
        return;
      }
      final record = AttendanceRecord(
        id: docId,
        courseId: course.id,
        courseCode: course.code,
        courseName: course.title,
        date: DateTime(date.year, date.month, date.day),
        status: newStatus,
        routineId: slot?.id,
        time: slot?.startTime,
      );
      await docRef.set(record.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving attendance record: $e');
    }
  }

  void _showCourseAttendanceSheet({
    required Course course,
    required List<AttendanceRecord> initialRecords,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required String uid,
  }) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final Color dangerColor = colors.background == AppColors.darkBackground
        ? const Color(0xFFFF8075)
        : const Color(0xFFC62828);
    final courseSlots = allSlots.where((s) {
      if (s.courseId.isNotEmpty && s.courseId == course.id) return true;
      return s.courseCode.trim().toLowerCase() == course.code.trim().toLowerCase() &&
          course.code.trim().isNotEmpty;
    }).toList();

    final List<AttendanceRecord> workingRecords = List<AttendanceRecord>.from(initialRecords);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final stats = RoutineCourseSyncService.computeCourseAttendance(
            courseRecords: workingRecords,
            useManualAttendanceOverride: course.useManualAttendanceOverride,
            manualAttendedClasses: course.manualAttendedClasses,
            manualTotalClasses: course.manualTotalClasses,
          );
          final attendedCount = stats.attended + stats.extra;
          final validCount = stats.validClassesCount;
          final hasLogs = validCount > 0;
          final pct = hasLogs ? stats.percentage : 0.0;
          final isSafe = !hasLogs || pct >= 75.0;
          final buffer = _computeAttendanceBuffer(attendedCount, validCount);

          // Build session list: scheduled routine dates up to today + existing recorded dates
          final today = DateTime.now();
          final todayDate = DateTime(today.year, today.month, today.day);
          final rawStart = holidaySettings.semesterStart ?? todayDate.subtract(const Duration(days: 90));
          final minAllowedStart = todayDate.subtract(const Duration(days: 180));
          final effectiveStart = rawStart.isBefore(minAllowedStart) ? minAllowedStart : rawStart;

          final Map<String, ({DateTime date, RoutineSlot? slot, AttendanceRecord? record})> sessionMap = {};

          // 1. Scheduled routine occurrences up to today
          DateTime cursor = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
          while (!cursor.isAfter(todayDate)) {
            final dKey = _attendanceDateKey(cursor);
            for (final s in courseSlots) {
              if (s.isActiveOnDate(cursor)) {
                final sessionKey = '${dKey}_${s.id}';
                sessionMap[sessionKey] = (date: cursor, slot: s, record: null);
              }
            }
            cursor = cursor.add(const Duration(days: 1));
          }

          // 2. Merge existing attendance records into scheduled sessions or extra entries
          for (final rec in workingRecords) {
            final dKey = _attendanceDateKey(rec.date);
            final rKey = rec.routineId ?? 'extra';
            final exactKey = '${dKey}_$rKey';
            if (sessionMap.containsKey(exactKey)) {
              final existing = sessionMap[exactKey]!;
              sessionMap[exactKey] = (date: existing.date, slot: existing.slot, record: rec);
            } else {
              // Match any slot on that date if routineId was empty
              String? matchedKey;
              for (final entry in sessionMap.entries) {
                if (entry.key.startsWith('${dKey}_') && entry.value.record == null) {
                  matchedKey = entry.key;
                  break;
                }
              }
              if (matchedKey != null) {
                final existing = sessionMap[matchedKey]!;
                sessionMap[matchedKey] = (date: existing.date, slot: existing.slot, record: rec);
              } else {
                sessionMap['${dKey}_${rec.id}'] = (
                  date: DateTime(rec.date.year, rec.date.month, rec.date.day),
                  slot: null,
                  record: rec,
                );
              }
            }
          }

          final sessions = sessionMap.values.toList()
            ..sort((a, b) => b.date.compareTo(a.date));

          Future<void> setStatus(DateTime date, RoutineSlot? slot, AttendanceRecord? existingRec, AttendanceStatus newStatus) async {
            SafeHaptics.selectionClick();
            final dateKey = _attendanceDateKey(date);
            final routineKey = slot?.id ?? existingRec?.routineId ?? 'extra';
            final docId = existingRec?.id ?? '${course.id}_${routineKey}_$dateKey';

            setSheetState(() {
              workingRecords.removeWhere((r) => r.id == docId ||
                  (_attendanceDateKey(r.date) == dateKey && (r.routineId ?? 'extra') == routineKey));
              if (newStatus != AttendanceStatus.unmarked) {
                workingRecords.add(
                  AttendanceRecord(
                    id: docId,
                    courseId: course.id,
                    courseCode: course.code,
                    courseName: course.title,
                    date: date,
                    status: newStatus,
                    routineId: slot?.id ?? existingRec?.routineId,
                    time: slot?.startTime ?? existingRec?.time,
                  ),
                );
              }
            });

            await _persistCourseAttendanceRecord(
              uid: uid,
              course: course,
              date: date,
              newStatus: newStatus,
              slot: slot,
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.86,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Text(
                              course.code,
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.primary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attendance History & Session Log',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  course.title,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                          ),
                        ],
                      ),
                    ),

                    // Live Summary Banner
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      hasLogs ? '${pct.toStringAsFixed(1)}%' : '--',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: !hasLogs
                                            ? colors.textPrimary
                                            : (isSafe ? const Color(0xFF4E9F72) : dangerColor),
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '$attendedCount / $validCount Attended • ${stats.canceled} Canceled',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: colors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  buffer.label,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.primary,
                              side: BorderSide(color: colors.surfaceBorder),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: todayDate,
                                firstDate: DateTime(2024),
                                lastDate: todayDate,
                              );
                              if (picked != null) {
                                await setStatus(
                                  DateTime(picked.year, picked.month, picked.day),
                                  null,
                                  null,
                                  AttendanceStatus.attended,
                                );
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: Text('Log Date', style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    Divider(height: 1, color: colors.surfaceBorder),

                    // Session Date Rows
                    Expanded(
                      child: sessions.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No scheduled class sessions found up to today.\nUse "Log Date" above to record an attendance session.',
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: sessions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (_, idx) {
                                final item = sessions[idx];
                                final status = item.record?.status ?? AttendanceStatus.unmarked;
                                final isBreak = holidaySettings.isHolidayOrBreak(item.date);
                                final timeStr = item.slot?.startTime ?? item.record?.time ?? 'Session';

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: colors.recessed,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colors.surfaceBorder),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                DateFormat('EEE, dd MMM yyyy').format(item.date),
                                                style: GoogleFonts.jetBrainsMono(
                                                  color: colors.textPrimary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '• $timeStr',
                                                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                                              ),
                                              if (isBreak) ...[
                                                const SizedBox(width: 6),
                                                Text(
                                                  '(Off-day)',
                                                  style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 10.5),
                                                ),
                                              ],
                                            ],
                                          ),
                                          Text(
                                            status.displayName,
                                            style: GoogleFonts.jetBrainsMono(
                                              color: status == AttendanceStatus.attended || status == AttendanceStatus.extra
                                                  ? const Color(0xFF4E9F72)
                                                  : status == AttendanceStatus.missed
                                                      ? dangerColor
                                                      : colors.textMuted,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _buildAttendanceStatusChip(
                                            label: 'Present',
                                            isSelected: status == AttendanceStatus.attended || status == AttendanceStatus.extra,
                                            activeColor: const Color(0xFF4E9F72),
                                            colors: colors,
                                            onTap: () => setStatus(item.date, item.slot, item.record, AttendanceStatus.attended),
                                          ),
                                          _buildAttendanceStatusChip(
                                            label: 'Absent',
                                            isSelected: status == AttendanceStatus.missed,
                                            activeColor: dangerColor,
                                            colors: colors,
                                            onTap: () => setStatus(item.date, item.slot, item.record, AttendanceStatus.missed),
                                          ),
                                          _buildAttendanceStatusChip(
                                            label: 'Canceled',
                                            isSelected: status == AttendanceStatus.canceled,
                                            activeColor: colors.textMuted,
                                            colors: colors,
                                            onTap: () => setStatus(item.date, item.slot, item.record, AttendanceStatus.canceled),
                                          ),
                                          if (status != AttendanceStatus.unmarked)
                                            _buildAttendanceStatusChip(
                                              label: 'Clear',
                                              isSelected: false,
                                              activeColor: colors.textMuted,
                                              colors: colors,
                                              onTap: () => setStatus(item.date, item.slot, item.record, AttendanceStatus.unmarked),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttendanceStatusChip({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.16) : colors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? activeColor : colors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? activeColor : colors.textMuted,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Dialogs & Configuration Modals (Stitch Dark/Light Tokens)
  // ===========================================================================
  void _showAddPlannerItemDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: colors.surfaceBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Schedule Academic Activity',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select what you would like to schedule',
                style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.surfaceBorder),
                ),
                tileColor: colors.recessed,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.school_rounded, color: colors.primary, size: 20),
                ),
                title: Text('Class Routine Slot', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                subtitle: Text('Regular lecture, tutorial, or lab sessional', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddRoutineSlotDialog(context);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.surfaceBorder),
                ),
                tileColor: colors.recessed,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: colors.secondary.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(Icons.assignment_late_outlined, color: colors.secondary, size: 20),
                ),
                title: Text('Assessment / Exam / CT', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                subtitle: Text('Quiz, class test, midterm, or assignment deadline', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddAssessmentDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddRoutineSlotDialog(BuildContext context, {RoutineSlot? existing}) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty
        ? courses.firstWhere((c) => existing != null && c.id == existing.courseId, orElse: () => courses.first)
        : null;

    int selectedDay = existing?.dayOfWeek ?? _selectedDate.weekday;
    final startCtrl = TextEditingController(text: existing?.startTime ?? '08:00 AM');
    final endCtrl = TextEditingController(text: existing?.endTime ?? '09:30 AM');
    final roomCtrl = TextEditingController(text: existing?.room ?? '');
    final teacherCtrl = TextEditingController(text: existing?.teacherBadge ?? '');
    CourseType selectedType = existing?.slotType ?? CourseType.theory;

    final daysList = [
      {'name': 'Saturday', 'day': 6},
      {'name': 'Sunday', 'day': 7},
      {'name': 'Monday', 'day': 1},
      {'name': 'Tuesday', 'day': 2},
      {'name': 'Wednesday', 'day': 3},
      {'name': 'Thursday', 'day': 4},
      {'name': 'Friday', 'day': 5},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.surfaceBorder),
          ),
          title: Text(
            existing == null ? 'Add Class Routine Slot' : 'Edit Routine Slot',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Course Selector
                  Text('Course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                      child: DropdownButton<Course>(
                        value: selectedCourse,
                        isExpanded: true,
                        dropdownColor: colors.surface,
                        hint: Text('Select course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                        items: courses.map((c) {
                          return DropdownMenuItem<Course>(
                            value: c,
                            child: Text('${c.code} • ${c.title}', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) => setDialogState(() => selectedCourse = val),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Day of Week
                  Text('Day of Week', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                      child: DropdownButton<int>(
                        value: selectedDay,
                        isExpanded: true,
                        dropdownColor: colors.surface,
                        items: daysList.map((d) {
                          return DropdownMenuItem<int>(
                            value: d['day'] as int,
                            child: Text(d['name'] as String, style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedDay = val);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Time Range
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start Time', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextField(
                                controller: startCtrl,
                                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  hintText: '08:00 AM',
                                  hintStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End Time', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextField(
                                controller: endCtrl,
                                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  hintText: '09:30 AM',
                                  hintStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Room & Teacher Initial
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Room No / Lab', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextField(
                                controller: roomCtrl,
                                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  hintText: 'RM 402',
                                  hintStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Teacher Initial', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 48,
                              child: TextField(
                                controller: teacherCtrl,
                                style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  hintText: 'Prof. M. Rahman [MR]',
                                  hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Class Type
                  Text('Class Type', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: Center(child: Text('Theory', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                          selected: selectedType == CourseType.theory,
                          selectedColor: colors.primary,
                          backgroundColor: colors.recessed,
                          labelStyle: TextStyle(
                            color: selectedType == CourseType.theory ? Colors.white : colors.textMuted,
                          ),
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedType = CourseType.theory);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ChoiceChip(
                          label: Center(child: Text('Lab / Sessional', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold))),
                          selected: selectedType == CourseType.sessional,
                          selectedColor: const Color(0xFF4E9F72),
                          backgroundColor: colors.recessed,
                          labelStyle: TextStyle(
                            color: selectedType == CourseType.sessional ? Colors.white : colors.textMuted,
                          ),
                          onSelected: (val) {
                            if (val) setDialogState(() => selectedType = CourseType.sessional);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.secondary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (selectedCourse == null) return;
                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                if (uid.isEmpty) return;

                final slotId = existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
                final newSlot = RoutineSlot(
                  id: slotId,
                  courseId: selectedCourse!.id,
                  courseCode: selectedCourse!.code,
                  courseTitle: selectedCourse!.title,
                  dayOfWeek: selectedDay,
                  startTime: startCtrl.text.trim(),
                  endTime: endCtrl.text.trim(),
                  room: roomCtrl.text.trim(),
                  teacherBadge: teacherCtrl.text.trim().isNotEmpty ? teacherCtrl.text.trim() : null,
                  slotType: selectedType,
                );

                await ref.read(routineRepositoryProvider).addRoutineSlot(uid, newSlot);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(
                existing == null ? 'Save Slot' : 'Update Slot',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAssessmentDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];
    final userProfile = ref.read(userProfileProvider);
    final track = _resolveAcademicTrack(userProfile);

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    final titleCtrl = TextEditingController();
    final marksCtrl = TextEditingController(text: '20');
    final weightCtrl = TextEditingController(text: '10.0');
    DateTime selectedDate = _selectedDate;
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    final initialTypeOptions = _getAssessmentTypeOptions(track, selectedCourse);
    String selectedType = initialTypeOptions.first.value;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final currentTypeOptions = _getAssessmentTypeOptions(track, selectedCourse);
          final effectiveType = currentTypeOptions.any((opt) => opt.value == selectedType)
              ? selectedType
              : currentTypeOptions.first.value;

          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            title: Text(
              'Schedule Assessment / Exam',
              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                        child: DropdownButton<Course>(
                          value: selectedCourse,
                          isExpanded: true,
                          dropdownColor: colors.surface,
                          hint: Text('Select course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                          items: courses.map((c) {
                            return DropdownMenuItem<Course>(
                              value: c,
                              child: Text('${c.code} • ${c.title}', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (val) => setDialogState(() {
                            selectedCourse = val;
                            final nextOptions = _getAssessmentTypeOptions(track, selectedCourse);
                            if (!nextOptions.any((opt) => opt.value == selectedType)) {
                              selectedType = nextOptions.first.value;
                            }
                          }),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Assessment Type', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                        if (track == _AcademicTrack.university && selectedCourse != null)
                          Text(
                            selectedCourse!.isSessional ? 'Lab / Sessional' : 'Theory Course',
                            style: GoogleFonts.jetBrainsMono(
                              color: selectedCourse!.isSessional ? const Color(0xFF4E9F72) : colors.primary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('ass_type_${track.name}_${selectedCourse?.id ?? 'none'}_${selectedCourse?.isSessional ?? false}_$effectiveType'),
                        initialValue: effectiveType,
                        isExpanded: true,
                        dropdownColor: colors.surface,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colors.recessed,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.surfaceBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.primary),
                          ),
                        ),
                        items: currentTypeOptions.map((opt) {
                          return DropdownMenuItem<String>(
                            value: opt.value,
                            child: Text(
                              opt.label,
                              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedType = val);
                        },
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text('Assessment Title / Topic', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 48,
                      child: TextField(
                        controller: titleCtrl,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colors.recessed,
                          isDense: true,
                          hintText: 'e.g. CT 4: System Data Structures',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Marks', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 48,
                                child: TextField(
                                  controller: marksCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: colors.recessed,
                                    isDense: true,
                                    hintText: '20',
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Weightage (%)', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 48,
                                child: TextField(
                                  controller: weightCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: colors.recessed,
                                    isDense: true,
                                    hintText: '10.0',
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Date and Time picker
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.surfaceBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setDialogState(() => selectedDate = picked);
                            },
                            icon: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(DateFormat('dd MMM yyyy').format(selectedDate), style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.textPrimary,
                              side: BorderSide(color: colors.surfaceBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: selectedTime,
                              );
                              if (picked != null) setDialogState(() => selectedTime = picked);
                            },
                            icon: const Icon(Icons.access_time_rounded, size: 16),
                            label: Text(selectedTime.format(context), style: GoogleFonts.jetBrainsMono(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (selectedCourse == null || titleCtrl.text.trim().isEmpty) return;
                  final marks = double.tryParse(marksCtrl.text.trim()) ?? 20.0;
                  final weight = double.tryParse(weightCtrl.text.trim()) ?? 10.0;

                  final scheduledDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  final newAss = Assessment(
                    id: 'ass_${DateTime.now().millisecondsSinceEpoch}',
                    courseId: selectedCourse!.id,
                    courseCode: selectedCourse!.code,
                    name: titleCtrl.text.trim(),
                    type: effectiveType,
                    date: scheduledDateTime,
                    dueDate: scheduledDateTime,
                    totalMarks: marks,
                    weightage: weight,
                    status: 'Pending',
                  );

                  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  if (uid.isNotEmpty) {
                    await ref.read(assessmentRepositoryProvider).createAssessment(uid, newAss);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text('Schedule Assessment', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditAssessmentDialog(Assessment assessment) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final marksCtrl = TextEditingController(text: assessment.obtainedMarks?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Text(assessment.name, style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total: ${assessment.totalMarks} marks • Weightage: ${assessment.weightage}%',
              style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Text('Marks Obtained', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
            const SizedBox(height: 6),
            SizedBox(
              height: 48,
              child: TextField(
                controller: marksCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.recessed,
                  isDense: true,
                  hintText: 'Enter obtained marks',
                  hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
            ),
            onPressed: () async {
              final val = double.tryParse(marksCtrl.text.trim());
              final updated = assessment.copyWith(
                obtainedMarks: val,
                status: val != null ? 'Attended' : assessment.status,
              );
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isNotEmpty) {
                await ref.read(assessmentRepositoryProvider).updateAssessment(uid, updated);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('Save Score', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateAssessmentStatus(Assessment assessment, String status) async {
    SafeHaptics.selectionClick();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    final updated = assessment.copyWith(status: status);
    await ref.read(assessmentRepositoryProvider).updateAssessment(uid, updated);
  }

  Future<void> _deleteAssessment(Assessment assessment) async {
    SafeHaptics.selectionClick();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    await ref.read(assessmentRepositoryProvider).deleteAssessment(uid, assessment.id);
  }

  // ===========================================================================
  // SECTION: Slot Details Modal (Launch Focus Session, Syllabus, Edit, Delete)
  // ===========================================================================
  void _showSlotDetails(RoutineSlot slot) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final isLab = slot.slotType == CourseType.sessional || slot.slotType == CourseType.practical;
    final accent = isLab ? const Color(0xFF4E9F72) : colors.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: colors.surfaceBorder, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Title & Type Badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      isLab ? 'LAB SESSIONAL' : 'THEORY',
                      style: GoogleFonts.jetBrainsMono(color: accent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: colors.textMuted, size: 20),
                    tooltip: 'Edit Slot',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showAddRoutineSlotDialog(context, existing: slot);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF8075), size: 20),
                    tooltip: 'Delete Slot',
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (uid.isNotEmpty) {
                        await ref.read(routineRepositoryProvider).removeRoutineSlot(uid, slot.id);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                slot.courseCode,
                style: GoogleFonts.jetBrainsMono(color: colors.primary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (slot.courseTitle.isNotEmpty)
                Text(
                  slot.courseTitle,
                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                ),

              const SizedBox(height: 16),

              // Meta details container
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 16, color: colors.secondary),
                        const SizedBox(width: 8),
                        Text('Time Window:', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                        const Spacer(),
                        Text(
                          slot.timeRange,
                          style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (slot.room.isNotEmpty) ...[
                      const Divider(height: 14),
                      Row(
                        children: [
                          Icon(Icons.meeting_room_outlined, size: 16, color: colors.primary),
                          const SizedBox(width: 8),
                          Text('Room / Lab Location:', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                          const Spacer(),
                          Text(
                            slot.room,
                            style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                    if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty) ...[
                      const Divider(height: 14),
                      Row(
                        children: [
                          Icon(Icons.person_outline_rounded, size: 16, color: colors.textMuted),
                          const SizedBox(width: 8),
                          Text('Instructor Initial / Sign:', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                          const Spacer(),
                          Text(
                            slot.teacherBadge!,
                            style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.secondary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        ref.read(timerProvider.notifier).changeSubject(
                          slot.courseTitle.isNotEmpty ? slot.courseTitle : slot.courseCode,
                        );
                        ref.read(navigationIndexProvider.notifier).state = 2; // Switch to Timer tab
                      },
                      icon: const Icon(Icons.timer_outlined, size: 18),
                      label: Text(
                        'Launch Focus Session',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      ref.read(navigationIndexProvider.notifier).state = 1; // Switch to Courses tab
                    },
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: Text('Syllabus', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
