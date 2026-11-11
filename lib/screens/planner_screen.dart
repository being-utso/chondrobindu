import 'package:firebase_auth/firebase_auth.dart';
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

enum _PlannerDesktopViewMode { timetable, calendar }
enum _PlannerMobileViewMode { agenda, weekGrid, calendar }

/// Screen 04: Academic Planner & Routine Workspace (Stitch Design System)
/// Fully responsive schedule studio: Dual-pane layout on Desktop/Web,
/// chronological agenda & week grid on Mobile.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  _PlannerDesktopViewMode _desktopViewMode = _PlannerDesktopViewMode.timetable;
  _PlannerMobileViewMode _mobileViewMode = _PlannerMobileViewMode.agenda;

  // Standard Bangladesh & International Academic Weekday sequence (Saturday to Friday)
  static const List<int> _academicWeekdays = [
    DateTime.saturday,  // 6
    DateTime.sunday,    // 7
    DateTime.monday,    // 1
    DateTime.tuesday,   // 2
    DateTime.wednesday, // 3
    DateTime.thursday,  // 4
    DateTime.friday,    // 5
  ];

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

  static String getWeekdayFull(int day) => switch (day) {
        DateTime.saturday => 'Saturday',
        DateTime.sunday => 'Sunday',
        DateTime.monday => 'Monday',
        DateTime.tuesday => 'Tuesday',
        DateTime.wednesday => 'Wednesday',
        DateTime.thursday => 'Thursday',
        DateTime.friday => 'Friday',
        _ => 'Day',
      };

  DateTime _getStartOfAcademicWeek(DateTime date) {
    final daysSinceSat = (date.weekday % 7 + 1) % 7;
    return DateTime(date.year, date.month, date.day).subtract(Duration(days: daysSinceSat));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 800;
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
    final selectedDaySlots = isClassSuppressed
        ? <RoutineSlot>[]
        : allSlots.where((s) {
            if (s.dayOfWeek != _selectedDate.weekday) return false;
            if (activeCourseIds != null && s.courseId.isNotEmpty && !activeCourseIds.contains(s.courseId)) {
              return false;
            }
            return s.isActiveOnDate(_selectedDate);
          }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

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
  // DESKTOP / WEB STUDIO DUAL-PANE VIEW
  // ===========================================================================
  Widget _buildDesktopStudio({
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required dynamic userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required List<ExamModel> allExams,
    required HolidaySettings holidaySettings,
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
    final termId = userProfile.term != null && userProfile.term.isNotEmpty
        ? 'TERM: ${userProfile.universityName ?? "UNI"} • ${userProfile.term}'
        : (userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'ACADEMIC TIMETABLE');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Operational Breadcrumb Strip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'ATELIER PLANNER // ROUTINE MATRIX',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('•', style: GoogleFonts.jetBrainsMono(color: colors.surfaceBorder)),
                    const SizedBox(width: 8),
                    Text(
                      termId.toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    // Sync badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(
                            allSlots.isNotEmpty ? 'ROUTINE ACTIVE' : 'NO ROUTINE CONFIGURED',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Options Menu Button
                    IconButton(
                      icon: Icon(Icons.settings_outlined, color: colors.textMuted, size: 18),
                      tooltip: 'Routine Settings',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const RoutineScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Zero-state check if no slots exist
              if (allSlots.isEmpty && allAssessments.isEmpty)
                _buildZeroState(colors, uid)
              else
                // Dual-Pane Layout: Left Pane (Timetable Grid / Calendar, flex: 7) + Right Pane (Day Agenda, flex: 5)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left / Center Pane: Comprehensive Schedule Studio (flex: 7)
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Pane Controls Header: Switcher + Month/Week navigation
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                // View Switcher: Weekly Timetable Grid vs Academic Calendar
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
                                      _buildSegmentPill(
                                        label: 'Weekly Timetable Grid',
                                        icon: Icons.grid_view_rounded,
                                        isSelected: _desktopViewMode == _PlannerDesktopViewMode.timetable,
                                        colors: colors,
                                        onTap: () {
                                          SafeHaptics.selectionClick();
                                          setState(() => _desktopViewMode = _PlannerDesktopViewMode.timetable);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _buildSegmentPill(
                                        label: 'Monthly Calendar',
                                        icon: Icons.calendar_month_outlined,
                                        isSelected: _desktopViewMode == _PlannerDesktopViewMode.calendar,
                                        colors: colors,
                                        onTap: () {
                                          SafeHaptics.selectionClick();
                                          setState(() => _desktopViewMode = _PlannerDesktopViewMode.calendar);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                // Today Button
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.primary,
                                    side: BorderSide(color: colors.surfaceBorder),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () {
                                    SafeHaptics.selectionClick();
                                    final now = DateTime.now();
                                    setState(() {
                                      _selectedDate = now;
                                      _focusedMonth = now;
                                    });
                                  },
                                  icon: const Icon(Icons.today_rounded, size: 14),
                                  label: Text(
                                    'Today',
                                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Month navigation buttons
                                IconButton(
                                  icon: Icon(Icons.chevron_left_rounded, color: colors.textPrimary, size: 20),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    SafeHaptics.selectionClick();
                                    setState(() {
                                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                                    });
                                  },
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('MMM yyyy').format(_focusedMonth),
                                  style: GoogleFonts.jetBrainsMono(
                                    color: colors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(Icons.chevron_right_rounded, color: colors.textPrimary, size: 20),
                                  padding: EdgeInsets.zero,
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

                          // Dynamic Center Content based on View Mode
                          if (_desktopViewMode == _PlannerDesktopViewMode.timetable)
                            _buildWeeklyTimetableGrid(
                              allSlots: allSlots,
                              courses: courses,
                              colors: colors,
                              isDark: isDark,
                              activeCourseIds: activeCourseIds,
                            )
                          else
                            _buildLeftCalendarColumn(
                              allAssessments: allAssessments,
                              allSlots: allSlots,
                              holidaySettings: holidaySettings,
                              activeCourseIds: activeCourseIds,
                              colors: colors,
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Right Pane: Day Agenda & Upcoming Deadlines (flex: 5)
                    Expanded(
                      flex: 5,
                      child: _buildRightDayAgendaColumn(
                        selectedDayAssessments: selectedDayAssessments,
                        selectedDaySlots: selectedDaySlots,
                        courseCodeMap: courseCodeMap,
                        courseTitleMap: courseTitleMap,
                        isClassSuppressed: isClassSuppressed,
                        isHoliday: isHoliday,
                        isExamPeriod: isExamPeriod,
                        colors: colors,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MOBILE VIEW: Chronological Day Agenda + Full Week Horizontal Grid
  // ===========================================================================
  Widget _buildMobilePlanner({
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required dynamic userProfile,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required List<ExamModel> allExams,
    required HolidaySettings holidaySettings,
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
    final weekStart = _getStartOfAcademicWeek(_selectedDate);
    final weekDates = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mobile Top Bar
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Academic Planner',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'Weekly Timetable',
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const Spacer(),
              // Today Button
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  side: BorderSide(color: colors.surfaceBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  SafeHaptics.selectionClick();
                  final now = DateTime.now();
                  setState(() {
                    _selectedDate = now;
                    _focusedMonth = now;
                  });
                },
                child: Text('Today', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              // Routine Settings / Management
              IconButton(
                icon: Icon(Icons.settings_outlined, color: colors.textMuted, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoutineScreen()),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Horizontal 7-Day Week Picker (Sat to Fri)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: weekDates.map((date) {
                final isSelected = isSameDay(date, _selectedDate);
                final isToday = isSameDay(date, DateTime.now());
                final hasClasses = allSlots.any((s) => s.dayOfWeek == date.weekday);

                return Expanded(
                  child: InkWell(
                    onTap: () {
                      SafeHaptics.lightImpact();
                      setState(() {
                        _selectedDate = date;
                        _focusedMonth = date;
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? colors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            getWeekdayShort(date.weekday).toUpperCase(),
                            style: GoogleFonts.plusJakartaSans(
                              color: isSelected
                                  ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                  : colors.textMuted,
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${date.day}',
                            style: GoogleFonts.jetBrainsMono(
                              color: isSelected
                                  ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                  : colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (isToday && !isSelected)
                            Container(width: 4, height: 4, decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle))
                          else if (hasClasses && !isSelected)
                            Container(width: 4, height: 4, decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.5), shape: BoxShape.circle))
                          else
                            const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // View Mode Selector: Agenda vs Weekly Grid vs Calendar
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMobileModePill(
                    label: 'Agenda',
                    icon: Icons.view_agenda_outlined,
                    isSelected: _mobileViewMode == _PlannerMobileViewMode.agenda,
                    colors: colors,
                    onTap: () => setState(() => _mobileViewMode = _PlannerMobileViewMode.agenda),
                  ),
                ),
                Expanded(
                  child: _buildMobileModePill(
                    label: 'Week Grid',
                    icon: Icons.grid_view_rounded,
                    isSelected: _mobileViewMode == _PlannerMobileViewMode.weekGrid,
                    colors: colors,
                    onTap: () => setState(() => _mobileViewMode = _PlannerMobileViewMode.weekGrid),
                  ),
                ),
                Expanded(
                  child: _buildMobileModePill(
                    label: 'Calendar',
                    icon: Icons.calendar_month_outlined,
                    isSelected: _mobileViewMode == _PlannerMobileViewMode.calendar,
                    colors: colors,
                    onTap: () => setState(() => _mobileViewMode = _PlannerMobileViewMode.calendar),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Dynamic Mobile Body
          if (allSlots.isEmpty && allAssessments.isEmpty)
            _buildZeroState(colors, uid)
          else if (_mobileViewMode == _PlannerMobileViewMode.agenda)
            _buildMobileAgendaFeed(
              colors: colors,
              isDark: isDark,
              selectedDayAssessments: selectedDayAssessments,
              selectedDaySlots: selectedDaySlots,
              courseCodeMap: courseCodeMap,
              courseTitleMap: courseTitleMap,
              isClassSuppressed: isClassSuppressed,
              isHoliday: isHoliday,
              isExamPeriod: isExamPeriod,
            )
          else if (_mobileViewMode == _PlannerMobileViewMode.weekGrid)
            _buildMobileHorizontalWeekGrid(
              allSlots: allSlots,
              courses: courses,
              colors: colors,
              isDark: isDark,
            )
          else
            _buildLeftCalendarColumn(
              allAssessments: allAssessments,
              allSlots: allSlots,
              holidaySettings: holidaySettings,
              activeCourseIds: activeCourseIds,
              colors: colors,
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Comprehensive 7-Day Weekly Timetable Grid (Desktop)
  // ===========================================================================
  Widget _buildWeeklyTimetableGrid({
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required Set<String>? activeCourseIds,
  }) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    final currentMinutes = now.hour * 60 + now.minute;

    // Filter active slots
    final activeSlots = allSlots.where((s) {
      if (activeCourseIds != null && s.courseId.isNotEmpty && !activeCourseIds.contains(s.courseId)) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
          Row(
            children: [
              Icon(Icons.calendar_view_week_rounded, size: 18, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Weekly Timetable Schedule',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // Legend
              _buildSlotTypeBadge('Theory', colors.primary, colors),
              const SizedBox(width: 8),
              _buildSlotTypeBadge('Lab / Sessional', colors.secondary, colors),
            ],
          ),
          const SizedBox(height: 14),

          // 7-Day Columns Layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _academicWeekdays.map((day) {
              final isToday = day == currentWeekday;
              final daySlots = activeSlots.where((s) => s.dayOfWeek == day).toList()
                ..sort((a, b) => RoutineCourseSyncService.parseTimeToMinutes(a.startTime)
                    .compareTo(RoutineCourseSyncService.parseTimeToMinutes(b.startTime)));

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: isToday ? colors.primary.withValues(alpha: 0.05) : colors.recessed.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday ? colors.primary : colors.surfaceBorder.withValues(alpha: 0.7),
                      width: isToday ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Day Header
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: isToday ? colors.primary.withValues(alpha: 0.15) : colors.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
                          border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              getWeekdayShort(day).toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                color: isToday ? colors.primary : colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${daySlots.length} ${daySlots.length == 1 ? "class" : "classes"}',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Slots list for this day
                      Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: daySlots.isEmpty
                            ? Container(
                                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 4),
                                child: Text(
                                  'Off Day',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: colors.textMuted.withValues(alpha: 0.6),
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              )
                            : Column(
                                children: daySlots.map((slot) {
                                  final startM = RoutineCourseSyncService.parseTimeToMinutes(slot.startTime);
                                  final endM = RoutineCourseSyncService.parseTimeToMinutes(slot.endTime);
                                  final isLiveNow = isToday && currentMinutes >= startM && currentMinutes <= endM;

                                  return _buildGridSlotCard(
                                    slot: slot,
                                    colors: colors,
                                    isLiveNow: isLiveNow,
                                  );
                                }).toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Slot Card inside Weekly Timetable Grid
  // ===========================================================================
  Widget _buildGridSlotCard({
    required RoutineSlot slot,
    required ChondrobinduThemeColors colors,
    required bool isLiveNow,
  }) {
    final isLab = slot.slotType == CourseType.sessional || slot.slotType == CourseType.practical;
    final accent = isLab ? colors.secondary : colors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () => _showSlotDetails(slot),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isLiveNow ? colors.secondary : colors.surfaceBorder),
            boxShadow: isLiveNow
                ? [
                    BoxShadow(
                      color: colors.secondary.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live tag if ongoing
              if (isLiveNow) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                      Text(
                        'LIVE NOW',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Time badge in JetBrains Mono
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      slot.startTime,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Course code
              Text(
                slot.courseCode,
                style: GoogleFonts.jetBrainsMono(
                  color: accent,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Title preview
              if (slot.courseTitle.isNotEmpty)
                Text(
                  slot.courseTitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 6),

              // Room number & Instructor
              Row(
                children: [
                  if (slot.room.isNotEmpty) ...[
                    Icon(Icons.meeting_room_outlined, size: 10, color: colors.textMuted),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        slot.room,
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty) ...[
                    Text(
                      slot.teacherBadge!,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Mobile Horizontal Full-Week Grid View
  // ===========================================================================
  Widget _buildMobileHorizontalWeekGrid({
    required List<RoutineSlot> allSlots,
    required List<Course> courses,
    required ChondrobinduThemeColors colors,
    required bool isDark,
  }) {
    final now = DateTime.now();
    final currentWeekday = now.weekday;
    final currentMinutes = now.hour * 60 + now.minute;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _academicWeekdays.map((day) {
          final isToday = day == currentWeekday;
          final daySlots = allSlots.where((s) => s.dayOfWeek == day).toList()
            ..sort((a, b) => RoutineCourseSyncService.parseTimeToMinutes(a.startTime)
                .compareTo(RoutineCourseSyncService.parseTimeToMinutes(b.startTime)));

          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isToday ? colors.primary.withValues(alpha: 0.05) : colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isToday ? colors.primary : colors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isToday ? colors.primary.withValues(alpha: 0.15) : colors.recessed,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        getWeekdayShort(day).toUpperCase(),
                        style: GoogleFonts.plusJakartaSans(
                          color: isToday ? colors.primary : colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${daySlots.length} classes',
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: daySlots.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Text('Off Day', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 11)),
                        )
                      : Column(
                          children: daySlots.map((slot) {
                            final startM = RoutineCourseSyncService.parseTimeToMinutes(slot.startTime);
                            final endM = RoutineCourseSyncService.parseTimeToMinutes(slot.endTime);
                            final isLiveNow = isToday && currentMinutes >= startM && currentMinutes <= endM;
                            return _buildGridSlotCard(slot: slot, colors: colors, isLiveNow: isLiveNow);
                          }).toList(),
                        ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Mobile Chronological Agenda Feed
  // ===========================================================================
  Widget _buildMobileAgendaFeed({
    required ChondrobinduThemeColors colors,
    required bool isDark,
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required bool isClassSuppressed,
    required bool isHoliday,
    required bool isExamPeriod,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date heading banner
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Agenda: ${DateFormat('dd MMM (EEE)').format(_selectedDate)}',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${selectedDayAssessments.length} Assessments • ${selectedDaySlots.length} Classes',
                  style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showAddPlannerItemDialog(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Add', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Assessments section if any
        if (selectedDayAssessments.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.assignment_late_outlined, size: 18, color: colors.secondary),
              const SizedBox(width: 6),
              Text(
                'Assessments & Quizzes',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${selectedDayAssessments.length}',
                  style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...selectedDayAssessments.map((a) {
            final cCode = courseCodeMap[a.courseId] ?? a.courseId;
            final cTitle = courseTitleMap[a.courseId] ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
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
          }),
          const SizedBox(height: 12),
        ],

        // Routine Classes section
        Row(
          children: [
            Icon(Icons.schedule_rounded, size: 18, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'Class Routine',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (isClassSuppressed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isHoliday ? 'HOLIDAY' : 'EXAM SUSPENSION',
                  style: GoogleFonts.jetBrainsMono(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),

        const SizedBox(height: 8),

        if (isClassSuppressed)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: colors.secondary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isHoliday
                        ? 'Classes suspended for official holiday / academic break.'
                        : 'Routine lectures suppressed during the examination period.',
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else if (selectedDaySlots.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Center(
              child: Text(
                'No classes scheduled for this day.',
                style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ...selectedDaySlots.map((slot) => _buildRoutineSlotCard(
                slot,
                courseCodeMap,
                courseTitleMap,
                colors,
                isSuspended: isClassSuppressed,
              )),
      ],
    );
  }

  // ===========================================================================
  // SECTION: Monthly Interactive Calendar (TableCalendar + Stitch tokens)
  // ===========================================================================
  Widget _buildLeftCalendarColumn({
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required ChondrobinduThemeColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Overline + Month Name + Year + Controls
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
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy').format(_focusedMonth),
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.primary,
                      side: BorderSide(color: colors.surfaceBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      SafeHaptics.selectionClick();
                      final now = DateTime.now();
                      setState(() {
                        _selectedDate = now;
                        _focusedMonth = now;
                      });
                    },
                    child: Text('Today', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.chevron_left_rounded, color: colors.textPrimary, size: 20),
                    onPressed: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.chevron_right_rounded, color: colors.textPrimary, size: 20),
                    onPressed: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),

          // Term Capsule Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(top: 10, bottom: 12),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.surfaceBorder.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Semester 24.2 • Fall 2026',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Text(
                    'WEEK 04',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // TableCalendar with Saturday Start
          TableCalendar<dynamic>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedMonth,
            currentDay: DateTime.now(),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.saturday,
            headerVisible: false,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
              weekendStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
              dowTextFormatter: (date, locale) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return days[date.weekday - 1];
              },
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
              weekendTextStyle: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
              todayDecoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: colors.secondary, width: 1.2),
              ),
              todayTextStyle: GoogleFonts.jetBrainsMono(color: colors.secondary, fontWeight: FontWeight.bold),
              selectedDecoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              selectedTextStyle: GoogleFonts.jetBrainsMono(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF171C24) : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
            onDaySelected: (selectedDay, focusedDay) {
              SafeHaptics.lightImpact();
              setState(() {
                _selectedDate = selectedDay;
                _focusedMonth = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedMonth = focusedDay);
            },
            eventLoader: (day) {
              final dayAssessments = allAssessments.where((a) {
                final d = a.dueDate ?? a.date;
                return d != null && d.year == day.year && d.month == day.month && d.day == day.day;
              }).toList();
              final isDaySuppressed = !holidaySettings.isWithinSemester(day) ||
                  holidaySettings.isHolidayOrBreak(day) ||
                  holidaySettings.isExamPeriod(day);
              final daySlots = isDaySuppressed
                  ? <RoutineSlot>[]
                  : allSlots.where((s) {
                      if (s.dayOfWeek != day.weekday) return false;
                      if (activeCourseIds != null && s.courseId.isNotEmpty && !activeCourseIds.contains(s.courseId)) {
                        return false;
                      }
                      return s.isActiveOnDate(day);
                    }).toList();
              return [...dayAssessments, ...daySlots];
            },
            holidayPredicate: (day) => holidaySettings.isHolidayOrBreak(day),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, date, focusedDay) => _buildCalendarDayCell(
                date: date,
                isSelected: false,
                isToday: isSameDay(date, DateTime.now()),
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
              ),
              todayBuilder: (context, date, focusedDay) => _buildCalendarDayCell(
                date: date,
                isSelected: isSameDay(date, _selectedDate),
                isToday: true,
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
              ),
              selectedBuilder: (context, date, focusedDay) => _buildCalendarDayCell(
                date: date,
                isSelected: true,
                isToday: isSameDay(date, DateTime.now()),
                allAssessments: allAssessments,
                allSlots: allSlots,
                holidaySettings: holidaySettings,
                activeCourseIds: activeCourseIds,
                colors: colors,
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Calendar Conventions Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CALENDAR CONVENTIONS',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _calendarLegendItem(colors.success, 'Class Routine', colors),
                    _calendarLegendItem(colors.secondary, 'Exam / CT Day', colors),
                    _calendarLegendItem(const Color(0xFFD98A3C), 'Exam Window', colors),
                    _calendarLegendItem(Colors.redAccent, 'Holiday / Break', colors),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Day Cell Builder for TableCalendar
  // ===========================================================================
  Widget _buildCalendarDayCell({
    required DateTime date,
    required bool isSelected,
    required bool isToday,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
    required Set<String>? activeCourseIds,
    required ChondrobinduThemeColors colors,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dayAssessments = allAssessments.where((a) {
      final d = a.dueDate ?? a.date;
      return d != null && d.year == date.year && d.month == date.month && d.day == date.day;
    }).toList();

    final isExamPeriod = holidaySettings.isExamPeriod(date);
    final isHoliday = holidaySettings.isHolidayOrBreak(date);
    final isWithinSemester = holidaySettings.isWithinSemester(date);
    final isExamDay = dayAssessments.isNotEmpty;

    final hasSlot = (!isHoliday && !isExamPeriod && isWithinSemester) &&
        allSlots.any((s) =>
            s.dayOfWeek == date.weekday &&
            s.isActiveOnDate(date) &&
            (activeCourseIds == null || !s.courseId.isNotEmpty || activeCourseIds.contains(s.courseId)));

    if (isSelected) {
      return Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
          child: Center(
            child: Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: isDark ? const Color(0xFF171C24) : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    if (isExamDay) {
      return Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.secondary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: colors.secondary.withValues(alpha: 0.3), blurRadius: 4),
            ],
          ),
          child: Center(
            child: Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    if (isHoliday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: Colors.redAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
          ],
        ),
      );
    }

    if (hasSlot) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Container(width: 4, height: 4, decoration: BoxDecoration(color: colors.success, shape: BoxShape.circle)),
          ],
        ),
      );
    }

    return Center(
      child: Text(
        '${date.day}',
        style: GoogleFonts.jetBrainsMono(
          color: isToday ? colors.secondary : colors.textPrimary,
          fontSize: 13,
          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION: Right Day Agenda Column (Desktop)
  // ===========================================================================
  Widget _buildRightDayAgendaColumn({
    required List<Assessment> selectedDayAssessments,
    required List<RoutineSlot> selectedDaySlots,
    required Map<String, String> courseCodeMap,
    required Map<String, String> courseTitleMap,
    required bool isClassSuppressed,
    required bool isHoliday,
    required bool isExamPeriod,
    required ChondrobinduThemeColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Agenda Top Card (Stitch Token rounded-lg 8px)
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(
                        'SELECTED SCHEDULE',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.secondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Agenda: ${DateFormat('dd MMM (EEEE)').format(_selectedDate)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showAddPlannerItemDialog(context),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text('+ Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // SECTION A: Assessments & Deadlines
        if (selectedDayAssessments.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: colors.surface,
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
                        Icon(Icons.assignment_late_outlined, size: 18, color: colors.secondary),
                        const SizedBox(width: 6),
                        Text(
                          'Assessments & Deadlines',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'CRITICAL PATH EVALUATION',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...selectedDayAssessments.map((a) {
                  final cCode = courseCodeMap[a.courseId] ?? a.courseId;
                  final cTitle = courseTitleMap[a.courseId] ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: AssessmentCard(
                      assessment: a,
                      courseCode: cCode,
                      courseTitle: cTitle,
                      cardColor: colors.recessed,
                      accentColor: colors.secondary,
                      onEditDetails: () => _showEditAssessmentDialog(a),
                      onEditMarks: () => _showEditAssessmentDialog(a),
                      onAttended: () => _updateAssessmentStatus(a, 'Attended'),
                      onMissed: () => _updateAssessmentStatus(a, 'Missed'),
                      onDelete: () => _deleteAssessment(a),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],

        // SECTION B: Class Routine Schedule
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
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
                      Icon(Icons.schedule_rounded, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Class Routine',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${selectedDaySlots.length} CLASSES',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (isClassSuppressed)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.recessed,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: colors.secondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isHoliday
                              ? 'No classes scheduled: Academic break or holiday.'
                              : 'Classes suspended due to examination window protocol.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (selectedDaySlots.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text(
                      'No classes scheduled for ${DateFormat('EEEE').format(_selectedDate)}.',
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                    ),
                  ),
                )
              else
                ...selectedDaySlots.map((slot) => _buildRoutineSlotCard(
                      slot,
                      courseCodeMap,
                      courseTitleMap,
                      colors,
                      isSuspended: isClassSuppressed,
                    )),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION: Day Agenda Routine Slot Card (Desktop & Mobile - Stitch Tokens)
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
  // SECTION: Slot Details Modal (Launch Focus Session, Syllabus, Edit, Delete)
  // ===========================================================================
  void _showSlotDetails(RoutineSlot slot) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final isLab = slot.slotType == CourseType.sessional || slot.slotType == CourseType.practical;
    final accent = isLab ? colors.secondary : colors.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Top info row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isLab ? 'LAB / SESSIONAL' : 'THEORY LECTURE',
                      style: GoogleFonts.jetBrainsMono(
                        color: accent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    getWeekdayFull(slot.dayOfWeek),
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.edit_outlined, color: colors.textMuted, size: 20),
                    tooltip: 'Edit Slot',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEditRoutineSlotDialog(context, slot);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Delete Slot',
                    onPressed: () {
                      Navigator.pop(ctx);
                      _confirmDeleteSlot(context, slot);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Title and Code
              Text(
                slot.courseCode,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (slot.courseTitle.isNotEmpty)
                Text(
                  slot.courseTitle,
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 14),
                ),

              const SizedBox(height: 14),

              // Metadata Slate
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(12),
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  void _confirmDeleteSlot(BuildContext context, RoutineSlot slot) {
    final colors = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Text('Delete Routine Slot?', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Remove ${slot.courseCode} (${slot.timeRange}) from your weekly timetable?',
          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isNotEmpty) {
                await ref.read(routineRepositoryProvider).removeRoutineSlot(uid, slot.id);
              }
            },
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION: Zero-State Card
  // ===========================================================================
  Widget _buildZeroState(ChondrobinduThemeColors colors, String uid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 36),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.calendar_view_week_rounded, size: 28, color: colors.secondary),
            ),
            const SizedBox(height: 16),
            Text(
              'No weekly timetable uploaded yet',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your classes manually or import your semester routine to activate your timetable.',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textMuted,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showAddRoutineSlotDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Add Class Slot', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.secondary,
                    side: BorderSide(color: colors.secondary.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutineScreen()),
                    );
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text('Smart Import Routine', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ],
            ),
          ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                'Add to Academic Planner',
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
                  borderRadius: BorderRadius.circular(10),
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
                  borderRadius: BorderRadius.circular(10),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            borderRadius: BorderRadius.circular(16),
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
                  Text('Course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (courses.isNotEmpty)
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
                          dropdownColor: colors.surface,
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                          isExpanded: true,
                          items: courses
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text('${c.code}: ${c.title}', overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedCourse = val;
                                if (val.teacherInitials.isNotEmpty) {
                                  teacherCtrl.text = val.teacherInitials.first;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    )
                  else
                    Text(
                      'No enrolled courses. Please add a course first.',
                      style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 13),
                    ),
                  const SizedBox(height: 12),

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
                        dropdownColor: colors.surface,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                        isExpanded: true,
                        items: daysList
                            .map((d) => DropdownMenuItem(
                                  value: d['day'] as int,
                                  child: Text(d['name'] as String),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedDay = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Start and End Time
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Room & Teacher
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Room Number', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                                  hintText: 'Room 302 / LT-1',
                                  hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
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
                                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  hintText: 'e.g. MSR, NHK',
                                  hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Slot Type: Theory vs Sessional
                  Text('Class Type', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedType = CourseType.theory),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: selectedType == CourseType.theory ? colors.primary.withValues(alpha: 0.15) : colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selectedType == CourseType.theory ? colors.primary : colors.surfaceBorder),
                            ),
                            child: Center(
                              child: Text(
                                'Theory Lecture',
                                style: GoogleFonts.plusJakartaSans(
                                  color: selectedType == CourseType.theory ? colors.primary : colors.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () => setDialogState(() => selectedType = CourseType.sessional),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: selectedType == CourseType.sessional ? colors.secondary.withValues(alpha: 0.15) : colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: selectedType == CourseType.sessional ? colors.secondary : colors.surfaceBorder),
                            ),
                            child: Center(
                              child: Text(
                                'Lab / Sessional',
                                style: GoogleFonts.plusJakartaSans(
                                  color: selectedType == CourseType.sessional ? colors.secondary : colors.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
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
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                if (selectedCourse == null) return;
                final start = startCtrl.text.trim();
                final end = endCtrl.text.trim();
                if (start.isEmpty || end.isEmpty) return;

                final newSlot = RoutineSlot(
                  id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  courseId: selectedCourse!.id,
                  courseCode: selectedCourse!.code,
                  courseTitle: selectedCourse!.title,
                  dayOfWeek: selectedDay,
                  startTime: start,
                  endTime: end,
                  room: roomCtrl.text.trim(),
                  teacherBadge: teacherCtrl.text.trim().isNotEmpty ? teacherCtrl.text.trim() : null,
                  slotType: selectedType,
                );

                final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                if (uid.isNotEmpty) {
                  await ref.read(routineRepositoryProvider).addRoutineSlot(uid, newSlot);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text(
                existing == null ? 'Add Slot' : 'Save Changes',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRoutineSlotDialog(BuildContext context, RoutineSlot slot) {
    _showAddRoutineSlotDialog(context, existing: slot);
  }

  void _showAddAssessmentDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final colors = AppColors.of(context);
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    final titleCtrl = TextEditingController();
    final marksCtrl = TextEditingController(text: '20');
    final weightCtrl = TextEditingController(text: '10.0');
    DateTime selectedDate = _selectedDate;
    TimeOfDay selectedTime = const TimeOfDay(hour: 10, minute: 0);
    String selectedType = 'quiz';

    final typesList = [
      {'val': 'quiz', 'label': 'Quiz / CT'},
      {'val': 'assignment', 'label': 'Assignment'},
      {'val': 'midterm', 'label': 'Midterm Exam'},
      {'val': 'final', 'label': 'Term Final Exam'},
      {'val': 'lab_final', 'label': 'Lab Final / Viva'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
                  Text('Title (e.g. CT 4: Linked Lists)', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                        hintText: 'Enter assessment title',
                        hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text('Course', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                  const SizedBox(height: 6),
                  if (courses.isNotEmpty)
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
                          dropdownColor: colors.surface,
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                          isExpanded: true,
                          items: courses
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text('${c.code}: ${c.title}', overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedCourse = val);
                          },
                        ),
                      ),
                    )
                  else
                    Text('No enrolled courses.', style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 13)),
                  const SizedBox(height: 12),

                  Text('Assessment Type', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
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
                      child: DropdownButton<String>(
                        value: selectedType,
                        dropdownColor: colors.surface,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                        isExpanded: true,
                        items: typesList
                            .map((t) => DropdownMenuItem(value: t['val']!, child: Text(t['label']!)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedType = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Date and Time picker triggers
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setDialogState(() => selectedDate = picked);
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, size: 16, color: colors.secondary),
                                const SizedBox(width: 8),
                                Text(DateFormat('dd MMM yyyy').format(selectedDate), style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: selectedTime);
                            if (picked != null) setDialogState(() => selectedTime = picked);
                          },
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.schedule_rounded, size: 16, color: colors.primary),
                                const SizedBox(width: 8),
                                Text(selectedTime.format(context), style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Marks & Weightage
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
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 13),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: colors.recessed,
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final name = titleCtrl.text.trim();
                if (name.isEmpty) return;
                final courseId = selectedCourse?.id ?? '';
                final marks = double.tryParse(marksCtrl.text.trim()) ?? 20.0;
                final weight = double.tryParse(weightCtrl.text.trim()) ?? 10.0;
                final finalDateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final newAss = Assessment(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  courseId: courseId,
                  name: name,
                  type: selectedType,
                  totalMarks: marks,
                  weightage: weight,
                  dueDate: finalDateTime,
                  date: finalDateTime,
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
        ),
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
          borderRadius: BorderRadius.circular(16),
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
  // SECTION: Helper Micro-Widgets
  // ===========================================================================
  Widget _buildSegmentPill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: colors.surfaceBorder) : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 1)),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? colors.textPrimary : colors.textMuted,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileModePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: colors.surfaceBorder) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? colors.primary : colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? colors.textPrimary : colors.textMuted,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotTypeBadge(String label, Color color, ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(color: color, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _calendarLegendItem(Color color, String label, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
