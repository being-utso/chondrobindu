import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/screens/journal_screen.dart';
import 'package:chondrobindu/models/routine_models.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/journal_provider.dart';

class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('computeMinDate Unit Tests', () {
    final today = DateTime.now();

    test('returns semesterStart for university track when before today', () {
      final semesterStart = DateTime(today.year, today.month - 1, 1);
      final minDate = computeMinDate(
        isUniversity: true,
        semesterStart: semesterStart,
        userCreatedAt: DateTime(today.year - 1, 1, 1),
      );
      expect(minDate, equals(DateTime(semesterStart.year, semesterStart.month, semesterStart.day)));
    });

    test('ignores future semesterStart and falls back to userCreatedAt', () {
      final futureSemStart = today.add(const Duration(days: 30));
      final userCreatedAt = DateTime(today.year, today.month - 2, 15);
      final minDate = computeMinDate(
        isUniversity: true,
        semesterStart: futureSemStart,
        userCreatedAt: userCreatedAt,
      );
      expect(minDate, equals(DateTime(userCreatedAt.year, userCreatedAt.month, userCreatedAt.day)));
    });

    test('uses userCreatedAt for college track even if semesterStart is provided', () {
      final semesterStart = DateTime(today.year, today.month - 1, 1);
      final userCreatedAt = DateTime(today.year, today.month - 3, 10);
      final minDate = computeMinDate(
        isUniversity: false,
        semesterStart: semesterStart,
        userCreatedAt: userCreatedAt,
      );
      expect(minDate, equals(DateTime(userCreatedAt.year, userCreatedAt.month, userCreatedAt.day)));
    });

    test('falls back to 90 days ago when no dates provided', () {
      final minDate = computeMinDate(
        isUniversity: false,
        semesterStart: null,
        userCreatedAt: null,
      );
      final expected = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 90));
      expect(minDate, equals(expected));
    });
  });

  group('InsightsScreen Period Picker Inline Display & Date Stepper Tests', () {
    testWidgets('Day mode displays inline calendar with days of the month (no popups)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Day mode
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();

      // Inline calendar header is visible directly below navigation
      expect(find.text('Select Focus Date'), findsOneWidget);
      expect(find.textContaining('Bounded:'), findsOneWidget);

      // Verify no dialog popup exists
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Month mode displays inline 12-month grid (no popups)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Month mode
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      // Inline month grid is directly rendered
      expect(find.text('Select Calendar Month'), findsOneWidget);
      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Dec'), findsOneWidget);

      // Verify no dialog popup exists
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Trend mode displays inline preset chips and custom window (no popups)', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Trend mode
      await tester.tap(find.text('Trend'));
      await tester.pumpAndSettle();

      // Inline trend controls are directly visible
      expect(find.text('Telemetry Trend Window'), findsOneWidget);
      expect(find.text('Last 7 Days'), findsOneWidget);
      expect(find.text('Last 14 Days'), findsOneWidget);
      expect(find.text('Last 30 Days'), findsOneWidget);

      // Tapping a preset works inline without dialog
      await tester.tap(find.text('Last 14 Days'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('College student does NOT display WEEK 04 mockup dummy text', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const collegeProfile = UserProfile(
        uid: 'test-college',
        email: 'college@chondrobindu.edu',
        displayName: 'College Student',
        institutionType: InstitutionType.college,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(collegeProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify College Track pill appears
      expect(find.textContaining('COLLEGE TRACK'), findsOneWidget);

      // Verify hardcoded WEEK 04 is completely absent
      expect(find.textContaining('WEEK 04'), findsNothing);
    });
  });
}
