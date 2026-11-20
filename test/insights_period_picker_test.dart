import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/screens/journal_screen.dart';
import 'package:chondrobindu/models/routine_models.dart';
import 'package:chondrobindu/models/study_session_model.dart';
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
    testWidgets('Day mode displays date stepper with chevrons and Today quick-jump button (no popups)', (tester) async {
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

      // Quick-jump button displays 'Today'
      expect(find.text('Today'), findsOneWidget);

      // Chevrons are present
      expect(find.byIcon(Icons.chevron_left_rounded), findsWidgets);
      expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);

      // Verify no dialog popup exists
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Month mode displays month stepper and This Month quick-jump button (no popups)', (tester) async {
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

      // Quick-jump button displays 'This Month'
      expect(find.text('This Month'), findsOneWidget);

      // Verify no dialog popup exists
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Trend mode displays trend stepper and Current quick-jump button (no popups)', (tester) async {
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

      // Quick-jump button displays 'Current'
      expect(find.text('Current'), findsOneWidget);

      // Verify no dialog popup exists
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

    testWidgets('Day mode renders 6 chronological 4-hour blocks (00-04 to 20-24) and DAY FOCUS TIME header', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final daySessions = [
        StudySession(
          id: 'ds1',
          courseId: 'cse109',
          courseCode: 'CSE 109',
          durationSeconds: 3600, // 1.0h in 08-12 block (hour 10)
          startedAt: DateTime(now.year, now.month, now.day, 10, 0),
          endedAt: DateTime(now.year, now.month, now.day, 11, 0),
        ),
        StudySession(
          id: 'ds2',
          courseId: 'math159',
          courseCode: 'MATH 159',
          durationSeconds: 7200, // 2.0h in 12-16 block (hour 14)
          startedAt: DateTime(now.year, now.month, now.day, 14, 0),
          endedAt: DateTime(now.year, now.month, now.day, 16, 0),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value(daySessions)),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value(daySessions)),
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
      await tester.tap(find.text('Day').first);
      await tester.pumpAndSettle();

      // Verify header changed to DAY FOCUS TIME
      expect(find.text('DAY FOCUS TIME'), findsOneWidget);

      // Verify 6 4-hour chronological blocks are rendered
      expect(find.text('00-04'), findsOneWidget);
      expect(find.text('04-08'), findsOneWidget);
      expect(find.text('08-12'), findsOneWidget);
      expect(find.text('12-16'), findsOneWidget);
      expect(find.text('16-20'), findsOneWidget);
      expect(find.text('20-24'), findsOneWidget);

      // Peak block is 12-16 with 2.0h
      expect(find.textContaining('Peak: 12-16'), findsOneWidget);

      // Verify Sat-Fri weekdays are not shown in the chart
      expect(find.text('Sat'), findsNothing);
      expect(find.text('Fri'), findsNothing);
    });

    testWidgets('Month mode renders weekly bars W1 to W4 and MONTH FOCUS TIME header', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final monthSessions = [
        StudySession(
          id: 'ms1',
          courseId: 'cse109',
          courseCode: 'CSE 109',
          durationSeconds: 14400, // 4.0h in W1 (day 3)
          startedAt: DateTime(now.year, now.month, 3, 10, 0),
          endedAt: DateTime(now.year, now.month, 3, 14, 0),
        ),
        StudySession(
          id: 'ms2',
          courseId: 'math159',
          courseCode: 'MATH 159',
          durationSeconds: 28800, // 8.0h in W2 (day 10)
          startedAt: DateTime(now.year, now.month, 10, 8, 0),
          endedAt: DateTime(now.year, now.month, 10, 16, 0),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value(monthSessions)),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value(monthSessions)),
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
      await tester.tap(find.text('Month').first);
      await tester.pumpAndSettle();

      // Verify header changed to MONTH FOCUS TIME
      expect(find.text('MONTH FOCUS TIME'), findsOneWidget);

      // Verify W1..W4 weekly bars exist
      expect(find.text('W1'), findsOneWidget);
      expect(find.text('W2'), findsOneWidget);
      expect(find.text('W3'), findsOneWidget);
      expect(find.text('W4'), findsOneWidget);

      // Peak week is W2 with 8.0h
      expect(find.textContaining('Peak: W2'), findsOneWidget);
    });

    testWidgets('Tapping date range in Trend mode opens Telemetry Trend Window dialog with selectable presets', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
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
      await tester.tap(find.text('Trend').first);
      await tester.pumpAndSettle();

      // Tap on the date switcher container
      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();

      // Verify Telemetry Trend Window dialog opened
      expect(find.text('Telemetry Trend Window'), findsOneWidget);
      expect(find.text('QUICK PRESETS'), findsOneWidget);
      expect(find.text('Last 7 Days'), findsOneWidget);
      expect(find.text('Last 14 Days'), findsOneWidget);
      expect(find.text('Last 30 Days'), findsOneWidget);
      expect(find.text('CUSTOM RANGE'), findsOneWidget);

      // Select 'Last 14 Days' preset
      await tester.tap(find.text('Last 14 Days'));
      await tester.pumpAndSettle();

      // Apply window
      await tester.tap(find.text('Apply Window'));
      await tester.pumpAndSettle();

      // Dialog is dismissed
      expect(find.text('Telemetry Trend Window'), findsNothing);
    });
  });
}
