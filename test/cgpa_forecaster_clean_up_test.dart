import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/models/user_profile.dart';
import 'package:chondrobindu/providers/firestore_providers.dart';
import 'package:chondrobindu/providers/journal_provider.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart' hide UserProfile;
import 'package:chondrobindu/screens/grading_setup_screen.dart';
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/services/exam_service.dart';
import 'package:chondrobindu/widgets/cgpa_forecaster_workspace.dart';
import 'package:chondrobindu/widgets/grading_scale_settings_dialog.dart';

class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CGPA Forecaster Clean Up & Parity Tests', () {
    const testUniProfile = UserProfile(
      uid: 'user-uni-1',
      email: 'student@buet.ac.bd',
      displayName: 'Test Student',
      institutionType: InstitutionType.university,
      level: '2',
      term: '1',
      universityName: 'BUET',
      department: 'EEE',
      targetGpa: 3.80,
    );

    testWidgets('Date bar & period switcher are completely hidden on CGPA Forecaster', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testUniProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testUniProfile)),
            studySessionsRangeStreamProvider.overrideWith((ref, param) => Stream.value([])),
            recentStudySessionsStreamProvider.overrideWith((ref) => Stream.value([])),
            coursesStreamProvider.overrideWith((ref) => Stream.value(const [
              Course(id: 'eee201', code: 'EEE 201', title: 'Signals & Systems', credits: 3.0),
            ])),
            journalStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
            examsStreamProvider.overrideWith((ref) => Stream.value([])),
            upcomingAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
            allAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: InsightsScreen(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // On Overview: Day | Week | Month | Trend are visible
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);

      // Switch to CGPA Forecaster sub-tab
      await tester.tap(find.text('CGPA Forecaster').first);
      await tester.pumpAndSettle();

      // Verify date bar controls are hidden
      expect(find.text('Trend'), findsNothing);
      expect(find.byIcon(Icons.restore_rounded), findsNothing);
      expect(find.text('Today'), findsNothing);
      expect(find.text('This Week'), findsNothing);
      expect(find.text('This Month'), findsNothing);
    });

    testWidgets('Real course final marks scale to / 210 and purge all dummy marks', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // 3.0 credit theory course with no logged marks
      final courses = [
        const Course(id: 'eee201', code: 'EEE 201', title: 'Signals & Systems', credits: 3.0),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(testUniProfile)),
            liveUserProfileProvider.overrideWith((ref) => Stream.value(testUniProfile)),
            allAssessmentsStreamProvider.overrideWith((ref) => Stream.value([])),
            attendanceRecordsStreamProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: CgpaForecasterWorkspace(
                  courses: courses,
                  profile: testUniProfile,
                  isDesktop: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify NO dummy marks exist
      expect(find.textContaining('8.9 / 10'), findsNothing);
      expect(find.textContaining('16.7 / 20'), findsNothing);
      expect(find.textContaining('58.3 / 30'), findsNothing);

      // 2. Verify clean authentic zero state out of real course max marks
      // Attendance: 0.0 / 30
      expect(find.text('0.0 / 30'), findsOneWidget);
      // CT: 0.0 / 60
      expect(find.text('0.0 / 60'), findsOneWidget);
      // Term Total: 0.0 / 90
      expect(find.text('0.0 / 90'), findsOneWidget);

      // 3. Verify Final Exam scales to / 210 marks (70% of 300 total marks for 3.0 Cr)
      // At default 80% slider: 0.80 * 210 = 168.0 marks
      expect(find.textContaining('/ 210'), findsWidgets);
      expect(find.textContaining('168.0 / 210'), findsWidgets);

      // 4. Test "What Do I Need on the Final?" accordion cutoff targets
      await tester.tap(find.text('What Do I Need on the Final?'));
      await tester.pumpAndSettle();

      // For A+ (80% of 300 = 240 marks). Earned = 0. Needed = 240.
      // Since 240 > 210 (finalMaxMarks), A+ should show Out of Reach (Needs > 210)
      expect(find.text('Out of Reach'), findsWidgets);
      expect(find.text('(Needs > 210)'), findsWidgets);

      // For A- (70% of 300 = 210 marks). Earned = 0. Needed = 210.
      // Since 210 <= 210, A- should show 210.0 / 210 marks (100% on Final)
      expect(find.text('210.0 / 210 marks'), findsWidgets);
      expect(find.text('(100% on Final)'), findsWidgets);
    });

    testWidgets('Grading Scale Settings Dialog allows full editing, adding, and deleting tiers', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      List<GradingRow> savedScale = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  GradingScaleSettingsDialog.showAdaptive(
                    context: context,
                    universityName: 'BUET',
                    currentScale: [
                      GradingRow(letterGrade: 'A+', gradePoint: 4.00, minPercentage: 80, maxPercentage: 100),
                      GradingRow(letterGrade: 'A', gradePoint: 3.75, minPercentage: 75, maxPercentage: 79),
                      GradingRow(letterGrade: 'F', gradePoint: 0.00, minPercentage: 0, maxPercentage: 39),
                    ],
                    onSave: (scale) {
                      savedScale = scale;
                    },
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      // Open the modal
      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Verify modal is displayed with title and subtitle
      expect(find.text('Grading Scale Settings'), findsOneWidget);
      expect(find.text('BUET Letter Grade & GPA Conversion'), findsOneWidget);

      // Verify the Fail row has editable text fields (no locked non-editable badge)
      expect(find.widgetWithText(TextFormField, 'F'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '0.00'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '0'), findsOneWidget);

      // Test + Add Grade Tier button
      await tester.tap(find.text('+ Add Grade Tier'));
      await tester.pumpAndSettle();

      // Verify a new tier row is added with default 'C-'
      expect(find.widgetWithText(TextFormField, 'C-'), findsOneWidget);

      // Test Delete icon button on row (skip modal header close button)
      final deleteButtons = find.byIcon(Icons.close_rounded);
      expect(deleteButtons, findsWidgets);
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();

      // Save & Apply Scale
      await tester.tap(find.text('Save & Apply Scale'));
      await tester.pumpAndSettle();

      // Verify onSave was triggered with updated scale
      expect(savedScale.isNotEmpty, isTrue);
    });
  });
}
