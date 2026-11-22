import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:chondrobindu/models/assessment_model.dart';
import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/models/journal_entry_model.dart';
import 'package:chondrobindu/models/syllabus_models.dart';
import 'package:chondrobindu/providers/analytics_provider.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/journal_provider.dart';
import 'package:chondrobindu/providers/performance_provider.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/screens/profile_screen.dart';
import 'package:chondrobindu/widgets/desktop_nav_bar.dart';

class MockUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  MockUserProfileNotifier(super.state);

  @override
  Future<void> updateProfile({
    String? fullName,
    String? nickname,
    String? username,
    String? email,
    String? phone,
    String? college,
    String? hscBatch,
    String? hscGroup,
    String? district,
    String? primaryTarget,
    String? secondaryTarget,
    bool? isOnboarded,
    String? profileImageUrl,
    int? todaysFocusMinutes,
    int? totalFocusMinutes,
    int? streakDays,
    int? targetFocusMinutes,
    String? scratchpadText,
    bool? isUniversityStudent,
    InstitutionType? institutionType,
    String? universityName,
    String? major,
    String? level,
    String? term,
    double? targetGpa,
    DateTime? termStartDate,
    bool clearTermStartDate = false,
    double? dailyFocusGoalHours,
    String? uid,
  }) async {
    state = state.copyWith(
      fullName: fullName,
      nickname: nickname,
      username: username,
      email: email,
      phone: phone,
      college: college,
      hscBatch: hscBatch,
      hscGroup: hscGroup,
      district: district,
      primaryTarget: primaryTarget,
      secondaryTarget: secondaryTarget,
      isOnboarded: isOnboarded,
      profileImageUrl: profileImageUrl,
      todaysFocusMinutes: todaysFocusMinutes,
      totalFocusMinutes: totalFocusMinutes,
      streakDays: streakDays,
      targetFocusMinutes: targetFocusMinutes,
      scratchpadText: scratchpadText,
      isUniversityStudent: isUniversityStudent,
      institutionType: institutionType,
      universityName: universityName,
      major: major,
      level: level,
      term: term,
      targetGpa: targetGpa,
      termStartDate: termStartDate,
      clearTermStartDate: clearTermStartDate,
      dailyFocusGoalHours: dailyFocusGoalHours,
    );
  }

  @override
  Future<void> updateDailyFocusGoal(double hours) async {
    state = state.copyWith(
      dailyFocusGoalHours: hours,
      targetFocusMinutes: (hours * 60).round(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Phase 6: UserProfile Model & Serialization Tests', () {
    test('termStartDate parses cleanly from Timestamp, ISO String, and handles null', () {
      final sampleDate = DateTime(2026, 1, 15);
      final fromTimestampMap = {
        'termStartDate': Timestamp.fromDate(sampleDate),
        'targetGpa': 3.85,
        'institutionType': 'university',
      };
      final profileA = UserProfile.fromMap(fromTimestampMap, 'user_1');
      expect(profileA.termStartDate, equals(sampleDate));
      expect(profileA.targetGpa, equals(3.85));
      expect(profileA.isUniversityStudent, isTrue);

      final fromStringMap = {
        'term_start_date': sampleDate.toIso8601String(),
        'target_gpa': 3.90,
      };
      final profileB = UserProfile.fromMap(fromStringMap, 'user_2');
      expect(profileB.termStartDate, equals(sampleDate));
      expect(profileB.targetGpa, equals(3.90));

      final nullMap = <String, dynamic>{};
      final profileC = UserProfile.fromMap(nullMap, 'user_3');
      expect(profileC.termStartDate, isNull);
    });

    test('termStartDate serializes to Timestamp in toMap and copyWith handles updates/clearing', () {
      final testDate = DateTime(2026, 2, 1);
      final profile = UserProfile.defaultProfile.copyWith(
        termStartDate: testDate,
        targetGpa: 3.80,
      );

      final mapped = profile.toMap();
      expect(mapped['termStartDate'], isA<Timestamp>());
      expect((mapped['termStartDate'] as Timestamp).toDate(), equals(testDate));
      expect(mapped['targetGpa'], equals(3.80));

      // Test clearTermStartDate in copyWith
      final cleared = profile.copyWith(clearTermStartDate: true);
      expect(cleared.termStartDate, isNull);
    });
  });

  group('Phase 6: Global Quick Search (⌘K) Dialog Tests', () {
    final testCourses = [
      const Course(
        id: 'c1',
        code: 'EEE 2105',
        title: 'Signals & Systems',
        credits: 3.0,
        rawData: {
          'syllabusData': [
            {
              'id': 'n1',
              'title': 'Continuous Fourier Transform',
              'children': [
                {'id': 'n1_1', 'title': 'Inverse Fourier Properties'},
              ],
            },
          ],
        },
      ),
      const Course(
        id: 'c2',
        code: 'CSE 2100',
        title: 'Data Structures Lab',
        courseType: CourseType.sessional,
        credits: 1.5,
      ),
    ];

    final testSubjects = [
      const Subject(
        id: 's1',
        title: 'Physics 1st Paper',
        chapters: [
          Chapter(
            id: 'ch1',
            title: 'Vector Analysis',
            sections: [
              StudySection(id: 'sec1', title: 'Dot and Cross Products'),
            ],
          ),
        ],
      ),
    ];

    final testAssessments = [
      Assessment(
        id: 'a1',
        name: 'CT 1 Fourier Analysis',
        courseCode: 'EEE 2105',
        totalMarks: 20.0,
        date: DateTime(2026, 3, 10),
      ),
    ];

    final testJournal = [
      StudyJournalEntry(
        id: 'j1',
        title: 'Deep Work on Signals',
        content: 'Derived convolution integrals for unit step responses.',
        topicsCovered: 'Signals & Systems, Fourier Transform',
        durationMinutes: 90,
        subjectOrCourseId: 'EEE 2105',
        timestamp: DateTime(2026, 2, 20),
      ),
    ];

    testWidgets('global search finds courses, subjects, topics, assessments, and journal entries', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      int selectedTab = -1;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier(
                  UserProfile.defaultProfile.copyWith(isLoaded: true),
                )),
            coursesStreamProvider.overrideWith((ref) => Stream.value(testCourses)),
            activeSyllabusSubjectsStreamProvider.overrideWith((ref) => Stream.value(testSubjects)),
            allAssessmentsStreamProvider.overrideWith((ref) => Stream.value(testAssessments)),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value(testAssessments)),
            journalStreamProvider.overrideWith((ref) => Stream.value(testJournal)),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: DesktopNavBar(
                  selectedIndex: 0,
                  onDestinationSelected: (idx) => selectedTab = idx,
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open Global Search Dialog
      final searchPill = find.text('Search anything...');
      expect(searchPill, findsOneWidget);
      await tester.tap(searchPill);
      await tester.pumpAndSettle();

      // Find Search Dialog TextField
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // 1. Search for course "EEE"
      await tester.enterText(searchField, 'EEE');
      await tester.pumpAndSettle();

      expect(find.text('COURSES'), findsOneWidget);
      expect(find.textContaining('EEE 2105'), findsWidgets);

      // 2. Search for topic "Fourier"
      await tester.enterText(searchField, 'Fourier');
      await tester.pumpAndSettle();

      expect(find.text('SYLLABUS TOPICS'), findsOneWidget);
      expect(find.text('Continuous Fourier Transform'), findsOneWidget);
      expect(find.text('PLANNER & ASSESSMENTS'), findsOneWidget);
      expect(find.textContaining('CT 1 Fourier Analysis'), findsOneWidget);

      // 3. Search for subject "Physics"
      await tester.enterText(searchField, 'Physics');
      await tester.pumpAndSettle();

      expect(find.text('SUBJECTS'), findsOneWidget);
      expect(find.text('Physics 1st Paper'), findsOneWidget);

      // 4. Search for journal entry "convolution"
      await tester.enterText(searchField, 'convolution');
      await tester.pumpAndSettle();

      expect(find.text('JOURNAL ENTRIES'), findsOneWidget);
      expect(find.text('Deep Work on Signals'), findsOneWidget);

      // 5. Tap on Journal entry result and verify tab navigation to Tab 4
      await tester.tap(find.text('Deep Work on Signals'));
      await tester.pumpAndSettle();

      expect(selectedTab, equals(4));
    });
  });

  group('Phase 6: Profile & Settings Screen Tests', () {
    testWidgets('renders academic track selector, ambient audio preferences, and updates target CGPA cleanly', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const initialProfile = UserProfile(
        uid: 'user_uni',
        email: 'sayem@buet.ac.bd',
        displayName: 'Shahriyer Sayem',
        fullName: 'Shahriyer Sayem',
        nickname: 'Sayem',
        username: 'sayem25',
        institutionType: InstitutionType.university,
        isLoaded: true,
        universityName: 'BUET',
        department: 'EEE',
        level: '2',
        term: '1',
        targetGpa: 3.80,
        dailyFocusGoalHours: 2.0,
      );

      final notifier = MockUserProfileNotifier(initialProfile);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => notifier),
            currentStreakProvider.overrideWith((ref) => 12),
            totalFocusMinutesProvider.overrideWith((ref) => 3600),
            totalCompletedExamsCountProvider.overrideWith((ref) => 15),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header and Name
      expect(find.text('Personal Profile'), findsOneWidget);
      expect(find.text('Shahriyer Sayem'), findsWidgets);

      // Verify 3 Academic Tracks selector rendered
      expect(find.text('Academic Track'), findsOneWidget);
      expect(find.text('University'), findsOneWidget);
      expect(find.text('College / HSC'), findsOneWidget);
      expect(find.text('Admission Prep'), findsOneWidget);

      // Verify University specific fields visible (Target CGPA & Term Start Date)
      expect(find.text('Target CGPA'), findsOneWidget);
      expect(find.text('Term Start Date'), findsOneWidget);
      expect(find.text('Archived Semesters'), findsOneWidget);

      // Verify Ambient Audio & Soundscapes Preferences card rendered
      expect(find.text('Ambient Audio & Soundscapes'), findsOneWidget);
      expect(find.text('Rainfall'), findsOneWidget);
      expect(find.text('Heavy Rain'), findsOneWidget);
      expect(find.text('Brown Noise'), findsOneWidget);

      // Verify Daily Focus Goal Selector
      expect(find.text('Daily Focus Goal'), findsOneWidget);
      expect(find.text('2.0h / day'), findsOneWidget);

      // Switch to College / HSC Track
      await tester.tap(find.text('College / HSC'));
      await tester.pumpAndSettle();

      // Target CGPA & Archived Semesters should now be hidden
      expect(find.text('Target CGPA'), findsNothing);
      expect(find.text('Archived Semesters'), findsNothing);
      expect(find.text('College / Institution'), findsOneWidget);
      expect(find.text('HSC Batch'), findsOneWidget);

      // Switch to Admission Prep Track
      await tester.tap(find.text('Admission Prep'));
      await tester.pumpAndSettle();

      // Admission Target Goals should now be visible
      expect(find.text('Admission Target Goals'), findsOneWidget);
      expect(find.text('Admission Target Goal'), findsOneWidget);
    });

    testWidgets('profile screen renders cleanly in both Light and Dark modes', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const initialProfile = UserProfile(
        uid: 'user_light',
        email: 'light@buet.ac.bd',
        displayName: 'Light Mode Student',
        fullName: 'Light Mode Student',
        nickname: 'Light',
        username: 'light_student',
        institutionType: InstitutionType.university,
        isLoaded: true,
        universityName: 'BUET',
        department: 'CSE',
        level: '1',
        term: '1',
        targetGpa: 3.75,
      );

      // Light Mode test
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier(initialProfile)),
            currentStreakProvider.overrideWith((ref) => 5),
            totalFocusMinutesProvider.overrideWith((ref) => 1200),
            totalCompletedExamsCountProvider.overrideWith((ref) => 3),
          ],
          child: MaterialApp(
            theme: ThemeData.light(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal Profile'), findsOneWidget);

      // Dark Mode test
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => MockUserProfileNotifier(initialProfile)),
            currentStreakProvider.overrideWith((ref) => 5),
            totalFocusMinutesProvider.overrideWith((ref) => 1200),
            totalCompletedExamsCountProvider.overrideWith((ref) => 3),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Personal Profile'), findsOneWidget);
    });
  });
}
