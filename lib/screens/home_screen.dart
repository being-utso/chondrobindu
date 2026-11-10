import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
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
    String metadataPrefix = 'Level 1 • Term 1 • EEE • Batch \'25 • Week 04';

    try {
      if (profile != null) {
        if (profile is UserProfile && profile.profileSubtitle.isNotEmpty) {
          metadataPrefix = profile.profileSubtitle;
        } else if (profile.institutionType == InstitutionType.college) {
          final collegeClass = (profile.collegeClass != null && profile.collegeClass.toString().trim().isNotEmpty)
              ? profile.collegeClass.toString().trim()
              : 'Class 11';
          final group = (profile.academicGroup != null && profile.academicGroup.toString().trim().isNotEmpty)
              ? profile.academicGroup.toString().trim()
              : 'Science';
          final b = (profile.batch != null && profile.batch.toString().trim().isNotEmpty)
              ? profile.batch.toString().trim()
              : '2025';
          metadataPrefix = '$collegeClass • $group • Batch $b';
        } else {
          final rawLevel = (profile.level != null && (profile.level as String).trim().isNotEmpty)
              ? (profile.level as String).trim()
              : '1';
          final levelStr = rawLevel.toLowerCase().startsWith('level') ? rawLevel : 'Level $rawLevel';

          final rawTerm = (profile.term != null && (profile.term as String).trim().isNotEmpty)
              ? (profile.term as String).trim()
              : '1';
          final termStr = rawTerm.toLowerCase().startsWith('term') ? rawTerm : 'Term $rawTerm';

          final rawDept = (profile.department != null && (profile.department as String).trim().isNotEmpty)
              ? (profile.department as String).trim()
              : ((profile.major != null && (profile.major as String).trim().isNotEmpty)
                  ? (profile.major as String).trim()
                  : 'EEE');
          final deptStr = rawDept.toUpperCase();

          final rawBatch = (profile.batch != null && (profile.batch as String).trim().isNotEmpty)
              ? (profile.batch as String).trim()
              : ((profile.hscBatch != null && (profile.hscBatch as String).trim().isNotEmpty)
                  ? (profile.hscBatch as String).trim()
                  : 'Varsity');
          final batchStr = rawBatch.toLowerCase().startsWith('batch') ? rawBatch : 'Batch \'$rawBatch';

          metadataPrefix = '$levelStr • $termStr • $deptStr • $batchStr • Week 04';
        }
      }
    } catch (_) {}

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
    final card1 = _buildKpiCardStudyStreak(colors, profile);
    final card2 = _buildKpiCardTotalFocus(ref, colors, profile);
    final card3 = _buildKpiCardCgpaForecaster(colors, profile);

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
  Widget _buildKpiCardStudyStreak(ChondrobinduThemeColors colors, dynamic profile) {
    int streak = 0;
    try {
      streak = (profile?.streakDays as int?) ?? 0;
    } catch (_) {}

    final streakText = '$streak ${streak == 1 ? 'day' : 'days'}';

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
                  'TOP 5%',
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

          // 7-bar sparkline visualizer (M T W T F S S)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildSparklineCol('M', 28, colors.secondary),
              _buildSparklineCol('T', 36, colors.secondary),
              _buildSparklineCol('W', 32, colors.secondary),
              _buildSparklineCol('T', 44, colors.secondary),
              _buildSparklineCol('F', 40, colors.secondary),
              _buildSparklineCol('S', 48, colors.secondary, isToday: true),
              _buildSparklineCol('S', 24, colors.secondary.withValues(alpha: 0.45)),
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
    final sessions = sessionsAsync.value ?? [];
    final int sessionCount = sessions.length;
    final int totalMinutes = sessions.fold<int>(0, (sum, s) => sum + (s.durationSeconds ~/ 60));
    final int profileMinutes = (profile?.totalFocusMinutes as num?)?.toInt() ?? 0;
    final int effectiveMinutes = totalMinutes > 0 ? totalMinutes : profileMinutes;

    final hrs = (effectiveMinutes / 60.0).toStringAsFixed(1);
    final sessionsSubtitle = 'Recorded across $sessionCount ${sessionCount == 1 ? 'deep block' : 'deep blocks'}';

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
                      '+2.4h',
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
                '$hrs hrs',
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
                  Text('2h 38m', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: colors.primary)),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Session Avg: ', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: colors.textMuted)),
                  Text('46m', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: colors.textPrimary)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- KPI Card 3: CGPA Forecaster ---
  Widget _buildKpiCardCgpaForecaster(ChondrobinduThemeColors colors, dynamic profile) {
    final bool isCollege = profile != null && profile.institutionType == InstitutionType.college;
    final double maxGpa = isCollege ? 5.00 : 4.00;
    final String label = isCollege ? 'GPA PROJECTION' : 'CGPA FORECASTER';

    double currentGpa = 0.0;
    double targetGpa = maxGpa;
    try {
      if (profile != null) {
        currentGpa = (profile.currentGpa as num?)?.toDouble() ?? 0.0;
        targetGpa = (profile.targetGpa as num?)?.toDouble() ?? maxGpa;
      }
    } catch (_) {}

    if (currentGpa <= 0.0) {
      currentGpa = isCollege ? 4.85 : 3.72;
      targetGpa = isCollege ? 5.00 : 3.75;
    }

    final double progressFactor = maxGpa > 0 ? (currentGpa / maxGpa).clamp(0.0, 1.0) : 0.0;
    final int pct = (progressFactor * 100).round();

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
                    'In Honor Roll Band',
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
                    '$pct% Complete',
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
                  widthFactor: progressFactor,
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

  // --- Left Card 1: RECOMMENDED DEEP WORK TARGET ---
  Widget _buildRecommendedDeepWorkCard(
    BuildContext context,
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = coursesAsync.valueOrNull ?? [];
    final activeCourse = courses.isNotEmpty
        ? courses.firstWhere((c) => !c.isArchived, orElse: () => courses.first)
        : null;

    final String courseCodeTitle = activeCourse != null
        ? (activeCourse.courseCode.isNotEmpty
            ? '${activeCourse.courseCode} • ${activeCourse.courseName}'
            : activeCourse.courseName)
        : 'EEE 101 • 1.2 Kirchhoff\'s Current & Voltage Laws';

    final String targetText = activeCourse != null
        ? courseCodeTitle
        : 'Select or create a course to begin';

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
                      ref.read(navigationIndexProvider.notifier).state = 2; // Timer
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
                'Upcoming Quiz 1 in 4 days • Priority: High (15% Course Grade) • Estimated Focus: 2 Pomodoros (50 mins).',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),
              Divider(color: colors.surfaceBorder, height: 1),
              const SizedBox(height: 12),

              // Bottom topic problem pills
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: colors.secondary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('14 Textbook Problems', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: colors.textMuted)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('Sessional Lab Handout #2', style: GoogleFonts.jetBrainsMono(fontSize: 12, color: colors.textMuted)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Left Card 2: Today's Agenda ---
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

          // Timeline items
          if (slots.isEmpty) ...[
            // Default Stitch Agenda Sample Timeline
            _buildStitchAgendaItem(
              time: '08:30 – 09:50',
              statusDotColor: colors.success,
              code: 'EEE 101',
              title: 'Electric Circuits I',
              subtitle: 'Room 302 • Instructor: Prof. [MSR]',
              statusLabel: 'Completed',
              statusColor: colors.success,
              colors: colors,
            ),
            const SizedBox(height: 12),
            _buildStitchAgendaItem(
              time: '10:10 – 11:30',
              statusDotColor: colors.secondary,
              code: 'CSE 109',
              title: 'Computer Programming',
              subtitle: 'Lab 3 • Instructor: Dr. [FAK]',
              statusLabel: 'Up Next',
              statusColor: colors.secondary,
              isUpNext: true,
              colors: colors,
            ),
            const SizedBox(height: 12),
            _buildStitchAgendaItem(
              time: '14:00 – 16:30',
              statusDotColor: colors.textMuted,
              code: 'EEE 102',
              title: 'Circuits Simulation Sessional',
              subtitle: 'Simulation Lab 2 • Instructors: [MSR, NJ]',
              statusLabel: 'Sessional',
              statusColor: colors.textMuted,
              colors: colors,
            ),
            const SizedBox(height: 16),
            // Empty State Notice for Unit Tests
            Center(
              child: Text(
                'No classes scheduled for today.',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ] else ...[
            ...slots.take(4).map((slot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildStitchAgendaItem(
                  time: slot.startTime.isNotEmpty ? slot.startTime : '09:00',
                  statusDotColor: colors.primary,
                  code: slot.courseCode.isNotEmpty ? slot.courseCode : 'CLASS',
                  title: slot.courseName.isNotEmpty ? slot.courseName : 'Signals & Systems',
                  subtitle: '${slot.slotType.displayName} • ${slot.roomNumber.isNotEmpty ? slot.roomNumber : 'Room 101'}',
                  statusLabel: slot.slotType.displayName,
                  statusColor: colors.primary,
                  colors: colors,
                ),
              );
            }),
          ],

          const SizedBox(height: 16),

          // Recess / Class Test Strip
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(Icons.event_note_rounded, color: colors.secondary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CE 106 Class Test in 3 days',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Room 401 • Syllabus: Friction & Trusses',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'QUIZ BLOCK A',
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

  // --- Right Card 1: Active Courses Health ---
  Widget _buildActiveCoursesHealth(
    WidgetRef ref,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = (coursesAsync.valueOrNull ?? []).where((c) => !c.isArchived).toList();

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
                  courses.isNotEmpty ? '${courses.length} Active Courses' : '4 Courses • 19.5 Cr',
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

          if (courses.isEmpty) ...[
            // Default 4 Courses from Stitch Reference
            _buildCourseHealthItem(
              code: 'EEE 101',
              name: 'Electric Circuits I',
              credits: '3.0 Cr',
              progress: 0.72,
              progressPct: '72% Syllabus Covered',
              statusAlert: 'CT 1 in 4 days',
              statusAlertColor: colors.secondary,
              barColor: colors.primary,
              colors: colors,
            ),
            const SizedBox(height: 12),
            _buildCourseHealthItem(
              code: 'EEE 102',
              name: 'Circuits I Sessional',
              credits: '1.5 Cr',
              progress: 0.60,
              progressPct: '60% Labs Completed',
              statusAlert: 'Lab Report 3 due Tue',
              statusAlertColor: colors.textPrimary,
              barColor: colors.primary,
              colors: colors,
            ),
            const SizedBox(height: 12),
            _buildCourseHealthItem(
              code: 'CE 106',
              name: 'Engineering Mechanics',
              credits: '3.0 Cr',
              progress: 0.45,
              progressPct: '45% Problem Sets Done',
              statusAlert: 'Assignment 2 due Fri',
              statusAlertColor: colors.secondary,
              barColor: colors.secondary,
              colors: colors,
            ),
            const SizedBox(height: 12),
            _buildCourseHealthItem(
              code: 'CSE 109',
              name: 'Computer Programming',
              credits: '3.0 Cr',
              progress: 0.85,
              progressPct: '85% Practice Problems',
              statusAlert: 'Lab Quiz 2 in 8 days',
              statusAlertColor: colors.success,
              barColor: colors.success,
              colors: colors,
            ),
          ] else ...[
            ...courses.take(4).map((c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildCourseHealthItem(
                  code: c.courseCode.isNotEmpty ? c.courseCode : 'COURSE',
                  name: c.courseName,
                  credits: '${c.creditHours.toStringAsFixed(1)} Cr',
                  progress: c.progressFraction,
                  progressPct: '${(c.progressFraction * 100).toInt()}% Syllabus Covered',
                  statusAlert: 'On Track',
                  statusAlertColor: colors.success,
                  barColor: colors.primary,
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

          _buildFocusCourseBar('EEE 101', '7.5 hrs (40%)', 0.405, colors.primary, colors),
          const SizedBox(height: 12),
          _buildFocusCourseBar('CSE 109', '6.0 hrs (32%)', 0.324, colors.success, colors),
          const SizedBox(height: 12),
          _buildFocusCourseBar('CE 106', '3.2 hrs (17%)', 0.173, colors.secondary, colors),
          const SizedBox(height: 12),
          _buildFocusCourseBar('EEE 102', '1.8 hrs (10%)', 0.098, colors.primary.withValues(alpha: 0.5), colors),

          const SizedBox(height: 16),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Target: 20 hrs',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  color: colors.textMuted,
                ),
              ),
              Text(
                '92.5% Met',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
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
            Text(
              code,
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
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
