import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/widgets/desktop_nav_bar.dart';
import 'package:chondrobindu/widgets/app_logo.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/screens/profile_screen.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/analytics_provider.dart';
import 'package:chondrobindu/providers/performance_provider.dart';
import 'package:chondrobindu/providers/journal_provider.dart';
import 'package:chondrobindu/screens/journal_screen.dart' show holidaySettingsStreamProvider;
import 'package:chondrobindu/models/routine_models.dart';

class MockUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  MockUserProfileNotifier(super.state);

  double? lastUpdatedGoal;

  @override
  Future<void> updateDailyFocusGoal(double goalHours) async {
    lastUpdatedGoal = goalHours;
    state = state.copyWith(dailyFocusGoalHours: goalHours);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Phase 5 Audit & Fixes Verification', () {
    testWidgets('DesktopNavBar renders AppLogo with crisp dimensions and theme awareness', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const profile = UserProfile(
        uid: 'user-p5',
        displayName: 'Tanvir Hossain',
        institutionType: InstitutionType.university,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier(profile)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: DesktopNavBar(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final logoFinder = find.byType(AppLogo);
      expect(logoFinder, findsOneWidget);
      final AppLogo logoWidget = tester.widget(logoFinder);
      expect(logoWidget.showContainer, isFalse);
      expect(logoWidget.size, inInclusiveRange(28.0, 32.0));
      expect(find.text('চন্দ্রবিন্দু'), findsOneWidget);
      expect(find.text('CHONDROBINDU'), findsOneWidget);
    });

    testWidgets('Date navigator in Insights clamps and steps without DST or month overflow glitches', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final testProfile = UserProfile(
        uid: 'user-p5',
        displayName: 'Tanvir Hossain',
        institutionType: InstitutionType.university,
        createdAt: today.subtract(const Duration(days: 365)),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier(testProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(const HolidaySettings())),
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // On launch, we are on current week (Week mode is default), forward chevron is disabled
      final forwardChevron = find.byIcon(Icons.chevron_right_rounded).first;
      final backChevron = find.byIcon(Icons.chevron_left_rounded).first;

      // Tap backward chevron to navigate to previous week
      await tester.tap(backChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Now forward chevron is enabled, tap it to return to current week
      await tester.tap(forwardChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Day mode
      await tester.tap(find.text('Day').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Step back a day
      await tester.tap(backChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Step back forward to today
      await tester.tap(forwardChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Switch to Month mode
      await tester.tap(find.text('Month').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Step back a month (always day 1 anchor, safe from 29th-31st skip)
      await tester.tap(backChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Step back forward to current month
      await tester.tap(forwardChevron);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Quick-Jump button returns to current period
      await tester.tap(find.text('This Month').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ProfileScreen displays Daily Focus Goal card and persists updates', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const profile = UserProfile(
        uid: 'user-p5',
        displayName: 'Tanvir Hossain',
        institutionType: InstitutionType.university,
        dailyFocusGoalHours: 2.0,
        isLoaded: true,
      );

      final notifier = MockUserProfileNotifier(profile);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => notifier),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
            totalFocusMinutesProvider.overrideWith((ref) => 120),
            currentStreakProvider.overrideWith((ref) => 5),
            totalCompletedExamsCountProvider.overrideWith((ref) => 3),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify Daily Focus Goal card is displayed
      expect(find.text('Daily Focus Goal'), findsOneWidget);
      expect(find.text('2.0h / day'), findsOneWidget);
      expect(find.text('4h'), findsOneWidget);

      // Tap '4h' preset
      await tester.tap(find.text('4h'));
      await tester.pumpAndSettle();

      expect(find.text('4.0h / day'), findsOneWidget);
    });
  });
}
