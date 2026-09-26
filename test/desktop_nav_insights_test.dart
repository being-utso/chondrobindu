import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/widgets/desktop_nav_bar.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/models/user_profile.dart';
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

  group('DesktopNavBar Navigation Actions Tests', () {
    testWidgets('renders desktop navbar brand, search pill, notification bell and profile chip', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testProfile = UserProfile(
        uid: 'test-user',
        email: 'test@chondrobindu.edu',
        displayName: 'Ayesha Rahman',
        institutionType: InstitutionType.university,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(64),
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

      // Brand
      expect(find.text('চন্দ্রবিন্দু'), findsOneWidget);
      expect(find.text('CHONDROBINDU'), findsOneWidget);

      // Search pill
      expect(find.text('Search anything...'), findsOneWidget);
      expect(find.text('⌘K'), findsOneWidget);

      // Profile chip
      expect(find.text('Ayesha Rahman'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);

      // Notification bell icon
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

    testWidgets('tapping search pill opens global search dialog', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(UserProfile.defaultProfile)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(64),
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

      // Tap search pill
      await tester.tap(find.text('Search anything...'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Type a course code (e.g. EEE 2105) or assessment name...'), findsOneWidget);
      expect(find.text('ESC'), findsOneWidget);
    });

    testWidgets('tapping notification bell opens dropdown with empty state when no alerts', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(UserProfile.defaultProfile)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(64),
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

      // Tap notification bell
      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pumpAndSettle();

      // Popup menu contents
      expect(find.text('All caught up! No upcoming exam or routine alerts.'), findsOneWidget);
    });

    testWidgets('tapping profile menu opens dropdown with academic track and sign out', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testProfile = UserProfile(
        uid: 'test-user',
        email: 'student@chondrobindu.edu',
        displayName: 'Tanvir Hossain',
        institutionType: InstitutionType.university,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(64),
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

      // Tap profile chip
      await tester.tap(find.text('Tanvir Hossain'));
      await tester.pumpAndSettle();

      // Popup menu items
      expect(find.text('student@chondrobindu.edu'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Help & Support'), findsOneWidget);
      expect(find.text('About Developer'), findsOneWidget);
      expect(find.text('Sign Out'), findsOneWidget);
    });
  });

  group('InsightsScreen Desktop Analytics Tests', () {
    testWidgets('renders desktop period selector and authentic zero KPI state', (tester) async {
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
          ],
          child: const MaterialApp(
            home: InsightsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Period filters
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Trend'), findsOneWidget);

      // KPIs for zero sessions
      expect(find.text('0h 0m'), findsWidgets);
      expect(find.text('TOTAL FOCUS TIME'), findsOneWidget);
      expect(find.text('SESSIONS'), findsOneWidget);
      expect(find.text('MAX SINGLE SESSION'), findsOneWidget);
      expect(find.text('AVG DAILY FOCUS'), findsOneWidget);

      // Empty state prompt
      expect(find.text('No study sessions recorded for this period. Use the Timer to start logging focus blocks.'), findsOneWidget);
      expect(find.text('Start Focus'), findsOneWidget);

      // Switch to Day period
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();
      expect(find.text('DAY FOCUS TIME'), findsOneWidget);

      // Verify date stepping chevrons
      final chevronRight = find.byIcon(Icons.chevron_right_rounded);
      expect(chevronRight, findsOneWidget);
      await tester.tap(chevronRight);
      await tester.pumpAndSettle();
    });
  });
}
