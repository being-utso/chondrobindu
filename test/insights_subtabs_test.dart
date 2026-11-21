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
import 'package:chondrobindu/services/exam_service.dart';

class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Insights Sub-Tabs & Layout Boundedness Tests', () {
    testWidgets('Desktop sub-tabs switch without any overflow or exception', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
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
          courseTitle: 'Calculus II',
          durationSeconds: 7200,
          startedAt: DateTime(now.year, now.month, now.day, 10, 0),
          endedAt: DateTime(now.year, now.month, now.day, 12, 0),
        ),
      ];

      const testProfile = UserProfile(
        uid: 'uni-user-1',
        email: 'scholar@buet.ac.bd',
        displayName: 'Zubair',
        institutionType: InstitutionType.university,
        level: '2',
        term: '1',
        universityName: 'BUET',
        department: 'EEE',
        targetGpa: 3.90,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value(sampleSessions)),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value(sampleSessions)),
            coursesStreamProvider.overrideWith((ref) => Stream.value(const [
              Course(id: 'math159', code: 'MATH 159', title: 'Calculus II', credits: 3.0),
            ])),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            examsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 1. Overview Tab (default)
      expect(find.text('Weekly Focus Distribution'), findsOneWidget);

      // 2. Switch to 'Time' Tab
      await tester.tap(find.text('Time').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Circadian Focus Rhythm'), findsOneWidget);

      // 3. Switch to 'Subjects' Tab
      await tester.tap(find.text('Subjects').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Course Focus Breakdown'), findsOneWidget);

      // 4. Switch to 'CGPA Forecaster' Tab
      await tester.tap(find.text('CGPA Forecaster').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Enrolled Course Simulations'), findsOneWidget);
      expect(find.textContaining('3.90'), findsOneWidget);

      // Verify date controls are completely hidden in CGPA Forecaster
      expect(find.text('Trend'), findsNothing);
      expect(find.byIcon(Icons.restore_rounded), findsNothing);

      // 5. Switch back to 'Time' and test Date Stepper
      await tester.tap(find.text('Time').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.chevron_left_rounded).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Desktop College track renders Performance tab cleanly', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testProfile = UserProfile(
        uid: 'college-user-1',
        email: 'hsc@notredame.edu',
        displayName: 'Fahim',
        institutionType: InstitutionType.college,
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
            examsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to 'Performance' Tab
      expect(find.text('Performance'), findsOneWidget);
      await tester.tap(find.text('Performance').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      expect(find.text('Performance Trends'), findsOneWidget);
      expect(find.text('Assessment Performance Ledger'), findsOneWidget);
    });

    testWidgets('Mobile sub-tabs switch cleanly on narrow screen', (tester) async {
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details);
      };
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testProfile = UserProfile(
        uid: 'uni-mobile-user',
        email: 'scholar@chondrobindu.edu',
        displayName: 'Nabila',
        institutionType: InstitutionType.university,
        level: '1',
        term: '2',
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
            examsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap Time sub-tab on mobile
      await tester.tap(find.text('Time').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap Subjects sub-tab on mobile
      await tester.tap(find.text('Subjects').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tap CGPA Forecaster sub-tab on mobile (scroll into view if needed)
      await tester.ensureVisible(find.text('CGPA Forecaster').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('CGPA Forecaster').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
