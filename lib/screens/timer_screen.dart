import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart';
import '../models/study_session_model.dart';
import '../models/syllabus_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/timer_provider.dart';
import '../providers/timer_subjects_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/nav_provider.dart';
import '../services/notification_service.dart';
import '../services/soundscape_service.dart';
import '../widgets/auto_scroll_marquee_text.dart';
import '../widgets/study_session_log_dialog.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/tour_service.dart';
import '../widgets/tour_coach_mark.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Focus Study Timer & Pomodoro Screen with "Desk Clock" Landscape StandBy Mode
/// and breathing pulse animation with global haptic micro-interactions.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key});

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Desktop Suite & Ambient Soundscape State
  final TextEditingController _desktopScratchpadController = TextEditingController();
  final Set<String> _selectedDesktopTopics = {};
  final Map<String, bool> _expandedChapters = {};
  final SoundscapeService _soundscapeService = SoundscapeService();
  bool _soundEnabled = false;
  String _selectedSoundscape = 'Rainfall';
  int _targetCycles = 5;

  // Onboarding Tour Keys
  final GlobalKey _keyTimerDial = GlobalKey();
  final GlobalKey _keyTimerMode = GlobalKey();
  bool _hasTriggeredTimerTour = false;

  void _triggerTimerTourIfNeeded(BuildContext showcaseContext) {
    final currentTab = ref.read(navigationIndexProvider);
    if (currentTab != 2 || _hasTriggeredTimerTour) return;
    triggerTourSafely(
      context: showcaseContext,
      section: TourSection.timer,
      keys: [_keyTimerDial, _keyTimerMode],
      onStarted: () => _hasTriggeredTimerTour = true,
      onSkippedOrEmpty: () => _hasTriggeredTimerTour = false,
    );
  }

  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;
  bool _isPostSessionDialogOpen = false;

  ChondrobinduThemeColors get colors => AppColors.of(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Request Android 13+ notification permissions when timer screen opens
    NotificationService().requestPermissions();

    // Synchronize UI with persistent audio service
    _soundEnabled = _soundscapeService.isPlaying;
    if (_soundscapeService.isPlaying) {
      _selectedSoundscape = SoundscapeService.toLabel(_soundscapeService.currentTrack);
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.045).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.40).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _desktopScratchpadController.dispose();
    super.dispose();
  }

  /// Lifecycle observation: Authoritative wall-clock sync when tab wakes or app resumes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final timerState = ref.read(timerProvider);

    if (state == AppLifecycleState.resumed) {
      if (timerState.status == TimerStatus.running) {
        ref.read(timerProvider.notifier).syncUi();
        if (mounted) {
          setState(() {});
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(navigationIndexProvider);
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final timerSubjects = ref.watch(timerSubjectsProvider);

    final isBreak = timerState.mode == TimerMode.breakTime;
    final isRunning = timerState.status == TimerStatus.running;
    final isPaused = timerState.status == TimerStatus.paused;
    final isInitial = timerState.status == TimerStatus.initial;

    // Subtle Breathing / Pulse Animation ONLY runs when Timer is Running
    if (isRunning) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating || _pulseController.value != 0.0) {
        _pulseController.animateTo(0.0, duration: const Duration(milliseconds: 300));
      }
    }

    // Resolve course & syllabus bindings
    final courses = (ref.watch(coursesStreamProvider).valueOrNull ?? []).where((c) => !c.isArchived).toList();
    final currentSubject = timerSubjects.contains(timerState.selectedSubject)
        ? timerState.selectedSubject
        : (timerSubjects.isNotEmpty ? timerSubjects.first : 'General Study');

    Course? selectedCourse;
    if (timerState.selectedCourseId != null && timerState.selectedCourseId!.isNotEmpty) {
      for (final c in courses) {
        if (c.id == timerState.selectedCourseId) {
          selectedCourse = c;
          break;
        }
      }
    }
    if (selectedCourse == null) {
      for (final c in courses) {
        if (c.title.toLowerCase() == currentSubject.toLowerCase() ||
            c.code.toLowerCase() == currentSubject.toLowerCase() ||
            currentSubject.toLowerCase().startsWith('${c.code.toLowerCase()}:')) {
          selectedCourse = c;
          break;
        }
      }
    }
    if (selectedCourse == null && courses.isNotEmpty && !timerSubjects.contains(currentSubject)) {
      selectedCourse = courses.first;
    }

    List<SyllabusTopic> liveTopics = [];
    if (selectedCourse != null) {
      liveTopics = ref.watch(syllabusTopicsStreamProvider(selectedCourse.id)).valueOrNull ?? [];
    }

    String? selectedTopicTitle;
    final activeTopicId = timerState.selectedTopicId ?? (_selectedDesktopTopics.isNotEmpty ? _selectedDesktopTopics.first : null);
    if (activeTopicId != null && activeTopicId.isNotEmpty) {
      if (activeTopicId.startsWith('chapter:')) {
        selectedTopicTitle = activeTopicId.replaceFirst('chapter:', '');
      } else {
        for (final t in liveTopics) {
          if (t.id == activeTopicId || t.topicIndex == activeTopicId) {
            selectedTopicTitle = t.title;
            break;
          }
          for (final sub in t.subtopics) {
            if (sub.id == activeTopicId || '${t.id}:${sub.id}' == activeTopicId || sub.subtopicIndex == activeTopicId) {
              selectedTopicTitle = '${t.topicIndex} > ${sub.title}';
              break;
            }
          }
          if (selectedTopicTitle != null) break;
        }
      }
      selectedTopicTitle ??= activeTopicId;
    }

    final isDesktopWide = MediaQuery.of(context).size.width >= 800;
    if (isDesktopWide) {
      return _buildDesktopSuite(
        context,
        ref,
        timerState,
        timerNotifier,
        timerSubjects,
        courses,
        selectedCourse,
        liveTopics,
        selectedTopicTitle,
        currentSubject,
        isBreak,
        isRunning,
        isPaused,
        isInitial,
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        if (orientation == Orientation.landscape) {
          return _buildLandscapeDeskClock(
            context,
            ref,
            timerState,
            timerNotifier,
            currentSubject,
            isBreak,
            isRunning,
            isPaused,
          );
        }

        return _buildPortraitTimer(
          context,
          ref,
          timerState,
          timerNotifier,
          timerSubjects,
          courses,
          selectedCourse,
          liveTopics,
          selectedTopicTitle,
          currentSubject,
          isBreak,
          isRunning,
          isPaused,
          isInitial,
        );
      },
    );
  }

  // =========================================================================
  // 1. DESKTOP SUITE (Width >= 800px)
  // =========================================================================
  Widget _buildDesktopSuite(
    BuildContext context,
    WidgetRef ref,
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    List<Course> courses,
    Course? selectedCourse,
    List<SyllabusTopic> liveTopics,
    String? selectedTopicTitle,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
    bool isInitial,
  ) {
    final isStopwatch = timerState.timerType == TimerType.stopwatch;
    final elapsedSec = timerState.elapsedSeconds;
    final stopwatchProgress = (elapsedSec % 1800) / 1800.0;
    final dialProgress = isStopwatch
        ? (timerState.status == TimerStatus.initial ? 0.0 : stopwatchProgress)
        : (isBreak ? 1.0 : timerState.progressRatio);

    final userProfile = ref.watch(userProfileProvider);
    String statusContext;
    if (userProfile.isUniversityStudent) {
      final dept = userProfile.department?.isNotEmpty == true ? userProfile.department! : 'ENG';
      final level = userProfile.level?.isNotEmpty == true ? userProfile.level! : '1';
      final term = userProfile.term?.isNotEmpty == true ? userProfile.term! : '1';
      statusContext = 'TERM $level.$term • $dept';
    } else {
      final batch = userProfile.hscBatch.isNotEmpty ? userProfile.hscBatch : '2025';
      final group = userProfile.hscGroup.isNotEmpty ? userProfile.hscGroup : 'Science';
      statusContext = 'HSC \'$batch • ${group.toUpperCase()}';
    }

    final todaySessionsAsync = ref.watch(todayStudySessionsStreamProvider);
    final todaySessions = todaySessionsAsync.value ?? [];

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
                // Top Ribbon & Status Header
                _buildDesktopTopRibbon(statusContext, isBreak, isRunning, isPaused),
                const SizedBox(height: 20),

                // 3-Column Studio Grid Layout (320px - Flex Center - 320px)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Column 1: Target Context Panel
                    SizedBox(
                      width: 320,
                      child: _buildDesktopTargetSelection(
                        timerState,
                        timerNotifier,
                        timerSubjects,
                        courses,
                        selectedCourse,
                        liveTopics,
                        currentSubject,
                        todaySessions.length,
                        selectedTopicTitle: selectedTopicTitle,
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Column 2: Center Hero Timer Dial
                    Expanded(
                      child: _buildDesktopCenterDial(
                        timerState,
                        timerNotifier,
                        currentSubject,
                        isBreak,
                        isRunning,
                        isPaused,
                        isStopwatch,
                        dialProgress,
                        selectedCourse: selectedCourse,
                        selectedTopicTitle: selectedTopicTitle,
                        todaySessionsCount: todaySessions.length,
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Column 3: Session Matrix & Live Output
                    SizedBox(
                      width: 320,
                      child: _buildDesktopSessionSummary(timerState, todaySessions),
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

  Widget _buildDesktopTopRibbon(
    String statusContext,
    bool isBreak,
    bool isRunning,
    bool isPaused,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Breadcrumbs & Status Tags
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'DEEP WORK STUDIO',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.secondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('•', style: TextStyle(color: colors.surfaceBorder, fontSize: 16)),
              const SizedBox(width: 10),
              Text(
                'SYNCHRONIZED TO $statusContext',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 10),
              Text('•', style: TextStyle(color: colors.surfaceBorder, fontSize: 16)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Text(
                  isBreak
                      ? 'BREAK IN PROGRESS'
                      : (isRunning ? 'ACTIVE SESSION' : (isPaused ? 'SESSION PAUSED' : 'STUDIO READY')),
                  style: GoogleFonts.jetBrainsMono(
                    color: isBreak ? colors.success : (isRunning ? colors.primary : colors.textMuted),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          // Ambient Soundscape Quick Button & Status
          Row(
            children: [
              InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  final track = SoundscapeService.fromLabel(_selectedSoundscape);
                  final willPlay = !_soundEnabled;
                  setState(() => _soundEnabled = willPlay);
                  if (willPlay) {
                    _soundscapeService.play(track);
                  } else {
                    _soundscapeService.stop();
                  }
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: colors.surface,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colors.surfaceBorder),
                      ),
                      duration: const Duration(seconds: 2),
                      content: Row(
                        children: [
                          Icon(Icons.water_drop_rounded, size: 16, color: colors.secondary),
                          const SizedBox(width: 8),
                          Text(
                            willPlay
                                ? 'Soundscape: $_selectedSoundscape enabled'
                                : 'Soundscape muted',
                            style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _soundEnabled ? colors.secondary.withValues(alpha: 0.15) : colors.recessed,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _soundEnabled ? colors.secondary : colors.surfaceBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _soundEnabled ? Icons.water_drop_rounded : Icons.water_drop_outlined,
                        size: 15,
                        color: _soundEnabled ? colors.secondary : colors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _soundEnabled
                            ? 'Soundscapes: [$_selectedSoundscape] [ON]'
                            : 'Soundscapes: [OFF]',
                        style: GoogleFonts.jetBrainsMono(
                          color: _soundEnabled ? colors.secondary : colors.textMuted,
                          fontSize: 11,
                          fontWeight: _soundEnabled ? FontWeight.bold : FontWeight.w500,
                        ),
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

  Widget _buildDesktopTargetSelection(
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    List<Course> courses,
    Course? selectedCourse,
    List<SyllabusTopic> liveTopics,
    String currentSubject,
    int todaySessionsCount, {
    String? selectedTopicTitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.adjust_rounded, color: colors.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Target Context',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'BLOCK 0${(todaySessionsCount % 5) + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Enrolled Course Label
          Text(
            'ENROLLED COURSE',
            style: GoogleFonts.jetBrainsMono(
              color: colors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),

          // 48px Height Course Dropdown Container
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: (selectedCourse != null)
                    ? selectedCourse.id
                    : (timerSubjects.contains(currentSubject) ? currentSubject : null),
                isExpanded: true,
                dropdownColor: colors.surface,
                icon: Icon(Icons.unfold_more_rounded, color: colors.textMuted, size: 18),
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: [
                  ...courses.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Text(
                              c.code,
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                c.title,
                                style: GoogleFonts.plusJakartaSans(
                                  color: colors.textPrimary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )),
                  if (courses.isEmpty)
                    ...timerSubjects.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 12.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  SafeHaptics.selectionClick();
                  Course? match;
                  for (final c in courses) {
                    if (c.id == val) {
                      match = c;
                      break;
                    }
                  }
                  if (match != null) {
                    timerNotifier.changeSubject(match.title);
                    timerNotifier.setSelectedCourseAndTopic(
                      courseId: match.id,
                      courseCode: match.code,
                      topicId: null,
                    );
                    setState(() {
                      _selectedDesktopTopics.clear();
                    });
                  } else {
                    timerNotifier.changeSubject(val);
                    timerNotifier.setSelectedCourseAndTopic(
                      courseId: null,
                      courseCode: val,
                      topicId: null,
                    );
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Linked Syllabus Topics Checklist Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LINKED SYLLABUS TOPIC',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 8),
              if (selectedTopicTitle != null || liveTopics.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      selectedTopicTitle ??
                          (liveTopics.first.chapterTitle.isNotEmpty
                              ? liveTopics.first.chapterTitle.split(':').first
                              : 'Syllabus'),
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.primary,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Collapsible Syllabus Tree (Chapter -> Topic -> Subtopic) with 220px max height cap
          if (liveTopics.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _buildDesktopSyllabusTree(liveTopics, selectedCourse),
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        courses.isEmpty
                            ? 'No courses enrolled yet. Add courses in Courses tab.'
                            : 'No topics found for this course. Add topics in Courses & Syllabus.',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Scratchpad & Fleeting Thoughts Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SCRATCHPAD & THOUGHTS',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Icon(Icons.cloud_sync_outlined, size: 14, color: colors.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _desktopScratchpadController,
            maxLines: 3,
            style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Jot down formulas, derivations, or fleeting thoughts to preserve flow state...',
              hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
              filled: true,
              fillColor: colors.recessed,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.surfaceBorder, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.secondary, width: 1.2),
              ),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: 36,
                child: TextButton(
                  onPressed: () {
                    SafeHaptics.selectionClick();
                    _desktopScratchpadController.clear();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    'Clear',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () {
                    SafeHaptics.lightImpact();
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: colors.surface,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: colors.surfaceBorder),
                        ),
                        content: Text(
                          'Scratchpad saved to session notes.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12.5),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bookmark_added_rounded, size: 14),
                  label: Text('Save', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDesktopSyllabusTree(List<SyllabusTopic> topics, Course? course) {
    // Group topics by chapterTitle
    final Map<String, List<SyllabusTopic>> chapters = {};
    for (final t in topics) {
      final ch = t.chapterTitle.isNotEmpty ? t.chapterTitle : 'General';
      chapters.putIfAbsent(ch, () => []).add(t);
    }

    final activeTopicId = ref.watch(timerProvider).selectedTopicId;

    return chapters.entries.map((entry) {
      final chapterKey = entry.key;
      final chapterTopics = entry.value;
      final isExpanded = _expandedChapters[chapterKey] ?? true;
      final chapterId = 'chapter:$chapterKey';
      final isChapterSelected = _selectedDesktopTopics.contains(chapterId) || activeTopicId == chapterId;

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: colors.recessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isChapterSelected ? colors.secondary : colors.surfaceBorder,
            width: isChapterSelected ? 1.2 : 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level 1: Chapter Header (Expand/Collapse + Deep Selection)
            InkWell(
              onTap: () {
                SafeHaptics.selectionClick();
                setState(() {
                  _expandedChapters[chapterKey] = !isExpanded;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                      size: 16,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        chapterKey,
                        style: GoogleFonts.plusJakartaSans(
                          color: isChapterSelected ? colors.secondary : colors.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () {
                        SafeHaptics.selectionClick();
                        setState(() {
                          _selectedDesktopTopics.clear();
                          if (!isChapterSelected) {
                            _selectedDesktopTopics.add(chapterId);
                          }
                        });
                        ref.read(timerProvider.notifier).setSelectedCourseAndTopic(
                          courseId: course?.id,
                          courseCode: course?.code,
                          topicId: !isChapterSelected ? chapterId : null,
                          clearTopic: isChapterSelected,
                        );
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isChapterSelected
                              ? colors.secondary.withValues(alpha: 0.15)
                              : colors.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isChapterSelected ? colors.secondary : colors.surfaceBorder,
                          ),
                        ),
                        child: Text(
                          isChapterSelected ? 'Selected' : 'Select',
                          style: GoogleFonts.jetBrainsMono(
                            color: isChapterSelected ? colors.secondary : colors.textMuted,
                            fontSize: 9,
                            fontWeight: isChapterSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Level 2 & 3: Topics & Leaf Subtopics
            if (isExpanded) ...[
              Divider(height: 1, thickness: 0.8, color: colors.surfaceBorder),
              ...chapterTopics.map((t) => _buildTreeNodeTopic(t, course, activeTopicId)),
            ],
          ],
        ),
      );
    }).toList();
  }

  Widget _buildTreeNodeTopic(SyllabusTopic topic, Course? course, String? activeTopicId) {
    final isSelected = _selectedDesktopTopics.contains(topic.id) ||
        _selectedDesktopTopics.contains(topic.topicIndex) ||
        activeTopicId == topic.id ||
        activeTopicId == topic.topicIndex;
    final hasSubtopics = topic.hasSubtopics;
    final isSubExpanded = _expandedChapters['topic_${topic.id}'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            SafeHaptics.selectionClick();
            setState(() {
              _selectedDesktopTopics.clear();
              if (!isSelected) {
                _selectedDesktopTopics.add(topic.id);
              }
            });
            ref.read(timerProvider.notifier).setSelectedCourseAndTopic(
              courseId: course?.id,
              courseCode: course?.code,
              topicId: !isSelected ? topic.id : null,
              clearTopic: isSelected,
            );
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? colors.secondary : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? colors.secondary : colors.textMuted,
                      width: 1.2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.surface,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${topic.topicIndex} ${topic.title}',
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? colors.textPrimary : colors.textMuted,
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (topic.isCompleted)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.success,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (hasSubtopics)
                  InkWell(
                    onTap: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _expandedChapters['topic_${topic.id}'] = !isSubExpanded;
                      });
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        isSubExpanded ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded,
                        size: 18,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Level 3: Leaf Subtopics
        if (hasSubtopics && isSubExpanded)
          ...topic.subtopics.map((sub) {
            final subId = '${topic.id}:${sub.id}';
            final isSubSelected = _selectedDesktopTopics.contains(subId) ||
                _selectedDesktopTopics.contains(sub.id) ||
                activeTopicId == subId ||
                activeTopicId == sub.id;

            return InkWell(
              onTap: () {
                SafeHaptics.selectionClick();
                setState(() {
                  _selectedDesktopTopics.clear();
                  if (!isSubSelected) {
                    _selectedDesktopTopics.add(subId);
                  }
                });
                ref.read(timerProvider.notifier).setSelectedCourseAndTopic(
                  courseId: course?.id,
                  courseCode: course?.code,
                  topicId: !isSubSelected ? subId : null,
                  clearTopic: isSubSelected,
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 3, 8, 3),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSubSelected ? colors.secondary : colors.surfaceBorder,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${sub.subtopicIndex} ${sub.title}',
                        style: GoogleFonts.plusJakartaSans(
                          color: isSubSelected ? colors.secondary : colors.textMuted,
                          fontSize: 11,
                          fontWeight: isSubSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sub.isCompleted)
                      Text(
                        '✓',
                        style: TextStyle(color: colors.success, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildDesktopTopicTile(SyllabusTopic topic, Course? course) {
    final isSelected = _selectedDesktopTopics.contains(topic.id) ||
        _selectedDesktopTopics.contains(topic.topicIndex) ||
        ref.read(timerProvider).selectedTopicId == topic.id;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () {
          SafeHaptics.selectionClick();
          setState(() {
            _selectedDesktopTopics.clear();
            if (!isSelected) {
              _selectedDesktopTopics.add(topic.id);
            }
          });
          ref.read(timerProvider.notifier).setSelectedCourseAndTopic(
            courseId: course?.id,
            courseCode: course?.code,
            topicId: !isSelected ? topic.id : null,
            clearTopic: isSelected,
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.secondary.withValues(alpha: 0.12) : colors.recessed,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? colors.secondary : colors.surfaceBorder,
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? colors.secondary : colors.surfaceBorder,
                ),
                child: isSelected
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.surface,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${topic.topicIndex} ${topic.title}',
                      style: GoogleFonts.plusJakartaSans(
                        color: isSelected ? colors.textPrimary : colors.textMuted,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (topic.isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.success,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCenterDial(
    TimerState timerState,
    TimerNotifier timerNotifier,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
    bool isStopwatch,
    double dialProgress, {
    Course? selectedCourse,
    String? selectedTopicTitle,
    required int todaySessionsCount,
  }) {
    final targetFocusMins = timerState.targetMinutes;
    final shortBreakMins = (targetFocusMins / 5).round().clamp(1, 15);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode Toggle & Duration Presets Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Pill Toggle: [ Focus ] vs [ Stopwatch ]
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildPillToggleItem('Focus', !isStopwatch, () {
                      SafeHaptics.selectionClick();
                      timerNotifier.setTimerType(TimerType.target);
                    }),
                    _buildPillToggleItem('Stopwatch', isStopwatch, () {
                      SafeHaptics.selectionClick();
                      timerNotifier.setTimerType(TimerType.stopwatch);
                    }),
                  ],
                ),
              ),

              // Duration Presets (Focus mode only)
              if (!isStopwatch)
                _buildDurationPresetsRow(timerState, timerNotifier)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.recessed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Open-ended Count-up',
                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // 290px Hero Circular Gauge & Monospace Display
          SizedBox(
            width: 290,
            height: 290,
            child: CustomPaint(
              painter: TimerDialPainter(
                progress: dialProgress,
                isStopwatch: isStopwatch,
                primaryColor: isBreak ? colors.success : colors.secondary,
                trackColor: colors.surfaceBorder,
                dialFillColor: colors.recessed.withValues(alpha: 0.35),
                borderColor: colors.surfaceBorder,
                glowColor: isBreak
                    ? colors.success.withValues(alpha: 0.45)
                    : colors.secondary.withValues(alpha: 0.45),
                strokeWidth: 9.0,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Interval Block Header Tag
                    Text(
                      isBreak
                          ? 'EARNED REST // BREAK'
                          : (timerState.isOvertime
                              ? 'DEEP OVERTIME // ZONE'
                              : 'DEEP FOCUS // BLOCK 0${(todaySessionsCount % 5) + 1}'),
                      style: GoogleFonts.jetBrainsMono(
                        color: isBreak ? colors.success : (timerState.isOvertime ? colors.secondary : colors.textMuted),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Massive Digital Readout in JetBrains Mono
                    Text(
                      timerState.formattedTime,
                      style: GoogleFonts.jetBrainsMono(
                        color: isBreak
                            ? colors.success
                            : (timerState.isOvertime ? colors.secondary : colors.textPrimary),
                        fontSize: 50,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Structured Subtitle Pill
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.recessed,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isBreak ? colors.success : colors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: AutoScrollMarqueeText(
                                text: isBreak
                                    ? 'Break'
                                    : (timerState.isOvertime
                                        ? 'Overtime • Recording study time'
                                        : '${selectedCourse?.code ?? currentSubject} • ${selectedTopicTitle ?? 'Focus Session'}'),
                                style: GoogleFonts.plusJakartaSans(
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
                    const SizedBox(height: 6),
                    Text(
                      'Cycle ${(todaySessionsCount % 5) + 1} of 5 Planned',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Primary Playback Controls Row
          if (isBreak)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.success,
                    side: BorderSide(color: colors.success.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    SafeHaptics.selectionClick();
                    timerNotifier.skipBreak();
                  },
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text('Skip Break', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    SafeHaptics.mediumImpact();
                    timerNotifier.endSession();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text('End Session', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Soundscape quick indicator button
                IconButton(
                  tooltip: 'Soundscape settings',
                  icon: Icon(
                    _soundEnabled ? Icons.headphones_rounded : Icons.headphones_outlined,
                    color: _soundEnabled ? colors.secondary : colors.textMuted,
                    size: 22,
                  ),
                  onPressed: () {
                    SafeHaptics.selectionClick();
                    final track = SoundscapeService.fromLabel(_selectedSoundscape);
                    final willPlay = !_soundEnabled;
                    setState(() => _soundEnabled = willPlay);
                    if (willPlay) {
                      _soundscapeService.play(track);
                    } else {
                      _soundscapeService.stop();
                    }
                  },
                ),
                const SizedBox(width: 16),

                // Hero 64px Play / Pause Button
                GestureDetector(
                  onTap: () {
                    SafeHaptics.mediumImpact();
                    timerNotifier.toggleStartPause();
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.secondary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors.secondary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Log Session / Finish Button
                IconButton(
                  tooltip: 'Log Completed Session',
                  icon: Icon(
                    Icons.flag_rounded,
                    color: (isRunning || isPaused) ? colors.primary : colors.textMuted,
                    size: 22,
                  ),
                  onPressed: () async {
                    SafeHaptics.heavyImpact();
                    final metadata = timerNotifier.prepareSessionCompletion();
                    final totalSecs = metadata.totalDurationSeconds;
                    int calculatedMins = (totalSecs / 60).round();
                    if (calculatedMins == 0 && totalSecs >= 15) calculatedMins = 1;

                    if (calculatedMins > 0) {
                      await ref.read(userProfileProvider.notifier).addFocusMinutes(calculatedMins);
                    }

                    await timerNotifier.completeSession(
                      courseId: metadata.courseId,
                      courseCode: metadata.courseCode,
                      finalElapsedSeconds: totalSecs,
                      mode: isStopwatch ? 'stopwatch' : 'focus',
                      sessionStartTime: metadata.sessionStartTime,
                    );

                    if (mounted) {
                      _showPostSessionDialog(
                        context,
                        metadata: metadata,
                        subject: metadata.courseTitle,
                        durationMinutes: calculatedMins > 0 ? calculatedMins : 1,
                      );
                    }
                  },
                ),
                if (isRunning || isPaused) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Discard Session',
                    icon: Icon(Icons.close_rounded, color: Colors.redAccent.withValues(alpha: 0.8), size: 20),
                    onPressed: () {
                      SafeHaptics.heavyImpact();
                      timerNotifier.discardSession();
                    },
                  ),
                ],
              ],
            ),

          const SizedBox(height: 20),

          // Bottom Motivational & Interval Microcopy
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_rounded, size: 14, color: colors.success),
                    const SizedBox(width: 6),
                    Text(
                      'STAY IN FLOW • DISTRACTIONS BLOCKED',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  isStopwatch
                      ? 'CONTINUOUS COUNT-UP • NO TARGET INTERVAL'
                      : 'CURRENT INTERVAL: $targetFocusMins MIN FOCUS + $shortBreakMins MIN RESET',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Atelier Soundscape Quick Modulation Palette
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.graphic_eq_rounded, size: 16, color: colors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    'Atelier Soundscapes:',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: SoundscapeService.allLabels.map((p) {
                      final track = SoundscapeService.fromLabel(p);
                      final isCurrentPlaying = _soundEnabled && _soundscapeService.isPlaying && _selectedSoundscape == p;
                      final isDark = Theme.of(context).brightness == Brightness.dark;
                      final activeTextColor = isDark ? const Color(0xFF171C24) : Colors.white;

                      return Padding(
                        padding: const EdgeInsets.only(left: 6.0),
                        child: InkWell(
                          onTap: () {
                            SafeHaptics.selectionClick();
                            if (isCurrentPlaying) {
                              setState(() {
                                _soundEnabled = false;
                              });
                              _soundscapeService.stop();
                            } else {
                              setState(() {
                                _selectedSoundscape = p;
                                _soundEnabled = true;
                              });
                              _soundscapeService.play(track);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: isCurrentPlaying ? colors.secondary : colors.recessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isCurrentPlaying ? colors.secondary : colors.surfaceBorder,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrentPlaying) ...[
                                  Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 11,
                                    color: activeTextColor,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  p,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: isCurrentPlaying ? activeTextColor : colors.textMuted,
                                    fontSize: 10.5,
                                    fontWeight: isCurrentPlaying ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSessionSummary(TimerState timerState, List<StudySession> todaySessions) {
    final cycleCount = todaySessions.where((s) => s.isCompletedInterval).length;
    final totalSeconds = todaySessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final totalMinutes = (totalSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = totalMinutes == 0 ? '0.0 hrs' : (hours > 0 ? '${hours}h ${mins}m' : '${mins}m');
    final targetCycles = _targetCycles;

    final targetFocusMins = timerState.targetMinutes;
    final shortBreakMins = (targetFocusMins / 5).round().clamp(1, 15);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: colors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.query_stats_rounded, color: colors.secondary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Session Matrix',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.tune_rounded, color: colors.textMuted, size: 16),
                onPressed: () => _showCustomDurationDialog(context, ref.read(timerProvider.notifier)),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Parameters Ledger Table
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                if (timerState.timerType == TimerType.stopwatch) ...[
                  _summaryRow('Mode', 'Continuous Count-up'),
                  const SizedBox(height: 6),
                  _summaryRow('Elapsed Time', timerState.formattedTime),
                  const SizedBox(height: 6),
                  _summaryRow('Status', timerState.status == TimerStatus.running ? 'Focusing' : 'Paused'),
                ] else ...[
                  _summaryRow('Target Focus', '$targetFocusMins min'),
                  const SizedBox(height: 6),
                  _summaryRow('Short Break', '$shortBreakMins min'),
                  const SizedBox(height: 6),
                  _summaryRow('Long Break', '15 min (post 4th)'),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Today's Deep Work Output
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TODAY'S DEEP WORK OUTPUT",
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cycleCount > 0 ? '94% VELOCITY' : 'READY TO START',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.success,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Big Metric Output Block
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.recessed,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Total focused time today',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Segmented Cycle Tracker (Configurable)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _showTargetCyclesDialog,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      Text(
                        '$cycleCount / $targetCycles cycles completed',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.tune_rounded, size: 12, color: colors.secondary),
                    ],
                  ),
                ),
              ),
              Text(
                '${((cycleCount / targetCycles) * 100).toInt()}% target',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(_targetCycles, (idx) {
              final isCompleted = idx < cycleCount;
              final isCurrent = idx == cycleCount && timerState.status == TimerStatus.running;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: idx < _targetCycles - 1 ? 4 : 0),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? colors.primary
                        : (isCurrent ? colors.secondary : colors.surfaceBorder),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),

          const SizedBox(height: 20),

          // Today's Ledger (Recent Completed Sessions)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TODAY'S LEDGER",
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                '$cycleCount Blocks logged',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.primary,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (todaySessions.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.timer_outlined, size: 24, color: colors.textMuted),
                    const SizedBox(height: 6),
                    Text(
                      'No focus sessions recorded today',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Start the timer above to log your first block.',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...todaySessions.take(3).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    DateFormat('h:mm a').format(s.startedAt),
                                    style: GoogleFonts.jetBrainsMono(
                                      color: colors.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      s.courseCode.isNotEmpty
                                          ? '${s.courseCode} - ${s.topicName.isNotEmpty ? s.topicName : s.cleanTitle}'
                                          : s.cleanTitle,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textPrimary,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${(s.durationSeconds / 60).round()}m',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: colors.success.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check, size: 11, color: colors.success),
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildPillToggleItem(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? Colors.white : colors.textMuted,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDurationPresetsRow(TimerState timerState, TimerNotifier timerNotifier) {
    final presets = [15, 25, 45, 60];
    final currentTarget = timerState.targetMinutes;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...presets.map((min) {
            final isSelected = currentTarget == min;
            return Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: () {
                  SafeHaptics.selectionClick();
                  timerNotifier.setTargetMinutes(min);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected ? colors.secondary : colors.recessed,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? colors.secondary : colors.surfaceBorder,
                    ),
                  ),
                  child: Text(
                    '$min min',
                    style: GoogleFonts.jetBrainsMono(
                      color: isSelected ? Colors.white : colors.textMuted,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
          // Custom preset
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              onTap: () => _showCustomDurationDialog(context, timerNotifier),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: (!presets.contains(currentTarget)) ? colors.secondary : colors.recessed,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (!presets.contains(currentTarget)) ? colors.secondary : colors.surfaceBorder,
                  ),
                ),
                child: Text(
                  !presets.contains(currentTarget) ? '$currentTarget min' : 'Custom',
                  style: GoogleFonts.jetBrainsMono(
                    color: (!presets.contains(currentTarget)) ? Colors.white : colors.textMuted,
                    fontSize: 11,
                    fontWeight: (!presets.contains(currentTarget)) ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
        ),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 2. PORTRAIT TIMER (Mobile Width < 800px)
  // =========================================================================
  Widget _buildPortraitTimer(
    BuildContext context,
    WidgetRef ref,
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    List<Course> courses,
    Course? selectedCourse,
    List<SyllabusTopic> liveTopics,
    String? selectedTopicTitle,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
    bool isInitial,
  ) {
    final isStopwatch = timerState.timerType == TimerType.stopwatch;
    final elapsedSec = timerState.elapsedSeconds;
    final stopwatchProgress = (elapsedSec % 1800) / 1800.0;
    final int completedCycles = elapsedSec ~/ 1800;

    final dialProgress = isStopwatch
        ? (timerState.status == TimerStatus.initial ? 0.0 : stopwatchProgress)
        : (isBreak ? 1.0 : timerState.progressRatio);

    final todaySessionsAsync = ref.watch(todayStudySessionsStreamProvider);
    final todaySessions = todaySessionsAsync.value ?? [];
    final cycleCount = todaySessions.where((s) => s.isCompletedInterval).length;
    final totalSeconds = todaySessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    final totalMinutes = (totalSeconds / 60).round();
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeDisplay = totalMinutes == 0 ? '0.0 hrs' : (hours > 0 ? '${hours}h ${mins}m' : '${mins}m');

    return ShowCaseWidget(
      enableAutoScroll: true,
      blurValue: 2.0,
      onFinish: () => TourService().markTourSeen(TourSection.timer),
      builder: (showcaseContext) {
        _triggerTimerTourIfNeeded(showcaseContext);
        return Scaffold(
          backgroundColor: colors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isBreak
                                ? 'Break Time ☕'
                                : (timerState.isOvertime
                                    ? 'Overtime Focus ⚡'
                                    : (isStopwatch ? 'Stopwatch Timer' : 'Focus Study Timer')),
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isBreak
                                ? 'Target reached! Rest your eyes & recharge'
                                : (timerState.isOvertime
                                    ? 'In the zone • Recording overtime'
                                    : (isStopwatch
                                        ? 'Open-ended study session • Counting up'
                                        : 'Distraction-free target countdown')),
                            style: GoogleFonts.plusJakartaSans(
                              color: isBreak ? colors.success : (timerState.isOvertime ? colors.secondary : colors.textMuted),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isBreak ? colors.success : (timerState.isOvertime ? colors.secondary : colors.primary)).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isBreak ? colors.success : (timerState.isOvertime ? colors.secondary : colors.primary)).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          isBreak
                              ? 'BREAK'
                              : (timerState.isOvertime
                                  ? 'OVERTIME'
                                  : (isRunning
                                      ? (isStopwatch ? 'STOPWATCH' : 'FOCUS')
                                      : (isPaused ? 'PAUSED' : (isStopwatch ? 'STOPWATCH' : 'READY')))),
                          style: GoogleFonts.jetBrainsMono(
                            color: isBreak ? colors.success : (timerState.isOvertime ? colors.secondary : colors.primary),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Timer Mode Toggle (Countdown vs Stopwatch)
                  if (!isBreak) ...[
                    TourShowcaseItem(
                      section: TourSection.timer,
                      step: TourStep(
                        key: _keyTimerMode,
                        title: 'Study Modes & Course Tagging',
                        description: 'Toggle between structured Pomodoro intervals with earned breaks or open stopwatch sessions tagged to your courses.',
                      ),
                      stepIndex: 2,
                      totalSteps: 2,
                      child: Container(
                        padding: const EdgeInsets.all(3.0),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Row(
                          children: [
                            // Target Mode
                            Expanded(
                              child: InkWell(
                                onTap: (isRunning || isPaused)
                                    ? () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            behavior: SnackBarBehavior.floating,
                                            content: Text('Finish or reset current session to switch modes.'),
                                          ),
                                        );
                                      }
                                    : () {
                                        SafeHaptics.lightImpact();
                                        timerNotifier.setTimerType(TimerType.target);
                                      },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !isStopwatch ? colors.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.track_changes_rounded,
                                          size: 14,
                                          color: !isStopwatch ? Colors.white : colors.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Target (Countdown)',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: !isStopwatch ? Colors.white : colors.textMuted,
                                            fontSize: 12,
                                            fontWeight: !isStopwatch ? FontWeight.bold : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Stopwatch Mode
                            Expanded(
                              child: InkWell(
                                onTap: (isRunning || isPaused)
                                    ? () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            behavior: SnackBarBehavior.floating,
                                            content: Text('Finish or reset current session to switch modes.'),
                                          ),
                                        );
                                      }
                                    : () {
                                        SafeHaptics.lightImpact();
                                        timerNotifier.setTimerType(TimerType.stopwatch);
                                      },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isStopwatch ? colors.secondary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.timer_outlined,
                                          size: 14,
                                          color: isStopwatch ? Colors.white : colors.textMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Stopwatch (Count-up)',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: isStopwatch ? Colors.white : colors.textMuted,
                                            fontSize: 12,
                                            fontWeight: isStopwatch ? FontWeight.bold : FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 48px Target Course Dropdown Container
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.school_outlined, color: colors.secondary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: (selectedCourse != null)
                                    ? selectedCourse.id
                                    : (timerSubjects.contains(currentSubject) ? currentSubject : null),
                                dropdownColor: colors.surface,
                                icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted),
                                style: GoogleFonts.plusJakartaSans(
                                  color: colors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                isExpanded: true,
                                items: [
                                  ...courses.map((c) => DropdownMenuItem(
                                        value: c.id,
                                        child: Text(
                                          '${c.code}: ${c.title}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )),
                                  if (courses.isEmpty)
                                    ...timerSubjects.map((subj) => DropdownMenuItem(
                                          value: subj,
                                          child: Text(subj, overflow: TextOverflow.ellipsis),
                                        )),
                                ],
                                onChanged: (newVal) {
                                  if (newVal == null) return;
                                  SafeHaptics.lightImpact();
                                  Course? match;
                                  for (final c in courses) {
                                    if (c.id == newVal) {
                                      match = c;
                                      break;
                                    }
                                  }
                                  if (match != null) {
                                    timerNotifier.changeSubject(match.title);
                                    timerNotifier.setSelectedCourseAndTopic(
                                      courseId: match.id,
                                      courseCode: match.code,
                                    );
                                  } else {
                                    timerNotifier.changeSubject(newVal);
                                    timerNotifier.setSelectedCourseAndTopic(
                                      courseId: null,
                                      courseCode: newVal,
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.tune_rounded, color: colors.textMuted, size: 18),
                            tooltip: 'Manage Timer Subjects',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              SafeHaptics.lightImpact();
                              _showManageSubjectsModal(context, ref);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // Quick Duration Presets (Target Mode only)
                  if (!isBreak && !isStopwatch) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [15, 25, 45, 60].map((mins) {
                        final isSelected = timerState.targetMinutes == mins;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
                          child: InkWell(
                            onTap: () {
                              SafeHaptics.lightImpact();
                              timerNotifier.setTargetMinutes(mins);
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.secondary : colors.surface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? colors.secondary : colors.surfaceBorder,
                                ),
                              ),
                              child: Text(
                                '${mins}m',
                                style: GoogleFonts.jetBrainsMono(
                                  color: isSelected ? Colors.white : colors.textMuted,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                  ],

                  // Circular Timer Dial with Breathing Pulse Animation & Adjustment Buttons
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // '-' Decrease Button
                        if (!isBreak && !isStopwatch) ...[
                          InkWell(
                            onTap: () {
                              SafeHaptics.lightImpact();
                              timerNotifier.decrementTargetMinutes(5);
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.surfaceBorder),
                              ),
                              child: Icon(Icons.remove_rounded, color: colors.textMuted, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],

                        // Dial Dial
                        TourShowcaseItem(
                          section: TourSection.timer,
                          step: TourStep.circle(
                            key: _keyTimerDial,
                            title: 'Focus Session',
                            description: 'Tap to begin tracking your study block with ambient distraction-free focus modes.',
                          ),
                          stepIndex: 1,
                          totalSteps: 2,
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: isRunning ? _scaleAnimation.value : 1.0,
                                child: SizedBox(
                                  width: 240,
                                  height: 240,
                                  child: CustomPaint(
                                    painter: TimerDialPainter(
                                      progress: dialProgress,
                                      isStopwatch: isStopwatch,
                                      primaryColor: isBreak ? colors.success : colors.secondary,
                                      trackColor: colors.surfaceBorder,
                                      dialFillColor: colors.surface,
                                      borderColor: colors.surfaceBorder,
                                      glowColor: isRunning
                                          ? (isBreak
                                              ? colors.success.withValues(alpha: _glowAnimation.value)
                                              : colors.secondary.withValues(alpha: _glowAnimation.value))
                                          : null,
                                      strokeWidth: 8.5,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            isBreak
                                                ? 'BREAK'
                                                : (timerState.isOvertime
                                                    ? 'OVERTIME'
                                                    : 'INTERVAL BLOCK 0${(cycleCount % 5) + 1}'),
                                            style: GoogleFonts.jetBrainsMono(
                                              color: isBreak
                                                  ? colors.success
                                                  : (timerState.isOvertime ? colors.secondary : colors.textMuted),
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.8,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            timerState.formattedTime,
                                            style: GoogleFonts.jetBrainsMono(
                                              color: isBreak
                                                  ? colors.success
                                                  : (timerState.isOvertime ? colors.secondary : colors.textPrimary),
                                              fontSize: isBreak ? 32 : 38,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: -1.0,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(maxWidth: 180),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: colors.recessed,
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: colors.surfaceBorder),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                      color: isBreak ? colors.success : colors.secondary,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: AutoScrollMarqueeText(
                                                      text: isBreak
                                                          ? 'Break'
                                                          : (timerState.isOvertime
                                                              ? 'Overtime • Recording study time'
                                                              : '${selectedCourse?.code ?? currentSubject} • ${selectedTopicTitle ?? 'Focus Session'}'),
                                                      style: GoogleFonts.plusJakartaSans(
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
                                          const SizedBox(height: 4),
                                          Text(
                                            isBreak
                                                ? 'Earned Rest'
                                                : (timerState.isOvertime
                                                    ? 'Overtime • Deep Focus'
                                                    : (isStopwatch
                                                        ? (completedCycles == 0
                                                            ? 'Cycle 1 (0–30m)'
                                                            : 'Cycle ${completedCycles + 1} • ${completedCycles * 30}m+ completed')
                                                        : 'Target: ${timerState.targetMinutes} min')),
                                            style: GoogleFonts.jetBrainsMono(
                                              color: colors.textMuted,
                                              fontSize: 10.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // '+' Increase Button
                        if (!isBreak && !isStopwatch) ...[
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () {
                              SafeHaptics.lightImpact();
                              timerNotifier.incrementTargetMinutes(5);
                            },
                            borderRadius: BorderRadius.circular(30),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                shape: BoxShape.circle,
                                border: Border.all(color: colors.surfaceBorder),
                              ),
                              child: Icon(Icons.add_rounded, color: colors.textMuted, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Minimal Break indicator banner - only shown when on break
                  if (isBreak) ...[
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 5.0),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.success.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Break: ${timerState.formattedTime}',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.success,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Controls Action Bar
                  if (isInitial && !isBreak) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Sound ambient button
                        GestureDetector(
                          onTap: () {
                            SafeHaptics.selectionClick();
                            _showSoundscapePickerSheet();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _soundEnabled
                                  ? colors.secondary.withValues(alpha: 0.15)
                                  : colors.surface,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _soundEnabled ? colors.secondary : colors.surfaceBorder,
                                width: _soundEnabled ? 1.5 : 1,
                              ),
                            ),
                            child: Icon(
                              _soundEnabled ? Icons.water_drop_rounded : Icons.water_drop_outlined,
                              color: _soundEnabled ? colors.secondary : colors.textMuted,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Hero 60px Play Button
                        GestureDetector(
                          onTap: () {
                            SafeHaptics.heavyImpact();
                            timerNotifier.startTimer();
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: colors.secondary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: colors.secondary.withValues(alpha: 0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Custom Target Dialog Button
                        IconButton(
                          icon: Icon(Icons.tune_rounded, color: colors.textMuted, size: 22),
                          onPressed: () => _showCustomDurationDialog(context, timerNotifier),
                        ),
                      ],
                    ),
                  ] else if (isBreak) ...[
                    Row(
                      children: [
                        // Pause / Resume
                        IconButton(
                          icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, color: colors.textPrimary),
                          onPressed: () {
                            SafeHaptics.lightImpact();
                            timerNotifier.toggleStartPause();
                          },
                        ),
                        const SizedBox(width: 10),
                        // Next Focus
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              SafeHaptics.heavyImpact();
                              timerNotifier.endBreak();
                            },
                            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                            label: Text('Next Focus', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // End Break
                        IconButton(
                          icon: const Icon(Icons.stop_rounded, color: Colors.redAccent),
                          onPressed: () {
                            SafeHaptics.heavyImpact();
                            timerNotifier.endSession();
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    // Running or Paused Controls
                    Row(
                      children: [
                        // Pause / Resume
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.secondary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () {
                              SafeHaptics.lightImpact();
                              timerNotifier.toggleStartPause();
                            },
                            icon: Icon(isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 18),
                            label: Text(isRunning ? 'Pause' : 'Resume', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Finish / Log Session
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colors.primary,
                              side: BorderSide(color: colors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              SafeHaptics.heavyImpact();
                              final metadata = timerNotifier.prepareSessionCompletion();
                              final totalSecs = metadata.totalDurationSeconds;
                              int calculatedMins = (totalSecs / 60).round();
                              if (calculatedMins == 0 && totalSecs >= 15) calculatedMins = 1;

                              if (calculatedMins > 0) {
                                await ref.read(userProfileProvider.notifier).addFocusMinutes(calculatedMins);
                              }

                              await timerNotifier.completeSession(
                                courseId: metadata.courseId,
                                courseCode: metadata.courseCode,
                                finalElapsedSeconds: totalSecs,
                                mode: isStopwatch ? 'stopwatch' : 'focus',
                                sessionStartTime: metadata.sessionStartTime,
                              );

                              if (!context.mounted) return;
                              _showPostSessionDialog(
                                context,
                                metadata: metadata,
                                subject: metadata.courseTitle,
                                durationMinutes: calculatedMins > 0 ? calculatedMins : 1,
                              );
                            },
                            icon: const Icon(Icons.flag_rounded, size: 18),
                            label: Text('Finish', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Discard
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
                          onPressed: () {
                            SafeHaptics.heavyImpact();
                            timerNotifier.discardSession();
                          },
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Collapsible Atomic Syllabus Topics Section
                  if (liveTopics.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: false,
                        shape: const Border(),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        title: Row(
                          children: [
                            Icon(Icons.checklist_rtl_rounded, color: colors.secondary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'ATOMIC SYLLABUS TOPICS',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          selectedTopicTitle != null ? 'Linked: $selectedTopicTitle' : 'Tap to link topic',
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: Column(
                              children: liveTopics.take(4).map((t) => _buildDesktopTopicTile(t, selectedCourse)).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Today's Output & Ledger
                  Container(
                    padding: const EdgeInsets.all(16),
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
                            Text(
                              "TODAY'S DEEP WORK",
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                            InkWell(
                              onTap: _showTargetCyclesDialog,
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
                                children: [
                                  Text(
                                    '$cycleCount / $_targetCycles cycles',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: colors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.tune_rounded, size: 12, color: colors.primary),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          timeDisplay,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (todaySessions.isEmpty)
                          Text(
                            'No focus sessions recorded today — start the timer to log your first block.',
                            style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                          )
                        else
                          ...todaySessions.take(3).map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: 6.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: colors.recessed,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: colors.surfaceBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.courseCode.isNotEmpty
                                              ? '${s.courseCode}: ${s.topicName.isNotEmpty ? s.topicName : s.cleanTitle}'
                                              : s.cleanTitle,
                                          style: GoogleFonts.plusJakartaSans(
                                            color: colors.textPrimary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        '${(s.durationSeconds / 60).round()}m',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: colors.textPrimary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =========================================================================
  // 3. LANDSCAPE DESK CLOCK (StandBy Mode)
  // =========================================================================
  Widget _buildLandscapeDeskClock(
    BuildContext context,
    WidgetRef ref,
    TimerState timerState,
    TimerNotifier timerNotifier,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
  ) {
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            SafeHaptics.lightImpact();
            timerNotifier.toggleStartPause();
          },
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: (isBreak ? colors.success : colors.secondary).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (isBreak ? colors.success : colors.secondary).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBreak ? Icons.coffee_rounded : Icons.menu_book_rounded,
                            size: 14,
                            color: isBreak ? colors.success : colors.secondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isBreak
                                ? 'BREAK TIME ☕'
                                : (timerState.isOvertime
                                    ? '${currentSubject.toUpperCase()} • OVERTIME ⚡'
                                    : currentSubject.toUpperCase()),
                            style: GoogleFonts.jetBrainsMono(
                              color: isBreak ? colors.success : colors.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Massive Desk Clock Countdown
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: isRunning ? _scaleAnimation.value : 1.0,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              timerState.formattedTime,
                              style: GoogleFonts.jetBrainsMono(
                                color: isBreak ? colors.success : colors.textPrimary,
                                fontSize: 110,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -3.0,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    Text(
                      isBreak
                          ? 'Earned Rest'
                          : (timerState.isOvertime
                              ? 'Overtime • Deep Focus'
                              : '${timerState.targetMinutes} min target • ${timerState.formattedEarnedBreak} earned break'),
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 42,
                    color: colors.textMuted.withValues(alpha: 0.5),
                    tooltip: isRunning ? 'Pause' : 'Resume',
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      timerNotifier.toggleStartPause();
                    },
                    icon: Icon(
                      isRunning
                          ? Icons.pause_circle_outline_rounded
                          : Icons.play_circle_outline_rounded,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 4. DIALOGS & MODALS
  // =========================================================================
  void _showTargetCyclesDialog() {
    SafeHaptics.selectionClick();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.repeat_rounded, color: colors.secondary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Target Daily Cycles',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [2, 4, 5, 6, 8].map((n) {
            final isSelected = n == _targetCycles;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? colors.primary : colors.textMuted,
                size: 20,
              ),
              title: Text(
                '$n cycles',
                style: GoogleFonts.plusJakartaSans(
                  color: isSelected ? colors.primary : colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              onTap: () {
                SafeHaptics.selectionClick();
                setState(() => _targetCycles = n);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showSoundscapePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheetState) {
          final isMuted = !_soundscapeService.isPlaying;

          final items = [
            (
              label: 'Off',
              sublabel: 'Mute / Stop playback',
              track: SoundscapeTrack.none,
              icon: Icons.volume_off_rounded,
            ),
            (
              label: 'Rainfall',
              sublabel: 'Gentle academic rain (rain.mp3)',
              track: SoundscapeTrack.rainfall,
              icon: Icons.water_drop_outlined,
            ),
            (
              label: 'Heavy Rain',
              sublabel: 'Deep acoustic rain shower (rain2.mp3)',
              track: SoundscapeTrack.heavyRain,
              icon: Icons.thunderstorm_outlined,
            ),
            (
              label: 'Brown Noise',
              sublabel: 'Low-frequency rumble & wind (wind.mp3)',
              track: SoundscapeTrack.brownNoise,
              icon: Icons.air_rounded,
            ),
            (
              label: 'Cafe Ambiance',
              sublabel: 'Warm coffeehouse murmur (cafe.mp3)',
              track: SoundscapeTrack.cafeAmbiance,
              icon: Icons.local_cafe_outlined,
            ),
            (
              label: 'Forest Birds',
              sublabel: 'Nature woodland atmosphere (birds.mp3)',
              track: SoundscapeTrack.forestBirds,
              icon: Icons.forest_outlined,
            ),
          ];

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Center drag indicator
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.surfaceBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ambient Soundscapes',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (_soundscapeService.isPlaying)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colors.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.graphic_eq_rounded, size: 12, color: colors.secondary),
                              const SizedBox(width: 4),
                              Text(
                                'LOOPING',
                                style: GoogleFonts.jetBrainsMono(
                                  color: colors.secondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Continuous background noise to sustain deep focus state',
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),

                  // Volume Slider Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _soundscapeService.volume == 0
                              ? Icons.volume_mute_rounded
                              : Icons.volume_down_rounded,
                          size: 18,
                          color: colors.textMuted,
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(ctx).copyWith(
                              activeTrackColor: colors.secondary,
                              inactiveTrackColor: colors.surfaceBorder,
                              thumbColor: colors.secondary,
                              overlayColor: colors.secondary.withValues(alpha: 0.15),
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            ),
                            child: Slider(
                              value: _soundscapeService.volume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (val) async {
                                await _soundscapeService.setVolume(val);
                                setSheetState(() {});
                              },
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text(
                            '${(_soundscapeService.volume * 100).round()}%',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Soundscape List
                  ...items.map((item) {
                    final bool isSelected = item.track == SoundscapeTrack.none
                        ? isMuted
                        : (_soundscapeService.isPlaying && _soundscapeService.currentTrack == item.track);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: InkWell(
                        onTap: () {
                          SafeHaptics.selectionClick();
                          if (item.track == SoundscapeTrack.none) {
                            setState(() => _soundEnabled = false);
                            setSheetState(() {});
                            _soundscapeService.stop();
                          } else {
                            if (isSelected) {
                              setState(() => _soundEnabled = false);
                              setSheetState(() {});
                              _soundscapeService.stop();
                            } else {
                              setState(() {
                                _selectedSoundscape = item.label;
                                _soundEnabled = true;
                              });
                              setSheetState(() {});
                              _soundscapeService.play(item.track);
                            }
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.secondary.withValues(alpha: 0.12)
                                : colors.recessed,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? colors.secondary : colors.surfaceBorder,
                              width: isSelected ? 1.2 : 0.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.icon,
                                color: isSelected ? colors.secondary : colors.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.label,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isSelected ? colors.secondary : colors.textPrimary,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    Text(
                                      item.sublabel,
                                      style: GoogleFonts.plusJakartaSans(
                                        color: colors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded, color: colors.secondary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _showCustomDurationDialog(BuildContext context, TimerNotifier timerNotifier) {
    SafeHaptics.selectionClick();
    final customCtrl = TextEditingController(text: '30');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Text(
          'Custom Focus Duration',
          style: GoogleFonts.plusJakartaSans(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set target focus time (5 - 360 minutes):',
              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: customCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                suffixText: 'minutes',
                suffixStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.surfaceBorder)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.secondary)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.secondary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final mins = int.tryParse(customCtrl.text.trim());
              if (mins != null && mins > 0) {
                SafeHaptics.mediumImpact();
                timerNotifier.setTargetMinutes(mins.clamp(5, 360));
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Set Target', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showManageSubjectsModal(BuildContext context, WidgetRef ref) {
    final customCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final subjects = ref.watch(timerSubjectsProvider);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Manage Timer Subjects',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  Text(
                    'Custom timer subjects are saved to your profile. Modifying this list does NOT alter your Syllabus or delete past study logs.',
                    style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 16),

                  // Add Custom Subject Input Row
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextField(
                            controller: customCtrl,
                            style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Enter new custom subject...',
                              hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
                              filled: true,
                              fillColor: colors.recessed,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: colors.surfaceBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: colors.surfaceBorder),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: colors.secondary),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          final text = customCtrl.text.trim();
                          if (text.isNotEmpty) {
                            SafeHaptics.lightImpact();
                            ref.read(timerSubjectsProvider.notifier).addCustomSubject(text);
                            ref.read(userProfileProvider.notifier).addCustomTimerSubject(text);
                            customCtrl.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: colors.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 2),
                                content: Text('Added "$text" to timer subjects.', style: GoogleFonts.plusJakartaSans(color: Colors.white)),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text('Add', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.secondary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Current Subjects List
                  Text(
                    'CURRENT TIMER SUBJECTS',
                    style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: subjects.length,
                      itemBuilder: (context, index) {
                        final subj = subjects[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: colors.recessed,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  subj,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (subjects.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'Remove from Timer',
                                  onPressed: () {
                                    SafeHaptics.lightImpact();
                                    ref.read(timerSubjectsProvider.notifier).deleteSubject(subj);
                                  },
                                ),
                            ],
                          ),
                        );
                      },
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

  /// Post-Session Study Logging Dialog & Session Finish Handover
  Future<void> _showPostSessionDialog(
    BuildContext context, {
    SessionMetadata? metadata,
    String? subject,
    int? durationMinutes,
  }) async {
    if (_isPostSessionDialogOpen || !mounted) return;
    _isPostSessionDialogOpen = true;
    try {
      final userProfile = ref.read(userProfileProvider);
      final mode = userProfile.isUniversityStudent ? 'university' : 'admission';
      final resolvedSubject = metadata?.courseTitle ?? subject ?? 'General Study';
      final resolvedId = metadata?.courseId ?? RoutineCourseSyncService.sanitizeDocId(resolvedSubject);

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.65),
        builder: (dialogCtx) => StudySessionLogDialog(
          metadata: metadata,
          subjectOrCourseName: resolvedSubject,
          subjectOrCourseId: resolvedId,
          durationMinutes: durationMinutes ?? metadata?.durationMinutes ?? 1,
          mode: mode,
          onSaved: () {
            ref.read(timerProvider.notifier).resetTimer();
          },
          onSkipped: () {
            ref.read(timerProvider.notifier).resetTimer();
          },
        ),
      );
    } finally {
      _isPostSessionDialogOpen = false;
    }
  }
}

// =========================================================================
// 5. CUSTOM TIMER DIAL PAINTER
// =========================================================================
class TimerDialPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isStopwatch;
  final Color primaryColor;
  final Color trackColor;
  final Color dialFillColor;
  final Color borderColor;
  final Color? glowColor;
  final double strokeWidth;

  const TimerDialPainter({
    required this.progress,
    required this.isStopwatch,
    required this.primaryColor,
    required this.trackColor,
    required this.dialFillColor,
    required this.borderColor,
    this.glowColor,
    this.strokeWidth = 8.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final arcRadius = (size.width - strokeWidth) / 2;

    // 1. Dial Fill
    if (dialFillColor != Colors.transparent) {
      final fillPaint = Paint()
        ..color = dialFillColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, outerRadius, fillPaint);
    }

    // 2. Soft Outer Border
    if (borderColor != Colors.transparent) {
      final borderPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawCircle(center, outerRadius - 0.5, borderPaint);
    }

    // 3. Background Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, arcRadius, trackPaint);

    // 4. Cardinal ticks (top, right, bottom, left)
    const cardinalCount = 4;
    for (int i = 0; i < cardinalCount; i++) {
      final tickAngle = -math.pi / 2 + (2 * math.pi * i / cardinalCount);
      final tickDistance = arcRadius;
      final tickX = center.dx + tickDistance * math.cos(tickAngle);
      final tickY = center.dy + tickDistance * math.sin(tickAngle);
      final tickPaint = Paint()
        ..color = borderColor.withValues(alpha: 0.8)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(tickX, tickY), 2.5, tickPaint);
    }

    // 5. Active Progress Arc
    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0.001) {
      final sweepAngle = 2 * math.pi * clampedProgress;
      final rect = Rect.fromCircle(center: center, radius: arcRadius);

      final arcPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweepAngle,
        false,
        arcPaint,
      );

      // Soft tip glow
      final tipAngle = -math.pi / 2 + sweepAngle;
      final tipX = center.dx + arcRadius * math.cos(tipAngle);
      final tipY = center.dy + arcRadius * math.sin(tipAngle);
      final tipCenter = Offset(tipX, tipY);

      final effectiveGlow = glowColor ?? primaryColor;
      final tipGlowPaint = Paint()
        ..color = effectiveGlow.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tipCenter, strokeWidth * 0.8, tipGlowPaint);

      // Inner highlight pip
      final pipPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tipCenter, 2.0, pipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TimerDialPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isStopwatch != isStopwatch ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.dialFillColor != dialFillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
