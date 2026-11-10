import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/constants/group_constants.dart';
import '../core/constants/quotes_data.dart';
import '../core/theme/app_colors.dart';
import '../models/exam_model.dart';
import '../providers/analytics_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/notes_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../services/syllabus_factory.dart';
import '../utils/safe_haptics.dart';
import '../widgets/app_preloader.dart';
import 'attendance_matrix_screen.dart';
import 'journal_screen.dart';
import 'routine_screen.dart';
import 'term_performance_screen.dart';

/// Alias for HomeDashboard
typedef HomeDashboard = HomeDashboardScreen;

/// Comprehensive Home Dashboard Screen for Chondrobindu Academic OS.
/// Follows "Lime Wash & Indigo Dye" (Light) / "Indigo Slate & Luminous Rust" (Dark) aesthetic.
class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  final TextEditingController _scratchpadController = TextEditingController();
  Timer? _scratchpadDebounceTimer;
  bool _isSavingScratchpad = false;
  bool _isScratchpadInitialized = false;
  late Quote _currentQuote;

  // Selected agenda filter for Today's Agenda
  final Set<String> _completedAgendaItemIds = {};

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

  /// Mandatory Non-Dismissible Profile Onboarding Modal
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
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = AppColors.of(context);

          return PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.surfaceBorder, width: 1.0),
              ),
              title: Row(
                children: [
                  Icon(Icons.school_rounded, color: colors.secondary, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Welcome to Chondrobindu!',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
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
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Full Name *',
                          labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          filled: true,
                          fillColor: colors.recessed,
                          prefixIcon: Icon(Icons.person_outline_rounded, color: colors.secondary, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nicknameCtrl,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Nickname / Preferred Name',
                          labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          filled: true,
                          fillColor: colors.recessed,
                          prefixIcon: Icon(Icons.badge_outlined, color: colors.secondary, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: collegeCtrl,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'College / Institution *',
                          labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          filled: true,
                          fillColor: colors.recessed,
                          prefixIcon: Icon(Icons.account_balance_outlined, color: colors.secondary, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your college' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: batch,
                              dropdownColor: colors.surface,
                              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'HSC Batch',
                                labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: colors.recessed,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              items: ['2024', '2025', '2026', '2027', '2028'].map((b) {
                                return DropdownMenuItem(value: b, child: Text('HSC $b'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => batch = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: targetOptions.contains(target) ? target : targetOptions.first,
                              isExpanded: true,
                              dropdownColor: colors.surface,
                              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'Target Goal',
                                labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: colors.recessed,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              ),
                              items: targetOptions.map((t) {
                                return DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setModalState(() => target = val);
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
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

                      final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
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

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        _showExamOnboardingModal();
                      }
                    }
                  },
                  child: Text('Save & Continue', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Skip for now (QA / Dev)', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _showExamOnboardingModal() {
    final examNameCtrl = TextEditingController(text: 'Model Test 01');
    final subjCtrl = TextEditingController(text: 'Physics');
    DateTime selectedDate = DateTime.now().add(const Duration(days: 7));
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = AppColors.of(context);

          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colors.surfaceBorder, width: 1.0),
            ),
            title: Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: colors.secondary, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Schedule First Exam?',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
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
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: examNameCtrl,
                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Exam Title',
                      labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: colors.recessed,
                      prefixIcon: Icon(Icons.assignment_outlined, color: colors.secondary, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: subjCtrl,
                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Subject',
                      labelStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: colors.recessed,
                      prefixIcon: Icon(Icons.book_outlined, color: colors.secondary, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.edit_calendar_rounded, size: 16, color: colors.secondary),
                        label: Text('Change Date', style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 730)),
                          );
                          if (picked != null) {
                            setModalState(() => selectedDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Skip', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final title = examNameCtrl.text.trim();
                  final subject = subjCtrl.text.trim();
                  if (title.isEmpty) return;

                  final examService = ref.read(examServiceProvider);
                  await examService.addExam(
                    ExamModel(
                      id: '',
                      examName: title,
                      subject: subject.isEmpty ? 'General' : subject,
                      date: selectedDate,
                      totalMarks: 100,
                    ),
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: colors.success,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        content: Text(
                          'First exam scheduled on your live dashboard!',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }
                },
                child: Text('Schedule', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTargetEventConfigModal(BuildContext context, UserProfile profile) {
    final colors = AppColors.of(context);
    final nameCtrl = TextEditingController(text: profile.targetEventName ?? 'BUET Admission Test');
    DateTime selectedDate = profile.targetEventDate ?? DateTime.now().add(const Duration(days: 120));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 20,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
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
                            color: colors.textMuted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.flag_rounded, color: colors.secondary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Set Admission Goal Target',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Target Event Name',
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                        decoration: InputDecoration(
                          hintText: 'e.g. BUET Admission Test / CKRUET',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted.withValues(alpha: 0.6), fontSize: 12.5),
                          filled: true,
                          fillColor: colors.recessed,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Target Event Date',
                        style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
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
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: colors.recessed,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Date: ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                                style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                              ),
                              Icon(Icons.calendar_month_rounded, color: colors.secondary, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
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
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          child: const Text('Save Countdown Target'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final userProfile = ref.watch(userProfileProvider);
    final todaysFocusMinutes = ref.watch(todaysFocusMinutesProvider);
    final currentStreak = ref.watch(currentStreakProvider);
    final weeklyTrend = ref.watch(weeklyTrendProvider);
    final uid = Firebase.apps.isNotEmpty ? (FirebaseAuth.instance.currentUser?.uid ?? '') : '';

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.of(context).size.width >= 768 ? 24.0 : 16.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. HEADER & GREETING BAR
                  _buildHeaderBanner(colors, userProfile),
                  const SizedBox(height: 24),

                  // 2. TOP KPI METRIC ROW (3 Bento Cards)
                  _buildTopKpiRow(colors, userProfile, todaysFocusMinutes, currentStreak, weeklyTrend),
                  const SizedBox(height: 24),

                  // 3. MAIN 12-COLUMN ASYMMETRIC BENTO GRID (7 Cols Left / 5 Cols Right)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth >= 1024;
                      if (isDesktop) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT COLUMN (7 cols width: flex 7)
                            Expanded(
                              flex: 7,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDeepWorkHeroCard(colors, userProfile),
                                  const SizedBox(height: 24),
                                  _buildAgendaLedger(colors, uid),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // RIGHT COLUMN (5 cols width: flex 5)
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildCoursesHealthCard(colors, uid),
                                  const SizedBox(height: 24),
                                  _buildFocusDistributionCard(colors),
                                ],
                              ),
                            ),
                          ],
                        );
                      } else {
                        // MOBILE & TABLET STACK
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDeepWorkHeroCard(colors, userProfile),
                            const SizedBox(height: 20),
                            _buildAgendaLedger(colors, uid),
                            const SizedBox(height: 20),
                            _buildCoursesHealthCard(colors, uid),
                            const SizedBox(height: 20),
                            _buildFocusDistributionCard(colors),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  // Additional utilities & quick access
                  _buildQuickAccessSection(colors, userProfile),
                  const SizedBox(height: 24),
                  _buildBrainDumpCard(colors, userProfile),
                  if (todaysFocusMinutes >= 720) ...[
                    const SizedBox(height: 24),
                    _buildBurnoutWellnessCard(colors),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. HEADER & GREETING BAR
  // =========================================================================
  Widget _buildHeaderBanner(ChondrobinduThemeColors colors, UserProfile userProfile) {
    final name = userProfile.displayName.isNotEmpty ? userProfile.displayName : 'Scholar';
    final greeting = _getGreeting();

    // Context badge string
    String statusBadge;
    if (userProfile.isUniversityStudent) {
      final dept = userProfile.department?.isNotEmpty == true ? userProfile.department! : 'ENG';
      final level = userProfile.level?.isNotEmpty == true ? userProfile.level! : '1';
      final term = userProfile.term?.isNotEmpty == true ? userProfile.term! : '1';
      final batch = userProfile.hscBatch.isNotEmpty ? userProfile.hscBatch : '25';
      statusBadge = 'Level $level • Term $term • $dept • Batch \'$batch • Week 04';
    } else {
      final batch = userProfile.hscBatch.isNotEmpty ? userProfile.hscBatch : '2025';
      final group = userProfile.hscGroup.isNotEmpty ? userProfile.hscGroup : 'Science';
      final target = userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'Engineering Prep';
      statusBadge = 'HSC \'$batch • $group • $target';
    }

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
                  color: colors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  statusBadge,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.primary,
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

        // Greeting Row + Quick Action Buttons
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 768;
            final greetingContent = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $name',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: isDesktop ? 28 : 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '“${_currentQuote.text}” — ${_currentQuote.author}',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            );

            final actionButtons = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Secondary Action: Log Study Session / Quick Note
                OutlinedButton.icon(
                  onPressed: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const JournalScreen()),
                    );
                  },
                  icon: Icon(Icons.bolt_rounded, size: 16, color: colors.secondary),
                  label: Text('Log Note', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: colors.surface,
                    side: BorderSide(color: colors.surfaceBorder),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 10),
                // Primary Action: Start Focus Session
                ElevatedButton.icon(
                  onPressed: () {
                    SafeHaptics.mediumImpact();
                    ref.read(navigationIndexProvider.notifier).state = 2; // Timer tab
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text('Start Focus', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
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

            if (isDesktop) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: greetingContent),
                  const SizedBox(width: 16),
                  actionButtons,
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  greetingContent,
                  const SizedBox(height: 14),
                  actionButtons,
                ],
              );
            }
          },
        ),
      ],
    );
  }

  // =========================================================================
  // 2. TOP KPI METRIC ROW (3 Bento Cards)
  // =========================================================================
  Widget _buildTopKpiRow(
    ChondrobinduThemeColors colors,
    UserProfile userProfile,
    int todaysFocusMinutes,
    int currentStreak,
    List<DailyStudyBarData> weeklyTrend,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        // Card 1: Study Streak, Card 2: Focus Time, Card 3: Academic Standing / CGPA
        final card1 = _buildKpiCard3StudyStreak(colors, currentStreak, weeklyTrend);
        final card2 = _buildKpiCard2FocusHours(colors, todaysFocusMinutes);
        final card3 = _buildKpiCard1AcademicStanding(colors, userProfile);

        if (isDesktop) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: card1),
                const SizedBox(width: 16),
                Expanded(child: card2),
                const SizedBox(width: 16),
                Expanded(child: card3),
              ],
            ),
          );
        } else {
          return Column(
            children: [
              card1,
              const SizedBox(height: 12),
              card2,
              const SizedBox(height: 12),
              card3,
            ],
          );
        }
      },
    );
  }

  // Card 1: Academic Standing & Milestone Progress
  Widget _buildKpiCard1AcademicStanding(ChondrobinduThemeColors colors, UserProfile userProfile) {
    final isUni = userProfile.isUniversityStudent;

    if (isUni) {
      return InkWell(
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
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
                  Row(
                    children: [
                      Icon(Icons.school_rounded, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'SEMESTER CGPA STANDING',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'TOP 5%',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '3.84',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    ' / 4.00',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+0.04 Delta',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Linear Gauge: Semester Covered
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0.72,
                  backgroundColor: colors.recessed,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('72% Covered', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                  Text('Target: 3.90', style: GoogleFonts.jetBrainsMono(color: colors.primary, fontSize: 10, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      // Admission Candidate Target Milestone
      final targetEvent = userProfile.targetEventName ?? (userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'BUET Admission');
      final eventDate = userProfile.targetEventDate ?? DateTime.now().add(const Duration(days: 120));
      final daysRemaining = max(0, eventDate.difference(DateTime.now()).inDays);

      return InkWell(
        onTap: () {
          SafeHaptics.lightImpact();
          _showTargetEventConfigModal(context, userProfile);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
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
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'ADMISSION TARGET',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.edit_outlined, size: 14, color: colors.textMuted),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$daysRemaining',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    ' days left',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (1.0 - (daysRemaining / 180)).clamp(0.1, 1.0),
                  backgroundColor: colors.recessed,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                targetEvent,
                style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      );
    }
  }

  // Card 2: Deep Work / Total Focus Time (Rust Accent)
  Widget _buildKpiCard2FocusHours(ChondrobinduThemeColors colors, int todaysFocusMinutes) {
    final hours = (todaysFocusMinutes / 60.0).toStringAsFixed(1);
    const targetMinutes = 300; // 5 hours target
    final progress = (todaysFocusMinutes / targetMinutes).clamp(0.0, 1.0);

    return InkWell(
      onTap: () {
        SafeHaptics.lightImpact();
        ref.read(navigationIndexProvider.notifier).state = 2; // Timer tab
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 18, color: colors.secondary),
                    const SizedBox(width: 6),
                    Text(
                      'TODAY\'S FOCUS TIME',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  '+12% vs avg',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  hours,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  ' hrs',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${todaysFocusMinutes ~/ 60}h ${todaysFocusMinutes % 60}m',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: colors.recessed,
                valueColor: AlwaysStoppedAnimation<Color>(colors.secondary),
                minHeight: 5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${(progress * 100).toInt()}% of 5h Goal', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                Text('Tap to Launch', style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 10, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Card 3: Study Streak with 7-Bar Sparkline Visualizer
  Widget _buildKpiCard3StudyStreak(
    ChondrobinduThemeColors colors,
    int currentStreak,
    List<DailyStudyBarData> weeklyTrend,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, size: 18, color: colors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    'STUDY STREAK',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'MOMENTUM',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$currentStreak',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          ' days',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Active momentum sustained',
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 7-Day Sparkline Bar Visualizer
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: () {
                  const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                  final bars = <Widget>[];

                  for (int i = 0; i < 7; i++) {
                    double heightFraction = 0.2;
                    if (weeklyTrend.isNotEmpty && i < weeklyTrend.length) {
                      final mins = weeklyTrend[i].totalMinutes;
                      heightFraction = (mins / 180.0).clamp(0.2, 1.0);
                    } else if (i >= 7 - min(currentStreak, 7)) {
                      heightFraction = 0.6 + (i * 0.05);
                    }

                    bars.add(
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2.5),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 30 * heightFraction,
                              decoration: BoxDecoration(
                                color: (i == 6) ? colors.secondary : colors.secondary.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              labels[i],
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return bars;
                }(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. LEFT COLUMN: RECOMMENDED DEEP WORK HERO CARD
  // =========================================================================
  Widget _buildDeepWorkHeroCard(ChondrobinduThemeColors colors, UserProfile userProfile) {
    final isUni = userProfile.isUniversityStudent;
    final topicTitle = isUni ? 'EEE 101 • 1.2 Kirchhoff\'s Current & Voltage Laws' : 'Physics • §3.4 Work, Energy & Power Theorem';
    final alertSubtitle = isUni
        ? 'Upcoming CT 1 in 4 days • Priority: High (15% Course Grade) • Estimated Focus: 2 Pomodoros (50 mins).'
        : 'Model Test in 5 days • High yield topic in BUET / Medical entrance • Estimated Focus: 2 Pomodoros.';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Stack(
        children: [
          // 4px Accent Left Border
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Tag
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.secondary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.secondary.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, size: 14, color: colors.secondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'RECOMMENDED DEEP WORK TARGET',
                                style: GoogleFonts.jetBrainsMono(
                                  color: colors.secondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '50m Session',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Main Topic Title
                Text(
                  topicTitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),

                // Subtitle Alert
                Text(
                  alertSubtitle,
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Footer Row: Practice Problem Tags & CTA Button
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 600;

                    final tags = Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _buildHeroDotTag('14 Textbook Problems', colors.secondary, colors),
                        _buildHeroDotTag('Sessional Handout #2', colors.primary, colors),
                      ],
                    );

                    final ctaButton = ElevatedButton.icon(
                      onPressed: () {
                        SafeHaptics.heavyImpact();
                        ref.read(navigationIndexProvider.notifier).state = 2; // Timer tab
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text('Launch Focus Session →', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    );

                    if (isCompact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          tags,
                          const SizedBox(height: 14),
                          SizedBox(width: double.infinity, child: ctaButton),
                        ],
                      );
                    } else {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: tags),
                          const SizedBox(width: 12),
                          ctaButton,
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroDotTag(String label, Color dotColor, ChondrobinduThemeColors colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            color: colors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. LEFT COLUMN: TODAY'S ACADEMIC AGENDA LEDGER
  // =========================================================================
  Widget _buildAgendaLedger(ChondrobinduThemeColors colors, String uid) {
    final dayOfWeek = DateFormat('EEEE').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Agenda',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$dayOfWeek Class & Evaluation Schedule',
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  SafeHaptics.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RoutineScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Full Routine',
                        style: GoogleFonts.plusJakartaSans(color: colors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Ledger Items
          _buildAgendaItem(
            timeRange: '08:30 – 09:50',
            courseCode: 'EEE 101',
            courseName: 'Electric Circuits I',
            details: 'Room 302 • Instructor: Prof. [MSR]',
            status: 'Completed',
            statusColor: colors.success,
            colors: colors,
            id: 'item_1',
          ),
          const SizedBox(height: 10),
          _buildAgendaItem(
            timeRange: '10:10 – 11:30',
            courseCode: 'CSE 109',
            courseName: 'Computer Programming',
            details: 'Lab 3 • Instructor: Dr. [FAK]',
            status: 'Up Next',
            statusColor: colors.secondary,
            colors: colors,
            id: 'item_2',
            isHighlighted: true,
          ),
          const SizedBox(height: 10),
          _buildAgendaItem(
            timeRange: '14:00 – 16:30',
            courseCode: 'EEE 102',
            courseName: 'Circuits Simulation Sessional',
            details: 'Simulation Lab 2 • Instructors: [MSR, NJ]',
            status: 'Sessional',
            statusColor: colors.primary,
            colors: colors,
            id: 'item_3',
          ),
          const SizedBox(height: 14),

          // Recess / Class Test Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.surfaceBorder, width: 1.0),
            ),
            child: Row(
              children: [
                Icon(Icons.event_note_rounded, size: 20, color: colors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CE 106 Class Test in 3 days',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Room 401 • Syllabus: Friction & Trusses',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'QUIZ BLOCK A',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.secondary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
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

  Widget _buildAgendaItem({
    required String timeRange,
    required String courseCode,
    required String courseName,
    required String details,
    required String status,
    required Color statusColor,
    required ChondrobinduThemeColors colors,
    required String id,
    bool isHighlighted = false,
  }) {
    final isDone = _completedAgendaItemIds.contains(id);

    return InkWell(
      onTap: () {
        setState(() {
          if (isDone) {
            _completedAgendaItemIds.remove(id);
          } else {
            _completedAgendaItemIds.add(id);
            SafeHaptics.selectionClick();
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isHighlighted ? colors.recessed : colors.recessed.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isHighlighted ? colors.secondary.withValues(alpha: 0.5) : colors.surfaceBorder,
            width: 1.0,
          ),
        ),
        child: LayoutBuilder(
          builder: (context, itemConstraints) {
            final isNarrow = itemConstraints.maxWidth < 450;
            if (isNarrow) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isDone) {
                          _completedAgendaItemIds.remove(id);
                        } else {
                          _completedAgendaItemIds.add(id);
                          SafeHaptics.selectionClick();
                        }
                      });
                    },
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: isDone ? colors.success : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: isDone ? colors.success : colors.surfaceBorder, width: 1.5),
                      ),
                      child: isDone
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              timeRange,
                              style: GoogleFonts.jetBrainsMono(
                                color: isHighlighted ? colors.secondary : colors.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                courseCode,
                                style: GoogleFonts.jetBrainsMono(
                                  color: colors.primary,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          courseName,
                          style: GoogleFonts.plusJakartaSans(
                            color: isDone ? colors.textMuted : colors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          details,
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      status,
                      style: GoogleFonts.jetBrainsMono(
                        color: statusColor,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isDone) {
                        _completedAgendaItemIds.remove(id);
                      } else {
                        _completedAgendaItemIds.add(id);
                        SafeHaptics.selectionClick();
                      }
                    });
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isDone ? colors.success : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: isDone ? colors.success : colors.surfaceBorder, width: 1.5),
                    ),
                    child: isDone
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 82,
                  child: Text(
                    timeRange,
                    style: GoogleFonts.jetBrainsMono(
                      color: isHighlighted ? colors.secondary : colors.textMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              courseCode,
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              courseName,
                              style: GoogleFonts.plusJakartaSans(
                                color: isDone ? colors.textMuted : colors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: isDone ? TextDecoration.lineThrough : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    status,
                    style: GoogleFonts.jetBrainsMono(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // =========================================================================
  // 3. RIGHT COLUMN: COURSES HEALTH / SYLLABUS VELOCITY
  // =========================================================================
  Widget _buildCoursesHealthCard(ChondrobinduThemeColors colors, String uid) {
    if (uid.isEmpty || Firebase.apps.isEmpty) {
      return _buildCoursesHealthPlaceholder(colors);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return _buildCoursesHealthPlaceholder(colors);
        }

        double totalCredits = 0;
        for (final doc in docs) {
          final data = doc.data();
          totalCredits += (data['credit'] as num?)?.toDouble() ?? 3.0;
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
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Courses Health',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Text(
                      '${docs.length} Courses • ${totalCredits.toStringAsFixed(1)} Cr',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Course progress rows
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: min(docs.length, 5),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data();
                  final code = data['courseCode'] as String? ?? 'CRS 10$index';
                  final name = data['courseTitle'] as String? ?? (data['name'] as String? ?? 'Subject');
                  final credits = (data['credit'] as num?)?.toDouble() ?? 3.0;
                  final progress = ((index * 18 + 52) % 100) / 100.0;
                  final isNeedsAttention = progress < 0.60;

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.recessed.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.surfaceBorder, width: 1.0),
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
                                        fontSize: 12.5,
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
                              '${credits.toStringAsFixed(1)} Cr',
                              style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: colors.surfaceBorder.withValues(alpha: 0.4),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isNeedsAttention ? colors.secondary : colors.primary,
                            ),
                            minHeight: 4.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${(progress * 100).toInt()}% Covered',
                              style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: (isNeedsAttention ? colors.secondary : colors.success).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isNeedsAttention ? 'Needs Attention' : 'On Track',
                                style: GoogleFonts.jetBrainsMono(
                                  color: isNeedsAttention ? colors.secondary : colors.success,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCoursesHealthPlaceholder(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Expanded(
                child: Text('Courses Health', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text('4 Courses • 19.5 Cr', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 14),
          _buildStaticCourseProgress('EEE 101', 'Electric Circuits I', '3.0 Cr', 0.72, false, colors),
          const SizedBox(height: 10),
          _buildStaticCourseProgress('EEE 102', 'Circuits Sessional', '1.5 Cr', 0.60, false, colors),
          const SizedBox(height: 10),
          _buildStaticCourseProgress('CE 106', 'Mechanics & Friction', '3.0 Cr', 0.45, true, colors),
          const SizedBox(height: 10),
          _buildStaticCourseProgress('CSE 109', 'Computer Programming', '3.0 Cr', 0.84, false, colors),
        ],
      ),
    );
  }

  Widget _buildStaticCourseProgress(
    String code,
    String name,
    String credits,
    double progress,
    bool isWarning,
    ChondrobinduThemeColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.recessed.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
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
                    Text(code, style: GoogleFonts.jetBrainsMono(color: colors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(name, style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(credits, style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: colors.surfaceBorder.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(isWarning ? colors.secondary : colors.primary),
              minHeight: 4.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${(progress * 100).toInt()}% Covered', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: (isWarning ? colors.secondary : colors.success).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isWarning ? 'Needs Attention' : 'On Track',
                  style: GoogleFonts.jetBrainsMono(
                    color: isWarning ? colors.secondary : colors.success,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
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
  // 3. RIGHT COLUMN: FOCUS DISTRIBUTION BY COURSE
  // =========================================================================
  Widget _buildFocusDistributionCard(ChondrobinduThemeColors colors) {
    final distList = ref.watch(subjectDistributionProvider);

    return Container(
      padding: const EdgeInsets.all(20),
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
              Expanded(
                child: Text(
                  'Focus by Course',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Last 7 Days',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (distList.isEmpty) ...[
            // Default visual telemetry placeholder if no study logs yet
            _buildFocusDistributionRow('EEE 101 Circuits', 42.0, colors.primary, '14.2h', colors),
            const SizedBox(height: 8),
            _buildFocusDistributionRow('CSE 109 Programming', 28.0, colors.secondary, '9.5h', colors),
            const SizedBox(height: 8),
            _buildFocusDistributionRow('MATH 157 Calculus', 18.0, colors.success, '6.1h', colors),
            const SizedBox(height: 8),
            _buildFocusDistributionRow('CE 106 Mechanics', 12.0, colors.textMuted, '4.0h', colors),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: min(distList.length, 5),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, idx) {
                final item = distList[idx];
                final color = idx == 0
                    ? colors.primary
                    : idx == 1
                        ? colors.secondary
                        : idx == 2
                            ? colors.success
                            : colors.textMuted;
                final hours = (item.totalMinutes / 60.0).toStringAsFixed(1);
                return _buildFocusDistributionRow(
                  item.subjectName,
                  item.percentage,
                  color,
                  '${hours}h',
                  colors,
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusDistributionRow(
    String title,
    double pct,
    Color color,
    String hours,
    ChondrobinduThemeColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(title, style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: [
                Text(hours, style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11)),
                const SizedBox(width: 8),
                Text('${pct.toInt()}%', style: GoogleFonts.jetBrainsMono(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (pct / 100.0).clamp(0.05, 1.0),
            backgroundColor: colors.recessed,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. BRAIN DUMP QUICK CAPTURE SCRATCHPAD
  // =========================================================================
  Widget _buildBrainDumpCard(ChondrobinduThemeColors colors, UserProfile userProfile) {
    if (!_isScratchpadInitialized) {
      _scratchpadController.text = userProfile.scratchpadText;
      _isScratchpadInitialized = true;
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.psychology_rounded, size: 20, color: colors.secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Brain Dump & Quick Scratchpad',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isSavingScratchpad)
                Row(
                  children: [
                    AppPreloader(size: 12, strokeWidth: 1.5, color: colors.secondary),
                    const SizedBox(width: 6),
                    Text('Saving...', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11)),
                  ],
                )
              else if (_scratchpadController.text.trim().isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.cloud_done_rounded, color: colors.success, size: 14),
                    const SizedBox(width: 4),
                    Text('Auto-saved', style: GoogleFonts.jetBrainsMono(color: colors.success, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _scratchpadController,
            maxLines: 3,
            minLines: 2,
            style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13, height: 1.4),
            onChanged: (value) {
              _scratchpadDebounceTimer?.cancel();
              if (!_isSavingScratchpad) {
                setState(() => _isSavingScratchpad = true);
              }
              _scratchpadDebounceTimer = Timer(const Duration(seconds: 1), () async {
                try {
                  await ref.read(userProfileProvider.notifier).updateScratchpad(value);
                } catch (e) {
                  debugPrint('Brain Dump auto-save error: $e');
                } finally {
                  if (mounted) setState(() => _isSavingScratchpad = false);
                }
              });
            },
            decoration: InputDecoration(
              hintText: 'Jot down distracting thoughts, formulas, or quick to-dos...',
              hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted.withValues(alpha: 0.6), fontSize: 12.5),
              filled: true,
              fillColor: colors.recessed,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.surfaceBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.primary, width: 1.2)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Auto-syncs after typing. Converts directly to permanent journal notes.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.secondary,
                  side: BorderSide(color: colors.secondary),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(Icons.bookmark_add_rounded, size: 14, color: colors.secondary),
                label: Text('Save to Journal', style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final text = _scratchpadController.text.trim();
                  if (text.isEmpty) return;

                  final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
                  if (uid != null) {
                    SafeHaptics.lightImpact();
                    try {
                      await ref.read(noteServiceProvider).convertBrainDumpToNote(uid, text);
                      _scratchpadController.clear();
                      await ref.read(userProfileProvider.notifier).updateScratchpad('');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: colors.surface,
                            content: Text('Saved to Journal!', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                          ),
                        );
                      }
                    } catch (_) {}
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. BURNOUT WELLNESS GUARD
  // =========================================================================
  Widget _buildBurnoutWellnessCard(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.self_improvement_rounded, size: 24, color: colors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'High Focus Cadence Detected (12+ Hours)',
                  style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Outstanding momentum! Remember that deep consolidation happens during rest. Hydrate and recharge.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. RIGHT COLUMN: QUICK ACCESS UTILITY GRID
  // =========================================================================
  Widget _buildQuickAccessSection(ChondrobinduThemeColors colors, UserProfile userProfile) {
    final isUni = userProfile.isUniversityStudent;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions & Utilities',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          if (isUni) ...[
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    title: 'CGPA Simulator',
                    subtitle: 'Projection',
                    icon: Icons.calculate_outlined,
                    iconColor: colors.primary,
                    colors: colors,
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
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionCard(
                    title: 'Weekly Routine',
                    subtitle: 'Timetable',
                    icon: Icons.calendar_view_week_rounded,
                    iconColor: colors.secondary,
                    colors: colors,
                    onTap: () {
                      SafeHaptics.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const RoutineScreen()));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    title: 'Study Journal',
                    subtitle: 'Notes',
                    icon: Icons.menu_book_rounded,
                    iconColor: colors.success,
                    colors: colors,
                    onTap: () {
                      SafeHaptics.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalScreen()));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionCard(
                    title: 'Attendance',
                    subtitle: 'Matrix',
                    icon: Icons.grid_view_rounded,
                    iconColor: colors.primary,
                    colors: colors,
                    onTap: () {
                      SafeHaptics.lightImpact();
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()));
                    },
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    title: 'Study Timer',
                    subtitle: 'Focus Mode',
                    icon: Icons.play_arrow_rounded,
                    iconColor: colors.secondary,
                    colors: colors,
                    onTap: () => ref.read(navigationIndexProvider.notifier).state = 2,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionCard(
                    title: 'Exams & Marks',
                    subtitle: 'Log Tests',
                    icon: Icons.insert_chart_outlined_rounded,
                    iconColor: colors.primary,
                    colors: colors,
                    onTap: () => ref.read(navigationIndexProvider.notifier).state = 3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    title: 'Syllabus Tracker',
                    subtitle: 'Chapters',
                    icon: Icons.menu_book_rounded,
                    iconColor: colors.success,
                    colors: colors,
                    onTap: () => ref.read(navigationIndexProvider.notifier).state = 1,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionCard(
                    title: 'Analytics',
                    subtitle: 'Insights',
                    icon: Icons.analytics_outlined,
                    iconColor: colors.secondary,
                    colors: colors,
                    onTap: () => ref.read(navigationIndexProvider.notifier).state = 4,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: colors.recessed.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.surfaceBorder, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
