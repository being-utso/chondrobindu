import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/group_constants.dart';
import '../core/constants/quotes_data.dart';
import '../models/exam_model.dart';
import '../providers/analytics_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/performance_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../services/syllabus_factory.dart';
import 'course_syllabus_screen.dart' show CourseSyllabusScreen;
import 'exams_screen.dart';
import 'performance_screen.dart';
import 'profile_screen.dart';
import 'syllabus_screen.dart';
import 'timer_screen.dart';
import '../providers/notes_provider.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_preloader.dart';
import 'journal_screen.dart';
import '../core/constants/group_constants.dart';
import '../models/note_model.dart';
import '../models/assessment_model.dart';
import '../models/routine_models.dart';
import 'attendance_matrix_screen.dart';
import 'routine_screen.dart';
import 'term_performance_screen.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../widgets/common/pressable_card.dart';
import '../widgets/common/app_badge.dart';
import '../widgets/common/luxury_glass_card.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Alias for HomeDashboard
typedef HomeDashboard = HomeDashboardScreen;

/// Comprehensive Home Dashboard Screen for Chondrobindu engineering prep app.
/// Follows Graphite & Copper Ember aesthetic (#110D0C, #1C1412, #F2B78A) with high-density widgets.
class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  bool _hasCheckedOnboarding = false;
  final TextEditingController _scratchpadController = TextEditingController();
  Timer? _scratchpadDebounceTimer;
  bool _isSavingScratchpad = false;
  bool _isScratchpadInitialized = false;
  late Quote _currentQuote;

  @override
  void initState() {
    super.initState();
    _currentQuote = motivationalQuotes[Random().nextInt(motivationalQuotes.length)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndPromptOnboarding();
    });
  }

  @override
  void dispose() {
    _scratchpadDebounceTimer?.cancel();
    _scratchpadController.dispose();
    super.dispose();
  }

  void _checkAndPromptOnboarding() {
    final profile = ref.read(userProfileProvider);
    if (!profile.isOnboarded) {
      _showProfileOnboardingModal();
    }
  }

  /// Task 3: Mandatory Non-Dismissible Profile Onboarding Modal
  void _showProfileOnboardingModal() {
    final profile = ref.read(userProfileProvider);
    final nameCtrl = TextEditingController(text: profile.fullName);
    final nicknameCtrl = TextEditingController(text: profile.nickname);
    final collegeCtrl = TextEditingController(text: profile.college);
    String target = profile.primaryTarget.isNotEmpty ? profile.primaryTarget : 'Engineering (BUET, CKRUET)';
    String batch = profile.hscBatch.isNotEmpty ? profile.hscBatch : '2025';

    final targetOptions = GroupConstants.getTargetsForGroup(profile.hscGroup);

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false, // Non-dismissible
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          const cardColor = Color(0xFF241C1A);
          const accentColor = Color(0xFFF2B78A);

          return PopScope(
            canPop: false, // Prevent back button dismissal
            child: AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: const [
                  Icon(Icons.waving_hand_rounded, color: Color(0xFFFBBF24), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Welcome to Chondrobindu!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set up your student profile to personalize your study tracker and target analytics.',
                        style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Full Name *',
                          labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: accentColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nicknameCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Nickname / Preferred Name *',
                          labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          prefixIcon: const Icon(Icons.badge_outlined, color: accentColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a nickname' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: targetOptions.contains(target) ? target : targetOptions.first,
                        dropdownColor: const Color(0xFF170F0D),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Admission Target *',
                          labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          prefixIcon: const Icon(Icons.track_changes_rounded, color: accentColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        items: targetOptions.map((opt) => DropdownMenuItem(value: opt, child: Text(opt))).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => target = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: collegeCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'College (Optional)',
                          labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          prefixIcon: const Icon(Icons.school_outlined, color: accentColor, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF140F0E),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      final updated = profile.copyWith(
                        fullName: nameCtrl.text.trim(),
                        nickname: nicknameCtrl.text.trim(),
                        primaryTarget: target,
                        college: collegeCtrl.text.trim(),
                        hscBatch: batch,
                        isOnboarded: true,
                      );

                      await ref.read(userProfileProvider.notifier).saveProfile(updated);

                      // Task 2: Automatically generate and save Subjects & Sections to Syllabus in Firestore
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null) {
                        try {
                          final defaultSyllabus = SyllabusFactory.generateSyllabus(target, profile.hscGroup);
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('syllabus_state')
                              .doc(target)
                              .set({
                            'target': target,
                            'subjects': defaultSyllabus.map((s) => s.toMap()).toList(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        } catch (e) {
                          debugPrint('Error populating default syllabus: $e');
                        }
                      }

                      if (mounted) {
                        Navigator.pop(ctx); // Close Profile Onboarding
                        _showExamOnboardingModal(); // Trigger optional exam onboarding
                      }
                    }
                  },
                  child: const Text('Save & Continue', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Task 3: Optional Exam Onboarding Modal (With Save / Skip)
  void _showExamOnboardingModal() {
    final examNameCtrl = TextEditingController(text: 'Model Test 01');
    final subjCtrl = TextEditingController(text: 'Physics');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          const cardColor = Color(0xFF241C1A);
          const accentColor = Color(0xFFF2B78A);

          return AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: const [
                Icon(Icons.calendar_month_rounded, color: accentColor, size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Schedule First Exam?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Would you like to schedule an upcoming admission test or model test to track on your dashboard?',
                    style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: examNameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Exam Title',
                      labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      prefixIcon: const Icon(Icons.assignment_outlined, color: accentColor, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Subject / Syllabus',
                      labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      prefixIcon: const Icon(Icons.menu_book_rounded, color: accentColor, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.event_rounded, color: accentColor, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Text('Change Date', style: TextStyle(color: accentColor, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), // Skip button closes popup
                child: const Text('Skip for now', style: TextStyle(color: Colors.blueGrey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: const Color(0xFF140F0E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final name = examNameCtrl.text.trim();
                  final subj = subjCtrl.text.trim();
                  await ref.read(examServiceProvider).addExam(
                        ExamModel(
                          id: '',
                          examName: name.isNotEmpty ? name : 'Model Test',
                          subject: subj.isNotEmpty ? subj : 'General',
                          date: selectedDate,
                          totalMarks: 100,
                          marksObtained: 0,
                          meritPosition: 0,
                          isCompleted: false,
                        ),
                      );
                  if (mounted) {
                    Navigator.pop(ctx); // Close Exam Onboarding
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: const Text(
                          'First exam scheduled on your live dashboard!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const orangeColor = Color(0xFFF2B78A);

    final userProfile = ref.watch(userProfileProvider);
    final authUser = FirebaseAuth.instance.currentUser;
    final String? effectiveImageUrl = (userProfile.profileImageUrl != null && userProfile.profileImageUrl!.trim().isNotEmpty)
        ? userProfile.profileImageUrl!.trim()
        : (authUser?.photoURL != null && authUser!.photoURL!.trim().isNotEmpty
            ? authUser.photoURL!.trim()
            : null);
    final bool hasProfileImage = effectiveImageUrl != null && effectiveImageUrl.isNotEmpty;

    // Watch live exams from Cloud Firestore
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.asData?.value ?? [];

    final todaysFocusMinutes = ref.watch(todaysFocusMinutesProvider);
    final currentStreak = ref.watch(currentStreakProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF241C1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
              ),
              padding: const EdgeInsets.all(7), // Tight padding so the glyph fills ~24x24
              child: Image.asset(
                'assets/icons/logo_ember.png', // Ensure this points to the copper ember asset
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Chondrobindu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '::',
              style: TextStyle(
                color: accentColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                SafeHaptics.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: CircleAvatar(
                radius: 19,
                backgroundColor: accentColor.withOpacity(0.2),
                backgroundImage: hasProfileImage ? NetworkImage(effectiveImageUrl) : null,
                child: !hasProfileImage
                    ? const Icon(
                        Icons.person,
                        color: accentColor,
                        size: 20,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Welcome Section
              _buildWelcomeHeader(userProfile),
              const SizedBox(height: 16),

              // Task 2: Admission Countdown Card (Top of Home Dashboard) - Hidden in University Mode
              if (!userProfile.isUniversityStudent) ...[
                _buildAdmissionCountdownCard(userProfile, context),
                const SizedBox(height: 24),
              ],

              // Task 3: In-App Wellness Card (Burnout Guard: 12+ hours today)
              if (todaysFocusMinutes >= 720) ...[
                _buildBurnoutWellnessCard(),
                const SizedBox(height: 20),
              ],

              // 2. Summary Cards (Live Focus Time & Streak from shared streams)
              _buildSummaryCards(cardColor, accentColor, orangeColor, todaysFocusMinutes, currentStreak),
              const SizedBox(height: 20),

              // 3. Brain Dump Quick Capture Scratchpad (Task 2 & 3: Auto-saved with 1s debounce)
              _buildBrainDumpCard(cardColor, accentColor, userProfile),
              const SizedBox(height: 20),

              // 4. Quote Card
              _buildMotivationalQuoteCard(cardColor, accentColor),
              const SizedBox(height: 20),

              // 5. University Mode: Upcoming Assessments & Attendance Overview | Admission Mode: Target Exam Countdown
              if (userProfile.isUniversityStudent) ...[
                _buildUpcomingAssessmentsWidget(cardColor, accentColor),
                const SizedBox(height: 20),
                _buildAttendanceOverviewCard(cardColor, accentColor),
                const SizedBox(height: 20),
              ] else ...[
                _buildLiveUpcomingExamCard(allExams, cardColor, accentColor),
                const SizedBox(height: 20),
              ],

              // 6. Quick Access Action Buttons
              _buildQuickAccessRow(cardColor, accentColor),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// Evaluates current hour for dynamic, natural greeting
  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    } else if (hour < 17) {
      return 'Good afternoon';
    } else {
      return 'Good evening';
    }
  }

  /// 1. Welcome Section
  Widget _buildWelcomeHeader(UserProfile userProfile) {
    final name = userProfile.displayName;
    final target = userProfile.isUniversityStudent
        ? (userProfile.universityName?.trim().isNotEmpty == true
            ? userProfile.universityName!.trim()
            : 'University Studies')
        : (userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'Admission');
    final greeting = _getGreeting();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '$greeting, $name',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),
            const Text('👋', style: TextStyle(fontSize: 22)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          userProfile.isUniversityStudent
              ? 'Welcome to your $target dashboard.'
              : 'Ready for your $target prep?',
          style: TextStyle(
            color: Colors.blueGrey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  /// 2. Summary Cards (Live Focus and Streak from shared streams)
  Widget _buildSummaryCards(Color cardColor, Color accentColor, Color orangeColor, int todaysFocusMinutes, int currentStreak) {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: "Today's Focus",
            value: '${todaysFocusMinutes}m',
            subtitle: 'Goal: 180m',
            icon: Icons.timer_outlined,
            iconColor: accentColor,
            cardColor: cardColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Study Streak',
            value: '$currentStreak Days',
            subtitle: currentStreak > 0 ? '🔥 On a roll!' : 'Start your streak!',
            icon: Icons.local_fire_department_rounded,
            iconColor: orangeColor,
            cardColor: cardColor,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardColor,
  }) {
    return PressableCard(
      backgroundColor: cardColor,
      padding: AppSpacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.labelMedium,
              ),
              Icon(icon, color: iconColor, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTypography.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  /// 3. Brain Dump / Scratchpad Quick Capture with Debounced Auto-Save
  Widget _buildBrainDumpCard(Color cardColor, Color accentColor, UserProfile userProfile) {
    if (!_isScratchpadInitialized) {
      _scratchpadController.text = userProfile.scratchpadText;
      _isScratchpadInitialized = true;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12.0),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withOpacity(0.3)),
                    ),
                    child: Icon(Icons.psychology_rounded, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Brain Dump',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Quick Capture Scratchpad',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
              ),
              if (_isSavingScratchpad)
                Row(
                  children: [
                    AppPreloader(
                      size: 13,
                      strokeWidth: 1.5,
                      color: accentColor,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Saving...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                )
              else if (_scratchpadController.text.trim().isNotEmpty)
                Row(
                  children: const [
                    Icon(Icons.cloud_done_rounded, color: Color(0xFF34D399), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Auto-saved',
                      style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scratchpadController,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.4),
            onChanged: (value) {
              _scratchpadDebounceTimer?.cancel();
              if (!_isSavingScratchpad) {
                setState(() {
                  _isSavingScratchpad = true;
                });
              }
              _scratchpadDebounceTimer = Timer(const Duration(seconds: 1), () async {
                try {
                  await ref.read(userProfileProvider.notifier).updateScratchpad(value);
                } catch (e) {
                  debugPrint('Brain Dump auto-save error: $e');
                } finally {
                  if (mounted) {
                    setState(() {
                      _isSavingScratchpad = false;
                    });
                  }
                }
              });
            },
            decoration: InputDecoration(
              hintText: 'Jot down distracting thoughts, formulas, or quick to-dos...',
              hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12.5),
              filled: true,
              fillColor: const Color(0xFF170F0D),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accentColor.withOpacity(0.4)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Free your mind before your study session. Auto-syncs to your profile after typing.',
                  style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentColor,
                  side: const BorderSide(color: Color(0xFFF2B78A)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.bookmark_add_rounded, size: 14, color: Color(0xFFF2B78A)),
                label: const Text('Save to Journal', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final text = _scratchpadController.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFFEF4444),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        content: const Text(
                          'Brain Dump is empty! Write something first to save it as a note.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    );
                    return;
                  }

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    SafeHaptics.lightImpact();
                    try {
                      await ref.read(noteServiceProvider).convertBrainDumpToNote(
                        uid,
                        _scratchpadController.text,
                      );
                      _scratchpadController.clear();
                      await ref.read(userProfileProvider.notifier).updateScratchpad('');

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFFF2B78A),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF140F0E)),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Saved Brain Dump to Journal!',
                                    style: TextStyle(color: Color(0xFF140F0E), fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const JournalScreen()),
                                    );
                                  },
                                  child: const Text('Open Journal', style: TextStyle(color: Color(0xFF140F0E), fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFFEF4444),
                            content: Text('Failed to save note: $e', style: const TextStyle(color: Colors.white)),
                          ),
                        );
                      }
                    }
                  }
                },
              ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.open_in_new_rounded, color: Colors.blueGrey, size: 18),
                tooltip: 'Open Journal',
                onPressed: () {
                  SafeHaptics.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const JournalScreen()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 4. Motivational Quote Card
  Widget _buildMotivationalQuoteCard(Color cardColor, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFBBF24).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.format_quote_rounded, color: Color(0xFFFBBF24), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${_currentQuote.text}"',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '— ${_currentQuote.author}',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
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

  /// TASK 3: Live Upcoming Assessments Widget for University Mode (Next 14 Days)
  Widget _buildUpcomingAssessmentsWidget(Color cardColor, Color accentColor) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .snapshots(),
      builder: (context, courseSnap) {
        final courseDocs = courseSnap.data?.docs ?? [];
        final Map<String, String> courseCodeMap = {};
        final List<Assessment> allAssessments = [];

        for (final doc in courseDocs) {
          final data = doc.data();
          final cCode = data['courseCode'] as String? ?? 'Course';
          courseCodeMap[doc.id] = cCode;
          allAssessments.addAll(
            Assessment.fromRawListOrMap(data['assessments'], defaultCourseId: doc.id),
          );
        }

        final now = DateTime.now();
        final startThreshold = now.subtract(const Duration(hours: 12));
        final endThreshold = now.add(const Duration(days: 14, hours: 23, minutes: 59));

        final datedAssessments = allAssessments.where((a) => a.date != null).toList();
        final upcoming = datedAssessments.where((a) {
          final d = a.date!;
          return d.isAfter(startThreshold) && d.isBefore(endThreshold);
        }).toList();

        upcoming.sort((a, b) => a.date!.compareTo(b.date!));

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18.0),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12.0),
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.assignment_turned_in_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Upcoming Assessments',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'CTs, Quizzes & Lab Tests (Next 14 Days)',
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (upcoming.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withOpacity(0.35)),
                      ),
                      child: Text(
                        '${upcoming.length} active',
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (upcoming.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF4A3830)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle_outline_rounded, color: Colors.blueGrey.shade500, size: 28),
                      const SizedBox(height: 8),
                      const Text(
                        'No assessments scheduled in the next 14 days',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You are all caught up! Enjoy your study flow.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                      ),
                    ],
                  ),
                )
              else
                ...upcoming.map((assess) {
                  final daysDiff = assess.date != null
                      ? assess.date!.difference(DateTime(now.year, now.month, now.day)).inDays
                      : 0;
                  String daysText;
                  Color badgeColor;
                  if (daysDiff <= 0) {
                    daysText = 'Today';
                    badgeColor = const Color(0xFFEF4444);
                  } else if (daysDiff == 1) {
                    daysText = 'Tomorrow';
                    badgeColor = const Color(0xFFF59E0B);
                  } else {
                    daysText = 'In $daysDiff days';
                    badgeColor = const Color(0xFFF2B78A);
                  }

                  final cCode = courseCodeMap[assess.courseId] ?? 'Course';
                  final dateText = assess.date != null
                      ? '${assess.date!.day}/${assess.date!.month}/${assess.date!.year}'
                      : 'Unscheduled';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF170F0D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A3830)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: badgeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: badgeColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            daysText,
                            style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    cCode,
                                    style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  Text('•', style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      assess.name,
                                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dateText • ${assess.totalMarks.toStringAsFixed(0)} Marks (${assess.weightage.toStringAsFixed(0)}%)',
                                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  /// Compact Attendance Summary Card (Uncluttered Home Screen)
  Widget _buildAttendanceOverviewCard(Color cardColor, Color accentColor) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, courseSnap) {
        final courseDocs = courseSnap.data?.docs ?? [];

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('attendance_records')
              .snapshots(),
          builder: (context, attSnap) {
            final attDocs = attSnap.data?.docs ?? [];
            final allRecords = attDocs
                .map((doc) => AttendanceRecord.fromMap(doc.data(), defaultId: doc.id))
                .toList();

            int totalAttended = 0;
            int totalMissed = 0;
            for (final doc in courseDocs) {
              final data = doc.data();
              final useOverride = data['useManualAttendanceOverride'] == true;
              if (useOverride) {
                totalAttended += (data['manualAttendedClasses'] as num?)?.toInt() ?? 0;
                final tot = (data['manualTotalClasses'] as num?)?.toInt() ?? 0;
                totalMissed += (tot - ((data['manualAttendedClasses'] as num?)?.toInt() ?? 0)).clamp(0, 9999);
              } else {
                final cRecords = allRecords.where((r) => r.courseId == doc.id).toList();
                totalAttended += cRecords.where((r) => r.status.name.toLowerCase() == 'attended').length;
                totalMissed += cRecords.where((r) => r.status.name.toLowerCase() == 'missed').length;
              }
            }
            final totalHeld = totalAttended + totalMissed;
            final overallRate = totalHeld > 0 ? (totalAttended / totalHeld) * 100.0 : 100.0;
            final rateColor = overallRate >= 75.0
                ? const Color(0xFF10B981)
                : (overallRate >= 60.0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));

            return buildGlassCard(
              padding: const EdgeInsets.all(18.0),
              borderRadius: BorderRadius.circular(16.0),
              child: Column(
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
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.co_present_rounded, color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attendance Summary',
                                style: AppTypography.cardTitle,
                              ),
                              Text(
                                '${courseDocs.length} Enrolled Courses Tracked',
                                style: AppTypography.subtext,
                              ),
                            ],
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.grid_view_rounded, size: 15),
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Matrix', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 16),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderMedium.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text('Attended', style: AppTypography.attendanceCount),
                            const SizedBox(height: 4),
                            Text(
                              '$totalAttended',
                              style: AppTypography.geistMono(
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 28, color: AppColors.borderMedium),
                        Column(
                          children: [
                            Text('Missed', style: AppTypography.attendanceCount),
                            const SizedBox(height: 4),
                            Text(
                              '$totalMissed',
                              style: AppTypography.geistMono(
                                color: AppColors.error,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Container(width: 1, height: 28, color: AppColors.borderMedium),
                        Column(
                          children: [
                            Text('Overall Rate', style: AppTypography.attendanceCount),
                            const SizedBox(height: 4),
                            Text(
                              totalHeld == 0 ? 'N/A' : '${overallRate.toStringAsFixed(1)}%',
                              style: AppTypography.geistMono(
                                color: rateColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (totalHeld > 0) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (overallRate / 100.0).clamp(0.0, 1.0),
                        backgroundColor: AppColors.borderMedium.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// 4. Live Upcoming Exam Card (Task 4: Live Data & Clean Empty State)
  Widget _buildLiveUpcomingExamCard(List<ExamModel> allExams, Color cardColor, Color accentColor) {
    final now = DateTime.now();
    final upcomingExams = allExams
        .where((e) => !e.isCompleted && e.date.isAfter(now.subtract(const Duration(hours: 12))))
        .toList();

    upcomingExams.sort((a, b) => a.date.compareTo(b.date));

    if (upcomingExams.isEmpty) {
      // Clean, elegant empty state UI
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.event_available_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Target Exam Countdown',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'No upcoming admission or model tests scheduled yet.',
              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.withOpacity(0.15),
                foregroundColor: accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                ref.read(navigationIndexProvider.notifier).state = 3;
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Schedule First Exam', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ],
        ),
      );
    }

    final nearest = upcomingExams.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        gradient: LinearGradient(
          colors: [
            cardColor,
            const Color(0xFF1E3A5F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.timer_outlined, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nearest.examName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        nearest.subject,
                        style: TextStyle(
                          color: Colors.blueGrey.shade300,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'UPCOMING',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 5. Quick Access Action Buttons (Specialized University Utilities: CGPA Simulator, Weekly Routine, Study Journal, Attendance Matrix)
  Widget _buildQuickAccessRow(Color cardColor, Color accentColor) {
    final userProfile = ref.watch(userProfileProvider);
    final isUni = userProfile.isUniversityStudent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (isUni) ...[
          Row(
            children: [
              // Utility 1: CGPA Simulator
              Expanded(
                child: _buildActionTile(
                  title: 'CGPA Simulator',
                  subtitle: 'Target & Projection',
                  icon: Icons.calculate_rounded,
                  iconColor: const Color(0xFFA855F7),
                  cardColor: cardColor,
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TermPerformanceScreen(
                          universityName: userProfile.universityName ?? 'BUET',
                          term: userProfile.term ?? '1',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Utility 2: Weekly Routine
              Expanded(
                child: _buildActionTile(
                  title: 'Weekly Routine',
                  subtitle: 'Timetable & Rooms',
                  icon: Icons.calendar_view_week_rounded,
                  iconColor: const Color(0xFFF2B78A),
                  cardColor: cardColor,
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutineScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Utility 3: Study Journal
              Expanded(
                child: _buildActionTile(
                  title: 'Study Journal',
                  subtitle: 'Notes & Reflections',
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFF10B981),
                  cardColor: cardColor,
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JournalScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Utility 4: Attendance Matrix
              Expanded(
                child: _buildActionTile(
                  title: 'Attendance Matrix',
                  subtitle: 'Overview & History',
                  icon: Icons.grid_view_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  cardColor: cardColor,
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  title: 'Study Timer',
                  subtitle: 'Start Focus',
                  icon: Icons.play_arrow_rounded,
                  iconColor: accentColor,
                  cardColor: cardColor,
                  onTap: () => ref.read(navigationIndexProvider.notifier).state = 2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  title: 'Exams & Marks',
                  subtitle: 'Log Results',
                  icon: Icons.insert_chart_outlined_rounded,
                  iconColor: const Color(0xFFA78BFA),
                  cardColor: cardColor,
                  onTap: () => ref.read(navigationIndexProvider.notifier).state = 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildActionTile(
                  title: 'Syllabus Tracker',
                  subtitle: 'Topics & Chapters',
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFF10B981),
                  cardColor: cardColor,
                  onTap: () => ref.read(navigationIndexProvider.notifier).state = 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionTile(
                  title: 'Growth Analytics',
                  subtitle: 'Trends & Insights',
                  icon: Icons.analytics_outlined,
                  iconColor: const Color(0xFFF97316),
                  cardColor: cardColor,
                  onTap: () => ref.read(navigationIndexProvider.notifier).state = 4,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color cardColor,
    required VoidCallback onTap,
  }) {
    return PressableCard(
      backgroundColor: cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderRadiusButton,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: AppColors.textTertiary,
            size: 14,
          ),
        ],
      ),
    );
  }

  /// Task 3: Subtle, warm-toned in-app wellness banner for Burnout Guard (12+ hours today)
  Widget _buildBurnoutWellnessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEA580C).withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF97316).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withOpacity(0.18),
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

  /// Task 2: Admission Countdown Card Widget

/// Task 2: Admission Countdown Card Widget
  Widget _buildAdmissionCountdownCard(UserProfile userProfile, BuildContext context) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = List<ExamModel>.from(examsAsync.asData?.value ?? [])
      ..sort((a, b) => a.date.compareTo(b.date));

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final upcomingExams = allExams
        .where((e) => e.date.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList();
    upcomingExams.sort((a, b) => a.date.compareTo(b.date));

    String? eventName;
    DateTime? eventDate;

    // 1. PRIORITY 1: Try to load the Pinned Exam first
    if (userProfile.pinnedHomeExamId != null && userProfile.pinnedHomeExamId!.isNotEmpty) {
      try {
        final pinnedExam = allExams.firstWhere((e) => e.id == userProfile.pinnedHomeExamId);
        eventName = pinnedExam.subject.trim().isNotEmpty
            ? '${pinnedExam.subject.trim()}: ${pinnedExam.examName.trim()}'
            : pinnedExam.examName.trim();
        eventDate = pinnedExam.date;
      } catch (_) {}
    }

    // 2. PRIORITY 2: If no pinned exam, use the Custom Target Event (Ultimate Goal)
    if (eventName == null && userProfile.targetEventName != null && userProfile.targetEventName!.isNotEmpty && userProfile.targetEventDate != null) {
      eventName = userProfile.targetEventName;
      eventDate = userProfile.targetEventDate;
    }

    // 3. PRIORITY 3: If no custom target is set, fallback to the closest Upcoming Exam
    if (eventName == null && upcomingExams.isNotEmpty) {
      final displayExam = upcomingExams.first;
      eventName = displayExam.subject.trim().isNotEmpty
          ? '${displayExam.subject.trim()}: ${displayExam.examName.trim()}'
          : displayExam.examName.trim();
      eventDate = displayExam.date;
    }

    final bool hasTarget = eventName != null && eventName.trim().isNotEmpty && eventDate != null;

    int daysRemaining = 0;
    if (hasTarget) {
      final targetDate = DateTime(eventDate!.year, eventDate.month, eventDate.day);
      daysRemaining = targetDate.difference(todayStart).inDays;
      if (daysRemaining < 0) daysRemaining = 0;
    }

    return GestureDetector(
      onTap: () {
        SafeHaptics.lightImpact();
        _showTargetEventConfigModal(context, userProfile);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF241C1A), Color(0xFF170F0D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFF2B78A).withOpacity(0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF2B78A).withOpacity(0.08),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: hasTarget
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFF2B78A).withOpacity(0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$daysRemaining',
                          style: const TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'DAYS',
                          style: TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, color: Color(0xFFF2B78A), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'TARGET COUNTDOWN',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.edit_rounded, color: Colors.blueGrey.shade400, size: 14),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'until $eventName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.stars_rounded, color: Color(0xFFF2B78A), size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tap to set your ultimate goal 🎯',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Set target exam name & test date',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Color(0xFFF2B78A), size: 22),
                ],
              ),
      ),
    );
  }

  /// Task 3: Configuration Modal for Admission Goal Target Event
  void _showTargetEventConfigModal(BuildContext context, UserProfile profile) {
    final nameCtrl = TextEditingController(text: profile.targetEventName ?? 'BUET Admission Test');
    DateTime selectedDate = profile.targetEventDate ?? DateTime.now().add(const Duration(days: 120));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade700,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.flag_rounded, color: Color(0xFFF2B78A), size: 22),
                      SizedBox(width: 8),
                      Text(
                        'Set Admission Goal Target',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Target Event Name TextField
                  const Text(
                    'Target Event Name',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'e.g. BUET Admission Test / CKRUET',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Target Event Date Picker
                  const Text(
                    'Target Event Date',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 1000)),
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF170F0D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blueGrey.shade700),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                            style: const TextStyle(color: Colors.white, fontSize: 13.5),
                          ),
                          const Icon(Icons.calendar_month_rounded, color: Color(0xFFF2B78A), size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Save Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final eventName = nameCtrl.text.trim();
                        if (eventName.isEmpty) return;

                        Navigator.pop(ctx);
                        SafeHaptics.heavyImpact();

                        await ref.read(userProfileProvider.notifier).updateTargetEvent(
                              eventName: eventName,
                              eventDate: selectedDate,
                            );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF140F0E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      child: const Text('Save Countdown Target'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
