import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/session_metadata.dart';
import '../services/notification_service.dart';
import 'timer_subjects_provider.dart';

export '../models/session_metadata.dart';

/// Explicit Timer States for the Finite State Machine (FSM)
enum FocusTimerMode {
  idle,
  focusRunning,
  focusPaused,
  overtimeRunning,   // Active when countdown reaches 00:00:00 and keeps counting UP
  sessionCompleted,  // Journal modal is active
  breakRunning,      // Active rest clock
  breakPaused,
}

enum TimerMode {
  focus,
  breakTime,
  extraTime,
}

enum TimerType {
  target, // Countdown from target duration
  stopwatch, // Open-ended count-up starting from 00:00:00
}

enum TimerStatus {
  initial,
  running,
  paused,
}

class TimerState {
  final TimerMode mode;
  final TimerStatus status;
  final FocusTimerMode focusMode;
  final TimerType timerType;
  final int elapsedSeconds;
  final int targetSeconds;
  final int overtimeSeconds;
  final int breakDurationSeconds;
  final int breakElapsedSeconds;
  final int extraElapsedSeconds;
  final String selectedSubject;
  final int currentSubjectElapsedSeconds;
  final SessionMetadata? sessionMetadata;

  const TimerState({
    required this.mode,
    required this.status,
    this.focusMode = FocusTimerMode.idle,
    this.timerType = TimerType.target,
    required this.elapsedSeconds,
    required this.targetSeconds,
    this.overtimeSeconds = 0,
    this.breakDurationSeconds = 300,
    this.breakElapsedSeconds = 0,
    this.extraElapsedSeconds = 0,
    this.selectedSubject = 'General Study',
    this.currentSubjectElapsedSeconds = 0,
    this.sessionMetadata,
  });

  /// Total logged focus seconds across target and overtime (or elapsed for stopwatch)
  int get totalLoggedSeconds {
    if (timerType == TimerType.target) {
      if (focusMode == FocusTimerMode.overtimeRunning || overtimeSeconds > 0) {
        return targetSeconds + overtimeSeconds;
      }
      return elapsedSeconds;
    }
    return elapsedSeconds;
  }

  /// Calculates earned break time: 5:1 focus ratio (1/5th ratio of total logged focus)
  int get earnedBreakSeconds {
    return (totalLoggedSeconds / 5).floor();
  }

