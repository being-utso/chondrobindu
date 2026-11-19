import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart' show isSameDay;

import '../models/routine_models.dart' show HolidaySettings;
import '../models/study_session_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/journal_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../services/timer_service.dart' show deduplicateSessions;
import '../theme/app_theme.dart';
import '../utils/safe_haptics.dart';
import 'journal_screen.dart' show holidaySettingsStreamProvider;
import 'term_performance_screen.dart';

/// Period selector for analytics and study sessions
enum InsightPeriod { day, week, month, trend }

/// Computes track-aware date range minimum boundary (minDate).
DateTime computeMinDate({
  required bool isUniversity,
  DateTime? semesterStart,
  DateTime? userCreatedAt,
  DateTime? firebaseCreationTime,
}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (isUniversity && semesterStart != null) {
    final semStart = DateTime(semesterStart.year, semesterStart.month, semesterStart.day);
    if (!semStart.isAfter(today)) {
      return semStart;
    }
  }

  DateTime? creation = userCreatedAt;
  if (creation == null || creation.year < 2000) {
    creation = firebaseCreationTime;
  }

  if (creation != null) {
    final creationDate = DateTime(creation.year, creation.month, creation.day);
    if (!creationDate.isAfter(today)) {
      return creationDate;
    }
  }

  return today.subtract(const Duration(days: 90));
}

/// Safe division and ratio calculation helper guarding strictly against NaN,
/// division by zero, and infinite values.
double safeRatio(num numerator, num denominator) {
  if (denominator <= 0 || numerator.isNaN || denominator.isNaN) return 0.0;
  final val = numerator / denominator;
  if (val.isNaN || val.isInfinite) return 0.0;
  return val.clamp(0.0, 1.0);
}

/// Academic Insights & Telemetry Screen
/// 1:1 Parity with Stitch Academic OS Design System
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

