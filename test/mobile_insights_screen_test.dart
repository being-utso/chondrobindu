import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/models/study_session_model.dart';
import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/models/user_profile.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart' hide UserProfile;
import 'package:chondrobindu/providers/journal_provider.dart';

class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('InsightsScreen Mobile Suite Tests', () {
    testWidgets('renders mobile layout cleanly on phone breakpoint without overflow', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final sampleSessions = [
        StudySession(
          id: 's1',
          courseId: 'math159',
          courseCode: 'MATH 159',
          courseTitle: 'Calculus & Analytical Geometry II',
          durationSeconds: 10800, // 3h 00m
          startedAt: DateTime(now.year, now.month, now.day, 21, 0),
          endedAt: DateTime(now.year, now.month, now.day, 23, 45),
        ),
        StudySession(
          id: 's2',
          courseId: 'cse109',
          courseCode: 'CSE 109',
          courseTitle: 'Computer Programming Fundamentals',
          durationSeconds: 6120, // 1h 42m
          startedAt: DateTime(now.year, now.month, now.day, 14, 0),
          endedAt: DateTime(now.year, now.month, now.day, 15, 45),
        ),
        StudySession(
          id: 's3',
          courseId: 'eee101',
          courseCode: 'EEE 101',
          courseTitle: 'Electrical Circuits I',
          durationSeconds: 4440, // 1h 14m
          startedAt: DateTime(now.year, now.month, now.day, 9, 0),
          endedAt: DateTime(now.year, now.month, now.day, 10, 30),
        ),
      ];

      const testProfile = UserProfile(
        uid: 'user-123',
        email: 'student@chondrobindu.edu',
        displayName: 'Afsana Mimi',
        institutionType: InstitutionType.university,
        term: '24.2',
        streakDays: 4,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value(sampleSessions)),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value(sampleSessions)),
            coursesStreamProvider.overrideWith((ref) => Stream.value(const [
              Course(id: 'math159', code: 'MATH 159', title: 'Calculus & Analytical Geometry II', credits: 3.0),
              Course(id: 'cse109', code: 'CSE 109', title: 'Computer Programming Fundamentals', credits: 3.0),
              Course(id: 'eee101', code: 'EEE 101', title: 'Electrical Circuits I', credits: 3.0),
            ])),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mobile Track Metadata Pill
      expect(find.textContaining('UNIVERSITY TRACK'), findsOneWidget);

      // Sub-Tabs
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Subjects'), findsOneWidget);

      // Period Granularity Buttons
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Trend'), findsOneWidget);

      // 2x2 Top KPI Grid
      expect(find.text('TOTAL FOCUS'), findsWidgets);
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('LONGEST SESSION'), findsOneWidget);
      expect(find.text('AVG DAILY FOCUS'), findsOneWidget);

      // Sections
      expect(find.text('Weekly Focus Distribution'), findsOneWidget);
      expect(find.text('Subject Allocation'), findsOneWidget);
      expect(find.text('24-Hour Diurnal Rhythm'), findsOneWidget);
      expect(find.text('6-Week Density Matrix'), findsOneWidget);
      expect(find.text("Scholar's Weekly Note"), findsOneWidget);

      // Verify no overflow exceptions occurred
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile college track displays College Track pill and Subjects terminology', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testProfile = UserProfile(
        uid: 'college-user',
        email: 'hsc@chondrobindu.edu',
        displayName: 'Tanvir Ahmed',
        institutionType: InstitutionType.college,
        streakDays: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // College Track Pill
      expect(find.textContaining('COLLEGE TRACK'), findsOneWidget);
      expect(find.textContaining('HSC 2026'), findsOneWidget);

      // Zero KPI state
      expect(find.text('TOTAL FOCUS'), findsWidgets);
      expect(find.text('0h 0m'), findsWidgets);
      expect(find.text('2-day streak active'), findsOneWidget);

      // No exceptions
      expect(tester.takeException(), isNull);
    });
  });
}
