import 'package:flutter_test/flutter_test.dart';
import 'package:chondrobindu/services/timer_service.dart';
import 'package:chondrobindu/models/study_session_model.dart';
import 'package:chondrobindu/models/analytics_models.dart';
import 'package:chondrobindu/utils/client_identity.dart';

void main() {
  group('formatCleanSessionTitle', () {
    test('formats clean title when code and title are distinct', () {
      final title = formatCleanSessionTitle(
        courseCode: 'MATH 157',
        courseTitle: 'Differential and Integral Calculus',
      );
      expect(title, 'MATH 157: Differential and Integral Calculus');
    });

    test('strips redundant course code prefix when title contains it', () {
      final title = formatCleanSessionTitle(
        courseCode: 'MATH 157',
        courseTitle: 'MATH 157: Differential and Integral Calculus',
      );
      expect(title, 'MATH 157: Differential and Integral Calculus');
    });

    test('strips course code when title begins with code without colon', () {
      final title = formatCleanSessionTitle(
        courseCode: 'PHY 121',
        courseTitle: 'PHY 121 Electricity & Magnetism',
      );
      expect(title, 'PHY 121: Electricity & Magnetism');
    });

    test('avoids duplicate repetition when title equals code', () {
      final title = formatCleanSessionTitle(
        courseCode: 'EEE 101',
        courseTitle: 'EEE 101',
      );
      expect(title, 'EEE 101');
    });

    test('uses fallback when both code and title are empty', () {
      final title = formatCleanSessionTitle(
        courseCode: '',
        courseTitle: '',
        fallback: 'General Study',
      );
      expect(title, 'General Study');
    });
  });

  group('deduplicateStudySessions', () {
    test('removes exact ID duplicates from multi-device listeners', () {
      final now = DateTime(2026, 9, 27, 10, 0, 0);
      final sessions = <StudySession>[
        StudySession(
          id: 'sess_1',
          courseId: 'c1',
          courseCode: 'MATH 157',
          courseTitle: 'Calculus',
          durationSeconds: 1800,
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 30)),
        ),
        StudySession(
          id: 'sess_1', // Duplicate ID
          courseId: 'c1',
          courseCode: 'MATH 157',
          courseTitle: 'Calculus',
          durationSeconds: 1800,
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 30)),
        ),
      ];

      final deduped = deduplicateStudySessions<StudySession>(
        sessions: sessions,
        getId: (s) => s.id,
        getCourseKey: (s) => s.courseCode,
        getStartTime: (s) => s.startedAt,
        getDurationSeconds: (s) => s.durationSeconds,
      );

      expect(deduped.length, 1);
      expect(deduped.first.id, 'sess_1');
    });

    test('collapses overlapping sessions starting within 90s with matching duration', () {
      final base = DateTime(2026, 9, 27, 1, 25, 10);
      final sessions = <StudySession>[
        StudySession(
          id: 'doc_a',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2760, // 46 mins
          startedAt: base,
          endedAt: base.add(const Duration(seconds: 2760)),
        ),
        StudySession(
          id: 'doc_b',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2761, // 1 second variation
          startedAt: base.add(const Duration(seconds: 1)),
          endedAt: base.add(const Duration(seconds: 2762)),
        ),
        StudySession(
          id: 'doc_c',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2760,
          startedAt: base.add(const Duration(seconds: 2)),
          endedAt: base.add(const Duration(seconds: 2762)),
        ),
      ];

      final deduped = deduplicateStudySessions<StudySession>(
        sessions: sessions,
        getId: (s) => s.id,
        getCourseKey: (s) => s.courseCode,
        getStartTime: (s) => s.startedAt,
        getDurationSeconds: (s) => s.durationSeconds,
      );

      expect(deduped.length, 1);
      expect(deduped.first.id, 'doc_a');
    });

    test('preserves legitimately distinct sessions', () {
      final morning = DateTime(2026, 9, 27, 10, 0, 0);
      final evening = DateTime(2026, 9, 27, 18, 0, 0);
      final sessions = <StudySession>[
        StudySession(
          id: 's_morning',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 1800,
          startedAt: morning,
          endedAt: morning.add(const Duration(minutes: 30)),
        ),
        StudySession(
          id: 's_evening',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 1800,
          startedAt: evening,
          endedAt: evening.add(const Duration(minutes: 30)),
        ),
        StudySession(
          id: 's_phy',
          courseId: 'c2',
          courseCode: 'PHY 121',
          durationSeconds: 1800,
          startedAt: evening,
          endedAt: evening.add(const Duration(minutes: 30)),
        ),
      ];

      final deduped = deduplicateStudySessions<StudySession>(
        sessions: sessions,
        getId: (s) => s.id,
        getCourseKey: (s) => s.courseCode,
        getStartTime: (s) => s.startedAt,
        getDurationSeconds: (s) => s.durationSeconds,
      );

      expect(deduped.length, 3);
    });
  });

  group('cleanTitle getters', () {
    test('StudySession.cleanTitle formats properly', () {
      final session = StudySession(
        id: '1',
        courseId: 'c',
        courseCode: 'CSE 109',
        courseTitle: 'Computer Programming',
        durationSeconds: 1200,
        startedAt: DateTime.now(),
        endedAt: DateTime.now(),
      );
      expect(session.cleanTitle, 'CSE 109: Computer Programming');
    });

    test('StudySessionLog.cleanTitle formats properly', () {
      final log = StudySessionLog(
        id: '1',
        subjectId: 's1',
        subjectName: 'EEE 102 Electrical Circuits',
        courseCode: 'EEE 102',
        courseTitle: 'Electrical Circuits',
        durationInMinutes: 45,
        date: DateTime.now(),
      );
      expect(log.cleanTitle, 'EEE 102: Electrical Circuits');
    });
  });

  group('ClientIdentity & Session ID tests', () {
    test('ClientIdentity provides non-empty instanceId and valid UUID v4 session IDs', () {
      expect(ClientIdentity.instanceId.isNotEmpty, isTrue);
      final sessionId1 = ClientIdentity.newSessionId();
      final sessionId2 = ClientIdentity.newSessionId();
      expect(sessionId1, isNot(equals(sessionId2)));
      // RFC 4122 v4 pattern: 8-4-4-4-12 hex digits with 4 at digit 13 and [89ab] at digit 17
      final uuidRegex = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(uuidRegex.hasMatch(sessionId1), isTrue);
      expect(uuidRegex.hasMatch(sessionId2), isTrue);
    });
  });

  group('deduplicateSessions (StudySession timeline merger)', () {
    test('collapses duplicate sessionIds', () {
      final now = DateTime(2026, 9, 27, 10, 0, 0);
      final sessions = [
        StudySession(
          id: 'doc_1',
          sessionId: 'session_unique_123',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 1800,
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 30)),
        ),
        StudySession(
          id: 'doc_2',
          sessionId: 'session_unique_123', // Same session ID
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 1800,
          startedAt: now,
          endedAt: now.add(const Duration(minutes: 30)),
        ),
      ];

      final result = deduplicateSessions(sessions);
      expect(result.length, 1);
      expect(result.first.sessionId, 'session_unique_123');
    });

    test('collapses overlapping sessions starting within 90s with duration diff <= 60s for same course', () {
      final base = DateTime(2026, 9, 27, 1, 25, 0);
      final sessions = [
        StudySession(
          id: 'doc_a',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2760, // 46 mins
          startedAt: base,
          endedAt: base.add(const Duration(seconds: 2760)),
        ),
        StudySession(
          id: 'doc_b',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2761, // 1s diff
          startedAt: base.add(const Duration(seconds: 5)), // 5s diff <= 90s
          endedAt: base.add(const Duration(seconds: 2766)),
        ),
      ];

      final result = deduplicateSessions(sessions);
      expect(result.length, 1);
    });

    test('retains distinct sessions beyond 90s drift or diff courses', () {
      final base = DateTime(2026, 9, 27, 1, 25, 0);
      final sessions = [
        StudySession(
          id: 'doc_math',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2760,
          startedAt: base,
          endedAt: base.add(const Duration(seconds: 2760)),
        ),
        StudySession(
          id: 'doc_phy',
          courseId: 'c2',
          courseCode: 'PHY 121',
          durationSeconds: 2760,
          startedAt: base.add(const Duration(seconds: 10)),
          endedAt: base.add(const Duration(seconds: 2770)),
        ),
        StudySession(
          id: 'doc_math_later',
          courseId: 'c1',
          courseCode: 'MATH 157',
          durationSeconds: 2760,
          startedAt: base.add(const Duration(minutes: 60)),
          endedAt: base.add(const Duration(minutes: 106)),
        ),
      ];

      final result = deduplicateSessions(sessions);
      expect(result.length, 3);
    });
  });

  group('deduplicateSessionLogs (StudySessionLog timeline merger)', () {
    test('collapses duplicate session logs within 90s and 60s duration diff', () {
      final base = DateTime(2026, 9, 27, 10, 0, 0);
      final logs = [
        StudySessionLog(
          id: 'log_1',
          subjectId: 's1',
          courseCode: 'MATH 157',
          subjectName: 'Calculus',
          durationInMinutes: 45,
          durationInSeconds: 2700,
          date: base,
          startTime: base,
          endTime: base.add(const Duration(minutes: 45)),
        ),
        StudySessionLog(
          id: 'log_2',
          subjectId: 's1',
          courseCode: 'MATH 157',
          subjectName: 'Calculus',
          durationInMinutes: 45,
          durationInSeconds: 2701,
          date: base.add(const Duration(seconds: 2)),
          startTime: base.add(const Duration(seconds: 2)),
          endTime: base.add(const Duration(minutes: 45)),
        ),
      ];

      final result = deduplicateSessionLogs(logs);
      expect(result.length, 1);
    });
  });
}

