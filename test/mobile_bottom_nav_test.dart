import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/models/routine_models.dart';
import 'package:chondrobindu/services/exam_service.dart';
import 'package:chondrobindu/screens/main_nav.dart';
import 'package:chondrobindu/screens/journal_screen.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/providers/nav_provider.dart';
import 'package:chondrobindu/providers/journal_provider.dart';
import 'package:chondrobindu/providers/notes_provider.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';

class FakeUserProfileNotifier extends UserProfileNotifier {
  FakeUserProfileNotifier(UserProfile initial) : super(firestore: null, auth: null, storage: null) {
    state = initial;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Mobile Bottom Navigation Bar 6-Tab Tests', () {
    testWidgets('renders all 6 navigation destinations including Journal on compact mobile viewport (360dp)', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testProfile = UserProfile(
        uid: 'test-user',
        email: 'test@chondrobindu.edu',
        displayName: 'Shahriyer',
        isOnboarded: true,
        isUniversityStudent: false,
        primaryTarget: 'Engineering (BUET, CKRUET)',
        hscBatch: '2025',
        hscGroup: 'Science',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
            navigationIndexProvider.overrideWith((ref) => 0),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            notesStreamProvider.overrideWith((ref) => Stream.value([])),
            universityCoursesStreamProvider.overrideWith((ref) => Stream.value([])),
            holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(HolidaySettings.defaultSettings)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value([])),
            examsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: MainNavigationScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify all 6 tabs exist in the NavigationBar
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Home'), findsWidgets);
      expect(find.text('Syllabus'), findsWidgets);
      expect(find.text('Timer'), findsWidgets);
      expect(find.text('Planner'), findsWidgets);
      expect(find.text('Journal'), findsWidgets);
      expect(find.text('Insights'), findsWidgets);

      // Verify the Journal tab icon is present
      expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);

      // Tap the Journal tab destination (index 4)
      await tester.tap(find.text('Journal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify selected icon in NavigationBar updates to filled auto_stories_rounded
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.byIcon(Icons.auto_stories_rounded),
        ),
        findsOneWidget,
      );
      expect(find.byType(JournalScreen), findsOneWidget);
    });

    testWidgets('top app bar journal icon jumps to Journal tab at index 4', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const testProfile = UserProfile(
        uid: 'test-user',
        email: 'test@chondrobindu.edu',
        displayName: 'Shahriyer',
        isOnboarded: true,
        isUniversityStudent: false,
        primaryTarget: 'Engineering (BUET, CKRUET)',
        hscBatch: '2025',
        hscGroup: 'Science',
      );

      final container = ProviderContainer(
        overrides: [
          userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testProfile)),
          navigationIndexProvider.overrideWith((ref) => 0),
          journalStreamProvider.overrideWith((ref) => Stream.value([])),
          notesStreamProvider.overrideWith((ref) => Stream.value([])),
          universityCoursesStreamProvider.overrideWith((ref) => Stream.value([])),
          holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(HolidaySettings.defaultSettings)),
          upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          coursesStreamProvider.overrideWith((ref) => Stream.value([])),
          examsStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: MainNavigationScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initially at tab 0
      expect(container.read(navigationIndexProvider), 0);

      // Tap top app bar Journal shortcut icon
      final journalTopBarBtn = find.byTooltip('Academic Journal');
      expect(journalTopBarBtn, findsOneWidget);
      await tester.tap(journalTopBarBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify index is now 4
      expect(container.read(navigationIndexProvider), 4);
      expect(find.byType(JournalScreen), findsOneWidget);
    });
  });
}
