import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart';
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
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2B78A),
                  foregroundColor: const Color(0xFF151211),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _showAddRoutineSlotDialog(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(
                  '+ Add Class Slot',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_days.length, (index) {
                final dayNum = index + 1; // 1 = Monday ... 7 = Sunday
                final daySlots = allSlots.where((s) => s.dayOfWeek == dayNum).toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));
                final courses = ref.watch(coursesStreamProvider).value ?? [];

                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      children: daySlots.isNotEmpty
                          ? daySlots.map((slot) => _buildLectureSlotCard(slot, courses)).toList()
                          : [
                              Container(
                                height: 120,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1816).withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF2E2623).withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '—',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: const Color(0xFF5A483E),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
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

  String _cleanCourseCode(RoutineSlot slot, List<Course> courses) {
    final raw = slot.courseCode.trim();
    final parsed = RoutineCourseSyncService.parseCourseCode(raw.isNotEmpty ? raw : slot.courseTitle);
    if (parsed.isNotEmpty) return parsed;
    return raw;
  }

  String _cleanCourseTitle(RoutineSlot slot, List<Course> courses) {
    final code = _cleanCourseCode(slot, courses);
    for (final c in courses) {
      if (c.id == slot.courseId || c.code.toLowerCase() == code.toLowerCase()) {
        if (c.title.isNotEmpty && c.title.toLowerCase() != code.toLowerCase()) {
          return c.title;
        }
      }
    }

    String raw = slot.courseTitle.trim();
    for (final delim in [' - ', ' – ', ' — ', ': ', ' • ', '|']) {
      if (raw.contains(delim)) {
        final parts = raw.split(delim);
        final part1 = parts[0].trim();
        final part2 = parts.sublist(1).join(delim).trim();
        if (part2.toLowerCase() != part1.toLowerCase() && part2.toLowerCase() != code.toLowerCase()) {
          return part2;
        } else {
          raw = part1;
        }
      }
    }

    if (raw.toUpperCase().startsWith(code.toUpperCase())) {
      final stripped = raw.substring(code.length).replaceFirst(RegExp(r'^[\s\-–—:•|]+'), '').trim();
      if (stripped.isNotEmpty) return stripped;
    }

    final words = raw.split(RegExp(r'\s+'));
    if (words.length >= 2 &&
        words.sublist(0, words.length ~/ 2).join(' ').toLowerCase() ==
            words.sublist(words.length ~/ 2).join(' ').toLowerCase()) {
      return words.sublist(0, words.length ~/ 2).join(' ');
    }

    return raw.isNotEmpty ? raw : code;
  }

  Widget _buildLectureSlotCard(RoutineSlot slot, List<Course> courses) {
    final Color accent = slot.slotType == CourseType.sessional
        ? const Color(0xFF34D399)
        : (slot.courseCode.startsWith('MATH') || slot.courseCode.startsWith('HUM')
            ? const Color(0xFF9E8C82)
            : const Color(0xFFF2B78A));
    final String cleanCode = _cleanCourseCode(slot, courses);
    final String cleanTitle = _cleanCourseTitle(slot, courses);
    final String timeBadge = '${slot.startTime} - ${slot.endTime}';
    final String roomBadge = slot.room.trim().isNotEmpty
        ? (slot.room.toLowerCase().startsWith('room') || slot.room.toLowerCase().startsWith('lab')
            ? slot.room
            : 'Room ${slot.room}')
        : '';
    final String classTypeLabel = slot.slotType == CourseType.sessional ? 'Lab' : 'Theory';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1 (Badge row): Start time - End time + Room badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                timeBadge,
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (roomBadge.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1816),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF382A24), width: 0.8),
                  ),
                  child: Text(
                    roomBadge,
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFEDE8E3),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Line 2 (Title): Course Code in bold with color accent pip
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
                  cleanCode,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),

          // Line 3 (Subtitle): Course Title with single line truncation and ellipsis
          Text(
            cleanTitle,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFF9E8C82),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Line 4 (Footer): Teacher initials and class type tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty)
                Text(
                  '[${slot.teacherBadge}]',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const SizedBox.shrink(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  classTypeLabel,
                  style: GoogleFonts.jetBrainsMono(
                    color: accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'UPCOMING ASSESSMENTS',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF9E8C82),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF2B78A),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showAddAssessmentDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: Text(
                    '+ Schedule',
                    style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
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
    final attendanceAsync = ref.watch(attendanceRecordsStreamProvider);
    final records = attendanceAsync.value ?? [];

    if (liveCourses != null && liveCourses.isNotEmpty) {
      return liveCourses.map((c) {
        final courseRecords = records.where((r) => r.courseId == c.id || (r.courseCode != null && r.courseCode == c.code)).toList();
        final totalClasses = courseRecords.where((r) => r.status != AttendanceStatus.canceled && r.status != AttendanceStatus.unmarked).length;
        final attendedClasses = courseRecords.where((r) => r.status == AttendanceStatus.attended || r.status == AttendanceStatus.extra).length;

        final String pctStr;
        final String classesStr;
        final Color pctColor;
        final double progressFraction;

        if (totalClasses > 0) {
          final pct = ((attendedClasses / totalClasses) * 100).toInt();
          progressFraction = attendedClasses / totalClasses;
          pctStr = '$pct%';
          classesStr = '$attendedClasses / $totalClasses classes';
          pctColor = pct >= 80 ? const Color(0xFF34D399) : const Color(0xFFF2B78A);
        } else {
          progressFraction = 0.0;
          pctStr = '--';
          classesStr = '0 / 0 classes';
          pctColor = const Color(0xFF9E8C82);
        }

        return _attendanceCardWithQuickLog(
          c,
          pctStr,
          classesStr,
          pctColor,
          progressFraction,
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
          color: isSelected ? const Color(0xFFF2B78A) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFF2B78A).withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? const Color(0xFF151211) : const Color(0xFF9E8C82),
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

  Future<void> _logQuickAttendance(Course course, AttendanceStatus status) async {
    SafeHaptics.mediumImpact();
    String uid = '';
    try {
      uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {}
    if (uid.isEmpty) return;

    final now = DateTime.now();
    final dateKey = '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
    final docId = '${course.id}_quick_$dateKey';

    final record = AttendanceRecord(
      id: docId,
      courseId: course.id,
      courseCode: course.code,
      courseName: course.title,
      date: DateTime(now.year, now.month, now.day),
      status: status,
      time: DateFormat('hh:mm a').format(now),
      classType: course.courseType.displayName,
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .doc(docId)
          .set(record.toMap(), SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1816),
            behavior: SnackBarBehavior.floating,
            content: Text('${course.code}: Marked as ${status.displayName}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error marking attendance: $e');
    }
  }

  Widget _attendanceCardWithQuickLog(
    Course course,
    String pct,
    String counts,
    Color pctColor,
    double progressFraction,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.code,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFFF2B78A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      course.title,
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFFEDE8E3),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    pct,
                    style: GoogleFonts.jetBrainsMono(
                      color: pctColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
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
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progressFraction.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: const Color(0xFF1E1816),
              valueColor: AlwaysStoppedAnimation<Color>(pctColor),
            ),
          ),
          const SizedBox(height: 10),
          // Quick Log Action Buttons: Present, Absent, Canceled
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _logQuickAttendance(course, AttendanceStatus.attended),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.4), width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'Present',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () => _logQuickAttendance(course, AttendanceStatus.missed),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'Absent',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: InkWell(
                  onTap: () => _logQuickAttendance(course, AttendanceStatus.canceled),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9E8C82).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF9E8C82).withValues(alpha: 0.3), width: 0.8),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFF9E8C82), size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'Cancel',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFF9E8C82),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddRoutineSlotDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    int selectedDay = 1; // Monday
    final startCtrl = TextEditingController(text: '08:00 AM');
    final endCtrl = TextEditingController(text: '09:30 AM');
    final roomCtrl = TextEditingController();
    final teacherCtrl = TextEditingController();
    CourseType selectedType = CourseType.theory;

    final daysList = [
      {'name': 'Monday', 'day': 1},
      {'name': 'Tuesday', 'day': 2},
      {'name': 'Wednesday', 'day': 3},
      {'name': 'Thursday', 'day': 4},
      {'name': 'Friday', 'day': 5},
      {'name': 'Saturday', 'day': 6},
      {'name': 'Sunday', 'day': 7},
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
                            labelText: 'Room / Venue (e.g. LT-1)',
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

  void _showAddAssessmentDialog(BuildContext context) {
    SafeHaptics.selectionClick();
    final coursesAsync = ref.read(coursesStreamProvider);
    final courses = coursesAsync.value ?? [];

    Course? selectedCourse = courses.isNotEmpty ? courses.first : null;
    final nameCtrl = TextEditingController();
    final marksCtrl = TextEditingController(text: '20');
    final weightageCtrl = TextEditingController(text: '10');
    String selectedType = 'quiz';
    DateTime selectedDate = DateTime.now().add(const Duration(days: 2));

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
}
