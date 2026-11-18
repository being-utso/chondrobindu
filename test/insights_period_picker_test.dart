import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/screens/journal_screen.dart';
import 'package:chondrobindu/models/routine_models.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';

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

  group('InsightsScreen Period Picker Modal & Date Stepper Tests', () {
    testWidgets('tapping date label opens PeriodPickerModal dialog in Day mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
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

      // Find date label with calendar icon
      final calendarIcon = find.byIcon(Icons.calendar_month_rounded);
      expect(calendarIcon, findsOneWidget);

      // Tap calendar date label to open modal
      await tester.tap(calendarIcon);
      await tester.pumpAndSettle();

      // Modal is open
      expect(find.text('Select Study Date'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Tap close icon to close
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Select Study Date'), findsNothing);
    });

    testWidgets('tapping date label in Month mode opens Month Picker with 12 months', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
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

      // Tap calendar date label to open modal
      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Select Calendar Month'), findsOneWidget);
      expect(find.text('Jan'), findsOneWidget);
      expect(find.text('Dec'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping date label in Trend mode opens Trend Picker with presets', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
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

      // Tap calendar date label
      await tester.tap(find.byIcon(Icons.calendar_month_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Telemetry Trend Window'), findsOneWidget);
      expect(find.text('Last 7 Days'), findsOneWidget);
      expect(find.text('Last 14 Days'), findsOneWidget);
      expect(find.text('Last 30 Days'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
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
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
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
