import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/session_metadata.dart';
import '../services/notification_service.dart';
import '../services/timer_service.dart';
import 'timer_subjects_provider.dart';

export '../models/session_metadata.dart';
export '../services/timer_service.dart';

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
  final String? selectedCourseId;
  final String? selectedTopicId;
  final String? activeSessionId;
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
    this.selectedCourseId,
    this.selectedTopicId,
    this.activeSessionId,
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

  /// Calculates earned break time: 5:1 focus ratio using canonical calculateBreakMinutes
  int get earnedBreakMinutes => calculateBreakMinutes(totalLoggedSeconds);
  int get earnedBreakSeconds => (totalLoggedSeconds / 5).floor().clamp(60, 7200);

  /// Formatted string for earned break duration (e.g., "5m 00s")
  String get formattedEarnedBreak {
    final mins = earnedBreakSeconds ~/ 60;
    final secs = earnedBreakSeconds % 60;
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
    String? selectedCourseId,
    String? selectedTopicId,
    String? activeSessionId,
    bool clearActiveSessionId = false,
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
      selectedCourseId: selectedCourseId ?? this.selectedCourseId,
      selectedTopicId: selectedTopicId ?? this.selectedTopicId,
      activeSessionId: clearActiveSessionId ? null : (activeSessionId ?? this.activeSessionId),
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
  final TimerService _timerService;
  StreamSubscription<ActiveSessionState>? _activeSessionSub;
  StreamSubscription<User?>? _authSub;
  bool _isLocallyInitiated = false;
  bool _isCompletingSession = false;

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
    TimerService? timerService,
    String? initialSubject,
    String? initialCourseId,
    String? initialTopicId,
  })  : _customFirestore = firestore,
        _customAuth = auth,
        _customNotificationService = notificationService,
        _timerService = timerService ?? TimerService(firestore: firestore, auth: auth),
        super(TimerState(
          mode: TimerMode.focus,
          status: TimerStatus.initial,
          elapsedSeconds: 0,
          targetSeconds: 1500, // Default 25 minutes
          breakDurationSeconds: 300,
          breakElapsedSeconds: 0,
          selectedSubject: initialSubject ?? 'General Study',
          selectedCourseId: initialCourseId,
          selectedTopicId: initialTopicId,
          currentSubjectElapsedSeconds: 0,
        )) {
    _initActiveSessionSync();
  }

  void _initActiveSessionSync() {
    final auth = _auth;
    if (auth == null) return;
    try {
      _authSub = auth.authStateChanges().listen((user) {
        _activeSessionSub?.cancel();
        if (user != null && user.uid.isNotEmpty) {
          _activeSessionSub = _timerService.watchActiveSession(user.uid).listen(
            _onRemoteActiveSessionUpdate,
            onError: (err) => debugPrint('Error in active_session sync: $err'),
          );
        }
      });
      final currentUid = auth.currentUser?.uid;
      if (currentUid != null && currentUid.isNotEmpty) {
        _activeSessionSub = _timerService.watchActiveSession(currentUid).listen(
          _onRemoteActiveSessionUpdate,
          onError: (err) => debugPrint('Error in active_session sync: $err'),
        );
      }
    } catch (e) {
      debugPrint('Error initializing active session sync: $e');
    }
  }

  void setSelectedCourseAndTopic({String? courseId, String? courseCode, String? topicId}) {
    state = state.copyWith(
      selectedCourseId: courseId ?? state.selectedCourseId,
      selectedSubject: courseCode ?? state.selectedSubject,
      selectedTopicId: topicId ?? state.selectedTopicId,
    );
  }

  void _onRemoteActiveSessionUpdate(ActiveSessionState remoteSession) {
    if (_isLocallyInitiated) {
      _isLocallyInitiated = false;
      return;
    }

    if (remoteSession.isRunning) {
      final startedAt = remoteSession.startedAt ?? DateTime.now();
      final diffSeconds = DateTime.now().difference(startedAt).inSeconds;
      final currentElapsed = remoteSession.elapsedBeforePauseSeconds + (diffSeconds > 0 ? diffSeconds : 0);

      final isStopwatch = remoteSession.mode == 'stopwatch';
      final isBreak = remoteSession.mode == 'break';

      if (isBreak) {
        final breakDur = remoteSession.targetDurationSeconds > 0 ? remoteSession.targetDurationSeconds : 300;
        final nextBreakElapsed = currentElapsed.clamp(0, breakDur);
        state = state.copyWith(
          mode: TimerMode.breakTime,
          status: TimerStatus.running,
          focusMode: FocusTimerMode.breakRunning,
          breakDurationSeconds: breakDur,
          breakElapsedSeconds: nextBreakElapsed,
          activeSessionId: remoteSession.sessionId,
          selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
          selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
          selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
        );
      } else if (isStopwatch) {
        state = state.copyWith(
          mode: TimerMode.focus,
          timerType: TimerType.stopwatch,
          status: TimerStatus.running,
          focusMode: FocusTimerMode.focusRunning,
          elapsedSeconds: currentElapsed,
          activeSessionId: remoteSession.sessionId,
          selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
          selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
          selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
        );
      } else {
        final target = remoteSession.targetDurationSeconds > 0 ? remoteSession.targetDurationSeconds : state.targetSeconds;
        if (currentElapsed >= target) {
          final overtime = currentElapsed - target;
          state = state.copyWith(
            mode: TimerMode.focus,
            timerType: TimerType.target,
            status: TimerStatus.running,
            focusMode: FocusTimerMode.overtimeRunning,
            targetSeconds: target,
            elapsedSeconds: target,
            overtimeSeconds: overtime,
            activeSessionId: remoteSession.sessionId,
            selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
            selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
            selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
          );
        } else {
          state = state.copyWith(
            mode: TimerMode.focus,
            timerType: TimerType.target,
            status: TimerStatus.running,
            focusMode: FocusTimerMode.focusRunning,
            targetSeconds: target,
            elapsedSeconds: currentElapsed,
            overtimeSeconds: 0,
            activeSessionId: remoteSession.sessionId,
            selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
            selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
            selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
          );
        }
      }

      _lastTickTime = DateTime.now();
      _enableWakelock();
      _startLocalTicker();
      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.isBreak
            ? 'Break Time ☕'
            : (state.isOvertime ? '${state.selectedSubject} (Overtime)' : state.selectedSubject),
        isRunning: true,
        isBreakMode: state.isBreak,
      );
    } else if (remoteSession.isPaused) {
      final currentElapsed = remoteSession.elapsedBeforePauseSeconds;
      _stopLocalTicker();
      _disableWakelock();

      final isStopwatch = remoteSession.mode == 'stopwatch';
      final isBreak = remoteSession.mode == 'break';

      if (isBreak) {
        state = state.copyWith(
          mode: TimerMode.breakTime,
          status: TimerStatus.paused,
          focusMode: FocusTimerMode.breakPaused,
          breakElapsedSeconds: currentElapsed,
          activeSessionId: remoteSession.sessionId,
          selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
          selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
          selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
        );
      } else if (isStopwatch) {
        state = state.copyWith(
          mode: TimerMode.focus,
          timerType: TimerType.stopwatch,
          status: TimerStatus.paused,
          focusMode: FocusTimerMode.focusPaused,
          elapsedSeconds: currentElapsed,
          activeSessionId: remoteSession.sessionId,
          selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
          selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
          selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
        );
      } else {
        final target = remoteSession.targetDurationSeconds > 0 ? remoteSession.targetDurationSeconds : state.targetSeconds;
        if (currentElapsed >= target) {
          final overtime = currentElapsed - target;
          state = state.copyWith(
            mode: TimerMode.focus,
            timerType: TimerType.target,
            status: TimerStatus.paused,
            focusMode: FocusTimerMode.focusPaused,
            targetSeconds: target,
            elapsedSeconds: target,
            overtimeSeconds: overtime,
            activeSessionId: remoteSession.sessionId,
            selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
            selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
            selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
          );
        } else {
          state = state.copyWith(
            mode: TimerMode.focus,
            timerType: TimerType.target,
            status: TimerStatus.paused,
            focusMode: FocusTimerMode.focusPaused,
            targetSeconds: target,
            elapsedSeconds: currentElapsed,
            overtimeSeconds: 0,
            activeSessionId: remoteSession.sessionId,
            selectedSubject: remoteSession.courseCode ?? state.selectedSubject,
            selectedCourseId: remoteSession.courseId ?? state.selectedCourseId,
            selectedTopicId: remoteSession.topicId ?? state.selectedTopicId,
          );
        }
      }

      _notificationService.showTimerNotification(
        timeRemaining: state.formattedTime,
        subject: state.isBreak
            ? 'Break Time ☕'
            : (state.isOvertime ? '${state.selectedSubject} (Overtime)' : state.selectedSubject),
        isRunning: false,
        isBreakMode: state.isBreak,
      );
    } else if (remoteSession.isIdle) {
      if (state.status != TimerStatus.initial) {
        _stopLocalTicker();
        _disableWakelock();
        _notificationService.cancelTimerNotification();
        _notificationService.cancelAbandonedPauseNudge();
        state = TimerState(
          mode: TimerMode.focus,
          focusMode: FocusTimerMode.idle,
          status: TimerStatus.initial,
          timerType: state.timerType,
          elapsedSeconds: 0,
          targetSeconds: state.targetSeconds > 0 ? state.targetSeconds : 1500,
          breakDurationSeconds: calculateBreakMinutes(state.targetSeconds > 0 ? state.targetSeconds : 1500) * 60,
          breakElapsedSeconds: 0,
          overtimeSeconds: 0,
          extraElapsedSeconds: 0,
          selectedSubject: state.selectedSubject,
          selectedCourseId: state.selectedCourseId,
          selectedTopicId: state.selectedTopicId,
          currentSubjectElapsedSeconds: 0,
        );
      }
    }
  }

  void _startLocalTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      _onTick();
    });
  }

  void _stopLocalTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickTime = null;
  }

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
    final segmentId = 'segment_${now.millisecondsSinceEpoch}_$uid';

    try {
      await firestore
          .collection('users')
          .doc(uid)
          .collection('focus_sessions')
          .doc(segmentId)
          .set({
        'sessionId': segmentId,
        'subject': subject,
        'subjectName': subject,
        'durationSeconds': durationSeconds,
        'durationMinutes': mins,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(now),
        'timestamp': Timestamp.fromDate(now),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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

    final isInitial = state.status == TimerStatus.initial;
    final uid = _auth?.currentUser?.uid ?? '';
    final currentSessionId = isInitial
        ? 'session_${DateTime.now().millisecondsSinceEpoch}_${uid.isNotEmpty ? uid : "local"}'
        : (state.activeSessionId ?? 'session_${DateTime.now().millisecondsSinceEpoch}_${uid.isNotEmpty ? uid : "local"}');

    if (isInitial) {
      _sessionStartTime = DateTime.now();
      final breakDur = calculateBreakMinutes(state.targetSeconds) * 60;
      state = state.copyWith(
        mode: TimerMode.focus,
        focusMode: FocusTimerMode.focusRunning,
        status: TimerStatus.running,
        elapsedSeconds: 0,
        overtimeSeconds: 0,
        breakDurationSeconds: breakDur,
        breakElapsedSeconds: 0,
        extraElapsedSeconds: 0,
        activeSessionId: currentSessionId,
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
        activeSessionId: currentSessionId,
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

    // Cross-Device Sync State Transition to Firestore
    if (uid.isNotEmpty) {
      _isLocallyInitiated = true;
      if (isInitial) {
        unawaited(_timerService.startActiveSession(
          uid: uid,
          sessionId: currentSessionId,
          mode: state.isBreak ? 'break' : (state.timerType == TimerType.stopwatch ? 'stopwatch' : 'focus'),
          courseId: state.selectedCourseId,
          courseCode: state.selectedSubject,
          topicId: state.selectedTopicId,
          targetDurationSeconds: state.isBreak
              ? state.breakDurationSeconds
              : (state.timerType == TimerType.stopwatch ? 0 : state.targetSeconds),
        ));
      } else {
        unawaited(_timerService.resumeActiveSession(uid));
      }
    }
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

      // Cross-Device Sync State Transition: PAUSE
      final uid = _auth?.currentUser?.uid ?? '';
      if (uid.isNotEmpty) {
        _isLocallyInitiated = true;
        unawaited(_timerService.pauseActiveSession(
          uid: uid,
          currentElapsedSeconds: state.totalLoggedSeconds,
        ));
      }
    }
  }

  /// Prepares session completion:
  /// 1. Pauses timer ticks.
  /// 2. Sets state to FocusTimerMode.sessionCompleted.
  /// 3. Builds immutable SessionMetadata snapshot for course isolation.
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
      courseId: state.selectedCourseId,
    );

    state = state.copyWith(
      status: TimerStatus.paused,
      focusMode: FocusTimerMode.sessionCompleted,
      sessionMetadata: metadata,
    );

    return metadata;
  }

  /// Persists session to Firestore users/{uid}/study_sessions and focus_sessions,
  /// updates user aggregate stats, and resets active_session to 'idle'
  Future<bool> completeSession({
    String? courseId,
    String? courseCode,
    String? topicId,
    int? finalElapsedSeconds,
    String? mode,
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
  }) async {
    if (_isCompletingSession) return false;
    _isCompletingSession = true;
    try {
      _ticker?.cancel();
      _lastTickTime = null;
      _abandonedPauseTimer?.cancel();
      _abandonedPauseTimer = null;
      _notificationService.cancelAbandonedPauseNudge();
      _disableWakelock();

      final uid = _auth?.currentUser?.uid ?? '';
      final elapsed = finalElapsedSeconds ?? state.totalLoggedSeconds;
      final start = sessionStartTime ?? _sessionStartTime ?? DateTime.now().subtract(Duration(seconds: elapsed));
      final sessionMode = mode ?? (state.timerType == TimerType.stopwatch ? 'stopwatch' : 'focus');

      if (uid.isEmpty) return false;

      _isLocallyInitiated = true;
      final success = await _timerService.completeSession(
        uid: uid,
        sessionId: state.activeSessionId,
        courseId: courseId ?? state.selectedCourseId,
        courseCode: courseCode ?? state.selectedSubject,
        topicId: topicId ?? state.selectedTopicId,
        finalElapsedSeconds: elapsed,
        mode: sessionMode,
        sessionStartTime: start,
        sessionEndTime: sessionEndTime,
      );

      state = state.copyWith(clearActiveSessionId: true);
      return success;
    } finally {
      _isCompletingSession = false;
    }
  }

  /// Automatically launches the earned break clock after session completion:
  /// Dynamically computes break based on ACTUAL elapsed focus time using 5:1 ratio:
  /// e.g. 50 mins stopwatch study -> 10 mins break (NOT 1 min).
  void startBreakAfterSession([int? focusElapsedSeconds]) {
    _abandonedPauseTimer?.cancel();
    _abandonedPauseTimer = null;
    _notificationService.cancelAbandonedPauseNudge();

    final elapsed = focusElapsedSeconds ?? state.totalLoggedSeconds;
    final int earnedBreak;
    if (state.timerType == TimerType.stopwatch) {
      final breakMinutes = calculateBreakMinutes(elapsed);
      earnedBreak = breakMinutes * 60;
    } else {
      earnedBreak = (focusElapsedSeconds != null)
          ? (focusElapsedSeconds / 5).floor().clamp(60, 7200)
          : state.earnedBreakSeconds.clamp(60, 7200);
    }

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

    final uid = _auth?.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _isLocallyInitiated = true;
      unawaited(_timerService.startActiveSession(
        uid: uid,
        mode: 'break',
        courseId: state.selectedCourseId,
        courseCode: state.selectedSubject,
        topicId: state.selectedTopicId,
        targetDurationSeconds: earnedBreak,
      ));
    }
  }

  /// Finish Session works gracefully in BOTH Running and Paused states
  Future<int> finishSession() async {
    final meta = prepareSessionCompletion();
    await completeSession(
      courseId: meta.courseId,
      courseCode: meta.courseCode,
      finalElapsedSeconds: meta.totalDurationSeconds,
      mode: state.timerType == TimerType.stopwatch ? 'stopwatch' : 'focus',
      sessionStartTime: meta.sessionStartTime,
    );
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

    final uid = _auth?.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _isLocallyInitiated = true;
      unawaited(_timerService.resetActiveSession(uid));
    }

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds > 0 ? state.targetSeconds : 1500,
      breakDurationSeconds: calculateBreakMinutes(state.targetSeconds > 0 ? state.targetSeconds : 1500) * 60,
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      selectedCourseId: state.selectedCourseId,
      selectedTopicId: state.selectedTopicId,
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

    final uid = _auth?.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _isLocallyInitiated = true;
      unawaited(_timerService.resetActiveSession(uid));
    }

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds > 0 ? state.targetSeconds : 1500,
      breakDurationSeconds: calculateBreakMinutes(state.targetSeconds > 0 ? state.targetSeconds : 1500) * 60,
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      selectedCourseId: state.selectedCourseId,
      selectedTopicId: state.selectedTopicId,
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

    final uid = _auth?.currentUser?.uid ?? '';
    if (uid.isNotEmpty) {
      _isLocallyInitiated = true;
      unawaited(_timerService.resetActiveSession(uid));
    }

    state = TimerState(
      mode: TimerMode.focus,
      focusMode: FocusTimerMode.idle,
      status: TimerStatus.initial,
      timerType: state.timerType,
      elapsedSeconds: 0,
      targetSeconds: state.targetSeconds,
      breakDurationSeconds: calculateBreakMinutes(state.targetSeconds) * 60,
      breakElapsedSeconds: 0,
      overtimeSeconds: 0,
      extraElapsedSeconds: 0,
      selectedSubject: state.selectedSubject,
      selectedCourseId: state.selectedCourseId,
      selectedTopicId: state.selectedTopicId,
      currentSubjectElapsedSeconds: 0,
    );
  }

  @override
  void dispose() {
    _activeSessionSub?.cancel();
    _authSub?.cancel();
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
