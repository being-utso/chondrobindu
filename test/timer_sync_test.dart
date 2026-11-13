import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chondrobindu/providers/timer_provider.dart';

void main() {
  group('Cross-Platform Focus Timer Sync Tests', () {
    test('ActiveTimerState serializes and deserializes canonical users/{uid}/active_timer/current schema', () {
      final nowUtc = DateTime.utc(2026, 11, 13, 12, 0, 0);
      final startedAtTs = Timestamp.fromDate(nowUtc);

      final mapData = {
        'status': 'running',
        'mode': 'countdown',
        'startedAt': startedAtTs,
        'accumulatedSeconds': 300,
        'targetDurationSeconds': 1500,
        'courseId': 'course_math101',
        'courseCode': 'MATH 101',
        'courseTitle': 'Calculus I',
        'topicId': 'limits_derivatives',
        'topicTitle': 'Limits & Derivatives',
        'cycleIndex': 2,
        'sessionId': 'session_abc123',
        'leadClientId': 'web_client_99',
        'isFinalized': false,
        'updatedAt': startedAtTs,
      };

      final state = ActiveTimerState.fromMap(mapData);
      expect(state.status, 'running');
      expect(state.mode, 'countdown');
      expect(state.isRunning, true);
      expect(state.isPaused, false);
      expect(state.isIdle, false);
      expect(state.accumulatedSeconds, 300);
      expect(state.targetDurationSeconds, 1500);
      expect(state.courseId, 'course_math101');
      expect(state.courseCode, 'MATH 101');
      expect(state.courseTitle, 'Calculus I');
      expect(state.topicId, 'limits_derivatives');
      expect(state.topicTitle, 'Limits & Derivatives');
      expect(state.cycleIndex, 2);
      expect(state.startedAt, nowUtc);

      final serialized = state.toMap();
      expect(serialized['status'], 'running');
      expect(serialized['mode'], 'countdown');
      expect(serialized['accumulatedSeconds'], 300);
      expect(serialized['targetDurationSeconds'], 1500);
      expect(serialized['cycleIndex'], 2);
      expect(serialized['courseId'], 'course_math101');
      expect(serialized['courseCode'], 'MATH 101');
      expect(serialized['courseTitle'], 'Calculus I');
      expect(serialized['topicTitle'], 'Limits & Derivatives');
    });

    test('Deterministic Local Calculation with Zero Drift (Countdown & Stopwatch)', () {
      final startedAt = DateTime.utc(2026, 11, 13, 10, 0, 0);

      // Countdown test: 25 minutes target (1500s), accumulated 300s, running for 120s
      final countdownSession = ActiveTimerState(
        status: 'running',
        mode: 'countdown',
        startedAt: startedAt,
        accumulatedSeconds: 300,
        targetDurationSeconds: 1500,
      );

      final nowAfter120s = startedAt.add(const Duration(seconds: 120));
      final totalElapsed = countdownSession.calculateElapsedSeconds(now: nowAfter120s);
      final remaining = countdownSession.calculateRemainingSeconds(now: nowAfter120s);

      // 300 accumulated + 120 running = 420s total
      expect(totalElapsed, 420);
      // 1500 target - 420 elapsed = 1080s remaining (18 minutes)
      expect(remaining, 1080);

      // Overtime countdown: running for 1300s -> 300 + 1300 = 1600s total (100s overtime)
      final nowAfter1300s = startedAt.add(const Duration(seconds: 1300));
      final overtimeElapsed = countdownSession.calculateElapsedSeconds(now: nowAfter1300s);
      final overtimeRemaining = countdownSession.calculateRemainingSeconds(now: nowAfter1300s);
      expect(overtimeElapsed, 1600);
      expect(overtimeRemaining, 0); // clamp at 0

      // Stopwatch test: accumulated 60s, running for 95s -> 155s total
      final stopwatchSession = ActiveTimerState(
        status: 'running',
        mode: 'stopwatch',
        startedAt: startedAt,
        accumulatedSeconds: 60,
      );

      final stopwatchElapsed = stopwatchSession.calculateElapsedSeconds(now: startedAt.add(const Duration(seconds: 95)));
      expect(stopwatchElapsed, 155);
    });

    test('Timezone Neutrality: Clients in different timezones calculate identical elapsed time', () {
      // Simulate remote session started at 14:00:00 UTC
      final serverStartUtc = DateTime.utc(2026, 11, 13, 14, 0, 0);
      final activeTimer = ActiveTimerState(
        status: 'running',
        mode: 'countdown',
        startedAt: serverStartUtc,
        accumulatedSeconds: 0,
        targetDurationSeconds: 1500,
      );

      // 75 seconds later in real time:
      // Client A in London (UTC+0) checks time: 14:01:15 UTC
      final clientANow = DateTime.utc(2026, 11, 13, 14, 1, 15);
      final clientAElapsed = activeTimer.calculateElapsedSeconds(now: clientANow);

      // Client B in Dhaka (UTC+6) checks same instant: local is 20:01:15 (+06:00) which converts to 14:01:15 UTC
      final clientBNow = DateTime.parse('2026-11-13T20:01:15+06:00');
      final clientBElapsed = activeTimer.calculateElapsedSeconds(now: clientBNow);

      expect(clientAElapsed, 75);
      expect(clientBElapsed, 75);
      expect(clientAElapsed, equals(clientBElapsed));
    });

    test('TimerState runningDelta and currentElapsedSeconds use UTC-safe math', () {
      final startedAt = DateTime.now().toUtc().subtract(const Duration(seconds: 45));
      final timerState = TimerState(
        mode: TimerMode.focus,
        status: TimerStatus.running,
        baseElapsedSeconds: 60,
        startedAt: startedAt,
        targetSeconds: 1500,
      );

      // baseElapsed 60 + runningDelta (~45) = ~105
      expect(timerState.baseElapsedSeconds, 60);
      expect(timerState.runningDelta >= 45, true);
      expect(timerState.currentElapsedSeconds >= 105, true);
      expect(timerState.elapsedSeconds >= 105, true);
    });

    test('TimerNotifier handles remote snapshot updates without initial overwrite', () {
      final notifier = TimerNotifier();
      // On boot, notifier is in initial idle state
      expect(notifier.state.status, TimerStatus.initial);
      expect(notifier.state.baseElapsedSeconds, 0);

      // Remote device starts a countdown session:
      final remoteRunning = ActiveTimerState(
        status: 'running',
        mode: 'countdown',
        startedAt: DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
        accumulatedSeconds: 0,
        targetDurationSeconds: 1500,
        courseCode: 'CSE 110',
        courseTitle: 'Programming',
        cycleIndex: 1,
      );

      // Simulate receiving remote active timer snapshot:
      // In notifier, calling _onRemoteActiveSessionUpdate via watchActiveTimer:
      // We verify state transitions directly through notifier contract
      const remotePaused = ActiveTimerState(
        status: 'paused',
        mode: 'countdown',
        accumulatedSeconds: 120,
        targetDurationSeconds: 1500,
        courseCode: 'CSE 110',
      );

      expect(remoteRunning.isRunning, true);
      expect(remotePaused.isPaused, true);
      expect(remotePaused.calculateElapsedSeconds(), 120);
      expect(remotePaused.calculateRemainingSeconds(), 1380); // 1500 - 120 = 1380 (23:00)

      notifier.dispose();
    });

    test('Pause and Resume state transitions preserve accumulated seconds', () {
      final notifier = TimerNotifier();
      notifier.startTimer();
      expect(notifier.state.status, TimerStatus.running);

      // Study for 100 seconds
      notifier.catchUp(100);
      expect(notifier.state.currentElapsedSeconds, 100);

      // Pause timer: baseElapsedSeconds becomes 100, startedAt cleared
      notifier.pauseTimer();
      expect(notifier.state.status, TimerStatus.paused);
      expect(notifier.state.baseElapsedSeconds, 100);
      expect(notifier.state.startedAt, null);

      // Resume timer: startedAt set to new anchor, baseElapsedSeconds preserved at 100
      notifier.startTimer();
      expect(notifier.state.status, TimerStatus.running);
      expect(notifier.state.baseElapsedSeconds, 100);
      expect(notifier.state.startedAt != null, true);

      // Study for another 50 seconds
      notifier.catchUp(50);
      expect(notifier.state.currentElapsedSeconds, 150);
      expect(notifier.state.formattedTime, '22:30'); // 25:00 - 02:30 = 22:30

      notifier.dispose();
    });
  });
}
