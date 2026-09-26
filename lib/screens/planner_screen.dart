import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart';
import '../models/routine_slot_model.dart';
import '../providers/firestore_providers.dart';
import '../utils/safe_haptics.dart';
import '../widgets/assessment_card.dart';
import 'exams_screen.dart' as mobile;
import 'journal_screen.dart' show holidaySettingsStreamProvider;

/// Screen 04: Academic Planner & Routine Matrix
/// Responsive desktop split-view layout aligned with Android mobile design.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;

    if (!isWide) {
      return const mobile.PlannerScreen();
    }

    final assessmentsAsync = ref.watch(allAssessmentsStreamProvider);
    final allAssessments = assessmentsAsync.valueOrNull ?? [];

    final routineAsync = ref.watch(weeklyRoutineStreamProvider);
    final allSlots = routineAsync.valueOrNull ?? [];

    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = coursesAsync.valueOrNull ?? [];

    final Map<String, String> courseCodeMap = {for (final c in courses) c.id: c.code};
    final Map<String, String> courseTitleMap = {for (final c in courses) c.id: c.title};

    final holidaySettingsAsync = ref.watch(holidaySettingsStreamProvider);
    final holidaySettings = holidaySettingsAsync.valueOrNull ?? HolidaySettings.defaultSettings;

    // Filter for selected day
    final selectedDayAssessments = allAssessments.where((a) {
      final d = a.date ?? a.dueDate;
      if (d == null) return false;
      return d.year == _selectedDate.year &&
          d.month == _selectedDate.month &&
          d.day == _selectedDate.day;
    }).toList();

    final selectedDaySlots = allSlots.where((s) => s.dayOfWeek == _selectedDate.weekday).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFF2B78A),
        foregroundColor: const Color(0xFF151211),
        elevation: 4,
        onPressed: () => _showAddPlannerItemDialog(context),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Interactive monthly calendar (flex: 5)
                Expanded(
                  flex: 5,
                  child: _buildLeftCalendarColumn(allAssessments, allSlots, holidaySettings),
                ),
                const SizedBox(width: 24),
                // Right Column: Day Agenda (flex: 7)
                Expanded(
                  flex: 7,
                  child: _buildRightDayAgendaColumn(
                    selectedDayAssessments,
                    selectedDaySlots,
                    courseCodeMap,
                    courseTitleMap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SECTION A: Left Column — Monthly Interactive Calendar ---
  Widget _buildLeftCalendarColumn(List<Assessment> allAssessments, List<RoutineSlot> allSlots, HolidaySettings holidaySettings) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Month Name + Year + < > + Today button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_focusedMonth),
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF2B78A),
                      side: const BorderSide(color: Color(0xFF382A24)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        final now = DateTime.now();
                        _selectedDate = now;
                        _focusedMonth = now;
                      });
                    },
                    child: Text('Today', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFFEDE8E3), size: 22),
                    onPressed: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFEDE8E3), size: 22),
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
          const SizedBox(height: 16),
          // Interactive TableCalendar
          TableCalendar<dynamic>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focusedMonth,
            currentDay: DateTime.now(),
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.saturday,
            headerVisible: false,
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 12, fontWeight: FontWeight.w600),
              weekendStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 12, fontWeight: FontWeight.w600),
              dowTextFormatter: (date, locale) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return days[date.weekday - 1];
              },
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFFEDE8E3), fontSize: 13),
              weekendTextStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFFEDE8E3), fontSize: 13),
              todayDecoration: BoxDecoration(
                color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF2B78A), width: 1.2),
              ),
              todayTextStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFFF2B78A), fontWeight: FontWeight.bold),
              selectedDecoration: const BoxDecoration(
                color: Color(0xFFF2B78A),
                shape: BoxShape.circle,
              ),
              selectedTextStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF151211), fontWeight: FontWeight.bold),
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
              setState(() {
                _focusedMonth = focusedDay;
              });
            },
            eventLoader: (day) {
              final dayAssessments = allAssessments.where((a) {
                final d = a.date ?? a.dueDate;
                return d != null && isSameDay(d, day);
              }).toList();
              final daySlots = allSlots.where((s) => s.dayOfWeek == day.weekday).toList();
              return [...dayAssessments, ...daySlots];
            },
            holidayPredicate: (day) => holidaySettings.isHolidayOrBreak(day),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, date, focusedDay) {
                return _buildCalendarDayCell(
                  date: date,
                  isSelected: false,
                  isToday: isSameDay(date, DateTime.now()),
                  allAssessments: allAssessments,
                  allSlots: allSlots,
                  holidaySettings: holidaySettings,
                );
              },
              todayBuilder: (context, date, focusedDay) {
                return _buildCalendarDayCell(
                  date: date,
                  isSelected: isSameDay(date, _selectedDate),
                  isToday: true,
                  allAssessments: allAssessments,
                  allSlots: allSlots,
                  holidaySettings: holidaySettings,
                );
              },
              selectedBuilder: (context, date, focusedDay) {
                return _buildCalendarDayCell(
                  date: date,
                  isSelected: true,
                  isToday: isSameDay(date, DateTime.now()),
                  allAssessments: allAssessments,
                  allSlots: allSlots,
                  holidaySettings: holidaySettings,
                );
              },
              holidayBuilder: (context, date, focusedDay) {
                return _buildCalendarDayCell(
                  date: date,
                  isSelected: isSameDay(date, _selectedDate),
                  isToday: isSameDay(date, DateTime.now()),
                  allAssessments: allAssessments,
                  allSlots: allSlots,
                  holidaySettings: holidaySettings,
                );
              },
              markerBuilder: (context, date, events) {
                return null;
              },
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF2E2623), height: 1),
          const SizedBox(height: 14),
          // 4-Tier Visual Hierarchy Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _calendarLegendItem(const Color(0xFF34D399), 'Class Routine'),
              _calendarLegendItem(const Color(0xFFF59E0B), 'Exam Window'),
              _calendarLegendItem(const Color(0xFFF2B78A), 'Exam Day'),
              _calendarLegendItem(const Color(0xFFEF4444), 'Holiday / Vacation'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _calendarLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF9E8C82),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarDayCell({
    required DateTime date,
    required bool isSelected,
    required bool isToday,
    required List<Assessment> allAssessments,
    required List<RoutineSlot> allSlots,
    required HolidaySettings holidaySettings,
  }) {
    final dayAssessments = allAssessments.where((a) {
      final d = a.date ?? a.dueDate;
      return d != null && isSameDay(d, date);
    }).toList();
    final hasSlot = allSlots.any((s) => s.dayOfWeek == date.weekday);
    final isExamPeriod = holidaySettings.isExamPeriod(date);
    final isHoliday = holidaySettings.isHolidayOrBreak(date);
    final isExamDay = dayAssessments.isNotEmpty;

    // Tier 1 (Highest priority): Selected Day
    if (isSelected) {
      return Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: Color(0xFFF2B78A),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF151211),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    // Tier 2: Specific Exam / Assessment Day (CT, Quiz, Lab Final, Term Final)
    if (isExamDay) {
      return Center(
        child: Tooltip(
          message: '${dayAssessments.length} Exam/Assessment${dayAssessments.length > 1 ? "s" : ""}',
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isExamPeriod ? const Color(0xFFF59E0B).withValues(alpha: 0.16) : const Color(0xFF241C1A),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFF2B78A), width: 1.8),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (dayAssessments.length > 1)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2B78A),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${dayAssessments.length}',
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFF151211),
                            fontSize: 7.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 3,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2B78A),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Tier 3: Exam Period / Prep Leave (Window) — distinct Muted Amber, never red!
    if (isExamPeriod) {
      return Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: isToday ? Border.all(color: const Color(0xFFF59E0B), width: 1.2) : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFF59E0B),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Positioned(
                bottom: 3,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Tier 4: Holidays & Vacations — Muted Red / Crimson (#EF4444)
    if (isHoliday) {
      return Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: isToday
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
                )
              : null,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Positioned(
                bottom: 3,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Tier 5: Regular Class Days / Ordinary Days
    return Center(
      child: Container(
        width: 38,
        height: 38,
        decoration: isToday
            ? BoxDecoration(
                color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF2B78A), width: 1.2),
              )
            : null,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '${date.day}',
              style: GoogleFonts.jetBrainsMono(
                color: isToday ? const Color(0xFFF2B78A) : const Color(0xFFEDE8E3),
                fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (hasSlot)
              Positioned(
                bottom: 3,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34D399),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- SECTION B: Right Column — Day Agenda ---
  Widget _buildRightDayAgendaColumn(
    List<Assessment> assessments,
    List<RoutineSlot> routineSlots,
    Map<String, String> courseCodeMap,
    Map<String, String> courseTitleMap,
  ) {
    final dayLabel = DateFormat('d MMM (EEEE)').format(_selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Agenda Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1816),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF2E2623), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Agenda: $dayLabel',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2B78A),
                  foregroundColor: const Color(0xFF151211),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showAddPlannerItemDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text('+ Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Section 1: Assessments & Deadlines
        Row(
          children: [
            const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF2B78A), size: 18),
            const SizedBox(width: 8),
            Text(
              'Assessments & Deadlines (${assessments.length})',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFEDE8E3),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (assessments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2623)),
            ),
            child: Center(
              child: Text(
                'No assessments or deadlines scheduled for this day.',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
              ),
            ),
          )
        else
          ...assessments.map((a) {
            final cCode = courseCodeMap[a.courseId] ?? a.courseCode;
            final cTitle = courseTitleMap[a.courseId];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: AssessmentCard(
                assessment: a,
                courseCode: cCode.isNotEmpty ? cCode : 'Course',
                courseTitle: cTitle,
                cardColor: const Color(0xFF1E1816),
                accentColor: const Color(0xFFF2B78A),
                onAttended: () => _updateAssessmentStatus(a, 'Attended'),
                onMissed: () => _updateAssessmentStatus(a, 'Missed'),
                onPostponed: () => _handlePostponeAssessment(a),
                onEditDetails: () => _showEditAssessmentDialog(a),
                onDelete: () => _deleteAssessment(a),
              ),
            );
          }),

        const SizedBox(height: 24),

        // Section 2: Routine / Class Schedule
        Row(
          children: [
            const Icon(Icons.schedule_rounded, color: Color(0xFF34D399), size: 18),
            const SizedBox(width: 8),
            Text(
              'Class Schedule (${routineSlots.length})',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFEDE8E3),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (routineSlots.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2623)),
            ),
            child: Center(
              child: Text(
                'No classes scheduled for this day.',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
              ),
            ),
          )
        else
          ...routineSlots.map((slot) => Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _buildRoutineSlotCard(slot, courseCodeMap, courseTitleMap),
              )),
      ],
    );
  }

  String _cleanCourseCode(RoutineSlot slot, Map<String, String> courseCodeMap) {
    if (courseCodeMap.containsKey(slot.courseId) && courseCodeMap[slot.courseId]!.isNotEmpty) {
      return courseCodeMap[slot.courseId]!;
    }
    final raw = slot.courseCode.trim();
    final match = RegExp(r'^([A-Z]{2,5})\s*(\d{3,4}[A-Z]?)').firstMatch(raw);
    if (match != null) {
      return '${match.group(1)} ${match.group(2)}';
    }
    final tokens = raw.split(RegExp(r'\s+'));
    if (tokens.length >= 4 && tokens[0] == tokens[2] && tokens[1] == tokens[3]) {
      return '${tokens[0]} ${tokens[1]}';
    }
    return raw.isNotEmpty ? raw : 'Course';
  }

  String _cleanCourseTitle(RoutineSlot slot, String cleanCode, Map<String, String> courseTitleMap) {
    if (courseTitleMap.containsKey(slot.courseId) && courseTitleMap[slot.courseId]!.isNotEmpty) {
      return courseTitleMap[slot.courseId]!;
    }
    String title = slot.courseTitle.trim();
    final codeRegex = RegExp(RegExp.escape(cleanCode), caseSensitive: false);
    title = title.replaceAll(codeRegex, '').trim();
    title = title.replaceFirst(RegExp(r'^[\s\-–—:]+'), '').trim();
    if (title.isEmpty) {
      return cleanCode;
    }
    return title;
  }

  Widget _buildRoutineSlotCard(RoutineSlot slot, Map<String, String> courseCodeMap, Map<String, String> courseTitleMap) {
    final cleanCode = _cleanCourseCode(slot, courseCodeMap);
    final cleanTitle = _cleanCourseTitle(slot, cleanCode, courseTitleMap);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1: Time badge + Room badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, color: Color(0xFF34D399), size: 15),
                  const SizedBox(width: 6),
                  Text(
                    slot.timeRange,
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF34D399),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (slot.room.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxWidth: 130),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF241C1A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF382A24)),
                  ),
                  child: Text(
                    slot.room.startsWith('Room') || slot.room.startsWith('Lab') ? slot.room : 'Room ${slot.room}',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Line 2: Single bold Course Code
          Text(
            cleanCode,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          // Line 3: Single Course Title
          Text(
            cleanTitle,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF9E8C82),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          const SizedBox(height: 10),
          // Line 4: Class type badge (Theory or Sessional/Lab) + optional Teacher badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF241C1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2E2623)),
                ),
                child: Text(
                  slot.slotType == CourseType.sessional ? 'Sessional/Lab' : (slot.slotType == CourseType.practical ? 'Practical' : 'Theory'),
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2623),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '[${slot.teacherBadge}]',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Assessment Actions ---
  Future<void> _updateAssessmentStatus(Assessment assessment, String newStatus) async {
    SafeHaptics.selectionClick();
    String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      final updated = assessment.copyWith(status: assessment.status == newStatus ? 'Pending' : newStatus);
      await ref.read(assessmentRepositoryProvider).updateAssessment(uid, updated);
    } catch (e) {
      debugPrint('Error updating assessment status: $e');
    }
  }

  Future<void> _deleteAssessment(Assessment assessment) async {
    SafeHaptics.mediumImpact();
    String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;
    try {
      await ref.read(assessmentRepositoryProvider).deleteAssessment(uid, assessment.id);
    } catch (e) {
      debugPrint('Error deleting assessment: $e');
    }
  }

  Future<void> _handlePostponeAssessment(Assessment assessment) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (assessment.date ?? DateTime.now()).add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        final updated = assessment.copyWith(
          status: 'Postponed',
          postponedToDate: picked,
        );
        await ref.read(assessmentRepositoryProvider).updateAssessment(uid, updated);
      }
    }
  }

  void _showEditAssessmentDialog(Assessment assessment) {
    SafeHaptics.selectionClick();
    final nameCtrl = TextEditingController(text: assessment.name);
    final marksCtrl = TextEditingController(text: assessment.totalMarks.toString());
    final weightCtrl = TextEditingController(text: assessment.weightage.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1816),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2623)),
        ),
        title: Text('Edit Assessment', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Title', labelStyle: TextStyle(color: Color(0xFF9E8C82))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: marksCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Total Marks', labelStyle: TextStyle(color: Color(0xFF9E8C82))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Weightage (%)', labelStyle: TextStyle(color: Color(0xFF9E8C82))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF9E8C82))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF2B78A), foregroundColor: const Color(0xFF151211)),
            onPressed: () async {
              String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              if (uid.isNotEmpty) {
                final updated = assessment.copyWith(
                  name: nameCtrl.text.trim(),
                  totalMarks: double.tryParse(marksCtrl.text.trim()) ?? assessment.totalMarks,
                  weightage: double.tryParse(weightCtrl.text.trim()) ?? assessment.weightage,
                );
                await ref.read(assessmentRepositoryProvider).updateAssessment(uid, updated);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddPlannerItemDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1816),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Schedule New Item', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                tileColor: const Color(0xFF241C1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF2B78A)),
                title: const Text('Schedule Assessment', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Class test, quiz, midterm, or final exam', style: TextStyle(color: Color(0xFF9E8C82), fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showAddAssessmentDialog(context);
                },
              ),
              const SizedBox(height: 10),
              ListTile(
                tileColor: const Color(0xFF241C1A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.schedule_rounded, color: Color(0xFF34D399)),
                title: const Text('Add Routine Class Slot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Weekly recurring lecture or lab session', style: TextStyle(color: Color(0xFF9E8C82), fontSize: 12)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showAddRoutineSlotDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddAssessmentDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    final nameCtrl = TextEditingController();
    final marksCtrl = TextEditingController(text: '20');
    final weightageCtrl = TextEditingController(text: '10');
    String selectedType = 'quiz';
    DateTime selectedDate = _selectedDate;

    final typeOptions = [
      {'val': 'quiz', 'label': 'Quiz'},
      {'val': 'ct', 'label': 'Class Test (CT)'},
      {'val': 'midterm', 'label': 'Midterm Exam'},
      {'val': 'final', 'label': 'Term Final Exam'},
      {'val': 'assignment', 'label': 'Assignment / Presentation'},
      {'val': 'other', 'label': 'Other'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1816),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2623)),
          ),
          title: Text(
            'Schedule Assessment',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFEDE8E3),
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
                  Text('Course', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  if (courses.isNotEmpty)
                    DropdownButton<Course>(
                      value: selectedCourse,
                      dropdownColor: const Color(0xFF241C1A),
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                      isExpanded: true,
                      underline: Container(height: 1, color: const Color(0xFF2E2623)),
                      items: courses.map((c) => DropdownMenuItem(value: c, child: Text('${c.code}: ${c.title}'))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCourse = val);
                      },
                    )
                  else
                    Text(
                      'No enrolled courses. Please add a course first.',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 13),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Assessment Title (e.g. Quiz 2 / CT 1)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Type', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: selectedType,
                    dropdownColor: const Color(0xFF241C1A),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    isExpanded: true,
                    underline: Container(height: 1, color: const Color(0xFF2E2623)),
                    items: typeOptions.map((t) => DropdownMenuItem(value: t['val'], child: Text(t['label']!))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEDE8E3),
                            side: const BorderSide(color: Color(0xFF2E2623)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 30)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_today_rounded, size: 14, color: Color(0xFFF2B78A)),
                          label: Text(
                            DateFormat('MMM d, yyyy').format(selectedDate),
                            style: GoogleFonts.plusJakartaSans(fontSize: 12.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: marksCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Total Marks',
                            labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
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
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF151211),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty || selectedCourse == null) return;
                final totalMarks = double.tryParse(marksCtrl.text.trim()) ?? 20.0;
                final weightage = double.tryParse(weightageCtrl.text.trim()) ?? 10.0;

                String uid = '';
                try {
                  uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                } catch (_) {}

                final assessment = Assessment(
                  id: generateAssessmentId('assess'),
                  courseId: selectedCourse!.id,
                  courseCode: selectedCourse!.code,
                  userId: uid,
                  name: name,
                  type: selectedType,
                  date: selectedDate,
                  totalMarks: totalMarks,
                  weightage: weightage,
                  status: 'Pending',
                );

                if (uid.isNotEmpty) {
                  await ref.read(assessmentRepositoryProvider).createAssessment(uid, assessment);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text('Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRoutineSlotDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    int selectedDay = _selectedDate.weekday;
    final startCtrl = TextEditingController(text: '08:00 AM');
    final endCtrl = TextEditingController(text: '09:30 AM');
    final roomCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    CourseType selectedType = CourseType.theory;

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
          backgroundColor: const Color(0xFF1E1816),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2623)),
          ),
          title: Text(
            'Add Class Routine Slot',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFEDE8E3),
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
                  Text('Course', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  if (courses.isNotEmpty)
                    DropdownButton<Course>(
                      value: selectedCourse,
                      dropdownColor: const Color(0xFF241C1A),
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                      isExpanded: true,
                      underline: Container(height: 1, color: const Color(0xFF2E2623)),
                      items: courses.map((c) => DropdownMenuItem(value: c, child: Text('${c.code}: ${c.title}'))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedCourse = val);
                      },
                    )
                  else
                    Text(
                      'No enrolled courses. Please add a course first.',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 13),
                    ),
                  const SizedBox(height: 14),
                  Text('Day of Week', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButton<int>(
                    value: selectedDay,
                    dropdownColor: const Color(0xFF241C1A),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    isExpanded: true,
                    underline: Container(height: 1, color: const Color(0xFF2E2623)),
                    items: daysList.map((d) => DropdownMenuItem(value: d['day'] as int, child: Text(d['name'] as String))).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedDay = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Start Time (e.g. 08:00 AM)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'End Time (e.g. 09:30 AM)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: roomCtrl,
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Room / Venue (e.g. Room 302 / Lab 1)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: teacherCtrl,
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                          decoration: InputDecoration(
                            labelText: 'Teacher Initials (e.g. MSR)',
                            labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Class Type', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButton<CourseType>(
                    value: selectedType,
                    dropdownColor: const Color(0xFF241C1A),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    isExpanded: true,
                    underline: Container(height: 1, color: const Color(0xFF2E2623)),
                    items: const [
                      DropdownMenuItem(value: CourseType.theory, child: Text('Theory')),
                      DropdownMenuItem(value: CourseType.sessional, child: Text('Sessional / Lab')),
                      DropdownMenuItem(value: CourseType.practical, child: Text('Practical')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF151211),
              ),
              onPressed: () async {
                if (selectedCourse == null) return;
                final start = startCtrl.text.trim();
                final end = endCtrl.text.trim();
                if (start.isEmpty || end.isEmpty) return;

                final newSlot = RoutineSlot(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
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

                String uid = '';
                try {
                  uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                } catch (_) {}
                if (uid.isNotEmpty) {
                  await ref.read(routineRepositoryProvider).addRoutineSlot(uid, newSlot);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text('Add Slot', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
