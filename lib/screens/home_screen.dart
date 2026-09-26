import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/safe_haptics.dart';
import '../widgets/academic_onboarding_modal.dart';

/// Screen 01: Home Command Center
/// Desktop-native 2-column layout (70% Left, 30% Right) with responsive 1-column mobile fallback.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 32.0 : 16.0,
          vertical: 24.0,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Context & Understated Greeting
                _buildHeader(profile, displayName),

                const SizedBox(height: 24.0),

                // Responsive 2-column layout (or stacked on mobile)
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left Column: 70% width
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Primary Metric Row (3 Horizontal Cards)
                            _buildPrimaryMetricsRow(ref, profile),

                            const SizedBox(height: 24.0),

                            // Assessment Radar & Quick Start Action
                            _buildQuickStartBanner(context, ref),

                            const SizedBox(height: 24.0),

                            // Focus Distribution & Course Health Preview
                            _buildCourseHealthPreview(ref),
                          ],
                        ),
                      ),

                      const SizedBox(width: 24.0),

                      // Right Column: 30% width (Today's Agenda)
                      Expanded(
                        flex: 3,
                        child: _buildTodaysAgenda(context, ref),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPrimaryMetricsRow(ref, profile, isMobile: true),
                      const SizedBox(height: 20.0),
                      _buildQuickStartBanner(context, ref),
                      const SizedBox(height: 20.0),
                      _buildTodaysAgenda(context, ref),
                      const SizedBox(height: 20.0),
                      _buildCourseHealthPreview(ref),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SECTION A: Header & Greeting ---
  Widget _buildHeader(dynamic profile, String name) {
    String metadataPrefix = 'Level 2 • Term 1 • EEE • Batch 2023';

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
          final batchStr = rawBatch.toLowerCase().startsWith('batch') ? rawBatch : 'Batch $rawBatch';

          metadataPrefix = '$levelStr • $termStr • $deptStr • $batchStr';
        }
      }
    } catch (_) {}

    final todayFormatted = DateFormat('EEE, d MMM y').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Metadata Pill Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1816),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF2E2623), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF34D399),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$metadataPrefix  |  $todayFormatted',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Greeting block
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good Day, $name',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '"Discipline today builds the freedom you want tomorrow."',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF9E8C82),
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- SECTION B: Primary Metric Cards ---
  Widget _buildPrimaryMetricsRow(WidgetRef ref, dynamic profile, {bool isMobile = false}) {
    if (isMobile) {
      return Column(
        children: [
          _buildStreakCard(profile),
          const SizedBox(height: 12),
          _buildFocusTimeCard(ref, profile),
          const SizedBox(height: 12),
          _buildCgpaCard(profile),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: _buildStreakCard(profile)),
        const SizedBox(width: 16),
        Expanded(child: _buildFocusTimeCard(ref, profile)),
        const SizedBox(width: 16),
        Expanded(child: _buildCgpaCard(profile)),
      ],
    );
  }

  Widget _buildStreakCard(dynamic profile) {
    int streak = 0;
    try {
      streak = (profile?.streakDays as int?) ?? 0;
    } catch (_) {}

    final streakText = '$streak ${streak == 1 ? 'day' : 'days'}';
    final streakSubtitle = streak > 0 ? 'Active momentum' : 'Start your streak today';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'STUDY STREAK',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.local_fire_department_rounded, color: Color(0xFFF2B78A), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            streakText,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                streakSubtitle,
                style: GoogleFonts.plusJakartaSans(
                  color: streak > 0 ? const Color(0xFF34D399) : const Color(0xFF9E8C82),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Mini sparkline bars
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sparkBar(10),
                  _sparkBar(16),
                  _sparkBar(12),
                  _sparkBar(22),
                  _sparkBar(18),
                  _sparkBar(26, isHighlight: true),
                  _sparkBar(28, isHighlight: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sparkBar(double height, {bool isHighlight = false}) {
    return Container(
      width: 4,
      height: height,
      margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFF2B78A) : const Color(0xFF382A24),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildFocusTimeCard(WidgetRef ref, dynamic profile) {
    final sessionsAsync = ref.watch(recentStudySessionsStreamProvider);
    final sessions = sessionsAsync.value ?? [];
    final int sessionCount = sessions.length;
    final int totalMinutes = sessions.fold<int>(0, (sum, s) => sum + (s.durationSeconds ~/ 60));
    final int profileMinutes = (profile.totalFocusMinutes as num?)?.toInt() ?? 0;
    final int effectiveMinutes = totalMinutes > 0 ? totalMinutes : profileMinutes;

    final hrs = (effectiveMinutes / 60.0).toStringAsFixed(1);
    final sessionsText = 'in $sessionCount ${sessionCount == 1 ? 'session' : 'sessions'}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TOTAL FOCUS TIME',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.timer_outlined, color: Color(0xFF34D399), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$hrs hrs',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFEDE8E3),
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                sessionsText,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFF9E8C82),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // Mini trend histogram
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sparkBar(14),
                  _sparkBar(20),
                  _sparkBar(18),
                  _sparkBar(24),
                  _sparkBar(30, isHighlight: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCgpaCard(dynamic profile) {
    final bool isCollege = profile != null && profile.institutionType == InstitutionType.college;
    final double maxGpa = isCollege ? 5.00 : 4.00;
    final String label = isCollege ? 'GPA FORECASTER' : 'CGPA FORECASTER';

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

    final progressFactor = maxGpa > 0 ? (currentGpa / maxGpa).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.auto_graph_rounded, color: Color(0xFFF2B78A), size: 20),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    currentGpa.toStringAsFixed(2),
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFEDE8E3),
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    ' / ${maxGpa.toStringAsFixed(2)}',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF9E8C82),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF241C1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF382A24), width: 0.8),
                ),
                child: Text(
                  'Target ${targetGpa.toStringAsFixed(2)}',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Dual-tone linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: const Color(0xFF2E2623)),
                  FractionallySizedBox(
                    widthFactor: progressFactor,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFF2B78A), Color(0xFF34D399)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SECTION C: Right Panel — Today's Agenda ---
  Widget _buildTodaysAgenda(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final agendaAsync = ref.watch(dailyAgendaStreamProvider(today));
    final slots = agendaAsync.valueOrNull ?? [];

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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_note_rounded, color: Color(0xFFF2B78A), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    "Today's Agenda",
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFEDE8E3),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  ref.read(navigationIndexProvider.notifier).state = 3; // Planner tab
                },
                child: Text(
                  'View All →',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFF2B78A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          if (slots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.event_available_outlined, color: Color(0xFF9E8C82), size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'No classes scheduled for today.',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF9E8C82),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...slots.take(4).map((slot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _agendaItem(
                  time: slot.startTime.isNotEmpty ? slot.startTime : 'Time N/A',
                  title: slot.courseName.isNotEmpty ? slot.courseName : (slot.courseCode.isNotEmpty ? slot.courseCode : 'Class'),
                  subtitle: slot.roomNumber.isNotEmpty ? slot.roomNumber : 'Room N/A',
                  type: slot.slotType.displayName,
                  teacherBadge: slot.teacherBadge,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _agendaItem({
    required String time,
    required String title,
    required String subtitle,
    required String type,
    String? teacherBadge,
    bool isOngoing = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOngoing ? const Color(0xFFF2B78A) : const Color(0xFF2E2623),
          width: isOngoing ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF382A24), width: 0.8),
            ),
            child: Text(
              time,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFFF2B78A),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$type • $subtitle',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF9E8C82),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (teacherBadge != null && teacherBadge.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1816),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
              ),
              child: Text(
                '[$teacherBadge]',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFF2B78A),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- SECTION D: Quick Start Focus Banner ---
  Widget _buildQuickStartBanner(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = coursesAsync.valueOrNull ?? [];
    final activeCourse = courses.isNotEmpty
        ? courses.firstWhere((c) => !c.isArchived, orElse: () => courses.first)
        : null;

    final targetText = activeCourse != null
        ? (activeCourse.courseCode.isNotEmpty
            ? '${activeCourse.courseCode} • ${activeCourse.courseName}'
            : activeCourse.courseName)
        : 'Select or create a course to begin';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF382A24), width: 1.2),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF241C1A),
            Color(0xFF1E1816),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.flash_on_rounded, color: Color(0xFFF2B78A), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RECOMMENDED DEEP WORK TARGET',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  targetText,
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDE8E3),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF151211),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              SafeHaptics.mediumImpact();
              if (activeCourse != null) {
                ref.read(timerProvider.notifier).changeSubject(activeCourse.title);
              }
              ref.read(navigationIndexProvider.notifier).state = 2; // Jump to Timer
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(
              'Start Focus →',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- SECTION E: Course Health Preview ---
  Widget _buildCourseHealthPreview(WidgetRef ref) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final courses = (coursesAsync.valueOrNull ?? []).where((c) => !c.isArchived).toList();

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
                'Active Courses Health',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '${courses.length} Active Courses',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (courses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  'No active courses enrolled yet.',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF9E8C82),
                    fontSize: 13,
                  ),
                ),
              ),
            )
          else ...[
            ...courses.take(4).map((c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10.0),
                child: _courseProgressRow(
                  c.courseCode.isNotEmpty ? c.courseCode : 'COURSE',
                  c.courseName,
                  c.progressFraction,
                  '${(c.progressFraction * 100).toInt()}%',
                  c.teacherBadge,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _courseProgressRow(String code, String name, double factor, String pct, String? teacher) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            code,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFF2B78A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            name,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFEDE8E3),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (teacher != null && teacher.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Text(
              '[$teacher]',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF9E8C82),
                fontSize: 11,
              ),
            ),
          ),
        Expanded(
          flex: 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: factor,
              backgroundColor: const Color(0xFF2E2623),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
              minHeight: 5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 40,
          child: Text(
            pct,
            textAlign: TextAlign.right,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFF9E8C82),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
