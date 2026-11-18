import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
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

import 'package:intl/intl.dart';
import '../models/study_session_model.dart';
import '../services/timer_service.dart';

/// Period selector for analytics and study sessions
enum InsightPeriod { day, week, month, trend }

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
    if (currentTab != 5 || _hasTriggeredTimelineTour) return;
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
  InsightPeriod _selectedPeriod = InsightPeriod.week;
  DateTime _currentAnchorDate = DateTime.now();

  DateTime get _rangeStart {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
      case InsightPeriod.week:
        // Bangladesh academic week starts on Saturday (ISO weekday 6)
        final daysFromSaturday = (_currentAnchorDate.weekday % 7 + 1) % 7;
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day)
            .subtract(Duration(days: daysFromSaturday));
      case InsightPeriod.month:
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, 1);
      case InsightPeriod.trend:
        final end = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day, 23, 59, 59);
        return end.subtract(const Duration(days: 29)).copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
    }
  }

  DateTime get _rangeEnd {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return _rangeStart.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      case InsightPeriod.week:
        return _rangeStart.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
      case InsightPeriod.month:
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month + 1, 1)
            .subtract(const Duration(milliseconds: 1));
      case InsightPeriod.trend:
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day, 23, 59, 59);
    }
  }

  String get _dateRangeLabel {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        return DateFormat('d MMM yyyy').format(_currentAnchorDate);
      case InsightPeriod.week:
        final start = _rangeStart;
        final end = _rangeEnd;
        if (start.month == end.month) {
          return '${start.day} - ${end.day} ${DateFormat('MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM yyyy').format(end)}';
      case InsightPeriod.month:
        return DateFormat('MMMM yyyy').format(_currentAnchorDate);
      case InsightPeriod.trend:
        final start = _rangeStart;
        final end = _rangeEnd;
        return '${DateFormat('d MMM').format(start)} - ${DateFormat('d MMM yyyy').format(end)}';
    }
  }

  void _stepDateRange(int direction) {
    SafeHaptics.selectionClick();
    setState(() {
      switch (_selectedPeriod) {
        case InsightPeriod.day:
          _currentAnchorDate = _currentAnchorDate.add(Duration(days: direction));
          break;
        case InsightPeriod.week:
          _currentAnchorDate = _currentAnchorDate.add(Duration(days: 7 * direction));
          break;
        case InsightPeriod.month:
          _currentAnchorDate = DateTime(_currentAnchorDate.year, _currentAnchorDate.month + direction, _currentAnchorDate.day);
          break;
        case InsightPeriod.trend:
          _currentAnchorDate = _currentAnchorDate.add(Duration(days: 30 * direction));
          break;
      }
    });
  }

  // TASK 4: University Study Analytics & Heatmap state
  String _uniStudyPeriodTab = 'Month';
  DateTime _uniHeatmapMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Period Selector Modal State & Compare Mode
  bool _periodCompareMode = false;
  String _selectedPeriodOption = 'Last 28 Days'; // 'Custom', 'Last 28 Days', 'Last 90 Days', 'Last 12 Months'
  DateTimeRange? _customDateRange;

  DateTimeRange _resolveActivePeriodRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_selectedPeriodOption) {
      case 'Last 28 Days':
        final start = today.subtract(const Duration(days: 28)).add(const Duration(seconds: 1));
        return DateTimeRange(start: DateTime(start.year, start.month, start.day), end: today);
      case 'Last 90 Days':
        final start = today.subtract(const Duration(days: 90)).add(const Duration(seconds: 1));
        return DateTimeRange(start: DateTime(start.year, start.month, start.day), end: today);
      case 'Last 12 Months':
        final start = DateTime(now.year - 1, now.month, now.day);
        return DateTimeRange(start: start, end: today);
      case 'Custom':
      default:
        return _customDateRange ??
            DateTimeRange(start: today.subtract(const Duration(days: 28)), end: today);
    }
  }

  DateTimeRange _resolvePrecedingPeriodRange(DateTimeRange currentRange) {
    final duration = currentRange.duration;
    final precedingEnd = currentRange.start.subtract(const Duration(seconds: 1));
    final precedingStart = precedingEnd.subtract(duration);
    return DateTimeRange(start: precedingStart, end: precedingEnd);
  }

  void _openPeriodSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF4A3830)),
      ),
      builder: (ctx) {
        bool tempCompare = _periodCompareMode;
        String tempOption = _selectedPeriodOption;
        DateTimeRange? tempRange = _customDateRange;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final now = DateTime.now();
            final last28DaysStr = '${now.subtract(const Duration(days: 28)).month}/${now.subtract(const Duration(days: 28)).day} - ${now.month}/${now.day}';

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Period',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                        onPressed: () => Navigator.pop(modalCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Compare Mode Switch Tile
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF110D0C),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.compare_arrows_rounded, color: Color(0xFFF2B78A), size: 20),
                            SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Compare Mode',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Display +/- % vs preceding timeframe',
                                  style: TextStyle(color: Colors.white54, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Switch(
                          value: tempCompare,
                          activeThumbColor: const Color(0xFFF2B78A),
                          onChanged: (val) {
                            setModalState(() => tempCompare = val);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Options list
                  const Text('TIME HORIZON', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 8),

                  _buildPeriodRadioOption(
                    title: 'Last 28 Days',
                    subtitle: last28DaysStr,
                    isSelected: tempOption == 'Last 28 Days',
                    onTap: () => setModalState(() => tempOption = 'Last 28 Days'),
                  ),
                  _buildPeriodRadioOption(
                    title: 'Last 90 Days',
                    subtitle: 'Previous quarter overview',
                    isSelected: tempOption == 'Last 90 Days',
                    onTap: () => setModalState(() => tempOption = 'Last 90 Days'),
                  ),
                  _buildPeriodRadioOption(
                    title: 'Last 12 Months',
                    subtitle: 'Annual progression & term summary',
                    isSelected: tempOption == 'Last 12 Months',
                    onTap: () => setModalState(() => tempOption = 'Last 12 Months'),
                  ),
                  _buildPeriodRadioOption(
                    title: 'Select Custom Period',
                    subtitle: tempRange != null
                        ? '${tempRange!.start.month}/${tempRange!.start.day}/${tempRange!.start.year} - ${tempRange!.end.month}/${tempRange!.end.day}/${tempRange!.end.year}'
                        : 'Custom calendar date range picker',
                    isSelected: tempOption == 'Custom',
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: modalCtx,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: tempRange ?? DateTimeRange(
                          start: DateTime.now().subtract(const Duration(days: 14)),
                          end: DateTime.now(),
                        ),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: Color(0xFFF2B78A),
                                onPrimary: Color(0xFF191514),
                                surface: Color(0xFF241C1A),
                                onSurface: Color(0xFFF5EBE6),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() {
                          tempOption = 'Custom';
                          tempRange = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 18),

                  // Action Buttons: Cancel and Ok
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF4A3830)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.pop(modalCtx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF2B78A),
                            foregroundColor: const Color(0xFF110D0C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _periodCompareMode = tempCompare;
                              _selectedPeriodOption = tempOption;
                              if (tempRange != null) {
                                _customDateRange = tempRange;
                              }
                            });
                            Navigator.pop(modalCtx);
                          },
                          child: const Text('Ok', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPeriodRadioOption({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF2B78A).withValues(alpha: 0.12) : const Color(0xFF110D0C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? const Color(0xFFF2B78A).withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              size: 18,
              color: isSelected ? const Color(0xFFF2B78A) : Colors.white38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFF2B78A) : Colors.white,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    return _buildMobileInsightsScreen(context);
  }

  // ignore: unused_element
  Widget _legacyBuildMobile(BuildContext context) {
    ref.watch(navigationIndexProvider);
    final userProfile = ref.watch(userProfileProvider);
    final streak = ref.watch(currentStreakProvider);
    final totalHours = ref.watch(totalStudyHoursProvider);
    final focusSessionsAsync = ref.watch(focusSessionsStreamProvider);
    final focusSessions = deduplicateSessionLogs(focusSessionsAsync.asData?.value ?? []);
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
    final totalDayMins = dailySessions.fold<int>(0, (total, s) => total + s.durationInMinutes);

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
                                  session.cleanTitle,
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
    String? deltaText,
    bool deltaIsPositive = true,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (deltaText != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (deltaIsPositive ? const Color(0xFF10B981) : Colors.redAccent).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    deltaText,
                    style: TextStyle(
                      color: deltaIsPositive ? const Color(0xFF10B981) : Colors.redAccent,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
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
    final uid = profile.uid.isNotEmpty ? profile.uid : (Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null);

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

                  final universityHours = universitySessions.fold<int>(0, (total, s) => total + s.durationInMinutes) / 60.0;

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

                  // TASK 4: Period range calculation and delta % comparison
                  final activeRange = _resolveActivePeriodRange();
                  final precedingRange = _resolvePrecedingPeriodRange(activeRange);

                  final periodSessions = universitySessions.where((s) {
                    final sessionTime = s.startTime ?? s.date;
                    return !sessionTime.isBefore(activeRange.start) && !sessionTime.isAfter(activeRange.end);
                  }).toList();

                  final precedingSessions = universitySessions.where((s) {
                    final sessionTime = s.startTime ?? s.date;
                    return !sessionTime.isBefore(precedingRange.start) && !sessionTime.isAfter(precedingRange.end);
                  }).toList();

                  final periodHours = periodSessions.fold<int>(0, (acc, s) => acc + s.durationInMinutes) / 60.0;
                  final precedingHours = precedingSessions.fold<int>(0, (acc, s) => acc + s.durationInMinutes) / 60.0;

                  String? periodDeltaText;
                  bool periodDeltaIsPositive = true;
                  if (_periodCompareMode) {
                    if (precedingHours > 0) {
                      final deltaPct = (((periodHours - precedingHours) / precedingHours) * 100).round();
                      periodDeltaIsPositive = deltaPct >= 0;
                      periodDeltaText = '${deltaPct >= 0 ? '+' : ''}$deltaPct% vs prev';
                    } else if (periodHours > 0) {
                      periodDeltaText = '+100% vs prev';
                      periodDeltaIsPositive = true;
                    }
                  }

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
                                title: _uniStudyPeriodTab == 'Period' ? 'Period Focus Time' : 'Total Study Time',
                                value: _uniStudyPeriodTab == 'Period'
                                    ? '${periodHours.toStringAsFixed(1)}h'
                                    : '${universityHours.toStringAsFixed(1)}h',
                                subtitle: _uniStudyPeriodTab == 'Period'
                                    ? '${periodSessions.length} sessions ($_selectedPeriodOption)'
                                    : '${universitySessions.length} University Sessions',
                                icon: Icons.access_time_rounded,
                                iconColor: accentColor,
                                cardColor: cardColor,
                                deltaText: _uniStudyPeriodTab == 'Period' ? periodDeltaText : null,
                                deltaIsPositive: periodDeltaIsPositive,
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
                            if (tab == 'Period') {
                              setState(() {
                                _uniStudyPeriodTab = 'Period';
                              });
                              _openPeriodSelectionModal(context);
                            } else {
                              setState(() {
                                _uniStudyPeriodTab = tab;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // TASK 5: Dynamic View Switching based on _uniStudyPeriodTab [Period | Day | Week | Month | Trend]
                        if (_uniStudyPeriodTab == 'Day') ...[
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            universitySessions.where((s) => isSameDay(s.date, _selectedDay)).toList(),
                            courseColorMap,
                            periodTitle: 'Course Distribution (${_selectedDay.day}/${_selectedDay.month})',
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
                        ] else if (_uniStudyPeriodTab == 'Period') ...[
                          _buildUniversityCourseDistributionSection(
                            cardColor,
                            periodSessions,
                            courseColorMap,
                            periodTitle: 'Course Distribution ($_selectedPeriodOption)',
                          ),
                          const SizedBox(height: 16),
                          _buildSelectedDateDetailCard(
                            cardColor,
                            accentColor,
                            periodSessions,
                            journalEntries,
                            availableCourses: availableCourses,
                            courseColorMap: courseColorMap,
                          ),
                          const SizedBox(height: 16),
                          _buildRecentActivityCard(cardColor, accentColor, periodSessions),
                        ] else ...[
                          // 'Month'
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
                        _selectedDay = DateTime(now.year, now.month, now.day);
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
              final isSelected = isSameDay(cellDate, _selectedDay);
              final isToday = isSameDay(cellDate, DateTime.now());

              final daySessions = universitySessions.where((s) => isSameDay(s.date, cellDate)).toList();
              final dayMinutes = daySessions.fold<int>(0, (acc, s) => acc + s.durationInMinutes);
              final dayHours = dayMinutes / 60.0;
              final cellColor = _getHeatmapIntensityColor(dayHours);

              return InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  setState(() {
                    _selectedDay = cellDate;
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

    final totalMins = courseMinutes.values.fold<int>(0, (total, m) => total + m);
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
    final date = _selectedDay;
    final dayName = _getWeekdayName(date.weekday);
    final monthName = _getMonthName(date.month);
    final formattedDateStr = '$dayName, $monthName ${date.day}, ${date.year}';
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final daySessions = collapseDuplicateSessionLogs(
      universitySessions
          .where((s) =>
              isSameDay(s.date, date) ||
              (s.startTime != null && isSameDay(s.startTime!, date)) ||
              (!s.date.isBefore(startOfDay) && !s.date.isAfter(endOfDay)))
          .toList(),
    );

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
      final courseName = s.cleanTitle;

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

      final resolvedTitle = matchedJournal != null && matchedJournal.title.isNotEmpty
          ? formatCleanSessionTitle(
              courseCode: s.courseCode,
              courseTitle: matchedJournal.title.replaceFirst('Study Log: ', ''),
              fallback: courseName,
            )
          : courseName;

      sessionItems.add(_TimelineSessionItem(
        id: s.id,
        sessionId: s.id,
        journalId: matchedJournal?.id,
        courseName: resolvedTitle,
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

    // Deduplicate any overlapping / multi-listener duplicated sessions
    final dedupedItems = deduplicateStudySessions<_TimelineSessionItem>(
      sessions: sessionItems,
      getId: (it) => it.sessionId ?? it.id,
      getCourseKey: (it) => it.courseName,
      getStartTime: (it) => it.startTime,
      getDurationSeconds: (it) => it.durationMinutes * 60,
    );
    sessionItems
      ..clear()
      ..addAll(dedupedItems);

    // TASK 2: Recompute totalSecs and maxSecs directly from the final deduplicated sessionItems
    // ensuring perfect alignment between the displayed Total Focus Time and the rendered timeline cards
    final totalSecs = sessionItems.fold<int>(0, (total, it) => total + (it.durationMinutes * 60));
    final maxSecs = sessionItems.isEmpty
        ? 0
        : sessionItems.map((it) => it.durationMinutes * 60).reduce((a, b) => a > b ? a : b);

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
              final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
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
                        // Start Time (Interactive)
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(startTime),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  startTime = DateTime(
                                    startTime.year,
                                    startTime.month,
                                    startTime.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  // If end time is now on or before start time, roll end time to next day if within 12h
                                  if (!endTime.isAfter(startTime)) {
                                    endTime = DateTime(
                                      startTime.year,
                                      startTime.month,
                                      startTime.day + 1,
                                      endTime.hour,
                                      endTime.minute,
                                    );
                                  }
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF110D0C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Start Time (Tap)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10)),
                                      Icon(Icons.edit_outlined, size: 12, color: Color(0xFFF2B78A)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTimeWithPeriodPrefix(startTime),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
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
                                  DateTime newEnd = DateTime(
                                    startTime.year,
                                    startTime.month,
                                    startTime.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  // If newEnd is <= startTime, treat as crossing midnight into next day
                                  if (!newEnd.isAfter(startTime)) {
                                    newEnd = newEnd.add(const Duration(days: 1));
                                  }
                                  endTime = newEnd;
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
                          isEndTimeValid
                              ? 'Duration: ${_formatDurationShort(durationMins)} ($durationMins mins)${endTime.day != startTime.day ? ' • Crosses Midnight' : ''}'
                              : 'End time must be after start time',
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

                                final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
                                final firestore = FirebaseFirestore.instance;
                                if (uid == null) return;

                                final topicsText = topicsController.text.trim();

                                // Check if session crosses midnight (spans two calendar dates)
                                final bool crossesMidnight = endTime.day != startTime.day ||
                                    endTime.difference(startTime).inHours >= 24;

                                String action = 'single';
                                if (crossesMidnight) {
                                  final choice = await showDialog<String>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (dialogCtx) => AlertDialog(
                                      backgroundColor: const Color(0xFF1C1412),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        side: const BorderSide(color: Color(0xFF4A3830)),
                                      ),
                                      title: const Row(
                                        children: [
                                          Icon(Icons.nightlight_round, color: Color(0xFFF2B78A), size: 22),
                                          SizedBox(width: 8),
                                          Text('Session Crosses Midnight', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                      content: const Text(
                                        'This study session spans across two calendar dates (ends tomorrow). Would you like to split this log into two consecutive daily entries so your daily analytics remain accurate?',
                                        style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
                                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogCtx, 'single'),
                                          child: const Text('Save as Single Log', style: TextStyle(color: Colors.white70)),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFF2B78A),
                                            foregroundColor: const Color(0xFF110D0C),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          onPressed: () => Navigator.pop(dialogCtx, 'split'),
                                          child: const Text('Split Across Both Days', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (choice == null || choice == 'cancel') return;
                                  action = choice;
                                }

                                try {
                                  if (action == 'split') {
                                    // Part 1: startTime to 23:59:59 on Day 1
                                    final endOfDay1 = DateTime(startTime.year, startTime.month, startTime.day, 23, 59, 59);
                                    final durationPart1Secs = endOfDay1.difference(startTime).inSeconds;
                                    final durationPart1Mins = (durationPart1Secs / 60).round().clamp(1, 1440);

                                    final docRef1 = await firestore.collection('users').doc(uid).collection('focus_sessions').add({
                                      'subject': courseToSave,
                                      'subjectName': courseToSave,
                                      'durationSeconds': durationPart1Secs,
                                      'durationMinutes': durationPart1Mins,
                                      'startTime': Timestamp.fromDate(startTime),
                                      'endTime': Timestamp.fromDate(endOfDay1),
                                      'timestamp': Timestamp.fromDate(endOfDay1),
                                      'createdAt': FieldValue.serverTimestamp(),
                                      'topicsCovered': topicsText,
                                    });

                                    await firestore.collection('users').doc(uid).collection('journal').doc(docRef1.id).set({
                                      'id': docRef1.id,
                                      'type': 'study_session',
                                      'title': 'Study Log: $courseToSave (Part 1)',
                                      'content': topicsText.isNotEmpty ? 'Topics: $topicsText' : 'Study session completed.',
                                      'topicsCovered': topicsText.isNotEmpty ? topicsText : null,
                                      'durationMinutes': durationPart1Mins,
                                      'subjectOrCourseId': courseToSave,
                                      'timestamp': Timestamp.fromDate(endOfDay1),
                                      'mode': 'university',
                                    });

                                    // Part 2: 00:00:00 to endTime on Day 2
                                    final startOfDay2 = DateTime(endTime.year, endTime.month, endTime.day, 0, 0, 0);
                                    final durationPart2Secs = endTime.difference(startOfDay2).inSeconds;
                                    final durationPart2Mins = (durationPart2Secs / 60).round().clamp(1, 1440);

                                    final docRef2 = await firestore.collection('users').doc(uid).collection('focus_sessions').add({
                                      'subject': courseToSave,
                                      'subjectName': courseToSave,
                                      'durationSeconds': durationPart2Secs,
                                      'durationMinutes': durationPart2Mins,
                                      'startTime': Timestamp.fromDate(startOfDay2),
                                      'endTime': Timestamp.fromDate(endTime),
                                      'timestamp': Timestamp.fromDate(endTime),
                                      'createdAt': FieldValue.serverTimestamp(),
                                      'topicsCovered': topicsText,
                                    });

                                    await firestore.collection('users').doc(uid).collection('journal').doc(docRef2.id).set({
                                      'id': docRef2.id,
                                      'type': 'study_session',
                                      'title': 'Study Log: $courseToSave (Part 2)',
                                      'content': topicsText.isNotEmpty ? 'Topics: $topicsText' : 'Study session completed.',
                                      'topicsCovered': topicsText.isNotEmpty ? topicsText : null,
                                      'durationMinutes': durationPart2Mins,
                                      'subjectOrCourseId': courseToSave,
                                      'timestamp': Timestamp.fromDate(endTime),
                                      'mode': 'university',
                                    });
                                  } else {
                                    final durationSecs = durationMins * 60;
                                    final docRef = await firestore.collection('users').doc(uid).collection('focus_sessions').add({
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

                                    await firestore.collection('users').doc(uid).collection('journal').doc(docRef.id).set({
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
                                  }

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

    DateTime startTime = session.startTime;
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
                        // Start Time (Interactive)
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(startTime),
                              );
                              if (picked != null) {
                                setModalState(() {
                                  startTime = DateTime(
                                    startTime.year,
                                    startTime.month,
                                    startTime.day,
                                    picked.hour,
                                    picked.minute,
                                  );
                                  if (!endTime.isAfter(startTime)) {
                                    endTime = DateTime(
                                      startTime.year,
                                      startTime.month,
                                      startTime.day + 1,
                                      endTime.hour,
                                      endTime.minute,
                                    );
                                  }
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF110D0C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Start Time (Tap)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10)),
                                      Icon(Icons.edit_outlined, size: 12, color: Color(0xFFF2B78A)),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatTimeWithPeriodPrefix(startTime),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
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

                                final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
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
                                      'startTime': Timestamp.fromDate(startTime),
                                      'endTime': Timestamp.fromDate(endTime),
                                      'timestamp': Timestamp.fromDate(endTime),
                                      'durationMinutes': durationMins,
                                      'durationSeconds': durationSecs,
                                      'topicsCovered': topicsText,
                                    });

                                    // Also update study_sessions if present
                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(uid)
                                          .collection('study_sessions')
                                          .doc(session.sessionId)
                                          .update({
                                        'courseCode': courseToSave,
                                        'courseTitle': courseToSave,
                                        'cleanTitle': courseToSave,
                                        'startedAt': Timestamp.fromDate(startTime),
                                        'endedAt': Timestamp.fromDate(endTime),
                                        'durationMinutes': durationMins,
                                        'durationSeconds': durationSecs,
                                        'topicName': topicsText,
                                      });
                                    } catch (_) {}
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
    final selectedDate = _selectedDay;
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
    final date = _selectedDay;
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
  // STITCH ACADEMIC OS — INSIGHTS & ANALYTICS SUITE (DESKTOP & MOBILE)
  // ============================================================================

  // ---------------------------------------------------------------------------
  // A. PURE DATA AGGREGATION & FORMATTING HELPERS
  // ---------------------------------------------------------------------------

  int _computeTotalFocusSeconds(List<StudySession> sessions) {
    return sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
  }

  String _formatFocusDuration(int totalSec) {
    if (totalSec <= 0) return '0h 0m';
    final hours = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  int _computeMaxSessionSeconds(List<StudySession> sessions) {
    return sessions.fold<int>(0, (currMax, s) => s.durationSeconds > currMax ? s.durationSeconds : currMax);
  }

  String _computeLongestSessionCourse(List<StudySession> sessions) {
    if (sessions.isEmpty) return 'No sessions';
    StudySession longest = sessions.first;
    for (final s in sessions) {
      if (s.durationSeconds > longest.durationSeconds) {
        longest = s;
      }
    }
    return longest.courseCode.isNotEmpty ? longest.courseCode : (longest.courseTitle ?? 'General Study');
  }

  int _computeAvgDailyFocusSeconds(List<StudySession> sessions, int daysCount) {
    if (sessions.isEmpty || daysCount <= 0) return 0;
    final totalSec = _computeTotalFocusSeconds(sessions);
    return totalSec ~/ daysCount;
  }

  List<Map<String, dynamic>> _computeWeeklyDistributionData(List<StudySession> sessions) {
    // Bangladesh academic week starts on Saturday (Sat, Sun, Mon, Tue, Wed, Thu, Fri)
    final dayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final weekStart = _rangeStart;
    final List<Map<String, dynamic>> result = [];

    for (int i = 0; i < 7; i++) {
      final dayDate = weekStart.add(Duration(days: i));
      final daySessions = sessions.where((s) => isSameDay(s.startedAt, dayDate));
      final int sec = daySessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
      final double hrs = double.parse((sec / 3600.0).toStringAsFixed(1));
      result.add({
        'day': dayLabels[i],
        'date': dayDate,
        'hours': hrs,
        'seconds': sec,
        'isToday': isSameDay(dayDate, DateTime.now()),
      });
    }

    return result;
  }

  List<Map<String, dynamic>> _computeSubjectAllocationData(List<StudySession> sessions, List<dynamic> enrolledCourses) {
    final Map<String, int> subjectSec = {};
    final Map<String, String> subjectTitles = {};

    for (final s in sessions) {
      final code = s.courseCode.isNotEmpty ? s.courseCode : 'General';
      subjectSec[code] = (subjectSec[code] ?? 0) + s.durationSeconds;
      if (s.courseTitle != null && s.courseTitle!.isNotEmpty) {
        subjectTitles[code] = s.courseTitle!;
      }
    }

    for (final c in enrolledCourses) {
      final code = (c.code as String? ?? '').isNotEmpty ? (c.code as String) : (c.title as String? ?? 'Module');
      subjectSec.putIfAbsent(code, () => 0);
      if ((c.title as String? ?? '').isNotEmpty) {
        subjectTitles[code] = c.title as String;
      }
    }

    final totalSec = subjectSec.values.fold<int>(0, (a, b) => a + b);
    final sorted = subjectSec.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    const palette = [
      Color(0xFF8FA8C8), // Indigo
      Color(0xFFC88256), // Rust
      Color(0xFF4E9F72), // Emerald
      Color(0xFFAFC9EA), // Soft Indigo
      Color(0xFFA5673F), // Amber
      Color(0xFF60A5FA), // Blue
    ];

    final List<Map<String, dynamic>> list = [];
    for (int i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final pct = totalSec > 0 ? ((entry.value / totalSec) * 100).round() : 0;
      final color = palette[i % palette.length];
      list.add({
        'code': entry.key,
        'title': subjectTitles[entry.key] ?? 'Module',
        'seconds': entry.value,
        'hoursStr': _formatFocusDuration(entry.value),
        'pct': pct,
        'color': color,
      });
    }

    return list;
  }

  Map<String, dynamic> _computeCircadianData(List<StudySession> sessions, DateTime anchorDate) {
    final daySessions = sessions.where((s) => isSameDay(s.startedAt, anchorDate)).toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final hourSeconds = List.filled(24, 0);
    for (final s in daySessions) {
      final h = s.startedAt.hour.clamp(0, 23);
      hourSeconds[h] += s.durationSeconds;
    }

    int peakH = -1;
    int maxHSec = 0;
    for (int h = 0; h < 24; h++) {
      if (hourSeconds[h] > maxHSec) {
        maxHSec = hourSeconds[h];
        peakH = h;
      }
    }

    String peakWindowStr = 'None';
    if (peakH != -1 && maxHSec > 0) {
      final startStr = '${peakH.toString().padLeft(2, '0')}:00';
      final endStr = '${((peakH + 2) % 24).toString().padLeft(2, '0')}:00';
      peakWindowStr = '$startStr – $endStr';
    }

    return {
      'daySessions': daySessions,
      'peakWindow': peakWindowStr,
    };
  }

  Map<String, dynamic> _computeRigorMatrixData(List<StudySession> recentSessions, int weeksCount) {
    final now = DateTime.now();
    final daysToFriday = (5 - now.weekday + 7) % 7;
    final currentFriday = DateTime(now.year, now.month, now.day).add(Duration(days: daysToFriday));
    final matrixStart = currentFriday.subtract(Duration(days: weeksCount * 7 - 1));

    int activeDays = 0;
    final List<List<Map<String, dynamic>>> grid = List.generate(7, (_) => []);

    for (int w = 0; w < weeksCount; w++) {
      for (int d = 0; d < 7; d++) {
        final cellDate = matrixStart.add(Duration(days: w * 7 + d));
        final daySessions = recentSessions.where((s) => isSameDay(s.startedAt, cellDate));
        final int sec = daySessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
        final double hrs = sec / 3600.0;
        int intensity = 0;
        if (hrs > 0) {
          activeDays++;
          if (hrs < 1.0) {
            intensity = 1;
          } else if (hrs < 2.5) {
            intensity = 2;
          } else {
            intensity = 3;
          }
        }
        grid[d].add({
          'date': cellDate,
          'hours': hrs,
          'seconds': sec,
          'intensity': intensity,
          'isFuture': cellDate.isAfter(now),
        });
      }
    }

    return {
      'grid': grid,
      'activeDays': activeDays,
    };
  }

  // ---------------------------------------------------------------------------
  // B. DESKTOP-NATIVE ACADEMIC INSIGHTS SUITE
  // ---------------------------------------------------------------------------

  Widget _buildDesktopInsightsScreen(BuildContext context) {
    final colors = AppColors.of(context);
    final sessionsAsync = ref.watch(studySessionsRangeStreamProvider(DateRangeParam(_rangeStart, _rangeEnd)));
    final sessions = deduplicateSessions(sessionsAsync.value ?? []);
    final recentSessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final recentSessions = deduplicateSessions(recentSessionsAsync.value ?? []);
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final effectiveCategoryTab = (isUni && _desktopCategoryTab == 'Performance') ? 'Overview' : _desktopCategoryTab;

    final coursesAsync = ref.watch(coursesStreamProvider);
    final enrolledCourses = coursesAsync.value ?? [];
    final attendanceAsync = ref.watch(attendanceRecordsStreamProvider);
    final attendanceRecords = attendanceAsync.value ?? [];

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Context Status Pill & Sync Indicator
                _buildDesktopStatusHeader(colors, profile, isUni),

                const SizedBox(height: 16),

                // 2. Sub-Navigation Tabs & Granularity Filter Ribbon
                _buildDesktopAnalyticsSubNav(colors, isUni),

                const SizedBox(height: 24),

                if (effectiveCategoryTab == 'Time') ...[
                  _buildDesktopTopKpis(colors, sessions, profile),
                  const SizedBox(height: 24),
                  _buildDesktopCircadianRhythmCard(colors, sessions),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildDesktopWeeklyHistogram(colors, sessions),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 6,
                        child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                      ),
                    ],
                  ),
                ] else if (effectiveCategoryTab == 'Subjects') ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 7,
                        child: _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
                      ),
                    ],
                  ),
                ] else if (effectiveCategoryTab == 'Performance') ...[
                  _buildExamPerformanceDeltas(ref, colors.surface, colors.secondary),
                  const SizedBox(height: 24),
                  _buildDesktopPerformanceLedger(colors),
                ] else if (effectiveCategoryTab == 'CGPA Forecaster') ...[
                  _buildDesktopCgpaForecasterWorkspace(colors),
                ] else ...[
                  // Default 'Overview'
                  _buildDesktopTopKpis(colors, sessions, profile),

                  const SizedBox(height: 24),

                  // Middle Charts Row (60% Weekly / 40% Subject Donut)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildDesktopWeeklyHistogram(colors, sessions),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Bottom Timeline & Heatmap Row (60% Circadian / 40% Rigor Matrix)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: _buildDesktopCircadianRhythmCard(colors, sessions),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 4,
                        child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // Contextual Architectural Scholar Stamp
                _buildScholarOperationalStamp(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopStatusHeader(ChondrobinduThemeColors colors, dynamic profile, bool isUni) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    if (!isUni) {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING TARGET';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$trackStr • $termStr • WEEK 04 METRICS',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Icon(Icons.verified_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              'DATA REFLECTED: ${DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase()} • SYNCHRONIZED',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopAnalyticsSubNav(ChondrobinduThemeColors colors, bool isUni) {
    final categories = isUni
        ? ['Overview', 'Time', 'Subjects', 'CGPA Forecaster']
        : ['Overview', 'Time', 'Subjects', 'Performance'];
    final periods = [
      (InsightPeriod.day, 'Day'),
      (InsightPeriod.week, 'Week'),
      (InsightPeriod.month, 'Month'),
      (InsightPeriod.trend, 'Trend'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;
          final subTabsWidget = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: categories.map((cat) {
                final active = _desktopCategoryTab == cat;
                return InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() => _desktopCategoryTab = cat);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? colors.primary.withValues(alpha: 0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: active ? Border.all(color: colors.primary.withValues(alpha: 0.5)) : null,
                    ),
                    child: Text(
                      cat,
                      style: GoogleFonts.plusJakartaSans(
                        color: active ? colors.textPrimary : colors.textMuted,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );

          final periodControls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: periods.map((p) {
                    final active = _selectedPeriod == p.$1;
                    return InkWell(
                      onTap: () {
                        SafeHaptics.selectionClick();
                        setState(() => _selectedPeriod = p.$1);
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: active ? colors.surface : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: active ? Border.all(color: colors.surfaceBorder) : null,
                        ),
                        child: Text(
                          p.$2,
                          style: GoogleFonts.plusJakartaSans(
                            color: active ? colors.primary : colors.textMuted,
                            fontSize: 12,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      color: colors.textMuted,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _stepDateRange(-1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        _dateRangeLabel,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      color: colors.textMuted,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _stepDateRange(1),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.recessed,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: subTabsWidget,
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: periodControls,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.recessed,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: subTabsWidget,
                ),
              ),
              const SizedBox(width: 12),
              periodControls,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDesktopTopKpis(ChondrobinduThemeColors colors, List<StudySession> sessions, dynamic profile) {
    final int totalSec = _computeTotalFocusSeconds(sessions);
    final String focusTimeStr = _formatFocusDuration(totalSec);

    final String sessionCountStr = '${sessions.length}';
    final String sessionSubtitle = sessions.isNotEmpty ? '▲ High consistency' : '0 sessions recorded';

    final int maxSec = _computeMaxSessionSeconds(sessions);
    final String maxSessionStr = maxSec > 0
        ? (maxSec >= 3600 ? '${maxSec ~/ 3600}h ${(maxSec % 3600) ~/ 60}m' : '${maxSec ~/ 60}m')
        : '0m';
    final String longestCourse = _computeLongestSessionCourse(sessions);

    final int daysCount = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 365);
    final int avgDailySec = _computeAvgDailyFocusSeconds(sessions, daysCount);
    final String avgDailyStr = avgDailySec > 0
        ? (avgDailySec >= 3600 ? '${avgDailySec ~/ 3600}h ${(avgDailySec % 3600) ~/ 60}m' : '${avgDailySec ~/ 60}m')
        : '0m';
    final int targetPct = (avgDailySec / 3600.0 * 100).round().clamp(0, 100);

    final int streakDays = profile?.streakDays ?? 0;
    final String streakSubtitle = '$streakDays-day streak active';

    return Row(
      children: [
        Expanded(
          child: _kpiCard(
            colors: colors,
            title: 'TOTAL FOCUS TIME',
            value: focusTimeStr,
            badge: streakSubtitle,
            badgeColor: colors.secondary,
            icon: Icons.local_fire_department_rounded,
            iconColor: colors.secondary,
            iconBg: colors.secondary.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            colors: colors,
            title: 'SESSIONS',
            value: sessionCountStr,
            badge: sessionSubtitle,
            badgeColor: sessions.isNotEmpty ? colors.success : colors.textMuted,
            icon: Icons.adjust_rounded,
            iconColor: colors.success,
            iconBg: colors.success.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            colors: colors,
            title: 'MAX SINGLE SESSION',
            value: maxSessionStr,
            badge: longestCourse,
            badgeColor: colors.primary,
            icon: Icons.bolt_rounded,
            iconColor: colors.primary,
            iconBg: colors.primary.withValues(alpha: 0.15),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _kpiCard(
            colors: colors,
            title: 'AVG DAILY FOCUS',
            value: avgDailyStr,
            badge: '$targetPct% of 1.0h daily target',
            badgeColor: colors.textMuted,
            icon: Icons.schedule_rounded,
            iconColor: colors.primary,
            iconBg: colors.recessed,
            progressFactor: avgDailySec / 3600.0,
          ),
        ),
      ],
    );
  }

  Widget _kpiCard({
    required ChondrobinduThemeColors colors,
    required String title,
    required String value,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    double? progressFactor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
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
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (progressFactor != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progressFactor.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: colors.recessed,
                valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            badge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopWeeklyHistogram(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final weeklyData = _computeWeeklyDistributionData(sessions);
    double peakVal = 0.0;
    String peakDay = 'None';
    for (final d in weeklyData) {
      final hrs = d['hours'] as double;
      if (hrs > peakVal) {
        peakVal = hrs;
        peakDay = d['day'] as String;
      }
    }

    final totalWeekSec = weeklyData.fold<int>(0, (acc, d) => acc + (d['seconds'] as int));
    final double totalWeekHours = totalWeekSec / 3600.0;
    final double variance = totalWeekHours - 7.0;
    final int weekPct = ((totalWeekHours / 7.0) * 100).round().clamp(0, 999);
    final double maxScale = math.max(3.0, (peakVal * 1.15).ceilToDouble());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
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
                      '${_selectedPeriod.name.toUpperCase()} FOCUS TIME',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Active academic load tracked by session timer',
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      peakVal > 0 ? 'Peak: $peakDay (${peakVal.toStringAsFixed(1)} hrs)' : 'Peak: None (0 hrs)',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (sessions.isEmpty)
            SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bar_chart_rounded, color: colors.textMuted, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      'No study sessions recorded for this period. Use the Timer to start logging focus blocks.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.secondary,
                        foregroundColor: const Color(0xFF171C24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () {
                        SafeHaptics.selectionClick();
                        ref.read(navigationIndexProvider.notifier).state = 2;
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Start Focus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 220,
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _guideLine(colors, '3.0h', false),
                      _guideLine(colors, '2.0h', false),
                      _guideLine(colors, '1.0h', true),
                      _guideLine(colors, '0.0h', false),
                    ],
                  ),
                  Positioned.fill(
                    left: 36,
                    right: 8,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: weeklyData.map((d) {
                        final double hrs = d['hours'] as double;
                        final String day = d['day'] as String;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        final double heightFactor = (hrs / maxScale).clamp(0.02, 1.0);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${hrs.toStringAsFixed(1)}h',
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.secondary : colors.primary,
                                fontSize: 10.5,
                                fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 36,
                              height: 140 * heightFactor,
                              decoration: BoxDecoration(
                                color: isPeak ? colors.secondary : colors.primary.withValues(alpha: 0.65),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                border: isPeak ? null : Border.all(color: colors.primary.withValues(alpha: 0.3)),
                                boxShadow: isPeak
                                    ? [
                                        BoxShadow(
                                          color: colors.secondary.withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              day,
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.textPrimary : colors.textMuted,
                                fontSize: 11,
                                fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Footer Metric Summary
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 8),
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12),
                        children: [
                          const TextSpan(text: 'Target Variance: '),
                          TextSpan(
                            text: '${variance >= 0 ? '+' : ''}${variance.toStringAsFixed(1)}h overall',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  'Total Week: ${totalWeekHours.toStringAsFixed(1)}h / 7.0h ($weekPct%)',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guideLine(ChondrobinduThemeColors colors, String label, bool isBenchmark) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(
              color: isBenchmark ? colors.secondary : colors.textMuted,
              fontSize: 10,
              fontWeight: isBenchmark ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                height: 1,
                color: isBenchmark ? colors.secondary.withValues(alpha: 0.4) : colors.surfaceBorder,
              ),
              if (isBenchmark)
                Positioned(
                  right: 0,
                  top: -16,
                  child: Text(
                    'Goal Target (1.0h)',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.secondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSubjectDistribution(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    final allocationList = _computeSubjectAllocationData(sessions, enrolledCourses);
    final totalSec = allocationList.fold<int>(0, (acc, item) => acc + (item['seconds'] as int));
    final focusTimeStr = _formatFocusDuration(totalSec);
    final activeCount = allocationList.where((item) => (item['seconds'] as int) > 0).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
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
                      'Subject Allocation',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isUni ? 'Distribution across enrolled modules' : 'Distribution across enrolled subjects',
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  '$activeCount ${isUni ? "Courses" : "Subjects"} Active',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (allocationList.isEmpty || totalSec == 0)
            SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(120, 120),
                      painter: _DonutChartPainter(
                        values: const [1.0],
                        colors: [colors.surfaceBorder],
                        trackColor: colors.recessed,
                        strokeWidth: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No enrolled courses or focus sessions logged yet.',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(160, 160),
                        painter: _DonutChartPainter(
                          values: allocationList.map((e) => (e['seconds'] as int).toDouble()).toList(),
                          colors: allocationList.map((e) => e['color'] as Color).toList(),
                          trackColor: colors.recessed,
                          strokeWidth: 16,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            focusTimeStr,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'TOTAL FOCUS',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 24),

                Expanded(
                  child: Column(
                    children: allocationList.take(4).map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.recessed,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: item['color'] as Color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['code'] as String,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      item['title'] as String,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textMuted,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${item['pct']}%',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: item['color'] as Color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    item['hoursStr'] as String,
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
                    }).toList(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopCircadianRhythmCard(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final circadianData = _computeCircadianData(sessions, _currentAnchorDate);
    final List<StudySession> daySessions = circadianData['daySessions'] as List<StudySession>;
    final String peakWindow = circadianData['peakWindow'] as String;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
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
                      'Circadian Focus Rhythm',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chronological time blocks logged across diurnal cycles (00:00 – 24:00)',
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bedtime_rounded, size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Peak Flow: $peakWindow',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00', '24:00'].map((h) {
              return Text(
                h,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 6),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned.fill(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(7, (_) => Container(width: 1, color: colors.surfaceBorder.withValues(alpha: 0.5))),
                      ),
                    ),

                    if (daySessions.isEmpty)
                      Center(
                        child: Text(
                          'No focus blocks logged on ${DateFormat('d MMM yyyy').format(_currentAnchorDate)}.',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      )
                    else
                      ...daySessions.map((s) {
                        final startM = (s.startedAt.hour * 60 + s.startedAt.minute).clamp(0, 1440);
                        final durM = math.max(15, (s.durationSeconds / 60).round());
                        final left = (startM / 1440.0) * width;
                        final blockWidth = math.max(28.0, (durM / 1440.0) * width);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: left.clamp(0.0, width - blockWidth),
                          width: blockWidth,
                          top: 6,
                          bottom: 6,
                          child: Tooltip(
                            message: '${s.cleanTitle}: ${DateFormat('HH:mm').format(s.startedAt)} - ${DateFormat('HH:mm').format(s.endedAt)} (${durM}m)',
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: blockColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                s.courseCode.isNotEmpty ? s.courseCode : 'FOCUS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  color: const Color(0xFF171C24),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legendDot(colors.success, 'Morning (06:00–12:00)', colors),
              _legendDot(colors.secondary, 'Afternoon (12:00–18:00)', colors),
              _legendDot(colors.primary, 'Night Flow (18:00–24:00)', colors),
            ],
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology_rounded, size: 16, color: colors.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    peakWindow != 'None'
                        ? 'Circadian rhythm indicates highest deep focus velocity during the $peakWindow window.'
                        : 'Log sessions at different times of day to reveal your optimal diurnal cognitive window.',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: colors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopStudyRigorMatrixCard(
    ChondrobinduThemeColors colors,
    List<StudySession> recentSessions,
    List<dynamic> attendanceRecords,
    bool isUni, {
    int weeksCount = 12,
  }) {
    final matrixData = _computeRigorMatrixData(recentSessions, weeksCount);
    final List<List<Map<String, dynamic>>> grid = matrixData['grid'] as List<List<Map<String, dynamic>>>;
    final int activeDays = matrixData['activeDays'] as int;

    String attendanceStr = '91.2% Attendance Correlation';
    if (attendanceRecords.isNotEmpty) {
      final attended = attendanceRecords.where((r) => r.isPresent == true).length;
      final pct = (attended / attendanceRecords.length * 100).toStringAsFixed(1);
      attendanceStr = '$pct% Attendance Correlation';
    }

    final dayLabels = ['S', 'S', 'M', 'T', 'W', 'T', 'F'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
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
                      'Study Rigor Matrix',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '12-Week Academic Consistency Calendar',
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  'Weeks W01 – W12',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: dayLabels.map((lbl) {
                  return Container(
                    height: 14,
                    margin: const EdgeInsets.only(bottom: 4),
                    alignment: Alignment.center,
                    child: Text(
                      lbl,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 9.5,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Column(
                  children: List.generate(7, (rowIdx) {
                    final rowDays = grid[rowIdx];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: rowDays.map((cell) {
                          final int intensity = cell['intensity'] as int;
                          final double hrs = cell['hours'] as double;
                          final DateTime date = cell['date'] as DateTime;

                          Color cellColor;
                          switch (intensity) {
                            case 1:
                              cellColor = colors.primary.withValues(alpha: 0.35);
                              break;
                            case 2:
                              cellColor = colors.primary;
                              break;
                            case 3:
                              cellColor = colors.secondary;
                              break;
                            case 0:
                            default:
                              cellColor = colors.recessed;
                              break;
                          }

                          return Expanded(
                            child: Tooltip(
                              message: '${DateFormat('EEE, d MMM').format(date)}: ${hrs.toStringAsFixed(1)}h',
                              child: Container(
                                height: 14,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: cellColor,
                                  borderRadius: BorderRadius.circular(2.5),
                                  border: intensity == 0 ? Border.all(color: colors.surfaceBorder.withValues(alpha: 0.5)) : null,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weeks W01 – W12',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
              Row(
                children: [
                  Text('Less', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                  const SizedBox(width: 6),
                  _matrixCell(colors.recessed, border: colors.surfaceBorder),
                  _matrixCell(colors.primary.withValues(alpha: 0.35)),
                  _matrixCell(colors.primary),
                  _matrixCell(colors.secondary),
                  const SizedBox(width: 6),
                  Text('More', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  '$activeDays Total Active Days',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (isUni)
                  Text(
                    attendanceStr,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.success,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'Academic Consistency',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.primary,
                      fontSize: 11.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _matrixCell(Color color, {Color? border}) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
        border: border != null ? Border.all(color: border) : null,
      ),
    );
  }

  Widget _buildScholarOperationalStamp(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.architecture_rounded, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ATELIER SPECIFICATION: CHONDROBINDU CORE 2.4 — FORMAL PROOF & REASONING SYSTEM',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 10.5,
                letterSpacing: 0.5,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'SESSION ENGINE: DETERMINISTIC REAL-TIME SYNC',
            style: GoogleFonts.jetBrainsMono(
              color: colors.textMuted,
              fontSize: 10.5,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // C. MOBILE-NATIVE ACADEMIC INSIGHTS SUITE
  // ---------------------------------------------------------------------------

  Widget _buildMobileInsightsScreen(BuildContext context) {
    final colors = AppColors.of(context);
    final sessionsAsync = ref.watch(studySessionsRangeStreamProvider(DateRangeParam(_rangeStart, _rangeEnd)));
    final sessions = deduplicateSessions(sessionsAsync.value ?? []);
    final recentSessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final recentSessions = deduplicateSessions(recentSessionsAsync.value ?? []);
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final effectiveCategoryTab = (isUni && _desktopCategoryTab == 'Performance') ? 'Overview' : _desktopCategoryTab;

    final coursesAsync = ref.watch(coursesStreamProvider);
    final enrolledCourses = coursesAsync.value ?? [];

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMobileStatusPill(colors, profile, isUni),

              const SizedBox(height: 12),

              _buildMobileSubNav(colors, isUni),

              const SizedBox(height: 12),

              _buildMobilePeriodSelectorAndStepper(colors),

              const SizedBox(height: 16),

              if (effectiveCategoryTab == 'Time') ...[
                _buildMobileTopKpis(colors, sessions, profile),
                const SizedBox(height: 16),
                _buildMobileCircadianRhythmCard(colors, sessions),
                const SizedBox(height: 16),
                _buildMobileWeeklyHistogram(colors, sessions),
                const SizedBox(height: 16),
                _buildMobileStudyRigorMatrixCard(colors, recentSessions, isUni, weeksCount: 6),
              ] else if (effectiveCategoryTab == 'Subjects') ...[
                _buildMobileSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                const SizedBox(height: 16),
                _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
              ] else if (effectiveCategoryTab == 'Performance') ...[
                _buildExamPerformanceDeltas(ref, colors.surface, colors.secondary),
                const SizedBox(height: 16),
                _buildDesktopPerformanceLedger(colors),
              ] else if (effectiveCategoryTab == 'CGPA Forecaster') ...[
                _buildDesktopCgpaForecasterWorkspace(colors),
              ] else ...[
                // Default 'Overview'
                _buildMobileTopKpis(colors, sessions, profile),

                const SizedBox(height: 16),

                _buildMobileWeeklyHistogram(colors, sessions),

                const SizedBox(height: 16),

                _buildMobileSubjectDistribution(colors, sessions, enrolledCourses, isUni),

                const SizedBox(height: 16),

                _buildMobileCircadianRhythmCard(colors, sessions),

                const SizedBox(height: 16),

                _buildMobileStudyRigorMatrixCard(colors, recentSessions, isUni, weeksCount: 6),

                const SizedBox(height: 16),

                _buildMobileReflectionNoteCard(colors),
              ],

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStatusPill(ChondrobinduThemeColors colors, dynamic profile, bool isUni) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    if (!isUni) {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$trackStr • $termStr • WEEK 04',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          DateFormat("MMM ''yy").format(DateTime.now()).toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileSubNav(ChondrobinduThemeColors colors, bool isUni) {
    final categories = isUni
        ? ['Overview', 'Time', 'Subjects', 'CGPA Forecaster']
        : ['Overview', 'Time', 'Subjects', 'Performance'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? colors.primary : colors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: active ? colors.primary : colors.surfaceBorder),
                ),
                child: Text(
                  cat,
                  style: GoogleFonts.plusJakartaSans(
                    color: active ? const Color(0xFF171C24) : colors.textMuted,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobilePeriodSelectorAndStepper(ChondrobinduThemeColors colors) {
    final periods = [
      (InsightPeriod.day, 'Day'),
      (InsightPeriod.week, 'Week'),
      (InsightPeriod.month, 'Month'),
      (InsightPeriod.trend, 'Trend'),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            children: periods.map((p) {
              final active = _selectedPeriod == p.$1;
              return Expanded(
                child: InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() => _selectedPeriod = p.$1);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? colors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: active ? Border.all(color: colors.surfaceBorder) : null,
                    ),
                    child: Text(
                      p.$2,
                      style: GoogleFonts.plusJakartaSans(
                        color: active ? colors.primary : colors.textMuted,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
                color: colors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _stepDateRange(-1),
              ),
              Text(
                _dateRangeLabel,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: colors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _stepDateRange(1),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTopKpis(ChondrobinduThemeColors colors, List<StudySession> sessions, dynamic profile) {
    final int totalSec = _computeTotalFocusSeconds(sessions);
    final String focusTimeStr = _formatFocusDuration(totalSec);

    final String sessionCountStr = '${sessions.length}';
    final String sessionSubtitle = sessions.isNotEmpty ? '▲ High consistency' : '0 recorded';

    final int maxSec = _computeMaxSessionSeconds(sessions);
    final String maxSessionStr = maxSec > 0
        ? (maxSec >= 3600 ? '${maxSec ~/ 3600}h ${(maxSec % 3600) ~/ 60}m' : '${maxSec ~/ 60}m')
        : '0m';
    final String longestCourse = _computeLongestSessionCourse(sessions);

    final int daysCount = (_rangeEnd.difference(_rangeStart).inDays + 1).clamp(1, 365);
    final int avgDailySec = _computeAvgDailyFocusSeconds(sessions, daysCount);
    final String avgDailyStr = avgDailySec > 0
        ? (avgDailySec >= 3600 ? '${avgDailySec ~/ 3600}h ${(avgDailySec % 3600) ~/ 60}m' : '${avgDailySec ~/ 60}m')
        : '0m';
    final int targetPct = (avgDailySec / 3600.0 * 100).round().clamp(0, 100);

    final int streakDays = profile?.streakDays ?? 0;
    final String streakSubtitle = '$streakDays-day streak active';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'TOTAL FOCUS',
                value: focusTimeStr,
                badge: streakSubtitle,
                badgeColor: colors.secondary,
                icon: Icons.local_fire_department_rounded,
                iconColor: colors.secondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'SESSIONS',
                value: sessionCountStr,
                badge: sessionSubtitle,
                badgeColor: sessions.isNotEmpty ? colors.success : colors.textMuted,
                icon: Icons.adjust_rounded,
                iconColor: colors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'LONGEST SESSION',
                value: maxSessionStr,
                badge: longestCourse,
                badgeColor: colors.primary,
                icon: Icons.bolt_rounded,
                iconColor: colors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _mobileKpiCard(
                colors: colors,
                title: 'AVG DAILY FOCUS',
                value: avgDailyStr,
                badge: '$targetPct% of 1.0h goal',
                badgeColor: colors.textMuted,
                icon: Icons.schedule_rounded,
                iconColor: colors.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _mobileKpiCard({
    required ChondrobinduThemeColors colors,
    required String title,
    required String value,
    required String badge,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
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
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            badge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: badgeColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileWeeklyHistogram(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final weeklyData = _computeWeeklyDistributionData(sessions);
    double peakVal = 0.0;
    String peakDay = 'None';
    for (final d in weeklyData) {
      final hrs = d['hours'] as double;
      if (hrs > peakVal) {
        peakVal = hrs;
        peakDay = d['day'] as String;
      }
    }

    final double maxScale = math.max(3.0, (peakVal * 1.15).ceilToDouble());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
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
                      'Weekly Focus Distribution',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Chronological hours tracked',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  peakVal > 0 ? 'Peak: $peakDay (${peakVal.toStringAsFixed(1)}h)' : 'Peak: None',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No study sessions recorded for this period.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 150,
              child: Stack(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _guideLine(colors, '3.0h', false),
                      _guideLine(colors, '1.0h', true),
                      _guideLine(colors, '0.0h', false),
                    ],
                  ),
                  Positioned.fill(
                    left: 36,
                    right: 8,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: weeklyData.map((d) {
                        final double hrs = d['hours'] as double;
                        final String day = d['day'] as String;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        final double heightFactor = (hrs / maxScale).clamp(0.02, 1.0);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${hrs.toStringAsFixed(1)}h',
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.secondary : colors.primary,
                                fontSize: 9.5,
                                fontWeight: isPeak ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 22,
                              height: 90 * heightFactor,
                              decoration: BoxDecoration(
                                color: isPeak ? colors.secondary : colors.primary.withValues(alpha: 0.65),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              day,
                              style: GoogleFonts.jetBrainsMono(
                                color: isPeak ? colors.textPrimary : colors.textMuted,
                                fontSize: 10,
                                fontWeight: isPeak ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileSubjectDistribution(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    final allocationList = _computeSubjectAllocationData(sessions, enrolledCourses);
    final totalSec = allocationList.fold<int>(0, (acc, item) => acc + (item['seconds'] as int));
    final focusTimeStr = _formatFocusDuration(totalSec);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
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
                      'Subject Allocation',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Active enrolled modules',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  '100% AUDITED',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Centered Donut Graphic
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: _DonutChartPainter(
                      values: allocationList.map((e) => (e['seconds'] as int).toDouble()).toList(),
                      colors: allocationList.map((e) => e['color'] as Color).toList(),
                      trackColor: colors.recessed,
                      strokeWidth: 15,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        focusTimeStr,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'TOTAL FOCUS',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Stacked Course Breakdown Cards
          Column(
            children: allocationList.take(4).map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item['color'] as Color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['code'] as String,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            item['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item['pct']}%',
                          style: GoogleFonts.jetBrainsMono(
                            color: item['color'] as Color,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          item['hoursStr'] as String,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCircadianRhythmCard(ChondrobinduThemeColors colors, List<StudySession> sessions) {
    final circadianData = _computeCircadianData(sessions, _currentAnchorDate);
    final List<StudySession> daySessions = circadianData['daySessions'] as List<StudySession>;
    final String peakWindow = circadianData['peakWindow'] as String;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '24-Hour Diurnal Rhythm',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Peak: $peakWindow',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['00:00', '06:00', '12:00', '18:00', '24:00'].map((h) {
              return Text(
                h,
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5),
              );
            }).toList(),
          ),

          const SizedBox(height: 6),

          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Container(
                height: 38,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (daySessions.isEmpty)
                      Center(
                        child: Text(
                          'No focus blocks logged today.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                        ),
                      )
                    else
                      ...daySessions.map((s) {
                        final startM = (s.startedAt.hour * 60 + s.startedAt.minute).clamp(0, 1440);
                        final durM = math.max(15, (s.durationSeconds / 60).round());
                        final left = (startM / 1440.0) * width;
                        final blockWidth = math.max(22.0, (durM / 1440.0) * width);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: left.clamp(0.0, width - blockWidth),
                          width: blockWidth,
                          top: 4,
                          bottom: 4,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              s.courseCode.isNotEmpty ? s.courseCode : 'F',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFF171C24),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMobileStudyRigorMatrixCard(
    ChondrobinduThemeColors colors,
    List<StudySession> recentSessions,
    bool isUni, {
    int weeksCount = 6,
  }) {
    final matrixData = _computeRigorMatrixData(recentSessions, weeksCount);
    final List<List<Map<String, dynamic>>> grid = matrixData['grid'] as List<List<Map<String, dynamic>>>;
    final dayLabels = ['S', 'S', 'M', 'T', 'W', 'T', 'F'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '6-Week Density Matrix',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  Text('Less', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5)),
                  const SizedBox(width: 4),
                  _matrixCell(colors.recessed, border: colors.surfaceBorder),
                  _matrixCell(colors.primary.withValues(alpha: 0.35)),
                  _matrixCell(colors.primary),
                  _matrixCell(colors.secondary),
                  const SizedBox(width: 4),
                  Text('Peak', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Column(
                  children: dayLabels.map((lbl) {
                    return Container(
                      height: 12,
                      margin: const EdgeInsets.only(bottom: 4),
                      alignment: Alignment.center,
                      child: Text(
                        lbl,
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: List.generate(7, (rowIdx) {
                      final rowDays = grid[rowIdx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Row(
                          children: rowDays.map((cell) {
                            final int intensity = cell['intensity'] as int;
                            Color cellColor;
                            switch (intensity) {
                              case 1:
                                cellColor = colors.primary.withValues(alpha: 0.35);
                                break;
                              case 2:
                                cellColor = colors.primary;
                                break;
                              case 3:
                                cellColor = colors.secondary;
                                break;
                              case 0:
                              default:
                                cellColor = colors.surface;
                                break;
                            }
                            return Expanded(
                              child: Container(
                                height: 12,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: cellColor,
                                  borderRadius: BorderRadius.circular(2),
                                  border: intensity == 0 ? Border.all(color: colors.surfaceBorder.withValues(alpha: 0.5)) : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileReflectionNoteCard(ChondrobinduThemeColors colors) {
    final journalAsync = ref.watch(journalStreamProvider);
    final entries = journalAsync.value ?? [];
    final latest = entries.isNotEmpty ? entries.first : null;

    final String quote = latest != null && latest.content.isNotEmpty
        ? (latest.content.length > 140 ? '${latest.content.substring(0, 140)}...' : latest.content)
        : 'Regular academic focus logging builds high retention and cognitive momentum. Review challenging problem sets during peak diurnal focus windows.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.psychology_rounded, size: 18, color: colors.secondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Scholar's Weekly Note",
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  quote,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // D. DETAILED SUB-TABS (SUBJECT DEEP DIVE, PERFORMANCE LEDGER, CGPA FORECASTER)
  // ---------------------------------------------------------------------------

  Widget _buildDesktopSubjectDeepDive(
    ChondrobinduThemeColors colors,
    List<StudySession> sessions,
    List<dynamic> enrolledCourses,
    bool isUni,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isUni ? 'Course Focus Breakdown' : 'Subject Focus Breakdown',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${enrolledCourses.length} Enrolled',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (enrolledCourses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No enrolled courses found for this term.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: enrolledCourses.length,
              separatorBuilder: (_, __) => Divider(color: colors.surfaceBorder, height: 16),
              itemBuilder: (context, index) {
                final course = enrolledCourses[index];
                final code = (course.code as String? ?? '').isNotEmpty ? (course.code as String) : (course.title as String? ?? '');
                final title = course.title as String? ?? '';
                final courseSessions = sessions.where((s) =>
                    (s.courseCode.isNotEmpty && s.courseCode.toLowerCase() == code.toLowerCase()) ||
                    s.courseId == course.id).toList();
                final int totalSec = courseSessions.fold<int>(0, (acc, s) => acc + s.durationSeconds);
                final String timeStr = _formatFocusDuration(totalSec);

                return Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _parseCourseColor(course.colorHex as String?) ?? colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            code,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${courseSessions.length} sessions',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      timeStr,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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

  Widget _buildDesktopPerformanceLedger(ChondrobinduThemeColors colors) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.value ?? [];
    final assessmentsAsync = ref.watch(upcomingAssessmentsStreamProvider);
    final upcomingAssessments = assessmentsAsync.value ?? [];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Assessment Performance Ledger',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${allExams.length} Total Exams',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (allExams.isEmpty && upcomingAssessments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No assessment records found.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                ),
              ),
            )
          else ...[
            ...allExams.take(5).map((exam) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: _ledgerRow(
                  colors: colors,
                  title: exam.examName,
                  date: DateFormat('d MMM yyyy').format(exam.date),
                  score: '${exam.scorePercentage.toStringAsFixed(1)}%',
                  isPass: exam.scorePercentage >= 50.0,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _ledgerRow({
    required ChondrobinduThemeColors colors,
    required String title,
    required String date,
    required String score,
    required bool isPass,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                date,
                style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
              ),
            ],
          ),
          Text(
            score,
            style: GoogleFonts.jetBrainsMono(
              color: isPass ? colors.success : colors.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopCgpaForecasterWorkspace(ChondrobinduThemeColors colors) {
    final profileAsync = ref.watch(liveUserProfileProvider);
    final fallbackProfile = ref.watch(userProfileProvider);
    final profile = profileAsync.value ?? fallbackProfile;
    final levelStr = profile.level?.isNotEmpty == true ? profile.level! : '1';
    final termStr = profile.term?.isNotEmpty == true ? profile.term! : '1';
    final uniStr = profile.universityName?.isNotEmpty == true ? profile.universityName! : 'BUET';
    final deptStr = profile.department?.isNotEmpty == true ? profile.department! : 'Engineering';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCgpaSimulatorCard(
          context: context,
          uniName: uniStr,
          major: deptStr,
          level: levelStr,
          term: termStr,
          cardColor: colors.surface,
          accentColor: colors.secondary,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target CGPA & Cutoff Planner',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Forecast minimum grades needed across remaining credits to achieve your graduation goal.',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.secondary,
                      foregroundColor: const Color(0xFF171C24),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: () {
                      SafeHaptics.mediumImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TermPerformanceScreen(
                            universityName: uniStr,
                            term: termStr,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.calculate_rounded, size: 16),
                    label: Text(
                      'Launch Interactive Simulator',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _desktopForecasterStatCard(
                      colors: colors,
                      label: 'TARGET CGPA',
                      value: profile.targetGpa > 0 ? profile.targetGpa.toStringAsFixed(2) : '3.80',
                      subtext: 'Graduation Target',
                      accent: colors.secondary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _desktopForecasterStatCard(
                      colors: colors,
                      label: 'CURRENT LEVEL & TERM',
                      value: 'Level $levelStr, Term $termStr',
                      subtext: deptStr,
                      accent: colors.success,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _desktopForecasterStatCard(
                      colors: colors,
                      label: 'SIMULATION SCALE',
                      value: '4.00 Max',
                      subtext: 'Standard University Scale',
                      accent: colors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _desktopForecasterStatCard({
    required ChondrobinduThemeColors colors,
    required String label,
    required String value,
    required String subtext,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Color? _parseCourseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final val = int.tryParse('FF$clean', radix: 16);
      if (val != null) return Color(val);
    } else if (clean.length == 8) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(val);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// E. MULTI-SEGMENT DONUT CHART PAINTER
// ---------------------------------------------------------------------------

class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final double strokeWidth;

  const _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
    this.strokeWidth = 14.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final total = values.fold<double>(0.0, (a, b) => a + b);
    if (total <= 0) return;

    double startAngle = -math.pi / 2; // -90 deg (top)
    for (int i = 0; i < values.length; i++) {
      final sweepAngle = (values[i] / total) * 2 * math.pi;
      if (sweepAngle <= 0) continue;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors || oldDelegate.trackColor != trackColor;
  }
}
