import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
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
          coursesStreamProvider.overrideWith((ref) => Stream.value([
            const Course(
              id: 'c1',
              code: 'EEE 101',
              title: 'Electric Circuits I',
              credits: 3.0,
              totalTopicsCount: 10,
              completedTopicsCount: 4,
            ),
          ])),
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

  testWidgets('HomeDashboard renders authentic zero-states for new accounts with 0 courses', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(const UserProfile(
            fullName: 'New Scholar',
            displayName: 'Scholar',
            isOnboarded: true,
            isUniversityStudent: true,
            universityName: 'BUET',
            department: 'EEE',
            level: '1',
            term: '1',
            targetGpa: 3.80,
          ))),
          coursesStreamProvider.overrideWith((ref) => Stream.value([])),
        ],
        child: const MaterialApp(
          home: HomeDashboardScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Academic Standing shows NO DATA and — / 4.00
    expect(find.text('NO DATA'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0% Covered'), findsOneWidget);
    expect(find.text('Target: 3.80'), findsOneWidget);

    // 2. Recommended Deep Work Target shows clean empty state
    expect(find.text('No Active Courses Yet'), findsOneWidget);
    expect(find.text('Add First Course →'), findsOneWidget);

    // 3. Courses Health shows clean empty state
    expect(find.text('0 Courses • 0.0 Cr'), findsOneWidget);
    expect(find.text('No courses enrolled yet. Head to the Courses tab to build your syllabus.'), findsOneWidget);

    // 4. Focus by Course shows clean empty state
    expect(find.text('Complete your first focus timer session to see your course breakdown here.'), findsOneWidget);
  });
}
