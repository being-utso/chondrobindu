import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart';
import '../providers/firestore_providers.dart';
import '../providers/timer_provider.dart';
import '../providers/timer_subjects_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/nav_provider.dart';
import '../services/notification_service.dart';
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
  // Desktop Suite State
  final TextEditingController _desktopScratchpadController = TextEditingController();
  final Set<String> _selectedDesktopTopics = {'3.1', '3.2', '3.3'};
  bool _desktopSoundEnabled = true;

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
  DateTime? _backgroundedTime;
  bool _isPostSessionDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Request Android 13+ notification permissions when timer screen opens
    NotificationService().requestPermissions();

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

  /// Task 2: Lifecycle observation to catch up on missed time when locked/backgrounded
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final timerState = ref.read(timerProvider);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // Record exact timestamp when phone is locked or app minimized while running
      if (timerState.status == TimerStatus.running) {
        _backgroundedTime = DateTime.now();
        debugPrint('Timer backgrounded/locked at: $_backgroundedTime');
      }
    } else if (state == AppLifecycleState.resumed) {
      // Catch up on time passed while phone was locked or app was in background
      if (_backgroundedTime != null && timerState.status == TimerStatus.running) {
        final now = DateTime.now();
        final missedSeconds = now.difference(_backgroundedTime!).inSeconds;
        debugPrint('Timer resumed. Catching up missed duration: $missedSeconds seconds');

        if (missedSeconds > 0) {
          ref.read(timerProvider.notifier).catchUp(missedSeconds);
          if (mounted) {
            setState(() {});
          }
        }
        _backgroundedTime = null;
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

    // Task 2: Subtle Breathing / Pulse Animation ONLY runs when Timer is Running
    if (isRunning) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating || _pulseController.value != 0.0) {
        _pulseController.animateTo(0.0, duration: const Duration(milliseconds: 300));
      }
    }

    const accentColor = Color(0xFFF2B78A);
    const breakColor = Color(0xFF34D399); // Emerald for Break
    final currentColor = isBreak ? breakColor : accentColor;

    // Ensure selected subject is valid or fallback to first available
    final currentSubject = timerSubjects.contains(timerState.selectedSubject)
        ? timerState.selectedSubject
        : (timerSubjects.isNotEmpty ? timerSubjects.first : 'General Study');

    final isDesktopWide = MediaQuery.of(context).size.width >= 800;
    if (isDesktopWide) {
      return _buildDesktopSuite(
        context,
        ref,
        timerState,
        timerNotifier,
        timerSubjects,
        currentSubject,
        isBreak,
        isRunning,
        isPaused,
        isInitial,
        currentColor,
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
          currentSubject,
          isBreak,
          isRunning,
          isPaused,
          isInitial,
          currentColor,
        );
      },
    );
  }

  /// Desktop-native 3-column Deep Work Suite (width >= 800px)
  Widget _buildDesktopSuite(
    BuildContext context,
    WidgetRef ref,
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
    bool isInitial,
    Color currentColor,
  ) {
    final isStopwatch = timerState.timerType == TimerType.stopwatch;
    final elapsedSec = timerState.elapsedSeconds;
    final stopwatchProgress = (elapsedSec % 1800) / 1800.0;
    final dialProgress = isStopwatch
        ? (timerState.status == TimerStatus.initial ? 0.0 : stopwatchProgress)
        : (isBreak ? 1.0 : timerState.progressRatio);

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column (flex 3): Context & Target Selection
                Expanded(
                  flex: 3,
                  child: _buildDesktopTargetSelection(timerState, timerNotifier, timerSubjects, currentSubject),
                ),

                const SizedBox(width: 24),

                // Center Column (flex 6): Immersive Timer Engine
                Expanded(
                  flex: 6,
                  child: _buildDesktopCenterDial(
                    timerState,
                    timerNotifier,
                    currentSubject,
                    isBreak,
                    isRunning,
                    isPaused,
                    isStopwatch,
                    dialProgress,
                    currentColor,
                  ),
                ),

                const SizedBox(width: 24),

                // Right Column (flex 3): Session Overview & Motivation
                Expanded(
                  flex: 3,
                  child: _buildDesktopSessionSummary(timerState),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTargetSelection(
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    String currentSubject,
  ) {
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
            children: [
              const Icon(Icons.school_outlined, color: Color(0xFFF2B78A), size: 18),
              const SizedBox(width: 8),
              Text(
                'TARGET COURSE',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Custom Dark Course Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: timerSubjects.contains(currentSubject)
                    ? currentSubject
                    : (timerSubjects.isNotEmpty ? timerSubjects.first : null),
                isExpanded: true,
                dropdownColor: const Color(0xFF241C1A),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFFF2B78A)),
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                items: timerSubjects
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    SafeHaptics.selectionClick();
                    timerNotifier.changeSubject(val);
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              const Icon(Icons.checklist_rounded, color: Color(0xFF34D399), size: 18),
              const SizedBox(width: 8),
              Text(
                'SELECT ATOMIC TOPICS',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Atomic topics list
          ...(() {
            final courses = ref.watch(coursesStreamProvider).valueOrNull ?? [];
            Course? matchedCourse;
            for (final c in courses) {
              if (c.title.toLowerCase() == currentSubject.toLowerCase() ||
                  c.code.toLowerCase() == currentSubject.toLowerCase()) {
                matchedCourse = c;
                break;
              }
            }
            if (matchedCourse != null) {
              final liveTopics = ref.watch(syllabusTopicsStreamProvider(matchedCourse.id)).valueOrNull;
              if (liveTopics != null && liveTopics.isNotEmpty) {
                return liveTopics.take(5).map((t) => _desktopTopicCheckbox(t.topicIndex, t.title)).toList();
              }
            }
            return [
              _desktopTopicCheckbox('3.1', 'Definition and classification of signals'),
              _desktopTopicCheckbox('3.2', 'Elementary continuous-time signals'),
              _desktopTopicCheckbox('3.3', 'Time shifting and scaling'),
              _desktopTopicCheckbox('3.4', 'Signal addition and multiplication'),
              _desktopTopicCheckbox('3.5', 'Even and odd signals'),
            ];
          })(),

          const SizedBox(height: 24),

          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Color(0xFFF2B78A), size: 18),
              const SizedBox(width: 8),
              Text(
                'SCRATCHPAD / FOCUS NOTES',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF9E8C82),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desktopScratchpadController,
            maxLines: 4,
            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Jot down formulas, derivations, blockages, or fleeting thoughts...',
              hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF241C1A),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2E2623), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopTopicCheckbox(String id, String title) {
    final isChecked = _selectedDesktopTopics.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () {
          SafeHaptics.selectionClick();
          setState(() {
            if (isChecked) {
              _selectedDesktopTopics.remove(id);
            } else {
              _selectedDesktopTopics.add(id);
            }
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF241C1A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isChecked ? const Color(0xFF34D399).withValues(alpha: 0.4) : const Color(0xFF2E2623),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                color: isChecked ? const Color(0xFF34D399) : const Color(0xFF9E8C82),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$id $title',
                  style: GoogleFonts.plusJakartaSans(
                    color: isChecked ? const Color(0xFFEDE8E3) : const Color(0xFF9E8C82),
                    fontSize: 12.5,
                    fontWeight: isChecked ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
    double dialProgress,
    Color currentColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pill Toggle: [ Focus ] vs [ Stopwatch ]
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _desktopPillToggleItem('Focus', !isStopwatch, () {
                  SafeHaptics.selectionClick();
                  timerNotifier.setTimerType(TimerType.target);
                }),
                _desktopPillToggleItem('Stopwatch', isStopwatch, () {
                  SafeHaptics.selectionClick();
                  timerNotifier.setTimerType(TimerType.stopwatch);
                }),
              ],
            ),
          ),

          const SizedBox(height: 36),

          // 280px Diameter Circular Countdown Dial
          SizedBox(
            width: 280,
            height: 280,
            child: CustomPaint(
              painter: TimerDialPainter(
                progress: dialProgress,
                isStopwatch: isStopwatch,
                primaryColor: isBreak ? const Color(0xFF34D399) : const Color(0xFFF2B78A),
                glowColor: timerState.isOvertime ? const Color(0xFFF2B78A).withValues(alpha: 0.35) : null,
                strokeWidth: 10.0,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timerState.formattedTime,
                      style: GoogleFonts.jetBrainsMono(
                        color: isBreak
                            ? const Color(0xFF34D399)
                            : (timerState.isOvertime
                                ? const Color(0xFFF2B78A)
                                : const Color(0xFFEDE8E3)),
                        fontSize: 48,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isBreak
                          ? 'Break • 5:1 Focus Ratio'
                          : (timerState.isOvertime
                              ? 'Overtime • Counting Up'
                              : '$currentSubject • Focus Session'),
                      style: GoogleFonts.plusJakartaSans(
                        color: isBreak ? const Color(0xFF34D399) : const Color(0xFF9E8C82),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 36),

          // Primary Action Bar
          if (isBreak)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF34D399),
                    side: const BorderSide(color: Color(0xFF064E3B)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    SafeHaptics.selectionClick();
                    timerNotifier.skipBreak();
                  },
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Skip Break'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34D399),
                    foregroundColor: const Color(0xFF151211),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    SafeHaptics.mediumImpact();
                    timerNotifier.endSession();
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('End Session'),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Sound / Ambient button
                IconButton(
                  icon: Icon(
                    _desktopSoundEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                    color: const Color(0xFF9E8C82),
                    size: 22,
                  ),
                  onPressed: () {
                    SafeHaptics.selectionClick();
                    setState(() => _desktopSoundEnabled = !_desktopSoundEnabled);
                  },
                ),
                const SizedBox(width: 16),

                // Large Play / Pause button
                GestureDetector(
                  onTap: () {
                    SafeHaptics.mediumImpact();
                    timerNotifier.toggleStartPause();
                  },
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: const Color(0xFF151211),
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Finish session button
                IconButton(
                  icon: const Icon(
                    Icons.flag_outlined,
                    color: Color(0xFF9E8C82),
                    size: 22,
                  ),
                  onPressed: () {
                    SafeHaptics.heavyImpact();
                    timerNotifier.startBreakAfterSession();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _desktopPillToggleItem(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF2B78A).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: const Color(0xFFF2B78A), width: 1) : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSessionSummary(TimerState timerState) {
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
            'SESSION PLAN',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFF9E8C82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          _summaryRow('Target Focus', '25 min'),
          const SizedBox(height: 10),
          _summaryRow('Short Break', '5 min'),
          const SizedBox(height: 10),
          _summaryRow('Cycle Ratio', '5:1 Focus-to-Rest'),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18.0),
            child: Divider(color: Color(0xFF2E2623), height: 1),
          ),

          Text(
            "TODAY'S OUTPUT",
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFF9E8C82),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '2 / 5 cycles',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '2h 10m focused',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFF34D399),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: const LinearProgressIndicator(
              value: 0.40,
              backgroundColor: Color(0xFF241C1A),
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
              minHeight: 5,
            ),
          ),

          const SizedBox(height: 32),

          // Motivational Quote
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF241C1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote_rounded, color: Color(0xFFF2B78A), size: 20),
                const SizedBox(height: 6),
                Text(
                  '"Small disciplines repeated with consistency every day lead to great achievements."',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF9E8C82),
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
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

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
        ),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            color: const Color(0xFFEDE8E3),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Minimalist "Desk Clock" UI for Landscape StandBy Mode on deep `#110D0C`
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
    const deepDeskBackground = Color(0xFF110D0C);
    const breakColor = Color(0xFF34D399);
    const accentColor = Color(0xFFF2B78A);
    final themeColor = isBreak ? breakColor : accentColor;

    return Scaffold(
      backgroundColor: deepDeskBackground,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            SafeHaptics.lightImpact();
            if (timerState.status == TimerStatus.initial &&
                timerState.selectedSubject != currentSubject) {
              timerNotifier.changeSubject(currentSubject);
            }
            timerNotifier.toggleStartPause();
          },
          child: Stack(
            children: [
              // Center Desk Clock Content with Breathing Pulse Animation
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Subtle Subject & Mode Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: themeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: themeColor.withOpacity(0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBreak ? Icons.coffee_rounded : Icons.menu_book_rounded,
                            size: 14,
                            color: themeColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isBreak
                                ? 'BREAK TIME ☕'
                                : (timerState.isOvertime
                                    ? '${currentSubject.toUpperCase()} • OVERTIME ⚡'
                                    : currentSubject.toUpperCase()),
                            style: TextStyle(
                              color: themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Massive Desk Clock Countdown Text with Pulse Animation
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              timerState.formattedTime,
                              style: TextStyle(
                                color: isBreak ? const Color(0xFFF5EBE6) : Colors.white,
                                fontSize: 110,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -3.0,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                shadows: [
                                  Shadow(
                                    color: themeColor.withOpacity(isRunning ? _glowAnimation.value : 0.1),
                                    offset: const Offset(0, 4),
                                    blurRadius: isRunning ? (16 + (_pulseController.value * 14)) : 10,
                                  ),
                                  const Shadow(
                                    color: Color(0x55000000),
                                    offset: Offset(0, 4),
                                    blurRadius: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Subtle Progress / Info Text
                    Text(
                      isBreak
                          ? 'Earned Rest • 5:1 Focus Ratio'
                          : (timerState.isOvertime
                              ? 'Overtime • Deep Focus'
                              : (timerState.timerType == TimerType.stopwatch
                                  ? (timerState.elapsedSeconds ~/ 1800 == 0
                                      ? 'Cycle 1 (0–30m) • ${timerState.formattedEarnedBreak} earned break'
                                      : 'Cycle ${(timerState.elapsedSeconds ~/ 1800) + 1} • ${(timerState.elapsedSeconds ~/ 1800) * 30}m+ completed • ${timerState.formattedEarnedBreak} earned break')
                                  : '${(timerState.targetSeconds ~/ 60)} min target • ${timerState.formattedEarnedBreak} earned break')),
                      style: TextStyle(
                        color: isBreak
                            ? const Color(0xFF7B968B)
                            : (timerState.isOvertime ? const Color(0xFFF2B78A) : Colors.white.withOpacity(0.45)),
                        fontSize: 12,
                        fontWeight: (isBreak || timerState.isOvertime) ? FontWeight.w600 : FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Subtle Semi-Transparent Pause/Resume Icon at Bottom Center
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    iconSize: 42,
                    color: Colors.white.withOpacity(0.35),
                    tooltip: isRunning ? 'Pause' : 'Resume',
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      if (timerState.status == TimerStatus.initial &&
                          timerState.selectedSubject != currentSubject) {
                        timerNotifier.changeSubject(currentSubject);
                      }
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

  /// Standard Portrait Timer UI with Pulse Animation & Haptics
  Widget _buildPortraitTimer(
    BuildContext context,
    WidgetRef ref,
    TimerState timerState,
    TimerNotifier timerNotifier,
    List<String> timerSubjects,
    String currentSubject,
    bool isBreak,
    bool isRunning,
    bool isPaused,
    bool isInitial,
    Color currentColor,
  ) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const breakColor = Color(0xFF34D399);

    final isStopwatch = timerState.timerType == TimerType.stopwatch;
    final elapsedSec = timerState.elapsedSeconds;
    final stopwatchProgress = (elapsedSec % 1800) / 1800.0;
    final int completedCycles = elapsedSec ~/ 1800;

    final dialProgress = isStopwatch
        ? (timerState.status == TimerStatus.initial ? 0.0 : stopwatchProgress)
        : (isBreak ? 1.0 : timerState.progressRatio);

    return ShowCaseWidget(
      enableAutoScroll: true,
      blurValue: 2.0,
      onFinish: () => TourService().markTourSeen(TourSection.timer),
      builder: (showcaseContext) {
        _triggerTimerTourIfNeeded(showcaseContext);
        return Scaffold(
          backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
              child: Row(
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isBreak
                            ? 'Target reached! Rest your eyes & recharge'
                            : (timerState.isOvertime
                                ? 'In the zone • Recording overtime'
                                : (isStopwatch
                                    ? 'Open-ended study session • Counting up'
                                    : 'Distraction-free target countdown')),
                        style: TextStyle(
                          color: isBreak
                              ? breakColor
                              : (timerState.isOvertime ? accentColor : Colors.blueGrey.shade400),
                          fontSize: 13,
                          fontWeight: (isBreak || timerState.isOvertime) ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isBreak ? breakColor : (timerState.isOvertime ? accentColor : currentColor)).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: (isBreak ? breakColor : (timerState.isOvertime ? accentColor : currentColor)).withOpacity(0.3)),
                    ),
                    child: Text(
                      isBreak
                          ? 'BREAK'
                          : (timerState.isOvertime
                              ? 'OVERTIME'
                              : (isRunning
                                  ? (isStopwatch ? 'STOPWATCH' : 'FOCUS')
                                  : (isPaused ? 'PAUSED' : (isStopwatch ? 'STOPWATCH' : 'READY')))),
                      style: TextStyle(
                        color: isBreak ? breakColor : (timerState.isOvertime ? accentColor : currentColor),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Task 1: Timer Mode Toggle (Target Countdown vs Stopwatch Count-up)
            if (!isBreak)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: TourShowcaseItem(
                  section: TourSection.timer,
                  step: TourStep(
                    key: _keyTimerMode,
                    title: 'Study Modes & Course Tagging',
                    description: 'Toggle between structured Pomodoro intervals with earned breaks or open stopwatch sessions tagged to your courses.',
                  ),
                  stepIndex: 2,
                  totalSteps: 2,
                  child: Container(
                  padding: const EdgeInsets.all(4.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      // Target Mode
                      Expanded(
                        child: GestureDetector(
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: !isStopwatch
                                  ? accentColor.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: !isStopwatch
                                  ? Border.all(color: accentColor.withOpacity(0.4))
                                  : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.track_changes_rounded,
                                    size: 14,
                                    color: !isStopwatch ? accentColor : Colors.blueGrey.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Target (Countdown)',
                                    style: TextStyle(
                                      color: !isStopwatch ? Colors.white : Colors.blueGrey.shade400,
                                      fontSize: 11.5,
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
                        child: GestureDetector(
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isStopwatch
                                  ? const Color(0xFFA78BFA).withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: isStopwatch
                                  ? Border.all(color: const Color(0xFFA78BFA).withOpacity(0.4))
                                  : null,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 14,
                                    color: isStopwatch ? const Color(0xFFA78BFA) : Colors.blueGrey.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Stopwatch (Count-up)',
                                    style: TextStyle(
                                      color: isStopwatch ? Colors.white : Colors.blueGrey.shade400,
                                      fontSize: 11.5,
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
            ),

            // Decoupled Dynamic Subject Dropdown + Manage Subjects Action
            if (!isBreak)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book_rounded, color: accentColor, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Subject: ',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: currentSubject,
                            dropdownColor: const Color(0xFF170F0D),
                            icon: const Icon(Icons.arrow_drop_down_rounded, color: accentColor),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            isExpanded: true,
                            items: timerSubjects.map((subj) {
                              return DropdownMenuItem(
                                value: subj,
                                child: Text(subj, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (newSubj) {
                              if (newSubj != null) {
                                SafeHaptics.lightImpact();
                                timerNotifier.changeSubject(newSubj);
                                if (isRunning || isPaused) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: const Color(0xFF241C1A),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      duration: const Duration(seconds: 2),
                                      content: Text(
                                        'Switched subject to $newSubj. Previous progress saved!',
                                        style: const TextStyle(color: accentColor, fontSize: 12.5),
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, color: Color(0xFFF2B78A), size: 18),
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
              )
            else
              // Break Time Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: breakColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.coffee_rounded, color: breakColor, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Break in progress • Hydrate & relax',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: breakColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'RECHARGE',
                          style: TextStyle(color: breakColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // Main Timer Section with '+' and '-' Adjust Buttons & Breathing Pulse
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Minimalist '-' Decrease Target Button (Hidden in Stopwatch mode or Break)
                  if (!isBreak && !isStopwatch) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          SafeHaptics.lightImpact();
                          timerNotifier.decrementTargetMinutes(5);
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.remove_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],

                  // Circular Timer Dial with Breathing Pulse Animation
                  TourShowcaseItem(
                    section: TourSection.timer,
                    step: TourStep.circle(
                      key: _keyTimerDial,
                      title: 'Focus Session',
                      description: 'Tap to begin tracking your study block with ambient distraction-free focus modes.',
                      targetPadding: const EdgeInsets.all(12),
                    ),
                    stepIndex: 1,
                    totalSteps: 2,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer Ambient Glow Ring (Animated breathing glow)
                              Container(
                                width: 232,
                                height: 232,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: isBreak
                                          ? const Color(0xFF064E3B).withOpacity(0.40)
                                          : (isStopwatch
                                              ? const Color(0xFFA855F7)
                                              : (timerState.isOvertime ? const Color(0xFFF2B78A) : currentColor))
                                              .withOpacity(isRunning ? _glowAnimation.value : 0.08),
                                      blurRadius: isRunning ? (24 + (_pulseController.value * 14)) : 12,
                                      spreadRadius: isRunning ? (1 + (_pulseController.value * 3)) : 0,
                                    ),
                                  ],
                                ),
                              ),

                              // Custom Dial with 30-min sweep, 5-min interval ticks, tip glow & deep obsidian fill
                              SizedBox(
                                width: 220,
                                height: 220,
                                child: CustomPaint(
                                  painter: TimerDialPainter(
                                    progress: dialProgress,
                                    isStopwatch: isStopwatch,
                                    primaryColor: isBreak
                                        ? const Color(0xFF34D399)
                                        : (timerState.isOvertime
                                            ? const Color(0xFFF2B78A)
                                            : (isStopwatch ? const Color(0xFFF2B78A) : currentColor)),
                                    secondaryColor: const Color(0xFFA855F7),
                                    trackColor: isBreak
                                        ? const Color(0xFF0F1412)
                                        : (timerState.isOvertime
                                            ? const Color(0xFFF2B78A)
                                            : const Color(0xFF261D1A)),
                                    dialFillColor: isBreak ? const Color(0xFF0F1412) : const Color(0xFF1A1513),
                                    borderColor: isBreak ? const Color(0xFF1A2420) : const Color(0xFF2D2420),
                                    glowColor: isBreak ? const Color(0xFF064E3B).withOpacity(0.40) : null,
                                    strokeWidth: 9.0,
                                  ),
                                ),
                              ),

                              // Center Time Display (MM:SS or HH:MM:SS)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    timerState.formattedTime,
                                    style: TextStyle(
                                      color: isBreak ? const Color(0xFFF5EBE6) : Colors.white,
                                      fontSize: isBreak ? 34 : 40,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -1.0,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    isBreak
                                        ? 'Earned Rest • 5:1 Focus Ratio'
                                        : (timerState.isOvertime
                                            ? 'Overtime • Deep Focus'
                                            : (isStopwatch
                                                ? (completedCycles == 0
                                                    ? 'Cycle 1 (0–30m)'
                                                    : 'Cycle ${completedCycles + 1} • ${completedCycles * 30}m+ completed')
                                                : 'Target: ${(timerState.targetSeconds ~/ 60)} min')),
                                    style: TextStyle(
                                      color: isBreak
                                          ? const Color(0xFF7B968B)
                                          : (timerState.isOvertime
                                              ? const Color(0xFFF2B78A)
                                              : (isStopwatch ? const Color(0xFFD4B8FF) : Colors.blueGrey.shade400)),
                                      fontSize: 12.0,
                                      fontWeight: (isBreak || timerState.isOvertime || isStopwatch) ? FontWeight.w600 : FontWeight.w500,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Minimalist '+' Increase Target Button (Hidden in Stopwatch mode or Break)
                  if (!isBreak && !isStopwatch) ...[
                    const SizedBox(width: 14),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          SafeHaptics.lightImpact();
                          timerNotifier.incrementTargetMinutes(5);
                        },
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: cardColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.add_rounded,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (!isBreak) ...[
              const SizedBox(height: 20),

              // Smart Break System Display (Accumulated Break Time)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
                margin: const EdgeInsets.symmetric(horizontal: 28.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1513),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF059669).withOpacity(0.3),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF059669).withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '☕ Earned Break: ${timerState.formattedEarnedBreak} • 5:1 ratio',
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // Quick Preset Selection Chips (Hidden in Stopwatch mode)
            if (isInitial && !isBreak && !isStopwatch) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [25, 50, 90].map((mins) {
                    final isSelected = (timerState.targetSeconds ~/ 60) == mins;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5.0),
                      child: ChoiceChip(
                        label: Text('${mins}m'),
                        selected: isSelected,
                        selectedColor: accentColor.withOpacity(0.2),
                        backgroundColor: cardColor,
                        side: BorderSide(
                          color: isSelected ? accentColor : const Color(0xFF4A3830),
                        ),
                        labelStyle: TextStyle(
                          color: isSelected ? accentColor : const Color(0xFFABA093),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12,
                        ),
                        onSelected: (_) {
                          SafeHaptics.lightImpact();
                          timerNotifier.setTargetMinutes(mins);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 0, 20.0, 32.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isInitial) ...[
                    // Idle state: Single primary "Start Session" button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          if (timerState.selectedSubject != currentSubject) {
                            timerNotifier.changeSubject(currentSubject);
                          }
                          timerNotifier.toggleStartPause();
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: const Text(
                          'Start Session',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isStopwatch ? const Color(0xFFA855F7) : accentColor,
                          foregroundColor: const Color(0xFF140F0E),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                          shadowColor: (isStopwatch ? const Color(0xFFA855F7) : accentColor).withOpacity(0.3),
                        ),
                      ),
                    ),
                  ] else if (isBreak) ...[
                    // Break Screen 3-button Control Dock
                    // 1. [Pause / Resume]: Square subtle icon button with 8px corner radius, border #232B27, bg #141B18, icon #7B968B
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF141B18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF232B27),
                          width: 1.2,
                        ),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          timerNotifier.toggleStartPause();
                        },
                        icon: Icon(
                          isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: const Color(0xFF7B968B),
                          size: 22,
                        ),
                        tooltip: isRunning ? 'Pause' : 'Resume',
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 2. [Next Focus]: Wide primary pill button, Warm Peach #F2B78A, dark bold text "Next Focus" with arrow icon
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            SafeHaptics.heavyImpact();
                            timerNotifier.endBreak();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).hideCurrentSnackBar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFFF2B78A),
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  content: const Text(
                                    '🎯 Ready for your next focus session! Let\'s do this.',
                                    style: TextStyle(
                                      color: Color(0xFF140F0E),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 19,
                            color: Color(0xFF140F0E),
                          ),
                          label: const Text(
                            'Next Focus',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF140F0E),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF2B78A),
                            foregroundColor: const Color(0xFF140F0E),
                            elevation: 3,
                            shadowColor: const Color(0xFFF2B78A).withOpacity(0.35),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 3. [End]: Square compact button with red border #382323, bg #141B18, red icon #FF6B6B -> ends session completely
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF141B18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF382323),
                          width: 1.2,
                        ),
                      ),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          SafeHaptics.heavyImpact();
                          timerNotifier.endSession();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF241C1A),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                content: const Text(
                                  'Break ended.',
                                  style: TextStyle(
                                    color: Color(0xFFABA093),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.stop_rounded,
                          color: Color(0xFFFF6B6B),
                          size: 22,
                        ),
                        tooltip: 'End Break',
                      ),
                    ),
                  ] else ...[
                    // Active / Break Session: Exactly 3 Clear Controls:
                    // 1. Pause / Resume toggle
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          timerNotifier.toggleStartPause();
                        },
                        icon: Icon(
                          isRunning ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                        label: Text(
                          isRunning ? 'Pause' : 'Resume',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isStopwatch ? const Color(0xFFA855F7) : currentColor,
                          foregroundColor: const Color(0xFF140F0E),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                          shadowColor: (isStopwatch ? const Color(0xFFA855F7) : currentColor).withOpacity(0.3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 2. Finish Session (logs time, opens Journal popup) / Next Focus (in Break)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          SafeHaptics.heavyImpact();
                          final metadata = timerNotifier.prepareSessionCompletion();
                          final totalSecs = metadata.totalDurationSeconds;
                          int calculatedMins = (totalSecs / 60).round();
                          if (calculatedMins == 0 && totalSecs >= 15) calculatedMins = 1;

                          if (calculatedMins > 0) {
                            await ref.read(userProfileProvider.notifier).addFocusMinutes(calculatedMins);
                          }

                          if (context.mounted) {
                            _showPostSessionDialog(
                              context,
                              metadata: metadata,
                              subject: metadata.courseTitle,
                              durationMinutes: calculatedMins > 0 ? calculatedMins : 1,
                            );
                          }
                        },
                        icon: const Icon(
                          Icons.check_circle_rounded,
                          size: 19,
                        ),
                        label: const Text(
                          'Finish',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF34D399),
                          backgroundColor: const Color(0xFF1A1513),
                          side: BorderSide(
                            color: const Color(0xFF059669).withOpacity(0.5),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // 3. Discard / Cancel (replaces "End" button; red #FF5964, calls discardSession(), dismisses timer to idle without logging)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          SafeHaptics.heavyImpact();
                          timerNotifier.discardSession();
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF241C1A),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFFF5964), width: 1),
                              ),
                              content: const Text(
                                'Session discarded.',
                                style: TextStyle(
                                  color: Color(0xFFFF5964),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.close_rounded, size: 19),
                        label: const Text(
                          'Discard',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF5964),
                          backgroundColor: const Color(0xFF1A1513),
                          side: BorderSide(
                            color: const Color(0xFFFF5964).withOpacity(0.4),
                            width: 1.2,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  /// Modal for adding/deleting timer-specific subjects without altering Syllabus
  void _showManageSubjectsModal(BuildContext context, WidgetRef ref) {
    final customCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
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
                      const Text(
                        'Manage Timer Subjects',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.blueGrey, size: 20),
                        onPressed: () {
                          SafeHaptics.lightImpact();
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Custom timer subjects are saved to your profile. Modifying this list does NOT alter your Syllabus or delete past study logs.',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
                  ),
                  const SizedBox(height: 16),

                  // Add Custom Subject Input Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: customCtrl,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Enter new custom subject...',
                            hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12.5),
                            filled: true,
                            fillColor: const Color(0xFF170F0D),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF4A3830)),
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
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                duration: const Duration(seconds: 2),
                                content: Text('Added "$text" to timer subjects.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF2B78A),
                          foregroundColor: const Color(0xFF140F0E),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Current Subjects List
                  const Text(
                    'CURRENT TIMER SUBJECTS',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 10.5, fontWeight: FontWeight.bold),
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
                            color: const Color(0xFF170F0D),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF4A3830)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  subj,
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (subjects.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.pinkAccent, size: 18),
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
        barrierColor: Colors.black.withOpacity(0.65),
        builder: (dialogCtx) => StudySessionLogDialog(
          metadata: metadata,
          subjectOrCourseName: resolvedSubject,
          subjectOrCourseId: resolvedId,
          durationMinutes: metadata?.durationMinutes ?? durationMinutes ?? 1,
          mode: mode,
        ),
      );
    } finally {
      _isPostSessionDialogOpen = false;
      // On modal dismissal / save / skip:
      // Transition immediately to FocusTimerMode.breakRunning and begin ticking earned break clock
      if (mounted) {
        ref.read(timerProvider.notifier).startBreakAfterSession();
      }
    }
  }
}


/// Custom painter for Timer & Stopwatch circular dial with 5-minute ticks,
/// smooth multi-color gradient sweep arc, tip glow, and deep obsidian finish.
class TimerDialPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final bool isStopwatch;
  final Color primaryColor;
  final Color secondaryColor;
  final Color trackColor;
  final Color dialFillColor;
  final Color borderColor;
  final Color? glowColor;
  final double strokeWidth;

  const TimerDialPainter({
    required this.progress,
    required this.isStopwatch,
    this.primaryColor = const Color(0xFFF2B78A),
    this.secondaryColor = const Color(0xFFA855F7),
    this.trackColor = const Color(0xFF261D1A),
    this.dialFillColor = const Color(0xFF1A1513),
    this.borderColor = const Color(0xFF2D2420),
    this.glowColor,
    this.strokeWidth = 9.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final arcRadius = (size.width - strokeWidth) / 2;

    // 1. Darken base dial fill to deep obsidian (#1A1513)
    final fillPaint = Paint()
      ..color = dialFillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, fillPaint);

    // 2. Soft outer ring border (#2D2420)
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, outerRadius - 0.75, borderPaint);

    // 3. Background track for the progress arc
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, arcRadius, trackPaint);

    // 4. Subtle 5-minute interval ticks/dots along the inner rim
    // 6 ticks for 30 minutes (0, 5, 10, 15, 20, 25 minutes)
    final tickDistance = arcRadius - (strokeWidth / 2) - 8.0;
    const tickCount = 6;
    for (int i = 0; i < tickCount; i++) {
      final tickAngle = -math.pi / 2 + (2 * math.pi * i / tickCount);
      final tickX = center.dx + tickDistance * math.cos(tickAngle);
      final tickY = center.dy + tickDistance * math.sin(tickAngle);

      final tickProgress = i / tickCount;
      final isReached = progress >= tickProgress && progress > 0.001;

      final tickPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = isReached
            ? primaryColor.withOpacity(0.85)
            : const Color(0xFF523F37).withOpacity(0.55);

      final dotRadius = (i == 0) ? 2.8 : 2.0;
      canvas.drawCircle(Offset(tickX, tickY), dotRadius, tickPaint);
    }

    // 5. Active elapsed arc with StrokeCap.round and smooth gradient (Peach #F2B78A to Purple #A855F7)
    final clampedProgress = progress.clamp(0.0, 1.0);
    if (clampedProgress > 0.001) {
      final sweepAngle = 2 * math.pi * clampedProgress;
      final rect = Rect.fromCircle(center: center, radius: arcRadius);

      final List<Color> gradientColors = isStopwatch
          ? [primaryColor, secondaryColor]
          : [primaryColor.withOpacity(0.9), primaryColor];

      final gradient = SweepGradient(
        startAngle: 0.0,
        endAngle: math.max(0.05, sweepAngle),
        colors: gradientColors,
        transform: const GradientRotation(-math.pi / 2),
      );

      final arcPaint = Paint()
        ..shader = gradient.createShader(rect)
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

      // 6. Soft radial glow / drop shadow behind active arc tip
      final tipAngle = -math.pi / 2 + sweepAngle;
      final tipX = center.dx + arcRadius * math.cos(tipAngle);
      final tipY = center.dy + arcRadius * math.sin(tipAngle);
      final tipCenter = Offset(tipX, tipY);

      final effectiveGlow = glowColor ?? (isStopwatch ? secondaryColor : primaryColor);
      final tipGlowPaint = Paint()
        ..color = effectiveGlow.withOpacity(0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(tipCenter, strokeWidth * 0.9, tipGlowPaint);

      // Crisp inner highlight pip at the arc tip
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
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.dialFillColor != dialFillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

