import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/analytics_models.dart';
import '../providers/analytics_provider.dart';
import '../providers/timer_subjects_provider.dart';
import '../providers/user_profile_provider.dart' hide UserProfile;
import '../services/exam_service.dart';
import '../services/pdf_report_service.dart';
import '../models/journal_entry_model.dart';
import '../providers/journal_provider.dart';
import '../providers/nav_provider.dart';
import '../theme/app_theme.dart';
import 'admission_archive_screen.dart';
import 'journal_screen.dart';
import 'term_performance_screen.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/tour_service.dart';
import '../widgets/tour_coach_mark.dart';
import '../providers/firestore_providers.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Performance & Study Insights Screen with uncapped historical data,
/// interactive calendar explorer, dynamic daily breakdowns, and chronological activity timeline.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

/// Typedef alias for Academic Insights Screen
typedef AcademicInsightsScreen = InsightsScreen;

/// Data class representing a logged session in the chronological timeline
class _TimelineSessionItem {
  final String id;
  final String? sessionId;
  final String? journalId;
  final String courseName;
  final String? topics;
  final String? content;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;

  _TimelineSessionItem({
    required this.id,
    this.sessionId,
    this.journalId,
    required this.courseName,
    this.topics,
    this.content,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
  });
}

/// Data class representing an unlogged gap in the chronological timeline
class _TimelineGapItem {
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;

  _TimelineGapItem({
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
  });
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  // Onboarding Tour Keys
  final GlobalKey _keyTimelineDayView = GlobalKey();
  final GlobalKey _keyTimelineGapBar = GlobalKey();
  bool _hasTriggeredTimelineTour = false;

  void _triggerTimelineTourIfNeeded(BuildContext showcaseContext) {
    final currentTab = ref.read(navigationIndexProvider);
    if (currentTab != 4 || _hasTriggeredTimelineTour) return;
    triggerTourSafely(
      context: showcaseContext,
      section: TourSection.timeline,
      keys: [_keyTimelineDayView, _keyTimelineGapBar],
      onStarted: () => _hasTriggeredTimelineTour = true,
      onSkippedOrEmpty: () => _hasTriggeredTimelineTour = false,
    );
  }

  DateTime _focusedDay = DateTime.now();
  DateTime? _calendarFilterDay;
  DateTime _selectedDay = DateTime.now();
  String _activeView = 'Summary'; // 'Summary', 'Calendar', 'Timeline'

  // Desktop State
  String _desktopCategoryTab = 'Overview';
  String _desktopPeriodTab = 'Week';

  // TASK 4: University Study Analytics & Heatmap state
  String _uniStudyPeriodTab = 'Month';
  DateTime get _uniSelectedInsightDate => _selectedDay;
  set _uniSelectedInsightDate(DateTime val) => _selectedDay = val;
  DateTime _uniHeatmapMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  void _loadDayInsights(DateTime day) {
    setState(() {
      _selectedDay = DateTime(day.year, day.month, day.day);
      _focusedDay = DateTime(day.year, day.month, day.day);
    });
  }

