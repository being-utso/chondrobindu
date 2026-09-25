import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/course_model.dart';
import '../models/routine_slot_model.dart';
import '../providers/firestore_providers.dart';
import '../utils/safe_haptics.dart';
import 'exams_screen.dart' as mobile;

/// Screen 04: Planner & Routine Matrix
/// Responsive desktop timetable grid (width >= 800) with mobile fallback to ExamsScreen.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  String _selectedView = 'Week';
  String _rightPanelTab = 'Assessments';

  final List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;

    if (!isWide) {
      return const mobile.PlannerScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main Area: Weekly Routine Calendar Grid (flex: 7)
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDateNavigationBar(),
                      const SizedBox(height: 20),
                      _buildWeeklyTimetableGrid(),
                    ],
                  ),
                ),

                const SizedBox(width: 24),

                // Right Column: Assessments & Attendance Ledger (flex: 3)
                Expanded(
                  flex: 3,
                  child: _buildRightSidePanel(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SECTION A: Date Navigation Bar ---
  Widget _buildDateNavigationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFFEDE8E3), size: 22),
            onPressed: () => SafeHaptics.selectionClick(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Text(
            '22 - 28 Sep 2026',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFEDE8E3), size: 22),
            onPressed: () => SafeHaptics.selectionClick(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 14),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF2B78A),
              side: const BorderSide(color: Color(0xFF382A24)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => SafeHaptics.selectionClick(),
            child: Text(
              'Today',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),

          const Spacer(),

          // View toggles: [ Week ] [ Month ]
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              children: [
                _viewToggleItem('Week', _selectedView == 'Week'),
                _viewToggleItem('Month', _selectedView == 'Month'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _viewToggleItem(String label, bool isSelected) {
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _selectedView = label);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF2B78A).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: const Color(0xFFF2B78A), width: 0.8) : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // --- SECTION B: 7-Column Timetable Grid ---
  Widget _buildWeeklyTimetableGrid() {
    final routineAsync = ref.watch(weeklyRoutineStreamProvider);
    final List<RoutineSlot> allSlots = routineAsync.value ?? [];

    final todayIndex = DateTime.now().weekday - 1; // 0..6
    final todayDayName = (todayIndex >= 0 && todayIndex < _days.length) ? _days[todayIndex] : 'Thu';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        children: [
          // Day Header Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2E2623), width: 1)),
            ),
            child: Row(
              children: _days.map((day) {
                final isToday = day == todayDayName;
                return Expanded(
                  child: Column(
                    children: [
                      Text(
                        day.toUpperCase(),
                        style: GoogleFonts.jetBrainsMono(
                          color: isToday ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                      if (isToday)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF2B78A),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Time Slots Grid
          allSlots.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today_outlined, color: Color(0xFF9E8C82), size: 36),
                        const SizedBox(height: 12),
                        Text(
                          'No scheduled classes',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF9E8C82),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(_days.length, (index) {
                      final dayNum = index + 1; // 1 = Monday ... 7 = Sunday
                      final daySlots = allSlots.where((s) => s.dayOfWeek == dayNum).toList()
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                      return Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            children: daySlots.isNotEmpty
                                ? daySlots.map((slot) => _buildLectureSlotCard(slot)).toList()
                                : [
                                    Container(
                                      height: 120,
                                      alignment: Alignment.center,
                                      child: Text(
                                        '—',
                                        style: GoogleFonts.jetBrainsMono(color: const Color(0xFF382A24)),
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildLectureSlotCard(RoutineSlot slot) {
    final Color accent = slot.slotType == CourseType.sessional
        ? const Color(0xFF34D399)
        : (slot.courseCode.startsWith('MATH') || slot.courseCode.startsWith('HUM')
            ? const Color(0xFF9E8C82)
            : const Color(0xFFF2B78A));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  slot.startTime,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            slot.courseCode,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            slot.courseTitle,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF9E8C82),
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  slot.room,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFABA093),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty)
                Text(
                  '[${slot.teacherBadge}]',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- SECTION C: Right Column — Assessments & Attendance ---
  Widget _buildRightSidePanel() {
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
          // Tab switcher
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _panelTabItem('Assessments', _rightPanelTab == 'Assessments'),
                ),
                Expanded(
                  child: _panelTabItem('Attendance', _rightPanelTab == 'Attendance'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_rightPanelTab == 'Assessments') ...[
            Text(
              'UPCOMING ASSESSMENTS',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF9E8C82),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 14),
            ..._buildAssessmentsList(),
          ] else ...[
            Text(
              'ATTENDANCE LEDGER',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF9E8C82),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 14),
            ..._buildAttendanceList(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildAssessmentsList() {
    final assessmentsAsync = ref.watch(upcomingAssessmentsStreamProvider);
    final items = assessmentsAsync.value;

    if (items != null && items.isNotEmpty) {
      return items.take(5).map((a) {
        final daysLeftStr = a.date != null
            ? () {
                final diff = a.date!.difference(DateTime.now()).inDays;
                if (diff < 0) return 'Past due';
                if (diff == 0) return 'Today';
                return '$diff days left';
              }()
            : 'Unscheduled';
        final dateStr = a.date != null ? DateFormat('MMM d').format(a.date!) : 'TBA';
        final Color cardColor = (a.type == 'quiz' || a.type == 'assignment')
            ? const Color(0xFF34D399)
            : const Color(0xFFF2B78A);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _assessmentCard(
            title: a.name,
            course: a.courseCode.isNotEmpty ? a.courseCode : 'Course',
            date: dateStr,
            marks: '${a.totalMarks.toInt()} marks',
            daysLeft: daysLeftStr,
            color: cardColor,
          ),
        );
      }).toList();
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 28.0),
        child: Center(
          child: Text(
            'No upcoming assessments.',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF9E8C82),
              fontSize: 13,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildAttendanceList() {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final liveCourses = coursesAsync.value;

    if (liveCourses != null && liveCourses.isNotEmpty) {
      return liveCourses.map((c) {
        final pct = (c.progressPercentage).clamp(60.0, 100.0).toInt();
        final pctColor = pct >= 80 ? const Color(0xFF34D399) : const Color(0xFFF2B78A);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _attendanceRow(
            c.code,
            c.title,
            '$pct%',
            '${c.completedTopicsCount} / ${c.totalTopicsCount > 0 ? c.totalTopicsCount : 20}',
            pctColor,
          ),
        );
      }).toList();
    }

    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 28.0),
        child: Center(
          child: Text(
            'No courses enrolled yet.',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF9E8C82),
              fontSize: 13,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _panelTabItem(String label, bool isSelected) {
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _rightPanelTab = label);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF2B78A).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: const Color(0xFFF2B78A), width: 0.8) : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _assessmentCard({
    required String title,
    required String course,
    required String date,
    required String marks,
    required String daysLeft,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
                ),
                child: Text(
                  daysLeft,
                  style: GoogleFonts.jetBrainsMono(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            course,
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date,
                style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 11),
              ),
              Text(
                marks,
                style: GoogleFonts.jetBrainsMono(color: const Color(0xFFF2B78A), fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _attendanceRow(String code, String name, String pct, String counts, Color pctColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E2623), width: 0.8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pct,
                style: GoogleFonts.jetBrainsMono(
                  color: pctColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                counts,
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