  /// Formatted string for earned break duration (e.g., "5m 00s")
  String get formattedEarnedBreak {
    final totalSecs = earnedBreakSeconds;
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  /// Helper boolean getters
  bool get isOvertime => focusMode == FocusTimerMode.overtimeRunning || overtimeSeconds > 0;
  bool get isBreak => mode == TimerMode.breakTime ||
      focusMode == FocusTimerMode.breakRunning ||
      focusMode == FocusTimerMode.breakPaused;
  bool get isBreakRunning => focusMode == FocusTimerMode.breakRunning;
  bool get isBreakPaused => focusMode == FocusTimerMode.breakPaused;
  int get targetMinutes => (targetSeconds / 60).round();

  /// Formats time:
  /// 1. Overtime: +MM:SS or +H:MM:SS
  /// 2. Break Mode: MM:SS countdown of break time remaining (e.g., 05:00 -> 00:00)
  /// 3. Extra Time Mode: +MM:SS or +H:MM:SS
  /// 4. Stopwatch Mode: HH:MM:SS or MM:SS (open-ended study count-up)
  /// 5. Target Mode: MM:SS or HH:MM:SS strictly counting DOWN the target focus time.
  String get formattedTime {
    if (focusMode == FocusTimerMode.overtimeRunning || (mode == TimerMode.extraTime && overtimeSeconds > 0)) {
      final displaySecs = overtimeSeconds;
      final hours = displaySecs ~/ 3600;
      final minutes = ((displaySecs % 3600) ~/ 60).toString().padLeft(2, '0');
      final seconds = (displaySecs % 60).toString().padLeft(2, '0');
      final baseTime = hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
      return '+$baseTime';
    }

    if (isBreak) {
      final remainingBreak = (breakDurationSeconds - breakElapsedSeconds).clamp(0, breakDurationSeconds);
      final minutes = (remainingBreak ~/ 60).toString().padLeft(2, '0');
      final seconds = (remainingBreak % 60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }

    if (mode == TimerMode.extraTime) {
      final displaySecs = extraElapsedSeconds;
      final hours = displaySecs ~/ 3600;
      final minutes = ((displaySecs % 3600) ~/ 60).toString().padLeft(2, '0');
      final seconds = (displaySecs % 60).toString().padLeft(2, '0');
      final baseTime = hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
      return '+$baseTime';
    }

    if (timerType == TimerType.stopwatch) {
      final displaySecs = elapsedSeconds;
      final hours = (displaySecs ~/ 3600).toString().padLeft(2, '0');
      final minutes = ((displaySecs % 3600) ~/ 60).toString().padLeft(2, '0');
      final seconds = (displaySecs % 60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }

    // Target Countdown Mode
    final remainingSecs = (targetSeconds - elapsedSeconds).clamp(0, targetSeconds);
    final hours = remainingSecs ~/ 3600;
    final minutes = ((remainingSecs % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (remainingSecs % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  /// Progress ratio from 0.0 to 1.0
  double get progressRatio {
    if (isBreak) {
      if (breakDurationSeconds <= 0) return 0.0;
      return (breakElapsedSeconds / breakDurationSeconds).clamp(0.0, 1.0);
    }
    if (focusMode == FocusTimerMode.overtimeRunning) {
      return 1.0;
    }
    if (mode == TimerMode.extraTime) return 1.0;
    if (timerType == TimerType.stopwatch) {
      if (status == TimerStatus.initial) return 0.0;
      return ((elapsedSeconds % 1800) / 1800.0);
    }
    if (targetSeconds <= 0) return 0.0;
    return (elapsedSeconds / targetSeconds).clamp(0.0, 1.0);
  }

  TimerState copyWith({
    TimerMode? mode,
    TimerStatus? status,
    FocusTimerMode? focusMode,
    TimerType? timerType,
    int? elapsedSeconds,
    int? targetSeconds,
    int? overtimeSeconds,
    int? breakDurationSeconds,
    int? breakElapsedSeconds,
    int? extraElapsedSeconds,
    String? selectedSubject,
    int? currentSubjectElapsedSeconds,
    SessionMetadata? sessionMetadata,
  }) {
    return TimerState(
      mode: mode ?? this.mode,
      status: status ?? this.status,
      focusMode: focusMode ?? this.focusMode,
      timerType: timerType ?? this.timerType,
      elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      overtimeSeconds: overtimeSeconds ?? this.overtimeSeconds,
      breakDurationSeconds: breakDurationSeconds ?? this.breakDurationSeconds,
      breakElapsedSeconds: breakElapsedSeconds ?? this.breakElapsedSeconds,
      extraElapsedSeconds: extraElapsedSeconds ?? this.extraElapsedSeconds,
      selectedSubject: selectedSubject ?? this.selectedSubject,
      currentSubjectElapsedSeconds: currentSubjectElapsedSeconds ?? this.currentSubjectElapsedSeconds,
      sessionMetadata: sessionMetadata ?? this.sessionMetadata,
    );
  }
}

final timerProvider = StateNotifierProvider<TimerNotifier, TimerState>((ref) {
  final subjects = ref.watch(timerSubjectsProvider);
  final initialSubj = subjects.isNotEmpty ? subjects.first : 'General Study';
  final notifier = TimerNotifier(initialSubject: initialSubj);

  ref.listen<List<String>>(timerSubjectsProvider, (_, next) {
    notifier.syncSubject(next);
  });

  return notifier;
});

class TimerNotifier extends StateNotifier<TimerState> {
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final NotificationService? _customNotificationService;
  Timer? _ticker;
  Timer? _abandonedPauseTimer;
  DateTime? _lastTickTime;
  String? _lastBurnoutAlertDate;

  FirebaseFirestore? get _firestore {
    if (_customFirestore != null) return _customFirestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  NotificationService get _notificationService =>
      _customNotificationService ?? NotificationService();

  TimerNotifier({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
    String? initialSubject,
  })  : _customFirestore = firestore,
        _customAuth = auth,
        _customNotificationService = notificationService,
        super(TimerState(
          mode: TimerMode.focus,
          status: TimerStatus.initial,
          elapsedSeconds: 0,
          targetSeconds: 1500, // Default 25 minutes
          breakElapsedSeconds: 0,
          selectedSubject: initialSubject ?? 'General Study',
          currentSubjectElapsedSeconds: 0,
        ));

  /// Sets target duration in minutes and resets timer state to focus countdown
  void setTargetMinutes(int minutes) {
    final seconds = (minutes * 60).clamp(60, 10800);
    final breakDuration = (seconds / 5).floor().clamp(60, 3600);
    state = state.copyWith(
      targetSeconds: seconds,
      breakDurationSeconds: breakDuration,
      mode: TimerMode.focus,
      focusMode: state.status == TimerStatus.initial ? FocusTimerMode.idle : state.focusMode,
      elapsedSeconds: state.status == TimerStatus.initial ? 0 : state.elapsedSeconds,
      overtimeSeconds: 0,
      breakElapsedSeconds: 0,
      extraElapsedSeconds: 0,
    );
  }

  /// Increments target time
  void incrementTargetMinutes([int stepMinutes = 5]) {
    final newTarget = (state.targetSeconds + (stepMinutes * 60)).clamp(300, 10800);
    final breakDuration = (newTarget / 5).floor().clamp(60, 3600);
    state = state.copyWith(
      targetSeconds: newTarget,
      breakDurationSeconds: breakDuration,
      mode: state.status == TimerStatus.initial ? TimerMode.focus : state.mode,
      focusMode: state.status == TimerStatus.initial ? FocusTimerMode.idle : state.focusMode,
      elapsedSeconds: state.status == TimerStatus.initial ? 0 : state.elapsedSeconds,
      overtimeSeconds: 0,
      breakElapsedSeconds: 0,
      extraElapsedSeconds: 0,
    );
  }

  /// Decrements target time
  void decrementTargetMinutes([int stepMinutes = 5]) {
    final newTarget = (state.targetSeconds - (stepMinutes * 60)).clamp(300, 10800);
    final breakDuration = (newTarget / 5).floor().clamp(60, 3600);
    state = state.copyWith(
      targetSeconds: newTarget,
      breakDurationSeconds: breakDuration,
      mode: state.status == TimerStatus.initial ? TimerMode.focus : state.mode,
      focusMode: state.status == TimerStatus.initial ? FocusTimerMode.idle : state.focusMode,
      elapsedSeconds: state.status == TimerStatus.initial ? 0 : state.elapsedSeconds,
      overtimeSeconds: 0,
      breakElapsedSeconds: 0,
      extraElapsedSeconds: 0,
    );
  }

  /// Real-time Subject Switching while timer is running or paused
  Future<void> changeSubject(String newSubject) async {
    if (newSubject == state.selectedSubject) return;

    final prevSubject = state.selectedSubject;
    final prevElapsed = state.currentSubjectElapsedSeconds;

    // Immediately write the elapsed time for the old subject to Firestore
    if (prevElapsed > 0 && state.mode != TimerMode.breakTime) {
      unawaited(_logFocusSegment(prevSubject, prevElapsed));
    }

    // Reset internal elapsed tracker for subject, keep overall clock running
    state = state.copyWith(
      selectedSubject: newSubject,
      currentSubjectElapsedSeconds: 0,
    );

    // Update persistent notification with new subject immediately
    if (state.status == TimerStatus.running || state.status == TimerStatus.paused) {
      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.mode == TimerMode.breakTime ? 'Break Time ☕' : newSubject,
        isRunning: state.status == TimerStatus.running,
        isBreakMode: state.mode == TimerMode.breakTime,
      );
    }
  }

  /// Synchronizes current subject with available subjects when timer is idle
  void syncSubject(List<String> availableSubjects) {
    if (state.status == TimerStatus.initial) {
      if (availableSubjects.isEmpty) {
        state = state.copyWith(selectedSubject: 'General Study');
      } else if (!availableSubjects.contains(state.selectedSubject)) {
        state = state.copyWith(selectedSubject: availableSubjects.first);
      }
    }
  }

  /// Task 3: Log focus segment to Firestore & Trigger Rolling Streak Protector
  Future<void> _logFocusSegment(String subject, int durationSeconds) async {
    final firestore = _firestore;
    final auth = _auth;
    if (firestore == null || auth == null) return;

    final uid = auth.currentUser?.uid;
    if (uid == null || durationSeconds <= 0) return;

    int mins = (durationSeconds / 60).round();
    if (mins == 0 && durationSeconds >= 15) mins = 1;

    final now = DateTime.now();
    final startTime = now.subtract(Duration(seconds: durationSeconds));

    try {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .add({
        'subject': subject,
        'subjectName': subject,
        'durationSeconds': durationSeconds,
        'durationMinutes': mins,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('Logged focus session ($mins mins, $durationSeconds s) for "$subject"');

      // Task 3: Schedule rolling streak protector for 9:00 PM tomorrow (dead-man's switch)
      unawaited(_notificationService.scheduleStreakProtectorReminder());

      // Task 1 & 2: Burnout Guard Daily Focus Hours Audit & Alert
      unawaited(_checkBurnoutThreshold(uid));
    } catch (e) {
      debugPrint('Error writing focus session to Firestore: $e');
    }
  }

  /// Task 1 & 2: Calculates total focus hours for current calendar day and triggers Burnout Guard alert if >= 12h (720m)
  Future<void> _checkBurnoutThreshold(String uid) async {
    final firestore = _firestore;
    if (firestore == null) return;

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfToday))
          .get();

      int totalMinutesToday = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        totalMinutesToday += (data['durationMinutes'] as num?)?.toInt() ?? 0;
      }

      if (totalMinutesToday >= 720) {
        final todayStr = '${now.year}-${now.month}-${now.day}';
        if (_lastBurnoutAlertDate != todayStr) {
          _lastBurnoutAlertDate = todayStr;
          await _notificationService.showBurnoutGuardNotification();
          debugPrint('Burnout Guard triggered: $totalMinutesToday mins focus today');
        }
      }
    } catch (e) {
      debugPrint('Error checking burnout threshold: $e');
    }
  }

  DateTime? _sessionStartTime;

  /// Toggle start/pause timer
  void toggleStartPause() {
    if (state.status == TimerStatus.running) {
      pauseTimer();
    } else {
      startTimer();
    }
  }

  void _enableWakelock() {
    try {
      WakelockPlus.enable().catchError((e) {
        debugPrint('Error enabling Wakelock: $e');
      });
    } catch (e) {
      debugPrint('Error enabling Wakelock: $e');
    }
  }

  void _disableWakelock() {
    try {
      WakelockPlus.disable().catchError((e) {
        debugPrint('Error disabling Wakelock: $e');
      });
    } catch (e) {
      debugPrint('Error disabling Wakelock: $e');
    }
  }

  /// Starts or resumes the timer with persistent low-priority notification
  void startTimer() {
    if (state.status == TimerStatus.running) return;

    // Cancel abandoned pause background timer and dismiss any pending nudge
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _notificationService.cancelAbandonedPauseNudge();

    if (state.status == TimerStatus.initial) {
      _sessionStartTime = DateTime.now();
      final breakDur = (state.targetSeconds / 5).floor().clamp(60, 3600);
      state = state.copyWith(
        mode: TimerMode.focus,
        focusMode: FocusTimerMode.focusRunning,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        overtimeSeconds: 0,
        breakDurationSeconds: breakDur,
        breakElapsedSeconds: 0,
        extraElapsedSeconds: 0,
      );
    } else {
      final newFocusMode = state.isBreak
          ? FocusTimerMode.breakRunning
          : (state.overtimeSeconds > 0
              ? FocusTimerMode.overtimeRunning
              : FocusTimerMode.focusRunning);
      state = state.copyWith(
        status: TimerStatus.running,
        focusMode: newFocusMode,
      );
    }
    _lastTickTime = DateTime.now();

    _enableWakelock();

    // Show persistent notification
    _notificationService.showTimerNotification(
      timeRemaining: state.formattedTime,
      subject: state.isBreak
          ? 'Break Time ☕'
          : (state.isOvertime ? '${state.selectedSubject} (Overtime)' : state.selectedSubject),
      isRunning: true,
      isBreakMode: state.isBreak,
    );

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _onTick();
    });
  }

  /// Catches up missed time when returning from background or screen-off
  void catchUp(int additionalSeconds) {
    if (state.status != TimerStatus.running || additionalSeconds <= 0) return;

    _lastTickTime = DateTime.now();

    if (state.isBreak) {
      final nextBreak = (state.breakElapsedSeconds + additionalSeconds).clamp(0, state.breakDurationSeconds);
      state = state.copyWith(breakElapsedSeconds: nextBreak);
      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: 'Break Time ☕',
        isRunning: true,
        isBreakMode: true,
      );
      return;
    }

    if (state.focusMode == FocusTimerMode.overtimeRunning || state.overtimeSeconds > 0) {
      final nextOvertime = state.overtimeSeconds + additionalSeconds;
      final nextSubjElapsed = state.currentSubjectElapsedSeconds + additionalSeconds;
      state = state.copyWith(
        overtimeSeconds: nextOvertime,
        currentSubjectElapsedSeconds: nextSubjElapsed,
        focusMode: FocusTimerMode.overtimeRunning,
      );
      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: '${state.selectedSubject} (Overtime)',
        isRunning: true,
        isBreakMode: false,
      );
      return;
    }

    final nextElapsed = state.elapsedSeconds + additionalSeconds;
    final nextSubjElapsed = state.currentSubjectElapsedSeconds + additionalSeconds;

    if (state.timerType == TimerType.target && nextElapsed >= state.targetSeconds) {
      // Reached 00:00:00 countdown! Do NOT auto-switch to break.
      // Transition immediately to FocusTimerMode.overtimeRunning and count up.
      final excessSeconds = nextElapsed - state.targetSeconds;
      state = state.copyWith(
        elapsedSeconds: state.targetSeconds,
        overtimeSeconds: excessSeconds,
        currentSubjectElapsedSeconds: nextSubjElapsed,
        focusMode: FocusTimerMode.overtimeRunning,
      );

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: '${state.selectedSubject} (Overtime)',
        isRunning: true,
        isBreakMode: false,
      );
    } else {
      state = state.copyWith(
        elapsedSeconds: nextElapsed,
        currentSubjectElapsedSeconds: nextSubjElapsed,
      );

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.selectedSubject,
        isRunning: true,
        isBreakMode: false,
      );
    }
  }

  /// Finite State Machine Tick execution:
  /// - Break countdown ticks towards 0
  /// - Overtime ticks UP (+00:01, +00:02...)
  /// - Countdown ticks DOWN to 0, then immediately transitions to Overtime without stopping
  void _onTick() {
    if (state.status != TimerStatus.running) return;

    final now = DateTime.now();
    final deltaSeconds = _lastTickTime != null ? now.difference(_lastTickTime!).inSeconds : 1;

    if (deltaSeconds <= 0) return;
    _lastTickTime = now;

    // 1. Break countdown mode
    if (state.isBreak) {
      final nextBreak = state.breakElapsedSeconds + deltaSeconds;
      if (nextBreak >= state.breakDurationSeconds) {
        state = state.copyWith(breakElapsedSeconds: state.breakDurationSeconds);
      } else {
        state = state.copyWith(breakElapsedSeconds: nextBreak);
      }

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: 'Break Time ☕',
        isRunning: true,
        isBreakMode: true,
      );
      return;
    }

    // 2. Overtime Running mode
    if (state.focusMode == FocusTimerMode.overtimeRunning || state.overtimeSeconds > 0) {
      final nextOvertime = state.overtimeSeconds + deltaSeconds;
      final nextSubjElapsed = state.currentSubjectElapsedSeconds + deltaSeconds;

      state = state.copyWith(
        overtimeSeconds: nextOvertime,
        currentSubjectElapsedSeconds: nextSubjElapsed,
        focusMode: FocusTimerMode.overtimeRunning,
      );

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: '${state.selectedSubject} (Overtime)',
        isRunning: true,
        isBreakMode: false,
      );
      return;
    }

    // 3. Focus countdown / stopwatch mode
    final nextElapsed = state.elapsedSeconds + deltaSeconds;
    final nextSubjElapsed = state.currentSubjectElapsedSeconds + deltaSeconds;

    if (state.timerType == TimerType.target && nextElapsed >= state.targetSeconds) {
      // Countdown reached 00:00:00!
      // Do NOT stop and do NOT auto-switch to break mode.
      // Transition immediately to FocusTimerMode.overtimeRunning and count UP.
      final excess = nextElapsed - state.targetSeconds;
      state = state.copyWith(
        elapsedSeconds: state.targetSeconds,
        overtimeSeconds: excess,
        currentSubjectElapsedSeconds: nextSubjElapsed,
        focusMode: FocusTimerMode.overtimeRunning,
      );

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: '${state.selectedSubject} (Overtime)',
        isRunning: true,
        isBreakMode: false,
      );
    } else {
      state = state.copyWith(
        elapsedSeconds: nextElapsed,
        currentSubjectElapsedSeconds: nextSubjElapsed,
        focusMode: FocusTimerMode.focusRunning,
      );

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.selectedSubject,
        isRunning: true,
        isBreakMode: false,
      );
    }
  }

  /// Skip break and immediately transition to Extra Time countup or idle
  void skipBreak() {
    if (state.isBreak) {
      endBreak();
    }
  }

  /// Sets timer type: Target Mode (Countdown) vs Stopwatch Mode (Count-up)
  void setTimerType(TimerType type) {
    if (state.timerType == type) return;
    if (state.status == TimerStatus.running) return;

    state = state.copyWith(
      timerType: type,
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      elapsedSeconds: 0,
      overtimeSeconds: 0,
      breakElapsedSeconds: 0,
      extraElapsedSeconds: 0,
      currentSubjectElapsedSeconds: 0,
    );
  }

  /// Pauses the running timer and starts a 15-minute background timer for the "Abandoned Pause" nudge
  void pauseTimer() {
    if (state.status == TimerStatus.running) {
      _ticker?.cancel();
      _lastTickTime = null;

      final newFocusMode = state.isBreak
          ? FocusTimerMode.breakPaused
          : FocusTimerMode.focusPaused;

      state = state.copyWith(
        status: TimerStatus.paused,
        focusMode: newFocusMode,
      );

      _disableWakelock();

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.isBreak
            ? 'Break Time ☕'
            : (state.isOvertime ? '${state.selectedSubject} (Overtime)' : state.selectedSubject),
        isRunning: false,
        isBreakMode: state.isBreak,
      );

      // Start 15-minute background timer for "Abandoned Pause" Nudge
      _abandonedPauseTimer?.cancel();
      _abandonedPauseTimer = Timer(const Duration(minutes: 15), () {
        if (state.status == TimerStatus.paused) {
          _notificationService.showAbandonedPauseNudge();
        }
      });
    }
  }

  /// Prepares session completion:
  /// 1. Pauses timer ticks.
  /// 2. Sets state to FocusTimerMode.sessionCompleted.
  /// 3. Builds immutable SessionMetadata snapshot for course isolation.
  /// 4. Asynchronously logs focus segment to Firestore.
  SessionMetadata prepareSessionCompletion() {
    _ticker?.cancel();
    _lastTickTime = null;
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _notificationService.cancelAbandonedPauseNudge();
    _disableWakelock();

    final now = DateTime.now();
    final totalSecs = state.totalLoggedSeconds;
    final startTime = _sessionStartTime ?? now.subtract(Duration(seconds: totalSecs));

    final metadata = SessionMetadata.fromSubject(
      state.selectedSubject,
      totalDurationSeconds: totalSecs,
      sessionStartTime: startTime,
      sessionEndTime: now,
    );

    state = state.copyWith(
      status: TimerStatus.paused,
      focusMode: FocusTimerMode.sessionCompleted,
      sessionMetadata: metadata,
    );

    if (totalSecs > 0) {
      unawaited(_logFocusSegment(state.selectedSubject, totalSecs));
    }

    return metadata;
  }

  /// Automatically launches the earned break clock after journal modal dismissal / save / skip:
  /// 1. Calculates earnedBreakSeconds = totalLoggedSeconds / 5.
  /// 2. Sets state to FocusTimerMode.breakRunning.
  /// 3. Starts ticking immediately.
  void startBreakAfterSession() {
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _notificationService.cancelAbandonedPauseNudge();

    final earnedBreak = state.earnedBreakSeconds.clamp(60, 7200);

    state = state.copyWith(
      mode: TimerMode.breakTime,
      focusMode: FocusTimerMode.breakRunning,
      status: TimerStatus.running,
      breakDurationSeconds: earnedBreak,
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      currentSubjectElapsedSeconds: 0,
    );

    _enableWakelock();
    _notificationService.showBreakAlertNotification();
    _notificationService.showTimerNotification(
      timeRemaining: state.formattedTime,
      subject: 'Break Time ☕',
      isRunning: true,
      isBreakMode: true,
    );

    _lastTickTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _onTick();
    });
  }

  /// Finish Session works gracefully in BOTH Running and Paused states
  Future<int> finishSession() async {
    final meta = prepareSessionCompletion();
    return meta.durationMinutes;
  }

  /// End Break Time and return to initial Focus mode (cancels notification)
  void endBreak() {
    _ticker?.cancel();
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _lastTickTime = null;
    _sessionStartTime = null;
    _notificationService.cancelTimerNotification();
    _notificationService.cancelAbandonedPauseNudge();

    _disableWakelock();

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds > 0 ? state.targetSeconds : 1500,
      breakDurationSeconds: (state.targetSeconds / 5).floor().clamp(60, 3600),
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      currentSubjectElapsedSeconds: 0,
    );
  }

  /// Discard and cancel the active session without saving or logging any time, resetting to idle
  void discardSession() {
    endSession();
  }

  /// End current session completely without logging extra time (cancels timers and notifications)
  void endSession() {
    _ticker?.cancel();
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _lastTickTime = null;
    _sessionStartTime = null;
    _notificationService.cancelTimerNotification();
    _notificationService.cancelAbandonedPauseNudge();

    _disableWakelock();

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds > 0 ? state.targetSeconds : 1500,
      breakDurationSeconds: (state.targetSeconds / 5).floor().clamp(60, 3600),
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      currentSubjectElapsedSeconds: 0,
    );
  }

  /// Resets timer to initial focus state (cancels notification)
  void resetTimer() {
    _ticker?.cancel();
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _lastTickTime = null;
    _sessionStartTime = null;
    _notificationService.cancelTimerNotification();
    _notificationService.cancelAbandonedPauseNudge();

    _disableWakelock();

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds,
      breakDurationSeconds: (state.targetSeconds / 5).floor().clamp(60, 3600),
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      currentSubjectElapsedSeconds: 0,
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _lastTickTime = null;
    _notificationService.cancelTimerNotification();
    _notificationService.cancelAbandonedPauseNudge();

    _disableWakelock();

    super.dispose();
  }
}