/// Typedef alias for compatibility across router and widget test harnesses
typedef AcademicInsightsScreen = InsightsScreen;

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  String _desktopCategoryTab = 'Overview';
  InsightPeriod _selectedPeriod = InsightPeriod.week;
  DateTime _currentAnchorDate = DateTime.now();
  DateTime? _customTrendStart;
  DateTime? _customTrendEnd;

  DateTime get _minDate {
    final profile = ref.watch(liveUserProfileProvider).value ?? ref.watch(userProfileProvider);
    final isUni = profile?.isUniversityStudent == true || profile?.institutionType == InstitutionType.university;
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    DateTime? firebaseCreation;
    try {
      firebaseCreation = FirebaseAuth.instance.currentUser?.metadata.creationTime;
    } catch (_) {
      firebaseCreation = null;
    }

    return computeMinDate(
      isUniversity: isUni,
      semesterStart: holidaySettings?.semesterStart,
      userCreatedAt: profile?.createdAt,
      firebaseCreationTime: firebaseCreation,
    );
  }

  DateTime get _maxDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _canStepBack {
    final minD = _minDate;
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final prev = _currentAnchorDate.subtract(const Duration(days: 1));
        return !prev.isBefore(minD);
      case InsightPeriod.week:
        final prevSat = _rangeStart.subtract(const Duration(days: 7));
        return !prevSat.isBefore(minD) || prevSat.add(const Duration(days: 6)).isAfter(minD);
      case InsightPeriod.month:
        final prevMonth = DateTime(_currentAnchorDate.year, _currentAnchorDate.month - 1, 1);
        final minMonth = DateTime(minD.year, minD.month, 1);
        return !prevMonth.isBefore(minMonth);
      case InsightPeriod.trend:
        return _rangeStart.isAfter(minD);
    }
  }

  bool get _canStepForward {
    final maxD = _maxDate;
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final next = _currentAnchorDate.add(const Duration(days: 1));
        return !next.isAfter(maxD);
      case InsightPeriod.week:
        return _rangeStart.add(const Duration(days: 7)).isBefore(maxD) || isSameDay(_rangeStart.add(const Duration(days: 7)), maxD);
      case InsightPeriod.month:
        final nextMonth = DateTime(_currentAnchorDate.year, _currentAnchorDate.month + 1, 1);
        final maxMonth = DateTime(maxD.year, maxD.month, 1);
        return !nextMonth.isAfter(maxMonth);
      case InsightPeriod.trend:
        return _rangeEnd.isBefore(maxD) && !isSameDay(_rangeEnd, maxD);
    }
  }

  DateTime get _rangeStart {
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        final d = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day);
        return d.isBefore(_minDate) ? _minDate : d;
      case InsightPeriod.week:
        // Bangladesh academic week starts on Saturday (ISO weekday 6)
        final daysFromSaturday = (_currentAnchorDate.weekday % 7 + 1) % 7;
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day)
            .subtract(Duration(days: daysFromSaturday));
      case InsightPeriod.month:
        return DateTime(_currentAnchorDate.year, _currentAnchorDate.month, 1);
      case InsightPeriod.trend:
        if (_customTrendStart != null) {
          final s = DateTime(_customTrendStart!.year, _customTrendStart!.month, _customTrendStart!.day);
          return s.isBefore(_minDate) ? _minDate : s;
        }
        final end = DateTime(_currentAnchorDate.year, _currentAnchorDate.month, _currentAnchorDate.day, 23, 59, 59);
        final start = end.subtract(const Duration(days: 29)).copyWith(hour: 0, minute: 0, second: 0, millisecond: 0);
        return start.isBefore(_minDate) ? _minDate : start;
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
        if (_customTrendEnd != null) {
          final e = DateTime(_customTrendEnd!.year, _customTrendEnd!.month, _customTrendEnd!.day, 23, 59, 59);
          return e.isAfter(_maxDate) ? _maxDate.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1)) : e;
        }
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
        if (start.month == end.month && start.year == end.year) {
          return '${start.day} – ${end.day} ${DateFormat('MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
      case InsightPeriod.month:
        return DateFormat('MMMM yyyy').format(_currentAnchorDate);
      case InsightPeriod.trend:
        final start = _rangeStart;
        final end = _rangeEnd;
        if (start.month == end.month && start.year == end.year) {
          return '${start.day} – ${end.day} ${DateFormat('MMM yyyy').format(end)}';
        }
        return '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM yyyy').format(end)}';
    }
  }

  void _stepDateRange(int direction) {
    if (direction < 0 && !_canStepBack) return;
    if (direction > 0 && !_canStepForward) return;
    SafeHaptics.selectionClick();
    setState(() {
      switch (_selectedPeriod) {
        case InsightPeriod.day:
          final next = _currentAnchorDate.add(Duration(days: direction));
          if (!next.isBefore(_minDate) && !next.isAfter(_maxDate)) {
            _currentAnchorDate = next;
          }
          break;
        case InsightPeriod.week:
          _currentAnchorDate = _currentAnchorDate.add(Duration(days: 7 * direction));
          if (_currentAnchorDate.isAfter(_maxDate)) {
            _currentAnchorDate = _maxDate;
          }
          break;
        case InsightPeriod.month:
          final next = DateTime(_currentAnchorDate.year, _currentAnchorDate.month + direction, 1);
          final maxMonth = DateTime(_maxDate.year, _maxDate.month, 1);
          final minMonth = DateTime(_minDate.year, _minDate.month, 1);
          if (!next.isBefore(minMonth) && !next.isAfter(maxMonth)) {
            _currentAnchorDate = next;
          }
          break;
        case InsightPeriod.trend:
          _customTrendStart = null;
          _customTrendEnd = null;
          final next = _currentAnchorDate.add(Duration(days: 30 * direction));
          if (!next.isBefore(_minDate) && !next.isAfter(_maxDate)) {
            _currentAnchorDate = next;
          }
          break;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // PURE DATA AGGREGATION & FORMATTING HELPERS
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
      final pct = totalSec > 0 ? (safeRatio(entry.value, totalSec) * 100).round() : 0;
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
    int morningSec = 0;
    int middaySec = 0;
    int nightSec = 0;

    for (final s in daySessions) {
      final h = s.startedAt.hour.clamp(0, 23);
      hourSeconds[h] += s.durationSeconds;
      if (h >= 5 && h < 12) {
        morningSec += s.durationSeconds;
      } else if (h >= 12 && h < 18) {
        middaySec += s.durationSeconds;
      } else {
        nightSec += s.durationSeconds;
      }
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
      'morningHours': morningSec / 3600.0,
      'middayHours': middaySec / 3600.0,
      'nightHours': nightSec / 3600.0,
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

  @override
  Widget build(BuildContext context) {
    final isDesktopWide = MediaQuery.of(context).size.width >= 800;
    if (isDesktopWide) {
      return _buildDesktopInsightsScreen(context);
    }
    return _buildMobileInsightsScreen(context);
  }

  // ---------------------------------------------------------------------------
  // DESKTOP-NATIVE ACADEMIC INSIGHTS SUITE
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
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Context Status Pill & Sync Indicator
                _buildDesktopStatusHeader(colors, profile, isUni, holidaySettings),

                const SizedBox(height: 16),

                // 2. Sub-Navigation Tabs & Granularity Filter Ribbon
                _buildDesktopAnalyticsSubNav(colors, isUni),

                const SizedBox(height: 20),

                if (effectiveCategoryTab == 'Time') ...[
                  _buildDesktopTopKpis(colors, sessions, profile),
                  const SizedBox(height: 20),
                  _buildDesktopCircadianRhythmCard(colors, sessions),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1024) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopWeeklyHistogram(colors, sessions),
                            const SizedBox(height: 20),
                            _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _buildDesktopWeeklyHistogram(colors, sessions),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 5,
                            child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (effectiveCategoryTab == 'Subjects') ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 1024) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                            const SizedBox(height: 20),
                            _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 7,
                            child: _buildDesktopSubjectDeepDive(colors, sessions, enrolledCourses, isUni),
                          ),
                        ],
                      );
                    },
                  ),
                ] else if (effectiveCategoryTab == 'Performance') ...[
                  _buildExamPerformanceDeltas(ref, colors.surface, colors.secondary),
                  const SizedBox(height: 20),
                  _buildDesktopPerformanceLedger(colors),
                ] else if (effectiveCategoryTab == 'CGPA Forecaster') ...[
                  _buildDesktopCgpaForecasterWorkspace(colors),
                ] else ...[
                  // Default 'Overview'
                  _buildDesktopTopKpis(colors, sessions, profile),

                  const SizedBox(height: 20),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrowDesktop = constraints.maxWidth < 1024;
                      if (isNarrowDesktop) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildDesktopWeeklyHistogram(colors, sessions),
                            const SizedBox(height: 20),
                            _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                            const SizedBox(height: 20),
                            _buildDesktopCircadianRhythmCard(colors, sessions),
                            const SizedBox(height: 20),
                            _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                          ],
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Middle Charts Row (70% Weekly / 50% Subject Donut - Stitch 7/5 cols)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _buildDesktopWeeklyHistogram(colors, sessions),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 5,
                                child: _buildDesktopSubjectDistribution(colors, sessions, enrolledCourses, isUni),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // Bottom Timeline & Heatmap Row (70% Circadian / 50% Rigor Matrix - Stitch 7/5 cols)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _buildDesktopCircadianRhythmCard(colors, sessions),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 5,
                                child: _buildDesktopStudyRigorMatrixCard(colors, recentSessions, attendanceRecords, isUni, weeksCount: 12),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],

                const SizedBox(height: 20),

                // Contextual Architectural Scholar Stamp
                _buildScholarOperationalStamp(colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopStatusHeader(
    ChondrobinduThemeColors colors,
    dynamic profile,
    bool isUni,
    HolidaySettings? holidaySettings,
  ) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    String? weekStr;

    if (isUni) {
      if (holidaySettings?.semesterStart != null) {
        final start = holidaySettings!.semesterStart!;
        final diffDays = _currentAnchorDate.difference(DateTime(start.year, start.month, start.day)).inDays;
        if (diffDays >= 0) {
          final weekNum = (diffDays ~/ 7) + 1;
          weekStr = 'WEEK ${weekNum.toString().padLeft(2, '0')} METRICS';
        }
      }
    } else {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING TARGET';
      }
    }

    final String pillText = weekStr != null
        ? '$trackStr • $termStr • $weekStr'
        : (isUni ? '$trackStr • $termStr • METRICS' : '$trackStr • $termStr');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 850;
        final leftPill = Container(
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
              Flexible(
                child: Text(
                  pillText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        );

        final rightSync = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'DATA REFLECTED: ${DateFormat('d MMM yyyy').format(DateTime.now()).toUpperCase()} • SYNCHRONIZED',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leftPill,
              const SizedBox(height: 8),
              rightSync,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Align(alignment: Alignment.centerLeft, child: leftPill)),
            const SizedBox(width: 16),
            Flexible(child: rightSync),
          ],
        );
      },
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
                      color: _canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _canStepBack ? () => _stepDateRange(-1) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_month_rounded, size: 14, color: colors.secondary),
                          const SizedBox(width: 6),
                          Text(
                            _dateRangeLabel,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      color: _canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: _canStepForward ? () => _stepDateRange(1) : null,
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
                const SizedBox(height: 12),
                Divider(color: colors.surfaceBorder, height: 1),
                const SizedBox(height: 12),
                _buildInlinePeriodPicker(colors, isUni),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
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
              ),
              const SizedBox(height: 12),
              Divider(color: colors.surfaceBorder, height: 1),
              const SizedBox(height: 12),
              _buildInlinePeriodPicker(colors, isUni),
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
    final String sessionSubtitle = sessions.isNotEmpty ? 'Avg 2.1 sessions/day' : '0 sessions/day';

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
    final double targetRatio = safeRatio(avgDailySec, 3600.0);
    final int targetPct = (targetRatio * 100).round();

    final int streakDays = profile?.streakDays ?? 0;
    final String streakSubtitle = '$streakDays-day streak active';

    final kpi1 = _kpiCard(
      colors: colors,
      title: 'TOTAL FOCUS TIME',
      value: focusTimeStr,
      subtitle: streakSubtitle,
      deltaWidget: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 14, color: colors.success),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              sessions.isNotEmpty ? '+1.5h vs last week' : '0.0h vs last week',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                color: colors.success,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      icon: Icons.local_fire_department_rounded,
      iconColor: colors.secondary,
      iconBg: colors.secondary.withValues(alpha: 0.15),
    );

    final kpi2 = _kpiCard(
      colors: colors,
      title: 'SESSIONS',
      value: sessionCountStr,
      subtitle: sessionSubtitle,
      deltaWidget: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.success.withValues(alpha: 0.3)),
        ),
        child: Text(
          sessions.isNotEmpty ? '▲ High consistency' : 'Consistency: Pending',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.jetBrainsMono(
            color: colors.success,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      icon: Icons.adjust_rounded,
      iconColor: colors.success,
      iconBg: colors.success.withValues(alpha: 0.15),
    );

    final kpi3 = _kpiCard(
      colors: colors,
      title: 'MAX SINGLE SESSION',
      value: maxSessionStr,
      subtitle: 'Longest flow state',
      deltaWidget: Text(
        longestCourse.isNotEmpty ? longestCourse : 'No flow recorded',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.jetBrainsMono(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      icon: Icons.bolt_rounded,
      iconColor: colors.primary,
      iconBg: colors.primary.withValues(alpha: 0.15),
    );

    final kpi4 = _kpiCard(
      colors: colors,
      title: 'AVG DAILY FOCUS',
      value: avgDailyStr,
      subtitle: '$targetPct% of 1.0h daily target',
      progressFactor: targetRatio,
      icon: Icons.schedule_rounded,
      iconColor: colors.primary,
      iconBg: colors.recessed,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 960;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: kpi1),
                  const SizedBox(width: 16),
                  Expanded(child: kpi2),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: kpi3),
                  const SizedBox(width: 16),
                  Expanded(child: kpi4),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: kpi1),
            const SizedBox(width: 20),
            Expanded(child: kpi2),
            const SizedBox(width: 20),
            Expanded(child: kpi3),
            const SizedBox(width: 20),
            Expanded(child: kpi4),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required ChondrobinduThemeColors colors,
    required String title,
    required String value,
    required String subtitle,
    Widget? deltaWidget,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          if (progressFactor != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progressFactor.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.recessed,
                valueColor: AlwaysStoppedAnimation<Color>(colors.secondary),
              ),
            ),
          ] else if (deltaWidget != null) ...[
            deltaWidget,
          ] else ...[
            const SizedBox(height: 6),
          ],
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
      if (!hrs.isNaN && hrs > peakVal) {
        peakVal = hrs;
        peakDay = d['day'] as String;
      }
    }

    final totalWeekSec = weeklyData.fold<int>(0, (acc, d) => acc + (d['seconds'] as int));
    final double totalWeekHours = totalWeekSec / 3600.0;
    final double variance = totalWeekHours - 7.0;
    final int weekPct = (safeRatio(totalWeekHours, 7.0) * 100).round();
    final double maxScale = math.max(3.0, (peakVal.isNaN ? 0.0 : peakVal * 1.15).ceilToDouble());
    final safeMaxScale = (maxScale.isNaN || maxScale.isInfinite || maxScale <= 0) ? 3.0 : maxScale;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

          const SizedBox(height: 16),

          if (sessions.isEmpty)
            SizedBox(
              height: 260,
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
              height: 260,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _guideLine(colors, '3.0h', false),
                        _guideLine(colors, '2.0h', false),
                        _guideLine(colors, '1.0h', true),
                        _guideLine(colors, '0.0h', false),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    left: 36,
                    right: 8,
                    bottom: 2,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: weeklyData.map((d) {
                        final double hrs = d['hours'] as double;
                        final String day = d['day'] as String;
                        final bool isPeak = peakVal > 0 && hrs == peakVal;
                        final double heightFactor = safeRatio(hrs, safeMaxScale);
                        final double safeHeight = hrs > 0 ? (160.0 * heightFactor).clamp(4.0, 160.0) : 0.0;

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
                              height: safeHeight,
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

    String dominantCode = allocationList.isNotEmpty ? (allocationList.first['code'] as String) : 'General Study';
    int dominantPct = allocationList.isNotEmpty ? (allocationList.first['pct'] as int) : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUni ? 'Course Allocation' : 'Subject Allocation',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 16,
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (allocationList.isEmpty || totalSec == 0)
            SizedBox(
              height: 260,
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
                      isUni ? 'No enrolled courses or focus sessions logged yet.' : 'No enrolled subjects or focus sessions logged yet.',
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
            SizedBox(
              height: 260,
              child: Row(
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: allocationList.take(4).map((item) {
                        return _buildCourseLegendItem(colors, item);
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Primary Discipline Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.psychology_rounded, size: 14, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Primary Discipline: $dominantCode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Dominant: $dominantPct%',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        fontSize: 16,
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
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bedtime_rounded, size: 14, color: colors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      'Peak Flow: $peakWindow',
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

          const SizedBox(height: 16),

          // 24H Timeline Grid Labels
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

          Container(
            height: 48,
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                if (width <= 0 || width.isNaN || width.isInfinite) {
                  return const SizedBox();
                }
                return Stack(
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
                        final left = safeRatio(startM, 1440.0) * width;
                        final safeBlockWidth = math.min(width, math.max(20.0, safeRatio(durM, 1440.0) * width));
                        final maxLeft = math.max(0.0, width - safeBlockWidth);
                        final safeLeft = (left.isNaN || left.isInfinite) ? 0.0 : left.clamp(0.0, maxLeft);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: safeLeft,
                          width: safeBlockWidth,
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
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          // Color-coded legend blocks (from Stitch reference)
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _legendDot(colors.success, '09:00–12:00 (Morning Focus)', colors),
              _legendDot(colors.secondary, '12:00–18:00 (Afternoon Block)', colors),
              _legendDot(colors.primary, '18:00–24:00 (Night Flow)', colors),
            ],
          ),

          const SizedBox(height: 12),

          // Cognitive Window Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology_rounded, size: 18, color: colors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Peak Cognitive Window: $peakWindow',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Deep Session Retention across diurnal cycle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color dotColor, String label, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
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

    String attendanceStr = isUni ? 'Academic Consistency' : 'Academic Consistency';
    if (attendanceRecords.isNotEmpty) {
      final attended = attendanceRecords.where((r) => r.isPresent == true).length;
      final pct = (safeRatio(attended, attendanceRecords.length) * 100).toStringAsFixed(1);
      attendanceStr = '$pct% Attendance Logged';
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        fontSize: 16,
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

          const SizedBox(height: 16),

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

          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Weeks W01 – W12',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
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

          const SizedBox(height: 12),

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
                Text(
                  attendanceStr,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.success,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 650;
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'SESSION ENGINE: DETERMINISTIC REAL-TIME SYNC',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            );
          }
          return Row(
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
              const SizedBox(width: 12),
              Text(
                'SESSION ENGINE: DETERMINISTIC REAL-TIME SYNC',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MOBILE-NATIVE ACADEMIC INSIGHTS SUITE
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
    final holidaySettings = ref.watch(holidaySettingsStreamProvider).valueOrNull;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMobileStatusPill(colors, profile, isUni, holidaySettings),

              const SizedBox(height: 12),

              _buildMobileSubNav(colors, isUni),

              const SizedBox(height: 12),

              _buildMobilePeriodSelectorAndStepper(colors, isUni),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileStatusPill(
    ChondrobinduThemeColors colors,
    dynamic profile,
    bool isUni,
    HolidaySettings? holidaySettings,
  ) {
    String trackStr = 'UNIVERSITY TRACK';
    String termStr = profile?.term?.isNotEmpty == true ? 'TERM ${profile.term}' : 'TERM 24.2';
    String? weekStr;

    if (isUni) {
      if (holidaySettings?.semesterStart != null) {
        final start = holidaySettings!.semesterStart!;
        final diffDays = _currentAnchorDate.difference(DateTime(start.year, start.month, start.day)).inDays;
        if (diffDays >= 0) {
          final weekNum = (diffDays ~/ 7) + 1;
          weekStr = 'WEEK ${weekNum.toString().padLeft(2, '0')}';
        }
      }
    } else {
      if (profile?.institutionType == InstitutionType.college || profile?.isCollegeStudent == true) {
        trackStr = 'COLLEGE TRACK';
        termStr = 'HSC 2026';
      } else {
        trackStr = 'ADMISSION TRACK';
        termStr = 'ENGINEERING';
      }
    }

    final String pillText = weekStr != null
        ? '$trackStr • $termStr • $weekStr'
        : '$trackStr • $termStr';

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
                    pillText,
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

  Widget _buildMobilePeriodSelectorAndStepper(ChondrobinduThemeColors colors, bool isUni) {
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
                color: _canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _canStepBack ? () => _stepDateRange(-1) : null,
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_rounded, size: 14, color: colors.secondary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _dateRangeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: _canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: _canStepForward ? () => _stepDateRange(1) : null,
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        _buildInlinePeriodPicker(colors, isUni),
      ],
    );
  }

  Widget _buildMobileTopKpis(ChondrobinduThemeColors colors, List<StudySession> sessions, dynamic profile) {
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
    final int targetPct = (safeRatio(avgDailySec, 3600.0) * 100).round();

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
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(icon, color: iconColor, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
      if (!hrs.isNaN && hrs > peakVal) {
        peakVal = hrs;
        peakDay = d['day'] as String;
      }
    }

    final double maxScale = math.max(3.0, (peakVal.isNaN ? 0.0 : peakVal * 1.15).ceilToDouble());
    final safeMaxScale = (maxScale.isNaN || maxScale.isInfinite || maxScale <= 0) ? 3.0 : maxScale;

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
                        final double heightFactor = safeRatio(hrs, safeMaxScale);
                        final double safeHeight = hrs > 0 ? (90.0 * heightFactor).clamp(4.0, 90.0) : 0.0;

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
                              height: safeHeight,
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
                      isUni ? 'Active enrolled modules' : 'Active enrolled subjects',
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
              return _buildCourseLegendItem(colors, item);
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
    final double morningHrs = circadianData['morningHours'] as double;
    final double middayHrs = circadianData['middayHours'] as double;
    final double nightHrs = circadianData['nightHours'] as double;

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
              Flexible(
                child: Text(
                  'Peak: $peakWindow',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
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
              if (width <= 0 || width.isNaN || width.isInfinite) {
                return const SizedBox(height: 38);
              }
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
                        final left = safeRatio(startM, 1440.0) * width;
                        final safeBlockWidth = math.min(width, math.max(16.0, safeRatio(durM, 1440.0) * width));
                        final maxLeft = math.max(0.0, width - safeBlockWidth);
                        final safeLeft = (left.isNaN || left.isInfinite) ? 0.0 : left.clamp(0.0, maxLeft);

                        Color blockColor;
                        if (s.startedAt.hour < 12) {
                          blockColor = colors.success;
                        } else if (s.startedAt.hour < 18) {
                          blockColor = colors.secondary;
                        } else {
                          blockColor = colors.primary;
                        }

                        return Positioned(
                          left: safeLeft,
                          width: safeBlockWidth,
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

          const SizedBox(height: 10),

          // Diurnal Split Badges from Stitch Mobile Spec
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Morning (${morningHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.success, fontSize: 10),
              ),
              Text(
                'Midday (${middayHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 10),
              ),
              Text(
                'Night Flow (${nightHrs.toStringAsFixed(1)}h)',
                style: GoogleFonts.jetBrainsMono(color: colors.primary, fontSize: 10),
              ),
            ],
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
  // DETAILED SUB-TABS (SUBJECT DEEP DIVE, PERFORMANCE LEDGER, CGPA FORECASTER)
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
              Expanded(
                child: Text(
                  isUni ? 'Course Focus Breakdown' : 'Subject Focus Breakdown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
              Expanded(
                child: Text(
                  'Assessment Performance Ledger',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 650) {
                    return Column(
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
                        const SizedBox(height: 12),
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
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
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
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
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
                  );
                },
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 650) {
                    return Column(
                      children: [
                        _desktopForecasterStatCard(
                          colors: colors,
                          label: 'TARGET CGPA',
                          value: profile.targetGpa > 0 ? profile.targetGpa.toStringAsFixed(2) : '3.80',
                          subtext: 'Graduation Target',
                          accent: colors.secondary,
                        ),
                        const SizedBox(height: 12),
                        _desktopForecasterStatCard(
                          colors: colors,
                          label: 'CURRENT LEVEL & TERM',
                          value: 'Level $levelStr, Term $termStr',
                          subtext: deptStr,
                          accent: colors.success,
                        ),
                        const SizedBox(height: 12),
                        _desktopForecasterStatCard(
                          colors: colors,
                          label: 'SIMULATION SCALE',
                          value: '4.00 Max',
                          subtext: 'Standard University Scale',
                          accent: colors.primary,
                        ),
                      ],
                    );
                  }
                  return Row(
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
                  );
                },
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
      width: double.infinity,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              color: accent,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

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
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3846)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC88256).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFC88256).withValues(alpha: 0.3), width: 0.8),
                  ),
                  child: const Icon(Icons.school_rounded, color: Color(0xFFC88256), size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uniName.isNotEmpty ? uniName : 'BUET',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFEDEAE0),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${major.isNotEmpty ? major : "EEE"} • Level ${level.isNotEmpty ? level : "1"}, Term ${term.isNotEmpty ? term : "1"}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFF8B95A5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B222C),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2E3846), width: 0.6),
                  ),
                  child: Text(
                    'Active Term',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFC88256),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFF2E3846), height: 1),
            const SizedBox(height: 12),

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
                  color: const Color(0xFF1B222C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E3846), width: 0.8),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4E9F72).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.insights_rounded, color: Color(0xFF4E9F72), size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CGPA Forecaster & Target Planner',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFFEDEAE0),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Project grades, calculate cutoffs, and track credits',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              color: const Color(0xFF8B95A5),
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, color: Color(0xFFC88256), size: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
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

    const emeraldColor = Color(0xFF4E9F72);
    const roseColor = Color(0xFFC88256);

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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E3846)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded, color: Color(0xFFC88256), size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Performance Trends',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFEDEAE0),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${completedExams.length} Exams Logged',
                style: const TextStyle(color: Color(0xFF8B95A5), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (completedExams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'Log exam scores in the Exams tab to view performance trends.',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF8B95A5), fontSize: 12.5),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B222C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E3846)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Latest Score',
                          style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${latestScore.toStringAsFixed(1)}%',
                          style: const TextStyle(color: Color(0xFFEDEAE0), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1)
                          Text(
                            formattedMarksDelta,
                            style: TextStyle(color: marksDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Baseline Exam', style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B222C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF2E3846)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Merit Rank',
                          style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          latestRank > 0 ? '#$latestRank' : 'N/A',
                          style: const TextStyle(color: Color(0xFFEDEAE0), fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        if (completedExams.length > 1)
                          Text(
                            formattedRankDelta,
                            style: TextStyle(color: rankDeltaColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                          )
                        else
                          const Text('Standard Rank', style: TextStyle(color: Color(0xFF8B95A5), fontSize: 11)),
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

  Color? _parseCourseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) return Color(0xFF000000 | val);
    }
    return null;
  }

  Widget _buildInlinePeriodPicker(ChondrobinduThemeColors colors, bool isUni) {
    IconData headerIcon;
    String headerTitle;
    String headerSubtitle;

    switch (_selectedPeriod) {
      case InsightPeriod.day:
        headerIcon = Icons.today_rounded;
        headerTitle = 'Select Focus Date';
        headerSubtitle = 'Bounded: ${DateFormat('d MMM yyyy').format(_minDate)} – Today';
        break;
      case InsightPeriod.week:
        headerIcon = Icons.calendar_view_week_rounded;
        headerTitle = 'Select Academic Week';
        headerSubtitle = 'Bangladesh Academic Week (Sat – Fri)';
        break;
      case InsightPeriod.month:
        headerIcon = Icons.calendar_month_rounded;
        headerTitle = 'Select Calendar Month';
        headerSubtitle = 'Academic Year Overview';
        break;
      case InsightPeriod.trend:
        headerIcon = Icons.tune_rounded;
        headerTitle = 'Telemetry Trend Window';
        headerSubtitle = 'Filter telemetry across custom timeframe';
        break;
    }

    Widget content;
    switch (_selectedPeriod) {
      case InsightPeriod.day:
        content = _DayPickerContent(
          colors: colors,
          currentAnchor: _currentAnchorDate,
          minDate: _minDate,
          maxDate: _maxDate,
          onDaySelected: (date) {
            setState(() {
              _currentAnchorDate = date;
            });
          },
        );
        break;
      case InsightPeriod.week:
        content = _WeekPickerContent(
          colors: colors,
          currentRangeStart: _rangeStart,
          minDate: _minDate,
          maxDate: _maxDate,
          onWeekSelected: (start) {
            setState(() {
              _currentAnchorDate = start;
            });
          },
        );
        break;
      case InsightPeriod.month:
        content = _MonthPickerContent(
          colors: colors,
          currentAnchor: _currentAnchorDate,
          minDate: _minDate,
          maxDate: _maxDate,
          onMonthSelected: (monthDate) {
            setState(() {
              _currentAnchorDate = monthDate;
            });
          },
        );
        break;
      case InsightPeriod.trend:
        content = _TrendPickerContent(
          colors: colors,
          minDate: _minDate,
          maxDate: _maxDate,
          isUniversity: isUni,
          trendStart: _rangeStart,
          trendEnd: _rangeEnd,
          onTrendRangeSelected: (start, end) {
            setState(() {
              _customTrendStart = start;
              _customTrendEnd = end;
              _currentAnchorDate = end;
            });
          },
        );
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Icon(headerIcon, color: colors.secondary, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      headerSubtitle,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: content,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseLegendItem(ChondrobinduThemeColors colors, Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
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
  }
}

// ---------------------------------------------------------------------------
// TRACK-BOUNDED INLINE PERIOD PICKER CONTENT (DAY, WEEK, MONTH, TREND)
// ---------------------------------------------------------------------------

class _DayPickerContent extends StatefulWidget {
  final ChondrobinduThemeColors colors;
  final DateTime currentAnchor;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime> onDaySelected;

  const _DayPickerContent({
    required this.colors,
    required this.currentAnchor,
    required this.minDate,
    required this.maxDate,
    required this.onDaySelected,
  });

  @override
  State<_DayPickerContent> createState() => _DayPickerContentState();
}

class _DayPickerContentState extends State<_DayPickerContent> {
  late DateTime _browsedMonth;

  @override
  void initState() {
    super.initState();
    _browsedMonth = DateTime(widget.currentAnchor.year, widget.currentAnchor.month, 1);
  }

  @override
  void didUpdateWidget(covariant _DayPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.currentAnchor, widget.currentAnchor)) {
      _browsedMonth = DateTime(widget.currentAnchor.year, widget.currentAnchor.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final daysInMonth = DateTime(_browsedMonth.year, _browsedMonth.month + 1, 0).day;
    final firstDayOffset = (_browsedMonth.weekday % 7 + 1) % 7;

    final canStepBack = !DateTime(_browsedMonth.year, _browsedMonth.month, 1).isBefore(
      DateTime(widget.minDate.year, widget.minDate.month, 1),
    );
    final canStepForward = !DateTime(_browsedMonth.year, _browsedMonth.month, 1).isAfter(
      DateTime(widget.maxDate.year, widget.maxDate.month, 1),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepBack
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedMonth = DateTime(_browsedMonth.year, _browsedMonth.month - 1, 1);
                      });
                    }
                  : null,
            ),
            Text(
              DateFormat('MMMM yyyy').format(_browsedMonth),
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepForward
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedMonth = DateTime(_browsedMonth.year, _browsedMonth.month + 1, 1);
                      });
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'].map((d) {
            return SizedBox(
              width: 36,
              child: Text(
                d,
                textAlign: TextAlign.center,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: firstDayOffset + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.0,
          ),
          itemBuilder: (context, index) {
            if (index < firstDayOffset) {
              return const SizedBox();
            }
            final day = index - firstDayOffset + 1;
            final date = DateTime(_browsedMonth.year, _browsedMonth.month, day);
            final isBeforeMin = date.isBefore(widget.minDate);
            final isAfterMax = date.isAfter(widget.maxDate);
            final isDisabled = isBeforeMin || isAfterMax;
            final isSelected = isSameDay(date, widget.currentAnchor);
            final isToday = isSameDay(date, DateTime.now());

            return InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      SafeHaptics.selectionClick();
                      widget.onDaySelected(date);
                    },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.secondary
                      : (isToday ? colors.primary.withValues(alpha: 0.15) : Colors.transparent),
                  borderRadius: BorderRadius.circular(6),
                  border: isToday && !isSelected
                      ? Border.all(color: colors.primary.withValues(alpha: 0.6))
                      : null,
                ),
                child: Text(
                  '$day',
                  style: GoogleFonts.jetBrainsMono(
                    color: isSelected
                        ? const Color(0xFF171C24)
                        : (isDisabled ? colors.textMuted.withValues(alpha: 0.3) : colors.textPrimary),
                    fontSize: 12,
                    fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WeekPickerContent extends StatefulWidget {
  final ChondrobinduThemeColors colors;
  final DateTime currentRangeStart;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime> onWeekSelected;

  const _WeekPickerContent({
    required this.colors,
    required this.currentRangeStart,
    required this.minDate,
    required this.maxDate,
    required this.onWeekSelected,
  });

  @override
  State<_WeekPickerContent> createState() => _WeekPickerContentState();
}

class _WeekPickerContentState extends State<_WeekPickerContent> {
  late DateTime _browsedMonth;

  @override
  void initState() {
    super.initState();
    _browsedMonth = DateTime(widget.currentRangeStart.year, widget.currentRangeStart.month, 1);
  }

  @override
  void didUpdateWidget(covariant _WeekPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!isSameDay(oldWidget.currentRangeStart, widget.currentRangeStart)) {
      _browsedMonth = DateTime(widget.currentRangeStart.year, widget.currentRangeStart.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final canStepBack = !DateTime(_browsedMonth.year, _browsedMonth.month, 1).isBefore(
      DateTime(widget.minDate.year, widget.minDate.month, 1),
    );
    final canStepForward = !DateTime(_browsedMonth.year, _browsedMonth.month, 1).isAfter(
      DateTime(widget.maxDate.year, widget.maxDate.month, 1),
    );

    final firstDayOfMonth = DateTime(_browsedMonth.year, _browsedMonth.month, 1);
    final lastDayOfMonth = DateTime(_browsedMonth.year, _browsedMonth.month + 1, 0);

    final firstSaturdayOffset = (firstDayOfMonth.weekday % 7 + 1) % 7;
    var currentSat = firstDayOfMonth.subtract(Duration(days: firstSaturdayOffset));

    final List<({DateTime start, DateTime end})> weeks = [];
    while (currentSat.isBefore(lastDayOfMonth) || isSameDay(currentSat, lastDayOfMonth)) {
      final weekEnd = currentSat.add(const Duration(days: 6));
      weeks.add((start: currentSat, end: weekEnd));
      currentSat = currentSat.add(const Duration(days: 7));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepBack
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedMonth = DateTime(_browsedMonth.year, _browsedMonth.month - 1, 1);
                      });
                    }
                  : null,
            ),
            Text(
              DateFormat('MMMM yyyy').format(_browsedMonth),
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepForward
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedMonth = DateTime(_browsedMonth.year, _browsedMonth.month + 1, 1);
                      });
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: weeks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final w = weeks[index];
            final isSelected = isSameDay(w.start, widget.currentRangeStart);
            final isDisabled = w.start.isAfter(widget.maxDate) || w.end.isBefore(widget.minDate);
            final label = '${DateFormat('d MMM').format(w.start)} – ${DateFormat('d MMM yyyy').format(w.end)}';

            return InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      SafeHaptics.selectionClick();
                      widget.onWeekSelected(w.start);
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.secondary.withValues(alpha: 0.2)
                      : (isDisabled ? colors.recessed.withValues(alpha: 0.4) : colors.recessed),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? colors.secondary : colors.surfaceBorder,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.calendar_view_week_rounded,
                            size: 16,
                            color: isSelected ? colors.secondary : colors.primary,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: isSelected
                                    ? colors.secondary
                                    : (isDisabled ? colors.textMuted.withValues(alpha: 0.3) : colors.textPrimary),
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ACTIVE',
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFF171C24),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MonthPickerContent extends StatefulWidget {
  final ChondrobinduThemeColors colors;
  final DateTime currentAnchor;
  final DateTime minDate;
  final DateTime maxDate;
  final ValueChanged<DateTime> onMonthSelected;

  const _MonthPickerContent({
    required this.colors,
    required this.currentAnchor,
    required this.minDate,
    required this.maxDate,
    required this.onMonthSelected,
  });

  @override
  State<_MonthPickerContent> createState() => _MonthPickerContentState();
}

class _MonthPickerContentState extends State<_MonthPickerContent> {
  late int _browsedYear;

  @override
  void initState() {
    super.initState();
    _browsedYear = widget.currentAnchor.year;
  }

  @override
  void didUpdateWidget(covariant _MonthPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentAnchor.year != widget.currentAnchor.year) {
      _browsedYear = widget.currentAnchor.year;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final canStepBack = _browsedYear > widget.minDate.year;
    final canStepForward = _browsedYear < widget.maxDate.year;

    final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: canStepBack ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepBack
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedYear--;
                      });
                    }
                  : null,
            ),
            Text(
              '$_browsedYear',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              color: canStepForward ? colors.textPrimary : colors.textMuted.withValues(alpha: 0.3),
              onPressed: canStepForward
                  ? () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _browsedYear++;
                      });
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
            final monthIndex = index + 1;
            final monthStart = DateTime(_browsedYear, monthIndex, 1);
            final monthEnd = DateTime(_browsedYear, monthIndex + 1, 0);

            final isDisabled = monthEnd.isBefore(widget.minDate) || monthStart.isAfter(widget.maxDate);
            final isSelected = _browsedYear == widget.currentAnchor.year && monthIndex == widget.currentAnchor.month;

            return InkWell(
              onTap: isDisabled
                  ? null
                  : () {
                      SafeHaptics.selectionClick();
                      final selected = monthStart.isAfter(widget.maxDate) ? widget.maxDate : monthStart;
                      widget.onMonthSelected(selected);
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.secondary
                      : (isDisabled ? colors.recessed.withValues(alpha: 0.4) : colors.recessed),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? colors.secondary : colors.surfaceBorder,
                  ),
                ),
                child: Text(
                  monthNames[index],
                  style: GoogleFonts.jetBrainsMono(
                    color: isSelected
                        ? const Color(0xFF171C24)
                        : (isDisabled ? colors.textMuted.withValues(alpha: 0.3) : colors.textPrimary),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TrendPickerContent extends StatefulWidget {
  final ChondrobinduThemeColors colors;
  final DateTime minDate;
  final DateTime maxDate;
  final bool isUniversity;
  final DateTime? trendStart;
  final DateTime? trendEnd;
  final void Function(DateTime start, DateTime end) onTrendRangeSelected;

  const _TrendPickerContent({
    required this.colors,
    required this.minDate,
    required this.maxDate,
    required this.isUniversity,
    required this.trendStart,
    required this.trendEnd,
    required this.onTrendRangeSelected,
  });

  @override
  State<_TrendPickerContent> createState() => _TrendPickerContentState();
}

class _TrendPickerContentState extends State<_TrendPickerContent> {
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isCustom = false;

  @override
  void initState() {
    super.initState();
    _endDate = widget.trendEnd ?? widget.maxDate;
    _startDate = widget.trendStart ?? _endDate.subtract(const Duration(days: 29));
    if (_startDate.isBefore(widget.minDate)) {
      _startDate = widget.minDate;
    }
  }

  @override
  void didUpdateWidget(covariant _TrendPickerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trendStart != widget.trendStart || oldWidget.trendEnd != widget.trendEnd) {
      _startDate = widget.trendStart ?? widget.minDate;
      _endDate = widget.trendEnd ?? widget.maxDate;
    }
  }

  void _applyPreset(int days, {bool sinceStart = false}) {
    SafeHaptics.selectionClick();
    setState(() => _isCustom = false);
    DateTime start;
    if (sinceStart) {
      start = widget.minDate;
    } else {
      start = widget.maxDate.subtract(Duration(days: days - 1));
      if (start.isBefore(widget.minDate)) {
        start = widget.minDate;
      }
    }
    widget.onTrendRangeSelected(start, widget.maxDate);
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: isStart ? widget.minDate : _startDate,
      lastDate: isStart ? _endDate : widget.maxDate,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: widget.colors.secondary,
                  surface: widget.colors.surface,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final sinceStartLabel = widget.isUniversity ? 'Since Semester Start' : 'Since Joined';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK PRESETS',
          style: GoogleFonts.jetBrainsMono(
            color: colors.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetChip(colors, 'Last 7 Days', () => _applyPreset(7)),
            _presetChip(colors, 'Last 14 Days', () => _applyPreset(14)),
            _presetChip(colors, 'Last 30 Days', () => _applyPreset(30)),
            _presetChip(colors, sinceStartLabel, () => _applyPreset(0, sinceStart: true)),
            _presetChip(colors, 'Custom Range', () {
              SafeHaptics.selectionClick();
              setState(() => _isCustom = true);
            }, isHighlighted: _isCustom),
          ],
        ),
        if (_isCustom) ...[
          const SizedBox(height: 20),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 16),
          Text(
            'CUSTOM DATE WINDOW',
            style: GoogleFonts.jetBrainsMono(
              color: colors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'START DATE',
                          style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy').format(_startDate),
                          style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.arrow_forward_rounded, color: colors.textMuted, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(false),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'END DATE',
                          style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 9.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy').format(_endDate),
                          style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.secondary,
                foregroundColor: const Color(0xFF171C24),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                SafeHaptics.selectionClick();
                widget.onTrendRangeSelected(_startDate, _endDate);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                'Apply Custom Window',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _presetChip(ChondrobinduThemeColors colors, String label, VoidCallback onTap, {bool isHighlighted = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isHighlighted ? colors.secondary.withValues(alpha: 0.2) : colors.recessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlighted ? colors.secondary : colors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            color: isHighlighted ? colors.secondary : colors.textPrimary,
            fontSize: 11.5,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SVG-COMPLIANT MULTI-SEGMENT DONUT CHART PAINTER
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
    if (size.width <= 0 || size.height <= 0) return;
    final stroke = strokeWidth > 0 ? strokeWidth : 1.0;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    if (radius <= 0 || radius.isNaN || radius.isInfinite) return;

    final center = Offset(size.width / 2, size.height / 2);

    // Background track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, trackPaint);

    final total = values.fold<double>(0.0, (a, b) => a + (b.isNaN || b.isInfinite ? 0.0 : b));
    if (total <= 0 || total.isNaN || total.isInfinite) return;

    double startAngle = -math.pi / 2; // -90 deg (top)
    for (int i = 0; i < values.length; i++) {
      final val = values[i];
      if (val.isNaN || val.isInfinite || val <= 0) continue;
      final sweepAngle = safeRatio(val, total) * 2 * math.pi;
      if (sweepAngle <= 0 || sweepAngle.isNaN || sweepAngle.isInfinite) continue;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
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
