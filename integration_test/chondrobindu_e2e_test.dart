import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chondrobindu/main.dart';
import 'package:chondrobindu/models/assessment_model.dart';
import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/models/routine_slot_model.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/screens/main_nav.dart';
import 'package:chondrobindu/screens/timer_screen.dart';
import 'package:chondrobindu/widgets/desktop_nav_bar.dart';

class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  Future<void> addFocusMinutes(int minutes) async {
    state = state.copyWith(
      todaysFocusMinutes: state.todaysFocusMinutes + minutes,
      totalFocusMinutes: state.totalFocusMinutes + minutes,
    );
  }

  @override
  void setUserProfile(UserProfile profile) {
    state = profile;
  }

  @override
  void resetProfile() {
    state = UserProfile.defaultProfile;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Chondrobindu End-to-End QA Pipeline Test', (WidgetTester tester) async {
    // 1. Hook into FlutterError.onError to detect any layout overflow or assertions
    final List<FlutterErrorDetails> overflowErrors = [];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed') || details.summary.toString().contains('overflowed')) {
        overflowErrors.add(details);
      }
      originalOnError?.call(details);
    };

    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    // 2. Setup mock data
    const mockProfile = UserProfile(
      uid: 'qa-tester-uid',
      email: 'qa@chondrobindu.edu',
      displayName: 'QA Tester',
      fullName: 'QA Tester',
      nickname: 'QA',
      username: 'qatester',
      institutionType: InstitutionType.university,
      isOnboarded: true,
      isLoaded: true,
      universityName: 'BUET',
      department: 'CSE',
      level: '2',
      term: '1',
      targetGpa: 3.85,
      streakDays: 5,
      todaysFocusMinutes: 45,
      totalFocusMinutes: 320,
    );

    final mockCourses = [
      const Course(
        id: 'c1',
        code: 'CSE 201',
        title: 'Object Oriented Programming',
        courseType: CourseType.theory,
        credits: 3.0,
        colorHex: '#34D399',
      ),
      const Course(
        id: 'c2',
        code: 'CSE 202',
        title: 'OOP Sessional',
        courseType: CourseType.sessional,
        credits: 1.5,
        colorHex: '#F2B78A',
      ),
    ];

    final mockAssessments = [
      Assessment(
        id: 'a1',
        courseId: 'c1',
        courseCode: 'CSE 201',
        name: 'Class Test 1',
        date: DateTime.now().add(const Duration(days: 3)),
        totalMarks: 20.0,
      ),
    ];

    final mockRoutine = [
      const RoutineSlot(
        id: 'r1',
        courseId: 'c1',
        courseCode: 'CSE 201',
        courseTitle: 'Object Oriented Programming',
        dayOfWeek: 1,
        startTime: '10:00 AM',
        endTime: '11:30 AM',
        room: 'Room 302',
      ),
    ];

    // Helper functions for desktop and mobile navigation
    Future<void> navigateDesktopTab(String label) async {
      final tabFinder = find.descendant(
        of: find.byType(DesktopNavBar),
        matching: find.text(label),
      );
      expect(tabFinder, findsOneWidget, reason: 'Desktop nav tab "$label" must exist');
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();
      expect(overflowErrors, isEmpty, reason: 'No overflow after navigating to desktop tab "$label"');
    }

    Future<void> navigateMobileTab(String label) async {
      final tabFinder = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      expect(tabFinder, findsOneWidget, reason: 'Mobile nav tab "$label" must exist');
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();
      expect(overflowErrors, isEmpty, reason: 'No overflow after navigating to mobile tab "$label"');
    }

    // 3. Set Desktop Viewport (1440x900)
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;

    // Boot Chondrobindu with mocked Riverpod providers
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(mockProfile)),
          liveUserProfileProvider.overrideWith((ref) => Stream.value(mockProfile)),
          coursesStreamProvider.overrideWith((ref) => Stream.value(mockCourses)),
          upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value(mockAssessments)),
          allAssessmentsStreamProvider.overrideWith((ref) => Stream.value(mockAssessments)),
          weeklyRoutineStreamProvider.overrideWith((ref) => Stream.value(mockRoutine)),
          dailyAgendaStreamProvider.overrideWith((ref, date) => Stream.value(mockRoutine)),
        ],
        child: const ChondrobinduApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(overflowErrors, isEmpty, reason: 'No overflow during initial app boot');

    // 4. Trigger Debug Bypass into MainNavigationScreen
    final bypassButton = find.byKey(const Key('qa_bypass_button'));
    expect(bypassButton, findsOneWidget, reason: 'QA bypass button must exist on AuthScreen in debug mode');
    await tester.tap(bypassButton);
    await tester.pumpAndSettle();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow after triggering QA bypass');

    // 5. Desktop Viewport (1440x900): Traverse all 5 primary tabs
    // Tab 0: Home
    await navigateDesktopTab('Home');
    expect(find.text('চন্দ্রবিন্দু'), findsWidgets);

    // Tab 1: Courses
    await navigateDesktopTab('Courses');

    // Tab 2: Timer
    await navigateDesktopTab('Timer');
    expect(find.byType(TimerScreen), findsOneWidget);

    // Tab 3: Planner
    await navigateDesktopTab('Planner');

    // Tab 4: Insights
    await navigateDesktopTab('Insights');

    // 6. Test Desktop Profile Modal: Open and Close
    final profileButton = find.descendant(
      of: find.byType(DesktopNavBar),
      matching: find.text('QA Tester'),
    );
    expect(profileButton, findsOneWidget);
    await tester.tap(profileButton);
    await tester.pumpAndSettle();

    // Verify popup menu opened
    expect(find.text('About Developer'), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow when opening profile menu');

    // Close the popup menu safely
    Navigator.of(tester.element(find.text('About Developer'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('About Developer'), findsNothing);
    expect(overflowErrors, isEmpty, reason: 'No overflow after closing profile menu');

    // 7. Test Planner Schedule Modal: Open and Close
    await navigateDesktopTab('Planner');
    final scheduleButton = find.widgetWithText(FloatingActionButton, 'Schedule');
    expect(scheduleButton, findsOneWidget);
    await tester.tap(scheduleButton);
    await tester.pumpAndSettle();

    // Verify schedule modal bottom sheet opened
    expect(find.text('Schedule New Item'), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow when opening Schedule modal');

    // Close the schedule modal bottom sheet
    Navigator.of(tester.element(find.text('Schedule New Item'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Schedule New Item'), findsNothing);
    expect(overflowErrors, isEmpty, reason: 'No overflow after closing Schedule modal');

    // 8. Test Timer: Start, Pause, and Reset
    await navigateDesktopTab('Timer');
    final playBtn = find.descendant(
      of: find.byType(TimerScreen),
      matching: find.byIcon(Icons.play_arrow_rounded),
    );
    expect(playBtn, findsOneWidget);
    await tester.tap(playBtn);
    await tester.pump();

    // Verify running state (icon switched to pause)
    final pauseBtn = find.descendant(
      of: find.byType(TimerScreen),
      matching: find.byIcon(Icons.pause_rounded),
    );
    expect(pauseBtn, findsOneWidget);

    // Pause the timer
    await tester.tap(pauseBtn);
    await tester.pump();

    // Verify paused state (icon switched back to play)
    expect(find.descendant(
      of: find.byType(TimerScreen),
      matching: find.byIcon(Icons.play_arrow_rounded),
    ), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow during desktop timer controls');

    // 9. Resize to Mobile Viewport (375x812)
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();
    expect(overflowErrors, isEmpty, reason: 'No overflow after resizing to mobile viewport');

    // 10. Mobile Viewport (375x812): Traverse all 5 primary tabs
    // Tab 0: Home
    await navigateMobileTab('Home');

    // Tab 1: Courses
    await navigateMobileTab('Courses');

    // Tab 2: Timer
    await navigateMobileTab('Timer');
    expect(find.byType(TimerScreen), findsOneWidget);

    // Test Mobile Timer: Start Session, Pause, and Discard (Reset)
    final startSessionBtn = find.text('Start Session');
    expect(startSessionBtn, findsOneWidget);
    await tester.tap(startSessionBtn);
    await tester.pump();

    // Verify mobile timer started
    final mobilePauseBtn = find.text('Pause');
    expect(mobilePauseBtn, findsOneWidget);

    // Pause mobile timer
    await tester.tap(mobilePauseBtn);
    await tester.pump();

    // Resume / Discard controls are visible
    final discardBtn = find.text('Discard');
    expect(discardBtn, findsOneWidget);

    // Reset timer back to idle
    await tester.tap(discardBtn);
    await tester.pumpAndSettle();
    expect(find.text('Start Session'), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow during mobile timer start/pause/discard');

    // Tab 3: Planner
    await navigateMobileTab('Planner');

    // Test Schedule Modal in Mobile Viewport
    final mobileScheduleBtn = find.widgetWithText(FloatingActionButton, 'Schedule');
    expect(mobileScheduleBtn, findsOneWidget);
    await tester.tap(mobileScheduleBtn);
    await tester.pumpAndSettle();

    expect(find.text('Schedule New Item'), findsOneWidget);
    expect(overflowErrors, isEmpty, reason: 'No overflow when opening mobile Schedule modal');

    Navigator.of(tester.element(find.text('Schedule New Item'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Schedule New Item'), findsNothing);
    expect(overflowErrors, isEmpty, reason: 'No overflow after closing mobile Schedule modal');

    // Tab 4: Insights
    await navigateMobileTab('Insights');
    expect(overflowErrors, isEmpty, reason: 'No overflow on mobile Insights tab');

    // Final Assertion
    expect(overflowErrors, isEmpty, reason: 'All viewports and interactive flows must complete with 0 overflows');
  });
}