  Future<void> _pickInsightDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFF2B78A),
              onPrimary: Color(0xFF191514),
              surface: Color(0xFF241C1A),
              onSurface: Color(0xFFF5EBE6),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFF2B78A)),
            ), dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1816)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      _loadDayInsights(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopWide = MediaQuery.of(context).size.width >= 800;
    if (isDesktopWide) {
      return _buildDesktopInsightsScreen(context);
    }

    ref.watch(navigationIndexProvider);
    final userProfile = ref.watch(userProfileProvider);
    final streak = ref.watch(currentStreakProvider);
    final totalHours = ref.watch(totalStudyHoursProvider);
    final focusSessionsAsync = ref.watch(focusSessionsStreamProvider);
    final focusSessions = focusSessionsAsync.asData?.value ?? [];
    final journalAsync = ref.watch(journalStreamProvider);
    final journalEntries = journalAsync.asData?.value ?? [];

    // TASK 1: Strict Mode Separation - University academic insights view
    if (userProfile.isUniversityStudent) {
      return _buildUniversityInsightsScreen(context, userProfile, streak, totalHours, focusSessions, journalEntries);
    }

    final avgFocus = ref.watch(averageFocusProvider);
    final weeklyTrend = ref.watch(weeklyTrendProvider);
    final subjectDist = ref.watch(subjectDistributionProvider);

    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);

    final hasWeeklyData = weeklyTrend.any((d) => d.totalMinutes > 0);
    final hasSubjectData = subjectDist.isNotEmpty && subjectDist.any((s) => s.totalMinutes > 0);
    final courseColorMap = _buildCourseColorMap(
      courseDocs: const [],
      sessions: focusSessions,
      journals: journalEntries,
    );

    // Filter sessions if a specific calendar day is selected (00:00 to 23:59)
    final displayedSessions = _calendarFilterDay == null
        ? focusSessions
        : focusSessions.where((s) => isSameDay(s.date, _calendarFilterDay)).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance Insights',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Uncapped history & live study analytics',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          SafeHaptics.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const JournalScreen()),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_stories_rounded, color: accentColor, size: 17),
                              SizedBox(width: 6),
                              Text(
                                'Study Journal',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _exportPdfReport(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Export PDF',
                                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                        ),
                        child: const Icon(Icons.insights_rounded, color: accentColor, size: 22),
                      ),
                    ],
                  ),
                ],
              ),
              // Task 3: In-App Wellness Card (Burnout Guard: 12+ hours today)
              if (ref.watch(isBurnoutThresholdReachedProvider)) ...[
                _buildBurnoutWellnessCard(),
                const SizedBox(height: 20),
              ],

              // Top All-Time Stats Cards Grid
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Current Streak',
                      value: '$streak Days',
                      subtitle: streak > 0 ? '🔥 Momentum active' : 'Start today',
                      icon: Icons.local_fire_department_rounded,
                      iconColor: const Color(0xFFF97316),
                      cardColor: cardColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Total Study Time',
                      value: '${totalHours.toStringAsFixed(1)}h',
                      subtitle: '${focusSessions.length} Total Sessions',
                      icon: Icons.access_time_rounded,
                      iconColor: accentColor,
                      cardColor: cardColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Avg Focus / Session',
                      value: '$avgFocus Mins',
                      subtitle: 'Last 7 days average',
                      icon: Icons.timer_outlined,
                      iconColor: const Color(0xFF34D399),
                      cardColor: cardColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'Sessions Logged',
                      value: '${focusSessions.length}',
                      subtitle: 'Since day 1',
                      icon: Icons.history_edu_rounded,
                      iconColor: const Color(0xFFA78BFA),
                      cardColor: cardColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // View Mode Selector (Summary, Calendar, Timeline)
              _buildViewModeSelector(cardColor, accentColor),
              const SizedBox(height: 20),

              // Dynamic Body depending on active view mode
              if (_activeView == 'Summary') ...[
                // 1. Weekly Trend Bar Chart Section
                _buildWeeklyTrendSection(weeklyTrend, hasWeeklyData, cardColor, accentColor),
                const SizedBox(height: 24),

                // 2. Task 3: Subject Focus Breakdown (Last 7 Days)
                _buildSubjectDistributionSection(subjectDist, hasSubjectData, cardColor, courseColorMap),
                const SizedBox(height: 24),

                // 3. Exam Deltas Card
                _buildExamPerformanceDeltas(ref, cardColor, accentColor),
                const SizedBox(height: 24),

                // 4. Recent Activity Timeline Preview
                _buildActivityTimelineSection(
                  context,
                  focusSessions.take(15).toList(),
                  cardColor,
                  accentColor,
                  title: 'Recent Activity History',
                  subtitle: '${focusSessions.length} total sessions recorded',
                ),
              ] else if (_activeView == 'Calendar') ...[
                // Historical Calendar View
                _buildCalendarSection(focusSessions, cardColor, accentColor),
                const SizedBox(height: 24),

                // Task 3: Daily Calendar Breakdown Chart directly underneath calendar when a day is tapped
                if (_calendarFilterDay != null) ...[
                  _buildDailyCalendarBreakdownSection(_calendarFilterDay!, displayedSessions, cardColor, accentColor),
                  const SizedBox(height: 24),
                ],

                // Filtered Sessions for Selected Day
                _buildActivityTimelineSection(
                  context,
                  displayedSessions,
                  cardColor,
                  accentColor,
                  title: _calendarFilterDay == null
                      ? 'All Historical Sessions (${focusSessions.length})'
                      : 'Sessions on ${_formatDayHeader(_calendarFilterDay!)} (${displayedSessions.length})',
                  subtitle: _calendarFilterDay == null
                      ? 'Tap any calendar date with a green dot to filter'
                      : 'Showing focus logs recorded on this day',
                  showClearFilter: _calendarFilterDay != null,
                ),
              ] else ...[
                // Task 1: Complete Chronological Historical Timeline with clean header separation
                _buildActivityTimelineSection(
                  context,
                  focusSessions,
                  cardColor,
                  accentColor,
                  title: 'Complete Historical Timeline',
                  subtitle: '${focusSessions.length} focus sessions from Day 1 to now',
                ),
              ],

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  /// View Mode Selector Tabs
  Widget _buildViewModeSelector(Color cardColor, Color accentColor) {
    const tabs = ['Summary', 'Calendar', 'Timeline'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _activeView == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                SafeHaptics.lightImpact();
                setState(() {
                  _activeView = tab;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: accentColor.withValues(alpha: 0.5))
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab == 'Summary'
                            ? Icons.bar_chart_rounded
                            : (tab == 'Calendar'
                                ? Icons.calendar_month_rounded
                                : Icons.history_rounded),
                        size: 16,
                        color: isSelected ? accentColor : Colors.blueGrey.shade400,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tab,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.blueGrey.shade400,
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Historical Calendar View using TableCalendar
  Widget _buildCalendarSection(
    List<StudySessionLog> allSessions,
    Color cardColor,
    Color accentColor,
  ) {
    return Container(
      width: double.infinity,
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
              const Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Study Calendar',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (_calendarFilterDay != null)
                GestureDetector(
                  onTap: () {
                    SafeHaptics.lightImpact();
                    setState(() {
                      _calendarFilterDay = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Clear Date',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TableCalendar<StudySessionLog>(
            firstDay: DateTime.utc(2023, 1, 1),
            lastDay: DateTime.now().add(const Duration(days: 365)),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.month,
            startingDayOfWeek: StartingDayOfWeek.sunday,
            selectedDayPredicate: (day) => isSameDay(_calendarFilterDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              SafeHaptics.lightImpact();
              setState(() {
                if (isSameDay(_calendarFilterDay, selectedDay)) {
                  _calendarFilterDay = null;
                } else {
                  _calendarFilterDay = selectedDay;
                }
                _focusedDay = focusedDay;
              });
            },
            eventLoader: (day) {
              return allSessions.where((s) => isSameDay(s.date, day)).toList();
            },
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              defaultTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
              weekendTextStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              selectedDecoration: const BoxDecoration(
                color: Color(0xFFF2B78A),
                shape: BoxShape.circle,
              ),
              selectedTextStyle: const TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
              todayDecoration: BoxDecoration(
                color: const Color(0xFFF2B78A).withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF2B78A)),
              ),
              todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              markerDecoration: const BoxDecoration(
                color: Color(0xFF34D399),
                shape: BoxShape.circle,
              ),
              markersMaxCount: 3,
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              leftChevronIcon: Icon(Icons.chevron_left_rounded, color: Color(0xFFF2B78A)),
              rightChevronIcon: Icon(Icons.chevron_right_rounded, color: Color(0xFFF2B78A)),
            ),
          ),
        ],
      ),
    );
  }

  /// Task 3: Aggregates and calculates subject breakdown strictly for a given day
  List<SubjectDistributionData> _calculateDailySubjectDistribution(List<StudySessionLog> dailySessions) {
    if (dailySessions.isEmpty) return [];

    final Map<String, int> subjectTotals = {};
    int grandTotal = 0;

    for (final log in dailySessions) {
      subjectTotals[log.subjectName] = (subjectTotals[log.subjectName] ?? 0) + log.durationInMinutes;
      grandTotal += log.durationInMinutes;
    }

    if (grandTotal == 0) return [];

    return subjectTotals.entries.map((entry) {
      final pct = (entry.value / grandTotal) * 100;
      return SubjectDistributionData(
        subjectName: entry.key,
        totalMinutes: entry.value,
        percentage: pct,
      );
    }).toList();
  }

  /// Task 3: Mini pie-chart and breakdown list rendered directly underneath the calendar for the selected day
  Widget _buildDailyCalendarBreakdownSection(
    DateTime day,
    List<StudySessionLog> dailySessions,
    Color cardColor,
    Color accentColor,
  ) {
    final dailyDist = _calculateDailySubjectDistribution(dailySessions);
    final totalDayMins = dailySessions.fold<int>(0, (sum, s) => sum + s.durationInMinutes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
                  const Icon(Icons.pie_chart_rounded, color: Color(0xFFF2B78A), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Daily Focus: ${_formatDayHeader(day)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                '${totalDayMins}m total',
                style: const TextStyle(
                  color: Color(0xFFF2B78A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (dailyDist.isEmpty)
            _buildEmptyState('No focus sessions recorded on ${_formatDayHeader(day)}.')
          else
            Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 28,
                      sections: _buildPieSections(dailyDist),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: dailyDist.asMap().entries.map((entry) {
                      final index = entry.key;
                      final data = entry.value;
                      final color = _paletteColors[index % _paletteColors.length];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                data.subjectName,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${data.totalMinutes}m (${data.percentage.toStringAsFixed(0)}%)',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Weekly Trend Bar Chart Section
  Widget _buildWeeklyTrendSection(
    List<DailyStudyBarData> weeklyTrend,
    bool hasWeeklyData,
    Color cardColor,
    Color accentColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Study Trend',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Last 7 Days',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!hasWeeklyData)
            _buildEmptyState('No study data logged for this week yet.')
          else
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxY(weeklyTrend),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (double value, TitleMeta meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < weeklyTrend.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                weeklyTrend[index].dayName,
                                style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    ),
                  ),
                  barGroups: weeklyTrend.asMap().entries.map((entry) {
                    final index = entry.key;
                    final data = entry.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: data.totalMinutes.toDouble(),
                          color: accentColor,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: _getMaxY(weeklyTrend),
                            color: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1C1412),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${weeklyTrend[groupIndex].dayName}\n${rod.toY.toInt()} min',
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Task 3: Subject Focus Breakdown Doughnut Chart (Last 7 Days)
  Widget _buildSubjectDistributionSection(
    List<SubjectDistributionData> subjectDist,
    bool hasSubjectData,
    Color cardColor, [
    Map<String, Color>? colorMap,
  ]) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subject Focus Breakdown',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Last 7 Days',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (!hasSubjectData)
            _buildEmptyState('No subject focus records available for the last 7 days.')
          else
            Row(
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 36,
                      sections: _buildPieSections(subjectDist, colorMap),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: subjectDist.asMap().entries.map((entry) {
                      final index = entry.key;
                      final data = entry.value;
                      final color = colorMap != null
                          ? _resolveCourseColor(data.subjectName, colorMap)
                          : _distinctCuratedPalette[index % _distinctCuratedPalette.length];

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                data.subjectName,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${data.percentage.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Task 1 & 2: Activity Timeline Section with Clean Header Spacing and Smooth NeverScrollableScrollPhysics
  Widget _buildActivityTimelineSection(
    BuildContext context,
    List<StudySessionLog> sessions,
    Color cardColor,
    Color accentColor, {
    String title = 'Study Activity Timeline',
    String subtitle = '',
    bool showClearFilter = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task 1: Separated Column for Title and Subtitle with SizedBox(height: 4)
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
                        const Icon(Icons.history_rounded, color: Color(0xFFF2B78A), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      ),
                    ],
                  ],
                ),
              ),
              if (showClearFilter) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    SafeHaptics.lightImpact();
                    setState(() {
                      _calendarFilterDay = null;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Show All',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          if (sessions.isEmpty)
            _buildEmptyState('No focus sessions logged for this period.')
          else
            // Task 2: shrinkWrap and NeverScrollableScrollPhysics to eliminate nested scrolling jitter
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                final startFormatted = _formatTimeOfDay(session.startTime);
                final endFormatted = _formatTimeOfDay(session.endTime ?? session.date);
                final dayLabel = _formatDayHeader(session.date);

                final showDayHeader = index == 0 ||
                    _formatDayHeader(sessions[index - 1].date) != dayLabel;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showDayHeader) ...[
                      Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 14, bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF110D0C),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: Text(
                                dayLabel,
                                style: const TextStyle(
                                  color: Color(0xFFF2B78A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.06), thickness: 1)),
                          ],
                        ),
                      ),
                    ],
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34D399).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF34D399), size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  session.subjectName,
                                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '$startFormatted – $endFormatted',
                                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('⏱️', style: TextStyle(fontSize: 11)),
                                const SizedBox(width: 4),
                                Text(
                                  'Study Session • ${session.durationInMinutes} mins',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.pinkAccent, size: 18),
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Delete Focus Session',
                            onPressed: () => _confirmDeleteSession(context, session),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  void _confirmDeleteSession(BuildContext context, StudySessionLog session) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Focus Session', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete the ${session.durationInMinutes}-minute focus session for "${session.subjectName}"?',
          style: const TextStyle(color: Colors.blueGrey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await deleteFocusSession(session.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFFEF4444),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    content: Text('Deleted session for "${session.subjectName}".'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _formatTimeOfDay(DateTime? dt) {
    if (dt == null) return '--:--';
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:$minute $period';
  }

  String _formatDayHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final target = DateTime(dt.year, dt.month, dt.day);

    if (target == today) return 'Today';
    if (target == yesterday) return 'Yesterday';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  /// High-contrast, visually distinct, dark-mode friendly accent colors curated for study timeline & charts
  static const List<Color> _distinctCuratedPalette = [
    Color(0xFFF43F5E), // Vivid Pink / Rose
    Color(0xFF06B6D4), // Electric Cyan
    Color(0xFFFBBF24), // Bright Amber / Yellow
    Color(0xFFA855F7), // Purple / Violet
    Color(0xFF10B981), // Emerald Green
    Color(0xFFFB923C), // Coral / Orange
    Color(0xFF6366F1), // Indigo
    Color(0xFF84CC16), // Lime
    Color(0xFFD946EF), // Fuchsia
    Color(0xFF38BDF8), // Sky Blue
  ];

  static const List<Color> _paletteColors = _distinctCuratedPalette;

  /// Builds a dynamic, deterministic map associating each active course or subject with a distinct accent color.
  /// If a course document defines a stored 'colorValue' or 'color', it is preserved.
  /// Otherwise, sorted unique courses are assigned non-adjacent contrasting hues from the curated pool.
  Map<String, Color> _buildCourseColorMap({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> courseDocs,
    required List<FocusSession> sessions,
    required List<StudyJournalEntry> journals,
  }) {
    final Map<String, Color> map = {};
    final Map<String, Color> explicitCourseColors = {};
    final Set<String> uniqueKeys = {};

    // 1. Process course documents and check for stored colors
    for (final doc in courseDocs) {
      final data = doc.data();
      final code = (data['courseCode'] as String? ?? '').trim();
      final name = (data['courseName'] as String? ?? '').trim();
      Color? docColor;

      if (data['colorValue'] is int) {
        docColor = Color(data['colorValue'] as int);
      } else if (data['color'] is int) {
        docColor = Color(data['color'] as int);
      } else if (data['color'] is String) {
        final colStr = data['color'] as String;
        if (colStr.startsWith('#')) {
          final hex = int.tryParse(colStr.replaceFirst('#', '0xFF'));
          if (hex != null) docColor = Color(hex);
        }
      }

      final label = code.isNotEmpty && name.isNotEmpty ? '$code • $name' : (code.isNotEmpty ? code : name);
      if (label.isNotEmpty) {
        uniqueKeys.add(label);
        if (docColor != null) {
          explicitCourseColors[label.toLowerCase()] = docColor;
          if (code.isNotEmpty) explicitCourseColors[code.toLowerCase()] = docColor;
          if (name.isNotEmpty) explicitCourseColors[name.toLowerCase()] = docColor;
        }
      }
    }

    // 2. Collect unique subjects from focus sessions
    for (final s in sessions) {
      final sub = s.subjectName.isNotEmpty ? s.subjectName.trim() : s.subject.trim();
      if (sub.isNotEmpty) uniqueKeys.add(sub);
    }

    // 3. Collect unique subjects from journals
    for (final j in journals) {
      final title = j.title.replaceFirst('Study Log: ', '').trim();
      if (title.isNotEmpty) uniqueKeys.add(title);
      final sub = j.subjectOrCourseId.trim();
      if (sub.isNotEmpty) uniqueKeys.add(sub);
    }

    // Sort uniquely to ensure deterministic, stable color assignments
    final sortedKeys = uniqueKeys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    // Assign distinct palette colors to keys that don't have an explicit color
    int paletteIdx = 0;
    for (final key in sortedKeys) {
      final lowerKey = key.toLowerCase();
      Color assignedColor;
      if (explicitCourseColors.containsKey(lowerKey)) {
        assignedColor = explicitCourseColors[lowerKey]!;
      } else {
        assignedColor = _distinctCuratedPalette[paletteIdx % _distinctCuratedPalette.length];
        paletteIdx++;
      }
      map[lowerKey] = assignedColor;
      map[key] = assignedColor;

      if (key.contains(' • ')) {
        final parts = key.split(' • ');
        for (final p in parts) {
          map[p.trim().toLowerCase()] = assignedColor;
        }
      }
    }

    // Copy explicit colors
    explicitCourseColors.forEach((k, v) {
      map[k] = v;
    });

    return map;
  }

  /// Resolves the distinctive accent color for a course from the generated map,
  /// with a robust deterministic fallback ensuring dark-mode contrast.
  Color _resolveCourseColor(String courseName, Map<String, Color> colorMap) {
    final key = courseName.trim().toLowerCase();
    if (key.isEmpty) return _distinctCuratedPalette[0];
    if (colorMap.containsKey(key)) return colorMap[key]!;

    for (final entry in colorMap.entries) {
      if (entry.key.isNotEmpty && (key.contains(entry.key) || entry.key.contains(key))) {
        return entry.value;
      }
    }

    final hash = key.codeUnits.fold<int>(0, (prev, elem) => prev + elem);
    return _distinctCuratedPalette[hash % _distinctCuratedPalette.length];
  }

  String _formatTimeWithPeriodPrefix(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$period $hour:$min';
  }

  String _formatDurationShort(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  double _getMaxY(List<DailyStudyBarData> trend) {
    double maxVal = 60.0;
    for (var item in trend) {
      if (item.totalMinutes > maxVal) {
        maxVal = item.totalMinutes.toDouble();
      }
    }
    return (maxVal * 1.2).ceilToDouble();
  }

  List<PieChartSectionData> _buildPieSections(List<SubjectDistributionData> list, [Map<String, Color>? colorMap]) {
    return list.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final color = colorMap != null
          ? _resolveCourseColor(data.subjectName, colorMap)
          : _distinctCuratedPalette[index % _distinctCuratedPalette.length];

      return PieChartSectionData(
        color: color,
        value: data.totalMinutes.toDouble(),
        title: '',
        radius: 28,
      );
    }).toList();
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: iconColor.withValues(alpha: 0.9), fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildExamPerformanceDeltas(WidgetRef ref, Color cardColor, Color accentColor) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.asData?.value ?? [];

    final completedExams = allExams
        .where((e) => (e.isCompleted && !e.isAbsent) || e.marksObtained > 0)
        .toList();

    completedExams.sort((a, b) => a.date.compareTo(b.date));

    final latestExam = completedExams.isNotEmpty ? completedExams.last : null;
    final previousExam = completedExams.length > 1 ? completedExams[completedExams.length - 2] : latestExam;

    final latestScore = latestExam?.scorePercentage ?? 0.0;
    final previousScore = previousExam?.scorePercentage ?? latestScore;
    final marksDelta = latestScore - previousScore;

    final latestRank = latestExam?.meritPosition ?? 0;
    final previousRank = previousExam?.meritPosition ?? latestRank;
    final rankDelta = previousRank - latestRank;

    const emeraldColor = Color(0xFF10B981);
    const roseColor = Color(0xFFEF4444);

    final marksDeltaColor = marksDelta >= 0 ? emeraldColor : roseColor;
    final rankDeltaColor = rankDelta >= 0 ? emeraldColor : roseColor;

    final formattedMarksDelta = marksDelta >= 0
        ? '+${marksDelta.toStringAsFixed(1)}%'
        : '-${marksDelta.abs().toStringAsFixed(1)}%';

    final formattedRankDelta = rankDelta > 0
        ? '▲ +$rankDelta'
        : (rankDelta < 0 ? '▼ ${rankDelta.abs()}' : '— 0');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
              const Row(
                children: [
                  Icon(Icons.trending_up_rounded, color: Color(0xFFF2B78A), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Performance Trends',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                '${completedExams.length} Exams Logged',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (completedExams.isEmpty)
            _buildEmptyState('Log exam scores in the Exams tab to view performance trends.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF170F0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest Score',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${latestScore.toStringAsFixed(1)}%',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1)
                          Text(
                            formattedMarksDelta,
                            style: TextStyle(color: marksDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Baseline Exam', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF170F0D),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Merit Rank',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          latestRank > 0 ? '#$latestRank' : 'N/A',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1 && latestRank > 0 && previousRank > 0)
                          Text(
                            formattedRankDelta,
                            style: TextStyle(color: rankDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Current Rank', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 8.0),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.query_stats_rounded, size: 36, color: Colors.blueGrey.shade700),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey.shade400,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Task 3: Subtle, warm-toned in-app wellness banner for Burnout Guard (12+ hours today)
  Widget _buildBurnoutWellnessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEA580C).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.favorite_rounded, color: Color(0xFFFB923C), size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              "You're working amazingly hard today! Don't forget to stay hydrated and rest.",
              style: TextStyle(
                color: Color(0xFFFED7AA),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Task 3: Export Academic Progress Report PDF
  Future<void> _exportPdfReport(BuildContext context, WidgetRef ref) async {
    await PdfReportService.handleExportPdfAction(context, ref);
  }

  /// Unified Apple-inspired glassmorphic CGPA & Term Simulator banner card
  Widget _buildCgpaSimulatorCard({
    required BuildContext context,
    required String uniName,
    required String major,
    required String level,
    required String term,
    required Color cardColor,
    required Color accentColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF241A17), Color(0xFF191210)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Academic Identity Pill & Active Term Badge
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFFF2B78A), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uniName.isNotEmpty ? uniName : 'BUET',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${major.isNotEmpty ? major : "EEE"} • Level ${level.isNotEmpty ? level : "1"}, Term ${term.isNotEmpty ? term : "1"}',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFABA093),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Compact Term Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E221E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF4A3830), width: 0.6),
                  ),
                  child: Text(
                    'Active Term',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFF382A24), height: 1),
            const SizedBox(height: 12),

            // Row 2: Direct Interactive CGPA Simulator Trigger Bar
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                SafeHaptics.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TermPerformanceScreen(
                      universityName: uniName,
                      term: term,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF140E0D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3A2B25), width: 0.8),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF06D6A0).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.insights_rounded, color: Color(0xFF06D6A0), size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CGPA Forecaster & Target Planner',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Project grades, calculate cutoffs, and track credits',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF8C7E77),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: Color(0xFFF2B78A), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUniversityInsightsScreen(
    BuildContext context,
    dynamic profile,
    int streak,
    double totalHours,
    List<FocusSession> sessions,
    List<StudyJournalEntry> journalEntries,
  ) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final uniName = profile.universityName?.isNotEmpty == true ? profile.universityName! : 'University';
    final major = profile.major?.isNotEmpty == true ? profile.major! : 'Engineering / Science';
    final level = profile.level?.isNotEmpty == true ? profile.level! : '1';
    final term = profile.term?.isNotEmpty == true ? profile.term! : '1';

    return ShowCaseWidget(
      enableAutoScroll: true,
      blurValue: 2.0,
      onFinish: () => TourService().markTourSeen(TourSection.timeline),
      builder: (showcaseContext) {
        _triggerTimelineTourIfNeeded(showcaseContext);
        return Scaffold(
          backgroundColor: backgroundColor,
      body: SafeArea(
        child: uid == null
            ? const Center(child: Text('Please sign in to view academic insights', style: TextStyle(color: Colors.white)))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('courses')
                    .snapshots(),
                builder: (context, courseSnapshot) {
                  final courseDocs = courseSnapshot.data?.docs ?? [];
                  final activeCourseCodes = courseDocs
                      .map((d) => (d.data()['courseCode'] as String? ?? '').toLowerCase().trim())
                      .where((c) => c.isNotEmpty)
                      .toSet();
                  final activeCourseNames = courseDocs
                      .map((d) => (d.data()['courseName'] as String? ?? '').toLowerCase().trim())
                      .where((n) => n.isNotEmpty)
                      .toSet();

                  // TASK 2: Strictly filter out legacy admission sessions & keep only active university course sessions
                  final universitySessions = sessions.where((s) {
                    final subj = s.subject.trim().toLowerCase();

                    // Strictly hide legacy Admission/HSC subjects
                    final isLegacy = kDefaultTimerSubjects.any((legacy) {
                      final l = legacy.toLowerCase();
                      return subj == l || subj.startsWith(l) || (subj.contains('paper') && !subj.contains('term paper')) || subj.contains('hsc') || subj.contains('model test');
                    });
                    if (isLegacy) return false;

                    // Strictly keep only sessions linked to active university courses or standard university timer subjects
                    final matchesActiveCourse = activeCourseCodes.any((code) => subj.contains(code)) ||
                        activeCourseNames.any((name) => subj.contains(name));
                    final matchesUniCategory = kDefaultUniversityTimerSubjects.any((cat) => subj == cat.toLowerCase());

                    return matchesActiveCourse || matchesUniCategory;
                  }).toList();

                  final universityHours = universitySessions.fold<int>(0, (sum, s) => sum + s.durationInMinutes) / 60.0;

                  final availableCourses = courseDocs.map((d) {
                    final data = d.data();
                    final code = (data['courseCode'] as String? ?? '').trim();
                    final name = (data['courseName'] as String? ?? '').trim();
                    if (code.isNotEmpty && name.isNotEmpty) return '$code • $name';
                    if (code.isNotEmpty) return code;
                    return name;
                  }).where((s) => s.isNotEmpty).toList();

                  final courseColorMap = _buildCourseColorMap(
                    courseDocs: courseDocs,
                    sessions: universitySessions,
                    journals: journalEntries,
                  );

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Screen Header with clean history icon
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Academic Insights',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Term analytics & study metrics',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFABA093),
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                // Small clean history icon button
                                IconButton(
                                  icon: const Icon(Icons.history_rounded, color: accentColor, size: 24),
                                  tooltip: 'Access Previous Admission Data',
                                  onPressed: () {
                                    SafeHaptics.lightImpact();
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const AdmissionArchiveScreen()),
                                    );
                                  },
                                ),
                                const SizedBox(width: 4),
                                GestureDetector(
                                    onTap: () => _exportPdfReport(context, ref),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary, size: 18),
                                          SizedBox(width: 6),
                                          Text(
                                            'Export PDF',
                                            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Academic Profile Status Card & Unified CGPA Simulator Banner
                        _buildCgpaSimulatorCard(
                          context: context,
                          uniName: uniName,
                          major: major,
                          level: level,
                          term: term,
                          cardColor: cardColor,
                          accentColor: accentColor,
                        ),
                        const SizedBox(height: 16),

                        // Study Stats Row
                        Row(
                          children: [
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Current Streak',
                                value: '$streak Days',
                                subtitle: streak > 0 ? '🔥 Momentum active' : 'Start today',
                                icon: Icons.local_fire_department_rounded,
                                iconColor: const Color(0xFFF97316),
                                cardColor: cardColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildSummaryCard(
                                title: 'Total Study Time',
                                value: '${universityHours.toStringAsFixed(1)}h',
                                subtitle: '${universitySessions.length} University Sessions',
                                icon: Icons.access_time_rounded,
                                iconColor: accentColor,
                                cardColor: cardColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // TASK 4 & 5: Segmented Pill Bar navigation [Period | Day | Week | Month | Trend]
                        AppSegmentedPillBar<String>(
                          segments: const ['Period', 'Day', 'Week', 'Month', 'Trend'],
                          selectedSegment: _uniStudyPeriodTab,
                          onSegmentSelected: (tab) {
                            setState(() {
                              _uniStudyPeriodTab = tab;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        // TASK 5: Dynamic View Switching based on _uniStudyPeriodTab [Period | Day | Week | Month | Trend]
                        if (_uniStudyPeriodTab == 'Day') ...[
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            universitySessions.where((s) => isSameDay(s.date, _uniSelectedInsightDate)).toList(),
                            courseColorMap,
                            periodTitle: 'Course Distribution (${_uniSelectedInsightDate.day}/${_uniSelectedInsightDate.month})',
                          ),
                          const SizedBox(height: 16),
                          _buildSelectedDateDetailCard(
                            cardColor,
                            accentColor,
                            universitySessions,
                            journalEntries,
                            availableCourses: availableCourses,
                            courseColorMap: courseColorMap,
                          ),
                          const SizedBox(height: 16),
                          _buildDayFocusSessionsCard(
                            cardColor,
                            accentColor,
                            universitySessions,
                            courseColorMap: courseColorMap,
                          ),
                        ] else if (_uniStudyPeriodTab == 'Week') ...[
                          _buildWeeklyDistributionCard(cardColor, accentColor, universitySessions),
                          const SizedBox(height: 16),
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            universitySessions,
                            courseColorMap,
                            periodTitle: 'Course Focus Breakdown',
                          ),
                          const SizedBox(height: 16),
                          _buildSelectedDateDetailCard(
                            cardColor,
                            accentColor,
                            universitySessions,
                            journalEntries,
                            availableCourses: availableCourses,
                            courseColorMap: courseColorMap,
                          ),
                        ] else if (_uniStudyPeriodTab == 'Trend') ...[
                          _buildSemesterTrendProgressionCard(cardColor, accentColor, universitySessions),
                          const SizedBox(height: 16),
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            universitySessions,
                            courseColorMap,
                            periodTitle: 'Semester Course Distribution',
                          ),
                          const SizedBox(height: 16),
                          _buildSelectedDateDetailCard(
                            cardColor,
                            accentColor,
                            universitySessions,
                            journalEntries,
                            availableCourses: availableCourses,
                            courseColorMap: courseColorMap,
                          ),
                        ] else ...[
                          // 'Month' and 'Period'
                          _buildUniversityHeatmapCard(cardColor, accentColor, universitySessions),
                          const SizedBox(height: 16),
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            universitySessions,
                            courseColorMap,
                            periodTitle: 'Overall Course Distribution',
                          ),
                          const SizedBox(height: 16),
                          _buildSelectedDateDetailCard(
                            cardColor,
                            accentColor,
                            universitySessions,
                            journalEntries,
                            availableCourses: availableCourses,
                            courseColorMap: courseColorMap,
                          ),
                          const SizedBox(height: 16),
                          _buildRecentActivityCard(cardColor, accentColor, universitySessions),
                        ],
                      ],
                    ),
                  );
                },
              ),
      ),
    );
        },
      );
  }

  Widget _buildRecentActivityCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Focus Activity',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          if (universitySessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'No university study sessions recorded yet. Use the Timer with your university courses to record focus sessions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                ),
              ),
            )
          else
            ...universitySessions.take(5).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: Color(0xFFF2B78A), size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s.subject.isNotEmpty ? s.subject : 'Course Study',
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Text(
                        '${s.durationMinutes} mins',
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildUniversityHeatmapCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions,
  ) {
    final year = _uniHeatmapMonth.year;
    final month = _uniHeatmapMonth.month;
    final monthName = _getMonthName(month);
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstDayWeekday = DateTime(year, month, 1).weekday; // 1 = Monday ... 7 = Sunday
    final leadingBlanks = firstDayWeekday - 1;

    return buildGlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header & nav with Today action
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$monthName $year',
                style: AppTypography.cardTitle.copyWith(fontSize: 16),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.today, size: 20, color: AppColors.primary),
                    tooltip: 'Today',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      final now = DateTime.now();
                      setState(() {
                        _uniHeatmapMonth = DateTime(now.year, now.month, 1);
                        _uniSelectedInsightDate = DateTime(now.year, now.month, now.day);
                      });
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _uniHeatmapMonth = DateTime(year, month - 1, 1);
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _uniHeatmapMonth = DateTime(year, month + 1, 1);
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Intensity Level Legend
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('Intensity: ', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                _buildIntensityLegendItem('0h', _getHeatmapIntensityColor(0)),
                const SizedBox(width: 6),
                _buildIntensityLegendItem('4h+', _getHeatmapIntensityColor(4)),
                const SizedBox(width: 6),
                _buildIntensityLegendItem('7h+', _getHeatmapIntensityColor(7)),
                const SizedBox(width: 6),
                _buildIntensityLegendItem('10h+', _getHeatmapIntensityColor(10)),
                const SizedBox(width: 6),
                _buildIntensityLegendItem('12h+', _getHeatmapIntensityColor(12)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Day of week labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
              return Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(color: Color(0xFFABA093), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          // Days grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingBlanks + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              if (index < leadingBlanks) {
                return const SizedBox.shrink();
              }
              final dayNumber = index - leadingBlanks + 1;
              final cellDate = DateTime(year, month, dayNumber);
              final isSelected = isSameDay(cellDate, _uniSelectedInsightDate);
              final isToday = isSameDay(cellDate, DateTime.now());

              final daySessions = universitySessions.where((s) => isSameDay(s.date, cellDate)).toList();
              final dayMinutes = daySessions.fold<int>(0, (acc, s) => acc + s.durationInMinutes);
              final dayHours = dayMinutes / 60.0;
              final cellColor = _getHeatmapIntensityColor(dayHours);

              return InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  setState(() {
                    _uniSelectedInsightDate = cellDate;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: cellColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Colors.white
                          : (isToday ? accentColor : Colors.white.withValues(alpha: 0.06)),
                      width: isSelected ? 2.0 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [BoxShadow(color: Colors.white.withValues(alpha: 0.2), blurRadius: 4, spreadRadius: 1)]
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$dayNumber',
                      style: TextStyle(
                        color: dayHours >= 7.0 ? const Color(0xFF110D0C) : Colors.white,
                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildIntensityLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: Colors.white12),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 10.5),
        ),
      ],
    );
  }

  /// Task 1 & 2: Course Focus Distribution Breakdown Section with dynamic curated colors
  Widget _buildUniversityCourseDistributionSection(
    Color cardColor,
    List<FocusSession> sessions,
    Map<String, Color> courseColorMap, {
    String periodTitle = 'Course Focus Breakdown',
  }) {
    final Map<String, int> courseMinutes = {};
    for (final s in sessions) {
      final name = s.subjectName.isNotEmpty ? s.subjectName : (s.subject.isNotEmpty ? s.subject : 'Course Study');
      courseMinutes[name] = (courseMinutes[name] ?? 0) + s.durationMinutes;
    }

    final totalMins = courseMinutes.values.fold<int>(0, (sum, m) => sum + m);
    if (totalMins == 0) return const SizedBox.shrink();

    final sortedEntries = courseMinutes.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
              Text(
                periodTitle,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                '${(totalMins / 60.0).toStringAsFixed(1)}h total',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 115,
                height: 115,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 28,
                    sections: sortedEntries.map((e) {
                      final color = _resolveCourseColor(e.key, courseColorMap);
                      return PieChartSectionData(
                        color: color,
                        value: e.value.toDouble(),
                        title: '',
                        radius: 24,
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: sortedEntries.take(5).map((e) {
                    final color = _resolveCourseColor(e.key, courseColorMap);
                    final pct = ((e.value / totalMins) * 100).round();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3.5),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              e.key,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Interactive Chronological Day Timeline with dynamic course colors, unlogged gap slots, and session actions
  Widget _buildSelectedDateDetailCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions,
    List<StudyJournalEntry> journalEntries, {
    required List<String> availableCourses,
    required Map<String, Color> courseColorMap,
  }) {
    final date = _uniSelectedInsightDate;
    final dayName = _getWeekdayName(date.weekday);
    final monthName = _getMonthName(date.month);
    final formattedDateStr = '$dayName, $monthName ${date.day}, ${date.year}';
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final daySessions = universitySessions
        .where((s) =>
            isSameDay(s.date, date) ||
            (s.startTime != null && isSameDay(s.startTime!, date)) ||
            (!s.date.isBefore(startOfDay) && !s.date.isAfter(endOfDay)))
        .toList();
    final totalSecs = daySessions.fold<int>(
      0,
      (acc, s) => acc + (s.durationInSeconds > 0 ? s.durationInSeconds : s.durationInMinutes * 60),
    );
    final maxSecs = daySessions.isEmpty
        ? 0
        : daySessions
            .map((s) => s.durationInSeconds > 0 ? s.durationInSeconds : s.durationInMinutes * 60)
            .reduce((a, b) => a > b ? a : b);

    DateTime? earliestStart;
    DateTime? latestEnd;
    for (final s in daySessions) {
      if (s.startTime != null) {
        if (earliestStart == null || s.startTime!.isBefore(earliestStart)) {
          earliestStart = s.startTime;
        }
      }
      if (s.endTime != null) {
        if (latestEnd == null || s.endTime!.isAfter(latestEnd)) {
          latestEnd = s.endTime;
        }
      }
    }

    final startFinishStr = earliestStart != null && latestEnd != null
        ? '${_formatTimeWithPeriodPrefix(earliestStart)} - ${_formatTimeWithPeriodPrefix(latestEnd)}'
        : (daySessions.isNotEmpty ? _formatTimeWithPeriodPrefix(daySessions.first.date) : '--');

    // Journal topics for this selected date
    final dayJournals = journalEntries.where((j) => isSameDay(j.timestamp, date)).toList();

    // 1. Unify daySessions and dayJournals into unique _TimelineSessionItem instances
    final List<_TimelineSessionItem> sessionItems = [];
    final Set<String> matchedJournalIds = {};

    for (final s in daySessions) {
      final sStart = s.startTime ?? s.date.subtract(Duration(minutes: s.durationMinutes));
      final sEnd = s.endTime ?? s.date;
      final courseName = s.subjectName.isNotEmpty ? s.subjectName : (s.subject.isNotEmpty ? s.subject : 'Course Study');

      StudyJournalEntry? matchedJournal;
      for (final j in dayJournals) {
        if (matchedJournalIds.contains(j.id)) continue;
        if (j.id == s.id ||
            (j.timestamp.difference(sEnd).inMinutes.abs() <= 5 &&
                (j.subjectOrCourseId.toLowerCase().contains(courseName.toLowerCase()) ||
                    courseName.toLowerCase().contains(j.subjectOrCourseId.toLowerCase())))) {
          matchedJournal = j;
          matchedJournalIds.add(j.id);
          break;
        }
      }

      sessionItems.add(_TimelineSessionItem(
        id: s.id,
        sessionId: s.id,
        journalId: matchedJournal?.id,
        courseName: matchedJournal != null && matchedJournal.title.isNotEmpty
            ? matchedJournal.title.replaceFirst('Study Log: ', '')
            : courseName,
        topics: matchedJournal?.topicsCovered,
        content: matchedJournal?.content,
        startTime: sStart.isBefore(sEnd) ? sStart : sEnd.subtract(Duration(minutes: s.durationMinutes)),
        endTime: sEnd,
        durationMinutes: s.durationMinutes > 0 ? s.durationMinutes : sEnd.difference(sStart).inMinutes.clamp(1, 1440),
      ));
    }

    for (final j in dayJournals) {
      if (matchedJournalIds.contains(j.id)) continue;
      final jEnd = j.timestamp;
      final jStart = jEnd.subtract(Duration(minutes: j.durationMinutes > 0 ? j.durationMinutes : 30));
      final courseName = j.title.isNotEmpty
          ? j.title.replaceFirst('Study Log: ', '')
          : (j.subjectOrCourseId.isNotEmpty ? j.subjectOrCourseId : 'Study Session');
      sessionItems.add(_TimelineSessionItem(
        id: j.id,
        journalId: j.id,
        courseName: courseName,
        topics: j.topicsCovered,
        content: j.content,
        startTime: jStart,
        endTime: jEnd,
        durationMinutes: j.durationMinutes > 0 ? j.durationMinutes : 30,
      ));
    }

    // Sort chronologically by startTime
    sessionItems.sort((a, b) => a.startTime.compareTo(b.startTime));

    // 2. Build Chronological Timeline with unlogged Gap Slots ("No Log")
    final List<dynamic> timelineItems = [];
    final now = DateTime.now();
    final isToday = isSameDay(date, now);

    if (sessionItems.isEmpty) {
      // Empty day: detect gap slot
      final morningStart = DateTime(date.year, date.month, date.day, 8, 0);
      final dayEnd = isToday
          ? (now.isAfter(morningStart.add(const Duration(minutes: 15))) ? now : morningStart.add(const Duration(hours: 4)))
          : DateTime(date.year, date.month, date.day, 22, 0);

      final diff = dayEnd.difference(morningStart).inMinutes;
      if (diff >= 5) {
        timelineItems.add(_TimelineGapItem(
          startTime: morningStart,
          endTime: dayEnd,
          durationMinutes: diff,
        ));
      }
    } else {
      // Gap before the first session?
      final first = sessionItems.first;
      final morningStart = DateTime(date.year, date.month, date.day, 8, 0);
      if (first.startTime.isAfter(morningStart.add(const Duration(minutes: 5)))) {
        timelineItems.add(_TimelineGapItem(
          startTime: morningStart,
          endTime: first.startTime,
          durationMinutes: first.startTime.difference(morningStart).inMinutes,
        ));
      }

      timelineItems.add(first);

      // Gaps between consecutive sessions
      for (int i = 0; i < sessionItems.length - 1; i++) {
        final current = sessionItems[i];
        final next = sessionItems[i + 1];

        if (next.startTime.isAfter(current.endTime.add(const Duration(minutes: 1)))) {
          final gapMins = next.startTime.difference(current.endTime).inMinutes;
          timelineItems.add(_TimelineGapItem(
            startTime: current.endTime,
            endTime: next.startTime,
            durationMinutes: gapMins,
          ));
        }
        timelineItems.add(next);
      }

      // Gap after the last session?
      final last = sessionItems.last;
      if (isToday) {
        if (now.isAfter(last.endTime.add(const Duration(minutes: 2)))) {
          timelineItems.add(_TimelineGapItem(
            startTime: last.endTime,
            endTime: now,
            durationMinutes: now.difference(last.endTime).inMinutes,
          ));
        }
      } else {
        final eveningEnd = DateTime(date.year, date.month, date.day, 22, 0);
        if (eveningEnd.isAfter(last.endTime.add(const Duration(minutes: 15)))) {
          timelineItems.add(_TimelineGapItem(
            startTime: last.endTime,
            endTime: eveningEnd,
            durationMinutes: eveningEnd.difference(last.endTime).inMinutes,
          ));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 22),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Previous Day',
                onPressed: () {
                  SafeHaptics.selectionClick();
                  _loadDayInsights(_selectedDay.subtract(const Duration(days: 1)));
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Center(
                  child: InkWell(
                    onTap: () => _pickInsightDay(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: Color(0xFFF2B78A), size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              formattedDateStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!isToday) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    SafeHaptics.lightImpact();
                    _loadDayInsights(DateTime.now());
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                    ),
                    child: const Text(
                      'Today',
                      style: TextStyle(
                        color: Color(0xFFF2B78A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 22),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Next Day',
                onPressed: () {
                  SafeHaptics.selectionClick();
                  _loadDayInsights(_selectedDay.add(const Duration(days: 1)));
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Metrics row: Total Focus Time | Max Single Session
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1412),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4A3830)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Focus Time', style: TextStyle(color: Colors.white54, fontSize: 10.5)),
                      const SizedBox(height: 4),
                      Text(
                        _formatHms(totalSecs),
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1412),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4A3830)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Max Single Session', style: TextStyle(color: Colors.white54, fontSize: 10.5)),
                      const SizedBox(height: 4),
                      Text(
                        _formatHms(maxSecs),
                        style: const TextStyle(color: Color(0xFFF2B78A), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1412),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF4A3830)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Session Window:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                Text(
                  startFinishStr,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Interactive Chronological Day Timeline Header
          TourShowcaseItem(
            section: TourSection.timeline,
            stepIndex: 1,
            totalSteps: 2,
            step: TourStep(
              key: _keyTimelineDayView,
              title: 'Chronological Study Log',
              description: 'Visualizes your completed focus sessions with distinct color-coded course indicators across the day.',
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.timeline_rounded, color: Color(0xFFF2B78A), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Recorded Study Topics & Timeline',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
                Text(
                  '${sessionItems.length} Sessions',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Chronological Timeline items list
          if (timelineItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text(
                  'No study topics or sessions recorded for this date.',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                ),
              ),
            )
          else
            ...timelineItems.map((item) {
              if (item is _TimelineSessionItem) {
                final courseColor = _resolveCourseColor(item.courseName, courseColorMap);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF170F0D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: courseColor.withValues(alpha: 0.25)),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Bold left accent pill / indicator strip
                          Container(
                            width: 5,
                            color: courseColor,
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: courseColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.courseName,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
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
                                          Text(
                                            '${item.durationMinutes} mins',
                                            style: TextStyle(
                                              color: courseColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          _buildSessionOptionsButton(
                                            context,
                                            item,
                                            availableCourses,
                                            courseColorMap,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_formatTimeWithPeriodPrefix(item.startTime)} - ${_formatTimeWithPeriodPrefix(item.endTime)}',
                                    style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11),
                                  ),
                                  if (item.topics != null && item.topics!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: courseColor.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: courseColor.withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        'Topics: ${item.topics}',
                                        style: TextStyle(
                                          color: courseColor.withValues(alpha: 0.95),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (item.content != null &&
                                      item.content!.isNotEmpty &&
                                      item.content != item.topics &&
                                      item.content != item.courseName &&
                                      !item.content!.startsWith('Topics: ${item.topics}')) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      item.content!,
                                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              } else if (item is _TimelineGapItem) {
                final isFirstGap = timelineItems.whereType<_TimelineGapItem>().firstOrNull == item;
                final gapWidget = Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.more_horiz_rounded, color: Colors.blueGrey.shade600, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${_formatTimeWithPeriodPrefix(item.startTime)} - ${_formatTimeWithPeriodPrefix(item.endTime)}  •  ${_formatDurationShort(item.durationMinutes)}',
                            style: TextStyle(
                              color: Colors.blueGrey.shade400,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      InkWell(
                        onTap: () => _openAddStudyLogDialog(
                          context,
                          gapStart: item.startTime,
                          gapEnd: item.endTime,
                          availableCourses: availableCourses,
                          courseColorMap: courseColorMap,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.35)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_rounded, color: Color(0xFFF2B78A), size: 14),
                              SizedBox(width: 3),
                              Text(
                                'Log',
                                style: TextStyle(
                                  color: Color(0xFFF2B78A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                if (isFirstGap) {
                  return TourShowcaseItem(
                    section: TourSection.timeline,
                    stepIndex: 2,
                    totalSteps: 2,
                    step: TourStep(
                      key: _keyTimelineGapBar,
                      title: 'Unlogged Gap Logging',
                      description: 'Detects gaps between study sessions. Tap + Log to retroactively record offline study hours.',
                    ),
                    child: gapWidget,
                  );
                }
                return gapWidget;
              }
              return const SizedBox.shrink();
            }),
        ],
      ),
    );
  }

  /// Session Card Options Menu with Edit and Delete
  Widget _buildSessionOptionsButton(
    BuildContext context,
    _TimelineSessionItem session,
    List<String> availableCourses,
    Map<String, Color> courseColorMap,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18),
      color: const Color(0xFF1E1512),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: EdgeInsets.zero,
      onSelected: (value) {
        if (value == 'edit') {
          _openEditStudyLogDialog(
            context,
            session: session,
            availableCourses: availableCourses,
            courseColorMap: courseColorMap,
          );
        } else if (value == 'delete') {
          _confirmDeleteStudyLog(context, session);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, color: Colors.white70, size: 16),
              SizedBox(width: 8),
              Text('Edit Study Log', style: TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
              SizedBox(width: 8),
              Text('Delete Study Log', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }

  /// Confirmation dialog before deleting a logged session and returning it to an unlogged gap
  void _confirmDeleteStudyLog(BuildContext context, _TimelineSessionItem session) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1512),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Delete Study Log?',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this study session for "${session.courseName}"?\n\nThis will recalculate your study time and return the time window to an unlogged gap.',
          style: const TextStyle(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid == null) return;

              try {
                if (session.sessionId != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('focus_sessions')
                      .doc(session.sessionId)
                      .delete();
                }
                if (session.journalId != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('journal')
                      .doc(session.journalId)
                      .delete();
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('notes')
                      .doc(session.journalId)
                      .delete();
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Study log deleted. Time slot reverted to unlogged gap.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error deleting study log: $e');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting study log: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Add Study Log Modal (prepopulated with gap interval, study logs only)
  void _openAddStudyLogDialog(
    BuildContext context, {
    required DateTime gapStart,
    required DateTime gapEnd,
    required List<String> availableCourses,
    required Map<String, Color> courseColorMap,
  }) {
    final coursesList = availableCourses.isNotEmpty
        ? availableCourses
        : ['General Study', 'Self Study', 'Assignment', 'Exam Prep'];

    String selectedCourse = coursesList.first;
    bool isCustomCourse = false;
    final customCourseController = TextEditingController();
    final topicsController = TextEditingController();

    DateTime startTime = gapStart;
    DateTime endTime = gapEnd;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF4A3830)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final durationMins = endTime.difference(startTime).inMinutes;
            final isEndTimeValid = endTime.isAfter(startTime);

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
                        const Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded, color: Color(0xFFF2B78A), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Add Study Log',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Log a completed study session for this time window (study sessions only).',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 18),

                    // Course selection
                    const Text(
                      'COURSE / SUBJECT',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    if (!isCustomCourse) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF110D0C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCourse,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1C1412),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                            items: coursesList.map((c) {
                              final col = _resolveCourseColor(c, courseColorMap);
                              return DropdownMenuItem<String>(
                                value: c,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        c,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => selectedCourse = val);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            isCustomCourse = true;
                            selectedCourse = '';
                          });
                        },
                        child: const Text(
                          '+ Enter custom subject / course',
                          style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: customCourseController,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'e.g., EEE 102 Lab, Calculus II',
                          hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF110D0C),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            isCustomCourse = false;
                            selectedCourse = coursesList.first;
                          });
                        },
                        child: const Text(
                          '← Choose from existing courses',
                          style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Topics Covered
                    const Text(
                      'TOPICS COVERED',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: topicsController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'e.g., Chapter 3: Complex Variables & Contour Integrals',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                        filled: true,
                        fillColor: const Color(0xFF110D0C),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Time Interval Preview & Adjust End Time
                    const Text(
                      'SESSION TIMELINE',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Start Time (Prepopulated to Gap boundary)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF110D0C),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Start Time', style: TextStyle(color: Colors.white54, fontSize: 10)),
                                const SizedBox(height: 2),
                                Text(
                                  _formatTimeWithPeriodPrefix(startTime),
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // End Time (Adjustable)
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(endTime),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  endTime = DateTime(
                                    startTime.year,
                                    startTime.month,
                                    startTime.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF110D0C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isEndTimeValid ? const Color(0xFFF2B78A).withValues(alpha: 0.4) : Colors.redAccent),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('End Time (Tap to edit)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10)),
                                      Icon(Icons.edit_outlined, size: 12, color: isEndTimeValid ? const Color(0xFFF2B78A) : Colors.redAccent),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTimeWithPeriodPrefix(endTime),
                                    style: TextStyle(
                                      color: isEndTimeValid ? Colors.white : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Duration indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEndTimeValid ? 'Duration: ${_formatDurationShort(durationMins)} ($durationMins mins)' : 'End time must be after start time',
                          style: TextStyle(
                            color: isEndTimeValid ? const Color(0xFF10B981) : Colors.redAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF2B78A),
                          foregroundColor: const Color(0xFF110D0C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        onPressed: (!isEndTimeValid || (isCustomCourse && customCourseController.text.trim().isEmpty))
                            ? null
                            : () async {
                                final courseToSave = isCustomCourse
                                    ? customCourseController.text.trim()
                                    : selectedCourse.trim();
                                if (courseToSave.isEmpty) return;

                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                if (uid == null) return;

                                final topicsText = topicsController.text.trim();
                                final durationSecs = durationMins * 60;

                                try {
                                  // Save to focus_sessions
                                  final docRef = await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .collection('focus_sessions')
                                      .add({
                                    'subject': courseToSave,
                                    'subjectName': courseToSave,
                                    'durationSeconds': durationSecs,
                                    'durationMinutes': durationMins,
                                    'startTime': Timestamp.fromDate(startTime),
                                    'endTime': Timestamp.fromDate(endTime),
                                    'timestamp': Timestamp.fromDate(endTime),
                                    'createdAt': FieldValue.serverTimestamp(),
                                    'topicsCovered': topicsText,
                                  });

                                  // Also save to journal
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .collection('journal')
                                      .doc(docRef.id)
                                      .set({
                                    'id': docRef.id,
                                    'type': 'study_session',
                                    'title': 'Study Log: $courseToSave',
                                    'content': topicsText.isNotEmpty ? 'Topics: $topicsText' : 'Study session completed.',
                                    'topicsCovered': topicsText.isNotEmpty ? topicsText : null,
                                    'durationMinutes': durationMins,
                                    'subjectOrCourseId': courseToSave,
                                    'timestamp': Timestamp.fromDate(endTime),
                                    'mode': 'university',
                                  });

                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Study log recorded successfully'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Error saving study log: $e');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error saving study log: $e')),
                                    );
                                  }
                                }
                              },
                        child: const Text(
                          'Save Study Log',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
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
  }

  /// Edit Study Log Dialog (Start time strictly fixed / read-only, End time adjustable)
  void _openEditStudyLogDialog(
    BuildContext context, {
    required _TimelineSessionItem session,
    required List<String> availableCourses,
    required Map<String, Color> courseColorMap,
  }) {
    final coursesList = availableCourses.isNotEmpty
        ? availableCourses
        : ['General Study', 'Self Study', 'Assignment', 'Exam Prep'];

    String selectedCourse = coursesList.contains(session.courseName)
        ? session.courseName
        : (coursesList.isNotEmpty ? coursesList.first : session.courseName);
    bool isCustomCourse = !coursesList.contains(session.courseName);
    final customCourseController = TextEditingController(text: isCustomCourse ? session.courseName : '');
    final topicsController = TextEditingController(text: session.topics ?? '');

    final startTime = session.startTime; // STRICTLY FIXED / READ-ONLY
    DateTime endTime = session.endTime;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF4A3830)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final durationMins = endTime.difference(startTime).inMinutes;
            final isEndTimeValid = endTime.isAfter(startTime);

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
                        const Row(
                          children: [
                            Icon(Icons.edit_note_rounded, color: Color(0xFFF2B78A), size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Edit Study Log',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Update recorded details. Start time is locked to preserve chronological order.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 18),

                    // Course selection
                    const Text(
                      'COURSE / SUBJECT',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    if (!isCustomCourse) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF110D0C),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCourse,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1C1412),
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                            items: coursesList.map((c) {
                              final col = _resolveCourseColor(c, courseColorMap);
                              return DropdownMenuItem<String>(
                                value: c,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(color: col, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        c,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => selectedCourse = val);
                              }
                            },
                          ),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: customCourseController,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'e.g., EEE 102 Lab',
                          filled: true,
                          fillColor: const Color(0xFF110D0C),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Topics Covered
                    const Text(
                      'TOPICS COVERED',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: topicsController,
                      style: const TextStyle(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'e.g., Chapter 3: Complex Variables',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                        filled: true,
                        fillColor: const Color(0xFF110D0C),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Timeline & End Time Adjustment
                    const Text(
                      'SESSION TIMELINE',
                      style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Start Time (Strictly FIXED / READ-ONLY)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF110D0C),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.lock_outline_rounded, color: Colors.white38, size: 12),
                                    SizedBox(width: 4),
                                    Text('Start Time (Fixed)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatTimeWithPeriodPrefix(startTime),
                                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // End Time (Adjustable)
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(endTime),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  endTime = DateTime(
                                    startTime.year,
                                    startTime.month,
                                    startTime.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF110D0C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isEndTimeValid ? const Color(0xFFF2B78A).withValues(alpha: 0.4) : Colors.redAccent),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('End Time (Tap to edit)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10)),
                                      Icon(Icons.edit_outlined, size: 12, color: isEndTimeValid ? const Color(0xFFF2B78A) : Colors.redAccent),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTimeWithPeriodPrefix(endTime),
                                    style: TextStyle(
                                      color: isEndTimeValid ? Colors.white : Colors.redAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Duration indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEndTimeValid ? 'Updated Duration: ${_formatDurationShort(durationMins)} ($durationMins mins)' : 'End time must be after start time',
                          style: TextStyle(
                            color: isEndTimeValid ? const Color(0xFF10B981) : Colors.redAccent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF2B78A),
                          foregroundColor: const Color(0xFF110D0C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        onPressed: (!isEndTimeValid || (isCustomCourse && customCourseController.text.trim().isEmpty))
                            ? null
                            : () async {
                                final courseToSave = isCustomCourse
                                    ? customCourseController.text.trim()
                                    : selectedCourse.trim();
                                if (courseToSave.isEmpty) return;

                                final uid = FirebaseAuth.instance.currentUser?.uid;
                                if (uid == null) return;

                                final topicsText = topicsController.text.trim();
                                final durationSecs = durationMins * 60;

                                try {
                                  if (session.sessionId != null) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .collection('focus_sessions')
                                        .doc(session.sessionId)
                                        .update({
                                      'subject': courseToSave,
                                      'subjectName': courseToSave,
                                      'endTime': Timestamp.fromDate(endTime),
                                      'timestamp': Timestamp.fromDate(endTime),
                                      'durationMinutes': durationMins,
                                      'durationSeconds': durationSecs,
                                      'topicsCovered': topicsText,
                                    });
                                  }

                                  if (session.journalId != null) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .collection('journal')
                                        .doc(session.journalId)
                                        .update({
                                      'title': 'Study Log: $courseToSave',
                                      'subjectOrCourseId': courseToSave,
                                      'topicsCovered': topicsText.isNotEmpty ? topicsText : null,
                                      'content': topicsText.isNotEmpty ? 'Topics: $topicsText' : 'Study session completed.',
                                      'durationMinutes': durationMins,
                                      'timestamp': Timestamp.fromDate(endTime),
                                    });
                                  }

                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Study log updated successfully'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint('Error updating study log: $e');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error updating study log: $e')),
                                    );
                                  }
                                }
                              },
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
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
  }

  Widget _buildWeeklyDistributionCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions,
  ) {
    final selectedDate = _uniSelectedInsightDate;
    final monday = selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final weekDays = List.generate(7, (i) => DateTime(monday.year, monday.month, monday.day).add(Duration(days: i)));

    final dayTotals = weekDays.map((d) {
      final sessions = universitySessions.where((s) => isSameDay(s.date, d));
      final totalMins = sessions.fold<int>(0, (acc, s) => acc + s.durationMinutes);
      return totalMins;
    }).toList();

    final maxMins = dayTotals.isEmpty ? 60.0 : (dayTotals.reduce((a, b) => a > b ? a : b).toDouble().clamp(60.0, 1440.0));
    final dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Weekly Focus Distribution',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '${monday.day}/${monday.month} - ${weekDays.last.day}/${weekDays.last.month}',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxMins * 1.15,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < dayNames.length) {
                          final isToday = isSameDay(weekDays[idx], DateTime.now());
                          final isSelected = isSameDay(weekDays[idx], selectedDate);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              dayNames[idx],
                              style: TextStyle(
                                color: isSelected
                                    ? const Color(0xFFF2B78A)
                                    : (isToday ? const Color(0xFF10B981) : Colors.blueGrey.shade400),
                                fontSize: 11.5,
                                fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(7, (i) {
                  final mins = dayTotals[i];
                  final isSelected = isSameDay(weekDays[i], selectedDate);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: mins.toDouble(),
                        color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF10B981),
                        width: 20,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxMins * 1.15,
                          color: Colors.white.withValues(alpha: 0.04),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSemesterTrendProgressionCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions,
  ) {
    final totalMins = universitySessions.fold<int>(0, (acc, s) => acc + s.durationMinutes);
    final totalHours = totalMins / 60.0;
    final activeDays = universitySessions.map((s) => '${s.date.year}-${s.date.month}-${s.date.day}').toSet().length;
    final avgDaily = activeDays > 0 ? (totalHours / activeDays) : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFA855F7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.trending_up_rounded, color: Color(0xFFA855F7), size: 20),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semester Study Progression',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text(
                    'Cumulative focus duration & momentum',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Hours', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${totalHours.toStringAsFixed(1)}h',
                        style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active Days', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '$activeDays Days',
                        style: const TextStyle(color: Color(0xFFF2B78A), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Avg / Active Day', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${avgDaily.toStringAsFixed(1)}h',
                        style: const TextStyle(color: Color(0xFFA855F7), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayFocusSessionsCard(
    Color cardColor,
    Color accentColor,
    List<FocusSession> universitySessions, {
    Map<String, Color>? courseColorMap,
  }) {
    final date = _uniSelectedInsightDate;
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final daySessions = universitySessions
        .where((s) =>
            isSameDay(s.date, date) ||
            (s.startTime != null && isSameDay(s.startTime!, date)) ||
            (!s.date.isBefore(startOfDay) && !s.date.isAfter(endOfDay)))
        .toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sessions on ${date.day}/${date.month}/${date.year}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                '${daySessions.length} sessions',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (daySessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: Center(
                child: Text(
                  'No focus sessions recorded on this day.',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                ),
              ),
            )
          else
            ...daySessions.map((s) {
              final startStr = s.startTime != null ? _formatTime12h(s.startTime!) : _formatTime12h(s.date);
              final endStr = s.endTime != null ? ' - ${_formatTime12h(s.endTime!)}' : '';
              final courseColor = _resolveCourseColor(s.subject, courseColorMap ?? {});
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF170F0D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: courseColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            bottomLeft: Radius.circular(10),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.timer_outlined, color: courseColor, size: 16),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.subject.isNotEmpty ? s.subject : 'Course Study',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        '$startStr$endStr',
                                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                '${s.durationMinutes} mins',
                                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _formatHms(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatTime12h(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min $period';
  }

  Color _getHeatmapIntensityColor(double hours) {
    if (hours <= 0) return const Color(0xFF1E1512);
    if (hours < 4.0) return const Color(0xFF4A3830);
    if (hours < 7.0) return const Color(0xFF8C5D3E);
    if (hours < 10.0) return const Color(0xFFD48D5E);
    return const Color(0xFFF2B78A);
  }

  String _getMonthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  String _getWeekdayName(int weekday) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    if (weekday >= 1 && weekday <= 7) return names[weekday - 1];
    return '';
  }

  // ============================================================================
  // DESKTOP-NATIVE ACADEMIC INSIGHTS SUITE (SCREEN 05)
  // ============================================================================

  Widget _buildDesktopInsightsScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A. Analytics Sub-Navigation
                _buildDesktopAnalyticsSubNav(),

                const SizedBox(height: 24),

                // B. Top KPIs (4 Horizontal Metric Cards)
                _buildDesktopTopKpis(),

                const SizedBox(height: 24),

                // C. Middle Row: Weekly Histogram (flex 6) & Subject Distribution Donut (flex 4)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _buildDesktopWeeklyHistogram(),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 4,
                      child: _buildDesktopSubjectDistribution(),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // D. Daily Timeline Bar
                _buildDesktopDailyTimelineBar(),

                const SizedBox(height: 24),

                // E. Focus Heatmap
                _buildDesktopFocusHeatmap(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopAnalyticsSubNav() {
    final categories = ['Overview', 'Time', 'Subjects', 'Performance', 'CGPA Forecaster'];
    final periods = ['Day', 'Week', 'Month', 'Trend'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Row(
        children: [
          // Category Tabs
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final active = _desktopCategoryTab == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: InkWell(
                      onTap: () {
                        SafeHaptics.selectionClick();
                        setState(() => _desktopCategoryTab = cat);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? const Color(0xFFF2B78A).withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: active ? Border.all(color: const Color(0xFFF2B78A), width: 0.8) : null,
                        ),
                        child: Text(
                          cat,
                          style: GoogleFonts.plusJakartaSans(
                            color: active ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Period Segmented Buttons
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              children: periods.map((p) {
                final active = _desktopPeriodTab == p;
                return InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() => _desktopPeriodTab = p);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFFF2B78A).withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: active ? Border.all(color: const Color(0xFFF2B78A), width: 0.8) : null,
                    ),
                    child: Text(
                      p,
                      style: GoogleFonts.plusJakartaSans(
                        color: active ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(width: 14),

          // Date navigator
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFFEDE8E3), size: 20),
                onPressed: () => SafeHaptics.selectionClick(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 6),
              Text(
                '22 - 28 Sep 2026',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFEDE8E3), size: 20),
                onPressed: () => SafeHaptics.selectionClick(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTopKpis() {
    final sessionsAsync = ref.watch(studySessionsDateStreamProvider(_selectedDay));
    final profileAsync = ref.watch(liveUserProfileProvider);
    final profile = profileAsync.value;
    final sessions = sessionsAsync.value ?? [];

    final int totalSec = sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
    final String focusTimeStr = sessions.isNotEmpty
        ? (totalSec >= 3600
            ? '${totalSec ~/ 3600}h ${(totalSec % 3600) ~/ 60}m'
            : '${totalSec ~/ 60}m')
        : (profile?.totalFocusMinutes != null && profile!.totalFocusMinutes > 0
            ? '${profile.totalFocusMinutes ~/ 60}h ${profile.totalFocusMinutes % 60}m'
            : '18h 32m');

    final String sessionCountStr = sessions.isNotEmpty
        ? '${sessions.length}'
        : '42';

    final int maxSec = sessions.fold<int>(0, (currMax, s) => s.durationSeconds > currMax ? s.durationSeconds : currMax);
    final String maxSessionStr = maxSec > 0
        ? (maxSec >= 3600 ? '${maxSec ~/ 3600}h ${(maxSec % 3600) ~/ 60}m' : '${maxSec ~/ 60}m')
        : '2h 15m';

    final String streakSubtitle = profile != null
        ? '${profile.streakDays}-day streak active'
        : '▲ +12% vs last week';

    return Row(
      children: [
        Expanded(
          child: _desktopKpiCard(
            title: 'TOTAL FOCUS TIME',
            value: focusTimeStr,
            subtitle: streakSubtitle,
            subtitleColor: const Color(0xFF34D399),
            icon: Icons.timer_outlined,
            iconColor: const Color(0xFFF2B78A),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _desktopKpiCard(
            title: 'SESSIONS',
            value: sessionCountStr,
            subtitle: '▲ High consistency',
            subtitleColor: const Color(0xFF34D399),
            icon: Icons.psychology_outlined,
            iconColor: const Color(0xFF34D399),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _desktopKpiCard(
            title: 'MAX SINGLE SESSION',
            value: maxSessionStr,
            subtitle: 'Longest flow state',
            subtitleColor: const Color(0xFF9E8C82),
            icon: Icons.bolt_rounded,
            iconColor: const Color(0xFFF2B78A),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _desktopKpiCard(
            title: 'AVG DAILY FOCUS',
            value: profile?.todaysFocusMinutes != null && profile!.todaysFocusMinutes > 0
                ? '${profile.todaysFocusMinutes}m'
                : '26m',
            subtitle: 'Consistent pace',
            subtitleColor: const Color(0xFF9E8C82),
            icon: Icons.trending_up_rounded,
            iconColor: const Color(0xFF34D399),
          ),
        ),
      ],
    );
  }

  Widget _desktopKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color subtitleColor,
    required IconData icon,
    required Color iconColor,
  }) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              color: subtitleColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopWeeklyHistogram() {
    final todayWeekday = DateTime.now().weekday; // 1 = Mon ... 7 = Sun
    final days = [
      {'day': 'Mon', 'val': 2.4, 'max': 5.0, 'highlight': todayWeekday == 1},
      {'day': 'Tue', 'val': 3.5, 'max': 5.0, 'highlight': todayWeekday == 2},
      {'day': 'Wed', 'val': 2.8, 'max': 5.0, 'highlight': todayWeekday == 3},
      {'day': 'Thu', 'val': 4.2, 'max': 5.0, 'highlight': todayWeekday == 4},
      {'day': 'Fri', 'val': 1.8, 'max': 5.0, 'highlight': todayWeekday == 5},
      {'day': 'Sat', 'val': 3.0, 'max': 5.0, 'highlight': todayWeekday == 6},
      {'day': 'Sun', 'val': 0.8, 'max': 5.0, 'highlight': todayWeekday == 7},
    ];

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WEEKLY FOCUS TIME',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                'Peak: Thu (4.2 hrs)',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFF2B78A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: days.map((d) {
                final double val = d['val'] as double;
                final bool isHl = d['highlight'] == true;
                final double heightFactor = val / 5.0;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${val}h',
                      style: GoogleFonts.jetBrainsMono(
                        color: isHl ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 32,
                      height: 120 * heightFactor,
                      decoration: BoxDecoration(
                        color: isHl ? const Color(0xFFF2B78A) : const Color(0xFF382A24),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: isHl
                            ? [
                                BoxShadow(
                                  color: const Color(0xFFF2B78A).withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      d['day'] as String,
                      style: GoogleFonts.jetBrainsMono(
                        color: isHl ? const Color(0xFFEDE8E3) : const Color(0xFF9E8C82),
                        fontSize: 12,
                        fontWeight: isHl ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSubjectDistribution() {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = coursesAsync.value;

    const palette = [
      Color(0xFFF2B78A),
      Color(0xFF34D399),
      Color(0xFF60A5FA),
      Color(0xFFA78BFA),
    ];

    final hasLiveCourses = courses != null && courses.isNotEmpty;
    final displayCourses = hasLiveCourses ? courses.take(4).toList() : null;

    final totalTopics = hasLiveCourses
        ? displayCourses!.fold<int>(0, (total, c) => total + (c.totalTopicsCount > 0 ? c.totalTopicsCount : 1))
        : 0;

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
          Text(
            'SUBJECT DISTRIBUTION',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFF9E8C82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 20),
          if (!hasLiveCourses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No enrolled courses to distribute.',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF9E8C82),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                // Circular Donut representation
                SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const CircularProgressIndicator(
                        value: 1.0,
                        strokeWidth: 14,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2E2623)),
                      ),
                      CircularProgressIndicator(
                        value: (totalTopics > 0 ? (displayCourses!.first.totalTopicsCount / totalTopics) : 0.0).clamp(0.0, 1.0),
                        strokeWidth: 14,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF2B78A)),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$totalTopics',
                            style: GoogleFonts.jetBrainsMono(
                              color: const Color(0xFFEDE8E3),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Topics',
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF9E8C82),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Subject Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: displayCourses!.asMap().entries.map((e) {
                      final idx = e.key;
                      final c = e.value;
                      final color = palette[idx % palette.length];
                      final count = c.totalTopicsCount > 0 ? c.totalTopicsCount : 1;
                      final pct = totalTopics > 0 ? ((count / totalTopics) * 100).round() : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _subjectLegendRow(c.code, '$pct%', color),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _subjectLegendRow(String title, String pct, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 12.5),
          ),
        ),
        Text(
          pct,
          style: GoogleFonts.jetBrainsMono(
            color: const Color(0xFF9E8C82),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopDailyTimelineBar() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.timeline_rounded, color: Color(0xFFF2B78A), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '24-HOUR CHRONOLOGICAL TIMELINE',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF9E8C82),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF2B78A),
                  side: const BorderSide(color: Color(0xFF382A24)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  minimumSize: Size.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => SafeHaptics.selectionClick(),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Log Gap'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 24h timeline bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 24,
              color: const Color(0xFF241C1A),
              child: Row(
                children: [
                  Expanded(flex: 9, child: Container(color: Colors.transparent)),
                  Expanded(flex: 2, child: Container(color: const Color(0xFFF2B78A))), // 9-11am
                  Expanded(flex: 2, child: Container(color: Colors.transparent)),
                  Expanded(flex: 3, child: Container(color: const Color(0xFF34D399))), // 1-4pm
                  Expanded(flex: 3, child: Container(color: Colors.transparent)),
                  Expanded(flex: 2, child: Container(color: const Color(0xFF60A5FA))), // 7-9pm
                  Expanded(flex: 3, child: Container(color: Colors.transparent)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('00:00', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10)),
              Text('06:00', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10)),
              Text('12:00', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10)),
              Text('18:00', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10)),
              Text('24:00', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF9E8C82), fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFocusHeatmap() {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STUDY DENSITY (HEATMAP)',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
              Row(
                children: [
                  Text('Less', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 11)),
                  const SizedBox(width: 6),
                  _heatmapCell(const Color(0xFF241C1A)),
                  _heatmapCell(const Color(0xFF382A24)),
                  _heatmapCell(const Color(0xFF6E4D3E)),
                  _heatmapCell(const Color(0xFFF2B78A)),
                  _heatmapCell(const Color(0xFF34D399)),
                  const SizedBox(width: 6),
                  Text('More', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 7 rows x 24 columns
          Column(
            children: List.generate(7, (rowIndex) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  children: List.generate(24, (colIndex) {
                    final int pseudoDensity = (rowIndex * 3 + colIndex * 7) % 5;
                    final Color cellColor = pseudoDensity == 0
                        ? const Color(0xFF241C1A)
                        : (pseudoDensity == 1
                            ? const Color(0xFF382A24)
                            : (pseudoDensity == 2
                                ? const Color(0xFF6E4D3E)
                                : (pseudoDensity == 3
                                    ? const Color(0xFFF2B78A)
                                    : const Color(0xFF34D399))));
                    return Expanded(
                      child: Container(
                        height: 14,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _heatmapCell(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
    );
  }
}
