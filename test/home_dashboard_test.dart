import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chondrobindu/screens/home_dashboard.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';

class FakeUserProfileNotifier extends UserProfileNotifier {
  FakeUserProfileNotifier(UserProfile initial) : super(firestore: null, auth: null, storage: null) {
    state = initial;
  }
}

void main() {
  testWidgets('HomeDashboard renders Header Banner, 3 KPI Bento Cards and Bento Grid on Desktop', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(const UserProfile(
            fullName: 'Shahriyer Sayem',
            displayName: 'Shahriyer',
            isOnboarded: true,
            isUniversityStudent: true,
            universityName: 'BUET',
            department: 'EEE',
            level: '1',
            term: '1',
            hscBatch: '25',
          ))),
        ],
        child: const MaterialApp(
          home: HomeDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Header & Greeting
    expect(find.textContaining('Shahriyer'), findsWidgets);
    expect(find.textContaining('Level 1 • Term 1 • EEE'), findsOneWidget);
    expect(find.text('Log Note'), findsOneWidget);
    expect(find.text('Start Focus'), findsOneWidget);

    // 2. Top KPI Cards
    expect(find.text('SEMESTER CGPA STANDING'), findsOneWidget);
    expect(find.text('TODAY\'S FOCUS TIME'), findsOneWidget);
    expect(find.text('STUDY STREAK'), findsOneWidget);

    // 3. Main Bento Left & Right
    expect(find.text('RECOMMENDED DEEP WORK TARGET'), findsOneWidget);
    expect(find.text('Launch Focus Session →'), findsOneWidget);
    expect(find.text('Today\'s Agenda'), findsOneWidget);
    expect(find.text('Courses Health'), findsOneWidget);
    expect(find.text('Focus by Course'), findsOneWidget);
    expect(find.text('Brain Dump & Quick Scratchpad'), findsOneWidget);
    expect(find.text('Quick Actions & Utilities'), findsOneWidget);
  });

  testWidgets('HomeDashboard renders vertically responsive stack on Mobile (<768px)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(const UserProfile(
            fullName: 'Shahriyer Sayem',
            displayName: 'Shahriyer',
            isOnboarded: true,
            isUniversityStudent: false,
            primaryTarget: 'Engineering (BUET, CKRUET)',
            hscBatch: '2025',
            hscGroup: 'Science',
          ))),
        ],
        child: const MaterialApp(
          home: HomeDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Context badge for College/Admission track
    expect(find.textContaining('HSC \'2025 • Science'), findsOneWidget);
    expect(find.text('ADMISSION TARGET'), findsOneWidget);
    expect(find.text('STUDY STREAK'), findsOneWidget);
    expect(find.text('RECOMMENDED DEEP WORK TARGET'), findsOneWidget);
  });
}
