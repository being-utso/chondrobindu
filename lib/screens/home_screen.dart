import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../providers/analytics_provider.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/safe_haptics.dart';
import '../widgets/academic_onboarding_modal.dart';
import 'journal_screen.dart';

/// Screen 01: Home Command Center
/// Strictly aligned with Stitch Academic OS Design System:
/// - Light Mode: "Lime Wash & Indigo Dye"
/// - Dark Mode: "Indigo Slate & Luminous Rust"
/// Layout:
/// - TIER 1: Full-width 3-Card KPI Row (Study Streak, Total Focus Time, CGPA Forecaster)
/// - TIER 2: 12-Column Main Bento Split:
///   * Left Column (flex: 7): Recommended Deep Work Target + Today's Agenda
///   * Right Column (flex: 5): Active Courses Health + Focus by Course
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final liveProfile = ref.watch(liveUserProfileProvider).valueOrNull;
    final fallbackProfile = ref.watch(userProfileProvider);
    final profile = liveProfile ?? fallbackProfile;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && profile.uid.isNotEmpty && !profile.isOnboarded) {
        AcademicOnboardingModal.showIfNeeded(context, ref, profile);
      }
    });

    final String displayName = profile.nickname.isNotEmpty
        ? profile.nickname
        : (profile.fullName.isNotEmpty ? profile.fullName.split(' ').first : 'Student');

    final isWide = MediaQuery.of(context).size.width >= 1024;
    final isTablet = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: colors.background,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 32.0 : 16.0,
          vertical: 24.0,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Context & Understated Greeting
                _buildHeader(context, ref, colors, profile, displayName),

                const SizedBox(height: 24.0),

                // TIER 1: Full-Width 3-Card KPI Row
                _buildTier1KpiRow(ref, colors, isDark, profile, isTablet),

                const SizedBox(height: 24.0),

                // TIER 2: 12-Column Main Bento Split
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: flex 7
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildRecommendedDeepWorkCard(context, ref, colors, isDark),
                            const SizedBox(height: 24.0),
                            _buildTodaysAgenda(context, ref, colors, isDark),
                          ],
                        ),
                      ),

                      const SizedBox(width: 24.0),

                      // Right Column: flex 5
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildActiveCoursesHealth(ref, colors, isDark),
                            const SizedBox(height: 24.0),
                            _buildFocusByCourse(ref, colors, isDark),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  // Mobile & Tablet Responsive Vertical Stack
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRecommendedDeepWorkCard(context, ref, colors, isDark),
                      const SizedBox(height: 20.0),
                      _buildTodaysAgenda(context, ref, colors, isDark),
                      const SizedBox(height: 20.0),
                      _buildActiveCoursesHealth(ref, colors, isDark),
                      const SizedBox(height: 20.0),
                      _buildFocusByCourse(ref, colors, isDark),
                    ],
                  ),

                const SizedBox(height: 48.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // HEADER & GREETING BAR
  // =========================================================================
  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    dynamic profile,
    String name,
  ) {
    String metadataPrefix = '';
    if (profile != null) {
      if (profile is UserProfile && profile.profileSubtitle.isNotEmpty) {
        metadataPrefix = profile.profileSubtitle;
      } else if (profile.institutionType == InstitutionType.college || (profile is UserProfile && !profile.isUniversityStudent)) {
        final b = (profile.hscBatch != null && profile.hscBatch.toString().trim().isNotEmpty)
            ? profile.hscBatch.toString().trim()
            : (profile.batch != null ? profile.batch.toString().trim() : '2025');
        final g = (profile.hscGroup != null && profile.hscGroup.toString().trim().isNotEmpty)
            ? profile.hscGroup.toString().trim()
            : (profile.academicGroup != null ? profile.academicGroup.toString().trim() : 'Science');
        final t = (profile.primaryTarget != null && profile.primaryTarget.toString().trim().isNotEmpty)
            ? profile.primaryTarget.toString().trim()
            : 'Engineering';
        metadataPrefix = 'HSC \'$b • $g • $t';
      } else {
        final uni = (profile.universityName != null && profile.universityName.toString().trim().isNotEmpty)
            ? profile.universityName.toString().trim()
            : 'BUET';
        final dept = (profile.department != null && profile.department.toString().trim().isNotEmpty)
            ? profile.department.toString().trim()
            : ((profile.major != null && profile.major.toString().trim().isNotEmpty)
                ? profile.major.toString().trim()
                : 'EEE');
        final rawLvl = (profile.level != null && profile.level.toString().trim().isNotEmpty)
            ? profile.level.toString().trim()
            : '1';
        final lvl = rawLvl.toLowerCase().startsWith('level') ? rawLvl : 'Level $rawLvl';
        final rawTrm = (profile.term != null && profile.term.toString().trim().isNotEmpty)
            ? profile.term.toString().trim()
            : '1';
        final trm = rawTrm.toLowerCase().startsWith('term') ? rawTrm : 'Term $rawTrm';
        metadataPrefix = '$uni • $dept • $lvl - $trm';
      }
    } else {
      metadataPrefix = 'BUET • EEE • Level 1 - Term 1';
    }

    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12
        ? 'Good Morning'
        : (hour < 17 ? 'Good Afternoon' : 'Good Evening');

    final isWide = MediaQuery.of(context).size.width >= 768;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Context Indicator Chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.surfaceBorder, width: 1.0),
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
                  metadataPrefix,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Greeting block + Quick action buttons
        if (isWide)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$timeGreeting, $name',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '“Discipline is choosing between what you want now and what you want most.” — Abraham Lincoln',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildHeaderActionButtons(context, ref, colors),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$timeGreeting, $name',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '“Discipline is choosing between what you want now and what you want most.” — Abraham Lincoln',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 14),
              _buildHeaderActionButtons(context, ref, colors),
            ],
          ),
      ],
    );
  }

  Widget _buildHeaderActionButtons(
    BuildContext context,
    WidgetRef ref,
    ChondrobinduThemeColors colors,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Secondary Action: Log Study Session
        OutlinedButton.icon(
          onPressed: () {
            SafeHaptics.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JournalScreen()),
            );
          },
          icon: Icon(Icons.bolt_rounded, size: 16, color: colors.secondary),
          label: Text(
            'Log Study Session',
            style: GoogleFonts.plusJakartaSans(
              color: colors.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: colors.primary.withValues(alpha: 0.08),
            side: BorderSide(color: colors.primary.withValues(alpha: 0.25)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 10),
        // Primary Action: Add Course Task / Start Focus
        ElevatedButton.icon(
          onPressed: () {
            SafeHaptics.mediumImpact();
            ref.read(navigationIndexProvider.notifier).state = 2; // Jump to Timer
          },
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(
            'Start Focus',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // TIER 1: FULL-WIDTH 3-CARD KPI ROW
  // =========================================================================
  Widget _buildTier1KpiRow(
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
    dynamic profile,
    bool isTablet,
  ) {
    final card1 = _buildKpiCardStudyStreak(ref, colors, profile);
    final card2 = _buildKpiCardTotalFocus(ref, colors, profile);
    final card3 = _buildKpiCardCgpaForecaster(ref, colors, profile);

    if (isTablet) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: card1),
            const SizedBox(width: 20),
            Expanded(child: card2),
            const SizedBox(width: 20),
            Expanded(child: card3),
          ],
        ),
      );
    } else {
      return Column(
        children: [
          card1,
          const SizedBox(height: 14),
          card2,
          const SizedBox(height: 14),
          card3,
        ],
      );
    }
  }

  // --- KPI Card 1: Study Streak ---
  Widget _buildKpiCardStudyStreak(WidgetRef ref, ChondrobinduThemeColors colors, dynamic profile) {
    final computedStreak = ref.watch(currentStreakProvider);
    final profileStreak = (profile?.streakDays as int?) ?? 0;
    final int streak = profileStreak > 0 ? profileStreak : computedStreak;

    final streakText = '$streak ${streak == 1 ? 'day' : 'days'}';

    final String momentumBadge;
    if (streak >= 7) {
      momentumBadge = 'TOP 5%';
    } else if (streak >= 3) {
      momentumBadge = 'TOP 15%';
    } else if (streak > 0) {
      momentumBadge = 'ACTIVE';
    } else {
      momentumBadge = 'DAY 0';
    }

    final weeklyTrend = ref.watch(weeklyTrendProvider);
    final maxMins = weeklyTrend.fold<int>(0, (max, item) => item.totalMinutes > max ? item.totalMinutes : max);
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, color: colors.secondary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'STUDY STREAK',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  momentumBadge,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Main value & subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                streakText,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                streak > 0 ? 'Active momentum sustained' : 'Start your streak today',
                style: GoogleFonts.plusJakartaSans(
                  color: streak > 0 ? colors.secondary : colors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          // 7-bar sparkline visualizer from real weekly activity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: weeklyTrend.isNotEmpty
                ? weeklyTrend.map((day) {
                    final isToday = day.date.year == now.year && day.date.month == now.month && day.date.day == now.day;
                    final double barHeight = (maxMins > 0 && day.totalMinutes > 0)
                        ? (12.0 + (day.totalMinutes / maxMins) * 36.0).clamp(12.0, 48.0)
                        : 6.0;
                    final Color barColor = day.totalMinutes > 0
                        ? colors.secondary
                        : colors.surfaceBorder;
                    final dayLetter = day.dayName.isNotEmpty ? day.dayName.substring(0, 1) : 'D';
                    return _buildSparklineCol(dayLetter, barHeight, barColor, isToday: isToday);
                  }).toList()
                : [
                    _buildSparklineCol('M', 6, colors.surfaceBorder),
                    _buildSparklineCol('T', 6, colors.surfaceBorder),
                    _buildSparklineCol('W', 6, colors.surfaceBorder),
                    _buildSparklineCol('T', 6, colors.surfaceBorder),
                    _buildSparklineCol('F', 6, colors.surfaceBorder),
                    _buildSparklineCol('S', 6, colors.surfaceBorder),
                    _buildSparklineCol('S', 6, colors.surfaceBorder, isToday: true),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _buildSparklineCol(String day, double height, Color barColor, {bool isToday = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: height,
          decoration: BoxDecoration(
            color: barColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          day,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
            color: isToday ? barColor : null,
          ),
        ),
      ],
    );
  }

  // --- KPI Card 2: Total Focus Time ---
  Widget _buildKpiCardTotalFocus(WidgetRef ref, ChondrobinduThemeColors colors, dynamic profile) {
    final sessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final sessions = sessionsAsync.valueOrNull ?? [];
    final studyLogs = ref.watch(studyLogsProvider);
    final allSessionsCount = sessions.isNotEmpty ? sessions.length : studyLogs.length;

    final int sessionSecondsTotal = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final int logsMinutesTotal = studyLogs.fold<int>(0, (sum, l) => sum + l.durationInMinutes);
    final int profileMinutes = (profile?.totalFocusMinutes as num?)?.toInt() ?? 0;

    final int effectiveTotalMinutes = sessionSecondsTotal > 0
        ? (sessionSecondsTotal ~/ 60)
        : (logsMinutesTotal > 0 ? logsMinutesTotal : profileMinutes);

    final double totalHours = effectiveTotalMinutes / 60.0;
    final String hrsString = '${totalHours.toStringAsFixed(1)} hrs';

    final String sessionsSubtitle = allSessionsCount > 0
        ? 'Recorded across $allSessionsCount ${allSessionsCount == 1 ? 'deep block' : 'deep blocks'}'
        : 'No focus sessions recorded yet';

    // Calculate this week vs last week trend
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));

    int thisWeekMinutes = 0;
    int lastWeekMinutes = 0;
    int thisWeekSessionCount = 0;

    if (sessions.isNotEmpty) {
      for (final s in sessions) {
        if (s.startedAt.isAfter(sevenDaysAgo)) {
          thisWeekMinutes += (s.durationSeconds ~/ 60);
          thisWeekSessionCount++;
        } else if (s.startedAt.isAfter(fourteenDaysAgo)) {
          lastWeekMinutes += (s.durationSeconds ~/ 60);
        }
      }
    } else {
      for (final l in studyLogs) {
        if (l.date.isAfter(sevenDaysAgo)) {
          thisWeekMinutes += l.durationInMinutes;
          thisWeekSessionCount++;
        } else if (l.date.isAfter(fourteenDaysAgo)) {
          lastWeekMinutes += l.durationInMinutes;
        }
      }
    }

    final double diffHours = (thisWeekMinutes - lastWeekMinutes) / 60.0;
    final bool isPositive = diffHours >= 0;
    final String trendText = '${isPositive ? '+' : ''}${diffHours.toStringAsFixed(1)}h';

    // Daily Mean over last 7 days
    final int dailyMeanMins = (thisWeekMinutes / 7).round();
    final String dailyMeanStr = '${dailyMeanMins ~/ 60}h ${dailyMeanMins % 60}m';

    // Session Avg
    final int sessionAvgMins = thisWeekSessionCount > 0
        ? (thisWeekMinutes / thisWeekSessionCount).round()
        : (allSessionsCount > 0 ? (effectiveTotalMinutes / allSessionsCount).round() : 0);
    final String sessionAvgStr = '${sessionAvgMins}m';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, color: colors.primary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'TOTAL FOCUS TIME',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.success.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up_rounded, size: 13, color: colors.success),
                    const SizedBox(width: 3),
                    Text(
                      trendText,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Main value & subtitle
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hrsString,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sessionsSubtitle,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          // Daily mean and session avg
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Daily Mean: ', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: colors.textMuted)),
                  Text(dailyMeanStr, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: colors.primary)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Session Avg: ', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: colors.textMuted)),
                  Text(sessionAvgStr, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- KPI Card 3: CGPA Forecaster ---
  Widget _buildKpiCardCgpaForecaster(WidgetRef ref, ChondrobinduThemeColors colors, dynamic profile) {
    final bool isCollege = profile != null &&
        (profile.institutionType == InstitutionType.college || (profile is UserProfile && !profile.isUniversityStudent));
    final double maxGpa = isCollege ? 5.00 : 4.00;
    final String label = isCollege ? 'GPA PROJECTION' : 'CGPA FORECASTER';

    final double targetGpa = (profile?.targetGpa as num?)?.toDouble() ?? (isCollege ? 5.00 : 3.75);

    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = (coursesAsync.valueOrNull ?? []).where((c) => !c.isArchived).toList();

    // Calculate real syllabus / semester completion
    int totalTopics = 0;
    int completedTopics = 0;
    double weightedProgressSum = 0.0;
    double totalCredits = 0.0;

    for (final c in courses) {
      totalTopics += c.totalTopicsCount;
      completedTopics += c.completedTopicsCount;
      totalCredits += c.credits;
      weightedProgressSum += (c.credits * c.progressFraction);
    }

    final double overallCompletionFraction = totalCredits > 0
        ? (weightedProgressSum / totalCredits).clamp(0.0, 1.0)
        : (totalTopics > 0 ? (completedTopics / totalTopics).clamp(0.0, 1.0) : 0.0);
    final int completionPct = (overallCompletionFraction * 100).round();

    // Forecasted GPA based on real target GPA and syllabus completion
    double currentGpa = 0.0;
    try {
      if (profile != null) {
        currentGpa = (profile.currentGpa as num?)?.toDouble() ?? 0.0;
      }
    } catch (_) {}

    if (currentGpa <= 0.0) {
      if (courses.isNotEmpty && overallCompletionFraction > 0) {
        currentGpa = (targetGpa * (0.85 + (overallCompletionFraction * 0.15))).clamp(0.0, maxGpa);
      } else {
        currentGpa = targetGpa;
      }
    }

    final String bandSubtitle;
    if (currentGpa >= (isCollege ? 4.75 : 3.75)) {
      bandSubtitle = 'In Honor Roll Band';
    } else if (currentGpa >= (isCollege ? 4.00 : 3.25)) {
      bandSubtitle = 'On Academic Track';
    } else if (currentGpa > 0.0) {
      bandSubtitle = 'Needs Acceleration';
    } else {
      bandSubtitle = 'No Grades Recorded Yet';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Header row
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school_rounded, color: colors.primary, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.25)),
                ),
                child: Text(
                  'TARGET ${targetGpa.toStringAsFixed(2)}',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Value and Honor Roll badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currentGpa.toStringAsFixed(2),
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    ' / ${maxGpa.toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 14, color: colors.success),
                  const SizedBox(width: 4),
                  Text(
                    bandSubtitle,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.success,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          // Semester Milestone Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Semester Milestone',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$completionPct% Complete',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.surfaceBorder, width: 1.0),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: overallCompletionFraction.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(4),
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

  // =========================================================================
  // TIER 2: LEFT COLUMN (FLEX 7)
  // =========================================================================

  // --- Left Card 1: RECOMMENDED DEEP WORK TARGET (Smart Priority Engine) ---
  Widget _buildRecommendedDeepWorkCard(
    BuildContext context,
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final rawCourses = (coursesAsync.valueOrNull ?? []).where((c) => !c.isArchived).toList();

    final upcomingAssessmentsAsync = ref.watch(upcomingAssessmentsStreamProvider);
    final rawAssessments = upcomingAssessmentsAsync.valueOrNull ?? [];

    // Filter valid pending/upcoming assessments with valid scheduled dates
    final validUpcomingAssessments = rawAssessments.where((a) {
      if (a.date == null) return false;
      final s = a.status.toLowerCase();
      return !s.contains('attended') && !s.contains('missed') && !s.contains('complete');
    }).toList();

    // Sort by nearest date ascending (nearest exam/quiz first)
    validUpcomingAssessments.sort((a, b) => a.date!.compareTo(b.date!));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Smart Priority Selection:
    // 1. Select course with the nearest upcoming exam/quiz/assessment
    Course? activeCourse;
    Assessment? prioritizedAssessment;

    if (validUpcomingAssessments.isNotEmpty) {
      for (final assess in validUpcomingAssessments) {
        final match = rawCourses.cast<Course?>().firstWhere(
          (c) => c != null && (
            c.id == assess.courseId ||
            c.code.toLowerCase().trim() == assess.courseCode.toLowerCase().trim() ||
            (assess.courseCode.isNotEmpty && c.code.toLowerCase().contains(assess.courseCode.toLowerCase()))
          ),
          orElse: () => null,
        );
        if (match != null) {
          activeCourse = match;
          prioritizedAssessment = assess;
          break;
        }
      }
      if (activeCourse == null && validUpcomingAssessments.isNotEmpty) {
        prioritizedAssessment = validUpcomingAssessments.first;
      }
    }

    // 2. If no course has an upcoming assessment, fall back to progress-first sorted courses
    final sortedCourses = Course.sortProgressFirst(rawCourses);
    activeCourse ??= sortedCourses.isNotEmpty ? sortedCourses.first : null;

    final bool hasAssessment = prioritizedAssessment != null && prioritizedAssessment.name.isNotEmpty;

    final String targetText;
    if (activeCourse != null) {
      targetText = activeCourse.code.isNotEmpty
          ? '${activeCourse.code} • ${activeCourse.title}'
          : activeCourse.title;
    } else if (prioritizedAssessment != null && prioritizedAssessment.courseCode.isNotEmpty) {
      targetText = '${prioritizedAssessment.courseCode} • ${prioritizedAssessment.name}';
    } else {
      targetText = 'Select or create a course to begin';
    }

    String prioritySubtitle;
    if (hasAssessment) {
      final assessDate = prioritizedAssessment.date != null
          ? DateTime(prioritizedAssessment.date!.year, prioritizedAssessment.date!.month, prioritizedAssessment.date!.day)
          : today;
      final days = assessDate.difference(today).inDays;
      final String countdownText = days == 0
          ? 'in 0 days (today)'
          : days == 1
              ? 'in 1 day'
              : days > 1
                  ? 'in $days days'
                  : 'due soon';
      final weightText = prioritizedAssessment.weightage > 0
          ? ' • Priority: High (${prioritizedAssessment.weightage.toStringAsFixed(0)}% Course Grade)'
          : ' • Priority: Major Assessment';
      final pomodoros = prioritizedAssessment.weightage >= 20 ? 3 : 2;
      final estMinutes = pomodoros * 25;
      prioritySubtitle = 'Upcoming ${prioritizedAssessment.name} $countdownText$weightText • Estimated Focus: $pomodoros Pomodoros ($estMinutes mins).';
    } else if (activeCourse != null) {
      final remainingTopics = activeCourse.totalTopicsCount - activeCourse.completedTopicsCount;
      if (remainingTopics > 0) {
        prioritySubtitle = '$remainingTopics topics remaining in syllabus • Estimated Focus: 2 Pomodoros (50 mins).';
      } else {
        prioritySubtitle = 'Syllabus on track • Ready for practice or revision focus block.';
      }
    } else {
      prioritySubtitle = 'Enroll in active courses to receive personalized deep work recommendations.';
    }

    // Dynamic problem/handout chips
    final List<String> topicChips = [];
    if (activeCourse != null) {
      if (activeCourse.totalTopicsCount > 0) {
        topicChips.add('${activeCourse.completedTopicsCount}/${activeCourse.totalTopicsCount} Syllabus Topics Done');
      }
      topicChips.add('${activeCourse.credits.toStringAsFixed(1)} Credit Hours');
      if (prioritizedAssessment != null && prioritizedAssessment.syllabusSummary != null && prioritizedAssessment.syllabusSummary!.isNotEmpty) {
        topicChips.add('Scope: ${prioritizedAssessment.syllabusSummary}');
      } else if (activeCourse.teacherBadge != null && activeCourse.teacherBadge!.isNotEmpty) {
        topicChips.add('Instructor: [${activeCourse.teacherBadge}]');
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Stack(
        children: [
          // 4px Rust Accent on the Left Border
          Positioned(
            left: -24,
            top: -24,
            bottom: -24,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: colors.secondary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top tag row
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.secondary.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bolt_rounded, size: 14, color: colors.secondary),
                        const SizedBox(width: 4),
                        Text(
                          'RECOMMENDED DEEP WORK TARGET',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.secondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasAssessment)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        prioritizedAssessment.weightage > 0
                            ? 'WEIGHT: ${prioritizedAssessment.weightage.toStringAsFixed(0)}%'
                            : 'NEAREST UPCOMING EXAM',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Title & Start Focus button
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 550;
                  final titleWidget = Text(
                    targetText,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  );

                  final buttonWidget = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      SafeHaptics.mediumImpact();
                      if (activeCourse != null) {
                        ref.read(timerProvider.notifier).changeSubject(activeCourse.title);
                      }
                      ref.read(navigationIndexProvider.notifier).state = 2; // Jump to Timer
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      'Start Focus →',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        titleWidget,
                        const SizedBox(height: 14),
                        buttonWidget,
                      ],
                    );
                  } else {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: titleWidget),
                        const SizedBox(width: 16),
                        buttonWidget,
                      ],
                    );
                  }
                },
              ),

              const SizedBox(height: 8),

              Text(
                prioritySubtitle,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              if (topicChips.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(color: colors.surfaceBorder, height: 1),
                const SizedBox(height: 12),

                // Bottom topic problem pills
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: topicChips.map((chipText) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(chipText, style: GoogleFonts.jetBrainsMono(fontSize: 12, color: colors.textMuted)),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Left Card 2: Today's Agenda (Combined Schedule & Upcoming Deadlines) ---
  Widget _buildTodaysAgenda(
    BuildContext context,
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final agendaAsync = ref.watch(dailyAgendaStreamProvider(today));
    final slots = agendaAsync.valueOrNull ?? [];

    final upcomingAssessmentsAsync = ref.watch(upcomingAssessmentsStreamProvider);
    final rawAssessments = upcomingAssessmentsAsync.valueOrNull ?? [];
    final validAssessments = rawAssessments.where((a) {
      if (a.date == null) return false;
      final s = a.status.toLowerCase();
      return !s.contains('attended') && !s.contains('missed') && !s.contains('complete');
    }).toList()..sort((a, b) => a.date!.compareTo(b.date!));

    final Assessment? nextAssessment = validAssessments.isNotEmpty ? validAssessments.first : null;
    final bool isCompletelyEmpty = slots.isEmpty && nextAssessment == null;

    final weekdayName = DateFormat('EEEE').format(now);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's Agenda",
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$weekdayName Class & Lab Sessions',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  ref.read(navigationIndexProvider.notifier).state = 3; // Planner
                },
                child: Text(
                  'View All →',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Timeline items / Empty State
          if (isCompletelyEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_available_outlined, color: colors.textMuted, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'No classes scheduled for today.',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No classes or tasks scheduled for today',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (slots.isEmpty && nextAssessment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.recessed.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_outlined, color: colors.textMuted, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No routine classes scheduled for today',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ...slots.take(4).map((slot) {
              bool isCompleted = false;
              try {
                final parts = slot.endTime.trim().split(' ');
                if (parts.length == 2) {
                  final timeParts = parts[0].split(':');
                  int hour = int.parse(timeParts[0]);
                  final minute = int.parse(timeParts[1]);
                  final isPm = parts[1].toUpperCase() == 'PM';
                  if (isPm && hour != 12) hour += 12;
                  if (!isPm && hour == 12) hour = 0;
                  final slotEnd = DateTime(now.year, now.month, now.day, hour, minute);
                  isCompleted = now.isAfter(slotEnd);
                }
              } catch (_) {}

              final timeString = slot.startTime.isNotEmpty
                  ? (slot.endTime.isNotEmpty ? '${slot.startTime} – ${slot.endTime}' : slot.startTime)
                  : 'Time N/A';
              final roomString = slot.roomNumber.isNotEmpty ? 'Room ${slot.roomNumber}' : 'Room N/A';
              final teacherString = slot.teacherBadge != null && slot.teacherBadge!.isNotEmpty
                  ? ' • Instructor: [${slot.teacherBadge}]'
                  : '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildStitchAgendaItem(
                  time: timeString,
                  statusDotColor: isCompleted ? colors.success : colors.secondary,
                  code: slot.courseCode.isNotEmpty ? slot.courseCode : 'CLASS',
                  title: slot.courseName.isNotEmpty ? slot.courseName : 'Class Session',
                  subtitle: '$roomString$teacherString',
                  statusLabel: isCompleted ? 'Completed' : slot.slotType.displayName,
                  statusColor: isCompleted ? colors.success : colors.primary,
                  colors: colors,
                  isUpNext: !isCompleted,
                ),
              );
            }),

            // Explicitly Surface the Next Upcoming Assessment / Exam
            if (nextAssessment != null) ...[
              const SizedBox(height: 8),
              _buildUpcomingAssessmentBanner(nextAssessment, colors, today),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildUpcomingAssessmentBanner(
    Assessment assessment,
    ChondrobinduThemeColors colors,
    DateTime today,
  ) {
    final assessDate = assessment.date != null
        ? DateTime(assessment.date!.year, assessment.date!.month, assessment.date!.day)
        : today;
    final daysAway = assessDate.difference(today).inDays;
    final String countdownBadge = daysAway == 0
        ? 'TODAY'
        : daysAway == 1
            ? 'TOMORROW'
            : 'IN $daysAway DAYS';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colors.secondary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.alarm_rounded, color: colors.secondary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        countdownBadge,
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${assessment.courseCode.isNotEmpty ? "${assessment.courseCode} • " : ""}${assessment.name}',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('EEEE, MMM d, yyyy').format(assessDate)}${assessment.weightage > 0 ? " • ${assessment.weightage.toStringAsFixed(0)}% Weight" : ""}${assessment.syllabusSummary != null && assessment.syllabusSummary!.isNotEmpty ? " • Scope: ${assessment.syllabusSummary}" : ""}',
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              assessment.type.isNotEmpty ? assessment.type.toUpperCase() : 'EXAM',
              style: GoogleFonts.jetBrainsMono(
                color: colors.secondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStitchAgendaItem({
    required String time,
    required Color statusDotColor,
    required String code,
    required String title,
    required String subtitle,
    required String statusLabel,
    required Color statusColor,
    required ChondrobinduThemeColors colors,
    bool isUpNext = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.recessed.withValues(alpha: isUpNext ? 1.0 : 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUpNext ? colors.secondary.withValues(alpha: 0.5) : colors.surfaceBorder,
          width: isUpNext ? 1.2 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Time badge
          SizedBox(
            width: 90,
            child: Text(
              time,
              style: GoogleFonts.jetBrainsMono(
                color: isUpNext ? colors.secondary : colors.textMuted,
                fontSize: 12,
                fontWeight: isUpNext ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),

          // Status indicator dot
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: statusDotColor,
              shape: BoxShape.circle,
            ),
          ),

          // Course info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                      ),
                      child: Text(
                        code,
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isUpNext ? colors.secondary : statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isUpNext ? colors.secondary : statusColor.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              statusLabel,
              style: GoogleFonts.jetBrainsMono(
                color: isUpNext ? Colors.white : statusColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TIER 2: RIGHT COLUMN (FLEX 5)
  // =========================================================================

  // --- Right Card 1: Active Courses Health (Progress-First Sorting) ---
  Widget _buildActiveCoursesHealth(
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final rawCourses = (coursesAsync.valueOrNull ?? []).where((c) => !c.isArchived).toList();
    // Dynamically sorted: active progress (completed > 0) -> highest % -> code sequence
    final courses = Course.sortProgressFirst(rawCourses);
    final double totalCr = courses.fold<double>(0.0, (sum, c) => sum + c.credits);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Active Courses Health',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  courses.isNotEmpty
                      ? '${courses.length} Active Courses • ${totalCr.toStringAsFixed(1)} Cr'
                      : '0 Courses Enrolled',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Text(
                  'No active courses enrolled yet.',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else ...[
            ...courses.take(6).map((c) {
              final double fraction = c.progressFraction.clamp(0.0, 1.0);
              final int pct = (fraction * 100).toInt();

              final String statusAlert;
              final Color statusAlertColor;
              final Color barColor;

              if (fraction == 0.0) {
                statusAlert = 'Not Started';
                statusAlertColor = colors.textMuted;
                barColor = colors.surfaceBorder;
              } else if (fraction >= 0.70) {
                statusAlert = 'On Track';
                statusAlertColor = colors.success;
                barColor = colors.success;
              } else {
                statusAlert = 'Needs Attention';
                statusAlertColor = colors.secondary;
                barColor = colors.secondary;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildCourseHealthItem(
                  code: c.code.isNotEmpty ? c.code : 'COURSE',
                  name: c.title,
                  credits: '${c.credits.toStringAsFixed(1)} Cr',
                  progress: fraction,
                  progressPct: '$pct% Syllabus Covered',
                  statusAlert: statusAlert,
                  statusAlertColor: statusAlertColor,
                  barColor: barColor,
                  colors: colors,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildCourseHealthItem({
    required String code,
    required String name,
    required String credits,
    required double progress,
    required String progressPct,
    required String statusAlert,
    required Color statusAlertColor,
    required Color barColor,
    required ChondrobinduThemeColors colors,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.recessed.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      code,
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                credits,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Progress bar
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.surfaceBorder,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  progressPct,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                statusAlert,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusAlertColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Right Card 2: Focus by Course Telemetry ---
  Widget _buildFocusByCourse(
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final distList = ref.watch(subjectDistributionProvider);
    final studyLogs = ref.watch(studyLogsProvider);

    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));
    final int weekMinutes = studyLogs
        .where((l) => l.date.isAfter(sevenDaysAgo))
        .fold<int>(0, (sum, l) => sum + l.durationInMinutes);
    final double weekHours = weekMinutes / 60.0;
    const double targetHours = 20.0;
    final int pctMet = ((weekHours / targetHours) * 100).round();

    final List<Color> palette = [
      colors.primary,
      colors.success,
      colors.secondary,
      colors.primary.withValues(alpha: 0.5),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Focus by Course',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Past 7 Days',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (distList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: Text(
                  'No study sessions logged in past 7 days.',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else ...[
            ...distList.take(4).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final dist = entry.value;
              final hrs = (dist.totalMinutes / 60.0).toStringAsFixed(1);
              final pct = dist.percentage.toStringAsFixed(0);
              final color = palette[index % palette.length];

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildFocusCourseBar(
                  dist.subjectName,
                  '$hrs hrs ($pct%)',
                  (dist.percentage / 100.0).clamp(0.0, 1.0),
                  color,
                  colors,
                ),
              );
            }),
          ],

          const SizedBox(height: 16),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Target: ${targetHours.toStringAsFixed(0)} hrs',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: colors.textMuted,
                ),
              ),
              Text(
                '$pctMet% Met',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: pctMet >= 100 ? colors.success : colors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCourseBar(
    String code,
    String stat,
    double factor,
    Color fill,
    ChondrobinduThemeColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                code,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              stat,
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.recessed,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: factor.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
