import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/constants/group_constants.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../models/exam_model.dart';
import '../models/note_model.dart';
import '../models/performance_models.dart';
import '../models/planner_event_model.dart';
import '../models/profile_models.dart';
import '../providers/notes_provider.dart';
import '../providers/performance_provider.dart';
import '../providers/user_profile_provider.dart' hide UserProfile;
import '../providers/nav_provider.dart';
import '../services/exam_service.dart';
import '../services/notification_service.dart';
import '../services/snack_bar_service.dart';
import '../services/assessment_service.dart';
import 'package:collection/collection.dart';
import '../widgets/app_logo.dart';
import '../models/routine_models.dart';
import '../models/syllabus_node.dart';
import 'journal_screen.dart';
import 'attendance_matrix_screen.dart';
import 'routine_screen.dart';
import 'term_performance_screen.dart';
import '../widgets/common/luxury_glass_card.dart';
import '../widgets/assessment_card.dart';
import '../core/theme/app_theme.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/tour_service.dart';
import '../widgets/tour_coach_mark.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Screen for managing exam targets, calendar scheduling, class routines, attendance, and term breaks.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

/// Backwards compatibility alias
typedef ExamsScreen = PlannerScreen;

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  // Onboarding Tour Keys
  final GlobalKey _keyPlannerCalendar = GlobalKey();
  final GlobalKey _keyPlannerAssessments = GlobalKey();
  final GlobalKey _keyPlannerAttendance = GlobalKey();
  bool _hasTriggeredPlannerTour = false;

  void _triggerPlannerTourIfNeeded(BuildContext showcaseContext) {
    final currentTab = ref.read(navigationIndexProvider);
    if (currentTab != 3 || _hasTriggeredPlannerTour) return;
    triggerTourSafely(
      context: showcaseContext,
      section: TourSection.planner,
      keys: [_keyPlannerCalendar, _keyPlannerAssessments, _keyPlannerAttendance],
      onStarted: () => _hasTriggeredPlannerTour = true,
      onSkippedOrEmpty: () => _hasTriggeredPlannerTour = false,
    );
  }

  // Local immediate state for recorded lecture topics to ensure zero-latency card update
  final Map<String, String> _localRecordedTopics = {};

  String _topicKey(DateTime date, String routineId) =>
      '${date.year}_${date.month}_${date.day}_$routineId';

  List<String> _getDynamicSubjectOptions() {
    final userProfile = ref.read(userProfileProvider);
    final group = userProfile.hscGroup;
    final target = userProfile.primaryTarget;

    final dynamicSubjects = GroupConstants.getExamSubjectsForUser(group, target);
    final combined = <String>{
      ...dynamicSubjects,
      'Combined Model Test',
      'Other',
    };
    return combined.toList();
  }
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  DateTime _uniSelectedDay = DateTime.now();
  DateTime _uniFocusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    ref.watch(navigationIndexProvider);
    final userProfile = ref.watch(userProfileProvider);

    // TASK 1: Strict Mode Separation - University assessments view for university students
    if (userProfile.isUniversityStudent) {
      return _buildUniversityAssessmentsScreen(context, userProfile);
    }

    final examsAsync = ref.watch(examsStreamProvider);
    final rawExams = examsAsync.asData?.value ?? [];

    final allExams = List<ExamModel>.from(rawExams)
      ..sort((a, b) => a.date.compareTo(b.date));

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final allCalendarExams = allExams
        .map((e) => UpcomingExam(
              id: e.id,
              examName: e.examName,
              subject: e.subject,
              totalMarks: e.totalMarks,
              targetDate: e.date,
              isAbsent: e.isAbsent,
              isCompleted: e.isCompleted,
            ))
        .toList();

    final upcomingExams = allExams
        .where((e) {
          final examDate = DateTime(e.date.year, e.date.month, e.date.day);
          return (examDate.isAfter(todayStart) || examDate.isAtSameMomentAs(todayStart)) &&
              !e.isCompleted &&
              !e.isAbsent;
        })
        .map((e) => UpcomingExam(
              id: e.id,
              examName: e.examName,
              subject: e.subject,
              totalMarks: e.totalMarks,
              targetDate: e.date,
              isAbsent: e.isAbsent,
              isCompleted: e.isCompleted,
            ))
        .toList();

    final pastExams = allExams
        .where((e) {
          final examDate = DateTime(e.date.year, e.date.month, e.date.day);
          return examDate.isBefore(todayStart) || e.isCompleted || e.isAbsent;
        })
        .map((e) => UpcomingExam(
              id: e.id,
              examName: e.examName,
              subject: e.subject,
              totalMarks: e.totalMarks,
              targetDate: e.date,
              isAbsent: e.isAbsent,
              isCompleted: e.isCompleted,
            ))
        .toList();

    final examRecords = allExams
        .where((e) => e.isCompleted || e.marksObtained > 0 || e.isAbsent)
        .map((e) => ExamRecord(
              id: e.id,
              examName: e.examName,
              subject: e.subject,
              marks: e.marksObtained,
              totalMarks: e.totalMarks,
              meritPosition: e.meritPosition,
              date: e.date,
              isAbsent: e.isAbsent,
            ))
        .toList();

    final pinnedId = userProfile.pinnedExamId;
    UpcomingExam? countdownExam;

    if (pinnedId != null && pinnedId.isNotEmpty) {
      try {
        final pinnedModel = allExams.firstWhere((e) => e.id == pinnedId);
        final pinnedDate = DateTime(pinnedModel.date.year, pinnedModel.date.month, pinnedModel.date.day);
        if (pinnedDate.isAfter(todayStart) || pinnedDate.isAtSameMomentAs(todayStart)) {
          countdownExam = UpcomingExam(
            id: pinnedModel.id,
            examName: pinnedModel.examName,
            subject: pinnedModel.subject,
            totalMarks: pinnedModel.totalMarks,
            targetDate: pinnedModel.date,
            isAbsent: pinnedModel.isAbsent,
            isCompleted: pinnedModel.isCompleted,
          );
        }
      } catch (_) {}
    }

    countdownExam ??= (upcomingExams.isNotEmpty ? upcomingExams.first : null);

    final improvement = ref.watch(performanceImprovementProvider);

    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const emeraldColor = Color(0xFF10B981);

    final selectedDayExams = allCalendarExams.where((e) {
      return e.targetDate.year == _selectedDate.year &&
          e.targetDate.month == _selectedDate.month &&
          e.targetDate.day == _selectedDate.day;
    }).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showLogScoreModal(context, allUpcomingExams: upcomingExams),
        backgroundColor: accentColor,
        foregroundColor: const Color(0xFF110D0C),
        icon: const Icon(Icons.add_task_rounded, size: 20),
        label: const Text(
          'Log Score',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      children: [
                        AppLogo(size: 32),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Exam Calendar & Tracker',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Schedule tests, log scores & monitor growth',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          ref.read(selectedNoteTagProvider.notifier).state = 'Exam Journal';
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JournalScreen()),
                          );
                        },
                        icon: const Icon(Icons.auto_stories_rounded, size: 16, color: Color(0xFFF2B78A)),
                        label: const Text('Journal', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 12, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          side: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showScheduleExamModal(context),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Schedule'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          backgroundColor: accentColor,
                          foregroundColor: const Color(0xFF110D0C),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (countdownExam != null) ...[
                _buildCountdownBanner(
                  countdownExam,
                  cardColor,
                  accentColor,
                  isPinned: countdownExam.id == userProfile.pinnedExamId,
                ),
                const SizedBox(height: 20),
              ],

              _buildVisualCalendar(allCalendarExams, examRecords, cardColor, accentColor),
              const SizedBox(height: 16),

              _buildSelectedDateSection(selectedDayExams, cardColor, accentColor),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Upcoming Target Exams',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${upcomingExams.length} Scheduled',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (upcomingExams.isNotEmpty)
                ...upcomingExams.map((e) => _buildUpcomingExamCard(e, cardColor, accentColor))
              else
                _buildEmptyExamsCard(cardColor),

              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 32),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Past Exams',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${pastExams.length} Total',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (pastExams.isNotEmpty)
                ...pastExams.map((e) => _buildUpcomingExamCard(e, cardColor, accentColor))
              else
                _buildEmptyHistoryCard(cardColor),

              const SizedBox(height: 24),

              if (examRecords.where((r) => !r.isAbsent).length >= 2) ...[
                _buildImprovementIndicatorCard(improvement, cardColor, emeraldColor, accentColor),
                const SizedBox(height: 16),
              ],

              if (examRecords.isNotEmpty) ...[
                _buildMarksTrendChart(examRecords.where((r) => !r.isAbsent).toList(), cardColor, accentColor),
                const SizedBox(height: 16),
                _buildExamHistoryList(examRecords, cardColor),
              ],

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountdownBanner(UpcomingExam exam, Color cardColor, Color accentColor, {bool isPinned = false}) {
    final days = exam.daysRemaining;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPinned
              ? [const Color(0xFF78350F).withValues(alpha: 0.4), const Color(0xFF1C1412)]
              : [cardColor, const Color(0xFF1E3A8A).withValues(alpha: 0.4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPinned ? const Color(0xFFFBBF24).withValues(alpha: 0.5) : accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isPinned ? const Color(0xFFFBBF24) : accentColor).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isPinned ? Icons.push_pin_rounded : Icons.timer_outlined,
              color: isPinned ? const Color(0xFFFBBF24) : accentColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exam.examName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPinned) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFBBF24), width: 0.8),
                        ),
                        child: const Text(
                          'Pinned 📌',
                          style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Subject: ${exam.subject}',
                  style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  days <= 0 ? '0' : '$days',
                  style: const TextStyle(
                    color: Color(0xFF110D0C),
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  days == 1 ? 'DAY LEFT' : 'DAYS LEFT',
                  style: const TextStyle(
                    color: Color(0xFF110D0C),
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisualCalendar(
    List<UpcomingExam> allCalendarExams,
    List<ExamRecord> records,
    Color cardColor,
    Color accentColor,
  ) {
    final monthName = _getMonthName(_focusedMonth.month);
    final year = _focusedMonth.year;
    final daysInMonth = DateTime(year, _focusedMonth.month + 1, 0).day;
    final firstWeekday = DateTime(year, _focusedMonth.month, 1).weekday;

    final isCurrentMonth = _focusedMonth.year == DateTime.now().year && _focusedMonth.month == DateTime.now().month;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '$monthName $year',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _focusedMonth = DateTime.now();
                        _selectedDate = DateTime.now();
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isCurrentMonth ? accentColor.withValues(alpha: 0.15) : const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.today_rounded, size: 14, color: Color(0xFFF2B78A)),
                          SizedBox(width: 4),
                          Text(
                            'Today',
                            style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.blueGrey),
                    onPressed: () {
                      setState(() {
                        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.blueGrey),
                    onPressed: () {
                      setState(() {
                        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((d) => SizedBox(
                      width: 32,
                      child: Text(
                        d,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 42,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              final dayOffset = index - (firstWeekday - 1);
              if (dayOffset < 1 || dayOffset > daysInMonth) {
                return const SizedBox.shrink();
              }

              final cellDate = DateTime(year, _focusedMonth.month, dayOffset);
              final isSelected = cellDate.year == _selectedDate.year &&
                  cellDate.month == _selectedDate.month &&
                  cellDate.day == _selectedDate.day;

              final isToday = cellDate.year == DateTime.now().year &&
                  cellDate.month == DateTime.now().month &&
                  cellDate.day == DateTime.now().day;

              final dayExams = allCalendarExams.where((e) =>
                  e.targetDate.year == cellDate.year &&
                  e.targetDate.month == cellDate.month &&
                  e.targetDate.day == cellDate.day).toList();

              final hasExam = dayExams.isNotEmpty;
              final hasAbsent = dayExams.any((e) => e.isAbsent);
              final hasCompleted = dayExams.any((e) => e.isCompleted && !e.isAbsent);

              Color dotColor = const Color(0xFFF59E0B);
              if (hasAbsent) {
                dotColor = const Color(0xFF94A3B8);
              } else if (hasCompleted) {
                dotColor = const Color(0xFF10B981);
              }

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedDate = cellDate);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor
                        : (hasExam ? accentColor.withValues(alpha: 0.15) : const Color(0xFF170F0D)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? accentColor
                          : (isToday ? const Color(0xFFF59E0B) : (hasExam ? accentColor.withValues(alpha: 0.4) : Colors.transparent)),
                      width: isToday && !isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        '$dayOffset',
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF110D0C)
                              : (hasExam ? Colors.white : Colors.blueGrey.shade400),
                          fontSize: 12,
                          fontWeight: isSelected || hasExam || isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (hasExam)
                        Positioned(
                          bottom: 4,
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF110D0C) : dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDateSection(List<UpcomingExam> selectedDayExams, Color cardColor, Color accentColor) {
    final formatted = '${_selectedDate.day} ${_getMonthName(_selectedDate.month)} ${_selectedDate.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.event_available_rounded, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Schedule for $formatted',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                '${selectedDayExams.length} Exams',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
              ),
            ],
          ),
          if (selectedDayExams.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...selectedDayExams.map((e) {
              final isAbsent = e.isAbsent;
              final isCompleted = e.isCompleted && !isAbsent;

              return InkWell(
                onTap: () => _showExamOptionsModal(context, e),
                child: Container(
                  margin: const EdgeInsets.only(top: 6.0, bottom: 4.0),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isAbsent
                        ? Colors.white.withValues(alpha: 0.03)
                        : const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isAbsent
                          ? Colors.blueGrey.shade700
                          : (isCompleted ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isAbsent
                              ? const Color(0xFF94A3B8)
                              : (isCompleted ? const Color(0xFF10B981) : const Color(0xFFF2B78A)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${e.examName} (${e.subject})',
                          style: TextStyle(
                            color: isAbsent ? Colors.blueGrey.shade400 : Colors.white,
                            fontSize: 12.5,
                            decoration: isAbsent ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (isAbsent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Absent',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else if (isCompleted)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Completed',
                            style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        Text(
                          '${e.totalMarks.toInt()} Marks',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                        ),
                      const SizedBox(width: 6),
                      const Icon(Icons.more_vert_rounded, size: 16, color: Colors.blueGrey),
                    ],
                  ),
                ),
              );
            }),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'No exams scheduled on this date.',
              style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpcomingExamCard(UpcomingExam exam, Color cardColor, Color accentColor) {
    final isAbsent = exam.isAbsent;
    final userProfile = ref.watch(userProfileProvider);
    final isPinnedExamTab = userProfile.pinnedExamId == exam.id;
    final isPinnedHomeTab = userProfile.pinnedHomeExamId == exam.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isAbsent ? cardColor.withValues(alpha: 0.6) : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isPinnedExamTab || isPinnedHomeTab)
              ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
              : (isAbsent ? Colors.blueGrey.shade700 : Colors.white.withValues(alpha: 0.06)),
          width: (isPinnedExamTab || isPinnedHomeTab) ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showExamOptionsModal(context, exam),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isAbsent ? Colors.blueGrey.withValues(alpha: 0.15) : accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isAbsent ? Icons.event_busy_rounded : Icons.assignment_turned_in_outlined,
                    color: isAbsent ? Colors.blueGrey : accentColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              exam.examName,
                              style: TextStyle(
                                color: isAbsent ? Colors.blueGrey.shade300 : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                decoration: isAbsent ? TextDecoration.lineThrough : null,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPinnedExamTab)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Exam Pin 📌',
                                style: TextStyle(color: Color(0xFFFBBF24), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (isPinnedHomeTab)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2B78A).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Home Pin 🏠',
                                style: TextStyle(color: Color(0xFFF2B78A), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (isAbsent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Absent',
                                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            )
                          else if (exam.isRecurring)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${exam.recurringType} (${exam.occurrenceIndex}/${exam.totalOccurrences})',
                                style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${exam.subject} • ${exam.targetDate.day}/${exam.targetDate.month}/${exam.targetDate.year} • ${exam.totalMarks.toInt()} Marks',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: (isPinnedExamTab || isPinnedHomeTab) ? const Color(0xFFFBBF24) : Colors.blueGrey,
                    size: 20,
                  ),
                  color: const Color(0xFF1C1412),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) async {
                    if (value == 'pin_exam') {
                      await ref.read(userProfileProvider.notifier).updatePinnedExams(
                            examTabId: isPinnedExamTab ? null : exam.id,
                            clearExamTab: isPinnedExamTab,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: Text(isPinnedExamTab ? 'Unpinned from Exams Tab' : 'Pinned to Exams Tab!'),
                          ),
                        );
                      }
                    } else if (value == 'pin_home') {
                      await ref.read(userProfileProvider.notifier).updatePinnedExams(
                            homeTabId: isPinnedHomeTab ? null : exam.id,
                            clearHomeTab: isPinnedHomeTab,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: Text(isPinnedHomeTab ? 'Unpinned from Home Dashboard' : 'Pinned to Home Dashboard!'),
                          ),
                        );
                      }
                    } else if (value == 'options') {
                      _showExamOptionsModal(context, exam);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem<String>(
                      value: 'pin_exam',
                      child: Row(
                        children: [
                          Icon(
                            isPinnedExamTab ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                            color: const Color(0xFFFBBF24),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isPinnedExamTab ? 'Unpin from Exams Tab' : '📌 Pin to Exams Tab',
                            style: TextStyle(
                              color: isPinnedExamTab ? const Color(0xFFFBBF24) : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'pin_home',
                      child: Row(
                        children: [
                          Icon(
                            isPinnedHomeTab ? Icons.home_rounded : Icons.home_outlined,
                            color: const Color(0xFFF2B78A),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isPinnedHomeTab ? 'Unpin from Home' : '🏠 Pin to Home Dashboard',
                            style: TextStyle(
                              color: isPinnedHomeTab ? const Color(0xFFF2B78A) : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'options',
                      child: Row(
                        children: [
                          Icon(Icons.tune_rounded, color: Colors.blueGrey, size: 18),
                          SizedBox(width: 10),
                          Text(
                            'Exam Options & Score',
                            style: TextStyle(color: Colors.white, fontSize: 13),
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
      ),
    );
  }

  void _showExamOptionsModal(BuildContext context, UpcomingExam exam) {
    final isAbsent = exam.isAbsent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.examName,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${exam.subject} • ${exam.targetDate.day}/${exam.targetDate.month}/${exam.targetDate.year}',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                ),
                const SizedBox(height: 16),

                ListTile(
                  leading: Icon(
                    isAbsent ? Icons.restore_rounded : Icons.event_busy_rounded,
                    color: isAbsent ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                  title: Text(
                    isAbsent ? 'Restore / Unmark Absent' : 'Mark as Unattended / Absent',
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    isAbsent ? 'Move back to active upcoming exams' : 'Mark this exam date as absent without recording a score',
                    style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(examServiceProvider).markAbsent(
                          examId: exam.id,
                          isAbsent: !isAbsent,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: isAbsent ? const Color(0xFF10B981) : Colors.blueGrey.shade800,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          content: Text(
                            isAbsent
                                ? 'Restored "${exam.examName}" to upcoming exams.'
                                : 'Marked "${exam.examName}" as absent.',
                          ),
                        ),
                      );
                    }
                  },
                ),

                if (!isAbsent)
                  ListTile(
                    leading: const Icon(Icons.task_alt_rounded, color: Color(0xFF10B981)),
                    title: const Text('Log Score For This Exam', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showLogScoreModal(context, prefilledExam: exam);
                    },
                  ),

                ListTile(
                  leading: const Icon(Icons.event_repeat_rounded, color: Color(0xFFF59E0B)),
                  title: const Text('Shift Future Dates in Series', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                  subtitle: Text(
                    'Bulk shift all subsequent scheduled dates in this exam series',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showShiftFutureDatesModal(context, exam);
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Color(0xFFF2B78A)),
                  title: const Text('Edit Scheduled Exam', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showScheduleExamModal(context, existingExam: exam);
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.pinkAccent),
                  title: const Text('Delete Exam', style: TextStyle(color: Colors.white, fontSize: 13.5)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await ref.read(examServiceProvider).deleteExam(exam.id);
                    ref.read(upcomingExamsProvider.notifier).deleteExam(exam.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFFEF4444),
                          behavior: SnackBarBehavior.floating,
                          content: Text('Exam removed.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showScheduleExamModal(BuildContext context, {UpcomingExam? existingExam}) {
    final userProfile = ref.read(userProfileProvider);
    final List<String> dynamicSubjects = [
      ...GroupConstants.getExamSubjectsForUser(userProfile.hscGroup, userProfile.primaryTarget),
      'Combined Model Test',
      'Other',
    ];

    final isEditing = existingExam != null;
    final nameCtrl = TextEditingController(text: existingExam?.examName ?? 'BUET Weekly Model Test');
    final marksCtrl = TextEditingController(text: existingExam?.totalMarks.toInt().toString() ?? '100');
    final occurrencesCtrl = TextEditingController(text: '3');

    String selectedSubject;
    String customSubject = '';

    if (isEditing) {
      if (dynamicSubjects.contains(existingExam.subject)) {
        selectedSubject = existingExam.subject;
      } else {
        selectedSubject = 'Other';
        customSubject = existingExam.subject;
      }
    } else {
      selectedSubject = dynamicSubjects.first;
    }

    final customSubjCtrl = TextEditingController(text: customSubject);
    DateTime selectedDate = existingExam?.targetDate ?? DateTime.now().add(const Duration(days: 7));
    String recurringType = isEditing ? 'None' : 'Weekly';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1412),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                isEditing ? 'Edit Scheduled Exam' : 'Schedule New Exam',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Exam Name',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: dynamicSubjects.contains(selectedSubject) ? selectedSubject : 'Other',
                      dropdownColor: const Color(0xFF1C1412),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                      items: dynamicSubjects.map((subj) {
                        return DropdownMenuItem(value: subj, child: Text(subj));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedSubject = val);
                        }
                      },
                    ),
                    if (selectedSubject == 'Other') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: customSubjCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          labelText: 'Custom Subject Name',
                          hintText: 'Enter subject name',
                          labelStyle: TextStyle(color: Colors.blueGrey),
                          filled: true,
                          fillColor: Color(0xFF170F0D),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: marksCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Total Marks',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) {
                          setModalState(() => selectedDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF170F0D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueGrey.shade700),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (!isEditing) ...[
                      const SizedBox(height: 14),
                      const Text('RECURRING TYPE', style: TextStyle(color: Colors.blueGrey, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Row(
                        children: ['None', 'Weekly', 'Monthly'].map((type) {
                          final isSel = recurringType == type;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setModalState(() => recurringType = type),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel ? const Color(0xFFF2B78A) : const Color(0xFF170F0D),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  type,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: isSel ? const Color(0xFF110D0C) : Colors.blueGrey,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (recurringType != 'None') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: occurrencesCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Number of Occurrences',
                            hintText: 'e.g. 3 for 3 recurring tests',
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            filled: true,
                            fillColor: Color(0xFF170F0D),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recurringType == 'Monthly'
                              ? 'Generates separate instances (e.g. "Exam 1", "Exam 2") monthly.'
                              : 'Generates separate instances (e.g. "Exam 1", "Exam 2") 7 days apart.',
                          style: TextStyle(color: Colors.amber.shade300, fontSize: 10.5),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              actions: [
                if (isEditing) ...[
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.pinkAccent),
                    tooltip: 'Delete Exam',
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      await ref.read(examServiceProvider).deleteExam(existingExam.id);
                      ref.read(upcomingExamsProvider.notifier).deleteExam(existingExam.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFFEF4444),
                            behavior: SnackBarBehavior.floating,
                            content: Text('Scheduled exam deleted successfully.'),
                          ),
                        );
                      }
                    },
                  ),
                  const Spacer(),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final resolvedSubj = (selectedSubject == 'Other')
                        ? (customSubjCtrl.text.trim().isNotEmpty ? customSubjCtrl.text.trim() : 'General')
                        : selectedSubject;
                    final total = double.tryParse(marksCtrl.text) ?? 100.0;
                    final count = int.tryParse(occurrencesCtrl.text) ?? 1;

                    Navigator.pop(dialogCtx);

                    if (name.isNotEmpty) {
                      SafeHaptics.heavyImpact();
                      final examService = ref.read(examServiceProvider);

                      if (isEditing) {
                        final originalDate = existingExam.targetDate;
                        final dateChanged = selectedDate.year != originalDate.year ||
                            selectedDate.month != originalDate.month ||
                            selectedDate.day != originalDate.day;

                        await examService.updateExam(
                          ExamModel(
                            id: existingExam.id,
                            examName: name,
                            subject: resolvedSubj,
                            date: selectedDate,
                            totalMarks: total,
                            marksObtained: 0,
                            meritPosition: 0,
                            isCompleted: false,
                            isAbsent: false,
                          ),
                        );
                        ref.read(upcomingExamsProvider.notifier).updateSingleExam(
                              existingExam.copyWith(
                                examName: name,
                                subject: resolvedSubj,
                                totalMarks: total,
                                targetDate: selectedDate,
                              ),
                            );

                        if (dateChanged && context.mounted) {
                          final shiftDuration = selectedDate.difference(originalDate);
                          final shiftDays = (shiftDuration.inHours / 24).round();

                          if (shiftDays != 0) {
                            final shouldShiftFuture = await showDialog<bool>(
                              context: context,
                              builder: (shiftCtx) => AlertDialog(
                                backgroundColor: const Color(0xFF1C1412),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                title: const Row(
                                  children: [
                                    Icon(Icons.event_repeat_rounded, color: Color(0xFFF2B78A), size: 22),
                                    SizedBox(width: 8),
                                    Text('Shift Future Exams?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                content: Text(
                                  'You shifted "$name" by ${shiftDays > 0 ? "+$shiftDays" : "$shiftDays"} day(s).\n\nWould you like to shift all subsequent exams in this series by the same amount?',
                                  style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(shiftCtx, false),
                                    child: const Text('Only This Exam', style: TextStyle(color: Colors.blueGrey)),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(shiftCtx, true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF2B78A),
                                      foregroundColor: const Color(0xFF110D0C),
                                    ),
                                    child: const Text('Shift All Future', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            );

                            if (shouldShiftFuture == true) {
                              final shiftedCount = await examService.shiftSubsequentExamDates(
                                baseSeriesName: name,
                                originalDate: originalDate,
                                shiftDuration: shiftDuration,
                                currentExamId: existingExam.id,
                              );

                              if (context.mounted && shiftedCount > 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFF2B78A),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    content: Text(
                                      '🗓️ Shifted $shiftedCount subsequent exam(s) in series by ${shiftDays > 0 ? "+$shiftDays" : "$shiftDays"} day(s).',
                                      style: const TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              content: Text('Updated "$name" successfully.'),
                            ),
                          );
                        }
                      } else {
                        final baseClean = ExamService.extractBaseName(name);
                        final highestExisting = await examService.getHighestExamNumber(baseClean);
                        final totalOccurrences = (recurringType != 'None') ? count.clamp(1, 52) : 1;

                        final List<ExamModel> batchExams = [];

                        for (int i = 0; i < totalOccurrences; i++) {
                          DateTime date = selectedDate;
                          if (recurringType == 'Weekly') {
                            date = selectedDate.add(Duration(days: i * 7));
                          } else if (recurringType == 'Monthly') {
                            date = DateTime(selectedDate.year, selectedDate.month + i, selectedDate.day);
                          }

                          final nextIndex = (highestExisting > 0 || totalOccurrences > 1)
                              ? (highestExisting + i + 1)
                              : 0;
                          final sequentialName = nextIndex > 0 ? '$baseClean $nextIndex' : baseClean;

                          batchExams.add(
                            ExamModel(
                              id: '',
                              examName: sequentialName,
                              subject: resolvedSubj,
                              date: date,
                              totalMarks: total,
                              isCompleted: false,
                              isAbsent: false,
                            ),
                          );
                        }

                        await examService.addExamsBatch(batchExams);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              content: Text(
                                totalOccurrences > 1
                                    ? 'Scheduled ${batchExams.first.examName} to ${batchExams.last.examName} ($totalOccurrences tests).'
                                    : 'Scheduled ${batchExams.first.examName}.',
                              ),
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF2B78A)),
                  child: Text(
                    isEditing ? 'Save Changes' : 'Save Exam',
                    style: const TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showShiftFutureDatesModal(BuildContext context, UpcomingExam exam) {
    int daysToShift = 1;
    final shiftDaysCtrl = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C1412),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.event_repeat_rounded, color: Color(0xFFF59E0B), size: 22),
                  SizedBox(width: 10),
                  Text(
                    'Shift Future Dates',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shift all uncompleted exams scheduled after "${exam.examName}" in this series by a chosen number of days.',
                    style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'QUICK SELECT SHIFT',
                    style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [1, 2, 3, 7, 14, -1, -7].map((days) {
                      final isSel = daysToShift == days;
                      return ChoiceChip(
                        label: Text(days > 0 ? '+$days d' : '$days d'),
                        selected: isSel,
                        selectedColor: const Color(0xFFF2B78A),
                        backgroundColor: const Color(0xFF170F0D),
                        labelStyle: TextStyle(
                          color: isSel ? const Color(0xFF110D0C) : Colors.blueGrey.shade300,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (sel) {
                          if (sel) {
                            setModalState(() {
                              daysToShift = days;
                              shiftDaysCtrl.text = days.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: shiftDaysCtrl,
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Days to shift (+ for later, - for earlier)',
                      labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null) {
                        setModalState(() {
                          daysToShift = parsed;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
                ),
                ElevatedButton(
                  onPressed: daysToShift == 0
                      ? null
                      : () async {
                          Navigator.pop(dialogCtx);
                          final shiftDuration = Duration(days: daysToShift);
                          final examService = ref.read(examServiceProvider);

                          final shiftedCount = await examService.shiftSubsequentExamDates(
                            baseSeriesName: exam.examName,
                            originalDate: exam.targetDate,
                            shiftDuration: shiftDuration,
                            currentExamId: exam.id,
                          );

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                content: Text(
                                  shiftedCount > 0
                                      ? '🗓️ Shifted $shiftedCount subsequent exam(s) by ${daysToShift > 0 ? "+$daysToShift" : "$daysToShift"} day(s) via WriteBatch.'
                                      : 'No subsequent exams found to shift.',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF2B78A),
                    foregroundColor: const Color(0xFF110D0C),
                  ),
                  child: const Text('Apply Shift', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showLogScoreModal(BuildContext context, {UpcomingExam? prefilledExam, List<UpcomingExam>? allUpcomingExams}) {
    final userProfile = ref.read(userProfileProvider);
    final List<String> dynamicSubjects = [
      ...GroupConstants.getExamSubjectsForUser(userProfile.hscGroup, userProfile.primaryTarget),
      'Combined Model Test',
      'Other',
    ];

    final examsAsync = ref.read(examsStreamProvider);
    final allExams = examsAsync.asData?.value ?? [];
    final List<UpcomingExam> upcomingList = allUpcomingExams ?? allExams
        .where((e) => !e.isCompleted && !e.isAbsent)
        .map((e) => UpcomingExam(
              id: e.id,
              examName: e.examName,
              subject: e.subject,
              totalMarks: e.totalMarks,
              targetDate: e.date,
            ))
        .toList();

    String selectedExamOption = prefilledExam != null
        ? prefilledExam.id
        : (upcomingList.isNotEmpty ? upcomingList.first.id : 'Other');

    final UpcomingExam? initialPicked = prefilledExam ??
        (upcomingList.any((e) => e.id == selectedExamOption)
            ? upcomingList.firstWhere((e) => e.id == selectedExamOption)
            : null);

    final nameCtrl = TextEditingController(text: initialPicked?.examName ?? '');
    final marksCtrl = TextEditingController();
    final totalMarksCtrl = TextEditingController(text: initialPicked?.totalMarks.toInt().toString() ?? '100');
    final meritCtrl = TextEditingController();

    String selectedSubject = (initialPicked != null && dynamicSubjects.contains(initialPicked.subject))
        ? initialPicked.subject
        : 'Other';
    final customSubjCtrl = TextEditingController(
      text: (initialPicked != null && !dynamicSubjects.contains(initialPicked.subject))
          ? initialPicked.subject
          : '',
    );

    DateTime customExamDate = initialPicked?.targetDate ?? DateTime.now();
    final List<_JournalInputItem> journalInputs = [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final isOtherSelected = selectedExamOption == 'Other';

          return AlertDialog(
            backgroundColor: const Color(0xFF1C1412),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Log Exam Result',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: (upcomingList.any((e) => e.id == selectedExamOption) || selectedExamOption == 'Other')
                        ? selectedExamOption
                        : 'Other',
                    dropdownColor: const Color(0xFF1C1412),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Select Scheduled Exam',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                    items: [
                      ...upcomingList.map((e) => DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              '${e.examName} (${e.subject})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )),
                      const DropdownMenuItem(
                        value: 'Other',
                        child: Text('Other / Custom Exam'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedExamOption = val;
                          if (val != 'Other') {
                            final picked = upcomingList.firstWhere((e) => e.id == val);
                            nameCtrl.text = picked.examName;
                            totalMarksCtrl.text = picked.totalMarks.toInt().toString();
                            customExamDate = picked.targetDate;
                            if (dynamicSubjects.contains(picked.subject)) {
                              selectedSubject = picked.subject;
                              customSubjCtrl.text = '';
                            } else {
                              selectedSubject = 'Other';
                              customSubjCtrl.text = picked.subject;
                            }
                          } else {
                            nameCtrl.text = '';
                            totalMarksCtrl.text = '100';
                            selectedSubject = 'Other';
                            customSubjCtrl.text = '';
                            customExamDate = DateTime.now();
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  if (isOtherSelected) ...[
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Custom Exam Title',
                        hintText: 'e.g. Model Test 01 / Final Mock',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: customExamDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setModalState(() => customExamDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF170F0D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueGrey.shade700),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Exam Date: ${customExamDate.day}/${customExamDate.month}/${customExamDate.year}',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5),
                            ),
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  DropdownButtonFormField<String>(
                    initialValue: dynamicSubjects.contains(selectedSubject) ? selectedSubject : 'Other',
                    dropdownColor: const Color(0xFF1C1412),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                    items: dynamicSubjects.map((subj) {
                      return DropdownMenuItem(value: subj, child: Text(subj));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedSubject = val);
                      }
                    },
                  ),

                  if (selectedSubject == 'Other') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customSubjCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Custom Subject Name',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: marksCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Marks Obtained',
                            hintText: 'e.g. 85',
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            filled: true,
                            fillColor: Color(0xFF170F0D),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: totalMarksCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Total Marks',
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            filled: true,
                            fillColor: Color(0xFF170F0D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: meritCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Merit Position (Optional)',
                      hintText: 'e.g. 45',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_stories_rounded, color: Color(0xFFF2B78A), size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Exam Journal',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Add Entry',
                        color: const Color(0xFF170F0D),
                        onSelected: (type) {
                          setModalState(() {
                            journalInputs.add(_JournalInputItem(type: type, controller: TextEditingController()));
                          });
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'mistake',
                            child: Row(
                              children: [
                                Text('🔴 Add Mistake', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'tip',
                            child: Row(
                              children: [
                                Text('💡 Add Tip / Trick', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.add_rounded, color: Color(0xFFF2B78A), size: 15),
                              SizedBox(width: 4),
                              Text('Add Note', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (journalInputs.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Log mistakes or shortcuts learned to review in Exam Journal.',
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11, fontStyle: FontStyle.italic),
                    ),
                  ],
                  for (int i = 0; i < journalInputs.length; i++) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: journalInputs[i].type == 'mistake'
                              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                              : const Color(0xFF10B981).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'mistake',
                                    label: Text('🔴 Mistake', style: TextStyle(fontSize: 9.5)),
                                  ),
                                  ButtonSegment(
                                    value: 'tip',
                                    label: Text('💡 Tip/Trick', style: TextStyle(fontSize: 9.5)),
                                  ),
                                ],
                                selected: {journalInputs[i].type},
                                onSelectionChanged: (newSelection) {
                                  setModalState(() {
                                    journalInputs[i].type = newSelection.first;
                                  });
                                },
                                style: const ButtonStyle(
                                  visualDensity: VisualDensity.compact,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    journalInputs[i].controller.dispose();
                                    journalInputs.removeAt(i);
                                  });
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4.0),
                                  child: Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: journalInputs[i].controller,
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 2,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: journalInputs[i].type == 'mistake'
                                  ? 'What mistake did you make in this test?'
                                  : 'Shortcut rule, formula, or tip learned...',
                              hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 11),
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim().isNotEmpty
                      ? nameCtrl.text.trim()
                      : (isOtherSelected ? 'Custom Exam' : 'Exam');
                  final resolvedSubj = (selectedSubject == 'Other')
                      ? (customSubjCtrl.text.trim().isNotEmpty ? customSubjCtrl.text.trim() : 'General')
                      : selectedSubject;
                  final marks = double.tryParse(marksCtrl.text) ?? 0.0;
                  final total = double.tryParse(totalMarksCtrl.text) ?? 100.0;
                  final merit = int.tryParse(meritCtrl.text) ?? 0;

                  final journalEntries = journalInputs
                      .map((item) => JournalEntry(
                            type: item.type,
                            content: item.controller.text.trim(),
                          ))
                      .where((e) => e.content.isNotEmpty)
                      .toList();

                  Navigator.pop(ctx);
                  SafeHaptics.heavyImpact();

                  final examService = ref.read(examServiceProvider);

                  if (selectedExamOption != 'Other' && selectedExamOption.isNotEmpty) {
                    await examService.logScore(
                      examId: selectedExamOption,
                      marksObtained: marks,
                      meritPosition: merit,
                      journalEntries: journalEntries,
                    );
                    ref.read(upcomingExamsProvider.notifier).deleteExam(selectedExamOption);
                  } else {
                    await examService.addExam(
                      ExamModel(
                        id: '',
                        examName: name,
                        subject: resolvedSubj,
                        date: customExamDate,
                        totalMarks: total,
                        marksObtained: marks,
                        meritPosition: merit,
                        isCompleted: true,
                        isAbsent: false,
                        journalEntries: journalEntries,
                      ),
                    );
                  }

                  final record = ExamRecord(
                    id: 'rec_${DateTime.now().millisecondsSinceEpoch}',
                    examName: name,
                    subject: resolvedSubj,
                    marks: marks,
                    totalMarks: total,
                    meritPosition: merit,
                    date: customExamDate,
                    isAbsent: false,
                  );

                  ref.read(examRecordsProvider.notifier).addRecord(record);

                  // Sync exam reflections/mistakes into unified Journal & Notes module
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null && journalEntries.isNotEmpty) {
                    final noteService = ref.read(noteServiceProvider);
                    for (final entry in journalEntries) {
                      final typeLabel = entry.type == 'mistake' ? 'Mistake Analysis' : 'Exam Reflection';
                      final noteTitle = '$typeLabel: $name ($resolvedSubj)';
                      final noteContent = '${entry.content}\n\nExam Score: $marks / $total${merit > 0 ? ' (Merit: $merit)' : ''}';
                      await noteService.addNote(
                        uid,
                        NoteModel(
                          id: '',
                          title: noteTitle,
                          content: noteContent,
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                          isPinned: false,
                          tags: [
                            'Exam Journal',
                            entry.type == 'mistake' ? 'Mistake' : 'General',
                          ],
                        ),
                      );
                    }
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: Text('Logged result for "$name" ($marks / $total)'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF2B78A)),
                child: const Text(
                  'Save Record',
                  style: TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditLoggedScoreModal(BuildContext context, ExamRecord record) {
    final userProfile = ref.read(userProfileProvider);
    final List<String> dynamicSubjects = [
      ...GroupConstants.getExamSubjectsForUser(userProfile.hscGroup, userProfile.primaryTarget),
      'Combined Model Test',
      'Other',
    ];

    final nameCtrl = TextEditingController(text: record.examName);
    final marksCtrl = TextEditingController(text: record.marks.toStringAsFixed(record.marks.truncateToDouble() == record.marks ? 0 : 1));
    final totalMarksCtrl = TextEditingController(text: record.totalMarks.toStringAsFixed(record.totalMarks.truncateToDouble() == record.totalMarks ? 0 : 1));
    final meritCtrl = TextEditingController(text: record.meritPosition > 0 ? record.meritPosition.toString() : '');

    String selectedSubject = dynamicSubjects.contains(record.subject) ? record.subject : 'Other';
    final customSubjCtrl = TextEditingController(text: !dynamicSubjects.contains(record.subject) ? record.subject : '');
    DateTime examDate = record.date;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1412),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text(
              'Edit Logged Score',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Exam Name',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: dynamicSubjects.contains(selectedSubject) ? selectedSubject : 'Other',
                    dropdownColor: const Color(0xFF1C1412),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Subject',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                    items: dynamicSubjects.map((subj) {
                      return DropdownMenuItem(value: subj, child: Text(subj));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() => selectedSubject = val);
                      }
                    },
                  ),
                  if (selectedSubject == 'Other') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: customSubjCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Custom Subject Name',
                        labelStyle: TextStyle(color: Colors.blueGrey),
                        filled: true,
                        fillColor: Color(0xFF170F0D),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: examDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 730)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModalState(() => examDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blueGrey.shade700),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Date: ${examDate.day}/${examDate.month}/${examDate.year}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5),
                          ),
                          const Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: marksCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Marks Obtained',
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            filled: true,
                            fillColor: Color(0xFF170F0D),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: totalMarksCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Total Marks',
                            labelStyle: TextStyle(color: Colors.blueGrey),
                            filled: true,
                            fillColor: Color(0xFF170F0D),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: meritCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'Merit Position',
                      hintText: 'e.g. 45',
                      labelStyle: TextStyle(color: Colors.blueGrey),
                      filled: true,
                      fillColor: Color(0xFF170F0D),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : record.examName;
                  final resolvedSubj = (selectedSubject == 'Other')
                      ? (customSubjCtrl.text.trim().isNotEmpty ? customSubjCtrl.text.trim() : 'General')
                      : selectedSubject;
                  final marks = double.tryParse(marksCtrl.text) ?? record.marks;
                  final total = double.tryParse(totalMarksCtrl.text) ?? record.totalMarks;
                  final merit = int.tryParse(meritCtrl.text) ?? 0;

                  Navigator.pop(dialogCtx);

                  final updatedRecord = record.copyWith(
                    examName: name,
                    subject: resolvedSubj,
                    marks: marks,
                    totalMarks: total,
                    meritPosition: merit,
                    date: examDate,
                  );

                  await ref.read(examServiceProvider).updateExam(
                        ExamModel(
                          id: record.id,
                          examName: name,
                          subject: resolvedSubj,
                          date: examDate,
                          totalMarks: total,
                          marksObtained: marks,
                          meritPosition: merit,
                          isCompleted: true,
                          isAbsent: false,
                        ),
                      );

                  ref.read(examRecordsProvider.notifier).updateRecord(updatedRecord);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: Text('Updated record for "$name".'),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF2B78A)),
                child: const Text(
                  'Save Changes',
                  style: TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExamHistoryList(List<ExamRecord> records, Color cardColor) {
    final sorted = List<ExamRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      children: sorted.map((r) {
        final isAbsent = r.isAbsent;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isAbsent ? cardColor.withValues(alpha: 0.6) : cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isAbsent ? Colors.blueGrey.shade700 : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.examName,
                            style: TextStyle(
                              color: isAbsent ? Colors.blueGrey.shade300 : Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              decoration: isAbsent ? TextDecoration.lineThrough : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAbsent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Absent',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9.5, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${r.subject} • ${r.date.day}/${r.date.month}/${r.date.year}',
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isAbsent) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${r.marks.toStringAsFixed(r.marks.truncateToDouble() == r.marks ? 0 : 1)}/${r.totalMarks.toStringAsFixed(r.totalMarks.truncateToDouble() == r.totalMarks ? 0 : 1)} (${r.percentage.toStringAsFixed(1)}%)',
                      style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    if (r.meritPosition > 0)
                      Text(
                        'Merit #${r.meritPosition}',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10.5),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Color(0xFFF2B78A), size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Edit Marks',
                onPressed: () => _showEditLoggedScoreModal(context, r),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.pinkAccent, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete Record',
                onPressed: () async {
                  await ref.read(examServiceProvider).deleteExam(r.id);
                  ref.read(examRecordsProvider.notifier).deleteRecord(r.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFFEF4444),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: Text('Deleted record for "${r.examName}".'),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyExamsCard(Color cardColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
      child: const Center(
        child: Text('No upcoming target exams. Tap Schedule above to add one.', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
      ),
    );
  }

  Widget _buildEmptyHistoryCard(Color cardColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
      child: const Center(
        child: Text('No exam records logged yet. Use Log Score to record test results.', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
      ),
    );
  }

  Widget _buildImprovementIndicatorCard(PerformanceImprovement imp, Color cardColor, Color emeraldColor, Color accentColor) {
    const roseColor = Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Row(
                children: [
                  Icon(
                    imp.marksDelta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    color: imp.isMarksImproved ? emeraldColor : roseColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text('SCORE PROGRESS', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${imp.marksDelta >= 0 ? '+' : ''}${imp.marksDelta.toStringAsFixed(1)}%',
                style: TextStyle(color: imp.isMarksImproved ? emeraldColor : roseColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(width: 1, height: 30, color: Colors.blueGrey.shade700),
          Column(
            children: [
              Row(
                children: [
                  Icon(
                    imp.meritDelta >= 0 ? Icons.emoji_events_rounded : Icons.arrow_downward_rounded,
                    color: imp.isMeritImproved ? emeraldColor : roseColor,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text('MERIT RANK PROGRESS', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                imp.meritDelta > 0
                    ? '+${imp.meritDelta} Ranks'
                    : (imp.meritDelta < 0 ? '${imp.meritDelta} Ranks' : 'Same Rank'),
                style: TextStyle(color: imp.isMeritImproved ? emeraldColor : roseColor, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMarksTrendChart(List<ExamRecord> records, Color cardColor, Color accentColor) {
    final sorted = List<ExamRecord>.from(records)..sort((a, b) => a.date.compareTo(b.date));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Score Progress Trend (%)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: sorted.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.percentage)).toList(),
                    isCurved: true,
                    color: accentColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1) % 12];
  }

  void _showCreateAssessmentModal(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please add at least one course first in the Courses tab.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => CreateAssessmentDialog(courses: courses),
    );
  }

  /// =========================================================================
  /// TASK 1: ASSESSMENT STATUS & POSTPONED WORKFLOW
  /// =========================================================================

  Future<void> _handleSemesterDatesPicker(
    BuildContext context,
    String uid,
    HolidaySettings holidaySettings,
  ) async {
    SafeHaptics.lightImpact();
    final initialRange = (holidaySettings.semesterStart != null && holidaySettings.semesterEnd != null)
        ? DateTimeRange(start: holidaySettings.semesterStart!, end: holidaySettings.semesterEnd!)
        : DateTimeRange(start: DateTime.now(), end: DateTime.now().add(const Duration(days: 120)));

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDateRange: initialRange,
      helpText: 'SELECT ACTIVE SEMESTER DATE RANGE',
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF2B78A),
              onPrimary: Color(0xFF110D0C),
              surface: Color(0xFF1C1412),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('holidays')
          .set({
        'semesterStart': Timestamp.fromDate(picked.start),
        'semesterEnd': Timestamp.fromDate(picked.end),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'semester_start': Timestamp.fromDate(picked.start),
        'semester_end': Timestamp.fromDate(picked.end),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Semester range saved: ${picked.start.day}/${picked.start.month} - ${picked.end.day}/${picked.end.month}/${picked.end.year}'),
          ),
        );
      }
    }
  }

  void _showUnifiedCreateSheet(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
  ) {
    SafeHaptics.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Create New Item',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: const Color(0xFF170F0D),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF2B78A), size: 20),
                  ),
                  title: const Text(
                    'New Assessment (CT / Exam)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Class test, quiz, term final or lab viva',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreateAssessmentModal(context, courseDocs);
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: const Color(0xFF170F0D),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event_note_rounded, color: Color(0xFF10B981), size: 20),
                  ),
                  title: const Text(
                    'New General Event',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    'Club activities, workshops, meetings or reminders',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreateEventModal(context);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Mark or toggle status as 'Attended' immediately without requiring marks entry
  Future<void> _handleAssessmentAttended(
    BuildContext context,
    String uid,
    Assessment assessment,
    String courseCode,
  ) async {
    SafeHaptics.lightImpact();
    try {
      final isCurrentlyAttended = assessment.isAttended;
      final newStatus = isCurrentlyAttended ? null : 'Attended';

      await AssessmentService().updateAssessmentStatus(
        uid: uid,
        courseId: assessment.courseId,
        assessmentId: assessment.id,
        status: newStatus,
      );

      if (context.mounted) {
        if (newStatus == null) {
          SnackBarService.showInfo(
            context,
            'Reset ${assessment.name} to scheduled.',
          );
        } else {
          SnackBarService.showSuccess(
            context,
            'Marked ${assessment.name} as Attended.',
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling assessment attended: $e');
    }
  }

  /// Optional Add / Edit Marks Modal
  Future<void> _showAddEditMarksModal(
    BuildContext context,
    String uid,
    Assessment assessment,
    String courseCode,
  ) async {
    final obtainedCtrl = TextEditingController(
      text: (assessment.obtainedMarks ?? 0) > 0 ? assessment.obtainedMarks.toString() : '',
    );
    final totalCtrl = TextEditingController(text: assessment.totalMarks.toString());
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.grade_rounded, color: Color(0xFF10B981), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Add / Edit Marks: ${assessment.name}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Course: $courseCode • Weightage: ${assessment.weightage.toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: obtainedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Marks Obtained',
                  labelStyle: const TextStyle(color: Color(0xFFF2B78A), fontSize: 13),
                  hintText: 'e.g. 17.5',
                  hintStyle: TextStyle(color: Colors.blueGrey.shade600),
                  filled: true,
                  fillColor: const Color(0xFF170F0D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.grade_rounded, color: Color(0xFFF2B78A), size: 18),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter marks obtained';
                  final num = double.tryParse(val.trim());
                  if (num == null || num < 0) return 'Enter a valid positive number';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: totalCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Total Marks',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF170F0D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.format_list_numbered_rounded, color: Colors.blueGrey, size: 18),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Enter total marks';
                  final num = double.tryParse(val.trim());
                  if (num == null || num <= 0) return 'Total marks must be > 0';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final obtained = double.parse(obtainedCtrl.text.trim());
              final total = double.parse(totalCtrl.text.trim());

              Navigator.pop(dialogCtx);
              SafeHaptics.lightImpact();

              try {
                final courseRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('courses')
                    .doc(assessment.courseId);

                final snap = await courseRef.get();
                if (snap.exists) {
                  final data = snap.data();
                  final rawAss = data?['assessments'];
                  List<dynamic> items = [];
                  if (rawAss is List) {
                    items = List.from(rawAss);
                  } else if (rawAss is Map) {
                    items = rawAss.values.toList();
                  }

                  bool found = false;
                  for (int i = 0; i < items.length; i++) {
                    if (items[i] is Map && items[i]['id'] == assessment.id) {
                      final updated = Map<String, dynamic>.from(items[i]);
                      updated['obtainedMarks'] = obtained;
                      updated['totalMarks'] = total;
                      updated['status'] = 'Attended';
                      items[i] = updated;
                      found = true;
                      break;
                    }
                  }

                  if (!found) {
                    final updatedAssessment = assessment.copyWith(
                      obtainedMarks: obtained,
                      totalMarks: total,
                      status: 'Attended',
                    );
                    items.add(updatedAssessment.toMap());
                  }

                  await courseRef.update({
                    'assessments': items,
                    'lastUpdated': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    SnackBarService.showSuccess(
                      context,
                      'Recorded ${obtained.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} for ${assessment.name}',
                    );
                  }
                }
              } catch (e) {
                debugPrint('Error recording assessment marks: $e');
              }
            },
            child: const Text('Save Marks', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Edit title, total marks, or weightage for an assessment
  /// Edit title, total marks, weightage, or topics covered for an assessment
  Future<void> _showEditAssessmentDetailsModal(
    BuildContext context,
    String uid,
    Assessment assessment,
  ) async {
    final titleCtrl = TextEditingController(text: assessment.name);
    final totalMarksCtrl = TextEditingController(text: assessment.totalMarks.toString());
    final weightageCtrl = TextEditingController(text: assessment.weightage.toString());
    final topicsCtrl = TextEditingController(text: assessment.syllabusSummary ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Color(0xFFF2B78A), size: 20),
            SizedBox(width: 8),
            Text(
              'Edit Assessment Details',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: titleCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Assessment Title',
                    labelStyle: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF170F0D),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter title' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: topicsCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Topics / Syllabus Covered (Optional)',
                    labelStyle: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12),
                    hintText: 'e.g., K-Maps, Quine-McCluskey, Multiplexers',
                    hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF170F0D),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: totalMarksCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Total Marks',
                          labelStyle: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) {
                          final val = double.tryParse(v?.trim() ?? '');
                          if (val == null || val <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: weightageCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Weightage (%)',
                          labelStyle: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) {
                          final val = double.tryParse(v?.trim() ?? '');
                          if (val == null || val < 0) return 'Must be >= 0';
                          return null;
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
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              final newTitle = titleCtrl.text.trim();
              final newTopics = topicsCtrl.text.trim();
              final newTotal = double.parse(totalMarksCtrl.text.trim());
              final newWeight = double.parse(weightageCtrl.text.trim());

              Navigator.pop(dialogCtx);
              SafeHaptics.lightImpact();

              final updatedAssessment = assessment.copyWith(
                name: newTitle,
                totalMarks: newTotal,
                weightage: newWeight,
                syllabusSummary: newTopics.isNotEmpty ? newTopics : null,
              );

              try {
                await AssessmentService().updateAssessment(
                  uid: uid,
                  assessment: updatedAssessment,
                );

                if (context.mounted) {
                  SnackBarService.showSuccess(context, 'Updated assessment details.');
                }
              } catch (e) {
                debugPrint('Error updating assessment: $e');
              }
            },
            child: const Text('Save Details', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Delete assessment from course in Firestore
  Future<void> _showDeleteAssessmentConfirmation(
    BuildContext context,
    String uid,
    Assessment assessment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text('Delete Assessment?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${assessment.name}"? This assessment will be permanently removed.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SafeHaptics.mediumImpact();
      try {
        await AssessmentService().deleteAssessment(
          uid: uid,
          courseId: assessment.courseId,
          assessmentId: assessment.id,
        );

        if (context.mounted) {
          SnackBarService.showSuccess(context, 'Deleted "${assessment.name}"');
        }
      } catch (e) {
        debugPrint('Error deleting assessment: $e');
      }
    }
  }

  Future<void> _handleAssessmentMissed(
    BuildContext context,
    String uid,
    Assessment assessment,
  ) async {
    SafeHaptics.mediumImpact();
    try {
      final isCurrentlyMissed = assessment.isMissed;
      final newStatus = isCurrentlyMissed ? null : 'Missed';

      await AssessmentService().updateAssessmentStatus(
        uid: uid,
        courseId: assessment.courseId,
        assessmentId: assessment.id,
        status: newStatus,
      );

      if (context.mounted) {
        if (newStatus == null) {
          SnackBarService.showInfo(
            context,
            'Reset ${assessment.name} to scheduled.',
          );
        } else {
          SnackBarService.showError(
            context,
            'Marked ${assessment.name} as Missed (0.0 marks).',
          );
        }
      }
    } catch (e) {
      debugPrint('Error toggling assessment missed: $e');
    }
  }

  Future<void> _handleAssessmentPostponed(
    BuildContext context,
    String uid,
    Assessment assessment,
    String courseCode,
  ) async {
    final safeDate = assessment.date ?? DateTime.now();
    final newDate = await showDatePicker(
      context: context,
      initialDate: safeDate.add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF2B78A),
            surface: Color(0xFF1C1412),
          ),
        ),
        child: child!,
      ),
    );

    if (newDate == null || !context.mounted) return;

    final newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(safeDate),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFF2B78A),
            surface: Color(0xFF1C1412),
          ),
        ),
        child: child!,
      ),
    );

    final resolvedTime = newTime ?? TimeOfDay.fromDateTime(safeDate);
    final targetDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      resolvedTime.hour,
      resolvedTime.minute,
    );

    SafeHaptics.mediumImpact();

    try {
      final courseRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(assessment.courseId);

      final snap = await courseRef.get();
      if (snap.exists) {
        final data = snap.data();
        final rawAss = data?['assessments'];
        List<dynamic> items = [];
        if (rawAss is List) {
          items = List.from(rawAss);
        } else if (rawAss is Map) {
          items = rawAss.values.toList();
        }

        final newAssessment = Assessment(
          courseId: assessment.courseId,
          name: assessment.name,
          date: targetDateTime,
          totalMarks: assessment.totalMarks,
          obtainedMarks: 0.0,
          weightage: assessment.weightage,
          status: 'Pending',
          postponedFromId: assessment.id,
        );

        for (int i = 0; i < items.length; i++) {
          if (items[i] is Map && items[i]['id'] == assessment.id) {
            final updated = Map<String, dynamic>.from(items[i]);
            updated['status'] = 'Postponed';
            updated['postponedToDate'] = Timestamp.fromDate(targetDateTime);
            updated['postponedToId'] = newAssessment.id;
            items[i] = updated;
            break;
          }
        }

        items.add(newAssessment.toMap());

        await courseRef.update({
          'assessments': items,
          'lastUpdated': FieldValue.serverTimestamp(),
        });

        await NotificationService().scheduleAssessmentReminder(
          assessmentName: assessment.name,
          courseName: courseCode,
          date: targetDateTime,
          id: newAssessment.id,
        );

        if (context.mounted) {
          SnackBarService.showSuccess(
            context,
            'Postponed ${assessment.name} ➔ Rescheduled for ${targetDateTime.day}/${targetDateTime.month}/${targetDateTime.year}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error postponing assessment: $e');
    }
  }

  /// =========================================================================
  /// TASK 2: NON-ACADEMIC CALENDAR EVENTS
  /// =========================================================================

  void _showCreateEventModal(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final titleCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String selectedCategory = 'Personal';
    DateTime selectedDate = _uniSelectedDay;
    TimeOfDay startTime = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 11, minute: 0);

    final categories = ['Personal', 'Club', 'Workshop', 'Seminar', 'Competition', 'Meeting', 'Other'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.event_note_rounded, color: Color(0xFFF2B78A), size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Create Calendar Event',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.blueGrey, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Event Title
                  const Text('EVENT TITLE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Robotics Club Meet, Hackathon Pitch',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Category Selector
                  const Text('CATEGORY', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        final isSel = selectedCategory == cat;
                        return GestureDetector(
                          onTap: () => setModalState(() => selectedCategory = cat),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSel ? const Color(0xFFF2B78A) : const Color(0xFF170F0D),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSel ? const Color(0xFFF2B78A) : Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSel ? const Color(0xFF110D0C) : Colors.white,
                                fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Date & Time Slot
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('DATE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final d = await showDatePicker(
                                  context: ctx,
                                  initialDate: selectedDate,
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (d != null) setModalState(() => selectedDate = d);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF170F0D),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                  ],
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
                            const Text('TIME SLOT', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final st = await showTimePicker(context: ctx, initialTime: startTime);
                                if (st != null) {
                                  final et = await showTimePicker(
                                    context: ctx,
                                    initialTime: TimeOfDay(hour: (st.hour + 1) % 24, minute: st.minute),
                                  );
                                  setModalState(() {
                                    startTime = st;
                                    if (et != null) endTime = et;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF170F0D),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, color: Color(0xFFF2B78A), size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${startTime.format(ctx)} - ${endTime.format(ctx)}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Remarks / Notes
                  const Text('REMARKS / NOTES (OPTIONAL)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: remarksCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Add agenda, room number, links, or notes...',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF110D0C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        if (title.isEmpty) return;

                        final slotStr = '${startTime.format(ctx)} - ${endTime.format(ctx)}';
                        final newEvent = PlannerEvent(
                          title: title,
                          category: selectedCategory,
                          date: selectedDate,
                          timeSlot: slotStr,
                          remarks: remarksCtrl.text.trim(),
                          status: 'Pending',
                        );

                        try {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('events')
                              .doc(newEvent.id)
                              .set(newEvent.toMap());
                        } catch (e) {
                          debugPrint('Error creating event: $e');
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          SnackBarService.showSuccess(context, 'Event "$title" scheduled for ${selectedDate.day}/${selectedDate.month}!');
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Save Event', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleEventCompleted(BuildContext context, String uid, PlannerEvent event) async {
    SafeHaptics.lightImpact();
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .doc(event.id)
          .update({'status': 'Completed'});
      if (context.mounted) {
        SnackBarService.showSuccess(context, 'Marked "${event.title}" as Completed!');
      }
    } catch (e) {
      debugPrint('Error updating event: $e');
    }
  }

  Future<void> _handleEventMissed(BuildContext context, String uid, PlannerEvent event) async {
    SafeHaptics.mediumImpact();
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('events')
          .doc(event.id)
          .update({'status': 'Missed'});
      if (context.mounted) {
        SnackBarService.showError(context, 'Marked "${event.title}" as Missed.');
      }
    } catch (e) {
      debugPrint('Error updating event: $e');
    }
  }

  Future<void> _handleEventPostponed(BuildContext context, String uid, PlannerEvent event) async {
    final newDate = await showDatePicker(
      context: context,
      initialDate: event.date.add(const Duration(days: 2)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (newDate == null || !context.mounted) return;

    SafeHaptics.mediumImpact();
    try {
      final newEvent = event.copyWith(
        id: generateEventId('event'),
        date: newDate,
        status: 'Pending',
      );

      final batch = FirebaseFirestore.instance.batch();
      final oldRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('events').doc(event.id);
      final newRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('events').doc(newEvent.id);

      batch.update(oldRef, {
        'status': 'Postponed',
        'postponedToDate': Timestamp.fromDate(newDate),
        'postponedToSlot': event.timeSlot,
      });
      batch.set(newRef, newEvent.toMap());

      await batch.commit();

      if (context.mounted) {
        SnackBarService.showSuccess(
          context,
          'Postponed "${event.title}" ➔ Rescheduled for ${newDate.day}/${newDate.month}/${newDate.year}',
        );
      }
    } catch (e) {
      debugPrint('Error postponing event: $e');
    }
  }

  Future<void> _handleEditEventRemarks(BuildContext context, String uid, PlannerEvent event) async {
    final editCtrl = TextEditingController(text: event.remarks);

    await showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Color(0xFFF2B78A), size: 22),
            SizedBox(width: 8),
            Text('Edit Event Remarks', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: editCtrl,
          maxLines: 3,
          style: const TextStyle(color: Colors.white, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Enter updated notes or remarks...',
            hintStyle: TextStyle(color: Colors.blueGrey.shade500),
            filled: true,
            fillColor: const Color(0xFF170F0D),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              SafeHaptics.lightImpact();
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('events')
                    .doc(event.id)
                    .update({'remarks': editCtrl.text.trim()});
                if (context.mounted) {
                  SnackBarService.showSuccess(context, 'Remarks updated!');
                }
              } catch (e) {
                debugPrint('Error updating remarks: $e');
              }
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentStatusButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.12),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? color : Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAssessmentTime(DateTime? dt) {
    if (dt == null) return '--:--';
    final hour = dt.hour;
    final minute = dt.minute;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mStr = minute.toString().padLeft(2, '0');
    return '$h12:$mStr $period';
  }

  Widget _buildAssessmentCard({
    required BuildContext context,
    required String uid,
    required Assessment assessment,
    required String courseCode,
    String? courseTitle,
    required Color cardColor,
    required Color accentColor,
  }) {
    return AssessmentCard(
      assessment: assessment,
      courseCode: courseCode,
      courseTitle: courseTitle,
      cardColor: cardColor,
      accentColor: accentColor,
      onAttended: () => _handleAssessmentAttended(context, uid, assessment, courseCode),
      onEditMarks: () => _showAddEditMarksModal(context, uid, assessment, courseCode),
      onMissed: () => _handleAssessmentMissed(context, uid, assessment),
      onPostponed: () => _handleAssessmentPostponed(context, uid, assessment, courseCode),
      onEditDetails: () => _showEditAssessmentDetailsModal(context, uid, assessment),
      onDelete: () => _showDeleteAssessmentConfirmation(context, uid, assessment),
    );
  }

  Widget _buildClassRoutineCard({
    required BuildContext context,
    required String uid,
    required ClassRoutine routine,
    required Map<String, AttendanceRecord> dateAttendanceMap,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> allAttendanceDocs,
    required List<ClassRoutine> allRoutines,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
    GlobalKey? attendanceKey,
  }) {
    final routineCode = RoutineCourseSyncService.parseCourseCode(
        routine.courseName.isNotEmpty ? routine.courseName : routine.courseId);
    final sanitizedRoutineCode = RoutineCourseSyncService.sanitizeDocId(routineCode);
    final record = dateAttendanceMap[routine.id] ??
        dateAttendanceMap['${routine.courseId}_${routine.id}'] ??
        dateAttendanceMap['${routineCode}_${routine.id}'] ??
        dateAttendanceMap['${sanitizedRoutineCode}_${routine.id}'];
    final currentStatus = record?.status ?? AttendanceStatus.unmarked;

    // Bi-Weekly Class Alternating Advisory via RoutineCourseSyncService
    final allAttendanceList = allAttendanceDocs
        .map((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id))
        .toList();
    final bool isAlternateDetected = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
      routine: routine,
      records: allAttendanceList,
      selectedDate: _uniSelectedDay,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onLongPress: () {
        SafeHaptics.heavyImpact();
        _showRoutineActionSheet(context, uid, routine,
            allRoutines: allRoutines, courseDocs: courseDocs);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF241C1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4A3830)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1412),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF4A3830)),
                      ),
                      child: Text(
                        '${routine.startTime} - ${routine.endTime}',
                        style: const TextStyle(
                            color: Color(0xFFD8CFC7),
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (routine.roomNumber != null && routine.roomNumber!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text('Room: ${routine.roomNumber}',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5)),
                    ],
                  ],
                ),
                Row(
                  children: [
                    Text(routine.classType,
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5)),
                    if (routine.isAlternating) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 0.6),
                        ),
                        child: Text(
                          routine.recurrence == 'biweekly_a'
                              ? 'Week A'
                              : (routine.recurrence == 'biweekly_b' ? 'Week B' : 'Biweekly'),
                          style: const TextStyle(
                              color: Color(0xFFF59E0B),
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.blueGrey, size: 18),
                      onPressed: () => _showRoutineActionSheet(context, uid, routine,
                          allRoutines: allRoutines, courseDocs: courseDocs),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_formatCleanCourseTitle(routine, courseDocs),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),

            // Interactive Attendance Toggle directly on Class Card
            Builder(
              builder: (ctx) {
                final attendanceRow = Row(
                  children: [
                    Text('Attendance:',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        AttendanceStatus.attended,
                        AttendanceStatus.missed,
                        AttendanceStatus.canceled,
                      ].map((st) {
                        final isSelected = currentStatus == st;
                        Color stBg;
                        Color stBorder;
                        Color stText;

                        if (st == AttendanceStatus.attended) {
                          stBg = isSelected ? const Color(0x3306D6A0) : const Color(0xFF170F0D);
                          stBorder = isSelected ? const Color(0x6606D6A0) : const Color(0xFF4A3830);
                          stText = isSelected ? const Color(0xFFFFFFFF) : const Color(0xFFABA093);
                        } else if (st == AttendanceStatus.missed) {
                          stBg = isSelected ? const Color(0x26EF4444) : const Color(0xFF170F0D);
                          stBorder = isSelected ? const Color(0x66EF4444) : const Color(0xFF4A3830);
                          stText = isSelected ? const Color(0xFFF87171) : const Color(0xFFABA093);
                        } else {
                          stBg = isSelected ? const Color(0x26F2B78A) : const Color(0xFF170F0D);
                          stBorder = isSelected ? const Color(0x66F2B78A) : const Color(0xFF4A3830);
                          stText = isSelected ? const Color(0xFFF2B78A) : const Color(0xFFABA093);
                        }

                        final String stLabel = st == AttendanceStatus.attended
                            ? 'Attended'
                            : (st == AttendanceStatus.missed ? 'Missed' : 'Canceled');

                        return InkWell(
                          onTap: () {
                            final nextStatus = isSelected ? AttendanceStatus.unmarked : st;
                            _updateAttendanceStatus(
                              uid: uid,
                              courseId: routine.courseId,
                              routineId: routine.id,
                              courseName: routine.courseName,
                              classType: routine.classType,
                              time: '${routine.startTime} - ${routine.endTime}',
                              newStatus: nextStatus,
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: stBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: stBorder,
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  st == AttendanceStatus.attended
                                      ? Icons.check_circle_rounded
                                      : (st == AttendanceStatus.missed
                                          ? Icons.cancel_rounded
                                          : Icons.do_not_disturb_on_rounded),
                                  size: 13,
                                  color: stText,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  stLabel,
                                  style: TextStyle(
                                    color: stText,
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                );

                if (attendanceKey != null) {
                  return TourShowcaseItem(
                    section: TourSection.planner,
                    step: TourStep(
                      key: attendanceKey,
                      title: 'One-Tap Attendance',
                      description: 'Log your daily lecture attendance with a single tap to instantly update semester percentages and shortage warnings.',
                    ),
                    stepIndex: 3,
                    totalSteps: 3,
                    child: attendanceRow,
                  );
                }
                return attendanceRow;
              },
            ),
            if (isAlternateDetected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Alternate week slot detected',
                        style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Class Topic Display with immediate local sync & "Record Lecture Topic" action
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final localTopic = _localRecordedTopics[_topicKey(_uniSelectedDay, routine.id)];
                final displayTopic = (localTopic != null && localTopic.trim().isNotEmpty)
                    ? localTopic.trim()
                    : (record?.topic != null && record!.topic!.trim().isNotEmpty
                        ? record.topic!.trim()
                        : null);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (displayTopic != null && displayTopic.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_added_rounded,
                                size: 14, color: Color(0xFFF2B78A)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Topic: $displayTopic',
                                style: const TextStyle(
                                    color: Color(0xFFF2B78A),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        'No topic recorded yet',
                        style: TextStyle(
                            color: Colors.blueGrey.shade500,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showLogTopicModal(context, uid, routine: routine),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note_rounded, size: 15, color: Color(0xFFF2B78A)),
                            SizedBox(width: 4),
                            Text(
                              "Record Lecture Topic",
                              style: TextStyle(
                                  color: Color(0xFFF2B78A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOffWeekRoutineCard({
    required BuildContext context,
    required String uid,
    required ClassRoutine offRoutine,
    required List<ClassRoutine> allRoutines,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
  }) {
    final offTitle = _formatCleanCourseTitle(offRoutine, courseDocs);
    final weekKey = '${_uniSelectedDay.year}-W${_uniSelectedDay.weekOfYear}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1715),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3830)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sync_disabled_rounded, color: Color(0xFFF59E0B), size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Off this week: $offTitle',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${offRoutine.startTime} - ${offRoutine.endTime} • ${offRoutine.recurrence == 'biweekly_a' ? 'Week A' : 'Week B'}',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              SafeHaptics.mediumImpact();
              final updatedSwaps = List<String>.from(offRoutine.swapWeeks)..add(weekKey);
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('routine')
                  .doc(offRoutine.id)
                  .update({
                'swapWeeks': updatedSwaps,
                'updatedAt': FieldValue.serverTimestamp(),
              });

              final partner = RoutineCourseSyncService.findPartnerClass(routine: offRoutine, allRoutines: allRoutines);
              if (partner != null) {
                final partnerSwaps = List<String>.from(partner.swapWeeks)..add(weekKey);
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('routine')
                    .doc(partner.id)
                    .update({
                  'swapWeeks': partnerSwaps,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
              }

              if (context.mounted) {
                SnackBarService.showSuccess(
                  context,
                  'Swapped! $offTitle is now active for Week ${_uniSelectedDay.weekOfYear}.',
                );
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2E201B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF2B78A), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Swap Turn',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatCleanExtraClassTitle(
    AttendanceRecord ex,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
  ) {
    for (final doc in courseDocs) {
      final data = doc.data();
      final cCode = (data['courseCode'] as String? ?? '').trim();
      final cName = (data['courseName'] as String? ?? '').trim();
      if (doc.id == ex.courseId ||
          (cCode.isNotEmpty && (cCode == ex.courseCode || cCode == ex.courseId)) ||
          (cName.isNotEmpty && cName.toLowerCase() == (ex.courseName ?? '').trim().toLowerCase())) {
        final effectiveCode = cCode.isNotEmpty ? cCode : doc.id;
        if (cName.isNotEmpty && cName.toLowerCase() != effectiveCode.toLowerCase()) {
          return '$effectiveCode • $cName';
        }
        return effectiveCode;
      }
    }
    final parsedCode = ex.courseCode ?? RoutineCourseSyncService.parseCourseCode(ex.courseName ?? ex.courseId);
    if (ex.courseName != null && ex.courseName!.trim().isNotEmpty && ex.courseName!.trim().toLowerCase() != parsedCode.toLowerCase()) {
      return '$parsedCode • ${ex.courseName!.trim()}';
    }
    return ex.courseName?.trim().isNotEmpty == true ? ex.courseName!.trim() : parsedCode;
  }

  Widget _buildExtraClassCard({
    required BuildContext context,
    required String uid,
    required AttendanceRecord ex,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
  }) {
    final currentStatus = ex.status;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onLongPress: () {
        SafeHaptics.heavyImpact();
        _showAddExtraClassModal(context, uid, courseDocs, existingRecord: ex);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF241C1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF4A3830)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Time badge, Class type chip, and Popup menu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1412),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF4A3830)),
                      ),
                      child: Text(
                        ex.time ?? '10:00 AM',
                        style: const TextStyle(
                          color: Color(0xFFD8CFC7),
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        ex.classType ?? 'Extra Lecture',
                        style: const TextStyle(
                          color: Color(0xFFF59E0B),
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.blueGrey, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: const Color(0xFF241C1A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF4A3830)),
                  ),
                  onSelected: (action) {
                    if (action == 'edit') {
                      _showAddExtraClassModal(context, uid, courseDocs, existingRecord: ex);
                    } else if (action == 'delete') {
                      _confirmDeleteExtraClass(context, uid, ex);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Edit Extra Class', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                          SizedBox(width: 8),
                          Text('Delete Extra Class', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Middle row: Course Code & Full Title
            Text(
              _formatCleanExtraClassTitle(ex, courseDocs),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 10),

            // Attendance selector row: Attended, Missed, Canceled
            Row(
              children: [
                Text(
                  'Attendance:',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    AttendanceStatus.attended,
                    AttendanceStatus.missed,
                    AttendanceStatus.canceled,
                  ].map((st) {
                    final isSelected = currentStatus == st;
                    Color stBg;
                    Color stBorder;
                    Color stText;

                    if (st == AttendanceStatus.attended) {
                      stBg = isSelected ? const Color(0x3306D6A0) : const Color(0xFF170F0D);
                      stBorder = isSelected ? const Color(0x6606D6A0) : const Color(0xFF4A3830);
                      stText = isSelected ? const Color(0xFFFFFFFF) : const Color(0xFFABA093);
                    } else if (st == AttendanceStatus.missed) {
                      stBg = isSelected ? const Color(0x26EF4444) : const Color(0xFF170F0D);
                      stBorder = isSelected ? const Color(0x66EF4444) : const Color(0xFF4A3830);
                      stText = isSelected ? const Color(0xFFF87171) : const Color(0xFFABA093);
                    } else {
                      stBg = isSelected ? const Color(0x26F2B78A) : const Color(0xFF170F0D);
                      stBorder = isSelected ? const Color(0x66F2B78A) : const Color(0xFF4A3830);
                      stText = isSelected ? const Color(0xFFF2B78A) : const Color(0xFFABA093);
                    }

                    final String stLabel = st == AttendanceStatus.attended
                        ? 'Attended'
                        : (st == AttendanceStatus.missed ? 'Missed' : 'Canceled');

                    return InkWell(
                      onTap: () {
                        final nextStatus = isSelected ? AttendanceStatus.unmarked : st;
                        _updateAttendanceStatus(
                          uid: uid,
                          courseId: ex.courseId,
                          routineId: ex.routineId,
                          courseName: ex.courseName ?? '',
                          classType: ex.classType ?? 'Extra Lecture',
                          time: ex.time ?? '10:00 AM',
                          newStatus: nextStatus,
                          existingDocId: ex.id,
                          topic: ex.topic,
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: stBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: stBorder,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              st == AttendanceStatus.attended
                                  ? Icons.check_circle_rounded
                                  : (st == AttendanceStatus.missed
                                      ? Icons.cancel_rounded
                                      : Icons.do_not_disturb_on_rounded),
                              size: 13,
                              color: stText,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              stLabel,
                              style: TextStyle(
                                color: stText,
                                fontSize: 11,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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
            const SizedBox(height: 10),

            // Bottom row: Record Lecture Topic
            Builder(
              builder: (context) {
                final topicKeyStr = _topicKey(_uniSelectedDay, ex.routineId ?? ex.id);
                final localTopic = _localRecordedTopics[topicKeyStr];
                final displayTopic = (localTopic != null && localTopic.trim().isNotEmpty)
                    ? localTopic.trim()
                    : (ex.topic != null && ex.topic!.trim().isNotEmpty
                        ? ex.topic!.trim()
                        : null);

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (displayTopic != null && displayTopic.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.bookmark_added_rounded,
                                size: 14, color: Color(0xFFF2B78A)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Topic: $displayTopic',
                                style: const TextStyle(
                                    color: Color(0xFFF2B78A),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        'No topic recorded yet',
                        style: TextStyle(
                            color: Colors.blueGrey.shade500,
                            fontSize: 11,
                            fontStyle: FontStyle.italic),
                      ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showLogTopicModal(
                        context,
                        uid,
                        courseId: ex.courseId,
                        courseName: ex.courseName ?? '',
                        routineOrRecordId: ex.routineId ?? ex.id,
                        classType: ex.classType ?? 'Extra Lecture',
                        time: ex.time ?? '10:00 AM',
                        existingDocId: ex.id,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note_rounded, size: 15, color: Color(0xFFF2B78A)),
                            SizedBox(width: 4),
                            Text(
                              "Record Lecture Topic",
                              style: TextStyle(
                                  color: Color(0xFFF2B78A),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlannerEventCard({
    required BuildContext context,
    required String uid,
    required PlannerEvent event,
    required Color cardColor,
    required Color accentColor,
  }) {
    final isPostponed = event.isPostponed;
    final isCompleted = event.isCompleted;
    final isMissed = event.isMissed;

    final postponedDateStr = event.postponedToDate != null
        ? '${event.postponedToDate!.day}/${event.postponedToDate!.month}/${event.postponedToDate!.year}'
        : '';

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isPostponed ? 0.65 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isPostponed
                ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                : (isCompleted
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : (isMissed
                        ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                        : const Color(0xFFF2B78A).withValues(alpha: 0.3))),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        event.category.toUpperCase(),
                        style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.timeSlot,
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                    ),
                  ],
                ),
                if (isPostponed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_clock_rounded, color: Color(0xFFF59E0B), size: 12),
                        const SizedBox(width: 4),
                        Text(
                          'Postponed ➔ Moved to $postponedDateStr',
                          style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (isCompleted)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Completed',
                          style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else if (isMissed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cancel_rounded, color: Color(0xFFEF4444), size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Missed',
                          style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              event.title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            if (event.remarks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF170F0D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.notes_rounded, size: 14, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.remarks,
                        style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                      ),
                    ),
                    InkWell(
                      onTap: () => _handleEditEventRemarks(context, uid, event),
                      child: const Icon(Icons.edit_note_rounded, size: 16, color: Color(0xFFF2B78A)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _handleEditEventRemarks(context, uid, event),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_comment_outlined, size: 13, color: Color(0xFFF2B78A)),
                    const SizedBox(width: 4),
                    Text(
                      'Add remarks / notes',
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
            if (!isPostponed) ...[
              const SizedBox(height: 10),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildAssessmentStatusButton(
                    label: 'Attended / Completed',
                    icon: Icons.check_circle_outline_rounded,
                    color: const Color(0xFF10B981),
                    isSelected: isCompleted,
                    onTap: () => _handleEventCompleted(context, uid, event),
                  ),
                  const SizedBox(width: 8),
                  _buildAssessmentStatusButton(
                    label: 'Missed',
                    icon: Icons.highlight_off_rounded,
                    color: const Color(0xFFEF4444),
                    isSelected: isMissed,
                    onTap: () => _handleEventMissed(context, uid, event),
                  ),
                  const SizedBox(width: 8),
                  _buildAssessmentStatusButton(
                    label: 'Postponed',
                    icon: Icons.update_rounded,
                    color: const Color(0xFFF59E0B),
                    isSelected: false,
                    onTap: () => _handleEventPostponed(context, uid, event),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'Monday';
      case DateTime.tuesday: return 'Tuesday';
      case DateTime.wednesday: return 'Wednesday';
      case DateTime.thursday: return 'Thursday';
      case DateTime.friday: return 'Friday';
      case DateTime.saturday: return 'Saturday';
      case DateTime.sunday: return 'Sunday';
      default: return '';
    }
  }

  String _getShortDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'Mon';
      case DateTime.tuesday: return 'Tue';
      case DateTime.wednesday: return 'Wed';
      case DateTime.thursday: return 'Thu';
      case DateTime.friday: return 'Fri';
      case DateTime.saturday: return 'Sat';
      case DateTime.sunday: return 'Sun';
      default: return '';
    }
  }

  /// TASK 4: Updates class attendance state in Firestore in real time
  TimeOfDay _parseTimeString(String? str, TimeOfDay fallback) {
    if (str == null || str.trim().isEmpty) return fallback;
    try {
      final cleaned = str.trim().toUpperCase();
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      final parts = cleaned.replaceAll('AM', '').replaceAll('PM', '').trim().split(':');
      int hour = int.parse(parts[0].trim());
      int minute = parts.length > 1 ? int.parse(parts[1].trim()) : 0;
      if (isPM && hour < 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (_) {
      return fallback;
    }
  }

  /// TASK 4: Updates class attendance state in Firestore in real time
  Future<void> _updateAttendanceStatus({
    required String uid,
    required String courseId,
    required String? routineId,
    required String courseName,
    required String classType,
    required String time,
    required AttendanceStatus newStatus,
    String? existingDocId,
    String? topic,
  }) async {
    SafeHaptics.mediumImpact();

    // TASK 1: Standardize courseId linking to canonical Firestore Course document ID
    final canonicalCourseId = await RoutineCourseSyncService.resolveCanonicalCourseId(
      uid: uid,
      courseId: courseId,
      rawName: courseName,
    );
    final courseCode = RoutineCourseSyncService.parseCourseCode(courseName.isNotEmpty ? courseName : courseId);

    final dateKey = '${_uniSelectedDay.year}_${_uniSelectedDay.month.toString().padLeft(2, '0')}_${_uniSelectedDay.day.toString().padLeft(2, '0')}';
    final docId = existingDocId ?? '${canonicalCourseId}_${routineId ?? 'extra'}_$dateKey';

    final record = AttendanceRecord(
      id: docId,
      courseId: canonicalCourseId,
      courseCode: courseCode,
      date: _uniSelectedDay,
      status: newStatus,
      routineId: routineId,
      courseName: courseName,
      classType: classType,
      time: time,
      topic: topic,
    );

    try {
      final batch = FirebaseFirestore.instance.batch();

      // 1. Write attendance record
      final attRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .doc(docId);
      final recordData = {
        ...record.toMap(),
        'status': newStatus == AttendanceStatus.unmarked ? 'unmarked' : newStatus.name,
        'courseId': canonicalCourseId,
        'courseCode': courseCode,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (topic != null && topic.isNotEmpty) {
        recordData['topic'] = topic;
      }
      batch.set(attRef, recordData, SetOptions(merge: true));

      // 2. If routineId provided and routine had a non-canonical courseId, fix it
      if (routineId != null && routineId.isNotEmpty && !routineId.startsWith('extra') && courseId != canonicalCourseId) {
        final routineRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('routine')
            .doc(routineId);
        batch.set(routineRef, {
          'courseId': canonicalCourseId,
          'courseCode': courseCode,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 3. Touch user profile & course to trigger immediate reactive refresh across Home & Courses screens
      final courseRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(canonicalCourseId);
      batch.set(courseRef, {
        'lastAttendanceUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (e) {
      debugPrint('Error updating attendance record: $e');
    }
  }

  /// TASK 4: Modal to log or edit an extra / makeup class on the selected date
  void _showAddExtraClassModal(
    BuildContext context,
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses, {
    AttendanceRecord? existingRecord,
  }) {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please add enrolled courses first.'),
        ),
      );
      return;
    }

    String selectedCourseId = courses.first.id;
    if (existingRecord != null) {
      final match = courses.where((c) =>
          c.id == existingRecord.courseId ||
          (c.data()['courseCode'] as String? ?? '').trim() == existingRecord.courseCode);
      if (match.isNotEmpty) {
        selectedCourseId = match.first.id;
      }
    }

    String selectedCourseName = existingRecord?.courseName ?? (courses.firstWhere((c) => c.id == selectedCourseId, orElse: () => courses.first).data()['courseName'] as String? ?? 'Course');
    String classType = existingRecord?.classType ?? 'Extra Lecture';
    TimeOfDay selectedTime = _parseTimeString(existingRecord?.time, const TimeOfDay(hour: 10, minute: 0));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(_uniSelectedDay.year, _uniSelectedDay.month, _uniSelectedDay.day);
    final isFuture = selectedDay.isAfter(today);

    AttendanceStatus? attendanceStatus = existingRecord != null
        ? (existingRecord.status == AttendanceStatus.unmarked ? null : existingRecord.status)
        : (isFuture ? null : AttendanceStatus.attended);

    final classTypes = ['Extra Lecture', 'Make-up Lab', 'Review Session'];
    if (!classTypes.contains(classType)) {
      classTypes.add(classType);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.more_time_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existingRecord != null ? 'Edit Extra / Makeup Class' : 'Add Extra / Makeup Class',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'For ${_uniSelectedDay.day} ${_getMonthName(_uniSelectedDay.month)} ${_uniSelectedDay.year}',
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text('SELECT COURSE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCourseId,
                    dropdownColor: const Color(0xFF1C1412),
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    items: courses.map((c) {
                      final name = c.data()['courseName'] as String? ?? 'Course';
                      final code = c.data()['courseCode'] as String? ?? '';
                      return DropdownMenuItem(
                        value: c.id,
                        child: Text('$code: $name', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          selectedCourseId = val;
                          final match = courses.firstWhere((c) => c.id == val);
                          selectedCourseName = match.data()['courseName'] as String? ?? 'Course';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('CLASS TYPE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: classTypes.map((type) {
                      final isSelected = classType == type;
                      return ChoiceChip(
                        label: Text(type, style: TextStyle(color: isSelected ? const Color(0xFF110D0C) : Colors.white, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selected: isSelected,
                        selectedColor: const Color(0xFFF2B78A),
                        backgroundColor: const Color(0xFF170F0D),
                        onSelected: (selected) {
                          if (selected) setModalState(() => classType = type);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text('CLASS TIME', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: selectedTime);
                      if (picked != null) setModalState(() => selectedTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(selectedTime.format(context), style: const TextStyle(color: Colors.white, fontSize: 14)),
                          const Icon(Icons.access_time_rounded, color: Color(0xFFF2B78A), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('ATTENDANCE STATUS', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(
                          'Pending / Scheduled',
                          style: TextStyle(
                            color: (attendanceStatus == null || attendanceStatus == AttendanceStatus.unmarked)
                                ? Colors.white
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: (attendanceStatus == null || attendanceStatus == AttendanceStatus.unmarked)
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        selected: attendanceStatus == null || attendanceStatus == AttendanceStatus.unmarked,
                        selectedColor: const Color(0xFF4A3830),
                        backgroundColor: const Color(0xFF170F0D),
                        onSelected: (selected) {
                          setModalState(() => attendanceStatus = null);
                        },
                      ),
                      ChoiceChip(
                        label: Text(
                          'Attended',
                          style: TextStyle(
                            color: attendanceStatus == AttendanceStatus.attended ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: attendanceStatus == AttendanceStatus.attended ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: attendanceStatus == AttendanceStatus.attended,
                        selectedColor: const Color(0xFF10B981),
                        backgroundColor: const Color(0xFF170F0D),
                        onSelected: (selected) {
                          setModalState(() {
                            attendanceStatus = selected ? AttendanceStatus.attended : null;
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(
                          'Missed',
                          style: TextStyle(
                            color: attendanceStatus == AttendanceStatus.missed ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: attendanceStatus == AttendanceStatus.missed ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: attendanceStatus == AttendanceStatus.missed,
                        selectedColor: const Color(0xFFEF4444),
                        backgroundColor: const Color(0xFF170F0D),
                        onSelected: (selected) {
                          setModalState(() {
                            attendanceStatus = selected ? AttendanceStatus.missed : null;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: const Color(0xFF110D0C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        final timeStr = selectedTime.format(context);
                        Navigator.pop(ctx);
                        final routineId = existingRecord?.routineId ?? 'extra_${DateTime.now().millisecondsSinceEpoch}';
                        _updateAttendanceStatus(
                          uid: uid,
                          courseId: selectedCourseId,
                          routineId: routineId,
                          courseName: selectedCourseName,
                          classType: classType,
                          time: timeStr,
                          newStatus: attendanceStatus ?? AttendanceStatus.unmarked,
                          existingDocId: existingRecord?.id,
                          topic: existingRecord?.topic,
                        );
                        SnackBarService.showSuccess(
                          context,
                          existingRecord != null ? 'Extra class updated!' : 'Extra class recorded!',
                        );
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(
                        existingRecord != null ? 'Update Extra Class' : 'Save Extra Class',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteExtraClass(BuildContext context, String uid, AttendanceRecord ex) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF4A3830)),
        ),
        title: const Text('Delete Extra Class?', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to remove this ${ex.classType ?? 'extra class'} (${ex.courseName ?? ex.courseId})?',
          style: const TextStyle(color: Color(0xFFD8CFC7), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('attendance_records')
                    .doc(ex.id)
                    .delete();
                if (context.mounted) {
                  SnackBarService.showSuccess(context, 'Extra class removed.');
                }
              } catch (e) {
                if (context.mounted) {
                  SnackBarService.showError(context, 'Failed to delete extra class: $e');
                }
              }
            },
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// TASK 2: Daily Class Topic Logger & Syllabus Linking Modal Bottom Sheet
  void _showLogTopicModal(
    BuildContext context,
    String uid, {
    ClassRoutine? routine,
    String? courseId,
    String? courseName,
    String? routineOrRecordId,
    String? classType,
    String? time,
    String? existingDocId,
  }) async {
    SafeHaptics.lightImpact();

    final effectiveCourseId = routine?.courseId ?? courseId ?? '';
    final effectiveCourseName = routine?.courseName ?? courseName ?? '';
    final effectiveId = routine?.id ?? routineOrRecordId ?? '';
    final effectiveClassType = routine?.classType ?? classType ?? 'Extra Lecture';
    final effectiveTime = routine != null ? '${routine.startTime} - ${routine.endTime}' : (time ?? '10:00 AM');

    List<SyllabusNode> nodes = [];
    final Set<String> existingTitles = {};

    try {
      final canonicalCourseId = await RoutineCourseSyncService.resolveCanonicalCourseId(
        uid: uid,
        courseId: effectiveCourseId,
        rawName: effectiveCourseName,
      );

      final courseDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(canonicalCourseId)
          .get();

      if (courseDoc.exists) {
        final data = courseDoc.data();
        final rawData = data?['syllabusData'] ?? data?['syllabus'];
        List<dynamic> rawList = [];
        if (rawData is List) {
          rawList = rawData;
        } else if (rawData is Map) {
          if (rawData['nodes'] is List) {
            rawList = rawData['nodes'] as List;
          } else if (rawData['chapters'] is List) {
            rawList = rawData['chapters'] as List;
          }
        }
        nodes = rawList
            .whereType<Map>()
            .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
            .toList();

        void collectTitles(List<SyllabusNode> list) {
          for (final n in list) {
            if (n.title.trim().isNotEmpty) existingTitles.add(n.title.trim());
            collectTitles(n.children);
          }
        }
        collectTitles(nodes);
      }
    } catch (e) {
      debugPrint('Error fetching syllabus topics: $e');
    }

    if (!context.mounted) return;

    final autocompleteTextCtrl = TextEditingController();
    final newTopicCtrl = TextEditingController();
    final noteUrlCtrl = TextEditingController();
    String selectedExistingTopic = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_note_rounded, color: Color(0xFFF2B78A), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Record Lecture Topic',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              effectiveCourseName.isNotEmpty ? effectiveCourseName : effectiveCourseId,
                              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 1. Autocomplete from Syllabus
                  const Text(
                    '1. SELECT FROM SYLLABUS',
                    style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  RawAutocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return existingTitles;
                      }
                      return existingTitles.where((String option) {
                        return option.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'Search topic from syllabus...',
                          hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFF2B78A), size: 18),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, color: Colors.blueGrey, size: 16),
                                  onPressed: () {
                                    controller.clear();
                                    setModalState(() {
                                      selectedExistingTopic = '';
                                      autocompleteTextCtrl.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          setModalState(() {
                            selectedExistingTopic = val;
                            autocompleteTextCtrl.text = val;
                          });
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 8.0,
                          color: const Color(0xFF1C1412),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1412),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.bookmark_outline_rounded, color: Color(0xFFF2B78A), size: 14),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            option,
                                            style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Or enter new topic name
                  const Text(
                    '2. OR ENTER NEW TOPIC NAME',
                    style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: newTopicCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. Diode Clamping Circuits, Lecture 5',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.add_task_rounded, color: Color(0xFFF2B78A), size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Optional Class Note Link
                  const Text(
                    '3. ATTACH CLASS NOTE LINK (OPTIONAL)',
                    style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteUrlCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'Google Drive, Notion, or PDF link',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFF2B78A), size: 18),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: const Color(0xFF110D0C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final enteredNew = newTopicCtrl.text.trim();
                        final selectedAutocomp = (selectedExistingTopic.isNotEmpty ? selectedExistingTopic : autocompleteTextCtrl.text).trim();
                        final finalTopic = enteredNew.isNotEmpty ? enteredNew : selectedAutocomp;

                        if (finalTopic.isEmpty) {
                          SnackBarService.showError(context, 'Please select or enter a topic name.');
                          return;
                        }

                        // TASK 4: Immediately record in local state so the class card updates with zero latency
                        final topicCacheKey = _topicKey(_uniSelectedDay, effectiveId);
                        setState(() {
                          _localRecordedTopics[topicCacheKey] = finalTopic;
                        });

                        // TASK 2: Instant Dialog Dismissal
                        Navigator.pop(ctx);

                        final rawUrl = noteUrlCtrl.text.trim();
                        final noteUrl = rawUrl.isNotEmpty
                            ? (rawUrl.startsWith('http://') || rawUrl.startsWith('https://') ? rawUrl : 'https://$rawUrl')
                            : '';

                        // Check if finalTopic exists in current syllabus
                        SyllabusNode? findNode(List<SyllabusNode> list, String title) {
                          for (final n in list) {
                            if (n.title.trim().toLowerCase() == title.toLowerCase()) return n;
                            final found = findNode(n.children, title);
                            if (found != null) return found;
                          }
                          return null;
                        }

                        final existingNode = findNode(nodes, finalTopic);

                        // TASK 1 & 3: Show non-sticky floating SnackBar
                        SnackBarService.showSuccess(
                          context,
                          'Recorded topic "$finalTopic"${existingNode == null ? ' under "Lectures & Class Logs"' : ' (Syllabus updated)'}!',
                        );

                        // Background persistence to Firestore
                        try {
                          if (existingNode != null) {
                            // Existing topic selected: mark covered/completed and append note link as child
                            existingNode.isCompleted = true;
                            if (noteUrl.isNotEmpty) {
                              final dateNoteTitle = 'Class Note (${_uniSelectedDay.day}/${_uniSelectedDay.month})';
                              final alreadyHasNote = existingNode.children.any((c) => c.title == dateNoteTitle);
                              if (!alreadyHasNote) {
                                existingNode.children.add(SyllabusNode(
                                  title: dateNoteTitle,
                                  isLeaf: true,
                                  resourceUrl: noteUrl,
                                  isCompleted: false,
                                ));
                              }
                            }
                            for (final root in nodes) {
                              root.updateHierarchicalCompletion();
                            }
                          } else {
                            // New topic entered: Create a new SyllabusNode under "Lectures & Class Logs" section
                            SyllabusNode? logsSection;
                            for (final n in nodes) {
                              final lower = n.title.trim().toLowerCase();
                              if (lower == 'lectures & class logs' || lower == 'class logs') {
                                logsSection = n;
                                break;
                              }
                            }
                            if (logsSection == null) {
                              logsSection = SyllabusNode(
                                title: 'Lectures & Class Logs',
                                isLeaf: false,
                                children: [],
                              );
                              nodes.add(logsSection);
                            }

                            final newTopicNode = SyllabusNode(
                              title: finalTopic,
                              isLeaf: true,
                              isCompleted: true,
                              resourceUrl: noteUrl.isNotEmpty ? noteUrl : null,
                            );
                            if (noteUrl.isNotEmpty) {
                              newTopicNode.children.add(SyllabusNode(
                                title: 'Class Note (${_uniSelectedDay.day}/${_uniSelectedDay.month})',
                                isLeaf: true,
                                resourceUrl: noteUrl,
                                isCompleted: false,
                              ));
                            }
                            logsSection.children.add(newTopicNode);
                          }

                          final canonicalCourseId = await RoutineCourseSyncService.resolveCanonicalCourseId(
                            uid: uid,
                            courseId: effectiveCourseId,
                            rawName: effectiveCourseName,
                          );
                          final courseCode = RoutineCourseSyncService.parseCourseCode(
                            effectiveCourseName.isNotEmpty ? effectiveCourseName : effectiveCourseId,
                          );

                          // 1. Save updated syllabus back to course document
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('courses')
                              .doc(canonicalCourseId)
                              .set({
                            'syllabusData': nodes.map((n) => n.toMap()).toList(),
                            'syllabus': nodes.map((n) => n.toMap()).toList(),
                            'lastAttendanceUpdate': FieldValue.serverTimestamp(),
                            'lastUpdated': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          final dateStr = '${_uniSelectedDay.year}-${_uniSelectedDay.month.toString().padLeft(2, '0')}-${_uniSelectedDay.day.toString().padLeft(2, '0')}';
                          final dateKeyUnderscore = '${_uniSelectedDay.year}_${_uniSelectedDay.month.toString().padLeft(2, '0')}_${_uniSelectedDay.day.toString().padLeft(2, '0')}';
                          final logDocId = '${canonicalCourseId}_${effectiveId}_$dateStr';
                          final attDocIdUnderscore = existingDocId ?? '${canonicalCourseId}_${effectiveId}_$dateKeyUnderscore';

                          // 2. Save log record to users/{uid}/class_logs
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('class_logs')
                              .doc(logDocId)
                              .set({
                            'id': logDocId,
                            'courseId': canonicalCourseId,
                            'courseCode': courseCode,
                            'routineId': effectiveId,
                            'courseName': effectiveCourseName,
                            'classType': effectiveClassType,
                            'date': Timestamp.fromDate(_uniSelectedDay),
                            'dateStr': dateStr,
                            'time': effectiveTime,
                            'topic': finalTopic,
                            'noteUrl': noteUrl.isNotEmpty ? noteUrl : null,
                            'isExistingTopic': existingNode != null,
                            'loggedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));

                          // 3. Save topic into attendance record across both key formats so query matches immediately
                          final Map<String, dynamic> attPayload = {
                            'id': attDocIdUnderscore,
                            'courseId': canonicalCourseId,
                            'courseCode': courseCode,
                            'routineId': effectiveId,
                            'courseName': effectiveCourseName,
                            'classType': effectiveClassType,
                            'date': Timestamp.fromDate(_uniSelectedDay),
                            'time': effectiveTime,
                            'topic': finalTopic,
                            'updatedAt': FieldValue.serverTimestamp(),
                          };
                          if (routine != null) {
                            attPayload['status'] = AttendanceStatus.attended.name;
                          }

                          final batch = FirebaseFirestore.instance.batch();
                          final attRef1 = FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('attendance_records')
                              .doc(attDocIdUnderscore);
                          final attRef2 = FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('attendance_records')
                              .doc(logDocId);
                          batch.set(attRef1, attPayload, SetOptions(merge: true));
                          batch.set(attRef2, {...attPayload, 'id': logDocId}, SetOptions(merge: true));
                          await batch.commit();
                        } catch (e) {
                          debugPrint('Error saving recorded topic in background: $e');
                        }
                      },
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'Save Lecture Topic',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Formats course title cleanly without duplication (e.g. "MATH 159 - MATH 159" -> "MATH 159 • Calculus II")
  String _formatCleanCourseTitle(ClassRoutine routine, List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs) {
    final raw = routine.courseName.trim();
    final parsedCode = RoutineCourseSyncService.parseCourseCode(raw.isNotEmpty ? raw : routine.courseId);

    // Look up in courseDocs
    String? matchedTitle;
    String? matchedCode;
    for (final doc in courseDocs) {
      final data = doc.data();
      final cCode = (data['courseCode'] as String? ?? '').trim();
      final cName = (data['courseName'] as String? ?? '').trim();
      if (RoutineCourseSyncService.routineMatchesCourse(
        routine: routine,
        courseId: doc.id,
        courseCode: cCode,
        courseName: cName,
      )) {
        matchedCode = cCode.isNotEmpty ? cCode : doc.id;
        matchedTitle = cName;
        break;
      }
    }

    final effectiveCode = (matchedCode != null && matchedCode.isNotEmpty) ? matchedCode : parsedCode;
    if (matchedTitle != null && matchedTitle.isNotEmpty && matchedTitle.toLowerCase() != effectiveCode.toLowerCase()) {
      return '$effectiveCode • $matchedTitle';
    }

    // Check for duplicate pattern in raw string e.g. "MATH 159 - MATH 159"
    for (final delimiter in [' - ', ' – ', ' — ', ': ', ' • ', '|']) {
      if (raw.contains(delimiter)) {
        final parts = raw.split(delimiter);
        if (parts.length >= 2) {
          final part1 = parts[0].trim();
          final part2 = parts.sublist(1).join(delimiter).trim();
          if (part1.toLowerCase() == part2.toLowerCase()) {
            return part1;
          }
          return '$part1 • $part2';
        }
      }
    }

    return raw.isNotEmpty ? raw : effectiveCode;
  }

  /// Routine Lifecycle Action Sheet (Reschedule/Shift across days OR End from today)
  void _showRoutineActionSheet(
    BuildContext context,
    String uid,
    ClassRoutine routine, {
    List<ClassRoutine> allRoutines = const [],
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs = const [],
  }) {
    final cleanTitle = _formatCleanCourseTitle(routine, courseDocs);
    final weekKey = '${_uniSelectedDay.year}-W${_uniSelectedDay.weekOfYear}';
    final bool isBiweekly = routine.isAlternating || routine.recurrence == 'biweekly_a' || routine.recurrence == 'biweekly_b';
    final bool isSwappedThisWeek = routine.isSwappedForDate(_uniSelectedDay);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xFF4A3830), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.tune_rounded, color: Color(0xFFF2B78A), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cleanTitle,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${routine.dayName} • ${routine.startTime} - ${routine.endTime}',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Divider(color: Color(0xFF382A24), height: 1),
                const SizedBox(height: 8),

                // Option 1: Change Day or Time
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.schedule_send_rounded, color: Color(0xFFF2B78A), size: 20),
                  ),
                  title: Text('Change Day or Time', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Shift this class to another time or day',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditRoutineFromDateModal(context, uid, routine);
                  },
                ),

                // Option 2 (If Biweekly): Swap Biweekly Turn for This Week
                if (isBiweekly) ...[
                  const SizedBox(height: 4),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF10B981), size: 20),
                    ),
                    title: Text('Swap Biweekly Turn for This Week', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(
                      isSwappedThisWeek
                          ? 'Currently swapped for Week ${_uniSelectedDay.weekOfYear}: tap to restore standard rotation'
                          : 'Run this class this week (shifts Week A/B for this week)',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final updatedSwaps = List<String>.from(routine.swapWeeks);
                      if (isSwappedThisWeek) {
                        updatedSwaps.remove(weekKey);
                      } else {
                        updatedSwaps.add(weekKey);
                      }

                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('routine')
                          .doc(routine.id)
                          .update({
                        'swapWeeks': updatedSwaps,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });

                      // Sync paired partner class if exists
                      final partner = RoutineCourseSyncService.findPartnerClass(routine: routine, allRoutines: allRoutines);
                      if (partner != null) {
                        final partnerSwaps = List<String>.from(partner.swapWeeks);
                        if (isSwappedThisWeek) {
                          partnerSwaps.remove(weekKey);
                        } else {
                          partnerSwaps.add(weekKey);
                        }
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(partner.id)
                            .update({
                          'swapWeeks': partnerSwaps,
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                      }

                      if (context.mounted) {
                        SnackBarService.showSuccess(
                          context,
                          isSwappedThisWeek
                              ? 'Restored standard biweekly rotation for Week ${_uniSelectedDay.weekOfYear}!'
                              : 'Swapped biweekly turn! This class is now active for Week ${_uniSelectedDay.weekOfYear}.',
                        );
                      }
                    },
                  ),
                ],

                const SizedBox(height: 4),

                // Option 3: Class Has Ended for the Term
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.event_busy_rounded, color: Color(0xFFF59E0B), size: 20),
                  ),
                  title: Text('Class Has Ended for the Term', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Keep all past attendance, but remove from today forward',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final partner = RoutineCourseSyncService.findPartnerClass(routine: routine, allRoutines: allRoutines);
                    final prevDay = _uniSelectedDay.subtract(const Duration(days: 1));

                    if (partner != null && (routine.isAlternating || routine.recurrence != 'weekly')) {
                      // Partner Takeover Prompt (Task 3)
                      final result = await showDialog<String>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: const Color(0xFF1C1412),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFF382A24), width: 0.8),
                          ),
                          title: Text(
                            '${routine.courseCode} has ended',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Would you like ${partner.courseCode} to take over every week from now on, or keep it every other week?',
                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF241C1A),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF4A3830)),
                                ),
                                child: Text(
                                  'Past attendance for both classes will remain 100% untouched in your history.',
                                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, 'cancel'),
                              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, 'keep_biweekly'),
                              child: Text('Keep Biweekly (Alternate weeks off)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 12)),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2B78A),
                                foregroundColor: const Color(0xFF110D0C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.pop(dCtx, 'make_weekly'),
                              child: Text('Make it Every Week', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );

                      if (result == 'keep_biweekly') {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(routine.id)
                            .update({
                          'effectiveUntil': Timestamp.fromDate(prevDay),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        if (context.mounted) {
                          SnackBarService.showSuccess(context, '${routine.courseCode} ended. ${partner.courseCode} remains biweekly.');
                        }
                      } else if (result == 'make_weekly') {
                        // 1. Cap ended routine
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(routine.id)
                            .update({
                          'effectiveUntil': Timestamp.fromDate(prevDay),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        // 2. Cap partner old routine
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(partner.id)
                            .update({
                          'effectiveUntil': Timestamp.fromDate(prevDay),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        // 3. Create new weekly slot for partner
                        final newId = generateRoutineId('class');
                        final weeklyPartner = ClassRoutine(
                          id: newId,
                          courseId: partner.courseId,
                          courseName: partner.courseName,
                          dayOfWeek: partner.dayOfWeek,
                          startTime: partner.startTime,
                          endTime: partner.endTime,
                          classType: partner.classType,
                          roomNumber: partner.roomNumber,
                          isAlternating: false,
                          recurrence: 'weekly',
                          pairedClassId: null,
                          effectiveFrom: _uniSelectedDay,
                          effectiveUntil: null,
                        );
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(newId)
                            .set(weeklyPartner.toMap());

                        if (context.mounted) {
                          SnackBarService.showSuccess(
                            context,
                            '${partner.courseCode} will now run every week starting ${_uniSelectedDay.day}/${_uniSelectedDay.month}!',
                          );
                        }
                      }
                    } else {
                      // Standard class ended confirmation
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: const Color(0xFF1C1412),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFF382A24), width: 0.8),
                          ),
                          title: Text('Class Has Ended for the Term', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          content: Text(
                            'Keep all past attendance for ${routine.courseCode}, but remove from ${_uniSelectedDay.day}/${_uniSelectedDay.month}/${_uniSelectedDay.year} forward?',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2B78A),
                                foregroundColor: const Color(0xFF110D0C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: Text('End Class', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('routine')
                            .doc(routine.id)
                            .update({
                          'effectiveUntil': Timestamp.fromDate(prevDay),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });
                        if (context.mounted) {
                          SnackBarService.showSuccess(context, 'Class ended from today forward. Past history preserved!');
                        }
                      }
                    }
                  },
                ),

                const SizedBox(height: 4),

                // Option 4: Delete Routine Slot
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                  ),
                  title: Text('Delete Routine Slot', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(
                    'Remove this slot completely (e.g. entered by mistake)',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dCtx) => AlertDialog(
                        backgroundColor: const Color(0xFF1C1412),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFF382A24), width: 0.8),
                        ),
                        title: Text('Delete Routine Slot', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 16)),
                        content: Text(
                          'Permanently delete ${routine.courseCode} (${routine.dayName} ${routine.startTime}) for all weeks?\n\nUse this only if this slot was entered by mistake.',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx, false),
                            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => Navigator.pop(dCtx, true),
                            child: Text('Delete Completely', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('routine')
                          .doc(routine.id)
                          .delete();

                      if (context.mounted) {
                        SnackBarService.showSuccess(context, 'Routine slot deleted permanently.');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Dialog to reschedule or shift routine lifecycle to another weekday or time
  void _showEditRoutineFromDateModal(BuildContext context, String uid, ClassRoutine routine) {
    int targetDayOfWeek = routine.dayOfWeek;
    DateTime splitStartDate = _uniSelectedDay;
    DateTime? splitEndDate = routine.effectiveUntil;

    TimeOfDay parseTimeString(String? str, TimeOfDay fallback) {
      if (str == null || str.trim().isEmpty) return fallback;
      try {
        final cleaned = str.trim().toUpperCase();
        final isPM = cleaned.contains('PM');
        final isAM = cleaned.contains('AM');
        final parts = cleaned.replaceAll('AM', '').replaceAll('PM', '').trim().split(':');
        int hour = int.parse(parts[0].trim());
        int minute = parts.length > 1 ? int.parse(parts[1].trim()) : 0;
        if (isPM && hour < 12) hour += 12;
        if (isAM && hour == 12) hour = 0;
        return TimeOfDay(hour: hour, minute: minute);
      } catch (_) {
        return fallback;
      }
    }

    TimeOfDay startTime = parseTimeString(routine.startTime, const TimeOfDay(hour: 9, minute: 0));
    TimeOfDay endTime = parseTimeString(routine.endTime, const TimeOfDay(hour: 10, minute: 30));
    final roomCtrl = TextEditingController(text: routine.roomNumber ?? '');
    String classType = routine.classType;

    final weekdaysList = [
      (DateTime.saturday, 'Sat'),
      (DateTime.sunday, 'Sun'),
      (DateTime.monday, 'Mon'),
      (DateTime.tuesday, 'Tue'),
      (DateTime.wednesday, 'Wed'),
      (DateTime.thursday, 'Thu'),
      (DateTime.friday, 'Fri'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: const Color(0xFF4A3830), borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Change Day or Time',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shift this class to another weekday or time. Past classes stay untouched in your history.',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Active Date Span Controls directly in Shift dialog
                  Text(
                    'WHEN DOES THIS SCHEDULE APPLY?',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: splitStartDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              builder: (context, child) => Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFF2B78A),
                                    onPrimary: Color(0xFF110D0C),
                                    surface: Color(0xFF1C1412),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setModalState(() => splitStartDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF241C1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFF2B78A), width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Starting From', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${splitStartDate.day}/${splitStartDate.month}/${splitStartDate.year}',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: const Color(0xFFF2B78A),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: splitEndDate ?? splitStartDate.add(const Duration(days: 90)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              builder: (context, child) => Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFF2B78A),
                                    onPrimary: Color(0xFF110D0C),
                                    surface: Color(0xFF1C1412),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setModalState(() => splitEndDate = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF241C1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: splitEndDate != null ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Until', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.w600)),
                                    if (splitEndDate != null)
                                      GestureDetector(
                                        onTap: () => setModalState(() => splitEndDate = null),
                                        child: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 14),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  splitEndDate != null
                                      ? '${splitEndDate!.day}/${splitEndDate!.month}/${splitEndDate!.year}'
                                      : 'Ongoing / Term End',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: splitEndDate != null ? const Color(0xFFF2B78A) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Flexible Day-to-Day Shifting: Weekday Selector Chips
                  Text(
                    'SHIFT TO WEEKDAY',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: weekdaysList.map((entry) {
                        final isSelected = targetDayOfWeek == entry.$1;
                        return GestureDetector(
                          onTap: () {
                            SafeHaptics.lightImpact();
                            setModalState(() => targetDayOfWeek = entry.$1);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF241C1A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              entry.$2,
                              style: GoogleFonts.plusJakartaSans(
                                color: isSelected ? const Color(0xFF110D0C) : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Room
                  Text('ROOM NUMBER (OPTIONAL)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: roomCtrl,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. Room 402',
                      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF241C1A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Time Pickers
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('START TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: startTime);
                                if (t != null) setModalState(() => startTime = t);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF241C1A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF4A3830)),
                                ),
                                child: Text(startTime.format(context), style: GoogleFonts.jetBrainsMono(color: Colors.white, fontWeight: FontWeight.bold)),
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
                            Text('END TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: endTime);
                                if (t != null) setModalState(() => endTime = t);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF241C1A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF4A3830)),
                                ),
                                child: Text(endTime.format(context), style: GoogleFonts.jetBrainsMono(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Save Split Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF110D0C),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);

                        SnackBarService.showSuccess(
                          context,
                          'Class rescheduled starting ${splitStartDate.day}/${splitStartDate.month}!',
                        );

                        try {
                          // 1. Cap old routine
                          final prevDay = splitStartDate.subtract(const Duration(days: 1));
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc(routine.id)
                              .update({
                            'effectiveUntil': Timestamp.fromDate(prevDay),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                          // 2. Insert new routine starting from splitStartDate with target weekday
                          final newId = generateRoutineId('class');
                          final newRoutine = ClassRoutine(
                            id: newId,
                            courseId: routine.courseId,
                            courseName: routine.courseName,
                            dayOfWeek: targetDayOfWeek,
                            startTime: startTime.format(context),
                            endTime: endTime.format(context),
                            classType: classType,
                            roomNumber: roomCtrl.text.trim().isNotEmpty ? roomCtrl.text.trim() : null,
                            isAlternating: routine.isAlternating,
                            recurrence: routine.recurrence,
                            pairedClassId: routine.pairedClassId,
                            effectiveFrom: splitStartDate,
                            effectiveUntil: splitEndDate,
                            swapWeeks: routine.swapWeeks,
                          );

                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc(newId)
                              .set(newRoutine.toMap());
                        } catch (e) {
                          debugPrint('Error splitting routine in background: $e');
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text('Apply Changes From This Date', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// TASK 2: Modal to add a single holiday or a date-range Override (Term Break, Exam Period, Holiday)
  void _showHolidayBreakModal(BuildContext context, String uid, HolidaySettings currentSettings) {
    final titleController = TextEditingController(text: 'Preparatory Leave (PL)');
    DateTime breakStart = _uniSelectedDay;
    DateTime breakEnd = _uniSelectedDay.add(const Duration(days: 6));
    DateTime singleHolidayDate = _uniSelectedDay;
    List<int> weeklyHolidays = List.from(currentSettings.weeklyHolidays);
    int selectedTab = 0; // 0: Range Override (Term Break / Exam Period), 1: Single Holiday, 2: Weekly Off-days
    OverrideType overrideType = OverrideType.termBreak;

    DateTime? semStart = currentSettings.semesterStart ?? DateTime(_uniSelectedDay.year, _uniSelectedDay.month <= 6 ? 1 : 7, 1);
    DateTime? semEnd = currentSettings.semesterEnd ?? DateTime(_uniSelectedDay.year, _uniSelectedDay.month <= 6 ? 6 : 12, 30);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          List<String> getPresetsForType(OverrideType type) {
            switch (type) {
              case OverrideType.examPeriod:
                return ['Midterm Exams', 'Term Final Exams', 'Lab Final Week', 'Class Test Week'];
              case OverrideType.termBreak:
                return ['Preparatory Leave (PL)', 'Mid Break', 'Semester Break', 'Study Vacation'];
              case OverrideType.holiday:
                return ['Eid Vacation', 'Durga Puja Vacation', 'Winter Vacation'];
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.beach_access_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Academic Calendar & Overrides',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Tab switcher (4 tabs)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        { 'id': 0, 'label': 'Range' },
                        { 'id': 1, 'label': 'Single Day' },
                        { 'id': 2, 'label': 'Weekly Off' },
                        { 'id': 3, 'label': 'Semester' },
                      ].map((tab) {
                        final tabId = tab['id'] as int;
                        final tabLabel = tab['label'] as String;
                        final isSel = selectedTab == tabId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setModalState(() => selectedTab = tabId),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSel ? const Color(0xFFF2B78A) : const Color(0xFF170F0D),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                tabLabel,
                                style: TextStyle(
                                  color: isSel ? const Color(0xFF110D0C) : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (selectedTab == 0) ...[
                    // Range Override Form (Term Break / Exam Period / Holiday)
                    const Text('OVERRIDE TYPE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        OverrideType.termBreak,
                        OverrideType.examPeriod,
                        OverrideType.holiday,
                      ].map((t) {
                        final isSelected = overrideType == t;
                        final Color activeColor = t == OverrideType.examPeriod
                            ? const Color(0xFF8B5CF6)
                            : (t == OverrideType.holiday ? const Color(0xFFEF4444) : const Color(0xFFF2B78A));

                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              t.displayName,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: activeColor,
                            backgroundColor: const Color(0xFF170F0D),
                            onSelected: (selected) {
                              if (selected) {
                                setModalState(() {
                                  overrideType = t;
                                  titleController.text = getPresetsForType(t).first;
                                });
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    const Text('TITLE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'e.g. Midterm Exams, Preparatory Leave (PL)',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFF170F0D),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: getPresetsForType(overrideType).map((preset) {
                        return ActionChip(
                          label: Text(preset, style: const TextStyle(color: Colors.white, fontSize: 10.5)),
                          backgroundColor: const Color(0xFF170F0D),
                          onPressed: () => setModalState(() => titleController.text = preset),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text('DATE RANGE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                          initialDateRange: DateTimeRange(start: breakStart, end: breakEnd),
                        );
                        if (picked != null) {
                          setModalState(() {
                            breakStart = picked.start;
                            breakEnd = picked.end;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF170F0D),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${breakStart.day} ${_getMonthName(breakStart.month)} - ${breakEnd.day} ${_getMonthName(breakEnd.month)} ${breakEnd.year}',
                              style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            ),
                            const Icon(Icons.date_range_rounded, color: Color(0xFFF2B78A), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: overrideType == OverrideType.examPeriod
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;

                          final newBreak = TermBreak(
                            title: title,
                            startDate: breakStart,
                            endDate: breakEnd,
                            type: overrideType,
                          );

                          final updated = currentSettings.copyWith(
                            termBreaks: [...currentSettings.termBreaks, newBreak],
                          );

                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('settings')
                              .doc('holidays')
                              .set(updated.toMap());

                          if (context.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('Save ${overrideType.displayName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ),
                    ),
                  ] else if (selectedTab == 1) ...[
                    // Single Day Holiday Form
                    const Text('SELECT DATE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: singleHolidayDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setModalState(() => singleHolidayDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF170F0D),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${singleHolidayDate.day} ${_getMonthName(singleHolidayDate.month)} ${singleHolidayDate.year}',
                              style: const TextStyle(color: Colors.white, fontSize: 13.5),
                            ),
                            const Icon(Icons.event_rounded, color: Color(0xFFF2B78A), size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: const Color(0xFF110D0C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final exists = currentSettings.specificHolidays.any((d) => isSameDay(d, singleHolidayDate));
                          if (!exists) {
                            final updated = currentSettings.copyWith(
                              specificHolidays: [...currentSettings.specificHolidays, singleHolidayDate],
                            );
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('settings')
                                .doc('holidays')
                                .set(updated.toMap());
                          }
                          if (context.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Single Holiday', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ),
                    ),
                  ] else if (selectedTab == 2) ...[
                    // Weekly Off-Days Form
                    const Text('WEEKLY OFF-DAYS', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        {'name': 'Friday', 'day': DateTime.friday},
                        {'name': 'Saturday', 'day': DateTime.saturday},
                        {'name': 'Sunday', 'day': DateTime.sunday},
                        {'name': 'Thursday', 'day': DateTime.thursday},
                      ].map((item) {
                        final dName = item['name'] as String;
                        final dVal = item['day'] as int;
                        final isSelected = weeklyHolidays.contains(dVal);

                        return FilterChip(
                          label: Text(dName, style: TextStyle(color: isSelected ? const Color(0xFF110D0C) : Colors.white, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedColor: const Color(0xFFF2B78A),
                          backgroundColor: const Color(0xFF170F0D),
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                weeklyHolidays.add(dVal);
                              } else {
                                weeklyHolidays.remove(dVal);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF2B78A),
                          foregroundColor: const Color(0xFF110D0C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final updated = currentSettings.copyWith(
                            weeklyHolidays: weeklyHolidays,
                          );
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('settings')
                              .doc('holidays')
                              .set(updated.toMap());
                          if (context.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Save Weekly Off-Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                      ),
                    ),
                  ] else ...[
                    // TASK 4: Active Semester Boundaries Form
                    const Text('SEMESTER START & END DATES', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Regular class routine is active exclusively between these dates.',
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: semStart ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) setModalState(() => semStart = picked);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF170F0D), borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('START DATE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    semStart != null ? '${semStart!.day}/${semStart!.month}/${semStart!.year}' : 'Not set',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: semEnd ?? DateTime.now().add(const Duration(days: 120)),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) setModalState(() => semEnd = picked);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFF170F0D), borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('END DATE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    semEnd != null ? '${semEnd!.day}/${semEnd!.month}/${semEnd!.year}' : 'Not set',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (currentSettings.semesterStart != null || currentSettings.semesterEnd != null) ...[
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              final updated = currentSettings.copyWith(
                                semesterStart: null,
                                semesterEnd: null,
                              );
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('settings')
                                  .doc('holidays')
                                  .set(updated.toMap());
                              if (context.mounted) Navigator.pop(ctx);
                            },
                            child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: SizedBox(
                            height: 46,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2B78A),
                                foregroundColor: const Color(0xFF110D0C),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () async {
                                final updated = currentSettings.copyWith(
                                  semesterStart: semStart,
                                  semesterEnd: semEnd,
                                );
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .collection('settings')
                                    .doc('holidays')
                                    .set(updated.toMap());
                                if (context.mounted) Navigator.pop(ctx);
                              },
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: const Text('Save Semester Dates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Active Breaks & Overrides List
                  Text(
                    'Active Overrides & Dates (${currentSettings.termBreaks.length + currentSettings.specificHolidays.length})',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (currentSettings.termBreaks.isEmpty && currentSettings.specificHolidays.isEmpty)
                    Text('No academic overrides or single holidays added yet.', style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12))
                  else ...[
                    ...currentSettings.termBreaks.map((b) {
                      final Color badgeColor = b.type == OverrideType.examPeriod
                          ? const Color(0xFF8B5CF6)
                          : (b.type == OverrideType.holiday ? const Color(0xFFEF4444) : const Color(0xFFF2B78A));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF170F0D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(b.title, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        b.type.displayName,
                                        style: TextStyle(color: badgeColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text('${b.startDate.day}/${b.startDate.month} - ${b.endDate.day}/${b.endDate.month}/${b.endDate.year}', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                              onPressed: () async {
                                final updated = currentSettings.copyWith(
                                  termBreaks: currentSettings.termBreaks.where((item) => item.id != b.id).toList(),
                                );
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .collection('settings')
                                    .doc('holidays')
                                    .set(updated.toMap());
                                setModalState(() {});
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    ...currentSettings.specificHolidays.map((h) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Holiday: ${h.day} ${_getMonthName(h.month)} ${h.year}', style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            onPressed: () async {
                              final updated = currentSettings.copyWith(
                                specificHolidays: currentSettings.specificHolidays.where((item) => !isSameDay(item, h)).toList(),
                              );
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('settings')
                                  .doc('holidays')
                                  .set(updated.toMap());
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                    )),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// TASK 1-4: The Unified Academic Planner Screen
  Widget _buildUniversityAssessmentsScreen(BuildContext context, UserProfile userProfile) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        backgroundColor: backgroundColor,
        body: Center(child: Text('Please sign in to view planner', style: TextStyle(color: Colors.white))),
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('holidays')
          .snapshots(),
      builder: (context, holidaySnap) {
        final holidayData = holidaySnap.data?.data();
        final holidaySettings = holidayData != null
            ? HolidaySettings.fromMap(holidayData)
            : HolidaySettings.defaultSettings;

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('courses')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, courseSnap) {
            final rawCourseDocs = courseSnap.data?.docs ?? [];
            final courseDocs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(rawCourseDocs);
            courseDocs.sort((a, b) => compareCourseCodes(
              a.data()['courseCode'] as String? ?? a.id,
              b.data()['courseCode'] as String? ?? b.id,
            ));

            // Extract all assessments across all courses safely
            final Map<String, String> courseCodeMap = {};
            final Map<String, String> courseTitleMap = {};
            final List<Assessment> courseDocAssessments = [];

            for (final doc in courseDocs) {
              final data = doc.data();
              final cCode = data['courseCode'] as String? ?? 'Course';
              final cTitle = data['courseTitle'] as String? ?? data['title'] as String? ?? data['name'] as String? ?? '';
              courseCodeMap[doc.id] = cCode;
              courseTitleMap[doc.id] = cTitle;
              courseDocAssessments.addAll(
                Assessment.fromCourseData(data, courseId: doc.id),
              );
            }

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collectionGroup('assessments')
                  .snapshots()
                  .handleError((e) {
                    debugPrint('collectionGroup assessments stream error: $e');
                  }),
              builder: (context, groupSnap) {
                final List<Assessment> allAssessments = List.from(courseDocAssessments);

                if (groupSnap.hasData && groupSnap.data != null) {
                  for (final doc in groupSnap.data!.docs) {
                    final data = doc.data();
                    final path = doc.reference.path;
                    final bool isUserDoc = (data['userId'] == uid) ||
                        path.startsWith('users/$uid/') ||
                        path.contains('users/$uid/') ||
                        path.contains('/users/$uid/');

                    if (isUserDoc) {
                      String derivedCourseId = '';
                      final pathSegments = path.split('/');
                      final courseIdx = pathSegments.indexOf('courses');
                      if (courseIdx != -1 && courseIdx + 1 < pathSegments.length) {
                        derivedCourseId = pathSegments[courseIdx + 1];
                      }
                      final ass = Assessment.fromMap(
                        data,
                        defaultId: doc.id,
                        defaultCourseId: derivedCourseId.isNotEmpty ? derivedCourseId : null,
                      );
                      if (ass.courseId.isEmpty && derivedCourseId.isNotEmpty) {
                        ass.courseId = derivedCourseId;
                      }
                      final existingIdx = allAssessments.indexWhere((x) =>
                          (x.id.isNotEmpty && ass.id.isNotEmpty && x.id == ass.id) ||
                          (x.courseId.isNotEmpty &&
                              ass.courseId.isNotEmpty &&
                              x.courseId == ass.courseId &&
                              x.name.trim().toLowerCase() == ass.name.trim().toLowerCase()));
                      if (existingIdx >= 0) {
                        allAssessments[existingIdx] = ass;
                      } else {
                        allAssessments.add(ass);
                      }
                    }
                  }
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('routine')
                      .snapshots(),
              builder: (context, routineSnap) {
                final routineDocs = routineSnap.data?.docs ?? [];
                final allRoutines = routineDocs
                    .map((d) => ClassRoutine.fromMap(d.data(), defaultId: d.id))
                    .toList();

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('attendance_records')
                      .snapshots(),
                  builder: (context, attSnap) {
                    final attDocs = attSnap.data?.docs ?? [];
                    final allAttendanceDocs = attDocs;

                    final Map<String, AttendanceRecord> dateAttendanceMap = {};
                    final List<AttendanceRecord> extraClassesForDay = [];

                    for (final doc in attDocs) {
                      final rec = AttendanceRecord.fromMap(doc.data(), defaultId: doc.id);
                      if (isSameDay(rec.date, _uniSelectedDay)) {
                        if (rec.routineId != null) {
                          dateAttendanceMap[rec.routineId!] = rec;
                          dateAttendanceMap['${rec.courseId}_${rec.routineId!}'] = rec;
                          if (rec.courseCode != null && rec.courseCode!.isNotEmpty) {
                            dateAttendanceMap['${rec.courseCode}_${rec.routineId!}'] = rec;
                            final san = RoutineCourseSyncService.sanitizeDocId(rec.courseCode!);
                            dateAttendanceMap['${san}_${rec.routineId!}'] = rec;
                          }
                          final parsedCourseCode = RoutineCourseSyncService.parseCourseCode(rec.courseName ?? rec.courseId);
                          dateAttendanceMap['${parsedCourseCode}_${rec.routineId!}'] = rec;
                          final sanFromParsed = RoutineCourseSyncService.sanitizeDocId(parsedCourseCode);
                          dateAttendanceMap['${sanFromParsed}_${rec.routineId!}'] = rec;
                        }
                        final bool isExplicitlyExtra = rec.status == AttendanceStatus.extra ||
                            (rec.routineId != null && rec.routineId!.startsWith('extra')) ||
                            (rec.id.contains('_extra_')) ||
                            (rec.classType != null && (
                              rec.classType!.toLowerCase().contains('extra') ||
                              rec.classType!.toLowerCase().contains('make-up') ||
                              rec.classType!.toLowerCase().contains('makeup') ||
                              rec.classType!.toLowerCase().contains('review')
                            ));
                        if (isExplicitlyExtra) {
                          extraClassesForDay.add(rec);
                        }
                      }
                    }

                    // Events stream for Non-Academic Calendar Events (TASK 2)
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('events')
                          .snapshots(),
                      builder: (context, eventSnap) {
                        final eventDocs = eventSnap.data?.docs ?? [];
                        final List<PlannerEvent> allEvents = eventDocs
                            .map((d) => PlannerEvent.fromMap(d.data(), d.id))
                            .toList();

                        // Events for the currently selected calendar date
                        final selectedDayEvents = allEvents.where((e) {
                          return isSameDay(e.date, _uniSelectedDay);
                        }).toList();

                        bool isSameCalendarDay(DateTime? a, DateTime? b) {
                          if (a == null || b == null) return false;
                          if (a.year == b.year && a.month == b.month && a.day == b.day) return true;
                          final localA = a.toLocal();
                          final localB = b.toLocal();
                          if (localA.year == localB.year &&
                              localA.month == localB.month &&
                              localA.day == localB.day) {
                            return true;
                          }
                          final utcA = a.toUtc();
                          final utcB = b.toUtc();
                          return utcA.year == utcB.year &&
                              utcA.month == utcB.month &&
                              utcA.day == utcB.day;
                        }

                        // Assessments for the currently selected calendar date
                        final selectedDayAssessments = allAssessments
                            .where((item) => isSameCalendarDay(item.date ?? item.dueDate, _uniSelectedDay))
                            .toList();

                        // Holiday / Term Break override status for selected date
                        final isHoliday = holidaySettings.isHoliday(_uniSelectedDay);
                        final holidayReason = holidaySettings.getHolidayReason(_uniSelectedDay);

                        // Routine classes for selected date strictly respecting lifecycle boundaries and semester range (TASK 3)
                        final isWithinSemester = holidaySettings.isWithinSemester(_uniSelectedDay);
                        final dayRoutines = isWithinSemester
                            ? RoutineCourseSyncService.sortRoutinesByTime(
                                allRoutines.where((r) => r.isActiveOnDate(_uniSelectedDay)).toList(),
                              )
                            : <ClassRoutine>[];
                        final offWeekRoutines = isWithinSemester
                            ? allRoutines.where((r) {
                                if (r.dayOfWeek != _uniSelectedDay.weekday) return false;
                                final isBiweekly = r.isAlternating || r.recurrence == 'biweekly_a' || r.recurrence == 'biweekly_b';
                                if (!isBiweekly) return false;
                                if (r.isActiveOnDate(_uniSelectedDay)) return false;
                                final d = DateTime(_uniSelectedDay.year, _uniSelectedDay.month, _uniSelectedDay.day);
                                if (r.effectiveFrom != null && d.isBefore(DateTime(r.effectiveFrom!.year, r.effectiveFrom!.month, r.effectiveFrom!.day))) return false;
                                if (r.effectiveUntil != null && d.isAfter(DateTime(r.effectiveUntil!.year, r.effectiveUntil!.month, r.effectiveUntil!.day))) return false;
                                return true;
                              }).toList()
                            : <ClassRoutine>[];

                        // Unified agenda items: Class routines and assessments merged and sorted chronologically
                        final unifiedAgendaItems = RoutineCourseSyncService.mergeAndSortAgenda(
                          routines: (isWithinSemester && !isHoliday && !holidaySettings.isExamPeriod(_uniSelectedDay))
                              ? dayRoutines
                              : <ClassRoutine>[],
                          assessments: selectedDayAssessments,
                        );

                        return ShowCaseWidget(
                          enableAutoScroll: true,
                          blurValue: 2.0,
                          onFinish: () => TourService().markTourSeen(TourSection.planner),
                          builder: (showcaseContext) {
                            _triggerPlannerTourIfNeeded(showcaseContext);
                            return Scaffold(
                      backgroundColor: backgroundColor,
                      appBar: AppBar(
                        backgroundColor: backgroundColor,
                        elevation: 0,
                        title: Text(
                          'Academic Planner',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        actions: [
                          // TASK 1: "Today" button to reset focused and selected day back to DateTime.now()
                          IconButton(
                            icon: const Icon(Icons.today_rounded, color: Color(0xFFF2B78A), size: 22),
                            tooltip: 'Today',
                            onPressed: () {
                              SafeHaptics.lightImpact();
                              setState(() {
                                final now = DateTime.now();
                                _uniSelectedDay = now;
                                _uniFocusedDay = now;
                              });
                            },
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70, size: 22),
                            color: const Color(0xFF241C1A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFF4A3830)),
                            ),
                            tooltip: 'Planner Options',
                            onSelected: (val) {
                              SafeHaptics.lightImpact();
                              if (val == 'routine') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const RoutineScreen()),
                                );
                              } else if (val == 'matrix') {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()),
                                );
                              } else if (val == 'dates') {
                                _handleSemesterDatesPicker(context, uid, holidaySettings);
                              } else if (val == 'holidays') {
                                _showHolidayBreakModal(context, uid, holidaySettings);
                              } else if (val == 'cgpa') {
                                final uni = userProfile.universityName ?? 'BUET';
                                final term = userProfile.term ?? '1';
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TermPerformanceScreen(universityName: uni, term: term),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'routine',
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_view_week_rounded, color: Color(0xFFF2B78A), size: 18),
                                    SizedBox(width: 10),
                                    Text('Routine Settings', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'matrix',
                                child: Row(
                                  children: [
                                    Icon(Icons.grid_view_rounded, color: Color(0xFF10B981), size: 18),
                                    SizedBox(width: 10),
                                    Text('Matrix View', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'dates',
                                child: Row(
                                  children: [
                                    Icon(Icons.date_range_rounded, color: Color(0xFFF2B78A), size: 18),
                                    SizedBox(width: 10),
                                    Text('Semester Dates', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'holidays',
                                child: Row(
                                  children: [
                                    Icon(Icons.beach_access_rounded, color: Color(0xFFF59E0B), size: 18),
                                    SizedBox(width: 10),
                                    Text('Holidays & Breaks', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'cgpa',
                                child: Row(
                                  children: [
                                    Icon(Icons.insights_rounded, color: Color(0xFFA855F7), size: 18),
                                    SizedBox(width: 10),
                                    Text('Term CGPA Simulator', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      body: SafeArea(
                        child: Stack(
                          children: [
                            SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // TASK 1: TableCalendar with Glass Styling & Dynamic User Holidays
                                  TourShowcaseItem(
                                    section: TourSection.planner,
                                    step: TourStep(
                                      key: _keyPlannerCalendar,
                                      title: 'Academic Calendar',
                                      description: 'View scheduled classes, assessment deadlines, term exams, and official university holidays in one unified view.',
                                    ),
                                    stepIndex: 1,
                                    totalSteps: 3,
                                    child: buildGlassCard(
                                    padding: const EdgeInsets.all(12),
                                    borderRadius: BorderRadius.circular(12),
                                    child: TableCalendar<dynamic>(
                                      firstDay: DateTime.utc(2020, 1, 1),
                                      lastDay: DateTime.utc(2035, 12, 31),
                                      focusedDay: _uniFocusedDay,
                                      currentDay: DateTime.now(),
                                      calendarFormat: CalendarFormat.month,
                                      startingDayOfWeek: StartingDayOfWeek.saturday,
                                      weekendDays: const [], // TASK 1: Override default hardcoded Sat/Sun weekends
                                      holidayPredicate: (day) => holidaySettings.isHoliday(day),
                                      headerStyle: HeaderStyle(
                                        formatButtonVisible: false,
                                        titleCentered: true,
                                        titleTextStyle: AppTypography.cardTitle,
                                        leftChevronIcon: const Icon(Icons.chevron_left_rounded, color: AppColors.primary),
                                        rightChevronIcon: const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
                                      ),
                                      daysOfWeekStyle: const DaysOfWeekStyle(
                                        weekdayStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                                        weekendStyle: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                      calendarStyle: CalendarStyle(
                                        outsideDaysVisible: true,
                                        defaultTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
                                        weekendTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
                                        holidayTextStyle: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                        todayDecoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.15),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.primary),
                                        ),
                                        selectedDecoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        selectedTextStyle: const TextStyle(color: Color(0xFF140F0E), fontWeight: FontWeight.bold),
                                      ),
                                      selectedDayPredicate: (day) =>
                                           day.year == _uniSelectedDay.year &&
                                           day.month == _uniSelectedDay.month &&
                                           day.day == _uniSelectedDay.day,
                                      onDaySelected: (selectedDay, focusedDay) {
                                        SafeHaptics.lightImpact();
                                        setState(() {
                                          _uniSelectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                                          _uniFocusedDay = focusedDay;
                                        });
                                      },
                                      eventLoader: (day) {
                                        final ass = allAssessments.where((a) => isSameCalendarDay(a.date ?? a.dueDate, day)).toList();
                                        final evs = allEvents.where((e) => isSameCalendarDay(e.date, day)).toList();
                                        return [...ass, ...evs];
                                      },
                                      calendarBuilders: CalendarBuilders(
                                        dowBuilder: (context, day) {
                                          final isWeeklyOff = holidaySettings.weeklyHolidays.contains(day.weekday);
                                          final text = _getShortDayName(day.weekday);
                                          return Center(
                                            child: Text(
                                              text,
                                              style: TextStyle(
                                                color: isWeeklyOff ? Colors.redAccent : Colors.blueGrey.shade400,
                                                fontWeight: isWeeklyOff ? FontWeight.bold : FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          );
                                        },
                                        defaultBuilder: (context, day, focusedDay) {
                                          if (holidaySettings.isHoliday(day)) {
                                            return Center(
                                              child: Text(
                                                '${day.day}',
                                                style: const TextStyle(
                                                  color: Colors.redAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            );
                                          }
                                          return null;
                                        },
                                        holidayBuilder: (context, day, focusedDay) {
                                          return Center(
                                            child: Text(
                                              '${day.day}',
                                              style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          );
                                        },
                                        outsideBuilder: (context, day, focusedDay) {
                                          final isHol = holidaySettings.isHoliday(day);
                                          return Center(
                                            child: Text(
                                              '${day.day}',
                                              style: TextStyle(
                                                color: isHol ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white24,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                          );
                                        },
                                        markerBuilder: (context, date, events) {
                                          if (events.isNotEmpty) {
                                            return Positioned(
                                              bottom: 4,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: events.take(3).map((_) {
                                                  return Container(
                                                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                                    width: 5,
                                                    height: 5,
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFF10B981),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            );
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                  ),
                                  ),
                                  const SizedBox(height: 20),

                                  // TASK 3: The Unified Daily Agenda Header & Overrides Evaluation
                                  TourShowcaseItem(
                                    section: TourSection.planner,
                                    step: TourStep(
                                      key: _keyPlannerAssessments,
                                      title: 'Pinned Assessments',
                                      description: 'Assessments and class tests always sit above your regular schedule so urgent deadlines are never missed.',
                                    ),
                                    stepIndex: 2,
                                    totalSteps: 3,
                                    child: Builder(
                                      builder: (context) {
                                        final override = holidaySettings.getTermBreakForDate(_uniSelectedDay);
                                        final isExamPeriod = override?.type == OverrideType.examPeriod;

                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Agenda: ${_uniSelectedDay.day} ${_getMonthName(_uniSelectedDay.month)} (${_getDayName(_uniSelectedDay.weekday)})',
                                              style: GoogleFonts.plusJakartaSans(
                                                color: const Color(0xFFF2B78A),
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (isExamPeriod)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                                                ),
                                                child: const Text('Exam Period', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 11, fontWeight: FontWeight.bold)),
                                              )
                                            else if (isHoliday)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent.withValues(alpha: 0.18),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                                                ),
                                                child: const Text('Holiday', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // TASK 3.1 & 3.2: EVALUATE OVERRIDES (EXAM PERIOD vs HOLIDAY vs REGULAR ROUTINE)
                                  Builder(
                                    builder: (context) {
                                      final override = holidaySettings.getTermBreakForDate(_uniSelectedDay);
                                      final isExamPeriod = override?.type == OverrideType.examPeriod;

                                      if (isExamPeriod) {
                                        // 1. EXAM PERIOD OVERRIDE
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 14),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.assignment_late_rounded, color: Color(0xFFA78BFA), size: 24),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '${override?.title ?? 'Exam Period'} - No Regular Classes',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    const Text(
                                                      'Regular class routine is suspended during exam periods. Scheduled assessments are shown below.',
                                                      style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      } else if (isHoliday) {
                                        // 2. HOLIDAY / TERM BREAK OVERRIDE
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 14),
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.beach_access_rounded, color: Colors.redAccent, size: 24),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      holidayReason ?? 'Holiday - No Regular Classes',
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    const Text(
                                                      'Regular class routine is paused for this day.',
                                                      style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),

                                  // Non-Academic Events (Club, Seminars, Workshops, etc.)
                                  if (selectedDayEvents.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.event_note_rounded, color: Color(0xFFF2B78A), size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Events & Activities (${selectedDayEvents.length})',
                                          style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...selectedDayEvents.map((event) => _buildPlannerEventCard(
                                          context: context,
                                          uid: uid,
                                          event: event,
                                          cardColor: cardColor,
                                          accentColor: accentColor,
                                        )),
                                    const SizedBox(height: 8),
                                  ],

                                  // Holiday / Exam Period Overrides or Outside Semester
                                  if (holidaySettings.isExamPeriod(_uniSelectedDay)) ...[
                                    if (unifiedAgendaItems.isEmpty)
                                      Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'No specific exams scheduled on this exam period date.',
                                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                                          ),
                                        ),
                                      )
                                    else ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF59E0B), size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Scheduled Exams (${unifiedAgendaItems.length})',
                                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...unifiedAgendaItems.map((item) {
                                        final assessment = item.assessment!;
                                        String courseCode = courseCodeMap[assessment.courseId] ?? '';
                                        if (courseCode.isEmpty) {
                                          for (final entry in courseCodeMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseCode = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        if (courseCode.isEmpty) {
                                          courseCode = assessment.courseId.isNotEmpty ? assessment.courseId : 'Course';
                                        }
                                        String courseTitle = courseTitleMap[assessment.courseId] ?? '';
                                        if (courseTitle.isEmpty) {
                                          for (final entry in courseTitleMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseTitle = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        return _buildAssessmentCard(
                                          context: context,
                                          uid: uid,
                                          assessment: assessment,
                                          courseCode: courseCode,
                                          courseTitle: courseTitle,
                                          cardColor: cardColor,
                                          accentColor: accentColor,
                                        );
                                      }),
                                      const SizedBox(height: 8),
                                    ],
                                  ] else if (!holidaySettings.isWithinSemester(_uniSelectedDay)) ...[
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.event_busy_rounded, color: Color(0xFFF59E0B), size: 24),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Outside Active Semester',
                                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'Regular class routine is inactive. Configured semester runs from ${holidaySettings.semesterStart != null ? '${holidaySettings.semesterStart!.day}/${holidaySettings.semesterStart!.month}/${holidaySettings.semesterStart!.year}' : 'N/A'} to ${holidaySettings.semesterEnd != null ? '${holidaySettings.semesterEnd!.day}/${holidaySettings.semesterEnd!.month}/${holidaySettings.semesterEnd!.year}' : 'N/A'}.',
                                                  style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selectedDayAssessments.isNotEmpty) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF59E0B), size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Assessments (${selectedDayAssessments.length})',
                                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...selectedDayAssessments.map((assessment) {
                                        String courseCode = courseCodeMap[assessment.courseId] ?? '';
                                        if (courseCode.isEmpty) {
                                          for (final entry in courseCodeMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseCode = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        if (courseCode.isEmpty) {
                                          courseCode = assessment.courseId.isNotEmpty ? assessment.courseId : 'Course';
                                        }
                                        String courseTitle = courseTitleMap[assessment.courseId] ?? '';
                                        if (courseTitle.isEmpty) {
                                          for (final entry in courseTitleMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseTitle = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        return _buildAssessmentCard(
                                          context: context,
                                          uid: uid,
                                          assessment: assessment,
                                          courseCode: courseCode,
                                          courseTitle: courseTitle,
                                          cardColor: cardColor,
                                          accentColor: accentColor,
                                        );
                                      }),
                                    ],
                                  ] else if (!holidaySettings.isHoliday(_uniSelectedDay)) ...[
                                    // UNIFIED AGENDA LIST: Merged Class Routine & Assessments sorted chronologically
                                    if (unifiedAgendaItems.isEmpty) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(18),
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'No classes or assessments scheduled for ${_getDayName(_uniSelectedDay.weekday)}.',
                                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                                          ),
                                        ),
                                      ),
                                      if (offWeekRoutines.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        ...offWeekRoutines.map((offRoutine) => _buildOffWeekRoutineCard(
                                              context: context,
                                              uid: uid,
                                              offRoutine: offRoutine,
                                              allRoutines: allRoutines,
                                              courseDocs: courseDocs,
                                            )),
                                      ],
                                    ] else ...[
                                      ...(() {
                                        final agendaAssessments = unifiedAgendaItems.where((it) => it.isAssessment).toList();
                                        final agendaRoutines = unifiedAgendaItems.where((it) => it.isRoutine).toList();

                                        return [
                                          if (agendaAssessments.isNotEmpty) ...[
                                            Row(
                                              children: [
                                                const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF59E0B), size: 16),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Assessments & Deadlines (${agendaAssessments.length})',
                                                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            ...agendaAssessments.map((item) {
                                              final assessment = item.assessment!;
                                              String courseCode = courseCodeMap[assessment.courseId] ?? '';
                                              if (courseCode.isEmpty) {
                                                for (final entry in courseCodeMap.entries) {
                                                  if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                                    courseCode = entry.value;
                                                    break;
                                                  }
                                                }
                                              }
                                              if (courseCode.isEmpty) {
                                                courseCode = assessment.courseId.isNotEmpty ? assessment.courseId : 'Course';
                                              }
                                              String courseTitle = courseTitleMap[assessment.courseId] ?? '';
                                              if (courseTitle.isEmpty) {
                                                for (final entry in courseTitleMap.entries) {
                                                  if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                                    courseTitle = entry.value;
                                                    break;
                                                  }
                                                }
                                              }
                                              return _buildAssessmentCard(
                                                context: context,
                                                uid: uid,
                                                assessment: assessment,
                                                courseCode: courseCode,
                                                courseTitle: courseTitle,
                                                cardColor: cardColor,
                                                accentColor: accentColor,
                                              );
                                            }),
                                          ],
                                          if (agendaAssessments.isNotEmpty && agendaRoutines.isNotEmpty)
                                            const SizedBox(height: 14),
                                          if (agendaRoutines.isNotEmpty) ...[
                                            Row(
                                              children: [
                                                const Icon(Icons.schedule_rounded, color: Color(0xFFF2B78A), size: 16),
                                                const SizedBox(width: 6),
                                                Text(
                                                  'Class Schedule (${agendaRoutines.length})',
                                                  style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            ...agendaRoutines.map((item) {
                                              final routine = item.routine!;
                                               return _buildClassRoutineCard(
                                                 context: context,
                                                 uid: uid,
                                                 routine: routine,
                                                 dateAttendanceMap: dateAttendanceMap,
                                                 allAttendanceDocs: allAttendanceDocs,
                                                 allRoutines: allRoutines,
                                                 courseDocs: courseDocs,
                                                 attendanceKey: (agendaRoutines.indexOf(item) == 0)
                                                     ? _keyPlannerAttendance
                                                     : null,
                                               );
                                            }),
                                          ],
                                        ];
                                      }()),
                                      if (offWeekRoutines.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        ...offWeekRoutines.map((offRoutine) => _buildOffWeekRoutineCard(
                                              context: context,
                                              uid: uid,
                                              offRoutine: offRoutine,
                                              allRoutines: allRoutines,
                                              courseDocs: courseDocs,
                                            )),
                                      ],
                                    ],
                                  ] else if (holidaySettings.isHoliday(_uniSelectedDay)) ...[
                                    if (selectedDayAssessments.isNotEmpty) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFFF59E0B), size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Assessments (${selectedDayAssessments.length})',
                                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ...selectedDayAssessments.map((assessment) {
                                        String courseCode = courseCodeMap[assessment.courseId] ?? '';
                                        if (courseCode.isEmpty) {
                                          for (final entry in courseCodeMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseCode = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        if (courseCode.isEmpty) {
                                          courseCode = assessment.courseId.isNotEmpty ? assessment.courseId : 'Course';
                                        }
                                        String courseTitle = courseTitleMap[assessment.courseId] ?? '';
                                        if (courseTitle.isEmpty) {
                                          for (final entry in courseTitleMap.entries) {
                                            if (entry.key.toLowerCase() == assessment.courseId.toLowerCase()) {
                                              courseTitle = entry.value;
                                              break;
                                            }
                                          }
                                        }
                                        return _buildAssessmentCard(
                                          context: context,
                                          uid: uid,
                                          assessment: assessment,
                                          courseCode: courseCode,
                                          courseTitle: courseTitle,
                                          cardColor: cardColor,
                                          accentColor: accentColor,
                                        );
                                      }),
                                    ],
                                  ],

                                  if (extraClassesForDay.isNotEmpty) ...[
                                    Row(
                                      children: [
                                        const Icon(Icons.more_time_rounded, color: Color(0xFFF59E0B), size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Extra Classes (${extraClassesForDay.length})',
                                          style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...extraClassesForDay.map((ex) => _buildExtraClassCard(
                                      context: context,
                                      uid: uid,
                                      ex: ex,
                                      courseDocs: courseDocs,
                                    )),
                                    const SizedBox(height: 6),
                                  ],

                                  // Add Extra Class Action Button (ALWAYS RENDERED)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFF2B78A),
                                        side: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () => _showAddExtraClassModal(context, uid, courseDocs),
                                      icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFFF2B78A)),
                                      label: const Text('Add Extra / Makeup Class', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                  ),

                                  const SizedBox(height: 90),
                                ],
                              ),
                            ),

                            // Unified Floating Action Button
                            Positioned(
                              bottom: 20,
                              right: 16,
                              child: FloatingActionButton(
                                heroTag: 'unified_planner_add_btn',
                                backgroundColor: const Color(0xFFF2B78A),
                                foregroundColor: const Color(0xFF140F0E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                tooltip: 'Create Item',
                                onPressed: () => _showUnifiedCreateSheet(context, courseDocs),
                                child: const Icon(Icons.add, size: 26),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
                );
              },
            );
          },
        );
      },
    );
  },
);
      },
    );
  }
}

class _JournalInputItem {
  String type;
  final TextEditingController controller;

  _JournalInputItem({
    required this.type,
    required this.controller,
  });
}

/// Modal dialog / sheet for creating assessments with dedicated Topics / Syllabus Covered field
class CreateAssessmentDialog extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> courses;
  final Function(Assessment assessment, String courseCode)? onSaved;

  const CreateAssessmentDialog({
    super.key,
    required this.courses,
    this.onSaved,
  });

  @override
  State<CreateAssessmentDialog> createState() => _CreateAssessmentDialogState();
}

class _CreateAssessmentDialogState extends State<CreateAssessmentDialog> {
  late String selectedCourseId;
  late String selectedCourseCode;
  String selectedType = 'Class Test (CT)';

  final nameCtrl = TextEditingController(text: 'CT 1');
  final topicsCtrl = TextEditingController();
  final totalMarksCtrl = TextEditingController(text: '20');
  final weightageCtrl = TextEditingController(text: '10');
  DateTime selectedDateTime = DateTime.now().add(const Duration(days: 3, hours: 2));

  late List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedCourses;

  List<String> _getAvailableAssessmentTypes(String courseId) {
    final doc = widget.courses.where((d) => d.id == courseId).firstOrNull;
    final courseType = CourseType.fromString(doc?.data()['courseType'] as String?);
    return courseType == CourseType.sessional
        ? kSessionalAssessmentTypes
        : kTheoryAssessmentTypes;
  }

  @override
  void initState() {
    super.initState();
    _sortedCourses = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(widget.courses);
    _sortedCourses.sort((a, b) => compareCourseCodes(
      a.data()['courseCode'] as String? ?? a.id,
      b.data()['courseCode'] as String? ?? b.id,
    ));
    selectedCourseId = _sortedCourses.isNotEmpty ? _sortedCourses.first.id : '';
    selectedCourseCode = _sortedCourses.isNotEmpty
        ? (_sortedCourses.first.data()['courseCode'] as String? ?? 'Course')
        : 'Course';

    if (selectedCourseId.isNotEmpty) {
      final availableTypes = _getAvailableAssessmentTypes(selectedCourseId);
      selectedType = availableTypes.first;
      _autoSequenceAssessment(selectedCourseId, selectedType);
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    topicsCtrl.dispose();
    totalMarksCtrl.dispose();
    weightageCtrl.dispose();
    super.dispose();
  }

  String _typeToTypeCode(String typeStr) {
    switch (typeStr) {
      case 'Class Test (CT)':
        return 'ct';
      case 'Quiz':
      case 'Quiz / Viva':
        return 'quiz';
      case 'Midterm Exam':
        return 'midterm';
      case 'Final Exam':
      case 'Term Final Exam':
        return 'final';
      case 'Assignment / Presentation':
      case 'Assignment / Report':
        return 'assignment';
      case 'Continuous Evaluation / Lab Performance':
        return 'continuous';
      case 'Lab Report / Assignment':
        return 'lab_report';
      case 'Lab Quiz':
        return 'lab_quiz';
      case 'Lab Final Exam':
        return 'lab_final';
      case 'Viva Voce':
        return 'viva';
      case 'Term Project / Presentation':
        return 'project';
      default:
        return 'ct';
    }
  }

  Set<int> _extractExistingCtNumbers(Map<String, dynamic>? courseData) {
    final Set<int> numbers = {};
    if (courseData == null) return numbers;

    final rawAss = courseData['assessments'];
    if (rawAss is Map) {
      final rawCts = rawAss['classTests'];
      if (rawCts is List) {
        for (final item in rawCts) {
          if (item is Map) {
            final name = item['name'] as String? ?? '';
            final match = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(name);
            if (match != null) {
              final n = int.tryParse(match.group(1) ?? '');
              if (n != null) numbers.add(n);
            }
          }
        }
      }
    } else if (rawAss is List) {
      for (final item in rawAss) {
        if (item is Map) {
          final name = item['name'] as String? ?? '';
          final match = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(name);
          if (match != null) {
            final n = int.tryParse(match.group(1) ?? '');
            if (n != null) numbers.add(n);
          }
        }
      }
    }
    return numbers;
  }

  void _autoSequenceAssessment(String courseId, String typeStr) {
    final doc = widget.courses.where((d) => d.id == courseId).firstOrNull;
    final courseData = doc?.data();

    if (typeStr == 'Class Test (CT)') {
      final ctNumbers = _extractExistingCtNumbers(courseData);
      final nextCtNum = ctNumbers.isEmpty ? 1 : (ctNumbers.reduce((a, b) => a > b ? a : b) + 1);
      nameCtrl.text = 'CT $nextCtNum';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '10';
    } else if (typeStr == 'Quiz' || typeStr == 'Quiz / Viva') {
      nameCtrl.text = 'Quiz 1';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '10';
    } else if (typeStr == 'Midterm Exam') {
      nameCtrl.text = 'Midterm Exam';
      totalMarksCtrl.text = '30';
      weightageCtrl.text = '30';
    } else if (typeStr == 'Term Final Exam' || typeStr == 'Final Exam') {
      nameCtrl.text = 'Term Final Exam';
      totalMarksCtrl.text = '210';
      weightageCtrl.text = '50';
    } else if (typeStr == 'Assignment / Presentation' || typeStr == 'Assignment / Report') {
      nameCtrl.text = 'Assignment 1';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '10';
    } else if (typeStr == 'Continuous Evaluation / Lab Performance') {
      nameCtrl.text = 'Continuous Evaluation';
      totalMarksCtrl.text = '30';
      weightageCtrl.text = '25';
    } else if (typeStr == 'Lab Report / Assignment') {
      nameCtrl.text = 'Lab Report 1';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '15';
    } else if (typeStr == 'Lab Quiz') {
      nameCtrl.text = 'Lab Quiz 1';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '15';
    } else if (typeStr == 'Lab Final Exam') {
      nameCtrl.text = 'Lab Final Exam';
      totalMarksCtrl.text = '50';
      weightageCtrl.text = '30';
    } else if (typeStr == 'Viva Voce') {
      nameCtrl.text = 'Viva Voce';
      totalMarksCtrl.text = '20';
      weightageCtrl.text = '15';
    } else if (typeStr == 'Term Project / Presentation') {
      nameCtrl.text = 'Term Project';
      totalMarksCtrl.text = '50';
      weightageCtrl.text = '25';
    }
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1) % 12];
  }

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF241C1A);
    const borderColor = Color(0xFF4A3830);
    const accentColor = Color(0xFFF2B78A);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_task_rounded, color: accentColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Schedule Assessment',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Course Dropdown
            Text(
              'COURSE',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedCourseId,
                  isExpanded: true,
                  dropdownColor: surfaceColor,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                  items: _sortedCourses.map((doc) {
                    final data = doc.data();
                    final code = data['courseCode'] as String? ?? 'Course';
                    final name = data['courseName'] as String? ?? '';
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text('$code - $name', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        selectedCourseId = val;
                        final doc = _sortedCourses.firstWhere((d) => d.id == val);
                        selectedCourseCode = doc.data()['courseCode'] as String? ?? 'Course';
                        final availableTypes = _getAvailableAssessmentTypes(selectedCourseId);
                        if (!availableTypes.contains(selectedType)) {
                          selectedType = availableTypes.first;
                        }
                        _autoSequenceAssessment(selectedCourseId, selectedType);
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Assessment Type Dropdown
            Text(
              'ASSESSMENT TYPE',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final availableTypes = _getAvailableAssessmentTypes(selectedCourseId);
                final currentSelectedType = availableTypes.contains(selectedType) ? selectedType : availableTypes.first;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentSelectedType,
                      isExpanded: true,
                      dropdownColor: surfaceColor,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                      items: availableTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            selectedType = val;
                            _autoSequenceAssessment(selectedCourseId, selectedType);
                          });
                        }
                      },
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 14),

            // Assessment Name
            Text(
              'ASSESSMENT NAME',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'e.g. CT 2, Midterm Exam, Lab Final',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accentColor)),
              ),
            ),
            const SizedBox(height: 14),

            // Topics / Syllabus Covered
            Text(
              'TOPICS / SYLLABUS COVERED (OPTIONAL)',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: topicsCtrl,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'e.g., K-Maps, Quine-McCluskey, Multiplexers or Ch 1-3',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accentColor)),
              ),
            ),
            const SizedBox(height: 14),

            // Date and Time Picker
            Text(
              'DATE & TIME',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final pickedDate = await showDatePicker(
                  context: context,
                  initialDate: selectedDateTime,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (pickedDate != null && context.mounted) {
                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                  );
                  if (pickedTime != null) {
                    setState(() {
                      selectedDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  }
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_month_rounded, color: accentColor, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          '${selectedDateTime.day} ${_getMonthName(selectedDateTime.month)} ${selectedDateTime.year} at ${selectedDateTime.hour.toString().padLeft(2, '0')}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const Icon(Icons.edit_calendar_rounded, color: accentColor, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Marks & Weightage Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL MARKS',
                        style: GoogleFonts.plusJakartaSans(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: totalMarksCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: '20',
                          filled: true,
                          fillColor: surfaceColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accentColor)),
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
                      Text(
                        'WEIGHTAGE (%)',
                        style: GoogleFonts.plusJakartaSans(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: weightageCtrl,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: '10',
                          filled: true,
                          fillColor: surfaceColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: accentColor)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: const Color(0xFF140F0E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;

                  final topics = topicsCtrl.text.trim();
                  final totalMarks = double.tryParse(totalMarksCtrl.text.trim()) ?? 20.0;
                  final weightage = double.tryParse(weightageCtrl.text.trim()) ?? 10.0;
                  final uid = FirebaseAuth.instance.currentUser?.uid;

                  if (uid == null) return;

                  // Duplicate Assessment Name Conflict Check
                  String? existingAssessmentId;
                  double? existingObtainedMarks;

                  try {
                    final subSnap = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('courses')
                        .doc(selectedCourseId)
                        .collection('assessments')
                        .get();
                    for (final sDoc in subSnap.docs) {
                      final sName = (sDoc.data()['name'] as String? ?? '').trim();
                      if (sName.toLowerCase() == name.toLowerCase()) {
                        existingAssessmentId = sDoc.id;
                        existingObtainedMarks = (sDoc.data()['obtainedMarks'] as num?)?.toDouble() ?? (sDoc.data()['obtained'] as num?)?.toDouble();
                        break;
                      }
                    }

                    if (existingAssessmentId == null) {
                      final courseDoc = widget.courses.where((d) => d.id == selectedCourseId).firstOrNull;
                      final cData = courseDoc?.data() ?? {};
                      for (final a in Assessment.fromCourseData(cData, courseId: selectedCourseId)) {
                        if (a.name.trim().toLowerCase() == name.toLowerCase()) {
                          existingAssessmentId = a.id;
                          existingObtainedMarks = a.obtainedMarks;
                          break;
                        }
                      }
                    }
                  } catch (e) {
                    debugPrint('Error checking assessment conflict: $e');
                  }

                  if (existingAssessmentId != null && context.mounted) {
                    final shouldOverwrite = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF241C1A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFF4A3830)),
                        ),
                        title: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF2B78A), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Assessment Name Conflict',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        content: Text(
                          'An assessment named "$name" already exists for $selectedCourseCode. Would you like to overwrite it with the new date and details, or keep the existing one?',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFABA093),
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(
                              'Keep Existing',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFABA093),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF2B78A),
                              foregroundColor: const Color(0xFF140F0E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(
                              'Overwrite / Replace',
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (shouldOverwrite != true) {
                      return;
                    }
                  }

                  final typeCode = _typeToTypeCode(selectedType);

                  final newAssessment = Assessment(
                    id: existingAssessmentId,
                    courseId: selectedCourseId,
                    userId: uid,
                    name: name,
                    type: typeCode,
                    date: selectedDateTime,
                    totalMarks: totalMarks,
                    obtainedMarks: existingObtainedMarks, // Preserve existing marks if overwriting
                    weightage: weightage,
                    status: 'Pending',
                    syllabusSummary: topics.isNotEmpty ? topics : null,
                  );

                  // 1. Dynamic Backfill Logic for CTs:
                  final List<Assessment> backfilledAssessments = [];
                  if (typeCode == 'ct') {
                    final ctMatch = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(name);
                    if (ctMatch != null) {
                      final targetCtNum = int.tryParse(ctMatch.group(1) ?? '') ?? 1;
                      final doc = widget.courses.where((d) => d.id == selectedCourseId).firstOrNull;
                      final existingNumbers = _extractExistingCtNumbers(doc?.data());

                      try {
                        final subSnap = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('courses')
                            .doc(selectedCourseId)
                            .collection('assessments')
                            .get();
                        for (final sDoc in subSnap.docs) {
                          final sName = sDoc.data()['name'] as String? ?? '';
                          final sMatch = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(sName);
                          if (sMatch != null) {
                            final sn = int.tryParse(sMatch.group(1) ?? '');
                            if (sn != null) existingNumbers.add(sn);
                          }
                        }
                      } catch (_) {}

                      for (int i = 1; i < targetCtNum; i++) {
                        if (!existingNumbers.contains(i)) {
                          final backfill = Assessment(
                            courseId: selectedCourseId,
                            name: 'CT $i',
                            type: 'ct',
                            date: null, // Unscheduled
                            totalMarks: 20.0,
                            obtainedMarks: null, // Unrecorded
                            weightage: weightage,
                            status: 'Pending',
                          );
                          backfilledAssessments.add(backfill);
                        }
                      }
                    }
                  }

                  // 2. Persist backfilled CTs
                  for (final bf in backfilledAssessments) {
                    await AssessmentService().createAssessment(
                      uid: uid,
                      assessment: bf,
                      courseCode: selectedCourseCode,
                    );
                  }

                  // 3. Persist new assessment
                  await AssessmentService().createAssessment(
                    uid: uid,
                    assessment: newAssessment,
                    courseCode: selectedCourseCode,
                  );

                  // 4. Synchronize into course document's assessments.classTests array
                  try {
                    final courseRef = FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('courses')
                        .doc(selectedCourseId);
                    final courseSnap = await courseRef.get();
                    if (courseSnap.exists) {
                      final cData = courseSnap.data() ?? {};
                      Map<String, dynamic> assMap = Map<String, dynamic>.from(
                          cData['assessments'] is Map ? cData['assessments'] : {});
                      List<dynamic> classTests = List<dynamic>.from(
                          assMap['classTests'] is List ? assMap['classTests'] : []);

                      for (final bf in backfilledAssessments) {
                        if (!classTests.any((item) => item is Map && item['name'] == bf.name)) {
                          classTests.add(bf.toMap());
                        }
                      }

                      if (typeCode == 'ct') {
                        final idx = classTests.indexWhere((item) => item is Map && item['name'] == newAssessment.name);
                        if (idx >= 0) {
                          classTests[idx] = newAssessment.toMap();
                        } else {
                          classTests.add(newAssessment.toMap());
                        }
                        assMap['classTests'] = classTests;
                      }

                      await courseRef.set({'assessments': assMap}, SetOptions(merge: true));
                    }
                  } catch (e) {
                    debugPrint('Error syncing classTests into course doc: $e');
                  }

                  widget.onSaved?.call(newAssessment, selectedCourseCode);

                  if (context.mounted) {
                    Navigator.pop(context);
                    final backfillMsg = backfilledAssessments.isNotEmpty
                        ? ' (Backfilled ${backfilledAssessments.length} preceding CTs)'
                        : '';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text('Scheduled "$name"$backfillMsg & synced with Course Dashboard!'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  'Save & Schedule Assessment',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}