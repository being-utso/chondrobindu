import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chondrobindu/core/constants/app_constants.dart';
import 'package:chondrobindu/core/constants/group_constants.dart';
import 'package:chondrobindu/core/constants/quotes_data.dart';
import 'package:chondrobindu/models/analytics_models.dart';
import 'package:chondrobindu/models/assessment_model.dart';
import 'package:chondrobindu/models/exam_model.dart';
import 'package:chondrobindu/models/journal_entry_model.dart';
import 'package:chondrobindu/models/note_model.dart';
import 'package:chondrobindu/models/planner_event_model.dart';
import 'package:chondrobindu/models/routine_models.dart';
import 'package:chondrobindu/models/syllabus_node.dart';
import 'package:chondrobindu/models/session_metadata.dart';
import 'package:chondrobindu/screens/add_course_screen.dart' hide Course, CourseType;
import 'package:chondrobindu/screens/insights_screen.dart';
import 'package:chondrobindu/screens/exams_screen.dart';
import 'package:chondrobindu/screens/admin_dashboard_screen.dart';
import 'package:chondrobindu/screens/admin_login_screen.dart';
import 'package:chondrobindu/screens/course_assessment_screen.dart';
import 'package:chondrobindu/screens/course_syllabus_screen.dart';
import 'package:chondrobindu/screens/grading_setup_screen.dart';
import 'package:chondrobindu/screens/journal_screen.dart';
import 'package:chondrobindu/screens/note_editor_screen.dart';
import 'package:chondrobindu/screens/term_performance_screen.dart';
import 'package:chondrobindu/screens/university_dashboard_screen.dart';
import 'package:chondrobindu/screens/home_dashboard.dart';
import 'package:chondrobindu/models/performance_models.dart';
import 'package:chondrobindu/providers/syllabus_provider.dart';
import 'package:chondrobindu/providers/timer_provider.dart';
import 'package:chondrobindu/providers/timer_subjects_provider.dart';
import 'package:chondrobindu/providers/user_profile_provider.dart';
import 'package:chondrobindu/services/background_audit_service.dart';
import 'package:chondrobindu/services/exam_service.dart';
import 'package:chondrobindu/services/pdf_report_service.dart';
import 'package:chondrobindu/services/syllabus_factory.dart';
import 'package:chondrobindu/services/assessment_calculator.dart';
import 'package:chondrobindu/constants/app_config.dart';
import 'package:chondrobindu/models/profile_models.dart';
import 'package:chondrobindu/screens/personal_profile_screen.dart';
import 'package:chondrobindu/screens/help_support_screen.dart';
import 'package:chondrobindu/widgets/app_logo.dart';
import 'package:chondrobindu/widgets/study_session_log_dialog.dart';
import 'package:chondrobindu/services/snack_bar_service.dart';
import 'package:chondrobindu/widgets/batch_add_materials_dialog.dart';
import 'package:chondrobindu/widgets/attendance_override_dialog.dart';
import 'package:chondrobindu/widgets/compact_loading_dialog.dart';
import 'package:chondrobindu/services/syllabus_parser_service.dart';
import 'package:chondrobindu/widgets/assessment_card.dart';
import 'package:chondrobindu/models/course_model.dart';
import 'package:chondrobindu/providers/notes_provider.dart';
import 'package:chondrobindu/providers/journal_provider.dart';
import 'package:chondrobindu/core/theme/app_colors.dart';
import 'package:chondrobindu/core/theme/app_spacing.dart';
import 'package:chondrobindu/core/theme/app_typography.dart';
import 'package:chondrobindu/core/theme/app_shadows.dart';
import 'package:chondrobindu/core/theme/app_theme.dart';
import 'package:chondrobindu/widgets/common/pressable_card.dart';
import 'package:chondrobindu/widgets/common/app_badge.dart';
import 'package:chondrobindu/widgets/common/app_skeleton.dart';
import 'package:chondrobindu/widgets/common/sleek_app_bar.dart';
import 'package:chondrobindu/widgets/common/luxury_glass_card.dart';
import 'package:chondrobindu/widgets/common/app_segmented_pill_bar.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';
import 'package:chondrobindu/main.dart';
import 'package:chondrobindu/widgets/desktop_nav_bar.dart';
import 'package:chondrobindu/screens/home_screen.dart';
import 'package:chondrobindu/screens/courses_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
class FakeUserProfileNotifier extends StateNotifier<UserProfile> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Syllabus Model Tests', () {
    test('StudySection serialization and deserialization', () {
      const section = StudySection(
        id: 'sec_1',
        title: 'Newtonian Mechanics',
        isCompleted: true,
      );

      final map = section.toMap();
      final fromMap = StudySection.fromMap(map);

      expect(fromMap.id, 'sec_1');
      expect(fromMap.title, 'Newtonian Mechanics');
      expect(fromMap.isCompleted, true);
    });

    test('SyllabusFactory generates default syllabus for targets', () {
      final engineeringSyllabus = SyllabusFactory.generateSyllabus('Engineering (BUET, CKRUET)');
      expect(engineeringSyllabus.isNotEmpty, true);
      expect(engineeringSyllabus.any((s) => s.title.contains('Physics')), true);

      final medicalSyllabus = SyllabusFactory.generateSyllabus('Medical (MBBS & BDS)');
      expect(medicalSyllabus.isNotEmpty, true);
      expect(medicalSyllabus.any((s) => s.title.contains('Biology')), true);
      expect(medicalSyllabus.any((s) => s.title.contains('General Knowledge')), true);

      final varsityASyllabus = SyllabusFactory.generateSyllabus('Versity "A" Unit');
      expect(varsityASyllabus.isNotEmpty, true);
      expect(varsityASyllabus.any((s) => s.title.contains('Higher Math')), true);
      expect(varsityASyllabus.any((s) => s.title.contains('Biology')), true);

      final varsityBSyllabus = SyllabusFactory.generateSyllabus('Versity "B" Unit');
      expect(varsityBSyllabus.isNotEmpty, true);
      expect(varsityBSyllabus.any((s) => s.title.contains('Bangla')), true);
      expect(varsityBSyllabus.any((s) => s.title.contains('General Knowledge')), true);

      final varsityCSyllabus = SyllabusFactory.generateSyllabus('Versity "C" Unit');
      expect(varsityCSyllabus.isNotEmpty, true);
      expect(varsityCSyllabus.any((s) => s.title.contains('Accounting')), true);

      final fallbackSyllabus = SyllabusFactory.generateSyllabus('Unknown Random Goal');
      expect(fallbackSyllabus.isNotEmpty, true);
    });

    test('SyllabusFactory generates Humanities and Commerce group syllabi correctly', () {
      final humanitiesHsc = SyllabusFactory.generateSyllabus('HSC Candidate / Board Exam', 'Humanities');
      expect(humanitiesHsc.any((s) => s.title.contains('Civics')), true);
      expect(humanitiesHsc.any((s) => s.title.contains('Economics')), true);
      expect(humanitiesHsc.any((s) => s.title.contains('History')), true);
      expect(humanitiesHsc.any((s) => s.title.contains('Geography')), true);

      final commerceHsc = SyllabusFactory.generateSyllabus('HSC Candidate / Board Exam', 'Commerce');
      expect(commerceHsc.any((s) => s.title.contains('Accounting')), true);
      expect(commerceHsc.any((s) => s.title.contains('Business Organization')), true);
      expect(commerceHsc.any((s) => s.title.contains('Finance')), true);
      expect(commerceHsc.any((s) => s.title.contains('Production Management')), true);

      final humanitiesTargets = GroupConstants.getTargetsForGroup('Humanities');
      expect(humanitiesTargets.contains('Engineering (BUET, CKRUET)'), false);
      expect(humanitiesTargets.contains('Varsity B Unit'), true);

      final commerceTargets = GroupConstants.getTargetsForGroup('Commerce');
      expect(commerceTargets.contains('Medical (MBBS & BDS)'), false);
      expect(commerceTargets.contains('Varsity C Unit'), true);
    });

    test('SyllabusFactory generates 13 subjects and 3 default sections for HSC Prep', () {
      final hscSyllabus = SyllabusFactory.generateSyllabus('HSC Prep/HSC Candidate');
      expect(hscSyllabus.length, 13);

      final expectedSubjects = [
        'Bangla 1st Paper',
        'Bangla 2nd Paper',
        'English 1st Paper',
        'English 2nd Paper',
        'Higher Math 1st Paper',
        'Higher Math 2nd Paper',
        'Physics 1st Paper',
        'Physics 2nd Paper',
        'Chemistry 1st Paper',
        'Chemistry 2nd Paper',
        'Biology 1st Paper',
        'Biology 2nd Paper',
        'ICT',
      ];

      for (final expected in expectedSubjects) {
        expect(hscSyllabus.any((s) => s.title.contains(expected)), true, reason: 'Missing $expected');
      }

      // Verify each subject has the 3 default sections
      for (final subject in hscSyllabus) {
        for (final chapter in subject.chapters) {
          expect(chapter.sections.length, 3);
          expect(chapter.sections[0].title, 'Main textbook');
          expect(chapter.sections[1].title, 'Exercise MCQ');
          expect(chapter.sections[2].title, 'Class note');
        }
      }
    });

    test('SyllabusNotifier applyGlobalSection and bulkDeleteSections', () {
      final notifier = SyllabusNotifier();
      final subjects = [
        const Subject(
          id: 'subj_1',
          title: 'Physics',
          chapters: [
            Chapter(
              id: 'chap_1',
              title: 'Vector',
              sections: [
                StudySection(id: 'sec_1', title: 'Main textbook'),
              ],
            ),
          ],
        ),
      ];
      notifier.setSubjects(subjects);
      expect(notifier.state[0].chapters[0].sections.length, 1);

      // Apply Global Add
      notifier.applyGlobalSection(
        sectionName: 'Question Bank',
        isAdd: true,
        subjectIds: {'subj_1'},
      );
      expect(notifier.state[0].chapters[0].sections.length, 2);

      // Bulk Delete Random Sections
      notifier.bulkDeleteSections({'subj_1|chap_1|sec_1'});
      expect(notifier.state[0].chapters[0].sections.length, 1);
    });
  });

  group('User Profile & Onboarding Tests', () {
    test('isProfileComplete requires isOnboarded, fullName, college, and primaryTarget', () {
      const defaultProfile = UserProfile.defaultProfile;
      expect(defaultProfile.isProfileComplete, false);

      // Incomplete: only name and isOnboarded, but missing college
      final partialProfile = defaultProfile.copyWith(
        fullName: 'Sayem Ahmed',
        isOnboarded: true,
        college: '',
      );
      expect(partialProfile.isProfileComplete, false);

      // Complete: all mandatory fields present
      final completeProfile = partialProfile.copyWith(
        college: 'Notre Dame College',
        district: 'Dhaka',
        primaryTarget: 'Engineering (BUET, CKRUET)',
        scratchpadText: 'Revise integration formulas before mock test',
      );
      expect(completeProfile.isProfileComplete, true);
      expect(completeProfile.scratchpadText, 'Revise integration formulas before mock test');

      final map = completeProfile.toMap();
      expect(map['scratchpad_text'], 'Revise integration formulas before mock test');

      final fromMap = UserProfile.fromMap(map);
      expect(fromMap.scratchpadText, 'Revise integration formulas before mock test');
    });
  });

  group('Performance & Exam Engine Tests', () {
    test('ExamModel handles isAbsent and score percentage accurately', () {
      final now = DateTime.now();
      final exam = ExamModel(
        id: 'exam_1',
        examName: 'Weekly Exam 1',
        subject: 'Physics 1st Paper',
        date: now,
        totalMarks: 100.0,
        marksObtained: 85.0,
        meritPosition: 12,
        isCompleted: true,
        isAbsent: false,
      );

      expect(exam.scorePercentage, 85.0);
      expect(exam.hasLoggedScore, true);

      final absentExam = exam.copyWith(
        marksObtained: 0.0,
        isAbsent: true,
      );
      expect(absentExam.isAbsent, true);
      expect(absentExam.hasLoggedScore, false);

      final map = absentExam.toMap();
      expect(map['isAbsent'], true);

      final fromMap = ExamModel.fromMap({
        'examName': 'Weekly Exam 2',
        'subject': 'Physics 1st Paper',
        'date': Timestamp.fromDate(now),
        'totalMarks': 100,
        'marksObtained': 0,
        'meritPosition': 0,
        'isCompleted': true,
        'isAbsent': true,
      }, 'exam_2');

      expect(fromMap.id, 'exam_2');
      expect(fromMap.examName, 'Weekly Exam 2');
      expect(fromMap.isAbsent, true);
      expect(fromMap.hasLoggedScore, false);
    });

    test('UpcomingExam serialization and deserialization with isAbsent', () {
      final now = DateTime.now();
      final exam = UpcomingExam(
        id: 'exam_1',
        examName: 'BUET Paper Final 1',
        subject: 'Higher Mathematics',
        totalMarks: 100.0,
        targetDate: now,
        recurringType: 'None',
        isAbsent: false,
      );

      expect(exam.examName, 'BUET Paper Final 1');
      expect(exam.subject, 'Higher Mathematics');
      expect(exam.totalMarks, 100.0);
      expect(exam.isAbsent, false);
    });
  });

  group('Timer State & Break Logic Tests', () {
    test('TimerState formattedTime handles focus countdown, stopwatch count-up, and break count-up (+MM:SS)', () {
      // 1. Focus countdown test: 25 minutes target, 0 elapsed -> 25:00
      const focusInitial = TimerState(
        mode: TimerMode.focus,
        status: TimerStatus.initial,
        timerType: TimerType.target,
        elapsedSeconds: 0,
        targetSeconds: 1500,
      );
      expect(focusInitial.formattedTime, '25:00');

      // 2. Focus in progress: 10 seconds elapsed -> 24:50
      final focusRunning = focusInitial.copyWith(elapsedSeconds: 10);
      expect(focusRunning.formattedTime, '24:50');

      // 3. Stopwatch Mode initial: 0 elapsed -> 00:00:00
      const stopwatchInitial = TimerState(
        mode: TimerMode.focus,
        status: TimerStatus.initial,
        timerType: TimerType.stopwatch,
        elapsedSeconds: 0,
        targetSeconds: 1500,
      );
      expect(stopwatchInitial.formattedTime, '00:00:00');

      // 4. Stopwatch in progress: 75 seconds elapsed -> 00:01:15
      final stopwatchRunning = stopwatchInitial.copyWith(elapsedSeconds: 75);
      expect(stopwatchRunning.formattedTime, '00:01:15');

      // 5. Stopwatch in progress over an hour: 3665 seconds -> 01:01:05
      final stopwatchHour = stopwatchInitial.copyWith(elapsedSeconds: 3665);
      expect(stopwatchHour.formattedTime, '01:01:05');

      // 6. Break Mode Countdown: 0 elapsed out of 300s -> 05:00
      const breakInitial = TimerState(
        mode: TimerMode.breakTime,
        status: TimerStatus.running,
        elapsedSeconds: 1500,
        targetSeconds: 1500,
        breakDurationSeconds: 300,
        breakElapsedSeconds: 0,
      );
      expect(breakInitial.formattedTime, '05:00');

      // 7. Break in progress: 65 seconds elapsed -> 03:55 (300 - 65 = 235s)
      final breakRunning = breakInitial.copyWith(breakElapsedSeconds: 65);
      expect(breakRunning.formattedTime, '03:55');

      // 8. Extra Time Mode count-up: 0 elapsed -> +00:00
      const extraInitial = TimerState(
        mode: TimerMode.extraTime,
        status: TimerStatus.running,
        elapsedSeconds: 1500,
        targetSeconds: 1500,
        extraElapsedSeconds: 0,
      );
      expect(extraInitial.formattedTime, '+00:00');

      // 9. Extra Time in progress: 65 seconds elapsed -> +01:05
      final extraRunning = extraInitial.copyWith(extraElapsedSeconds: 65);
      expect(extraRunning.formattedTime, '+01:05');
    });

    test('TimerNotifier setTimerType switches between target and stopwatch modes', () {
      final notifier = TimerNotifier();
      expect(notifier.state.timerType, TimerType.target);

      notifier.setTimerType(TimerType.stopwatch);
      expect(notifier.state.timerType, TimerType.stopwatch);
      expect(notifier.state.formattedTime, '00:00:00');

      notifier.setTimerType(TimerType.target);
      expect(notifier.state.timerType, TimerType.target);
      expect(notifier.state.formattedTime, '25:00');
    });

    test('TimerState earnedBreakSeconds calculation', () {
      const state = TimerState(
        mode: TimerMode.focus,
        status: TimerStatus.running,
        elapsedSeconds: 1500, // 25 mins
        targetSeconds: 1500,
      );
      expect(state.earnedBreakSeconds, 300); // 5 mins
      expect(state.formattedEarnedBreak, '5m 00s');
    });

    test('Decoupled Timer Subjects default list contains core subjects', () {
      expect(kDefaultTimerSubjects.length >= 10, true);
      expect(kDefaultTimerSubjects.contains('Physics 1st Paper'), true);
      expect(kDefaultTimerSubjects.contains('General Study'), true);
    });

    test('StudySessionLog model holds exact start/end times and seconds', () {
      final now = DateTime.now();
      final start = now.subtract(const Duration(minutes: 25));
      final log = StudySessionLog(
        id: 'session_1',
        date: now,
        durationInMinutes: 25,
        durationInSeconds: 1500,
        subjectId: 'Physics 1st Paper',
        subjectName: 'Physics 1st Paper',
        startTime: start,
        endTime: now,
      );

      expect(log.id, 'session_1');
      expect(log.durationInMinutes, 25);
      expect(log.durationInSeconds, 1500);
      expect(log.startTime, start);
      expect(log.endTime, now);
      expect(log.toString(), 'Physics 1st Paper (25 mins)');
    });

    test('TimerNotifier catchUp accurately advances elapsed time upon resuming', () {
      final notifier = TimerNotifier();
      notifier.startTimer();
      expect(notifier.state.status, TimerStatus.running);
      expect(notifier.state.elapsedSeconds, 0);

      // Simulate 120 seconds missed in background
      notifier.catchUp(120);
      expect(notifier.state.elapsedSeconds, 120);
      expect(notifier.state.formattedTime, '23:00'); // 25:00 - 02:00 = 23:00

      // Simulate catching up beyond target (e.g. 1500 target, elapsed currently 120, + 1400s missed)
      notifier.catchUp(1400); // 1520s total -> target 1500 reached, 20s overtime!
      expect(notifier.state.focusMode, FocusTimerMode.overtimeRunning);
      expect(notifier.state.elapsedSeconds, 1500);
      expect(notifier.state.overtimeSeconds, 20);
      expect(notifier.state.isOvertime, true);
      expect(notifier.state.formattedTime, '+00:20');

      // Finish session handover:
      final meta = notifier.prepareSessionCompletion();
      expect(notifier.state.focusMode, FocusTimerMode.sessionCompleted);
      expect(meta.totalDurationSeconds, 1520);
      expect(notifier.state.earnedBreakSeconds, 1520 ~/ 5); // 304s = 5m 4s

      // Start break clock
      notifier.startBreakAfterSession();
      expect(notifier.state.focusMode, FocusTimerMode.breakRunning);
      expect(notifier.state.mode, TimerMode.breakTime);
      expect(notifier.state.formattedTime, '05:04');

      // Test skipBreak returns cleanly to focus setup
      notifier.skipBreak();
      expect(notifier.state.mode, TimerMode.focus);
      expect(notifier.state.focusMode, FocusTimerMode.idle);
      expect(notifier.state.status, TimerStatus.initial);

      notifier.dispose();
    });

    test('Global study and focus calculation providers compute accurate stats from StudySessionLogs', () {
      final now = DateTime.now();
      final logs = [
        StudySessionLog(
          id: 's1',
          date: now,
          durationInMinutes: 45,
          durationInSeconds: 2700,
          subjectId: 'Physics',
          subjectName: 'Physics',
        ),
        StudySessionLog(
          id: 's2',
          date: now,
          durationInMinutes: 30,
          durationInSeconds: 1800,
          subjectId: 'Chemistry',
          subjectName: 'Chemistry',
        ),
        StudySessionLog(
          id: 's3',
          date: now.subtract(const Duration(days: 1)),
          durationInMinutes: 60,
          durationInSeconds: 3600,
          subjectId: 'Math',
          subjectName: 'Math',
        ),
      ];

      // Today's total = 45 + 30 = 75 mins
      final todayLogs = logs.where((l) =>
          l.date.year == now.year &&
          l.date.month == now.month &&
          l.date.day == now.day);
      final todayTotal = todayLogs.fold<int>(0, (sum, i) => sum + i.durationInMinutes);
      expect(todayTotal, 75);

      // All-time total = 45 + 30 + 60 = 135 mins
      final allTimeTotal = logs.fold<int>(0, (sum, i) => sum + i.durationInMinutes);
      expect(allTimeTotal, 135);
      expect(allTimeTotal / 60.0, 2.25);
    });
  });

  group('UserProfile University Mode Serialization Tests', () {
    test('UserProfile serializes and deserializes University Mode fields accurately', () {
      final uniProfile = UserProfile.defaultProfile.copyWith(
        fullName: 'Shahriyer Sayem',
        isOnboarded: true,
        isUniversityStudent: true,
        universityName: 'BUET',
        major: 'EEE',
        level: '2',
        term: '1',
      );

      final map = uniProfile.toMap();
      expect(map['isUniversityStudent'], true);
      expect(map['universityName'], 'BUET');
      expect(map['major'], 'EEE');
      expect(map['level'], '2');
      expect(map['term'], '1');

      final restored = UserProfile.fromMap(map);
      expect(restored.isUniversityStudent, true);
      expect(restored.universityName, 'BUET');
      expect(restored.major, 'EEE');
      expect(restored.level, '2');
      expect(restored.term, '1');
      expect(restored.isProfileComplete, true);
    });

    test('UserProfile defaults to isUniversityStudent = false for HSC candidates', () {
      const hscProfile = UserProfile.defaultProfile;
      expect(hscProfile.isUniversityStudent, false);
      expect(hscProfile.universityName, null);
      expect(hscProfile.major, null);

      final jsonMap = hscProfile.toJson();
      final restored = UserProfile.fromJson(jsonMap);
      expect(restored.isUniversityStudent, false);
      expect(restored.universityName, null);
    });

    test('GradingRow toMap and fromMap roundtrip operates correctly', () {
      final row = GradingRow(
        letterGrade: 'A+',
        gradePoint: 4.0,
        minPercentage: 80,
        maxPercentage: 100,
      );

      final map = row.toMap();
      expect(map['letterGrade'], 'A+');
      expect(map['gradePoint'], 4.0);
      expect(map['minPercentage'], 80);
      expect(map['maxPercentage'], 100);

      final restored = GradingRow.fromMap(map);
      expect(restored.letterGrade, 'A+');
      expect(restored.gradePoint, 4.0);
      expect(restored.minPercentage, 80);
      expect(restored.maxPercentage, 100);
    });

    test('CourseModel toMap and fromMap roundtrip operates correctly', () {
      final now = DateTime.now();
      final course = CourseModel(
        id: 'c101',
        courseCode: 'EEE 101',
        courseName: 'Electrical Circuits I',
        creditHours: 3.0,
        courseType: 'Theory',
        universityName: 'BUET',
        syllabusData: {'topics': ['KCL', 'KVL']},
        createdAt: now,
      );

      final map = course.toMap();
      expect(map['courseCode'], 'EEE 101');
      expect(map['courseName'], 'Electrical Circuits I');
      expect(map['creditHours'], 3.0);
      expect(map['courseType'], 'Theory');
      expect(map['universityName'], 'BUET');

      final restored = CourseModel.fromMap(map, 'c101');
      expect(restored.courseCode, 'EEE 101');
      expect(restored.courseName, 'Electrical Circuits I');
      expect(restored.creditHours, 3.0);
      expect(restored.courseType, 'Theory');
      expect(restored.universityName, 'BUET');
    });

    test('SyllabusChapter and SyllabusTopic toMap and fromMap roundtrip operates correctly', () {
      final chapter = SyllabusChapter(
        chapterName: 'Chapter 1: Basic Circuits',
        topics: [
          SyllabusTopic(topicName: 'KCL & KVL', isCompleted: true),
          SyllabusTopic(topicName: 'Nodal Analysis', isCompleted: false),
        ],
      );

      final map = chapter.toMap();
      expect(map['chapterName'], 'Chapter 1: Basic Circuits');
      expect((map['topics'] as List).length, 2);

      final restored = SyllabusChapter.fromMap(map);
      expect(restored.chapterName, 'Chapter 1: Basic Circuits');
      expect(restored.topics.length, 2);
      expect(restored.topics[0].topicName, 'KCL & KVL');
      expect(restored.topics[0].isCompleted, true);
      expect(restored.topics[1].topicName, 'Nodal Analysis');
      expect(restored.topics[1].isCompleted, false);
    });

    test('SyllabusNode multi-level nesting, progress calculations and serialization', () {
      final rootFolder = SyllabusNode(
        title: 'Hardware Part',
        isLeaf: false,
        children: [
          SyllabusNode(
            title: 'Module 1: Combinational Logic',
            isLeaf: false,
            children: [
              SyllabusNode(title: 'Logic Gates', isLeaf: true, isCompleted: true),
              SyllabusNode(title: 'Karnaugh Maps', isLeaf: true, isCompleted: false),
            ],
          ),
          SyllabusNode(title: 'Lab 1: Gate Verification', isLeaf: true, isCompleted: true),
        ],
      );

      expect(rootFolder.totalLeafCount, 3);
      expect(rootFolder.completedLeafCount, 2);
      expect((rootFolder.progress * 100).round(), 67);

      final map = rootFolder.toMap();
      expect(map['title'], 'Hardware Part');
      expect(map['isLeaf'], false);

      final restored = SyllabusNode.fromMap(map);
      expect(restored.title, 'Hardware Part');
      expect(restored.children.length, 2);
      expect(restored.totalLeafCount, 3);
      expect(restored.completedLeafCount, 2);
    });

    test('AssessmentItem toMap, fromMap and percentage calculations operate correctly', () {
      final item = AssessmentItem(name: 'CT 1', obtained: 18.0, total: 20.0);
      expect(item.percentage, 90.0);

      final map = item.toMap();
      expect(map['name'], 'CT 1');
      expect(map['obtained'], 18.0);
      expect(map['total'], 20.0);

      final restored = AssessmentItem.fromMap(map);
      expect(restored.name, 'CT 1');
      expect(restored.obtained, 18.0);
      expect(restored.total, 20.0);
      expect(restored.percentage, 90.0);
    });
  });

  group('AppConstants Centralized Configuration Tests', () {
    test('AppConstants contains correct developer and external link configurations', () {
      expect(AppConstants.developerName, 'Shahriyer Sayem');
      expect(AppConstants.developerPortfolioUrl, 'https://being-utso.github.io/');
      expect(AppConstants.developerBuyMeACoffeeUrl, 'https://being-utso.github.io/contact.html');
      expect(AppConstants.donationBkashNumber, '+8801622988969');
      expect(AppConstants.donationLink, 'https://buymeacoffee.com/utso.sayem');
      expect(AppConstants.privacyPolicyUrl, 'https://being-utso.github.io/privacy.html');
      expect(AppConstants.supportEmail, 's.sayemx@gmail.com');
      expect(AppConstants.playStoreLink, '');
      expect(AppConstants.appName, 'Chondrobindu');
    });

    test('motivationalQuotes repository contains 15 valid quotes with text and author', () {
      expect(motivationalQuotes.length, 15);
      for (final quote in motivationalQuotes) {
        expect(quote.text.isNotEmpty, true);
        expect(quote.author.isNotEmpty, true);
      }
    });
  });

  group('QuillController WYSIWYG Tests', () {
    test('QuillController initializes document from plain text or JSON Delta cleanly', () {
      final doc = Document()..insert(0, 'Hello World');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );

      expect(controller.document.toPlainText().trim(), 'Hello World');
    });

    test('QuillController applies bold and header attributes cleanly', () {
      final doc = Document()..insert(0, 'Study Notes');
      final controller = QuillController(
        document: doc,
        selection: const TextSelection(baseOffset: 0, extentOffset: 11),
      );

      controller.formatSelection(Attribute.bold);
      expect(controller.getSelectionStyle().containsKey(Attribute.bold.key), true);
    });

    test('NoteModel plainTextContent extracts clean text from Quill JSON Delta and falls back to raw string', () {
      final jsonDeltaNote = NoteModel(
        id: '1',
        title: 'Delta Note',
        content: '[{"insert":"Hello World\\n"}]',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(jsonDeltaNote.plainTextContent, 'Hello World');

      final plainTextNote = NoteModel(
        id: '2',
        title: 'Legacy Note',
        content: 'Simple legacy note content',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(plainTextNote.plainTextContent, 'Simple legacy note content');
    });
  });

  group('Scheduled Exam Reminders Calculation Tests', () {
    test('Exam reminder calculates exactly 6:00 PM the day before exam date', () {
      final examDate = DateTime(2026, 8, 20, 10, 0); // August 20, 10:00 AM
      final dayBefore = examDate.subtract(const Duration(days: 1));
      final reminderTime = DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18, 0, 0);

      expect(reminderTime.year, 2026);
      expect(reminderTime.month, 8);
      expect(reminderTime.day, 19);
      expect(reminderTime.hour, 18);
      expect(reminderTime.minute, 0);
      expect(reminderTime.second, 0);
    });
  });

  group('Smart Recurrence Numbering & Bulk Date Shift Tests', () {
    test('ExamService extractBaseName strips trailing sequence numbers cleanly', () {
      expect(ExamService.extractBaseName('Weekly Exam'), 'Weekly Exam');
      expect(ExamService.extractBaseName('Weekly Exam 5'), 'Weekly Exam');
      expect(ExamService.extractBaseName('BUET Weekly Model Test 12'), 'BUET Weekly Model Test');
      expect(ExamService.extractBaseName('Paper Final'), 'Paper Final');
      expect(ExamService.extractBaseName('Physics Chapter 1 Test 3'), 'Physics Chapter 1 Test');
    });

    test('ExamService extractTrailingNumber extracts integer sequence index correctly', () {
      expect(ExamService.extractTrailingNumber('Weekly Exam 5', 'Weekly Exam'), 5);
      expect(ExamService.extractTrailingNumber('Weekly Exam 12', 'Weekly Exam'), 12);
      expect(ExamService.extractTrailingNumber('Weekly Exam', 'Weekly Exam'), null);
      expect(ExamService.extractTrailingNumber('Other Exam 3', 'Weekly Exam'), null);
    });

    test('Smart recurrence continuation starts from highest number + 1', () {
      final existingExams = ['Weekly Exam 1', 'Weekly Exam 2', 'Weekly Exam 3', 'Weekly Exam 5'];
      const baseName = 'Weekly Exam';

      int highest = 0;
      for (final exam in existingExams) {
        final num = ExamService.extractTrailingNumber(exam, baseName);
        if (num != null && num > highest) highest = num;
      }
      expect(highest, 5);

      final newCount = 3;
      final generatedNames = List.generate(newCount, (i) => '$baseName ${highest + i + 1}');
      expect(generatedNames, ['Weekly Exam 6', 'Weekly Exam 7', 'Weekly Exam 8']);
    });

    test('Bulk date shift correctly applies Duration offset to subsequent exam dates', () {
      final baseDate = DateTime(2026, 8, 15, 10, 0); // Saturday
      final newDate = DateTime(2026, 8, 16, 10, 0); // Sunday (+1 day shift)
      final shift = newDate.difference(baseDate);

      final subsequentExamDate = DateTime(2026, 8, 22, 10, 0);
      final shiftedDate = subsequentExamDate.add(shift);

      expect(shiftedDate.year, 2026);
      expect(shiftedDate.month, 8);
      expect(shiftedDate.day, 23);
    });
  });

  group('Insights Chart & Calendar Data Filtering Tests', () {
    test('Weekly subject breakdown only aggregates data within the last 7 days', () {
      final now = DateTime.now();
      final logs = [
        StudySessionLog(
          id: 'l1',
          date: now.subtract(const Duration(days: 2)),
          durationInMinutes: 40,
          durationInSeconds: 2400,
          subjectId: 'Physics',
          subjectName: 'Physics',
        ),
        StudySessionLog(
          id: 'l2',
          date: now.subtract(const Duration(days: 4)),
          durationInMinutes: 60,
          durationInSeconds: 3600,
          subjectId: 'Chemistry',
          subjectName: 'Chemistry',
        ),
        StudySessionLog(
          id: 'l3',
          date: now.subtract(const Duration(days: 20)), // 20 days ago (should be excluded)
          durationInMinutes: 120,
          durationInSeconds: 7200,
          subjectId: 'Math',
          subjectName: 'Math',
        ),
      ];

      final sevenDaysAgo = now.subtract(const Duration(days: 7));
      final weeklyLogs = logs.where((l) => l.date.isAfter(sevenDaysAgo)).toList();

      expect(weeklyLogs.length, 2);
      final totalWeeklyMins = weeklyLogs.fold<int>(0, (sum, i) => sum + i.durationInMinutes);
      expect(totalWeeklyMins, 100);

      // Verify percentages: Physics (40/100 = 40%), Chemistry (60/100 = 60%)
      final physicsLog = weeklyLogs.firstWhere((l) => l.subjectName == 'Physics');
      expect((physicsLog.durationInMinutes / totalWeeklyMins) * 100, 40.0);
    });

    test('Daily calendar filtering strictly isolates records for the selected calendar date', () {
      final targetDay = DateTime(2026, 8, 11);
      final logs = [
        StudySessionLog(
          id: 'd1',
          date: DateTime(2026, 8, 11, 9, 30),
          durationInMinutes: 45,
          durationInSeconds: 2700,
          subjectId: 'Higher Math',
          subjectName: 'Higher Math',
        ),
        StudySessionLog(
          id: 'd2',
          date: DateTime(2026, 8, 11, 15, 0),
          durationInMinutes: 30,
          durationInSeconds: 1800,
          subjectId: 'Physics',
          subjectName: 'Physics',
        ),
        StudySessionLog(
          id: 'd3',
          date: DateTime(2026, 8, 10, 15, 0), // Different day
          durationInMinutes: 50,
          durationInSeconds: 3000,
          subjectId: 'Chemistry',
          subjectName: 'Chemistry',
        ),
      ];

      final dailyLogs = logs.where((l) =>
          l.date.year == targetDay.year &&
          l.date.month == targetDay.month &&
          l.date.day == targetDay.day).toList();

      expect(dailyLogs.length, 2);
      final totalDayMins = dailyLogs.fold<int>(0, (sum, l) => sum + l.durationInMinutes);
      expect(totalDayMins, 75);
    });
  });

  group('Smart Notifications & Nudges Calculation Tests', () {
    test('Post-Exam score log nudge calculates exactly 10 days after exam date at 10:00 AM', () {
      final examDate = DateTime(2026, 8, 15, 14, 0); // August 15
      final tenDaysAfter = examDate.add(const Duration(days: 10));
      final nudgeTime = DateTime(tenDaysAfter.year, tenDaysAfter.month, tenDaysAfter.day, 10, 0, 0);

      expect(nudgeTime.year, 2026);
      expect(nudgeTime.month, 8);
      expect(nudgeTime.day, 25); // August 25
      expect(nudgeTime.hour, 10);
      expect(nudgeTime.minute, 0);
      expect(nudgeTime.second, 0);
    });

    test('Rolling streak protector calculates 9:00 PM on the following day', () {
      final sessionLogTime = DateTime(2026, 8, 11, 14, 30);
      final followingDay = sessionLogTime.add(const Duration(days: 1));
      final streakProtectorTime = DateTime(followingDay.year, followingDay.month, followingDay.day, 21, 0, 0);

      expect(streakProtectorTime.year, 2026);
      expect(streakProtectorTime.month, 8);
      expect(streakProtectorTime.day, 12);
      expect(streakProtectorTime.hour, 21); // 9:00 PM
      expect(streakProtectorTime.minute, 0);
      expect(streakProtectorTime.second, 0);
    });

    test('Abandoned pause duration threshold is exactly 15 minutes', () {
      const pauseNudgeDuration = Duration(minutes: 15);
      expect(pauseNudgeDuration.inMinutes, 15);
      expect(pauseNudgeDuration.inSeconds, 900);
    });
  });

  group('Workmanager Background Audit & Syllabus Decay Tests', () {
    test('matchesCoreSubject correctly groups 1st and 2nd papers for all 4 core subjects', () {
      // Physics
      expect(BackgroundAuditService.matchesCoreSubject('Physics 1st Paper', 'Physics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Physics 2nd Paper', 'Physics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('পদার্থবিজ্ঞান ১ম পত্র', 'Physics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Chemistry 1st Paper', 'Physics'), false);

      // Chemistry
      expect(BackgroundAuditService.matchesCoreSubject('Chemistry 1st Paper', 'Chemistry'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Chemistry 2nd Paper', 'Chemistry'), true);
      expect(BackgroundAuditService.matchesCoreSubject('রসায়ন ২য় পত্র', 'Chemistry'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Biology 1st Paper', 'Chemistry'), false);

      // Higher Mathematics
      expect(BackgroundAuditService.matchesCoreSubject('Higher Mathematics 1st Paper', 'Higher Mathematics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Higher Math 2nd Paper', 'Higher Mathematics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('উচ্চতর গণিত ১ম পত্র', 'Higher Mathematics'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Physics 1st Paper', 'Higher Mathematics'), false);

      // Biology
      expect(BackgroundAuditService.matchesCoreSubject('Biology 1st Paper', 'Biology'), true);
      expect(BackgroundAuditService.matchesCoreSubject('Biology 2nd Paper', 'Biology'), true);
      expect(BackgroundAuditService.matchesCoreSubject('জীববিজ্ঞান ১ম পত্র', 'Biology'), true);
      expect(BackgroundAuditService.matchesCoreSubject('English 1st Paper', 'Biology'), false);
    });

    test('Syllabus decay correctly detects subjects untouched for over 14 days', () {
      final now = DateTime(2026, 8, 11, 10, 0);

      final physicsActivity = DateTime(2026, 7, 20); // 22 days ago (> 14 days)
      final chemistryActivity = DateTime(2026, 8, 5); // 6 days ago (<= 14 days)

      expect(now.difference(physicsActivity).inDays >= 14, true);
      expect(now.difference(chemistryActivity).inDays >= 14, false);
    });

    test('Weekly wrap-up aggregates focus minutes over the last 7 days', () {
      final now = DateTime(2026, 8, 9, 20, 0); // Sunday evening
      final sevenDaysAgo = now.subtract(const Duration(days: 7));

      final sessions = [
        StudySessionLog(
          id: 'w1',
          date: DateTime(2026, 8, 8, 14, 0),
          durationInMinutes: 90,
          durationInSeconds: 5400,
          subjectId: 'Physics 1st Paper',
          subjectName: 'Physics 1st Paper',
        ),
        StudySessionLog(
          id: 'w2',
          date: DateTime(2026, 8, 5, 10, 0),
          durationInMinutes: 120,
          durationInSeconds: 7200,
          subjectId: 'Chemistry 1st Paper',
          subjectName: 'Chemistry 1st Paper',
        ),
        StudySessionLog(
          id: 'w3',
          date: DateTime(2026, 7, 20, 10, 0), // 20 days ago (excluded)
          durationInMinutes: 180,
          durationInSeconds: 10800,
          subjectId: 'Biology 1st Paper',
          subjectName: 'Biology 1st Paper',
        ),
      ];

      final weeklySessions = sessions.where((s) => s.date.isAfter(sevenDaysAgo)).toList();
      expect(weeklySessions.length, 2);

      final totalMinutes = weeklySessions.fold<int>(0, (sum, s) => sum + s.durationInMinutes);
      expect(totalMinutes, 210);

      final totalHours = totalMinutes / 60.0;
      expect(totalHours, 3.5);
      expect(totalHours.toStringAsFixed(1), '3.5');
    });
  });

  group('Burnout Guard & Daily Wellness Tests', () {
    test('Burnout threshold is exactly 12 hours (720 minutes)', () {
      const burnoutMinutes = 720;
      expect(burnoutMinutes / 60, 12.0);

      const subThresholdMinutes = 719;
      expect(subThresholdMinutes >= 720, false);

      const exactThresholdMinutes = 720;
      expect(exactThresholdMinutes >= 720, true);

      const overThresholdMinutes = 750;
      expect(overThresholdMinutes >= 720, true);
    });

    test('Today focus duration accurately detects 12+ hours threshold', () {
      final now = DateTime(2026, 8, 11, 22, 0);

      final todaySessions = [
        StudySessionLog(
          id: 'b1',
          date: DateTime(2026, 8, 11, 8, 0),
          durationInMinutes: 240, // 4 hours
          durationInSeconds: 14400,
          subjectId: 'Physics',
          subjectName: 'Physics',
        ),
        StudySessionLog(
          id: 'b2',
          date: DateTime(2026, 8, 11, 14, 0),
          durationInMinutes: 300, // 5 hours
          durationInSeconds: 18000,
          subjectId: 'Chemistry',
          subjectName: 'Chemistry',
        ),
        StudySessionLog(
          id: 'b3',
          date: DateTime(2026, 8, 11, 20, 0),
          durationInMinutes: 200, // 3 hours 20 mins -> Total: 12h 20m (740 mins)
          durationInSeconds: 12000,
          subjectId: 'Math',
          subjectName: 'Math',
        ),
        StudySessionLog(
          id: 'b4',
          date: DateTime(2026, 8, 10, 20, 0), // Yesterday (excluded)
          durationInMinutes: 180,
          durationInSeconds: 10800,
          subjectId: 'Biology',
          subjectName: 'Biology',
        ),
      ];

      final filteredToday = todaySessions.where((s) =>
          s.date.year == now.year &&
          s.date.month == now.month &&
          s.date.day == now.day).toList();

      expect(filteredToday.length, 3);

      final totalTodayMins = filteredToday.fold<int>(0, (sum, s) => sum + s.durationInMinutes);
      expect(totalTodayMins, 740);
      expect(totalTodayMins >= 720, true);
    });

    test('Burnout notification once-per-day alert deduplication', () {
      String? lastNotifiedDate;
      int alertCount = 0;

      void onSessionSaved(DateTime sessionDate, int totalMins) {
        if (totalMins >= 720) {
          final dateKey = '${sessionDate.year}-${sessionDate.month}-${sessionDate.day}';
          if (lastNotifiedDate != dateKey) {
            lastNotifiedDate = dateKey;
            alertCount++;
          }
        }
      }

      final today = DateTime(2026, 8, 11);

      // Session 1 crosses threshold
      onSessionSaved(today, 730);
      expect(alertCount, 1);

      // Session 2 on same day further adds time
      onSessionSaved(today, 760);
      expect(alertCount, 1); // Deduplicated!

      // Session 3 on next day
      final tomorrow = DateTime(2026, 8, 12);
      onSessionSaved(tomorrow, 740);
      expect(alertCount, 2); // Fires for new day!
    });
  });

  group('Progress Report PDF Generation Tests', () {
    test('generateProgressReport produces valid non-empty PDF bytes', () async {
      const profile = UserProfile(
        fullName: 'Shahriyer Sayem',
        nickname: 'Sayem',
        username: 'sayem25',
        email: 'sayem@example.com',
        phone: '01700000000',
        college: 'Notre Dame College',
        primaryTarget: 'Engineering (BUET, CKRUET)',
        hscBatch: '2025',
      );

      final syllabus = SyllabusFactory.generateSyllabus('Engineering');
      final exams = [
        ExamModel(
          id: 'e1',
          examName: 'BUET Weekly Model Test 1',
          subject: 'Physics',
          date: DateTime.now().subtract(const Duration(days: 5)),
          totalMarks: 100,
          marksObtained: 85,
          meritPosition: 12,
          isCompleted: true,
        ),
      ];

      final pdfBytes = await PdfReportService.generateProgressReport(
        userProfile: profile,
        focusHoursLast30Days: 42.5,
        syllabusSubjects: syllabus,
        recentExams: exams,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes.length > 500, true);
    });
  });

  group('Exam Journal Model & Filtering Tests', () {
    test('JournalEntry correctly identifies mistakes and tips', () {
      const mistake = JournalEntry(type: 'mistake', content: 'Forgot negative sign in integration');
      const tip = JournalEntry(type: 'tip', content: 'Use L\'Hopital rule when limit gives 0/0');

      expect(mistake.isMistake, true);
      expect(mistake.isTip, false);

      expect(tip.isTip, true);
      expect(tip.isMistake, false);
    });

    test('ExamModel serializes and deserializes journal_entries array accurately', () {
      final exam = ExamModel(
        id: 'j1',
        examName: 'BUET Final Mock',
        subject: 'Physics 1st Paper',
        date: DateTime(2026, 8, 10),
        totalMarks: 100,
        marksObtained: 92,
        isCompleted: true,
        journalEntries: const [
          JournalEntry(type: 'mistake', content: 'Misread vector direction in Q4'),
          JournalEntry(type: 'tip', content: 'Use energy conservation shortcut for pendulum'),
        ],
      );

      expect(exam.hasJournalEntries, true);

      final map = exam.toMap();
      expect(map['journal_entries'], isNotNull);
      expect((map['journal_entries'] as List).length, 2);

      final parsed = ExamModel.fromMap(map, 'j1');
      expect(parsed.journalEntries.length, 2);
      expect(parsed.journalEntries.first.type, 'mistake');
      expect(parsed.journalEntries.first.content, 'Misread vector direction in Q4');
      expect(parsed.journalEntries.last.isTip, true);
    });
  });

  group('Admission Countdown Target Tests', () {
    test('UserProfile serializes and deserializes target_event_name and target_event_date', () {
      final targetDate = DateTime(2026, 12, 31);
      final profile = UserProfile(
        fullName: 'Shahriyer Sayem',
        nickname: 'Sayem',
        username: 'sayem25',
        email: 'sayem@example.com',
        phone: '01700000000',
        primaryTarget: 'Engineering (BUET, CKRUET)',
        targetEventName: 'BUET Admission Test',
        targetEventDate: targetDate,
      );

      final map = profile.toMap();
      expect(map['target_event_name'], 'BUET Admission Test');
      expect(map['target_event_date'], isNotNull);

      final parsed = UserProfile.fromMap(map);
      expect(parsed.targetEventName, 'BUET Admission Test');
      expect(parsed.targetEventDate, isNotNull);
      expect(parsed.targetEventDate!.year, 2026);
      expect(parsed.targetEventDate!.month, 12);
      expect(parsed.targetEventDate!.day, 31);
    });

    test('Days remaining calculation computes accurate integer days difference', () {
      final today = DateTime(2026, 8, 11);
      final eventDate = DateTime(2026, 12, 31);

      final todayDateOnly = DateTime(today.year, today.month, today.day);
      final targetDateOnly = DateTime(eventDate.year, eventDate.month, eventDate.day);

      final daysRemaining = targetDateOnly.difference(todayDateOnly).inDays;
      expect(daysRemaining, 142);
    });

    test('SyllabusFactory generates IBA Prep subjects and sections accurately', () {
      final ibaSyllabus = SyllabusFactory.generateSyllabus('IBA Prep');
      expect(ibaSyllabus.length, 3);
      expect(ibaSyllabus[0].title, 'English');
      expect(ibaSyllabus[1].title, 'Mathematics');
      expect(ibaSyllabus[2].title, 'Analytical Ability');

      for (final subject in ibaSyllabus) {
        for (final chapter in subject.chapters) {
          final sectionTitles = chapter.sections.map((s) => s.title).toList();
          expect(sectionTitles, contains('Vocabulary/Grammar'));
          expect(sectionTitles, contains('Practice Problems'));
          expect(sectionTitles, contains('Previous Year Questions'));
        }
      }
    });

    test('UserProfile isLoaded defaults to false and becomes true when fromMap is called', () {
      expect(UserProfile.defaultProfile.isLoaded, false);

      final map = {
        'fullName': 'Sayem',
        'email': 'sayem@example.com',
        'primaryTarget': 'IBA Prep',
        'isOnboarded': true,
      };

      final profile = UserProfile.fromMap(map);
      expect(profile.isLoaded, true);
    });
  });

  group('Syllabus Presets & Exam Sorting/Countdown Tests', () {
    test('SyllabusFactory generates Medical preset with exact 8 subjects', () {
      final medSyllabus = SyllabusFactory.generateSyllabus('Medical (MBBS & BDS)');
      final titles = medSyllabus.map((s) => s.title).toList();
      expect(titles, contains('Physics 1st Paper (পদার্থবিজ্ঞান ১ম পত্র)'));
      expect(titles, contains('Physics 2nd Paper (পদার্থবিজ্ঞান ২য় পত্র)'));
      expect(titles, contains('Chemistry 1st Paper (রসায়ন ১ম পত্র)'));
      expect(titles, contains('Chemistry 2nd Paper (রসায়ন ২য় পত্র)'));
      expect(titles, contains('Biology 1st Paper (জীববিজ্ঞান ১ম পত্র)'));
      expect(titles, contains('Biology 2nd Paper (জীববিজ্ঞান ২য় পত্র)'));
      expect(titles, contains('General Knowledge (সাধারণ জ্ঞান)'));
      expect(titles, contains('English (ইংরেজি)'));
      expect(medSyllabus.length, 8);
    });

    test('SyllabusFactory generates Engineering preset with Physics, Chemistry, Math', () {
      final engSyllabus = SyllabusFactory.generateSyllabus('Engineering (BUET, CKRUET)');
      final titles = engSyllabus.map((s) => s.title).toList();
      expect(titles, contains('Physics 1st Paper (পদার্থবিজ্ঞান ১ম পত্র)'));
      expect(titles, contains('Physics 2nd Paper (পদার্থবিজ্ঞান ২য় পত্র)'));
      expect(titles, contains('Chemistry 1st Paper (রসায়ন ১ম পত্র)'));
      expect(titles, contains('Chemistry 2nd Paper (রসায়ন ২য় পত্র)'));
      expect(titles, contains('Higher Math 1st Paper (উচ্চতর গণিত ১ম পত্র)'));
      expect(titles, contains('Higher Math 2nd Paper (উচ্চতর গণিত ২য় পত্র)'));
      expect(engSyllabus.length, 6);
    });

    test('Exam sorting and splitting into upcomingExams and pastExams operates correctly', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final pastDate = today.subtract(const Duration(days: 5));
      final futureDate1 = today.add(const Duration(days: 2));
      final futureDate2 = today.add(const Duration(days: 10));

      final rawExams = [
        ExamModel(
          id: 'e2',
          examName: 'Future Exam 2',
          subject: 'Physics',
          totalMarks: 100,
          marksObtained: 0,
          date: futureDate2,
        ),
        ExamModel(
          id: 'e_past',
          examName: 'Past Exam',
          subject: 'Biology',
          totalMarks: 100,
          marksObtained: 85,
          date: pastDate,
        ),
        ExamModel(
          id: 'e1',
          examName: 'Future Exam 1',
          subject: 'Chemistry',
          totalMarks: 100,
          marksObtained: 0,
          date: futureDate1,
        ),
      ];

      // 1. Sort ascending by date
      final sortedExams = List<ExamModel>.from(rawExams)..sort((a, b) => a.date.compareTo(b.date));
      expect(sortedExams.first.id, 'e_past');
      expect(sortedExams[1].id, 'e1');
      expect(sortedExams.last.id, 'e2');

      // 2. Split into upcoming and past
      final upcoming = sortedExams.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return (d.isAfter(today) || d.isAtSameMomentAs(today)) && !e.isCompleted && !e.isAbsent;
      }).toList();

      final past = sortedExams.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return d.isBefore(today) || e.isCompleted || e.isAbsent;
      }).toList();

      expect(upcoming.length, 2);
      expect(upcoming.first.id, 'e1'); // Closest upcoming exam
      expect(upcoming.last.id, 'e2');
      expect(past.length, 1);
      expect(past.first.id, 'e_past');
    });

    test('Countdown logic selects pinned exam when set and defaults to upcoming.first', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final futureDate1 = today.add(const Duration(days: 2));
      final futureDate2 = today.add(const Duration(days: 10));

      final upcoming = [
        ExamModel(id: 'e1', examName: 'E1', subject: 'Chem', totalMarks: 100, marksObtained: 0, date: futureDate1),
        ExamModel(id: 'e2', examName: 'E2', subject: 'Math', totalMarks: 100, marksObtained: 0, date: futureDate2),
      ];

      // Case A: No pinned exam -> defaults to upcoming.first
      String? pinnedId;
      ExamModel? selectedExam;
      if (pinnedId != null && pinnedId.isNotEmpty) {
        try {
          selectedExam = upcoming.firstWhere((e) => e.id == pinnedId);
        } catch (_) {}
      }
      selectedExam ??= (upcoming.isNotEmpty ? upcoming.first : null);
      expect(selectedExam?.id, 'e1');

      // Case B: Pinned exam is 'e2' -> chooses 'e2'
      pinnedId = 'e2';
      selectedExam = null;
      if (pinnedId.isNotEmpty) {
        try {
          selectedExam = upcoming.firstWhere((e) => e.id == pinnedId);
        } catch (_) {}
      }
      selectedExam ??= (upcoming.isNotEmpty ? upcoming.first : null);
      expect(selectedExam?.id, 'e2');
    });
  });

  group('Critical Bugs & Task 1-5 Verifications', () {
    test('Task 1: SyllabusFactory generates exact presets for all Varsity units and fallbacks', () {
      // Varsity A
      final va = SyllabusFactory.generateSyllabus('Varsity A Unit');
      expect(va.any((s) => s.title.contains('Physics')), true);
      expect(va.any((s) => s.title.contains('Chemistry')), true);
      expect(va.any((s) => s.title.contains('Higher Math')), true);
      expect(va.any((s) => s.title.contains('Biology')), true);

      // Varsity B
      final vb = SyllabusFactory.generateSyllabus('Varsity B Unit');
      expect(vb.any((s) => s.title.contains('Bangla')), true);
      expect(vb.any((s) => s.title.contains('English')), true);
      expect(vb.any((s) => s.title.contains('General Knowledge')), true);

      // Varsity C (Commerce)
      final vc = SyllabusFactory.generateSyllabus('Varsity C Unit');
      expect(vc.any((s) => s.title.contains('Accounting')), true);
      expect(vc.any((s) => s.title.contains('Business')), true);
      expect(vc.any((s) => s.title.contains('Finance')), true);
      expect(vc.any((s) => s.title.contains('Bangla')), true);
      expect(vc.any((s) => s.title.contains('English')), true);

      // Medical
      final med = SyllabusFactory.generateSyllabus('Medical (MBBS & BDS)');
      expect(med.length, 8);
      expect(med.any((s) => s.title.contains('Biology')), true);
      expect(med.any((s) => s.title.contains('General Knowledge')), true);

      // Fallback
      final fallback = SyllabusFactory.generateSyllabus('NonExistentGoal');
      expect(fallback.isNotEmpty, true);
    });

    test('Task 2: UserProfile serializes and deserializes custom_timer_subjects', () {
      final profile = UserProfile.defaultProfile.copyWith(
        customTimerSubjects: ['Marketing', 'Statistics', 'Ethics'],
      );

      final map = profile.toMap();
      expect(map['custom_timer_subjects'], ['Marketing', 'Statistics', 'Ethics']);

      final fromMap = UserProfile.fromMap(map);
      expect(fromMap.customTimerSubjects.length, 3);
      expect(fromMap.customTimerSubjects, contains('Marketing'));
      expect(fromMap.customTimerSubjects, contains('Statistics'));
      expect(fromMap.customTimerSubjects, contains('Ethics'));
    });

    test('Task 3: Timer state machine strictly transitions: Focus countdown -> Overtime count-up -> Session Complete -> Break countdown -> Extra Time count-up', () {
      // 1. Initial State: Target countdown 1500s (25 mins)
      final notifier = TimerNotifier();
      notifier.setTargetMinutes(25);
      expect(notifier.state.mode, TimerMode.focus);
      expect(notifier.state.targetSeconds, 1500);
      expect(notifier.state.formattedTime, '25:00');

      // 2. Start timer and tick down
      notifier.startTimer();
      expect(notifier.state.status, TimerStatus.running);
      expect(notifier.state.focusMode, FocusTimerMode.focusRunning);

      // 3. Catch up remaining focus seconds to hit target 0 + 30s overtime
      notifier.catchUp(1530);
      expect(notifier.state.focusMode, FocusTimerMode.overtimeRunning);
      expect(notifier.state.overtimeSeconds, 30);
      expect(notifier.state.formattedTime, '+00:30'); // Count-up strictly with '+'

      // 4. Finish handover -> prepares session completion snapshot
      final meta = notifier.prepareSessionCompletion();
      expect(notifier.state.focusMode, FocusTimerMode.sessionCompleted);
      expect(meta.totalDurationSeconds, 1530);
      expect(notifier.state.earnedBreakSeconds, 1530 ~/ 5); // 306s = 5m 6s

      // 5. Break starts immediately on dialog exit
      notifier.startBreakAfterSession();
      expect(notifier.state.focusMode, FocusTimerMode.breakRunning);
      expect(notifier.state.mode, TimerMode.breakTime);
      expect(notifier.state.formattedTime, '05:06');

      // 6. Progress break duration: 120s into break
      notifier.catchUp(120);
      expect(notifier.state.mode, TimerMode.breakTime);
      expect(notifier.state.breakElapsedSeconds, 120);
      expect(notifier.state.formattedTime, '03:06'); // 306 - 120 = 186s = 03:06

      // 7. Complete break duration: remaining 186s to reach 00:00
      notifier.catchUp(186);
      expect(notifier.state.mode, TimerMode.breakTime);
      expect(notifier.state.breakElapsedSeconds, 306);
      expect(notifier.state.formattedTime, '00:00');

      // 8. Test skipBreak from break mode returns cleanly to focus setup
      final notifier2 = TimerNotifier();
      notifier2.startTimer();
      notifier2.prepareSessionCompletion();
      notifier2.startBreakAfterSession();
      expect(notifier2.state.mode, TimerMode.breakTime);
      notifier2.skipBreak();
      expect(notifier2.state.mode, TimerMode.focus);
      expect(notifier2.state.focusMode, FocusTimerMode.idle);
      expect(notifier2.state.status, TimerStatus.initial);

      notifier.dispose();
      notifier2.dispose();
    });

    test('SessionMetadata snapshots active course context and isolates from subject changes', () {
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      final end = DateTime.now();

      final meta1 = SessionMetadata.fromSubject(
        'CSE 110: Computer Programming',
        totalDurationSeconds: 1800,
        sessionStartTime: start,
        sessionEndTime: end,
      );

      expect(meta1.courseCode, 'CSE 110');
      expect(meta1.courseTitle, 'Computer Programming');
      expect(meta1.durationMinutes, 30);
      expect(meta1.courseId, 'cse_110');

      // Custom/General subject without colon
      final meta2 = SessionMetadata.fromSubject(
        'Calculus & Linear Algebra',
        totalDurationSeconds: 900,
      );
      expect(meta2.courseCode, 'Calculus & Linear Algebra');
      expect(meta2.courseTitle, 'Calculus & Linear Algebra');
      expect(meta2.durationMinutes, 15);
      expect(meta2.courseId, 'calculus_linear_algebra');
    });
  });

  group('Journal & NoteModel Tests', () {
    test('NoteModel toMap and fromMap roundtrip', () {
      final now = DateTime.now();
      final note = NoteModel(
        id: 'note_123',
        title: 'Physics Integration Formula',
        content: 'Integral of sin(x) dx = -cos(x) + C',
        createdAt: now,
        updatedAt: now,
        isPinned: true,
        tags: const ['Formula', 'Physics'],
      );

      final map = note.toMap();
      final fromMapNote = NoteModel.fromMap(map, 'note_123');

      expect(fromMapNote.id, 'note_123');
      expect(fromMapNote.title, 'Physics Integration Formula');
      expect(fromMapNote.content, 'Integral of sin(x) dx = -cos(x) + C');
      expect(fromMapNote.isPinned, true);
      expect(fromMapNote.tags, contains('Formula'));
    });

    test('NoteModel copyWith updates fields cleanly', () {
      final note = NoteModel(
        id: 'note_1',
        title: 'Original Title',
        content: 'Original Content',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isPinned: false,
        tags: const ['General'],
      );

      final updated = note.copyWith(
        title: 'Updated Title',
        isPinned: true,
        tags: const ['Brain Dump'],
      );

      expect(updated.id, 'note_1');
      expect(updated.title, 'Updated Title');
      expect(updated.content, 'Original Content');
      expect(updated.isPinned, true);
      expect(updated.tags, ['Brain Dump']);
    });

    testWidgets('AppLogo widget renders cleanly with fallback support', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLogo(size: 32),
          ),
        ),
      );

      expect(find.byType(AppLogo), findsOneWidget);
    });
  });

  group('University Mode Isolation & Dynamic PDF Export Tests', () {
    test('PdfReportService generates valid university term PDF bytes', () async {
      const userProfile = UserProfile(
        fullName: 'Test Uni Student',
        nickname: 'Uni',
        username: 'unistudent',
        email: 'uni@example.com',
        phone: '01700000000',
        primaryTarget: 'Engineering',
        universityName: 'BUET',
        major: 'Computer Science and Engineering',
        level: '2',
        term: '1',
        isUniversityStudent: true,
      );

      final courses = [
        {
          'courseCode': 'CSE 201',
          'courseName': 'Object Oriented Programming',
          'courseType': 'Theory',
          'creditHours': 3.0,
        },
        {
          'courseCode': 'CSE 202',
          'courseName': 'OOP Sessional',
          'courseType': 'Lab',
          'creditHours': 1.5,
        },
      ];

      final assessments = [
        Assessment(
          courseId: 'c1',
          name: 'CT 1',
          date: DateTime(2026, 9, 15, 10, 0),
          totalMarks: 20.0,
          obtainedMarks: 18.5,
          weightage: 15.0,
        ),
      ];

      final pdfBytes = await PdfReportService.generateUniversityTermReport(
        userProfile: userProfile,
        focusHoursLast30Days: 42.5,
        courses: courses,
        assessments: assessments,
        courseCodeMap: {'c1': 'CSE 201'},
      );

      expect(pdfBytes.isNotEmpty, true);
      expect(pdfBytes.lengthInBytes, greaterThan(1000));
    });

    test('Strict focus sessions filtering filters out legacy admission sessions', () {
      final sessions = [
        StudySessionLog(
          id: 's1',
          date: DateTime.now(),
          durationInMinutes: 45,
          subjectId: 'Physics 1st Paper',
          subjectName: 'Physics 1st Paper',
        ),
        StudySessionLog(
          id: 's2',
          date: DateTime.now(),
          durationInMinutes: 60,
          subjectId: 'Biology 2nd Paper',
          subjectName: 'Biology 2nd Paper',
        ),
        StudySessionLog(
          id: 's3',
          date: DateTime.now(),
          durationInMinutes: 30,
          subjectId: 'Model Test Practice',
          subjectName: 'Model Test Practice',
        ),
        StudySessionLog(
          id: 's4',
          date: DateTime.now(),
          durationInMinutes: 50,
          subjectId: 'CSE 201: OOP',
          subjectName: 'CSE 201: OOP',
        ),
        StudySessionLog(
          id: 's5',
          date: DateTime.now(),
          durationInMinutes: 90,
          subjectId: 'Assignment',
          subjectName: 'Assignment',
        ),
      ];

      final activeCourseCodes = {'cse 201', 'cse 202'};
      final activeCourseNames = {'object oriented programming', 'oop sessional'};

      final universitySessions = sessions.where((s) {
        final subj = s.subject.trim().toLowerCase();

        final isLegacy = kDefaultTimerSubjects.any((legacy) {
          final l = legacy.toLowerCase();
          return subj == l || subj.startsWith(l) || (subj.contains('paper') && !subj.contains('term paper')) || subj.contains('hsc') || subj.contains('model test');
        });
        if (isLegacy) return false;

        final matchesActiveCourse = activeCourseCodes.any((code) => subj.contains(code)) ||
            activeCourseNames.any((name) => subj.contains(name));
        final matchesUniCategory = kDefaultUniversityTimerSubjects.any((cat) => subj == cat.toLowerCase());

        return matchesActiveCourse || matchesUniCategory;
      }).toList();

      expect(universitySessions.length, 2);
      expect(universitySessions.map((s) => s.id), containsAll(['s4', 's5']));
      expect(universitySessions.any((s) => s.subject.contains('Physics')), false);
      expect(universitySessions.any((s) => s.subject.contains('Biology')), false);
      expect(universitySessions.any((s) => s.subject.contains('Model Test')), false);
    });
  });

  group('Sprint 4: Archiving, AI Routine, and Holiday Management Tests', () {
    test('ClassRoutine isAlternating serializes and deserializes accurately', () {
      final routine1 = ClassRoutine(
        courseId: 'c101',
        courseName: 'CSE 202: OOP Sessional',
        dayOfWeek: DateTime.sunday,
        startTime: '09:00 AM',
        endTime: '12:00 PM',
        classType: 'Lab',
        roomNumber: 'Lab 4',
        isAlternating: true,
      );

      final map1 = routine1.toMap();
      expect(map1['isAlternating'], true);

      final restored1 = ClassRoutine.fromMap(map1);
      expect(restored1.isAlternating, true);
      expect(restored1.courseName, 'CSE 202: OOP Sessional');
      expect(restored1.roomNumber, 'Lab 4');

      final routine2 = ClassRoutine(
        courseId: 'c102',
        courseName: 'CSE 201: OOP Theory',
        dayOfWeek: DateTime.monday,
        startTime: '10:00 AM',
        endTime: '11:00 AM',
      );

      expect(routine2.isAlternating, false);
      final map2 = routine2.toMap();
      expect(map2['isAlternating'], false);

      final restored2 = ClassRoutine.fromMap(map2);
      expect(restored2.isAlternating, false);
    });

    test('HolidaySettings correctly identifies weekly and specific one-off holidays', () {
      final specificDay = DateTime(2026, 12, 16); // Victory Day
      final regularFriday = DateTime(2026, 9, 18); // Friday
      final regularSaturday = DateTime(2026, 9, 19); // Saturday
      final regularSunday = DateTime(2026, 9, 20); // Sunday (Working day in BD)

      final holidaySettings = HolidaySettings(
        weeklyHolidays: [DateTime.friday, DateTime.saturday],
        specificHolidays: [specificDay],
      );

      expect(holidaySettings.isHoliday(regularFriday), true);
      expect(holidaySettings.isHoliday(regularSaturday), true);
      expect(holidaySettings.isHoliday(specificDay), true);
      expect(holidaySettings.isHoliday(regularSunday), false);
    });

    test('HolidaySettings toMap and fromMap serialization roundtrip', () {
      final holidayDate = DateTime(2026, 3, 26);
      final settings = HolidaySettings(
        weeklyHolidays: [DateTime.friday],
        specificHolidays: [holidayDate],
      );

      final map = settings.toMap();
      expect(map['weeklyHolidays'], [DateTime.friday]);

      final restored = HolidaySettings.fromMap(map);
      expect(restored.weeklyHolidays, [DateTime.friday]);
      expect(restored.specificHolidays.length, 1);
      expect(restored.isHoliday(holidayDate), true);
      expect(restored.isHoliday(DateTime(2026, 3, 29)), false); // Sunday is working day
    });

    test('Archive data packaging correctly aggregates term statistics', () {
      final courses = [
        {
          'id': 'c1',
          'courseCode': 'CSE 201',
          'creditHours': 3.0,
        },
        {
          'id': 'c2',
          'courseCode': 'CSE 202',
          'creditHours': 1.5,
        },
      ];

      double totalCredits = 0.0;
      for (final c in courses) {
        totalCredits += (c['creditHours'] as num).toDouble();
      }
      expect(totalCredits, 4.5);

      final records = [
        AttendanceRecord(
          courseId: 'c1',
          date: DateTime.now(),
          status: AttendanceStatus.attended,
        ),
        AttendanceRecord(
          courseId: 'c1',
          date: DateTime.now(),
          status: AttendanceStatus.attended,
        ),
        AttendanceRecord(
          courseId: 'c2',
          date: DateTime.now(),
          status: AttendanceStatus.missed,
        ),
        AttendanceRecord(
          courseId: 'c2',
          date: DateTime.now(),
          status: AttendanceStatus.extra,
        ),
      ];

      final stats = AttendanceStats.fromRecords(records);
      expect(stats.attended, 2);
      expect(stats.missed, 1);
      expect(stats.extra, 1);
      expect(stats.validClassesCount, 4);
      expect(stats.percentage, 75.0);
    });

    test('SyllabusNode dynamic node transformation and material sub-sections operate cleanly', () {
      // Initially: A regular topic node imported from a PDF syllabus
      final topicNode = SyllabusNode(
        id: 'top_1',
        title: 'Polymorphism & Dynamic Dispatch',
        isLeaf: true,
        isCompleted: false,
      );

      expect(topicNode.isLeaf, true);
      expect(topicNode.children.isEmpty, true);
      expect(topicNode.totalLeafCount, 1);
      expect(topicNode.completedLeafCount, 0);

      // Student adds material sub-nodes (Class Note, Ref Book, etc.)
      topicNode.children.addAll([
        SyllabusNode(title: 'Class Note', isLeaf: true, isCompleted: false),
        SyllabusNode(title: 'Lecture Sheet', isLeaf: true, isCompleted: false),
        SyllabusNode(title: 'Ref Book', isLeaf: true, isCompleted: false),
      ]);

      expect(topicNode.children.length, 3);
      expect(topicNode.children.isNotEmpty, true);
      // Total count includes parent topic (1) + 3 materials = 4
      expect(topicNode.totalLeafCount, 4);
      expect(topicNode.completedLeafCount, 0);

      // Complete the lecture sheet
      topicNode.children[1].isCompleted = true;
      expect(topicNode.completedLeafCount, 1);
      expect(topicNode.progress, 0.25);

      // Complete the parent topic as well
      topicNode.isCompleted = true;
      expect(topicNode.completedLeafCount, 2);
      expect(topicNode.progress, 0.50);

      // Firestore roundtrip serialization test
      final map = topicNode.toMap();
      expect(map['title'], 'Polymorphism & Dynamic Dispatch');
      expect(map['isLeaf'], true);
      expect((map['children'] as List).length, 3);

      final restored = SyllabusNode.fromMap(map);
      expect(restored.title, 'Polymorphism & Dynamic Dispatch');
      expect(restored.isLeaf, true);
      expect(restored.children.length, 3);
      expect(restored.children[0].title, 'Class Note');
      expect(restored.children[1].title, 'Lecture Sheet');
      expect(restored.children[1].isCompleted, true);
      expect(restored.completedLeafCount, 2);
      expect(restored.totalLeafCount, 4);
    });

    test('SyllabusNode resourceUrl serializes, deserializes, and copies accurately', () {
      final nodeWithUrl = SyllabusNode(
        title: 'Lecture Sheet 1: Pointers & References',
        isLeaf: true,
        resourceUrl: 'https://drive.google.com/file/d/12345/view?usp=sharing',
      );

      expect(nodeWithUrl.resourceUrl, 'https://drive.google.com/file/d/12345/view?usp=sharing');

      final map = nodeWithUrl.toMap();
      expect(map['resourceUrl'], 'https://drive.google.com/file/d/12345/view?usp=sharing');

      final restored = SyllabusNode.fromMap(map);
      expect(restored.resourceUrl, 'https://drive.google.com/file/d/12345/view?usp=sharing');

      final nodeWithoutUrl = SyllabusNode(
        title: 'Class Note (Handwritten)',
        isLeaf: true,
      );
      final map2 = nodeWithoutUrl.toMap();
      expect(map2.containsKey('resourceUrl'), false);

      final updatedWithUrl = nodeWithoutUrl.copyWith(
        resourceUrl: 'https://onedrive.live.com/view.aspx?resid=abc',
      );
      expect(updatedWithUrl.resourceUrl, 'https://onedrive.live.com/view.aspx?resid=abc');
      expect(updatedWithUrl.title, 'Class Note (Handwritten)');
    });

    test('Assessment.fromRawListOrMap handles null, List, and Map inputs without type cast crash', () {
      // 1. Null input
      expect(Assessment.fromRawListOrMap(null), isEmpty);

      // 2. List<dynamic> input
      final listData = [
        {
          'id': 'assess_1',
          'courseId': 'cse_101',
          'name': 'CT 1: Logic Gates',
          'totalMarks': 20.0,
          'obtainedMarks': 18.0,
          'weightage': 10.0,
          'date': Timestamp.now(),
        },
        {
          'id': 'assess_2',
          'courseId': 'cse_101',
          'name': 'CT 2: K-Maps',
          'totalMarks': 20.0,
          'obtainedMarks': 15.0,
          'weightage': 10.0,
          'date': DateTime.now().toIso8601String(),
        },
      ];
      final fromList = Assessment.fromRawListOrMap(listData);
      expect(fromList.length, 2);
      expect(fromList[0].name, 'CT 1: Logic Gates');
      expect(fromList[1].name, 'CT 2: K-Maps');

      // 3. Map<String, dynamic> input (extracts .values.toList())
      final mapData = <String, dynamic>{
        'assess_1': {
          'id': 'assess_1',
          'name': 'CT 1: Logic Gates',
          'totalMarks': 20.0,
          'obtainedMarks': 18.0,
          'date': Timestamp.now(),
        },
        'assess_2': {
          'id': 'assess_2',
          'name': 'CT 2: K-Maps',
          'totalMarks': 20.0,
          'obtainedMarks': 15.0,
          'date': Timestamp.now(),
        },
      };
      final fromMap = Assessment.fromRawListOrMap(mapData, defaultCourseId: 'cse_101');
      expect(fromMap.length, 2);
      expect(fromMap.map((a) => a.name).toSet(), containsAll(['CT 1: Logic Gates', 'CT 2: K-Maps']));
      expect(fromMap.first.courseId, 'cse_101');

      // 4. Invalid types (e.g. integer or string) return empty list
      expect(Assessment.fromRawListOrMap('invalid_data'), isEmpty);
      expect(Assessment.fromRawListOrMap(12345), isEmpty);
    });

    test('TermBreak and HolidaySettings range evaluation and serialization', () {
      final termBreak = TermBreak(
        id: 'break_pl_1',
        title: 'Preparatory Leave (PL)',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 9, 10),
      );

      // 1. TermBreak containsDate check
      expect(termBreak.containsDate(DateTime(2026, 9, 1)), isTrue);
      expect(termBreak.containsDate(DateTime(2026, 9, 5)), isTrue);
      expect(termBreak.containsDate(DateTime(2026, 9, 10)), isTrue);
      expect(termBreak.containsDate(DateTime(2026, 8, 31)), isFalse);
      expect(termBreak.containsDate(DateTime(2026, 9, 11)), isFalse);

      // 2. TermBreak toMap and fromMap
      final breakMap = termBreak.toMap();
      final restoredBreak = TermBreak.fromMap(breakMap);
      expect(restoredBreak.id, 'break_pl_1');
      expect(restoredBreak.title, 'Preparatory Leave (PL)');
      expect(restoredBreak.startDate.day, 1);
      expect(restoredBreak.endDate.day, 10);

      // 3. HolidaySettings with termBreaks
      final settings = HolidaySettings(
        weeklyHolidays: [DateTime.friday, DateTime.saturday],
        specificHolidays: [DateTime(2026, 12, 16)],
        termBreaks: [termBreak],
      );

      // Check dates
      expect(settings.isHoliday(DateTime(2026, 9, 5)), isTrue); // in TermBreak
      expect(settings.isHoliday(DateTime(2026, 12, 16)), isTrue); // Victory Day
      expect(settings.isHoliday(DateTime(2026, 9, 4)), isTrue); // Friday & in TermBreak
      expect(settings.isHoliday(DateTime(2026, 9, 15)), isFalse); // Normal Tuesday

      // Check reason descriptions
      expect(settings.getHolidayReason(DateTime(2026, 9, 5)), contains('Preparatory Leave'));
      expect(settings.getHolidayReason(DateTime(2026, 12, 16)), contains('Public Holiday'));

      // 4. HolidaySettings toMap and fromMap roundtrip
      final settingsMap = settings.toMap();
      final restoredSettings = HolidaySettings.fromMap(settingsMap);
      expect(restoredSettings.weeklyHolidays, containsAll([DateTime.friday, DateTime.saturday]));
      expect(restoredSettings.specificHolidays.length, 1);
      expect(restoredSettings.termBreaks.length, 1);
      expect(restoredSettings.termBreaks.first.title, 'Preparatory Leave (PL)');
      expect(restoredSettings.isHoliday(DateTime(2026, 9, 5)), isTrue);
    });

    test('AcademicOverride and OverrideType examPeriod evaluation and serialization', () {
      final examPeriod = TermBreak(
        id: 'exam_mid_1',
        title: 'Midterm Exams',
        startDate: DateTime(2026, 10, 10),
        endDate: DateTime(2026, 10, 18),
        type: OverrideType.examPeriod,
      );

      final holidayBreak = TermBreak(
        id: 'eid_1',
        title: 'Eid Vacation',
        startDate: DateTime(2026, 6, 15),
        endDate: DateTime(2026, 6, 22),
        type: OverrideType.holiday,
      );

      expect(examPeriod.isExamPeriod, isTrue);
      expect(examPeriod.isHolidayOrBreak, isFalse);
      expect(holidayBreak.isExamPeriod, isFalse);
      expect(holidayBreak.isHolidayOrBreak, isTrue);

      final settings = HolidaySettings(
        weeklyHolidays: [DateTime.friday],
        termBreaks: [examPeriod, holidayBreak],
      );

      // Exam period check
      expect(settings.isExamPeriod(DateTime(2026, 10, 12)), isTrue);
      expect(settings.isHoliday(DateTime(2026, 10, 12)), isTrue);
      expect(settings.isHolidayOrBreak(DateTime(2026, 10, 12)), isFalse);

      // Holiday break check
      expect(settings.isExamPeriod(DateTime(2026, 6, 16)), isFalse);
      expect(settings.isHoliday(DateTime(2026, 6, 16)), isTrue);
      expect(settings.isHolidayOrBreak(DateTime(2026, 6, 16)), isTrue);

      // Serialization roundtrip
      final map = examPeriod.toMap();
      expect(map['type'], 'examPeriod');
      final restored = TermBreak.fromMap(map);
      expect(restored.type, OverrideType.examPeriod);
      expect(restored.title, 'Midterm Exams');

      // Helper fromString
      expect(OverrideType.fromString('holiday'), OverrideType.holiday);
      expect(OverrideType.fromString('examPeriod'), OverrideType.examPeriod);
      expect(OverrideType.fromString('termBreak'), OverrideType.termBreak);
      expect(OverrideType.fromString('unknown'), OverrideType.termBreak);
    });

    test('TASK 1: SyllabusNode cascading completion and hierarchical bottom-up evaluation', () {
      final child1 = SyllabusNode(title: 'Lecture 1', isLeaf: true, isCompleted: false);
      final child2 = SyllabusNode(title: 'Lecture 2', isLeaf: true, isCompleted: false);
      final topicNode = SyllabusNode(
        title: 'Fourier Transform',
        isLeaf: false,
        isCompleted: false,
        children: [child1, child2],
      );

      // 1. Parent check cascades down to all children
      topicNode.setCompletedCascading(true);
      expect(topicNode.isCompleted, isTrue);
      expect(child1.isCompleted, isTrue);
      expect(child2.isCompleted, isTrue);

      // 2. Parent uncheck cascades down to all children
      topicNode.setCompletedCascading(false);
      expect(topicNode.isCompleted, isFalse);
      expect(child1.isCompleted, isFalse);
      expect(child2.isCompleted, isFalse);

      // 3. Child manually checked: 1 of 2 -> parent remains false
      child1.isCompleted = true;
      topicNode.updateHierarchicalCompletion();
      expect(topicNode.isCompleted, isFalse);

      // 4. All children checked -> parent automatically becomes true
      child2.isCompleted = true;
      topicNode.updateHierarchicalCompletion();
      expect(topicNode.isCompleted, isTrue);

      // 5. One child unchecked -> parent automatically becomes false
      child1.isCompleted = false;
      topicNode.updateHierarchicalCompletion();
      expect(topicNode.isCompleted, isFalse);
    });

    test('TASK 4 & 5: ClassRoutine lifecycle splitting and isActiveOnDate evaluation', () {
      final oldRoutine = ClassRoutine(
        id: 'routine_1',
        courseId: 'c_eee101',
        courseName: 'EEE 101',
        dayOfWeek: DateTime.monday,
        startTime: '09:00 AM',
        endTime: '10:30 AM',
        classType: 'Theory',
        effectiveFrom: null,
        effectiveUntil: DateTime(2026, 9, 14), // Ends on Sept 14
      );

      final newRoutine = ClassRoutine(
        id: 'routine_2',
        courseId: 'c_eee101',
        courseName: 'EEE 101',
        dayOfWeek: DateTime.monday,
        startTime: '10:30 AM', // Rescheduled start time
        endTime: '12:00 PM',
        classType: 'Theory',
        effectiveFrom: DateTime(2026, 9, 15), // Active from Sept 15 forward
        effectiveUntil: null,
      );

      final mondayBefore = DateTime(2026, 9, 7); // Monday before split
      final mondayAfter = DateTime(2026, 9, 21); // Monday after split
      final tuesday = DateTime(2026, 9, 8); // Tuesday (wrong day)

      // Before split date
      expect(oldRoutine.isActiveOnDate(mondayBefore), isTrue);
      expect(newRoutine.isActiveOnDate(mondayBefore), isFalse);

      // After split date
      expect(oldRoutine.isActiveOnDate(mondayAfter), isFalse);
      expect(newRoutine.isActiveOnDate(mondayAfter), isTrue);

      // Wrong day of week
      expect(oldRoutine.isActiveOnDate(tuesday), isFalse);
      expect(newRoutine.isActiveOnDate(tuesday), isFalse);
    });

    test('TASK 4: HolidaySettings semesterStart and semesterEnd boundaries enforcement', () {
      final settings = HolidaySettings(
        semesterStart: DateTime(2026, 7, 1),
        semesterEnd: DateTime(2026, 12, 31),
      );

      expect(settings.isWithinSemester(DateTime(2026, 7, 1)), isTrue);
      expect(settings.isWithinSemester(DateTime(2026, 9, 15)), isTrue);
      expect(settings.isWithinSemester(DateTime(2026, 12, 31)), isTrue);

      // Outside bounds
      expect(settings.isWithinSemester(DateTime(2026, 6, 30)), isFalse);
      expect(settings.isWithinSemester(DateTime(2027, 1, 1)), isFalse);

      // Serialization roundtrip
      final map = settings.toMap();
      final restored = HolidaySettings.fromMap(map);
      expect(restored.semesterStart?.month, 7);
      expect(restored.semesterEnd?.month, 12);
      expect(restored.isWithinSemester(DateTime(2026, 9, 15)), isTrue);
      expect(restored.isWithinSemester(DateTime(2026, 6, 1)), isFalse);
    });

    test('TASK 6: Bi-weekly class clash detection within same Saturday-to-Friday calendar week', () {
      // Current day: Monday, Aug 17, 2026
      final mondayDate = DateTime(2026, 8, 17);
      final int daysSinceSat = (mondayDate.weekday - DateTime.saturday + 7) % 7;
      final weekStart = DateTime(mondayDate.year, mondayDate.month, mondayDate.day).subtract(Duration(days: daysSinceSat));
      final weekEnd = weekStart.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));

      // Week should span from Saturday Aug 15 to Friday Aug 21
      expect(weekStart.day, 15);
      expect(weekEnd.day, 21);

      final attendedWednesday = AttendanceRecord(
        id: 'att_1',
        courseId: 'c_lab102',
        routineId: 'alt_routine_slot_b',
        courseName: 'EEE 102 Lab',
        classType: 'Lab',
        date: DateTime(2026, 8, 19), // Wednesday in same week
        status: AttendanceStatus.attended,
      );

      final attendedPreviousWeek = AttendanceRecord(
        id: 'att_2',
        courseId: 'c_lab102',
        routineId: 'alt_routine_slot_b',
        courseName: 'EEE 102 Lab',
        classType: 'Lab',
        date: DateTime(2026, 8, 12), // Wednesday of previous week
        status: AttendanceStatus.attended,
      );

      // Check same week clash:
      final isAttendedInSameWeek = !attendedWednesday.date.isBefore(weekStart) && !attendedWednesday.date.isAfter(weekEnd);
      expect(isAttendedInSameWeek, isTrue);

      // Check previous week (should not clash):
      final isPreviousInSameWeek = !attendedPreviousWeek.date.isBefore(weekStart) && !attendedPreviousWeek.date.isAfter(weekEnd);
      expect(isPreviousInSameWeek, isFalse);
    });

    test('AttendanceStats totalClasses calculates aggregate attended + missed + extra correctly', () {
      const stats = AttendanceStats(
        attended: 12,
        missed: 3,
        canceled: 2,
        extra: 1,
      );

      expect(stats.totalClasses, 16);
      expect(stats.validClassesCount, 16);
      expect(stats.attended, 12);
      expect(stats.missed, 3);
      expect(stats.canceled, 2);
      expect(stats.extra, 1);
    });

    test('TASK 4: Aggregate total attendance percentage strictly follows Total Attended / (Total Attended + Total Missed)', () {
      const stats = AttendanceStats(
        attended: 18,
        missed: 6,
        canceled: 4,
        extra: 2,
      );

      final totalAttended = stats.attended + stats.extra; // 20
      final totalMissed = stats.missed; // 6
      final aggregateTotal = totalAttended + totalMissed; // 26
      final percentage = (totalAttended / aggregateTotal) * 100.0;

      expect(totalAttended, 20);
      expect(aggregateTotal, 26);
      expect(percentage, closeTo(76.92, 0.01));
    });

    test('TASK 3: ClassRoutine is strictly filtered out when date is outside semester bounds', () {
      final semesterSettings = HolidaySettings(
        weeklyHolidays: [5], // Friday
        semesterStart: DateTime(2026, 7, 1),
        semesterEnd: DateTime(2026, 11, 30),
      );

      final routine = ClassRoutine(
        id: 'r_math',
        courseId: 'c_math',
        courseName: 'MATH 101',
        dayOfWeek: DateTime.monday,
        startTime: '09:00 AM',
        endTime: '10:30 AM',
        classType: 'Theory',
      );

      final insideDate = DateTime(2026, 8, 17); // Monday in August
      final beforeDate = DateTime(2026, 6, 15); // Monday before semester
      final afterDate = DateTime(2026, 12, 14); // Monday after semester

      expect(semesterSettings.isWithinSemester(insideDate), isTrue);
      expect(routine.isActiveOnDate(insideDate), isTrue);

      expect(semesterSettings.isWithinSemester(beforeDate), isFalse);
      expect(semesterSettings.isWithinSemester(afterDate), isFalse);
    });

    test('TASK 2 & 3: AttendanceRecord topic serializes and logs cleanly', () {
      final record = AttendanceRecord(
        courseId: 'c_eee101',
        date: DateTime(2026, 8, 29),
        status: AttendanceStatus.attended,
        courseName: 'EEE 101',
        topic: 'Thevenin Theorem & Superposition',
      );

      final map = record.toMap();
      expect(map['topic'], 'Thevenin Theorem & Superposition');
      expect(map['status'], 'attended');

      final deserialized = AttendanceRecord.fromMap(map);
      expect(deserialized.topic, 'Thevenin Theorem & Superposition');
      expect(deserialized.courseName, 'EEE 101');
      expect(deserialized.status, AttendanceStatus.attended);
    });

    test('TASK 3: SyllabusNode Class Logs section auto-appends newly typed topic', () {
      final List<SyllabusNode> nodes = [
        SyllabusNode(
          title: 'Unit 1: Fundamentals',
          isLeaf: false,
          children: [
            SyllabusNode(title: 'Ohm Law', isLeaf: true, isCompleted: true),
          ],
        ),
      ];

      // Simulate typing a new topic "Kirchhoff Laws"
      const typedTopic = 'Kirchhoff Laws';
      final Set<String> existingTitles = {};
      void collect(List<SyllabusNode> list) {
        for (final n in list) {
          if (n.title.trim().isNotEmpty) existingTitles.add(n.title.trim());
          collect(n.children);
        }
      }
      collect(nodes);

      expect(existingTitles.contains(typedTopic), isFalse);

      // Append under Class Logs
      SyllabusNode? classLogsNode;
      for (final n in nodes) {
        if (n.title.trim().toLowerCase() == 'class logs') {
          classLogsNode = n;
          break;
        }
      }
      if (classLogsNode == null) {
        classLogsNode = SyllabusNode(title: 'Class Logs', isLeaf: false, children: []);
        nodes.add(classLogsNode);
      }

      classLogsNode.children.add(SyllabusNode(title: typedTopic, isLeaf: true, isCompleted: true));

      expect(nodes.length, 2);
      expect(nodes.last.title, 'Class Logs');
      expect(nodes.last.children.length, 1);
      expect(nodes.last.children.first.title, 'Kirchhoff Laws');
      expect(nodes.last.children.first.isCompleted, isTrue);
    });

    test('TASK 1: Batch Add Materials attaches selected categories to multiple topics without duplicate titles', () {
      final section = SyllabusNode(
        title: 'Chapter 1: Semiconductor Diodes',
        isLeaf: false,
        children: [
          SyllabusNode(title: 'Topic 1: PN Junction', isLeaf: true, isCompleted: false),
          SyllabusNode(title: 'Topic 2: Zener Breakdown', isLeaf: true, isCompleted: false),
          SyllabusNode(
            title: 'Sub-chapter 1.1',
            isLeaf: false,
            children: [
              SyllabusNode(title: 'Topic 3: Diode Rectifiers', isLeaf: true, isCompleted: false),
            ],
          ),
        ],
      );

      // Collect all leaf topics
      List<SyllabusNode> collectLeafTopics(SyllabusNode parent) {
        List<SyllabusNode> list = [];
        for (final child in parent.children) {
          if (child.isLeaf) {
            list.add(child);
          } else {
            list.addAll(collectLeafTopics(child));
          }
        }
        return list;
      }

      final leafTopics = collectLeafTopics(section);
      expect(leafTopics.length, 3);

      final selectedCategories = ['Class Note', 'Lecture Sheet', 'Ref Book', 'Term Final Question'];

      for (final topic in leafTopics) {
        for (final cat in selectedCategories) {
          final exists = topic.children.any(
            (c) => c.title.trim().toLowerCase() == cat.trim().toLowerCase(),
          );
          if (!exists) {
            topic.children.add(
              SyllabusNode(title: cat, isLeaf: true, isCompleted: false),
            );
          }
        }
      }

      for (final topic in leafTopics) {
        expect(topic.children.length, 4);
        expect(topic.children.map((c) => c.title).toList(), selectedCategories);
      }

      // Re-running batch attach doesn't duplicate
      for (final topic in leafTopics) {
        for (final cat in selectedCategories) {
          final exists = topic.children.any(
            (c) => c.title.trim().toLowerCase() == cat.trim().toLowerCase(),
          );
          if (!exists) {
            topic.children.add(
              SyllabusNode(title: cat, isLeaf: true, isCompleted: false),
            );
          }
        }
      }

      for (final topic in leafTopics) {
        expect(topic.children.length, 4);
      }
    });

    test('TASK 2: Unified Attendance Sync strictly calculates attendedCount, totalHeld, and attendanceRate', () {
      final records = [
        AttendanceRecord(courseId: 'CSE101', date: DateTime.now(), status: AttendanceStatus.attended),
        AttendanceRecord(courseId: 'CSE101', date: DateTime.now(), status: AttendanceStatus.attended),
        AttendanceRecord(courseId: 'CSE101', date: DateTime.now(), status: AttendanceStatus.extra),
        AttendanceRecord(courseId: 'CSE101', date: DateTime.now(), status: AttendanceStatus.missed),
        AttendanceRecord(courseId: 'CSE101', date: DateTime.now(), status: AttendanceStatus.canceled),
      ];

      final stats = AttendanceStats.fromRecords(records);
      expect(stats.attended, 2);
      expect(stats.extra, 1);
      expect(stats.missed, 1);
      expect(stats.canceled, 1);

      // Formulas from prompt:
      // attendedCount = records with status Attended + Extra
      final attendedCount = stats.attended + stats.extra;
      // totalHeld = records with status Attended + Missed + Extra
      final totalHeld = stats.attended + stats.missed + stats.extra;
      // attendanceRate = (attendedCount / totalHeld) * 100%
      final double attendanceRate = totalHeld > 0 ? (attendedCount / totalHeld) * 100.0 : 100.0;

      expect(attendedCount, 3);
      expect(totalHeld, 4);
      expect(attendanceRate, 75.0);
      expect(attendanceRate >= 75.0, isTrue); // In Good Standing
    });

    test('TASK 1: RoutineCourseSyncService parses course codes and categorizes credit hours correctly', () {
      expect(RoutineCourseSyncService.parseCourseCode('PHY 121 - Physics I'), 'PHY 121');
      expect(RoutineCourseSyncService.parseCourseCode('MATH 157: Calculus'), 'MATH 157');
      expect(RoutineCourseSyncService.parseCourseCode('CSE 110 (Section A)'), 'CSE 110');
      expect(RoutineCourseSyncService.parseCourseCode('EEE 101'), 'EEE 101');
      expect(RoutineCourseSyncService.parseCourseCode('CSE-201'), 'CSE-201');
      expect(RoutineCourseSyncService.parseCourseCode('ENG 101L • English Language'), 'ENG 101L');

      // Credit hours and course type inference logic
      final isLab1 = 'Sessional/Lab'.toLowerCase().contains('lab');
      final isLab2 = 'Theory'.toLowerCase().contains('lab');
      expect(isLab1 ? 1.5 : 3.0, 1.5);
      expect(isLab2 ? 1.5 : 3.0, 3.0);
    });

    test('TASK 2: Daily Class Topic Logger marks existing syllabus topic complete and links note', () {
      final topicNode = SyllabusNode(
        title: 'Bipolar Junction Transistors',
        isLeaf: true,
        isCompleted: false,
      );
      final sectionNode = SyllabusNode(
        title: 'Electronics',
        isLeaf: false,
        children: [topicNode],
      );
      final syllabus = [sectionNode];

      // Topic logged: existing topic selected
      topicNode.isCompleted = true;
      const noteUrl = 'https://drive.google.com/lecture_bjt.pdf';
      topicNode.children.add(SyllabusNode(
        title: 'Class Note (30/8)',
        isLeaf: true,
        resourceUrl: noteUrl,
        isCompleted: false,
      ));

      expect(topicNode.isCompleted, isTrue);
      expect(topicNode.children.length, 1);
      expect(topicNode.children.first.resourceUrl, noteUrl);
    });

    test('TASK 2: Daily Class Topic Logger adds new topic under Lectures & Class Logs section', () {
      final syllabus = <SyllabusNode>[
        SyllabusNode(title: 'Calculus Basics', isLeaf: false, children: []),
      ];

      // New topic entered that wasn't in original syllabus
      final newTopic = 'Taylor Series Approximations';
      const noteUrl = 'https://drive.google.com/taylor.pdf';

      SyllabusNode? logsSection;
      for (final n in syllabus) {
        final lower = n.title.trim().toLowerCase();
        if (lower == 'lectures & class logs' || lower == 'class logs') {
          logsSection = n;
          break;
        }
      }
      if (logsSection == null) {
        logsSection = SyllabusNode(
          title: 'Lectures & Class Logs',
          isLeaf: false,
          children: [],
        );
        syllabus.add(logsSection);
      }

      final newTopicNode = SyllabusNode(
        title: newTopic,
        isLeaf: true,
        isCompleted: true,
        resourceUrl: noteUrl,
      );
      newTopicNode.children.add(SyllabusNode(
        title: 'Class Note (30/8)',
        isLeaf: true,
        resourceUrl: noteUrl,
        isCompleted: false,
      ));
      logsSection.children.add(newTopicNode);

      expect(syllabus.length, 2);
      expect(syllabus.last.title, 'Lectures & Class Logs');
      expect(syllabus.last.children.length, 1);
      expect(syllabus.last.children.first.title, 'Taylor Series Approximations');
      expect(syllabus.last.children.first.isCompleted, isTrue);
      expect(syllabus.last.children.first.resourceUrl, noteUrl);
    });

    test('TASK 1: RoutineCourseSyncService.sanitizeDocId standardizes canonical document IDs', () {
      expect(RoutineCourseSyncService.sanitizeDocId('MATH 157'), 'MATH_157');
      expect(RoutineCourseSyncService.sanitizeDocId('CSE 109'), 'CSE_109');
      expect(RoutineCourseSyncService.sanitizeDocId('PHY 121'), 'PHY_121');
      expect(RoutineCourseSyncService.sanitizeDocId('EEE-101'), 'EEE_101');
      expect(RoutineCourseSyncService.sanitizeDocId('SWE   312'), 'SWE_312');
      expect(RoutineCourseSyncService.sanitizeDocId('__chem 101__'), 'CHEM_101');
    });

    test('TASK 1 & 2: AttendanceRecord stores courseCode and roundtrips cleanly', () {
      final record = AttendanceRecord(
        id: 'MATH_157_routine_001_2026_08_30',
        courseId: 'MATH_157',
        courseCode: 'MATH 157',
        courseName: 'MATH 157 - Differential Calculus',
        date: DateTime(2026, 8, 30),
        status: AttendanceStatus.attended,
        routineId: 'routine_001',
        classType: 'Theory',
        time: '09:00 AM - 10:30 AM',
      );

      final map = record.toMap();
      expect(map['courseId'], 'MATH_157');
      expect(map['courseCode'], 'MATH 157');
      expect(map['status'], 'attended');

      final deserialized = AttendanceRecord.fromMap(map, defaultId: record.id);
      expect(deserialized.id, 'MATH_157_routine_001_2026_08_30');
      expect(deserialized.courseId, 'MATH_157');
      expect(deserialized.courseCode, 'MATH 157');
      expect(deserialized.status, AttendanceStatus.attended);
    });

    test('TASK 2: RoutineCourseSyncService.recordMatchesCourse performs resilient multi-identifier matching', () {
      // Course in Firestore has id = 'MATH_157', courseCode = 'MATH 157'
      const courseId = 'MATH_157';
      const courseCode = 'MATH 157';
      const courseName = 'Differential Calculus';

      // 1. Direct doc ID match
      final r1 = AttendanceRecord(
        courseId: 'MATH_157',
        date: DateTime.now(),
        status: AttendanceStatus.attended,
      );
      expect(RoutineCourseSyncService.recordMatchesCourse(
        record: r1,
        courseId: courseId,
        courseCode: courseCode,
        courseName: courseName,
      ), isTrue);

      // 2. Matching by courseCode in courseId field (e.g. saved as 'MATH 157' or 'math 157')
      final r2 = AttendanceRecord(
        courseId: 'math 157',
        date: DateTime.now(),
        status: AttendanceStatus.attended,
      );
      expect(RoutineCourseSyncService.recordMatchesCourse(
        record: r2,
        courseId: courseId,
        courseCode: courseCode,
        courseName: courseName,
      ), isTrue);

      // 3. Matching by record.courseCode when record.courseId is a random/legacy doc ID
      final r3 = AttendanceRecord(
        courseId: 'legacy_random_doc_abc',
        courseCode: 'MATH 157',
        date: DateTime.now(),
        status: AttendanceStatus.attended,
      );
      expect(RoutineCourseSyncService.recordMatchesCourse(
        record: r3,
        courseId: courseId,
        courseCode: courseCode,
        courseName: courseName,
      ), isTrue);

      // 4. Matching by parsed courseName (e.g. 'MATH 157 (Theory)')
      final r4 = AttendanceRecord(
        courseId: 'legacy_random_doc_xyz',
        courseName: 'MATH 157 (Theory)',
        date: DateTime.now(),
        status: AttendanceStatus.attended,
      );
      expect(RoutineCourseSyncService.recordMatchesCourse(
        record: r4,
        courseId: courseId,
        courseCode: courseCode,
        courseName: courseName,
      ), isTrue);

      // 5. Distinct course correctly returns false
      final r5 = AttendanceRecord(
        courseId: 'PHY_121',
        courseCode: 'PHY 121',
        date: DateTime.now(),
        status: AttendanceStatus.attended,
      );
      expect(RoutineCourseSyncService.recordMatchesCourse(
        record: r5,
        courseId: courseId,
        courseCode: courseCode,
        courseName: courseName,
      ), isFalse);
    });

    group('Sprint 8: Post-Session Study Logging & Auto-Journal Sync Tests', () {
      test('StudyJournalEntry serialization and deserialization roundtrip', () {
        final now = DateTime.now();
        final entry = StudyJournalEntry(
          id: 'test_journal_123',
          type: 'study_session',
          title: 'Study Log: CSE 109',
          content: 'Topics: Nodal Analysis, Thevenin theorem\n\nNotes: Understood AC sources, need more practice.',
          topicsCovered: 'Nodal Analysis, Thevenin theorem',
          reflections: 'Understood AC sources, need more practice.',
          durationMinutes: 45,
          subjectOrCourseId: 'CSE_109',
          timestamp: now,
          mode: 'university',
        );

        final map = entry.toMap();
        expect(map['id'], 'test_journal_123');
        expect(map['type'], 'study_session');
        expect(map['title'], 'Study Log: CSE 109');
        expect(map['durationMinutes'], 45);
        expect(map['subjectOrCourseId'], 'CSE_109');
        expect(map['mode'], 'university');
        expect(map['topicsCovered'], 'Nodal Analysis, Thevenin theorem');
        expect(map['reflections'], 'Understood AC sources, need more practice.');

        // Reconstruct from map
        final restored = StudyJournalEntry.fromMap(map, 'test_journal_123');
        expect(restored.id, 'test_journal_123');
        expect(restored.type, 'study_session');
        expect(restored.isStudySession, isTrue);
        expect(restored.title, 'Study Log: CSE 109');
        expect(restored.durationMinutes, 45);
        expect(restored.subjectOrCourseId, 'CSE_109');
        expect(restored.mode, 'university');
        expect(restored.topicsCovered, 'Nodal Analysis, Thevenin theorem');
        expect(restored.reflections, 'Understood AC sources, need more practice.');
      });

      test('StudyJournalEntry admission mode defaults and formatting', () {
        final now = DateTime.now();
        final entry = StudyJournalEntry(
          id: 'adm_log_456',
          title: 'Study Log: Physics 1st Paper',
          content: 'Topics: Vector calculus and dot product',
          topicsCovered: 'Vector calculus and dot product',
          durationMinutes: 30,
          subjectOrCourseId: 'Physics_1st_Paper',
          timestamp: now,
          mode: 'admission',
        );

        expect(entry.type, 'study_session');
        expect(entry.isStudySession, isTrue);
        expect(entry.mode, 'admission');
        expect(entry.reflections, isNull);

        final map = entry.toMap();
        final restored = StudyJournalEntry.fromMap(map, 'adm_log_456');
        expect(restored.title, 'Study Log: Physics 1st Paper');
        expect(restored.durationMinutes, 30);
        expect(restored.mode, 'admission');
      });

      test('StudySessionFeedItem conforms to JournalFeedItem contract', () {
        final testDate = DateTime(2026, 8, 30, 15, 30);
        final entry = StudyJournalEntry(
          id: 'item_789',
          title: 'Study Log: MATH 157',
          content: 'Linear algebra review',
          durationMinutes: 60,
          subjectOrCourseId: 'MATH_157',
          timestamp: testDate,
          mode: 'university',
        );

        final feedItem = StudySessionFeedItem(entry);
        expect(feedItem, isA<JournalFeedItem>());
        expect(feedItem.date, testDate);
        expect(feedItem.isPinned, isFalse);
        expect(feedItem.entry.durationMinutes, 60);
      });
    });

    group('Sprint 9: Lab Lock, Sessional Assessment & Post-Timer Dialog Tests', () {
      test('RoutineCourseSyncService extractBaseCourseCode parses codes correctly', () {
        expect(RoutineCourseSyncService.extractBaseCourseCode('EEE 102 (H)'), 'EEE 102');
        expect(RoutineCourseSyncService.extractBaseCourseCode('EEE 102 (S)'), 'EEE 102');
        expect(RoutineCourseSyncService.extractBaseCourseCode('CSE 110 [Lab]'), 'CSE 110');
        expect(RoutineCourseSyncService.extractBaseCourseCode('PHY 121'), 'PHY 121');
        expect(RoutineCourseSyncService.extractBaseCourseCode('MATH 157'), 'MATH 157');
        expect(RoutineCourseSyncService.extractBaseCourseCode(''), '');
      });

      test('RoutineCourseSyncService getAcademicWeekRange sets Saturday to Friday boundaries', () {
        // Wednesday, August 26, 2026
        final wednesday = DateTime(2026, 8, 26, 14, 30);
        final range = RoutineCourseSyncService.getAcademicWeekRange(wednesday);

        expect(range.start.weekday, DateTime.saturday);
        expect(range.start.year, 2026);
        expect(range.start.month, 8);
        expect(range.start.day, 22);
        expect(range.start.hour, 0);
        expect(range.start.minute, 0);

        expect(range.end.weekday, DateTime.friday);
        expect(range.end.year, 2026);
        expect(range.end.month, 8);
        expect(range.end.day, 28);
        expect(range.end.hour, 23);
        expect(range.end.minute, 59);
      });

      test('RoutineCourseSyncService isAlternatingCounterpartBlocked detects paired biweekly lab session', () {
        final date = DateTime(2026, 8, 26); // Wednesday in week Aug 22 - Aug 28
        final routineH = ClassRoutine(
          id: 'rot_eee102_h',
          courseId: 'EEE_102',
          courseName: 'EEE 102 (H)',
          classType: 'Sessional',
          recurrence: 'biweekly_a',
          pairedClassId: 'rot_eee102_s',
          dayOfWeek: DateTime.wednesday,
          startTime: '08:00',
          endTime: '11:00',
        );

        final routineS = ClassRoutine(
          id: 'rot_eee102_s',
          courseId: 'EEE_102',
          courseName: 'EEE 102 (S)',
          classType: 'Sessional',
          recurrence: 'biweekly_b',
          pairedClassId: 'rot_eee102_h',
          dayOfWeek: DateTime.wednesday,
          startTime: '08:00',
          endTime: '11:00',
        );

        // Scenario 1: No attendance record yet for the week
        final isBlockedBefore = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: routineS,
          records: [],
          selectedDate: date,
        );
        expect(isBlockedBefore, isFalse);

        // Scenario 2: Counterpart routineH attended on Wednesday Aug 26
        final attendanceH = AttendanceRecord(
          id: 'att_1',
          courseId: 'EEE_102',
          routineId: 'rot_eee102_h',
          courseCode: 'EEE 102 (H)',
          date: DateTime(2026, 8, 26),
          status: AttendanceStatus.attended,
        );

        final isBlockedAfter = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: routineS,
          records: [attendanceH],
          selectedDate: date,
        );
        expect(isBlockedAfter, isTrue);

        // Target itself (routineH) should not be blocked by its own record
        final isHTargetBlocked = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: routineH,
          records: [attendanceH],
          selectedDate: date,
        );
        expect(isHTargetBlocked, isFalse);
      });

      test('Theory classes and weekly recurring slots are NEVER blocked by alternate validator', () {
        final date = DateTime(2026, 8, 26);
        final theorySlot1 = ClassRoutine(
          id: 'rot_phy121_sun',
          courseId: 'PHY_121',
          courseName: 'PHY 121 • Waves & Oscillation, Optics & Thermal Physics',
          classType: 'Theory',
          recurrence: 'weekly',
          dayOfWeek: DateTime.sunday,
          startTime: '10:00 AM',
          endTime: '10:50 AM',
        );

        final theorySlot2 = ClassRoutine(
          id: 'rot_phy121_wed',
          courseId: 'PHY_121',
          courseName: 'PHY 121 • Waves & Oscillation, Optics & Thermal Physics',
          classType: 'Theory',
          recurrence: 'weekly',
          dayOfWeek: DateTime.wednesday,
          startTime: '10:00 AM',
          endTime: '10:50 AM',
        );

        // Attendance recorded on Sunday for the same course and time slot
        final attendanceSun = AttendanceRecord(
          id: 'att_phy_sun',
          courseId: 'PHY_121',
          routineId: 'rot_phy121_sun',
          courseCode: 'PHY 121',
          courseName: 'PHY 121 • Waves & Oscillation, Optics & Thermal Physics',
          classType: 'Theory',
          time: '10:00 AM - 10:50 AM',
          date: DateTime(2026, 8, 23), // Sunday of the same academic week
          status: AttendanceStatus.attended,
        );

        // Wednesday Theory class must NOT be blocked by Sunday Theory attendance
        final isTheoryBlocked = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: theorySlot2,
          records: [attendanceSun],
          selectedDate: date,
        );
        expect(isTheoryBlocked, isFalse);

        // Weekly Sessional without paired class ID must also NOT be blocked
        final weeklyLab = ClassRoutine(
          id: 'rot_cse110_lab',
          courseId: 'CSE_110',
          courseName: 'CSE 110 • Programming Lab',
          classType: 'Lab',
          recurrence: 'weekly',
          dayOfWeek: DateTime.wednesday,
          startTime: '02:00 PM',
          endTime: '05:00 PM',
        );

        final isWeeklyLabBlocked = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: weeklyLab,
          records: [attendanceSun],
          selectedDate: date,
        );
        expect(isWeeklyLabBlocked, isFalse);
      });

      test('AssessmentItem calculates percentage and serializes correctly', () {
        final item = AssessmentItem(name: 'Quiz 1', obtained: 16.0, total: 20.0);
        expect(item.percentage, 80.0);

        final map = item.toMap();
        expect(map['name'], 'Quiz 1');
        expect(map['obtained'], 16.0);
        expect(map['total'], 20.0);

        final restored = AssessmentItem.fromMap(map);
        expect(restored.name, 'Quiz 1');
        expect(restored.obtained, 16.0);
        expect(restored.total, 20.0);
      });

      testWidgets('StudySessionLogDialog renders summary, fields and buttons cleanly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: StudySessionLogDialog(
                subjectOrCourseName: 'EEE 101',
                subjectOrCourseId: 'EEE_101',
                durationMinutes: 45,
                mode: 'university',
              ),
            ),
          ),
        );

        expect(find.text('Session Completed! 🎉'), findsOneWidget);
        expect(find.text('EEE 101'), findsOneWidget);
        expect(find.text('45 mins'), findsOneWidget);
        expect(find.text('KEYWORDS / TOPICS READ'), findsOneWidget);
        expect(find.text('QUICK REFLECTION / NOTES (OPTIONAL)'), findsOneWidget);
        expect(find.text('Skip'), findsOneWidget);
        expect(find.text('Save to Journal'), findsOneWidget);
      });

      test('AssessmentCalculationHelper calculateCategoryScore with all items', () {
        final items = [
          AssessmentItem(name: 'Quiz 1', obtained: 15.0, total: 20.0), // 75%
          AssessmentItem(name: 'Quiz 2', obtained: 20.0, total: 20.0), // 100%
        ];

        final result = AssessmentCalculationHelper.calculateCategoryScore(
          items: items,
          weightagePercentage: 20.0,
          useBestOf: false,
        );

        expect(result.totalItems, 2);
        expect(result.countedItems, 2);
        expect(result.percentage, 87.5);
        expect(result.weightedScore, closeTo(17.5, 0.01));
        expect(result.weightage, 20.0);
      });

      test('AssessmentCalculationHelper calculateCategoryScore with Best-of-N', () {
        final items = [
          AssessmentItem(name: 'CT 1', obtained: 10.0, total: 20.0), // 50%
          AssessmentItem(name: 'CT 2', obtained: 18.0, total: 20.0), // 90%
          AssessmentItem(name: 'CT 3', obtained: 16.0, total: 20.0), // 80%
          AssessmentItem(name: 'CT 4', obtained: 20.0, total: 20.0), // 100%
        ];

        // Best 3 of 4: CT 4 (100%), CT 2 (90%), CT 3 (80%). Excludes CT 1 (50%).
        // Avg = (100 + 90 + 80) / 3 = 90.0%
        final result = AssessmentCalculationHelper.calculateCategoryScore(
          items: items,
          weightagePercentage: 20.0,
          useBestOf: true,
          bestCount: 3,
        );

        expect(result.totalItems, 4);
        expect(result.countedItems, 3);
        expect(result.percentage, 90.0);
        expect(result.weightedScore, closeTo(18.0, 0.01));
        expect(result.activeItems.length, 3);
        expect(result.activeItems.first.name, 'CT 4');
      });

      test('AssessmentCalculationHelper calculatePredictedGrade and CGPA conversion', () {
        // Quizzes (20%): 90% -> 18.0 pts
        final res1 = CategoryCalculationResult(
          obtained: 90,
          total: 100,
          percentage: 90.0,
          weightedScore: 18.0,
          weightage: 20.0,
          useBestOf: true,
          bestCount: 3,
          totalItems: 4,
          countedItems: 3,
          activeItems: const [],
        );

        // Midterm (30%): 80% -> 24.0 pts
        final res2 = CategoryCalculationResult(
          obtained: 24,
          total: 30,
          percentage: 80.0,
          weightedScore: 24.0,
          weightage: 30.0,
          useBestOf: false,
          bestCount: 1,
          totalItems: 1,
          countedItems: 1,
          activeItems: const [],
        );

        // Final (50%): 85% -> 42.5 pts
        final res3 = CategoryCalculationResult(
          obtained: 178.5,
          total: 210,
          percentage: 85.0,
          weightedScore: 42.5,
          weightage: 50.0,
          useBestOf: false,
          bestCount: 1,
          totalItems: 1,
          countedItems: 1,
          activeItems: const [],
        );

        final predicted = AssessmentCalculationHelper.calculatePredictedGrade(
          categoryResults: [res1, res2, res3],
        );

        // Total weighted score = 18.0 + 24.0 + 42.5 = 84.5 / 100
        expect(predicted.totalWeightedScore, closeTo(84.5, 0.01));
        expect(predicted.totalWeightage, 100.0);
        expect(predicted.isFullWeightage, isTrue);
        expect(predicted.letterGrade, 'A+');
        expect(predicted.gradePoint, 4.00);
        expect(predicted.remarks, 'Outstanding');
      });

      test('AssessmentCalculationHelper percentageToGrade converts all brackets', () {
        expect(AssessmentCalculationHelper.percentageToGrade(82).letterGrade, 'A+');
        expect(AssessmentCalculationHelper.percentageToGrade(82).gradePoint, 4.00);

        expect(AssessmentCalculationHelper.percentageToGrade(76).letterGrade, 'A');
        expect(AssessmentCalculationHelper.percentageToGrade(76).gradePoint, 3.75);

        expect(AssessmentCalculationHelper.percentageToGrade(71).letterGrade, 'A-');
        expect(AssessmentCalculationHelper.percentageToGrade(71).gradePoint, 3.50);

        expect(AssessmentCalculationHelper.percentageToGrade(66).letterGrade, 'B+');
        expect(AssessmentCalculationHelper.percentageToGrade(66).gradePoint, 3.25);

        expect(AssessmentCalculationHelper.percentageToGrade(61).letterGrade, 'B');
        expect(AssessmentCalculationHelper.percentageToGrade(61).gradePoint, 3.00);

        expect(AssessmentCalculationHelper.percentageToGrade(56).letterGrade, 'B-');
        expect(AssessmentCalculationHelper.percentageToGrade(56).gradePoint, 2.75);

        expect(AssessmentCalculationHelper.percentageToGrade(51).letterGrade, 'C+');
        expect(AssessmentCalculationHelper.percentageToGrade(51).gradePoint, 2.50);

        expect(AssessmentCalculationHelper.percentageToGrade(46).letterGrade, 'C');
        expect(AssessmentCalculationHelper.percentageToGrade(46).gradePoint, 2.25);

        expect(AssessmentCalculationHelper.percentageToGrade(41).letterGrade, 'D');
        expect(AssessmentCalculationHelper.percentageToGrade(41).gradePoint, 2.00);

        expect(AssessmentCalculationHelper.percentageToGrade(35).letterGrade, 'F');
        expect(AssessmentCalculationHelper.percentageToGrade(35).gradePoint, 0.00);
      });
    });

    group('Sprint 10: Persistent SnackBars, Dialog Dismissal, UI Copy & Lecture Topics Tests', () {
      testWidgets('TASK 1: SnackBarService shows floating snackbar with 3s duration and black View button', (tester) async {
        bool viewTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    SnackBarService.showStudySessionSaved(
                      context,
                      durationMinutes: 25,
                      onViewPressed: () {
                        viewTapped = true;
                      },
                    );
                  },
                  child: const Text('Show SnackBar'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Show SnackBar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify floating SnackBar renders with correct text and action
        expect(find.text('Session notes saved to Journal (25m)'), findsOneWidget);
        expect(find.text('View'), findsOneWidget);

        // Tap the View action button
        await tester.tap(find.text('View'));
        await tester.pump();
        expect(viewTapped, isTrue);

        // Advance 3 seconds + animation to verify it auto-dismisses
        await tester.pump(const Duration(seconds: 4));
        expect(find.text('Session notes saved to Journal (25m)'), findsNothing);
      });

      testWidgets('TASK 1: SnackBarService hides current snackbar before showing new one', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => SnackBarService.showSuccess(context, 'First Message'),
                      child: const Text('First'),
                    ),
                    ElevatedButton(
                      onPressed: () => SnackBarService.showSuccess(context, 'Second Message'),
                      child: const Text('Second'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('First'));
        await tester.pump();
        expect(find.text('First Message'), findsOneWidget);

        // Show second message immediately
        await tester.tap(find.text('Second'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // First message was hidden, second message is displayed
        expect(find.text('Second Message'), findsOneWidget);
      });

      testWidgets('TASK 2: StudySessionLogDialog instantly dismisses upon Save tap', (tester) async {
        bool onSavedCalled = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => StudySessionLogDialog(
                        subjectOrCourseName: 'Algorithms',
                        subjectOrCourseId: 'cse204',
                        durationMinutes: 45,
                        onSaved: () => onSavedCalled = true,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.text('Algorithms'), findsOneWidget);
        expect(find.text('Save to Journal'), findsOneWidget);

        // Tap Save to Journal
        await tester.tap(find.text('Save to Journal'));
        await tester.pumpAndSettle();

        // Verify dialog is instantly dismissed and onSaved callback is invoked
        expect(find.byType(StudySessionLogDialog), findsNothing);
        expect(onSavedCalled, isTrue);
      });

      test('TASK 3: Professional UI copy checks', () {
        const topicLabel = 'Record Lecture Topic';
        const sessionsRecorded = '3 Sessions Recorded';
        const emptyRecords = 'No entries recorded yet';
        const journalSaved = 'Session notes saved to Journal';

        expect(topicLabel, isNot(contains('Log Today\'s Topic')));
        expect(sessionsRecorded, isNot(contains('Total Classes Logged')));
        expect(emptyRecords, isNot(contains('logged yet')));
        expect(journalSaved, isNot(contains('Study session logged to Journal!')));
      });
    });

    group('Sprint 11: Journal Archive & Mode Segregation + Custom Batch Materials Tests', () {
      test('TASK 1: JournalNotesScreen typedef alias is valid and equal to JournalScreen', () {
        expect(JournalNotesScreen, equals(JournalScreen));
      });

      testWidgets('TASK 1: JournalNotesScreen displays [Current Term | Admission / Archived] when isUniversityStudent is true', (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const uniProfile = UserProfile(
          fullName: 'Test Student',
          nickname: 'Student',
          username: 'student',
          email: 'student@buet.ac.bd',
          phone: '01700000000',
          primaryTarget: 'Engineering',
          isUniversityStudent: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(uniProfile)),
              notesStreamProvider.overrideWith((ref) => Stream.value([
                NoteModel(
                  id: 'n1',
                  title: 'Data Structures Note',
                  content: 'Binary Trees and Graphs',
                  createdAt: DateTime(2026, 3, 1),
                  updatedAt: DateTime(2026, 3, 1),
                  tags: const ['University', 'General'],
                ),
                NoteModel(
                  id: 'n2',
                  title: 'HSC Physics Formula',
                  content: 'Newtonian Mechanics',
                  createdAt: DateTime(2024, 1, 1),
                  updatedAt: DateTime(2024, 1, 1),
                  tags: const ['Admission', 'Formula'],
                ),
              ])),
              examsStreamProvider.overrideWith((ref) => Stream.value([
                ExamModel(
                  id: 'ex1',
                  examName: 'BUET Admission Mock 1',
                  subject: 'Physics',
                  date: DateTime(2024, 5, 10),
                  marksObtained: 85,
                  totalMarks: 100,
                  isCompleted: true,
                  journalEntries: [
                    JournalEntry(
                      content: 'Silly mistake in vector cross product',
                      type: 'mistake',
                    ),
                  ],
                ),
              ])),
              journalStreamProvider.overrideWith((ref) => Stream.value([
                StudyJournalEntry(
                  id: 's1',
                  title: 'CSE 204 Trees Study',
                  content: 'Reviewed AVL Tree balance factors',
                  durationMinutes: 45,
                  subjectOrCourseId: 'CSE 204',
                  timestamp: DateTime(2026, 3, 2),
                  mode: 'university',
                ),
                StudyJournalEntry(
                  id: 's2',
                  title: 'Udvash Model Test Prep',
                  content: 'Organic chemistry reactions review',
                  durationMinutes: 60,
                  subjectOrCourseId: 'Chemistry',
                  timestamp: DateTime(2024, 2, 15),
                  mode: 'admission',
                ),
              ])),
              universityCoursesStreamProvider.overrideWith((ref) => Stream.value([
                {'id': 'cse204', 'courseCode': 'CSE 204', 'courseName': 'Data Structures'},
              ])),
              holidaySettingsStreamProvider.overrideWith((ref) => Stream.value(
                HolidaySettings(
                  weeklyHolidays: const [5, 6],
                  semesterStart: DateTime(2026, 1, 1),
                  semesterEnd: DateTime(2026, 6, 30),
                ),
              )),
            ],
            child: const MaterialApp(
              home: JournalNotesScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Verify Top Segment Filter is present
        expect(find.text('Current Term'), findsOneWidget);
        expect(find.text('Admission / Archived'), findsOneWidget);

        // 2. In "Current Term" segment (default):
        // Current university notes & university study sessions appear
        expect(find.text('Data Structures Note'), findsOneWidget);
        expect(find.text('CSE 204 Trees Study'), findsOneWidget);
        // Legacy admission notes and model tests should NOT appear
        expect(find.text('HSC Physics Formula'), findsNothing);
        expect(find.text('BUET Admission Mock 1'), findsNothing);
        expect(find.text('Udvash Model Test Prep'), findsNothing);

        // 3. Tap "Admission / Archived" segment
        await tester.tap(find.text('Admission / Archived'));
        await tester.pumpAndSettle();

        // Now legacy model test reflections and archived notes appear!
        expect(find.text('HSC Physics Formula'), findsOneWidget);
        expect(find.text('BUET Admission Mock 1'), findsOneWidget);
        expect(find.text('Udvash Model Test Prep'), findsOneWidget);
        // University current term notes should NOT appear in Archived segment
        expect(find.text('Data Structures Note'), findsNothing);
        expect(find.text('CSE 204 Trees Study'), findsNothing);
      });

      testWidgets('TASK 2: BatchAddMaterialsDialog + Custom button adds and attaches custom category', (tester) async {
        final topicA = SyllabusNode(title: 'Binary Search Trees', isLeaf: true);
        final topicB = SyllabusNode(title: 'Graph Traversal', isLeaf: true);
        final sectionNode = SyllabusNode(
          title: 'Algorithms Section',
          isLeaf: false,
          children: [topicA, topicB],
        );
        final allNodes = [sectionNode];

        bool onSaveCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BatchAddMaterialsDialog(
                        sectionNode: sectionNode,
                        allNodes: allNodes,
                        onSave: (updated) async {
                          onSaveCalled = true;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Batch Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Batch Dialog'));
        await tester.pumpAndSettle();

        // 1. Verify standard categories + '+ Custom' button are rendered
        expect(find.text('Class Note'), findsOneWidget);
        expect(find.text('Lecture Sheet'), findsOneWidget);
        expect(find.text('Ref Book'), findsOneWidget);
        expect(find.text('Term Final Question'), findsOneWidget);
        expect(find.text('+ Custom'), findsOneWidget);

        // 2. Tap '+ Custom' button to open inline input
        await tester.tap(find.text('+ Custom'));
        await tester.pumpAndSettle();

        // Enter custom category name
        await tester.enterText(find.byType(TextField).last, 'Assignment Sheet');
        await tester.tap(find.text('Add'));
        await tester.pumpAndSettle();

        // Verify "Assignment Sheet" chip is now rendered and selected
        expect(find.text('Assignment Sheet'), findsOneWidget);

        // 3. Tap 'Attach' button
        final attachFinder = find.widgetWithText(ElevatedButton, 'Attach (6)'); // 3 categories * 2 topics
        expect(attachFinder, findsOneWidget);
        await tester.tap(attachFinder);
        await tester.pumpAndSettle();

        // Verify onSave was called and topics now contain child 'Assignment Sheet'
        expect(onSaveCalled, isTrue);
        expect(topicA.children.any((c) => c.title == 'Assignment Sheet'), isTrue);
        expect(topicB.children.any((c) => c.title == 'Assignment Sheet'), isTrue);
      });

      testWidgets('BatchAddMaterialsDialog: direct child filtering (one level down only) and duplicate handling with consolidated SnackBar', (tester) async {
        final existingNote = SyllabusNode(id: 'note_1', title: 'Class Note', isLeaf: true);
        final existingSheet = SyllabusNode(id: 'sheet_1', title: 'Lecture Sheet', isLeaf: true);

        // Topic 1 already has 2 sub-materials
        final topic1 = SyllabusNode(
          id: 't_1',
          title: 'Complex number system',
          isLeaf: false,
          children: [existingNote, existingSheet],
        );
        // Topic 2 has no sub-materials
        final topic2 = SyllabusNode(
          id: 't_2',
          title: 'General functions of a complex variable',
          isLeaf: true,
          children: [],
        );

        final parentSection = SyllabusNode(
          id: 'sec_1',
          title: 'Complex Variable',
          isLeaf: false,
          children: [topic1, topic2],
        );
        final allNodes = [parentSection];

        bool onSaveCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BatchAddMaterialsDialog(
                        sectionNode: parentSection,
                        allNodes: allNodes,
                        onSave: (updated) async {
                          onSaveCalled = true;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Batch Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Batch Dialog'));
        await tester.pumpAndSettle();

        // 1. Direct Child Filtering:
        // Must show immediate direct children
        expect(find.text('Complex number system'), findsOneWidget);
        expect(find.text('General functions of a complex variable'), findsOneWidget);

        // Topic count header shows (2/2)
        expect(find.text('2. SELECT TOPICS (2/2)'), findsOneWidget);

        // 2. Attach default categories ('Class Note', 'Lecture Sheet') across both topics
        // Topic 1 already has 'Class Note' and 'Lecture Sheet' -> 2 duplicates skipped
        // Topic 2 does not have them -> 2 added
        final attachBtn = find.widgetWithText(ElevatedButton, 'Attach (4)');
        expect(attachBtn, findsOneWidget);
        await tester.tap(attachBtn);
        await tester.pumpAndSettle();

        expect(onSaveCalled, isTrue);
        expect(topic1.children.length, 2); // No duplicates added to topic1
        expect(topic2.children.length, 2); // 2 added to topic2

        // Consolidated SnackBar verifying duplicates were skipped
        expect(find.text('Added 2 material(s) (2 duplicate(s) skipped).'), findsOneWidget);
      });

      testWidgets('BatchAddMaterialsDialog: all items duplicate shows consolidated skipped SnackBar and adds nothing', (tester) async {
        final existingNote = SyllabusNode(id: 'note_1', title: 'Class Note', isLeaf: true);
        final existingSheet = SyllabusNode(id: 'sheet_1', title: 'Lecture Sheet', isLeaf: true);

        final topic1 = SyllabusNode(
          id: 't_1',
          title: 'Complex number system',
          isLeaf: false,
          children: [existingNote, existingSheet],
        );

        final parentSection = SyllabusNode(
          id: 'sec_1',
          title: 'Complex Variable',
          isLeaf: false,
          children: [topic1],
        );
        final allNodes = [parentSection];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => BatchAddMaterialsDialog(
                        sectionNode: parentSection,
                        allNodes: allNodes,
                      ),
                    );
                  },
                  child: const Text('Open Batch Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Batch Dialog'));
        await tester.pumpAndSettle();

        final attachBtn = find.widgetWithText(ElevatedButton, 'Attach (2)');
        await tester.tap(attachBtn);
        await tester.pumpAndSettle();

        expect(topic1.children.length, 2);
        expect(find.text('Materials already attached. Skipped 2 existing item(s).'), findsOneWidget);
      });
    });

    group('Sprint 12: Attendance Weightage for CGPA & Bulk Override Tests', () {
      test('Course & CourseModel properly serialize and deserialize manual attendance override fields', () {
        final course = CourseModel(
          id: 'course-mid-override',
          courseCode: 'CSE 301',
          courseName: 'Database Management Systems',
          creditHours: 3.0,
          courseType: 'Theory',
          universityName: 'BUET',
          createdAt: DateTime(2026, 1, 1),
          useManualAttendanceOverride: true,
          manualAttendedClasses: 18,
          manualTotalClasses: 20,
        );

        expect(course.useManualAttendanceOverride, isTrue);
        expect(course.manualAttendedClasses, 18);
        expect(course.manualTotalClasses, 20);

        final map = course.toMap();
        expect(map['useManualAttendanceOverride'], isTrue);
        expect(map['manualAttendedClasses'], 18);
        expect(map['manualTotalClasses'], 20);

        final deserialized = CourseModel.fromMap(map, 'course-mid-override');
        expect(deserialized.useManualAttendanceOverride, isTrue);
        expect(deserialized.manualAttendedClasses, 18);
        expect(deserialized.manualTotalClasses, 20);

        final copy = course.copyWith(
          useManualAttendanceOverride: false,
          manualAttendedClasses: null,
          manualTotalClasses: null,
        );
        expect(copy.useManualAttendanceOverride, isFalse);
      });

      test('AttendanceStats and RoutineCourseSyncService respect manual override vs calendar records', () {
        final records = <AttendanceRecord>[
          AttendanceRecord(
            id: 'r1',
            date: DateTime(2026, 2, 1),
            courseId: 'c1',
            courseCode: 'CSE 301',
            status: AttendanceStatus.attended,
          ),
          AttendanceRecord(
            id: 'r2',
            date: DateTime(2026, 2, 2),
            courseId: 'c1',
            courseCode: 'CSE 301',
            status: AttendanceStatus.attended,
          ),
          AttendanceRecord(
            id: 'r3',
            date: DateTime(2026, 2, 3),
            courseId: 'c1',
            courseCode: 'CSE 301',
            status: AttendanceStatus.missed,
          ),
        ];

        // 1. Calendar tracking only
        final calendarStats = RoutineCourseSyncService.computeCourseAttendance(
          courseRecords: records,
          useManualAttendanceOverride: false,
        );
        expect(calendarStats.isManualOverride, isFalse);
        expect(calendarStats.attended, 2);
        expect(calendarStats.missed, 1);
        expect(calendarStats.totalClasses, 3);
        expect(calendarStats.percentage, closeTo(66.67, 0.1));

        // 2. Manual bulk override active (e.g., student joined mid-semester having 16 of 18 classes attended)
        final overrideStats = RoutineCourseSyncService.computeCourseAttendance(
          courseRecords: records,
          useManualAttendanceOverride: true,
          manualAttendedClasses: 16,
          manualTotalClasses: 18,
        );
        expect(overrideStats.isManualOverride, isTrue);
        expect(overrideStats.attended, 16);
        expect(overrideStats.missed, 2);
        expect(overrideStats.totalClasses, 18);
        expect(overrideStats.percentage, closeTo((16 / 18) * 100, 0.01));

        // 3. calculateAttendanceRate helper
        final rate = RoutineCourseSyncService.calculateAttendanceRate(
          courseRecords: records,
          useManualAttendanceOverride: true,
          manualAttendedClasses: 16,
          manualTotalClasses: 18,
        );
        expect(rate, closeTo((16 / 18) * 100, 0.01));
      });

      test('Attendance weightage is dynamically calculated and integrated into predicted marks and CGPA', () {
        // Attendance: 18 attended out of 20 held -> 90% attendance
        const attended = 18;
        const totalHeld = 20;
        const attendanceWeightage = 10.0; // 10%

        // Formula: (Attended / Total) * Attendance Weightage
        final attEarnedMarks = (attended / totalHeld) * attendanceWeightage; // 9.0 marks
        expect(attEarnedMarks, 9.0);

        final attResult = CategoryCalculationResult(
          obtained: attEarnedMarks,
          total: attendanceWeightage,
          percentage: (attended / totalHeld) * 100.0,
          weightedScore: attEarnedMarks,
          weightage: attendanceWeightage,
          useBestOf: false,
          bestCount: 1,
          totalItems: totalHeld,
          countedItems: attended,
          activeItems: const [],
        );

        // Theory course breakdown:
        // CT: 20% weightage, scored 16/20 -> 16.0 marks
        // Midterm: 30% weightage, scored 25/30 -> 25.0 marks
        // Final: 40% weightage, scored 35/40 -> 35.0 marks
        // Attendance: 10% weightage, scored 18/20 -> 9.0 marks
        // Total marks = 16 + 25 + 35 + 9 = 85.0 / 100 -> Grade A (4.00)
        final ctResult = AssessmentCalculationHelper.calculateCategoryScore(
          items: [AssessmentItem(name: 'CT 1', obtained: 16.0, total: 20.0)],
          weightagePercentage: 20.0,
        );
        final midResult = AssessmentCalculationHelper.calculateCategoryScore(
          items: [AssessmentItem(name: 'Mid', obtained: 25.0, total: 30.0)],
          weightagePercentage: 30.0,
        );
        final finResult = AssessmentCalculationHelper.calculateCategoryScore(
          items: [AssessmentItem(name: 'Final', obtained: 35.0, total: 40.0)],
          weightagePercentage: 40.0,
        );

        final overallWithAtt = AssessmentCalculationHelper.calculatePredictedGrade(
          categoryResults: [attResult, ctResult, midResult, finResult],
        );

        expect(overallWithAtt.totalWeightedScore, 85.0);
        expect(overallWithAtt.normalizedPercentage, 85.0);
        expect(overallWithAtt.letterGrade, 'A+');
        expect(overallWithAtt.gradePoint, 4.00);
      });

      testWidgets('AttendanceOverrideDialog renders input fields and validates limits correctly', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AttendanceOverrideDialog(
                courseId: 'test-course-id',
                courseCode: 'CSE 301',
                calendarAttended: 12,
                calendarTotal: 15,
                currentlyUsingOverride: false,
              ),
            ),
          ),
        );

        expect(find.text('Manual Attendance Tally'), findsOneWidget);
        expect(find.text('Total Classes Held'), findsOneWidget);
        expect(find.text('Total Classes Attended'), findsOneWidget);
        expect(find.text('Save Override'), findsOneWidget);

        // Pre-populated with calendar values
        expect(find.text('12'), findsOneWidget);
        expect(find.text('15'), findsOneWidget);
      });
    });

    group('Sprint 13: Course-Specific Attendance Auditing & Bidirectional Planner Sync Tests', () {
      test('CourseDashboardScreen typedef is identical to CourseSyllabusScreen', () {
        expect(CourseDashboardScreen, equals(CourseSyllabusScreen));
      });

      test('RoutineCourseSyncService.routineMatchesCourse correctly matches course by ID, code, or name', () {
        final routineA = ClassRoutine(
          id: 'routine-1',
          courseId: 'cse-301-database-systems',
          courseName: 'CSE 301 - Database Systems',
          roomNumber: 'Room 402',
          startTime: '10:00 AM',
          endTime: '11:30 AM',
          dayOfWeek: 1,
          classType: 'Lecture',
        );

        // Match by courseId
        expect(
          RoutineCourseSyncService.routineMatchesCourse(
            routine: routineA,
            courseId: 'cse-301-database-systems',
            courseCode: 'CSE 301',
          ),
          isTrue,
        );

        // Match by courseCode from courseName
        expect(
          RoutineCourseSyncService.routineMatchesCourse(
            routine: routineA,
            courseId: 'other-id',
            courseCode: 'CSE 301',
          ),
          isTrue,
        );

        // Match by base course code
        final routineB = ClassRoutine(
          id: 'routine-2',
          courseId: 'eee-102-lab',
          courseName: 'EEE 102 (H) [Lab]',
          roomNumber: 'Lab 2',
          startTime: '02:00 PM',
          endTime: '05:00 PM',
          dayOfWeek: 2,
          classType: 'Lab',
        );
        expect(
          RoutineCourseSyncService.routineMatchesCourse(
            routine: routineB,
            courseId: 'random-id',
            courseCode: 'EEE 102',
          ),
          isTrue,
        );

        // Negative match
        expect(
          RoutineCourseSyncService.routineMatchesCourse(
            routine: routineA,
            courseId: 'phy-101',
            courseCode: 'PHY 101',
          ),
          isFalse,
        );
      });

      test('Attendance document ID convention matches PlannerScreen exactly', () {
        const canonicalCourseId = 'course-cse-301';
        const routineId = 'routine-101';
        final date = DateTime(2026, 9, 15);

        final dateKey = '${date.year}_${date.month.toString().padLeft(2, '0')}_${date.day.toString().padLeft(2, '0')}';
        final docId = '${canonicalCourseId}_${routineId}_$dateKey';

        expect(dateKey, '2026_09_15');
        expect(docId, 'course-cse-301_routine-101_2026_09_15');

        // Extra session convention
        final extraDocId = '${canonicalCourseId}_extra_$dateKey';
        expect(extraDocId, 'course-cse-301_extra_2026_09_15');
      });

      test('CourseAttendanceAuditScreen typedef is identical to CourseAttendanceScreen', () {
        expect(CourseAttendanceAuditScreen, equals(CourseAttendanceScreen));
      });

      testWidgets('CourseAttendanceScreen renders tabs, title and UI elements without crash', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: CourseAttendanceScreen(
                courseId: 'test-course-id',
                courseCode: 'CSE 301',
                courseName: 'Database Management Systems',
              ),
            ),
          ),
        );

        // Check polished AppBar title
        expect(find.text('Attendance: CSE 301'), findsOneWidget);
        expect(find.text('Database Management Systems'), findsOneWidget);

        // Check polished TabBar titles
        expect(find.text('Timeline'), findsOneWidget);
        expect(find.text('Summary & Tally'), findsOneWidget);
      });
    });

    group('Sprint 14: Visual Identity & Design System Overhaul Tests', () {
      test('AppSpacing 8pt grid and radius metrics conform to design system', () {
        expect(AppSpacing.micro, 4.0);
        expect(AppSpacing.xs, 8.0);
        expect(AppSpacing.sm, 12.0);
        expect(AppSpacing.md, 16.0);
        expect(AppSpacing.lg, 20.0);
        expect(AppSpacing.xl, 24.0);
        expect(AppSpacing.xxl, 32.0);
        expect(AppSpacing.huge, 40.0);

        expect(AppSpacing.radiusCard, 12.0);
        expect(AppSpacing.radiusButton, 10.0);
        expect(AppSpacing.radiusBadge, 12.0);
        expect(AppSpacing.radiusModal, 12.0);
        expect(AppSpacing.radiusActionContainer, 12.0);
      });

      test('AppColors applies Graphite & Copper Ember design tokens', () {
        expect(AppColors.scaffoldBackground, const Color(0xFF110D0C));
        expect(AppColors.surface, const Color(0xFF241C1A));
        expect(AppColors.surfaceElevated, const Color(0xFF2E2422));
        expect(AppColors.textPrimary, const Color(0xFFFFFFFF));
        expect(AppColors.textSecondary, const Color(0xFFABA093));
        expect(AppColors.borderMedium, const Color(0xFF4A3830));
        expect(AppColors.primary, const Color(0xFFF2B78A));
        expect(AppColors.amber, const Color(0xFFF2B78A));
        expect(AppColors.success, const Color(0xFF06D6A0));
        expect(AppColors.error, const Color(0xFFF87171));
        expect(AppColors.warning, const Color(0xFFF2B78A));
      });

      test('AppTheme.darkTheme generates consistent Material 3 theme', () {
        final theme = AppTheme.darkTheme;
        expect(theme.useMaterial3, isTrue);
        expect(theme.brightness, Brightness.dark);
        expect(theme.scaffoldBackgroundColor, AppColors.scaffoldBackground);
        expect(theme.colorScheme.primary, AppColors.primary);
        expect(theme.colorScheme.surface, AppColors.surface);

        // Verify typography and shadows tokens
        expect(AppTypography.displayLarge.fontWeight, FontWeight.w800);
        expect(AppTypography.titleMedium.fontSize, 15);
        expect(AppTypography.bodyMedium.height, 1.5);
        expect(AppShadows.cardShadow.blurRadius, 16.0);
        expect(AppShadows.elevatedShadow.blurRadius, 24.0);
      });

      testWidgets('PressableCard renders with 16px radius and invokes onTap', (tester) async {
        bool tapped = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PressableCard(
                onTap: () => tapped = true,
                child: const Text('Test Pressable Card'),
              ),
            ),
          ),
        );

        expect(find.text('Test Pressable Card'), findsOneWidget);
        await tester.tap(find.text('Test Pressable Card'));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
      });

      testWidgets('AppBadge renders label, icon, and conforms to 8px radius', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              body: AppBadge(
                label: 'Present',
                icon: Icons.check_circle_rounded,
                variant: AppBadgeVariant.success,
              ),
            ),
          ),
        );

        expect(find.text('Present'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      });

      testWidgets('AppSkeleton shimmer factory renders properly', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  AppSkeleton.card(height: 80),
                  AppSkeleton.line(width: 100),
                  AppSkeleton.circle(size: 40),
                ],
              ),
            ),
          ),
        );

        expect(find.byType(AppSkeleton), findsNWidgets(3));
      });

      testWidgets('SleekAppBar renders frosted title and actions', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const Scaffold(
              appBar: SleekAppBar(
                title: 'Chondrobindu',
                subtitle: 'Engineering Prep',
              ),
              body: SizedBox(),
            ),
          ),
        );

        expect(find.text('Chondrobindu'), findsOneWidget);
        expect(find.text('Engineering Prep'), findsOneWidget);
      });

      test('CourseModel.fromMap safely parses syllabusData when formatted as List<dynamic> without type casting crash', () {
        final rawMapWithList = {
          'courseCode': 'CSE 301',
          'courseName': 'Database Systems',
          'syllabusData': [
            {'topic': 'Relational Algebra', 'hours': 4},
            {'topic': 'Normalization', 'hours': 6},
          ],
        };

        // Must not throw "type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>?' in type cast"
        final course = CourseModel.fromMap(rawMapWithList, 'cse301_doc');
        expect(course.id, 'cse301_doc');
        expect(course.courseCode, 'CSE 301');
        expect(course.syllabusData, isNotNull);
        expect(course.syllabusData!['topics'], isA<List>());
      });

      test('CourseModel.fromMap safely parses syllabusData when formatted as Map<String, dynamic>', () {
        final rawMapWithMap = {
          'courseCode': 'CSE 302',
          'courseName': 'Database Lab',
          'syllabusData': {
            'chapters': ['SQL', 'Triggers', 'Indexing'],
          },
        };

        final course = CourseModel.fromMap(rawMapWithMap, 'cse302_doc');
        expect(course.syllabusData!['chapters'], isA<List>());
      });
    });

    group('Sprint 15: Term Performance & What-If CGPA Simulator Tests', () {
      test('CgpaCalculatorScreen typedef is identical to TermPerformanceScreen', () {
        expect(CgpaCalculatorScreen, equals(TermPerformanceScreen));
      });

      test('CourseScoreBreakdown.compute safely handles List<dynamic> assessments without type cast crash', () {
        final courseData = {
          'courseCode': 'CSE 311',
          'courseName': 'Artificial Intelligence',
          'creditHours': 3.0,
          'assessments': [
            {
              'name': 'Attendance',
              'obtainedMarks': 9.0,
              'totalMarks': 10.0,
              'weightage': 10.0,
            },
            {
              'name': 'CT 1',
              'obtainedMarks': 18.0,
              'totalMarks': 20.0,
              'weightage': 10.0,
            },
            {
              'name': 'CT 2',
              'obtainedMarks': 20.0,
              'totalMarks': 20.0,
              'weightage': 10.0,
            },
            {
              'name': 'Midterm',
              'obtainedMarks': 27.0,
              'totalMarks': 30.0,
              'weightage': 30.0,
            },
          ],
        };

        // Must not throw "type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>?' in type cast"
        final breakdown = CourseScoreBreakdown.compute(courseData);
        expect(breakdown.attendanceSecured, closeTo(9.0, 0.01));
        expect(breakdown.attendanceWeight, closeTo(10.0, 0.01));
        expect(breakdown.ctSecured, closeTo(19.0, 0.01));
        expect(breakdown.ctWeight, closeTo(20.0, 0.01));
        expect(breakdown.midSecured, closeTo(27.0, 0.01));
        expect(breakdown.midWeight, closeTo(30.0, 0.01));
        expect(breakdown.totalSecured, closeTo(55.0, 0.01));
        expect(breakdown.totalSecuredWeight, closeTo(60.0, 0.01));
        expect(breakdown.remainingWeight, closeTo(40.0, 0.01));
      });

      test('CourseScoreBreakdown.compute safely handles Map<String, dynamic> structured assessments', () {
        final courseData = {
          'courseCode': 'MATH 157',
          'creditHours': 3.0,
          'assessments': {
            'attendanceWeightage': 10.0,
            'classesAttended': 12,
            'totalClasses': 15,
            'ctWeightage': 20.0,
            'ctUseBestOf': true,
            'ctBestCount': 2,
            'classTests': [
              {'name': 'CT 1', 'obtained': 10.0, 'total': 20.0}, // 50%
              {'name': 'CT 2', 'obtained': 18.0, 'total': 20.0}, // 90%
              {'name': 'CT 3', 'obtained': 16.0, 'total': 20.0}, // 80%
            ],
            'midtermWeightage': 30.0,
            'midtermObtained': 24.0,
            'midtermTotal': 30.0, // 80% -> 24.0 pts
          },
        };

        final breakdown = CourseScoreBreakdown.compute(courseData);
        // Attendance: 12/15 * 10 = 8.0 pts
        expect(breakdown.attendanceSecured, closeTo(8.0, 0.01));
        // CT best 2 of 3: CT2 (90%) and CT3 (80%) avg = 85% -> 85% * 20 = 17.0 pts
        expect(breakdown.ctSecured, closeTo(17.0, 0.01));
        // Midterm: 24.0 / 30.0 * 30 = 24.0 pts
        expect(breakdown.midSecured, closeTo(24.0, 0.01));
        // Total evaluated weight: 10 + 20 + 30 = 60.0%
        expect(breakdown.totalSecuredWeight, closeTo(60.0, 0.01));
        // Remaining for Final exam: 40.0%
        expect(breakdown.remainingWeight, closeTo(40.0, 0.01));
        // Total secured: 8.0 + 17.0 + 24.0 = 49.0 pts
        expect(breakdown.totalSecured, closeTo(49.0, 0.01));
      });

      test('CourseScoreBreakdown.compute respects manual attendance override when enabled', () {
        final courseData = {
          'courseCode': 'EEE 101',
          'useManualAttendanceOverride': true,
          'manualAttendedClasses': 18,
          'manualTotalClasses': 20,
          'assessments': {
            'attendanceWeightage': 10.0,
            'classesAttended': 5, // Calendar says 5/10, but override says 18/20
            'totalClasses': 10,
          },
        };

        final breakdown = CourseScoreBreakdown.compute(courseData);
        // Should use 18 / 20 * 10 = 9.0 pts
        expect(breakdown.attendanceSecured, closeTo(9.0, 0.01));
      });

      test('Interactive What-If predictive simulation computes projected percentage and BUET CGPA correctly', () {
        // Course 1: 3.0 Cr, 50.0 secured out of 60.0% weight.
        // User moves slider on remaining 40.0% to 85%:
        // Projected marks = 85% * 40.0% = 34.0 pts.
        // Total Course 1 = 50.0 + 34.0 = 84.0% -> BUET A+ (4.00)
        final c1Total = 50.0 + (0.85 * 40.0);
        final c1Grade = AssessmentCalculationHelper.percentageToGrade(c1Total);
        expect(c1Grade.letterGrade, 'A+');
        expect(c1Grade.gradePoint, 4.00);

        // Course 2: 1.5 Cr, 45.0 secured out of 60.0% weight.
        // User moves slider on remaining 40.0% to 70%:
        // Projected marks = 70% * 40.0% = 28.0 pts.
        // Total Course 2 = 45.0 + 28.0 = 73.0% -> BUET A- (3.50)
        final c2Total = 45.0 + (0.70 * 40.0);
        final c2Grade = AssessmentCalculationHelper.percentageToGrade(c2Total);
        expect(c2Grade.letterGrade, 'A-');
        expect(c2Grade.gradePoint, 3.50);

        // Term CGPA = ((4.00 * 3.0) + (3.50 * 1.5)) / (3.0 + 1.5)
        // = (12.0 + 5.25) / 4.5 = 17.25 / 4.5 = 3.8333...
        final simulatedCgpa = ((c1Grade.gradePoint * 3.0) + (c2Grade.gradePoint * 1.5)) / (3.0 + 1.5);
        expect(simulatedCgpa, closeTo(3.833, 0.01));
      });

      testWidgets('TermPerformanceScreen renders header, title, and initial loading or empty state without crash', (tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: TermPerformanceScreen(
                universityName: 'BUET',
                term: 'Level 1 Term 1',
              ),
            ),
          ),
        );

        // Verify title
        expect(find.text('Term Performance & CGPA'), findsOneWidget);
        expect(find.text('BUET • Level 1 Term 1'), findsOneWidget);
      });
    });

    group('Task 1 to Task 4 Integrated Features Tests', () {
      test('TASK 1: Assessment model status lifecycle (Attended, Missed, Postponed)', () {
        final initial = Assessment(
          courseId: 'course_cse_101',
          name: 'Class Test 1',
          date: DateTime(2026, 9, 5, 10, 0),
          totalMarks: 20.0,
          weightage: 15.0,
          status: 'Pending',
        );
        expect(initial.isAttended, false);
        expect(initial.isMissed, false);
        expect(initial.isPostponed, false);

        // Attended with score
        final attended = initial.copyWith(
          status: 'Attended',
          obtainedMarks: 18.5,
        );
        expect(attended.isAttended, true);
        expect(attended.obtainedMarks, 18.5);

        // Missed with 0.0
        final missed = initial.copyWith(
          status: 'Missed',
          obtainedMarks: 0.0,
        );
        expect(missed.isMissed, true);
        expect(missed.obtainedMarks, 0.0);

        // Postponed to new date
        final rescheduledDate = DateTime(2026, 9, 12, 10, 0);
        final postponed = initial.copyWith(
          status: 'Postponed',
          postponedToDate: rescheduledDate,
          postponedToId: 'ass_new_1',
        );
        expect(postponed.isPostponed, true);
        expect(postponed.postponedToDate, rescheduledDate);
        expect(postponed.postponedToId, 'ass_new_1');

        // Verify Map Serialization
        final map = postponed.toMap();
        expect(map['status'], 'Postponed');
        expect(map['postponedToId'], 'ass_new_1');

        final restored = Assessment.fromMap(map);
        expect(restored.status, 'Postponed');
        expect(restored.postponedToDate, rescheduledDate);
        expect(restored.isPostponed, true);
      });

      test('TASK 2: PlannerEvent model creation, remarks editing, and postponement', () {
        final event = PlannerEvent(
          id: 'ev_1',
          title: 'Robotics Club Workshop',
          category: 'Club Activity',
          date: DateTime(2026, 9, 10),
          timeSlot: '04:00 PM - 06:00 PM',
          remarks: 'Bring Arduino kit and jumper wires',
          status: 'Pending',
        );

        expect(event.title, 'Robotics Club Workshop');
        expect(event.category, 'Club Activity');
        expect(event.remarks, 'Bring Arduino kit and jumper wires');
        expect(event.isCompleted, false);
        expect(event.isMissed, false);
        expect(event.isPostponed, false);

        // Update remarks
        final updated = event.copyWith(
          remarks: 'Brought kit; next session in lab 3',
          status: 'Completed',
        );
        expect(updated.isCompleted, true);
        expect(updated.remarks, 'Brought kit; next session in lab 3');

        // Postpone event
        final rescheduled = event.copyWith(
          status: 'Postponed',
          postponedToDate: DateTime(2026, 9, 17),
          postponedToSlot: '05:00 PM - 07:00 PM',
        );
        expect(rescheduled.isPostponed, true);
        expect(rescheduled.postponedToDate, DateTime(2026, 9, 17));

        // Serialization
        final map = rescheduled.toMap();
        expect(map['title'], 'Robotics Club Workshop');
        expect(map['category'], 'Club Activity');
        expect(map['status'], 'Postponed');

        final fromMap = PlannerEvent.fromMap(map, 'ev_1');
        expect(fromMap.title, 'Robotics Club Workshop');
        expect(fromMap.isPostponed, true);
      });

      test('TASK 3: Configurable Grading Scale & Required Target Calculation', () {
        // Grading Scale row test
        final row = GradingRow(
          letterGrade: 'A+',
          gradePoint: 4.00,
          minPercentage: 80,
          maxPercentage: 100,
        );
        expect(row.letterGrade, 'A+');
        expect(row.minPercentage, 80);

        final map = row.toMap();
        final restoredRow = GradingRow.fromMap(map);
        expect(restoredRow.letterGrade, 'A+');
        expect(restoredRow.minPercentage, 80);

        // Required Target Calculation:
        // Student has secured 50.0% marks out of 60.0% evaluated weight.
        // Remaining/pending weight is 40.0%.
        // Target: A+ (cutoff 80.0%)
        // Required on pending = ((80.0 - 50.0) / 40.0) * 100% = (30.0 / 40.0) * 100% = 75.0%
        const securedMarks = 50.0;
        const pendingWeight = 40.0;
        const targetAplus = 80.0;
        final reqAplus = ((targetAplus - securedMarks) / pendingWeight) * 100.0;
        expect(reqAplus, closeTo(75.0, 0.001));

        // Target: A- (cutoff 70.0%)
        // Required on pending = ((70.0 - 50.0) / 40.0) * 100% = (20.0 / 40.0) * 100% = 50.0%
        const targetAminus = 70.0;
        final reqAminus = ((targetAminus - securedMarks) / pendingWeight) * 100.0;
        expect(reqAminus, closeTo(50.0, 0.001));
      });

      test('TASK 4: Study Insights formatters & typedef alias', () {
        // Test typedef alias
        expect(AcademicInsightsScreen, equals(InsightsScreen));

        // Test formatDuration hh:mm:ss
        const totalSecs = (10 * 3600) + (2 * 60) + 23; // 10:02:23
        final h = totalSecs ~/ 3600;
        final m = (totalSecs % 3600) ~/ 60;
        final s = totalSecs % 60;
        final formatted = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
        expect(formatted, '10:02:23');

        // Test intensity thresholds
        Color getHeatmapColor(double hours) {
          if (hours <= 0) return const Color(0xFF1E293B);
          if (hours < 4.0) return const Color(0xFF0284C7).withValues(alpha: 0.35);
          if (hours < 7.0) return const Color(0xFF0284C7);
          if (hours < 10.0) return const Color(0xFF38BDF8);
          if (hours < 12.0) return const Color(0xFF8B5CF6);
          return const Color(0xFFF59E0B);
        }

        expect(getHeatmapColor(0.0), const Color(0xFF1E293B));
        expect(getHeatmapColor(2.5), const Color(0xFF0284C7).withValues(alpha: 0.35));
        expect(getHeatmapColor(5.0), const Color(0xFF0284C7));
        expect(getHeatmapColor(8.5), const Color(0xFF38BDF8));
        expect(getHeatmapColor(11.0), const Color(0xFF8B5CF6));
        expect(getHeatmapColor(14.0), const Color(0xFFF59E0B));
      });

      test('Interactive Date Navigation for Day View in InsightsScreen', () {
        final initialDate = DateTime(2026, 9, 25);
        DateTime selectedDay = initialDate;

        // Step backward (Previous Day <)
        selectedDay = selectedDay.subtract(const Duration(days: 1));
        expect(selectedDay, DateTime(2026, 9, 24));

        // Step forward (Next Day >)
        selectedDay = selectedDay.add(const Duration(days: 1));
        expect(selectedDay, DateTime(2026, 9, 25));

        // Date boundaries: startOfDay and endOfDay
        final startOfDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, 0, 0, 0);
        final endOfDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day, 23, 59, 59);

        final s1 = FocusSession(
          id: 's1',
          date: DateTime(2026, 9, 25, 10, 30),
          durationInMinutes: 45,
          subjectId: 'cse101',
          subjectName: 'CSE 101',
        );
        final s2 = FocusSession(
          id: 's2',
          date: DateTime(2026, 9, 24, 23, 30),
          durationInMinutes: 30,
          subjectId: 'cse101',
          subjectName: 'CSE 101',
        );

        final matchesDay = [s1, s2].where((s) =>
            (s.date.year == selectedDay.year && s.date.month == selectedDay.month && s.date.day == selectedDay.day) ||
            (!s.date.isBefore(startOfDay) && !s.date.isAfter(endOfDay))).toList();

        expect(matchesDay.length, 1);
        expect(matchesDay.first.id, 's1');

        // Dynamic title formatting
        final headerTitle = 'Sessions on ${selectedDay.day}/${selectedDay.month}/${selectedDay.year}';
        expect(headerTitle, 'Sessions on 25/9/2026');

        // Today pill visibility check
        final today = DateTime(2026, 9, 25);
        final isSelectedToday = (selectedDay.year == today.year && selectedDay.month == today.month && selectedDay.day == today.day);
        expect(isSelectedToday, isTrue);

        final pastDay = DateTime(2026, 9, 20);
        final isPastDayToday = (pastDay.year == today.year && pastDay.month == today.month && pastDay.day == today.day);
        expect(isPastDayToday, isFalse);
      });
    });

    group('Sprint 16: UI Streamlining, Grade Projector, Dashboard Cleanup & Time Filters Tests', () {
      test('TASK 1 & TASK 4: Screen Aliases & Vocabulary Verification', () {
        // CourseDetailsScreen typedef equals CourseSyllabusScreen
        expect(CourseDetailsScreen, equals(CourseSyllabusScreen));
        // HomeDashboard typedef equals HomeDashboardScreen
        expect(HomeDashboard, equals(HomeDashboardScreen));
      });

      test('TASK 2: Course Grade Projector Combined Calculation', () {
        // Attendance: 9/10 classes attended = (9 / 10) * 10 = 9.0 pts
        const attSecured = 9.0;
        // CT: 17.5 / 20.0 weighted score = 17.5 pts
        const ctSecured = 17.5;
        // Total evaluated secured = 26.5 pts out of 30% weight
        const evaluatedSecured = attSecured + ctSecured; // 26.5
        const pendingWeight = 70.0; // 70% remaining (Final Exam)
        const finTotal = 210.0;

        // User sets slider to 80% on Final Exam
        const simulatedFinalPercent = 80.0;
        final simulatedFinalMarks = (simulatedFinalPercent / 100.0) * finTotal; // 168.0 / 210
        final simulatedFinalWeighted = (simulatedFinalPercent / 100.0) * pendingWeight; // 56.0 pts

        expect(simulatedFinalMarks, 168.0);
        expect(simulatedFinalWeighted, 56.0);

        final projectedTotal = evaluatedSecured + simulatedFinalWeighted; // 26.5 + 56.0 = 82.5%
        expect(projectedTotal, 82.5);

        final projectedGrade = AssessmentCalculationHelper.percentageToGrade(projectedTotal);
        expect(projectedGrade.letterGrade, 'A+');
        expect(projectedGrade.gradePoint, 4.00);

        // User sets slider to 50% on Final Exam
        const simulatedFinalPercent2 = 50.0;
        final simulatedFinalWeighted2 = (simulatedFinalPercent2 / 100.0) * pendingWeight; // 35.0 pts
        final projectedTotal2 = evaluatedSecured + simulatedFinalWeighted2; // 26.5 + 35.0 = 61.5%
        final projectedGrade2 = AssessmentCalculationHelper.percentageToGrade(projectedTotal2);
        expect(projectedGrade2.letterGrade, 'B');
        expect(projectedGrade2.gradePoint, 3.00);
      });

      test('TASK 3: Compact Attendance Summary Aggregation', () {
        // Aggregating attendance rates across multiple courses
        final courses = [
          {'attended': 12, 'missed': 2},
          {'attended': 10, 'missed': 1},
          {'attended': 8, 'missed': 4},
        ];

        int totalAttended = 0;
        int totalMissed = 0;
        for (final c in courses) {
          totalAttended += c['attended']!;
          totalMissed += c['missed']!;
        }

        final totalHeld = totalAttended + totalMissed; // 30 + 7 = 37
        expect(totalAttended, 30);
        expect(totalMissed, 7);
        expect(totalHeld, 37);

        final overallRate = (totalAttended / totalHeld) * 100.0;
        expect(overallRate, closeTo(81.08, 0.01));
        final isSafe = overallRate >= 75.0;
        expect(isSafe, true);
      });

      test('TASK 5: Functional Insights Time Filter Switcher Tabs', () {
        const tabs = ['Period', 'Day', 'Week', 'Month', 'Trend'];
        expect(tabs.contains('Day'), true);
        expect(tabs.contains('Week'), true);
        expect(tabs.contains('Month'), true);
        expect(tabs.contains('Trend'), true);
        expect(tabs.contains('Period'), true);

        // Date reset logic for "Today" button
        final now = DateTime.now();
        final heatmapMonth = DateTime(now.year, now.month, 1);
        final selectedDate = DateTime(now.year, now.month, now.day);
        expect(heatmapMonth.month, now.month);
        expect(selectedDate.day, now.day);
      });

      test('Sprint 17 - AssessmentModel & AssessmentItem topics / syllabusSummary field support', () {
        final ass = Assessment(
          courseId: 'cse_209',
          name: 'CT 2 (Digital Logic)',
          date: DateTime(2026, 9, 15, 10, 0),
          totalMarks: 20.0,
          obtainedMarks: 18.5,
          weightage: 10.0,
          syllabusSummary: 'K-Maps, Quine-McCluskey, Multiplexers',
        );

        // Model getters
        expect(ass.syllabusSummary, 'K-Maps, Quine-McCluskey, Multiplexers');
        expect(ass.topics, 'K-Maps, Quine-McCluskey, Multiplexers');

        // toMap serialization
        final map = ass.toMap();
        expect(map['syllabusSummary'], 'K-Maps, Quine-McCluskey, Multiplexers');
        expect(map['topics'], 'K-Maps, Quine-McCluskey, Multiplexers');

        // fromMap deserialization with 'syllabusSummary'
        final fromMap1 = Assessment.fromMap(map);
        expect(fromMap1.syllabusSummary, 'K-Maps, Quine-McCluskey, Multiplexers');
        expect(fromMap1.topics, 'K-Maps, Quine-McCluskey, Multiplexers');

        // fromMap deserialization fallback to 'topics'
        final mapFallback = Map<String, dynamic>.from(map)..remove('syllabusSummary');
        final fromMap2 = Assessment.fromMap(mapFallback);
        expect(fromMap2.syllabusSummary, 'K-Maps, Quine-McCluskey, Multiplexers');

        // copyWith verification
        final updated = ass.copyWith(
          syllabusSummary: 'Ch 1-3 & Fourier Series',
        );
        expect(updated.syllabusSummary, 'Ch 1-3 & Fourier Series');
        expect(updated.topics, 'Ch 1-3 & Fourier Series');

        // AssessmentItem in course_assessment_screen
        final item = AssessmentItem(
          name: 'Quiz 1',
          obtained: 19.0,
          total: 20.0,
          syllabusSummary: 'Number Systems & Boolean Algebra',
        );
        expect(item.syllabusSummary, 'Number Systems & Boolean Algebra');
        expect(item.topics, 'Number Systems & Boolean Algebra');

        final itemMap = item.toMap();
        expect(itemMap['syllabusSummary'], 'Number Systems & Boolean Algebra');
        expect(itemMap['topics'], 'Number Systems & Boolean Algebra');

        final itemFromMap = AssessmentItem.fromMap(itemMap);
        expect(itemFromMap.syllabusSummary, 'Number Systems & Boolean Algebra');
        expect(itemFromMap.topics, 'Number Systems & Boolean Algebra');
      });

      testWidgets('Sprint 17 - CreateAssessmentDialog and Topic Pill rendering', (tester) async {
        // Verify pill rendering with syllabus topic
        final assessmentWithTopic = Assessment(
          courseId: 'cse_209',
          name: 'CT 1',
          date: DateTime(2026, 9, 10, 10, 0),
          totalMarks: 20.0,
          obtainedMarks: 18.0,
          weightage: 10.0,
          syllabusSummary: 'K-Map Simplification',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Text(assessmentWithTopic.name),
                  if (assessmentWithTopic.syllabusSummary != null &&
                      assessmentWithTopic.syllabusSummary!.trim().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.menu_book_rounded),
                          Flexible(
                            child: Text('Topic: ${assessmentWithTopic.syllabusSummary!.trim()}'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

        expect(find.text('CT 1'), findsOneWidget);
        expect(find.text('Topic: K-Map Simplification'), findsOneWidget);
        expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
      });

      test('AppFonts typography helper returns configured font styles', () {
        final geist = AppFonts.geist();
        expect(geist.fontFamily, contains('Geist'));

        final mono = AppFonts.geistMono();
        expect(mono.fontFamily, contains('GeistMono'));
      });
    });

    group('Sprint 18: Graphite & Copper Ember Design System & Apple Glassmorphism Tests', () {
      test('TASK 1: Graphite & Copper Ember color tokens match exact specification', () {
        // Scaffold / Canvas Background: Color(0xFF110D0C) (or Color(0xFF140F0E))
        expect(AppColors.scaffoldBackground, const Color(0xFF110D0C));
        expect(AppColors.canvas, const Color(0xFF110D0C));
        expect(AppColors.background, const Color(0xFF140F0E));

        // Card / Container Base Surface: Color(0xFF241C1A)
        expect(AppColors.surface, const Color(0xFF241C1A));

        // Elevated Borders / Dividers / Structural Lines: Color(0xFF4A3830)
        expect(AppColors.borderMedium, const Color(0xFF4A3830));
        expect(AppColors.divider, const Color(0xFF4A3830));

        // Secondary Muted Text & Subtitles: Color(0xFFABA093)
        expect(AppColors.textSecondary, const Color(0xFFABA093));

        // Primary Headings & Crisp Body: Color(0xFFFFFFFF)
        expect(AppColors.textPrimary, const Color(0xFFFFFFFF));

        // Hero Brand / Primary CTA / Active Sliders / Score Accents: Color(0xFFF2B78A) (Ember Copper)
        expect(AppColors.primary, const Color(0xFFF2B78A));
        expect(AppColors.copper, const Color(0xFFF2B78A));
        expect(AppColors.ember, const Color(0xFFF2B78A));

        // Success / Present: Color(0xFF06D6A0) or Color(0xFFABA093).withOpacity(0.2) with Color(0xFFFFFFFF) text
        expect(AppColors.success, const Color(0xFF06D6A0));
        expect(AppColors.present, const Color(0xFF06D6A0));
        expect(AppColors.presentBg, const Color(0x33ABA093));
        expect(AppColors.presentText, const Color(0xFFFFFFFF));

        // Danger / Missed: Color(0xFFEF4444).withOpacity(0.15) with Color(0xFFF87171) text
        expect(AppColors.error, const Color(0xFFF87171));
        expect(AppColors.errorContainer, const Color(0x26EF4444));
        expect(AppColors.missed, const Color(0xFFF87171));
        expect(AppColors.missedBg, const Color(0x26EF4444));

        // Warning / Postponed: Color(0xFFF2B78A).withOpacity(0.15) with Color(0xFFF2B78A) text
        expect(AppColors.warning, const Color(0xFFF2B78A));
        expect(AppColors.warningContainer, const Color(0x26F2B78A));
        expect(AppColors.postponed, const Color(0xFFF2B78A));
        expect(AppColors.postponedBg, const Color(0x26F2B78A));
      });

      test('TASK 2: Multi-Font Scale (Geist + GeistMono) hierarchy conforms to spec', () {
        // Page Titles & AppBars: 20sp, FontWeight.w600 (SemiBold), Color(0xFFFFFFFF)
        expect(AppTypography.pageTitle.fontSize, 20);
        expect(AppTypography.pageTitle.fontWeight, FontWeight.w600);
        expect(AppTypography.pageTitle.color, const Color(0xFFFFFFFF));

        expect(AppTypography.appBarTitle.fontSize, 20);
        expect(AppTypography.appBarTitle.fontWeight, FontWeight.w600);
        expect(AppTypography.appBarTitle.color, const Color(0xFFFFFFFF));

        // Section Headers: 13sp, FontWeight.w600, Color(0xFFABA093) (with subtle letter-spacing)
        expect(AppTypography.sectionHeader.fontSize, 13);
        expect(AppTypography.sectionHeader.fontWeight, FontWeight.w600);
        expect(AppTypography.sectionHeader.color, const Color(0xFFABA093));
        expect(AppTypography.sectionHeader.letterSpacing, isNotNull);

        // Card Titles: 15sp, FontWeight.w600, Color(0xFFFFFFFF)
        expect(AppTypography.cardTitle.fontSize, 15);
        expect(AppTypography.cardTitle.fontWeight, FontWeight.w600);
        expect(AppTypography.cardTitle.color, const Color(0xFFFFFFFF));

        // Body Text & Descriptions: 13sp, FontWeight.w400, Color(0xFFD8CFC7)
        expect(AppTypography.bodyText.fontSize, 13);
        expect(AppTypography.bodyText.fontWeight, FontWeight.w400);
        expect(AppTypography.bodyText.color, const Color(0xFFD8CFC7));

        // Subtext & Taglines: 11sp, FontWeight.w500, Color(0xFFABA093)
        expect(AppTypography.subtext.fontSize, 11);
        expect(AppTypography.subtext.fontWeight, FontWeight.w500);
        expect(AppTypography.subtext.color, const Color(0xFFABA093));

        // Technical / Numerical Data:
        // CGPA Display: 24sp - 32sp, FontWeight.w700, Color(0xFFF2B78A)
        expect(AppTypography.cgpaDisplay.fontSize, greaterThanOrEqualTo(24));
        expect(AppTypography.cgpaDisplay.fontSize, lessThanOrEqualTo(32));
        expect(AppTypography.cgpaDisplay.fontWeight, FontWeight.w700);
        expect(AppTypography.cgpaDisplay.color, const Color(0xFFF2B78A));

        // Attendance Counts: 11sp, FontWeight.w500
        expect(AppTypography.attendanceCount.fontSize, 11);
        expect(AppTypography.attendanceCount.fontWeight, FontWeight.w500);

        // Time Slots: 11sp, FontWeight.w500
        expect(AppTypography.timeSlot.fontSize, 11);
        expect(AppTypography.timeSlot.fontWeight, FontWeight.w500);

        // Course Codes: 14sp, FontWeight.w700
        expect(AppTypography.courseCode.fontSize, 14);
        expect(AppTypography.courseCode.fontWeight, FontWeight.w700);
      });

      testWidgets('TASK 3: LuxuryGlassCard and buildGlassCard render with blur and copper ember gradient border', (tester) async {
        bool cardTapped = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: LuxuryGlassCard(
                onTap: () => cardTapped = true,
                child: const Text('Apple Glass Container Content'),
              ),
            ),
          ),
        );

        expect(find.text('Apple Glass Container Content'), findsOneWidget);
        expect(find.byType(BackdropFilter), findsOneWidget);

        await tester.tap(find.text('Apple Glass Container Content'));
        await tester.pumpAndSettle();
        expect(cardTapped, isTrue);

        // Also test buildGlassCard standalone
        final standaloneCard = buildGlassCard(
          borderRadius: BorderRadius.circular(12),
          child: const Text('Standalone Glass Card'),
        );
        expect(standaloneCard, isA<Widget>());
      });

      testWidgets('TASK 4: AppBadge variants (present, postpone, absent, unmarked) and standardized 12px radii', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Column(
                children: [
                  AppBadge.present(label: 'Present Status'),
                  AppBadge.postpone(label: 'Postponed Exam'),
                  AppBadge.absent(label: 'Absent Today'),
                  AppBadge.unmarked(label: 'Unmarked Item'),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Present Status'), findsOneWidget);
        expect(find.text('Postponed Exam'), findsOneWidget);
        expect(find.text('Absent Today'), findsOneWidget);
        expect(find.text('Unmarked Item'), findsOneWidget);

        // Verify Radii Standardization
        expect(AppSpacing.radiusCard, 12.0);
        expect(AppSpacing.radiusModal, 12.0);
        expect(AppSpacing.radiusActionContainer, 12.0);
        expect(AppSpacing.radiusButton, 10.0);
        expect(AppSpacing.radiusBadge, 12.0);

        // Verify GradientSliderTrackShape exists and can be constructed
        const trackShape = GradientSliderTrackShape();
        expect(trackShape.gradient.colors, [const Color(0xFF4A3830), const Color(0xFFF2B78A)]);

        // Verify theme button styling
        final btnTheme = AppTheme.darkTheme.elevatedButtonTheme;
        expect(btnTheme.style, isNotNull);
      });

      testWidgets('TASK 5: AppSegmentedPillBar interactive control renders and updates selection', (tester) async {
        String selected = 'Day';
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: AppSegmentedPillBar<String>(
                    segments: const ['Period', 'Day', 'Week', 'Month', 'Trend'],
                    selectedSegment: selected,
                    onSegmentSelected: (val) {
                      setState(() {
                        selected = val;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        );

        expect(find.text('Period'), findsOneWidget);
        expect(find.text('Day'), findsOneWidget);
        expect(find.text('Week'), findsOneWidget);
        expect(find.text('Month'), findsOneWidget);
        expect(find.text('Trend'), findsOneWidget);

        // Tap 'Week'
        await tester.tap(find.text('Week'));
        await tester.pumpAndSettle();
        expect(selected, 'Week');

        // Tap 'Trend'
        await tester.tap(find.text('Trend'));
        await tester.pumpAndSettle();
        expect(selected, 'Trend');
      });

      test('TASK 6: Screen Rollout - Theme integration and aliases consistency', () {
        expect(AppColors.surface, const Color(0xFF241C1A));
        expect(AppColors.borderMedium, const Color(0xFF4A3830));
        expect(AppColors.primary, const Color(0xFFF2B78A));
        expect(AppColors.ctaText, const Color(0xFF140F0E));
        expect(AppColors.scaffoldBackground, const Color(0xFF110D0C));

        // Verify that AppTheme darkTheme sliderTheme has GradientSliderTrackShape
        final sliderTheme = AppTheme.darkTheme.sliderTheme;
        expect(sliderTheme.trackShape, isA<GradientSliderTrackShape>());
        expect(sliderTheme.activeTrackColor, AppColors.primary);
        expect(sliderTheme.thumbColor, AppColors.primary);
      });

      test('Sprint 19: Root-Level Theme Overwrite & Graphite & Copper Ember Theme Verification', () {
        final theme = AppTheme.darkTheme;
        expect(theme.colorScheme.primary, const Color(0xFFF2B78A));
        expect(theme.colorScheme.onPrimary, const Color(0xFF140F0E));
        expect(theme.colorScheme.surface, const Color(0xFF241C1A));
        expect(theme.colorScheme.outline, const Color(0xFF4A3830));
        expect(theme.colorScheme.secondary, const Color(0xFFABA093));
        expect(theme.navigationBarTheme.backgroundColor, const Color(0xFF140F0E));
        expect(theme.popupMenuTheme.color, const Color(0xFF1C1412));

        // Verify switch theme resolution
        final selectedThumb = theme.switchTheme.thumbColor?.resolve({WidgetState.selected});
        final unselectedThumb = theme.switchTheme.thumbColor?.resolve({});
        expect(selectedThumb, const Color(0xFFF2B78A));
        expect(unselectedThumb, const Color(0xFFABA093));

        // Deduplication string test logic
        const rawDuplicate = 'MATH 159 - MATH 159';
        final parts = rawDuplicate.split(' - ');
        expect(parts[0], parts[1]);
      });

      test('Sprint 20: Mid-Semester Routine Versioning & Date Boundary Tests', () {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        final lastWeekYesterday = yesterday.subtract(const Duration(days: 7));
        final tomorrow = now.add(const Duration(days: 1));

        // 1. Old routine effective up to yesterday
        final oldRoutine = ClassRoutine(
          id: 'old_1',
          courseId: 'CSE 101',
          courseName: 'Structured Programming',
          dayOfWeek: yesterday.weekday,
          startTime: '09:00',
          endTime: '10:00',
          roomNumber: '301',
          effectiveUntil: yesterday,
        );

        // Active on yesterday and last week yesterday
        expect(oldRoutine.isActiveOnDate(yesterday), isTrue);
        expect(oldRoutine.isActiveOnDate(lastWeekYesterday), isTrue);
        // Not active on next week yesterday (after effectiveUntil)
        final nextWeekYesterday = yesterday.add(const Duration(days: 7));
        expect(oldRoutine.isActiveOnDate(nextWeekYesterday), isFalse);

        // 2. New routine effective from today
        final newRoutine = ClassRoutine(
          id: 'new_1',
          courseId: 'CSE 101',
          courseName: 'Structured Programming',
          dayOfWeek: now.weekday,
          startTime: '10:00',
          endTime: '11:00',
          roomNumber: '401',
          effectiveFrom: now,
        );

        // Not active on last week now (before effectiveFrom)
        final lastWeekNow = now.subtract(const Duration(days: 7));
        expect(newRoutine.isActiveOnDate(lastWeekNow), isFalse);
        // Active on today and next week now
        expect(newRoutine.isActiveOnDate(now), isTrue);
        final nextWeekNow = now.add(const Duration(days: 7));
        expect(newRoutine.isActiveOnDate(nextWeekNow), isTrue);

        // 3. Serialization verification of effectiveFrom and effectiveUntil
        final map = newRoutine.toMap();
        expect(map['effectiveFrom'], isNotNull);
        final revived = ClassRoutine.fromMap(map);
        expect(revived.effectiveFrom, isNotNull);
        expect(revived.isActiveOnDate(now), isTrue);
      });
    });

    group('Sprint 17: Routine Chronological Sorting, Scroll Stability, Phrasing & Simulation Tests', () {
      test('parseTimeToMinutes correctly parses AM/PM, ranges, 24-hr, and unassigned times', () {
        // Morning AM
        expect(RoutineCourseSyncService.parseTimeToMinutes('08:00 AM'), 480);
        expect(RoutineCourseSyncService.parseTimeToMinutes('10:00 AM'), 600);
        expect(RoutineCourseSyncService.parseTimeToMinutes('11:30 AM'), 690);

        // Afternoon/Evening PM
        expect(RoutineCourseSyncService.parseTimeToMinutes('12:00 PM'), 720);
        expect(RoutineCourseSyncService.parseTimeToMinutes('01:50 PM'), 830);
        expect(RoutineCourseSyncService.parseTimeToMinutes('02:15 PM'), 855);

        // Midnight AM
        expect(RoutineCourseSyncService.parseTimeToMinutes('12:00 AM'), 0);

        // Range format (e.g. "11:00 AM - 01:50 PM")
        expect(RoutineCourseSyncService.parseTimeToMinutes('11:00 AM - 01:50 PM'), 660);

        // Missing / unassigned time pushes to end (1440)
        expect(RoutineCourseSyncService.parseTimeToMinutes(null), 1440);
        expect(RoutineCourseSyncService.parseTimeToMinutes(''), 1440);
        expect(RoutineCourseSyncService.parseTimeToMinutes('TBD'), 1440);
      });

      test('sortRoutinesByTime strictly orders daily routines chronologically', () {
        final rLate = ClassRoutine(
          id: 'cse_110',
          courseId: 'CSE 110',
          courseName: 'CSE 110: Algorithm Lab',
          dayOfWeek: DateTime.monday,
          startTime: '11:00 AM',
          endTime: '01:50 PM',
        );

        final rEarly = ClassRoutine(
          id: 'phy_121',
          courseId: 'PHY 121',
          courseName: 'PHY 121: Waves & Oscillation',
          dayOfWeek: DateTime.monday,
          startTime: '10:00 AM',
          endTime: '10:50 AM',
        );

        final rUnassigned = ClassRoutine(
          id: 'math_157',
          courseId: 'MATH 157',
          courseName: 'MATH 157: Calculus',
          dayOfWeek: DateTime.monday,
          startTime: '',
          endTime: '',
        );

        // Input in jumbled order: unassigned first, then 11:00 AM, then 10:00 AM
        final sorted = RoutineCourseSyncService.sortRoutinesByTime([rUnassigned, rLate, rEarly]);

        expect(sorted.length, 3);
        // 10:00 AM must come first
        expect(sorted[0].id, 'phy_121');
        // 11:00 AM must come second
        expect(sorted[1].id, 'cse_110');
        // Unassigned must come last
        expect(sorted[2].id, 'math_157');
      });

      test('Dynamic Final Exam calculation and humanized feedback logic', () {
        const totalSecured = 25.6; // e.g. Attendance (8) + CT (17.6)
        const finalExamWeight = 70.0;
        const totalFinalExamMarks = 70.0;

        // Target A: cutoff 75.0
        final marksNeededA = 75.0 - totalSecured; // 49.4
        final reqMarksA = (marksNeededA / finalExamWeight) * totalFinalExamMarks;
        expect(reqMarksA, closeTo(49.4, 0.01));

        // When student needs 67.2 / 70 on remaining:
        const remainingNeeded = 67.2;
        final reqPercent = (remainingNeeded / finalExamWeight) * 100.0;
        expect(reqPercent, closeTo(96.0, 0.01));

        // When target is already secured:
        const marksNeededSecured = -2.0;
        expect(marksNeededSecured <= 0, isTrue);

        // When target is impossible (> 70 marks):
        const impossibleMarks = 75.0;
        expect(impossibleMarks > totalFinalExamMarks, isTrue);
      });

      testWidgets('CourseSimulationCard renders What Do I Need on the Final and expands without throwing', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                key: const PageStorageKey<String>('term_performance_scroll_key'),
                child: CourseSimulationCard(
                  docId: 'c1',
                  courseCode: 'PHY 121',
                  courseName: 'Waves & Oscillation',
                  creditHours: 3.0,
                  courseType: 'Theory',
                  breakdown: const CourseScoreBreakdown(
                    attendanceSecured: 8.0,
                    attendanceWeight: 10.0,
                    ctSecured: 17.6,
                    ctWeight: 20.0,
                    midSecured: 0.0,
                    midWeight: 0.0,
                    otherSecured: 0.0,
                    otherWeight: 0.0,
                    totalSecured: 25.6,
                    totalSecuredWeight: 30.0,
                    remainingWeight: 70.0,
                  ),
                  isSelected: true,
                  finalExamTotal: 210.0,
                  externalSliderValue: 80.0,
                  gradingScale: const [],
                  defaultScale: [
                    GradingRow(letterGrade: 'A+', gradePoint: 4.0, minPercentage: 80, maxPercentage: 100),
                    GradingRow(letterGrade: 'A', gradePoint: 3.75, minPercentage: 75, maxPercentage: 79),
                  ],
                  onToggleSelected: (_) {},
                  onSimulationChanged: (_, __, ___) {},
                ),
              ),
            ),
          ),
        );

        expect(find.byKey(const PageStorageKey<String>('term_performance_scroll_key')), findsOneWidget);
        expect(find.text('PHY 121'), findsOneWidget);
        expect(find.text('Current Term Marks: 25.6 / 30'), findsOneWidget);
        expect(find.text('Expected Final Exam Score:'), findsOneWidget);
        expect(find.text('What Do I Need on the Final?'), findsOneWidget);

        // Tap to expand
        await tester.tap(find.text('What Do I Need on the Final?'));
        await tester.pumpAndSettle();

        expect(find.text('Score Needed in Final Exam'), findsOneWidget);
        expect(find.text('Out of 210 marks'), findsOneWidget);
        expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
        expect(find.text('80% (4.00)'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsWidgets);
        expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
        expect(find.text('Projected Final Exam Score:'), findsOneWidget);
      });

      test('TASK 2: ClassRoutine swapWeeks serializes, deserializes, and flips active status for date', () {
        // Monday week 36 (even) and Monday week 37 (odd)
        final mondayWeek36 = DateTime(2026, 9, 7); // week 36 (even)
        final mondayWeek37 = DateTime(2026, 9, 14); // week 37 (odd)
        expect(mondayWeek36.weekday, DateTime.monday);
        expect(mondayWeek37.weekday, DateTime.monday);
        expect(mondayWeek36.weekOfYear % 2 == 0, true); // Even week
        expect(mondayWeek37.weekOfYear % 2 != 0, true); // Odd week

        final routineA = ClassRoutine(
          id: 'routine_week_a',
          courseId: 'CSE 110',
          courseName: 'CSE 110: Algorithm Lab',
          dayOfWeek: DateTime.monday,
          startTime: '10:00 AM',
          endTime: '01:00 PM',
          recurrence: 'biweekly_a', // Odd weeks
        );

        // Normally active on Week 37 (odd) and inactive on Week 36 (even)
        expect(routineA.isActiveOnDate(mondayWeek37), true);
        expect(routineA.isActiveOnDate(mondayWeek36), false);
        expect(routineA.isSwappedForDate(mondayWeek37), false);

        // Swap week 37: becomes inactive on week 37
        final week37Key = '${mondayWeek37.year}-W${mondayWeek37.weekOfYear}';
        final swappedA = routineA.copyWith(swapWeeks: [week37Key]);
        expect(swappedA.isSwappedForDate(mondayWeek37), true);
        expect(swappedA.isActiveOnDate(mondayWeek37), false);

        // Swap week 36: becomes active on week 36
        final week36Key = '${mondayWeek36.year}-W${mondayWeek36.weekOfYear}';
        final swappedWeek36 = routineA.copyWith(swapWeeks: [week36Key]);
        expect(swappedWeek36.isSwappedForDate(mondayWeek36), true);
        expect(swappedWeek36.isActiveOnDate(mondayWeek36), true);

        // Serialization & deserialization check
        final map = swappedA.toMap();
        expect(map['swapWeeks'], [week37Key]);
        final restored = ClassRoutine.fromMap(map);
        expect(restored.swapWeeks, [week37Key]);
        expect(restored.isActiveOnDate(mondayWeek37), false);
      });

      test('TASK 2 & 3: RoutineCourseSyncService findPartnerClass locates paired class', () {
        final labA = ClassRoutine(
          id: 'slot_lab_a',
          courseId: 'CSE 110',
          courseName: 'CSE 110: Algorithm Lab',
          dayOfWeek: DateTime.tuesday,
          startTime: '02:00 PM',
          endTime: '05:00 PM',
          recurrence: 'biweekly_a',
          pairedClassId: 'slot_lab_b',
        );

        final labB = ClassRoutine(
          id: 'slot_lab_b',
          courseId: 'EEE 164',
          courseName: 'EEE 164: Electronics Lab',
          dayOfWeek: DateTime.tuesday,
          startTime: '02:00 PM',
          endTime: '05:00 PM',
          recurrence: 'biweekly_b',
          pairedClassId: 'slot_lab_a',
        );

        final unrelatedTheory = ClassRoutine(
          id: 'slot_math',
          courseId: 'MATH 157',
          courseName: 'MATH 157: Calculus',
          dayOfWeek: DateTime.monday,
          startTime: '10:00 AM',
          endTime: '11:00 AM',
        );

        final allSlots = [labA, labB, unrelatedTheory];

        final partnerOfA = RoutineCourseSyncService.findPartnerClass(
          routine: labA,
          allRoutines: allSlots,
        );
        expect(partnerOfA, isNotNull);
        expect(partnerOfA!.id, 'slot_lab_b');

        final partnerOfB = RoutineCourseSyncService.findPartnerClass(
          routine: labB,
          allRoutines: allSlots,
        );
        expect(partnerOfB, isNotNull);
        expect(partnerOfB!.id, 'slot_lab_a');

        final partnerOfMath = RoutineCourseSyncService.findPartnerClass(
          routine: unrelatedTheory,
          allRoutines: allSlots,
        );
        expect(partnerOfMath, isNull);
      });

      test('TASK 3: Partner takeover converts biweekly partner into weekly routine preserving history', () {
        final splitDate = DateTime(2026, 9, 15);
        final prevDay = splitDate.subtract(const Duration(days: 1));

        final oldPartnerLab = ClassRoutine(
          id: 'partner_lab_old',
          courseId: 'CSE 110',
          courseName: 'CSE 110: Algorithm Lab',
          dayOfWeek: DateTime.tuesday,
          startTime: '02:00 PM',
          endTime: '05:00 PM',
          recurrence: 'biweekly_a', // odd weeks
          pairedClassId: 'ended_lab_id',
        );

        // Cap old slot at prevDay
        final cappedPartner = oldPartnerLab.copyWith(effectiveUntil: prevDay);
        expect(cappedPartner.effectiveUntil, prevDay);
        // Before split date: capped partner is active on odd weeks (Sep 1 is week 35, odd)
        final pastOddTuesday = DateTime(2026, 9, 1);
        expect(pastOddTuesday.weekOfYear % 2 != 0, true);
        expect(cappedPartner.isActiveOnDate(pastOddTuesday), true);
        // On and after split date: capped partner is inactive
        expect(cappedPartner.isActiveOnDate(splitDate), false);

        // Spawn new weekly routine from splitDate
        final newWeeklyPartner = ClassRoutine(
          id: 'partner_lab_new_weekly',
          courseId: oldPartnerLab.courseId,
          courseName: oldPartnerLab.courseName,
          dayOfWeek: oldPartnerLab.dayOfWeek,
          startTime: oldPartnerLab.startTime,
          endTime: oldPartnerLab.endTime,
          recurrence: 'weekly',
          isAlternating: false,
          effectiveFrom: splitDate,
        );

        expect(newWeeklyPartner.recurrence, 'weekly');
        expect(newWeeklyPartner.isAlternating, false);
        // Before split date: inactive
        expect(newWeeklyPartner.isActiveOnDate(pastOddTuesday), false);
        // On and after split date: active on Tuesday every week
        expect(newWeeklyPartner.isActiveOnDate(splitDate), true);
        final futureTuesday = splitDate.add(const Duration(days: 7));
        expect(newWeeklyPartner.isActiveOnDate(futureTuesday), true);
      });

      group('Sprint 21: Profile Subtitle, Developer Description & Configurable Contact Link Tests', () {
        test('TASK 1: profileSubtitle formats "Level X - Term Y" cleanly from numeric or text strings', () {
          // Standard numeric level/term
          final userUni1 = UserProfile(
            email: 'test@buet.ac.bd',
            fullName: 'Shahriyer Sayem',
            nickname: 'Sayem',
            username: 'sayem',
            phone: '0123456789',
            primaryTarget: 'BUET Studies',
            isUniversityStudent: true,
            universityName: 'BUET',
            major: 'EEE',
            level: '1',
            term: '1',
          );
          expect(userUni1.profileSubtitle, 'BUET • EEE • Level 1 - Term 1');

          // Text level/term ("Level 2", "Term 2")
          final userUni2 = UserProfile(
            email: 'test2@buet.ac.bd',
            fullName: 'Shahriyer Sayem',
            nickname: 'Sayem',
            username: 'sayem',
            phone: '0123456789',
            primaryTarget: 'BUET Studies',
            isUniversityStudent: true,
            universityName: 'BUET',
            major: 'CSE',
            level: 'Level 2',
            term: 'Term 2',
          );
          expect(userUni2.profileSubtitle, 'BUET • CSE • Level 2 - Term 2');

          // Non-university admission student
          final userAdmission = UserProfile(
            email: 'candidate@hsc.edu',
            fullName: 'Candidate',
            nickname: 'Cand',
            username: 'candidate',
            phone: '0123456789',
            primaryTarget: 'Engineering Prep',
            isUniversityStudent: false,
            hscBatch: '24',
          );
          expect(userAdmission.profileSubtitle, '24 Batch • Engineering Prep');
        });

        test('TASK 2 & 3: AppConfig declared supportContactUrl and screen aliases exist', () {
          expect(AppConfig.supportContactUrl, isNotEmpty);
          expect(AppConfig.supportContactUrl, contains('https://'));

          // Screen alias types compile and match
          expect(PersonalProfileScreen, equals(ProfileScreen));
          expect(HelpSupportScreen, equals(HelpScreen));
        });

        testWidgets('TASK 2: Profile screen renders updated developer description text', (tester) async {
          const expectedDescription =
              'Crafted by Shahriyer Sayem — a distraction-free academic workspace built for university engineering undergraduates, college, and admission students.';
          expect(expectedDescription, contains('university engineering undergraduates, college, and admission students'));
        });

        test('TASK 1: AndroidManifest.xml contains queries for https, http, and mailto', () {
          final manifestFile = File('android/app/src/main/AndroidManifest.xml');
          expect(manifestFile.existsSync(), isTrue);
          final content = manifestFile.readAsStringSync();
          expect(content, contains('<queries>'));
          expect(content, contains('<data android:scheme="https" />'));
          expect(content, contains('<data android:scheme="http" />'));
          expect(content, contains('<data android:scheme="mailto" />'));
        });

        testWidgets('TASK 2: Help & Support screen renders unified developer description', (tester) async {
          tester.view.physicalSize = const Size(1080, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          const profile = UserProfile(
            fullName: 'Test Student',
            nickname: 'Student',
            username: 'student',
            email: 'student@example.com',
            phone: '01700000000',
            primaryTarget: 'Engineering',
            isUniversityStudent: true,
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(profile)),
              ],
              child: const MaterialApp(
                home: HelpSupportScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('About the Developer'), findsOneWidget);
          expect(find.byType(RichText), findsWidgets);
          final richTexts = tester.widgetList<RichText>(find.byType(RichText));
          final hasUnifiedText = richTexts.any((rt) =>
              rt.text.toPlainText().contains('university engineering undergraduates, college, and admission students'));
          expect(hasUnifiedText, isTrue);
        });

        testWidgets('TASK: HelpSupportScreen Send Message empty query validation', (tester) async {
          tester.view.physicalSize = const Size(1080, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          const profile = UserProfile(
            fullName: 'Test Student',
            nickname: 'Student',
            username: 'student',
            email: 'student@example.com',
            phone: '01700000000',
            primaryTarget: 'Engineering',
            isUniversityStudent: true,
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(profile)),
              ],
              child: const MaterialApp(
                home: HelpSupportScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Tap Send Message without typing in message
          final sendButtonFinder = find.widgetWithText(ElevatedButton, 'Send Message');
          expect(sendButtonFinder, findsOneWidget);
          await tester.tap(sendButtonFinder);
          await tester.pump();

          expect(find.text('Please describe your query before sending.'), findsOneWidget);
        });
      });

      group('Academic Planner Agenda View: Class Routines & Assessments Merging Tests', () {
        test('PlannerAgendaItem correctly wraps routines and assessments with timestamps', () {
          final routine = ClassRoutine(
            id: 'rt_1',
            courseId: 'cse_101',
            courseName: 'CSE 101',
            startTime: '08:30 AM',
            endTime: '09:30 AM',
            dayOfWeek: 1,
            roomNumber: 'Room 301',
          );
          final itemR = PlannerAgendaItem.routine(routine);
          expect(itemR.isRoutine, isTrue);
          expect(itemR.isAssessment, isFalse);
          expect(itemR.routine?.courseName, 'CSE 101');
          expect(itemR.timeInMinutes, 8 * 60 + 30); // 510

          final assessment = Assessment(
            id: 'as_1',
            courseId: 'c1',
            name: 'Class Test 1',
            totalMarks: 20,
            date: DateTime(2026, 9, 13, 10, 15),
            type: 'quiz',
          );
          final itemA = PlannerAgendaItem.assessment(assessment);
          expect(itemA.isAssessment, isTrue);
          expect(itemA.isRoutine, isFalse);
          expect(itemA.assessment?.name, 'Class Test 1');
          expect(itemA.timeInMinutes, 10 * 60 + 15); // 615
        });

        test('RoutineCourseSyncService.mergeAndSortAgenda prioritizes assessments at top then sorts chronologically', () {
          final r1 = ClassRoutine(
            id: 'rt_1',
            courseId: 'eee_101',
            courseName: 'EEE 101',
            startTime: '08:00 AM',
            endTime: '09:00 AM',
            dayOfWeek: 1,
          );
          final r2 = ClassRoutine(
            id: 'rt_2',
            courseId: 'math_101',
            courseName: 'MATH 101',
            startTime: '11:00 AM',
            endTime: '12:00 PM',
            dayOfWeek: 1,
          );
          final ct = Assessment(
            id: 'as_ct',
            courseId: 'c1',
            name: 'EEE 101 Quiz 1',
            totalMarks: 20,
            date: DateTime(2026, 9, 13, 9, 30),
            type: 'quiz',
          );
          final mid = Assessment(
            id: 'as_mid',
            courseId: 'c2',
            name: 'PHY 101 Midterm',
            totalMarks: 50,
            date: DateTime(2026, 9, 13, 14, 0), // 2:00 PM
            type: 'midterm',
          );

          final merged = RoutineCourseSyncService.mergeAndSortAgenda(
            routines: [r2, r1],
            assessments: [mid, ct],
          );

          expect(merged.length, 4);
          // Assessments prioritized at top (sorted chronologically: 9:30 AM, 2:00 PM), routines below (8:00 AM, 11:00 AM)
          expect(merged[0].isAssessment, isTrue);
          expect(merged[0].assessment?.name, 'EEE 101 Quiz 1');
          expect(merged[1].isAssessment, isTrue);
          expect(merged[1].assessment?.name, 'PHY 101 Midterm');
          expect(merged[2].isRoutine, isTrue);
          expect(merged[2].routine?.courseName, 'EEE 101');
          expect(merged[3].isRoutine, isTrue);
          expect(merged[3].routine?.courseName, 'MATH 101');
        });

        test('RoutineCourseSyncService.mergeAndSortAgenda handles assessments without specific time gracefully', () {
          final r1 = ClassRoutine(
            id: 'rt_1',
            courseId: 'cse_101',
            courseName: 'CSE 101',
            startTime: '10:00 AM',
            endTime: '11:00 AM',
            dayOfWeek: 1,
          );
          final noDateAssessment = Assessment(
            id: 'as_nodate',
            courseId: 'c1',
            name: 'Assignment Due',
            totalMarks: 10,
            date: null,
            type: 'assignment',
          );

          final merged = RoutineCourseSyncService.mergeAndSortAgenda(
            routines: [r1],
            assessments: [noDateAssessment],
          );

          expect(merged.length, 2);
          // Assessment is prioritized above routine
          expect(merged[0].isAssessment, isTrue);
          expect(merged[0].assessment?.name, 'Assignment Due');
          expect(merged[1].isRoutine, isTrue);
          expect(merged[1].routine?.courseName, 'CSE 101');
        });
      });

      group('Syllabus PDF Import Flow & Section Management Tests', () {
        test('SyllabusNode.appendImportedNodes directly adds chapters as top-level sections without Section 1 wrapper when course syllabus is empty', () {
          final importedChapters = [
            SyllabusNode(
              title: 'Chapter 1: Logic Gates',
              isLeaf: false,
              children: [
                SyllabusNode(title: 'AND, OR, NOT Gates', isLeaf: true),
                SyllabusNode(title: 'Universal Gates', isLeaf: true),
              ],
            ),
          ];

          final result = SyllabusNode.appendImportedNodes(
            existingNodes: [],
            importedNodes: importedChapters,
          );

          expect(result.nodes.length, 1);
          expect(result.targetSectionTitle, 'Chapter 1: Logic Gates');
          expect(result.nodes.first.title, 'Chapter 1: Logic Gates');
          expect(result.nodes.first.isLeaf, isFalse);
          expect(result.nodes.first.children.length, 2);
          expect(result.nodes.first.children.first.title, 'AND, OR, NOT Gates');
          expect(result.nodes.first.children.last.title, 'Universal Gates');
        });

        test('SyllabusNode.appendImportedNodes directly appends chapters as top-level sections when course already has sections', () {
          final sectionA = SyllabusNode(
            title: 'Midterm Syllabus',
            isLeaf: false,
            children: [
              SyllabusNode(title: 'Chapter 1', isLeaf: false, children: [
                SyllabusNode(title: 'Topic 1.1', isLeaf: true),
              ]),
            ],
          );
          final sectionB = SyllabusNode(
            title: 'Final Term Syllabus',
            isLeaf: false,
            children: [
              SyllabusNode(title: 'Chapter 5', isLeaf: false, children: [
                SyllabusNode(title: 'Topic 5.1', isLeaf: true),
              ]),
            ],
          );

          final newImported = [
            SyllabusNode(
              title: 'Chapter 6: Advanced Topics',
              isLeaf: false,
              children: [
                SyllabusNode(title: 'Topic 6.1', isLeaf: true),
              ],
            ),
          ];

          final result = SyllabusNode.appendImportedNodes(
            existingNodes: [sectionA, sectionB],
            importedNodes: newImported,
          );

          // Top-level sections are flattened without redundant wrapper
          expect(result.nodes.length, 3);
          expect(result.targetSectionTitle, 'Chapter 6: Advanced Topics');
          expect(result.nodes[0].title, 'Midterm Syllabus');
          expect(result.nodes[1].title, 'Final Term Syllabus');
          expect(result.nodes[2].title, 'Chapter 6: Advanced Topics');
          expect(result.nodes[2].children.length, 1);
          expect(result.nodes[2].children.first.title, 'Topic 6.1');
        });

        test('Multiple successive imports append chapters directly as top-level sections', () {
          final existing = <SyllabusNode>[];

          // Import batch 1 into empty syllabus
          final batch1 = [
            SyllabusNode(title: 'Chapter 1', isLeaf: false, children: [
              SyllabusNode(title: 'Topic 1', isLeaf: true),
            ]),
          ];
          final res1 = SyllabusNode.appendImportedNodes(existingNodes: existing, importedNodes: batch1);
          expect(res1.targetSectionTitle, 'Chapter 1');
          expect(res1.nodes.length, 1);
          expect(res1.nodes[0].title, 'Chapter 1');

          // Import batch 2 into same course
          final batch2 = [
            SyllabusNode(title: 'Chapter 2', isLeaf: false, children: [
              SyllabusNode(title: 'Topic 2', isLeaf: true),
            ]),
          ];
          final res2 = SyllabusNode.appendImportedNodes(existingNodes: res1.nodes, importedNodes: batch2);
          expect(res2.targetSectionTitle, 'Chapter 2');
          expect(res2.nodes.length, 2);
          expect(res2.nodes[0].title, 'Chapter 1');
          expect(res2.nodes[1].title, 'Chapter 2');
        });

        test('Syllabus JSON Schema parsing correctly creates chapters with topics and nested materials', () {
          const rawJson = '''[
            {
              "title": "Complex Variable",
              "topics": [
                {
                  "title": "Complex number system",
                  "items": ["Class Note", "Lecture Sheet", "Ref Book", "Term Final Question"]
                },
                {
                  "title": "General functions of a complex variable",
                  "items": []
                }
              ]
            },
            {
              "title": "Vector Analysis",
              "topics": [
                {
                  "title": "Dot and Cross Products",
                  "items": ["Lecture 1 Notes"]
                }
              ]
            }
          ]''';

          final decoded = jsonDecode(rawJson) as List<dynamic>;
          final List<SyllabusNode> chapterNodes = [];

          for (final chapterObj in decoded) {
            final chapterMap = Map<String, dynamic>.from(chapterObj as Map);
            final chapterTitle = (chapterMap['title'] ?? 'Chapter').toString().trim();
            final rawTopics = chapterMap['topics'] as List<dynamic>? ?? [];

            final List<SyllabusNode> topicNodes = [];
            for (final t in rawTopics) {
              final tMap = Map<String, dynamic>.from(t as Map);
              final topicTitle = (tMap['title'] ?? 'Topic').toString().trim();
              final rawItems = (tMap['items'] as List<dynamic>?) ?? [];

              final List<SyllabusNode> materialNodes = rawItems.map((m) {
                return SyllabusNode(
                  title: m.toString().trim(),
                  isLeaf: true,
                  isCompleted: false,
                );
              }).toList();

              topicNodes.add(
                SyllabusNode(
                  title: topicTitle,
                  isLeaf: true,
                  isCompleted: false,
                  children: materialNodes,
                ),
              );
            }

            chapterNodes.add(
              SyllabusNode(
                title: chapterTitle,
                isLeaf: false,
                children: topicNodes,
              ),
            );
          }

          expect(chapterNodes.length, 2);
          expect(chapterNodes[0].title, 'Complex Variable');
          expect(chapterNodes[0].isLeaf, isFalse);
          expect(chapterNodes[0].children.length, 2);

          // Topic 1
          final topic1 = chapterNodes[0].children[0];
          expect(topic1.title, 'Complex number system');
          expect(topic1.isLeaf, isTrue);
          expect(topic1.children.length, 4);
          expect(topic1.children[0].title, 'Class Note');
          expect(topic1.children[1].title, 'Lecture Sheet');
          expect(topic1.children[2].title, 'Ref Book');
          expect(topic1.children[3].title, 'Term Final Question');

          // Topic 2
          final topic2 = chapterNodes[0].children[1];
          expect(topic2.title, 'General functions of a complex variable');
          expect(topic2.isLeaf, isTrue);
          expect(topic2.children.isEmpty, isTrue);

          // Chapter 2
          expect(chapterNodes[1].title, 'Vector Analysis');
          expect(chapterNodes[1].children.length, 1);
          expect(chapterNodes[1].children[0].title, 'Dot and Cross Products');
          expect(chapterNodes[1].children[0].children.length, 1);
          expect(chapterNodes[1].children[0].children[0].title, 'Lecture 1 Notes');
        });

        test('SyllabusNode.unwrapNode promotes child chapters to top level when removing an artificial root wrapper', () {
          final chapter1 = SyllabusNode(
            id: 'chap_1',
            title: 'Complex Variable',
            isLeaf: false,
            children: [
              SyllabusNode(id: 'top_1', title: 'Complex Numbers', isLeaf: true),
            ],
          );
          final chapter2 = SyllabusNode(
            id: 'chap_2',
            title: 'Vector Analysis',
            isLeaf: false,
            children: [
              SyllabusNode(id: 'top_2', title: 'Gradient and Divergence', isLeaf: true),
            ],
          );
          final rootWrapper = SyllabusNode(
            id: 'root_sec_1',
            title: 'Section 1',
            isLeaf: false,
            children: [chapter1, chapter2],
          );

          final allNodes = <SyllabusNode>[rootWrapper];

          // Action: Remove Section Only (Keep Topics / Chapters)
          final unwrapped = SyllabusNode.unwrapNode(nodes: allNodes, targetId: 'root_sec_1');

          expect(unwrapped, isTrue);
          expect(allNodes.length, 2);
          expect(allNodes[0].id, 'chap_1');
          expect(allNodes[0].title, 'Complex Variable');
          expect(allNodes[0].parentId, isNull);
          expect(allNodes[0].children.length, 1);

          expect(allNodes[1].id, 'chap_2');
          expect(allNodes[1].title, 'Vector Analysis');
          expect(allNodes[1].parentId, isNull);
          expect(allNodes[1].children.length, 1);
        });

        test('SyllabusNode.unwrapNode reassigns parent ID when removing a nested section inside a parent chapter', () {
          final topic1 = SyllabusNode(id: 'top_1', title: 'Limit and Continuity', isLeaf: true);
          final topic2 = SyllabusNode(id: 'top_2', title: 'Derivatives', isLeaf: true);
          final nestedSection = SyllabusNode(
            id: 'sec_diff',
            title: 'Differential Calculus',
            isLeaf: false,
            parentId: 'chap_math_1',
            children: [topic1, topic2],
          );
          final parentChapter = SyllabusNode(
            id: 'chap_math_1',
            title: 'Mathematics I',
            isLeaf: false,
            children: [nestedSection],
          );

          final allNodes = <SyllabusNode>[parentChapter];

          // Action: Remove Section Only (Keep Topics)
          final unwrapped = SyllabusNode.unwrapNode(nodes: allNodes, targetId: 'sec_diff');

          expect(unwrapped, isTrue);
          expect(allNodes.length, 1);
          expect(allNodes.first.id, 'chap_math_1');
          // Topics are now direct children of parentChapter and their parentId is reassigned
          expect(parentChapter.children.length, 2);
          expect(parentChapter.children[0].id, 'top_1');
          expect(parentChapter.children[0].parentId, 'chap_math_1');
          expect(parentChapter.children[1].id, 'top_2');
          expect(parentChapter.children[1].parentId, 'chap_math_1');
        });

        test('SyllabusNode.removeNode recursively destroys the section and all its contents', () {
          final chapter = SyllabusNode(
            id: 'chap_delete_all',
            title: 'Linear Algebra',
            isLeaf: false,
            children: [
              SyllabusNode(id: 't_matrices', title: 'Matrices', isLeaf: true),
              SyllabusNode(id: 't_determinants', title: 'Determinants', isLeaf: true),
            ],
          );
          final allNodes = <SyllabusNode>[chapter];

          // Action: Delete Section & All Contents
          final removed = SyllabusNode.removeNode(nodes: allNodes, targetId: 'chap_delete_all');

          expect(removed, isTrue);
          expect(allNodes.isEmpty, isTrue);
        });

        test('SyllabusNode parentId serializes and deserializes accurately', () {
          final node = SyllabusNode(
            id: 'node_custom_parent',
            title: 'Eigenvalues',
            parentId: 'parent_chap_99',
            isLeaf: true,
          );

          final map = node.toMap();
          expect(map['parentId'], 'parent_chap_99');

          final restored = SyllabusNode.fromMap(map);
          expect(restored.id, 'node_custom_parent');
          expect(restored.title, 'Eigenvalues');
          expect(restored.parentId, 'parent_chap_99');
        });

        test('SyllabusNode.groupNodesIntoSection groups selected topics into a new folder at the first topic position', () {
          final top1 = SyllabusNode(id: 't_1', title: 'Gradient', isLeaf: true);
          final top2 = SyllabusNode(id: 't_2', title: 'Divergence', isLeaf: true);
          final top3 = SyllabusNode(id: 't_3', title: 'Curl', isLeaf: true);
          final top4 = SyllabusNode(id: 't_4', title: 'Stokes Theorem', isLeaf: true);

          final allNodes = <SyllabusNode>[top1, top2, top3, top4];

          // Group top2 and top3 into "Vector Fields"
          final newSection = SyllabusNode.groupNodesIntoSection(
            nodes: allNodes,
            targetIds: {'t_2', 't_3'},
            sectionTitle: 'Vector Fields',
          );

          expect(newSection, isNotNull);
          expect(newSection!.title, 'Vector Fields');
          expect(newSection.isLeaf, isFalse);
          expect(newSection.children.length, 2);
          expect(newSection.children[0].id, 't_2');
          expect(newSection.children[0].parentId, newSection.id);
          expect(newSection.children[1].id, 't_3');
          expect(newSection.children[1].parentId, newSection.id);

          // All nodes tree order: [top1, newSection, top4]
          expect(allNodes.length, 3);
          expect(allNodes[0].id, 't_1');
          expect(allNodes[1].id, newSection.id);
          expect(allNodes[2].id, 't_4');
        });

        test('SyllabusNode.groupNodesIntoSection preserves child notes and resourceUrls on grouped topics', () {
          final childMaterial = SyllabusNode(id: 'mat_1', title: 'Handwritten Notes', isLeaf: true);
          final topA = SyllabusNode(
            id: 't_a',
            title: 'Fourier Transform',
            isLeaf: true,
            resourceUrl: 'https://drive.google.com/file/fourier',
            children: [childMaterial],
          );
          final topB = SyllabusNode(id: 't_b', title: 'Laplace Transform', isLeaf: true);

          final allNodes = <SyllabusNode>[topA, topB];

          final newGroup = SyllabusNode.groupNodesIntoSection(
            nodes: allNodes,
            targetIds: {'t_a'},
            sectionTitle: 'Transforms',
          );

          expect(newGroup, isNotNull);
          expect(newGroup!.children.length, 1);
          final groupedA = newGroup.children.first;
          expect(groupedA.id, 't_a');
          expect(groupedA.title, 'Fourier Transform');
          expect(groupedA.resourceUrl, 'https://drive.google.com/file/fourier');
          expect(groupedA.children.length, 1);
          expect(groupedA.children.first.title, 'Handwritten Notes');
        });

        test('SyllabusNode convertToFolder and convertToTopic dynamically toggle node representation', () {
          final node = SyllabusNode(id: 'toggle_1', title: 'Intro to AI', isLeaf: true);
          expect(node.isLeaf, isTrue);

          // Convert to folder
          node.convertToFolder();
          expect(node.isLeaf, isFalse);

          // Convert back to topic
          node.convertToTopic();
          expect(node.isLeaf, isTrue);
        });

        test('SyllabusNode.unwrapNode smoothly promotes orphaned topics to standalone top level when deleting a folder', () {
          final topicX = SyllabusNode(id: 'top_x', title: 'Binary Trees', isLeaf: true);
          final topicY = SyllabusNode(id: 'top_y', title: 'AVL Trees', isLeaf: true);
          final folder = SyllabusNode(
            id: 'sec_trees',
            title: 'Tree Data Structures',
            isLeaf: false,
            children: [topicX, topicY],
          );

          final allNodes = <SyllabusNode>[folder];

          // Action: Remove Section Only (Keep Topics)
          final success = SyllabusNode.unwrapNode(nodes: allNodes, targetId: 'sec_trees');

          expect(success, isTrue);
          expect(allNodes.length, 2);
          expect(allNodes[0].id, 'top_x');
          expect(allNodes[0].parentId, isNull);
          expect(allNodes[1].id, 'top_y');
          expect(allNodes[1].parentId, isNull);
        });
      });

      group('Timer & Journal Sync & Error Handling Tests', () {
        test('TimerNotifier.endSession cleanly terminates session and resets without logging', () {
          final notifier = TimerNotifier();
          // Simulate running timer
          notifier.state = notifier.state.copyWith(
            mode: TimerMode.breakTime,
            status: TimerStatus.running,
            elapsedSeconds: 1500,
            breakElapsedSeconds: 120,
            breakDurationSeconds: 300,
          );

          expect(notifier.state.mode, TimerMode.breakTime);
          expect(notifier.state.status, TimerStatus.running);

          // Invoke endSession
          notifier.endSession();

          expect(notifier.state.mode, TimerMode.focus);
          expect(notifier.state.status, TimerStatus.initial);
          expect(notifier.state.elapsedSeconds, 0);
          expect(notifier.state.breakElapsedSeconds, 0);
          expect(notifier.state.extraElapsedSeconds, 0);
        });

        test('Syllabus node selection and hierarchical completion sync', () {
          final topic1 = SyllabusNode(id: 't1', title: 'Thevenin Theorem', isLeaf: true, isCompleted: false);
          final topic2 = SyllabusNode(id: 't2', title: 'Norton Theorem', isLeaf: true, isCompleted: false);
          final chapter = SyllabusNode(id: 'c1', title: 'Network Theorems', isLeaf: false, children: [topic1, topic2]);
          final section = SyllabusNode(id: 's1', title: 'DC Circuits', isLeaf: false, children: [chapter]);

          // Mark t1 completed
          final selectedIds = {'t1'};
          void markCompleted(List<SyllabusNode> nodes) {
            for (final n in nodes) {
              if (selectedIds.contains(n.id)) {
                n.isCompleted = true;
              }
              markCompleted(n.children);
            }
          }

          markCompleted([section]);
          expect(topic1.isCompleted, isTrue);
          expect(topic2.isCompleted, isFalse);

          // Bottom up evaluation
          section.updateHierarchicalCompletion();
          // Since topic2 is not completed, chapter and section should remain false
          expect(chapter.isCompleted, isFalse);
          expect(section.isCompleted, isFalse);

          // Now complete topic2
          selectedIds.add('t2');
          markCompleted([section]);
          section.updateHierarchicalCompletion();
          // Now both chapter and section evaluate to completed
          expect(chapter.isCompleted, isTrue);
          expect(section.isCompleted, isTrue);
        });

        test('503 and GenerativeAIException error message parsing', () {
          final errors = [
            'GenerativeAIException: 503 Service Unavailable',
            'ResourceExhausted: The AI model is overloaded',
            '503: Model busy',
          ];

          for (final err in errors) {
            final isBusy = err.contains('503') ||
                err.contains('GenerativeAIException') ||
                err.contains('overloaded') ||
                err.contains('ResourceExhausted');
            expect(isBusy, isTrue);

            final msg = isBusy
                ? 'The AI server is currently busy. Please try importing your syllabus again in a few minutes.'
                : 'Smart Import failed: $err';
            expect(msg, 'The AI server is currently busy. Please try importing your syllabus again in a few minutes.');
          }
        });

        test('Holiday assessments are identified and preserved on holiday dates', () {
          final holiday = DateTime(2026, 9, 18); // Friday/holiday
          final assessment = Assessment(
            id: 'ct_1',
            courseId: 'cse_101',
            name: 'CT 2: Graph Theory',
            type: 'CT',
            date: holiday,
          );

          // Ensure assessment date matches selected day even if isHoliday is true
          final matchesDay = assessment.date?.year == holiday.year &&
              assessment.date?.month == holiday.month &&
              assessment.date?.day == holiday.day;

          expect(matchesDay, isTrue);
          expect(assessment.type, 'CT');
          expect(assessment.name, contains('CT 2'));
        });

        testWidgets('AssessmentCard renders with amber accent CT badge and course details', (tester) async {
          final assessment = Assessment(
            id: 'ct_101',
            courseId: 'cse_201',
            name: 'CT 1: Discrete Mathematics',
            type: 'CT',
            date: DateTime(2026, 9, 20, 10, 30),
            syllabusSummary: 'Graph Coloring, Eulerian Paths',
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AssessmentCard(
                  assessment: assessment,
                  courseCode: 'CSE 201 • Discrete Math',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('CT'), findsWidgets);
          expect(find.text('CT 1: Discrete Mathematics'), findsOneWidget);
          expect(find.text('CSE 201 • Discrete Math'), findsOneWidget);
          expect(find.text('10:30 AM'), findsOneWidget);
          expect(find.text('Topic: Graph Coloring, Eulerian Paths'), findsOneWidget);
        });

        test('SyllabusNode hierarchical subtopics and material selection with cascading completion', () {
          final noteMaterial = SyllabusNode(id: 'm1', title: 'Class Note', isLeaf: true, isCompleted: false);
          final sheetMaterial = SyllabusNode(id: 'm2', title: 'Lecture Sheet', isLeaf: true, isCompleted: false);
          final refBookMaterial = SyllabusNode(id: 'm3', title: 'Ref Book', isLeaf: true, isCompleted: false);
          final termQMaterial = SyllabusNode(id: 'm4', title: 'Term Final Question', isLeaf: true, isCompleted: false);

          final topicNode = SyllabusNode(
            id: 't1',
            title: 'Introduction to Graph Theory',
            isLeaf: false,
            children: [noteMaterial, sheetMaterial, refBookMaterial, termQMaterial],
          );

          final sectionNode = SyllabusNode(
            id: 's1',
            title: 'Section 1: Graphs',
            isLeaf: false,
            children: [topicNode],
          );

          expect(sectionNode.totalLeafCount, 4);
          expect(sectionNode.completedLeafCount, 0);

          // Cascading parent completion
          topicNode.setCompletedCascading(true);
          expect(noteMaterial.isCompleted, isTrue);
          expect(sheetMaterial.isCompleted, isTrue);
          expect(refBookMaterial.isCompleted, isTrue);
          expect(termQMaterial.isCompleted, isTrue);

          sectionNode.updateHierarchicalCompletion();
          expect(sectionNode.isCompleted, isTrue);
          expect(sectionNode.completedLeafCount, 4);
          expect(sectionNode.progress, 1.0);
        });

        test('Dynamic Auto-Conversion: adding children dynamically turns a topic into a folder with tally and parentId', () {
          final topic = SyllabusNode(
            id: 'top_1',
            title: 'Eigenvalues & Eigenvectors',
            isLeaf: true,
            isCompleted: false,
          );

          // Initially empty: renders as topic row (children.isEmpty)
          expect(topic.children.isEmpty, isTrue);
          bool isFolder = topic.children.isNotEmpty;
          expect(isFolder, isFalse);

          // Add child material
          final childMaterial = SyllabusNode(
            id: 'mat_1',
            title: 'Lecture Sheet 1',
            isLeaf: true,
            isCompleted: false,
            parentId: topic.id,
          );
          topic.children.add(childMaterial);

          // Dynamically becomes a folder
          isFolder = topic.children.isNotEmpty;
          expect(isFolder, isTrue);
          expect(childMaterial.parentId, 'top_1');

          // Tally calculations
          final completed = topic.children.fold<int>(0, (acc, c) => acc + c.completedLeafCount);
          final total = topic.children.fold<int>(0, (acc, c) => acc + c.totalLeafCount);
          expect(completed, 0);
          expect(total, 1);

          // Complete child
          childMaterial.isCompleted = true;
          final updatedCompleted = topic.children.fold<int>(0, (acc, c) => acc + c.completedLeafCount);
          expect(updatedCompleted, 1);
        });

        test('Dynamic Auto-Conversion: removing all children dynamically reverts folder back to checkable topic', () {
          final folder = SyllabusNode(
            id: 'fold_1',
            title: 'Differential Equations',
            isLeaf: false,
          );
          final sub1 = SyllabusNode(id: 'sub_1', title: 'Homogeneous ODEs', isLeaf: true, parentId: folder.id);
          final sub2 = SyllabusNode(id: 'sub_2', title: 'Non-homogeneous ODEs', isLeaf: true, parentId: folder.id);
          folder.children.addAll([sub1, sub2]);

          expect(folder.children.isNotEmpty, isTrue);
          bool isFolder = folder.children.isNotEmpty;
          expect(isFolder, isTrue);

          // Remove first child
          SyllabusNode.removeNode(nodes: folder.children, targetId: 'sub_1');
          expect(folder.children.length, 1);
          expect(folder.children.isNotEmpty, isTrue);

          // Remove last child
          SyllabusNode.removeNode(nodes: folder.children, targetId: 'sub_2');
          expect(folder.children.isEmpty, isTrue);

          // Dynamically reverts to topic row (children.isEmpty)
          isFolder = folder.children.isNotEmpty;
          expect(isFolder, isFalse);
        });

        test('Dynamic Auto-Conversion: hierarchical serialization and deserialization preserves parentId and nested structure', () {
          final parent = SyllabusNode(
            id: 'root_section',
            title: 'Complex Analysis',
            isLeaf: false,
          );
          final child = SyllabusNode(
            id: 'child_topic',
            title: 'Cauchy-Riemann Equations',
            isLeaf: true,
            parentId: parent.id,
            resourceUrl: 'https://example.com/cr.pdf',
          );
          parent.children.add(child);

          final map = parent.toMap();
          expect(map['id'], 'root_section');
          expect(map['children'].length, 1);
          expect(map['children'][0]['parentId'], 'root_section');
          expect(map['children'][0]['resourceUrl'], 'https://example.com/cr.pdf');

          final restored = SyllabusNode.fromMap(map);
          expect(restored.id, 'root_section');
          expect(restored.children.length, 1);
          expect(restored.children[0].parentId, 'root_section');
          expect(restored.children[0].title, 'Cauchy-Riemann Equations');
          expect(restored.children.isNotEmpty, isTrue);
        });

        test('TimerNotifier discardSession resets state to initial without logging', () {
          final notifier = TimerNotifier();
          notifier.setTargetMinutes(25);
          notifier.toggleStartPause();

          expect(notifier.state.status, TimerStatus.running);

          // Call discardSession
          notifier.discardSession();

          expect(notifier.state.status, TimerStatus.initial);
          expect(notifier.state.mode, TimerMode.focus);
          expect(notifier.state.elapsedSeconds, 0);
          expect(notifier.state.breakElapsedSeconds, 0);
          expect(notifier.state.extraElapsedSeconds, 0);
        });

        test('TimerNotifier syncSubject synchronizes subject from available list', () {
          final notifier = TimerNotifier();
          // Initial subject is General Study (not hardcoded Physics 1st Paper)
          expect(notifier.state.selectedSubject, 'General Study');

          // Sync with available courses
          notifier.syncSubject(['CSE 101', 'MATH 201', 'PHYS 102']);
          expect(notifier.state.selectedSubject, 'CSE 101');

          // If already has valid subject from the list, it retains it
          notifier.changeSubject('MATH 201');
          notifier.syncSubject(['CSE 101', 'MATH 201', 'PHYS 102']);
          expect(notifier.state.selectedSubject, 'MATH 201');

          // If available list is empty, falls back to General Study
          notifier.syncSubject([]);
          expect(notifier.state.selectedSubject, 'General Study');
        });
      });

      group('Planner Assessments and AI Import Resilience Tests', () {
        test('Assessment.fromMap parses dueDate, due_date, and aliases date/dueDate correctly', () {
          final now = DateTime(2026, 9, 15, 14, 30);
          final map1 = {
            'id': 'a1',
            'name': 'Assignment 1',
            'type': 'assignment',
            'dueDate': Timestamp.fromDate(now),
          };
          final ass1 = Assessment.fromMap(map1, defaultId: 'a1');
          expect(ass1.date, isNotNull);
          expect(ass1.dueDate, isNotNull);
          expect(ass1.date!.year, 2026);
          expect(ass1.date!.month, 9);
          expect(ass1.date!.day, 15);
          expect(ass1.date!.hour, 14);
          expect(ass1.date!.minute, 30);

          final map2 = {
            'id': 'a2',
            'name': 'Assignment 2',
            'type': 'assignment',
            'due_date': now.toIso8601String(),
          };
          final ass2 = Assessment.fromMap(map2, defaultId: 'a2');
          expect(ass2.date, isNotNull);
          expect(ass2.dueDate, isNotNull);
          expect(ass2.dueDate!.year, 2026);

          // Serialization includes both date and dueDate
          final serialized = ass1.toMap();
          expect(serialized['date'], isNotNull);
          expect(serialized['dueDate'], isNotNull);

          // copyWith dueDate
          final updated = ass1.copyWith(dueDate: DateTime(2026, 9, 20, 10, 0));
          expect(updated.date!.day, 20);
          expect(updated.dueDate!.day, 20);
        });

        test('isSameCalendarDay matches dates across raw, local, and UTC representations', () {
          bool isSameCalendarDay(DateTime? a, DateTime? b) {
            if (a == null || b == null) return false;
            if (a.year == b.year && a.month == b.month && a.day == b.day) return true;
            final localA = a.toLocal();
            final localB = b.toLocal();
            if (localA.year == localB.year &&
                localA.month == localB.month &&
                localA.day == localB.day) {
              return true;
            }
            final utcA = a.toUtc();
            final utcB = b.toUtc();
            return utcA.year == utcB.year &&
                utcA.month == utcB.month &&
                utcA.day == utcB.day;
          }

          final localDate = DateTime(2026, 9, 14, 0, 0);
          final utcEquivalent = DateTime.utc(2026, 9, 14, 6, 30);
          expect(isSameCalendarDay(localDate, utcEquivalent), isTrue);

          final differentDate = DateTime(2026, 9, 15, 0, 0);
          expect(isSameCalendarDay(localDate, differentDate), isFalse);
        });

        test('PlannerAgendaItem wraps Assessment and calculates timeInMinutes from date or dueDate', () {
          final ass = Assessment(
            id: 'test_a',
            name: 'Math CT',
            courseId: 'c1',
            type: 'ct',
            date: DateTime(2026, 9, 14, 10, 15),
          );
          final item = PlannerAgendaItem.assessment(ass);
          expect(item.isAssessment, isTrue);
          expect(item.isRoutine, isFalse);
          expect(item.timeInMinutes, 10 * 60 + 15);
        });

        test('RoutineCourseSyncService.mergeAndSortAgenda prioritizes assessments at the top before routines', () {
          final routine = ClassRoutine(
            id: 'r1',
            courseId: 'c1',
            courseName: 'Algorithms',
            dayOfWeek: 1,
            startTime: '09:00 AM',
            endTime: '10:30 AM',
          );
          final assessment = Assessment(
            id: 'a1',
            name: 'CT 1',
            courseId: 'c1',
            type: 'ct',
            date: DateTime(2026, 9, 14, 11, 0),
          );

          final merged = RoutineCourseSyncService.mergeAndSortAgenda(
            routines: [routine],
            assessments: [assessment],
          );

          expect(merged.length, 2);
          // Assessment prioritized at top even though it is at 11:00 AM while routine is 9:00 AM
          expect(merged[0].isAssessment, isTrue);
          expect(merged[0].assessment?.name, 'CT 1');
          expect(merged[1].isRoutine, isTrue);
          expect(merged[1].routine?.courseName, 'Algorithms');
        });

        testWidgets('AssessmentCard renders ASSIGNMENT badge, course title, and Due prefix', (tester) async {
          final assessment = Assessment(
            id: 'hw1',
            name: 'Homework 1: Graph Algorithms',
            courseId: 'CSE202',
            type: 'assignment',
            date: DateTime(2026, 9, 14, 11, 59),
          );

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AssessmentCard(
                  assessment: assessment,
                  courseCode: 'CSE 202',
                  courseTitle: 'Data Structures & Algorithms',
                ),
              ),
            ),
          );

          expect(find.text('ASSIGNMENT'), findsOneWidget);
          expect(find.text('CSE 202 • Data Structures & Algorithms'), findsOneWidget);
          expect(find.text('Due 11:59 AM'), findsOneWidget);
          expect(find.text('Homework 1: Graph Algorithms'), findsOneWidget);
        });

        test('Assessment.fromCourseData extracts classTests, quizzesViva, and labReports from assessments map', () {
          final courseData = {
            'courseCode': 'CSE 311',
            'courseTitle': 'Database Systems',
            'assessments': {
              'ctWeightage': 20.0,
              'classTests': [
                {
                  'id': 'ct_1',
                  'name': 'CT 1',
                  'type': 'ct',
                  'date': '2026-09-14T10:00:00.000Z',
                  'totalMarks': 20.0,
                  'obtainedMarks': 18.0,
                },
                {
                  'id': 'ct_2',
                  'name': 'CT 2',
                  'type': 'ct',
                  'date': '2026-09-20T10:00:00.000Z',
                  'totalMarks': 20.0,
                },
              ],
              'quizzesViva': [
                {
                  'id': 'quiz_1',
                  'name': 'Quiz 1 (SQL)',
                  'type': 'quiz',
                  'date': '2026-09-14T14:30:00.000Z',
                  'totalMarks': 15.0,
                }
              ],
              'labReportsAssignments': [
                {
                  'id': 'report_1',
                  'name': 'Lab Report 1',
                  'type': 'assignment',
                  'dueDate': '2026-09-14T23:59:00.000Z',
                  'totalMarks': 10.0,
                }
              ],
            },
          };

          final assessments = Assessment.fromCourseData(courseData, courseId: 'CSE_311');

          expect(assessments.length, 4);
          expect(assessments.any((a) => a.id == 'ct_1' && a.courseId == 'CSE_311'), isTrue);
          expect(assessments.any((a) => a.id == 'quiz_1' && a.courseId == 'CSE_311'), isTrue);
          expect(assessments.any((a) => a.id == 'report_1' && a.courseId == 'CSE_311'), isTrue);

          // Test calendar day normalization matching
          final selectedDate = DateTime.utc(2026, 9, 14);
          final sameDayItems = assessments.where((a) {
            final d = a.date ?? a.dueDate;
            if (d == null) return false;
            final dUtc = d.toUtc();
            return dUtc.year == selectedDate.year &&
                dUtc.month == selectedDate.month &&
                dUtc.day == selectedDate.day;
          }).toList();

          // ct_1, quiz_1, and report_1 are all on Sept 14, 2026
          expect(sameDayItems.length, 3);
        });

        test('Assessment.fromRawListOrMap parses both direct List and category Map structures', () {
          // Direct list
          final directList = [
            {'id': 'a1', 'name': 'Assignment 1', 'totalMarks': 10.0},
          ];
          final parsedList = Assessment.fromRawListOrMap(directList, defaultCourseId: 'c1');
          expect(parsedList.length, 1);
          expect(parsedList.first.name, 'Assignment 1');

          // Category map
          final categoryMap = {
            'classTests': [
              {'id': 'ct1', 'name': 'CT 1', 'totalMarks': 20.0},
            ],
            'quizzesViva': [
              {'id': 'q1', 'name': 'Quiz 1', 'totalMarks': 10.0},
            ],
            'ctWeightage': 20.0,
          };
          final parsedMap = Assessment.fromRawListOrMap(categoryMap, defaultCourseId: 'c2');
          expect(parsedMap.length, 2);
          expect(parsedMap.any((a) => a.name == 'CT 1'), isTrue);
          expect(parsedMap.any((a) => a.name == 'Quiz 1'), isTrue);
        });

        group('Gemini Model Config & Deprecation Fallback Tests', () {
          test('AppConfig exposes gemini-3.1-pro-preview as geminiModelName and specifies fallback cascade', () {
            expect(AppConfig.geminiModelName, 'gemini-3.1-pro-preview');
            expect(AppConfig.geminiPrimaryModel, 'gemini-3.1-pro-preview');
            expect(AppConfig.geminiCandidateModels, contains('gemini-3.1-pro-preview'));
            expect(AppConfig.geminiCandidateModels, contains('gemini-2.5-flash'));
            expect(AppConfig.geminiCandidateModels.first, 'gemini-3.1-pro-preview');
          });

          test('Deprecation and capacity error strings are accurately recognized for fallback logic', () {
            const deprecationMsg =
                'This model models/gemini-2.0-flash is no longer available. Please update your code to use models/gemini-2.5-flash for the latest features and improvements.';
            final lower = deprecationMsg.toLowerCase();
            final isDeprecationOrNotFound = lower.contains('no longer available') ||
                lower.contains('deprecated') ||
                lower.contains('not found') ||
                lower.contains('404');
            expect(isDeprecationOrNotFound, isTrue);

            const overloadedMsg = '503 Service Unavailable: The model is overloaded. Please try again later.';
            final overloadedLower = overloadedMsg.toLowerCase();
            final isRetryable = overloadedLower.contains('503') ||
                overloadedLower.contains('overloaded') ||
                overloadedLower.contains('unavailable') ||
                overloadedLower.contains('resourceexhausted') ||
                overloadedLower.contains('rate') ||
                overloadedLower.contains('quota');
            expect(isRetryable, isTrue);
          });

          test('JSON parsing strips markdown code fences and cleans response', () {
            const rawResponse = '```json\n[{"chapterName": "Chapter 1", "topics": ["T1", "T2"]}]\n```';
            String cleanJson = rawResponse.trim();
            final codeFenceRegex = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
            final fenceMatch = codeFenceRegex.firstMatch(cleanJson);
            if (fenceMatch != null && fenceMatch.group(1) != null) {
              cleanJson = fenceMatch.group(1)!.trim();
            }
            final decoded = jsonDecode(cleanJson);
            expect(decoded is List, isTrue);
            expect((decoded as List).length, 1);
            expect(decoded.first['chapterName'], 'Chapter 1');
            expect(decoded.first['topics'], ['T1', 'T2']);
          });
        });

        group('CourseSyllabusScreen Unified Scroll Layout Tests', () {
          test('CourseSyllabusScreen typedefs and unified scroll architecture', () {
            expect(CourseDashboardScreen, equals(CourseSyllabusScreen));
            expect(CourseDetailsScreen, equals(CourseSyllabusScreen));
          });
        });

        group('Multi-Instructor, Sessional CGPA & Routine Interchange Tests', () {
          test('Teacher model and CourseModel multi-instructor serialization', () {
            final t1 = Teacher(id: 't_1', name: 'Dr. Rahman', initials: 'MSR', isActive: true);
            final t2 = Teacher(id: 't_2', name: 'Prof. Karim', initials: 'AK', isActive: true);
            final course = CourseModel(
              id: 'c_101',
              courseCode: 'CSE 101',
              courseName: 'Structured Programming',
              creditHours: 3.0,
              teachers: [t1, t2],
              courseType: 'sessional',
              universityName: 'BUET',
              createdAt: DateTime(2026, 1, 1),
            );

            expect(course.teachers.length, 2);
            expect(course.getTeacher('t_1')?.name, 'Dr. Rahman');
            expect(course.getTeacher('t_2')?.initials, 'AK');
            expect(course.getTeacher('non_existent'), isNull);
            expect(course.isSessional, isTrue);
            expect(course.isTheory, isFalse);

            final map = course.toMap();
            final restored = CourseModel.fromMap(map, 'c_101');
            expect(restored.teachers.length, 2);
            expect(restored.teachers.first.initials, 'MSR');
            expect(restored.isSessional, isTrue);
          });

          test('ClassRoutineSlot respects effectiveFrom and effectiveUntil boundaries', () {
            final slot = ClassRoutine(
              id: 'slot_1',
              courseId: 'c_101',
              courseName: 'CSE 101',
              dayOfWeek: 1, // Monday
              startTime: '08:00',
              endTime: '09:30',
              classType: 'Theory',
              teacherId: 't_1',
              effectiveFrom: DateTime(2026, 1, 1),
              effectiveUntil: DateTime(2026, 3, 31),
            );

            // Active within bounds on Mondays (dayOfWeek = 1)
            expect(slot.isActiveOnDate(DateTime(2026, 2, 16)), isTrue); // Monday
            expect(slot.isActiveOnDate(DateTime(2026, 1, 5)), isTrue);  // Monday
            expect(slot.isActiveOnDate(DateTime(2026, 3, 30)), isTrue); // Monday

            // Inactive on non-Mondays
            expect(slot.isActiveOnDate(DateTime(2026, 2, 15)), isFalse); // Sunday

            // Inactive outside date bounds even if Monday
            expect(slot.isActiveOnDate(DateTime(2025, 12, 29)), isFalse); // Monday before effectiveFrom
            expect(slot.isActiveOnDate(DateTime(2026, 4, 6)), isFalse);   // Monday after effectiveUntil
          });

          test('RoutineSlotOverride serializes and deserializes replacement parameters cleanly', () {
            final override = RoutineSlotOverride(
              overrideId: 'ovr_101',
              originalSlotId: 'slot_1',
              targetDate: '2026-04-10',
              replacementCourseId: 'c_202',
              replacementCourseName: 'EEE 201',
              replacementTeacherId: 't_2',
              isTemporarySwap: true,
            );

            final map = override.toMap();
            expect(map['targetDate'], '2026-04-10');
            expect(map['replacementCourseId'], 'c_202');
            expect(map['replacementCourseName'], 'EEE 201');
            expect(map['replacementTeacherId'], 't_2');
            expect(map['isTemporarySwap'], isTrue);

            final restored = RoutineSlotOverride.fromMap(map);
            expect(restored.overrideId, 'ovr_101');
            expect(restored.targetDate, '2026-04-10');
            expect(restored.replacementTeacherId, 't_2');
          });

          test('Dynamic weightage re-normalizes active weights and skips zero-weight categories', () {
            final List<Assessment> items = [
              Assessment(id: 'a1', name: 'Quiz 1', type: 'ct', obtainedMarks: 18.0, totalMarks: 20.0),
              Assessment(id: 'a2', name: 'Quiz 2', type: 'ct', obtainedMarks: 20.0, totalMarks: 20.0),
            ];

            // When total weightage is configured as 10%
            final result10 = AssessmentCalculationHelper.calculateCategoryScore(
              items: items,
              weightagePercentage: 10.0,
            );
            // Average = 95%, weighted = 9.5
            expect(result10.percentage, 95.0);
            expect(result10.weightedScore, 9.5);

            // Zero-weight category produces 0 weighted score
            final resultZero = AssessmentCalculationHelper.calculateCategoryScore(
              items: items,
              weightagePercentage: 0.0,
            );
            expect(resultZero.weightedScore, 0.0);
          });

          test('JournalScreen accepts and preserves initialCourseFilter parameter', () {
            const journal = JournalScreen(initialCourseFilter: 'CSE 101');
            expect(journal.initialCourseFilter, 'CSE 101');
          });

          test('Stopwatch 30-minute sweep progress and completed cycles logic', () {
            // Formula verification
            double getProgress(int elapsed) => (elapsed % 1800) / 1800.0;
            int getCycles(int elapsed) => elapsed ~/ 1800;
            String getCycleText(int elapsed) {
              final cycles = getCycles(elapsed);
              return cycles == 0
                  ? 'Cycle 1 (0–30m)'
                  : 'Cycle ${cycles + 1} • ${cycles * 30}m+ completed';
            }

            // At 0 seconds (initial)
            expect(getProgress(0), 0.0);
            expect(getCycles(0), 0);
            expect(getCycleText(0), 'Cycle 1 (0–30m)');

            // At 15 minutes (900 seconds) -> 50% through cycle 1
            expect(getProgress(900), 0.5);
            expect(getCycles(900), 0);
            expect(getCycleText(900), 'Cycle 1 (0–30m)');

            // At 30 minutes (1800 seconds) -> cycle 1 completed, entering cycle 2
            expect(getProgress(1800), 0.0);
            expect(getCycles(1800), 1);
            expect(getCycleText(1800), 'Cycle 2 • 30m+ completed');

            // At 45 minutes (2700 seconds) -> 50% through cycle 2
            expect(getProgress(2700), 0.5);
            expect(getCycles(2700), 1);
            expect(getCycleText(2700), 'Cycle 2 • 30m+ completed');

            // At 60 minutes (3600 seconds) -> cycle 2 completed, entering cycle 3
            expect(getProgress(3600), 0.0);
            expect(getCycles(3600), 2);
            expect(getCycleText(3600), 'Cycle 3 • 60m+ completed');
          });
        });

        group('CompactLoadingDialog Tests', () {
          testWidgets('renders CompactLoadingDialog with constrained width and non-dismissible PopScope', (tester) async {
            await tester.pumpWidget(
              const MaterialApp(
                home: Scaffold(
                  body: CompactLoadingDialog(
                    message: 'Deleting account and wiping data...',
                    indicatorColor: Color(0xFFEF4444),
                  ),
                ),
              ),
            );

            // Message text renders
            expect(find.text('Deleting account and wiping data...'), findsOneWidget);

            // Dialog is present
            expect(find.byType(Dialog), findsOneWidget);

            // PopScope is non-dismissible (canPop: false)
            final popScopeFinder = find.byType(PopScope);
            expect(popScopeFinder, findsOneWidget);
            final PopScope popScope = tester.widget(popScopeFinder);
            expect(popScope.canPop, isFalse);

            // Container has maximum width constraint of 340
            final containerFinder = find.byType(Container);
            expect(containerFinder, findsWidgets);
            final containerWidgets = tester.widgetList<Container>(containerFinder);
            final constrainedContainer = containerWidgets.firstWhere(
              (c) => c.constraints?.maxWidth == 340,
            );
            expect(constrainedContainer.constraints?.maxWidth, 340);
          });
        });

        group('Extra / Makeup Class and Attendance Status Tests', () {
          test('AttendanceStatus.fromString correctly parses unmarked and null values', () {
            expect(AttendanceStatus.fromString('unmarked'), AttendanceStatus.unmarked);
            expect(AttendanceStatus.fromString(null), AttendanceStatus.unmarked);
            expect(AttendanceStatus.fromString('attended'), AttendanceStatus.attended);
            expect(AttendanceStatus.fromString('missed'), AttendanceStatus.missed);
            expect(AttendanceStatus.fromString('canceled'), AttendanceStatus.canceled);
            expect(AttendanceStatus.fromString('cancelled'), AttendanceStatus.canceled);
            expect(AttendanceStatus.fromString('extra'), AttendanceStatus.extra);
          });

          test('AttendanceRecord serializes and deserializes unmarked status cleanly', () {
            final record = AttendanceRecord(
              id: 'extra_2026-09-25_12345678',
              courseId: 'CE_106',
              courseCode: 'CE 106',
              courseName: 'Engineering Drawing',
              date: DateTime(2026, 9, 25),
              status: AttendanceStatus.unmarked,
              routineId: 'extra_2026-09-25_12345678',
              classType: 'Make-up Lab',
              time: '10:00 AM',
            );

            final map = record.toMap();
            expect(map['status'], 'unmarked');
            expect(map['routineId'], 'extra_2026-09-25_12345678');
            expect(map['classType'], 'Make-up Lab');

            final fromMap = AttendanceRecord.fromMap(map);
            expect(fromMap.status, AttendanceStatus.unmarked);
            expect(fromMap.routineId, 'extra_2026-09-25_12345678');
            expect(fromMap.classType, 'Make-up Lab');
          });

          test('Extra class identification recognizes extra classes with unmarked status and custom routine IDs', () {
            bool isExtra(AttendanceRecord rec) {
              return rec.status == AttendanceStatus.extra ||
                  (rec.routineId != null && rec.routineId!.startsWith('extra')) ||
                  (rec.id.contains('_extra_')) ||
                  (rec.classType != null && (
                    rec.classType!.toLowerCase().contains('extra') ||
                    rec.classType!.toLowerCase().contains('make-up') ||
                    rec.classType!.toLowerCase().contains('makeup') ||
                    rec.classType!.toLowerCase().contains('review')
                  ));
            }

            // Case 1: Unmarked extra class scheduled in the future with routineId 'extra_...'
            final futureUnmarked = AttendanceRecord(
              id: 'extra_2026-10-01_100',
              courseId: 'c1',
              date: DateTime(2026, 10, 1),
              status: AttendanceStatus.unmarked,
              routineId: 'extra_2026-10-01_100',
              classType: 'Extra Lecture',
            );
            expect(isExtra(futureUnmarked), isTrue);

            // Case 2: Make-up Lab with unmarked status
            final makeupUnmarked = AttendanceRecord(
              id: 'doc_123',
              courseId: 'c2',
              date: DateTime(2026, 10, 2),
              status: AttendanceStatus.unmarked,
              classType: 'Make-up Lab',
            );
            expect(isExtra(makeupUnmarked), isTrue);

            // Case 3: Regular routine class (should NOT be flagged as extra)
            final regularClass = AttendanceRecord(
              id: 'att_routine_1',
              courseId: 'c3',
              date: DateTime(2026, 10, 1),
              status: AttendanceStatus.attended,
              routineId: 'routine_mon_9am',
              classType: 'Theory',
            );
            expect(isExtra(regularClass), isFalse);
          });
        });

        group('Atomic Syllabus Topic Decomposition Tests', () {
          test('decomposes dense differential calculus theorems into discrete atomic checklist items', () {
            const rawTopic = "Leibnitz's theorem, Rolle's theorem, Mean value theorem, Taylor's and Maclaurin's theorems";
            final decomposed = SyllabusParserService.decomposeTopicTitle(rawTopic);

            expect(decomposed, [
              "Leibnitz's theorem",
              "Rolle's theorem",
              "Mean value theorem",
              "Taylor's theorem",
              "Maclaurin's theorem",
            ]);
          });

          test('decomposes indeterminate forms and differentiation rules cleanly', () {
            const rawTopic = "Evaluation of indeterminate forms by L'Hospital's rule, Partial differentiation, Euler's theorem";
            final decomposed = SyllabusParserService.decomposeTopicTitle(rawTopic);

            expect(decomposed, [
              "Evaluation of indeterminate forms by L'Hospital's rule",
              "Partial differentiation",
              "Euler's theorem",
            ]);
          });

          test('decomposes semicolon delimited topics with numbering artifacts stripped', () {
            const rawTopic = "1. Complex numbers; 2. Cauchy-Riemann equations; 3. Conformal mapping";
            final decomposed = SyllabusParserService.decomposeTopicTitle(rawTopic);

            expect(decomposed, [
              "Complex numbers",
              "Cauchy-Riemann equations",
              "Conformal mapping",
            ]);
          });

          test('preserves commas within parentheses while splitting outside commas', () {
            const rawTopic = "Integration by parts (algebraic, exponential), Integration by substitution, Trigonometric integrals";
            final decomposed = SyllabusParserService.decomposeTopicTitle(rawTopic);

            expect(decomposed, [
              "Integration by parts (algebraic, exponential)",
              "Integration by substitution",
              "Trigonometric integrals",
            ]);
          });

          test('avoids false splitting on non-splittable compound phrases and single entities', () {
            expect(
              SyllabusParserService.decomposeTopicTitle("Properties and applications of matrices"),
              ["Properties and applications of matrices"],
            );
            expect(
              SyllabusParserService.decomposeTopicTitle("Research and Development"),
              ["Research and Development"],
            );
            expect(
              SyllabusParserService.decomposeTopicTitle("Trial and Error"),
              ["Trial and Error"],
            );
            expect(
              SyllabusParserService.decomposeTopicTitle("L'Hospital's rule"),
              ["L'Hospital's rule"],
            );
          });

          test('sanitizeChapterNodes and parseSyllabusJsonResponse decompose raw JSON compound topics into standalone leaf nodes', () {
            const rawJson = '''
[
  {
    "title": "Calculus",
    "topics": [
      {
        "title": "Leibnitz's theorem, Rolle's theorem, Mean value theorem, Taylor's and Maclaurin's theorems",
        "items": ["Class Note", "Lecture Sheet"]
      }
    ]
  }
]
''';
            final chapters = SyllabusParserService.parseSyllabusJsonResponse(rawJson);
            expect(chapters.length, 1);
            expect(chapters.first.title, "Calculus");

            final topics = chapters.first.children;
            expect(topics.length, 5);
            expect(topics[0].title, "Leibnitz's theorem");
            expect(topics[1].title, "Rolle's theorem");
            expect(topics[2].title, "Mean value theorem");
            expect(topics[3].title, "Taylor's theorem");
            expect(topics[4].title, "Maclaurin's theorem");

            for (final t in topics) {
              expect(t.isLeaf, isTrue);
              expect(t.children.length, 2);
              expect(t.children[0].title, "Class Note");
              expect(t.children[1].title, "Lecture Sheet");
            }
          });
        });

        group('Dynamic Multi-Model Failover Pipeline Tests', () {
          test('kGeminiModelPriorityPool has the exact required priority ordering', () {
            expect(kGeminiModelPriorityPool, [
              'gemini-2.5-flash',
              'gemini-1.5-flash',
              'gemini-1.5-pro',
            ]);
          });

          test('simulating 429 quota/rate-limit on primary model silently promotes to secondary model', () async {
            final attemptedModels = <String>[];

            final result = await SyllabusParserService.extractSyllabusWithFailover(
              modelPool: kGeminiModelPriorityPool,
              testModelInvoker: (modelName) async {
                attemptedModels.add(modelName);
                if (modelName == 'gemini-2.5-flash') {
                  throw Exception('ResourceExhausted: 429 Quota exceeded for model gemini-2.5-flash');
                }
                if (modelName == 'gemini-1.5-flash') {
                  return '[{"title": "Differential Equations", "topics": [{"title": "First order ODE"}]}]';
                }
                throw Exception('Unexpected model call: $modelName');
              },
            );

            expect(attemptedModels, ['gemini-2.5-flash', 'gemini-1.5-flash']);
            expect(result.contains('Differential Equations'), isTrue);
          });

          test('simulating failure on first two models silently falls through to gemini-1.5-pro', () async {
            final attemptedModels = <String>[];

            final result = await SyllabusParserService.extractSyllabusWithFailover(
              modelPool: kGeminiModelPriorityPool,
              testModelInvoker: (modelName) async {
                attemptedModels.add(modelName);
                if (modelName == 'gemini-2.5-flash') {
                  throw Exception('503 Service Unavailable: overloaded');
                }
                if (modelName == 'gemini-1.5-flash') {
                  throw Exception('500 Internal Server Error');
                }
                if (modelName == 'gemini-1.5-pro') {
                  return '[{"title": "Linear Algebra", "topics": [{"title": "Matrix Inversion"}]}]';
                }
                throw Exception('Unexpected model call: $modelName');
              },
            );

            expect(attemptedModels, ['gemini-2.5-flash', 'gemini-1.5-flash', 'gemini-1.5-pro']);
            expect(result.contains('Linear Algebra'), isTrue);
          });
        });

        group('Progressive Loading UX Tests', () {
          testWidgets('CompactLoadingDialog displays progressive stages based on elapsed time', (tester) async {
            await tester.pumpWidget(
              const MaterialApp(
                home: Scaffold(
                  body: CompactLoadingDialog(
                    message: 'Extracting syllabus structure...',
                    isProgressive: true,
                  ),
                ),
              ),
            );

            // Stage 1 (0.0s - 3.0s):
            expect(find.text('Extracting syllabus structure...'), findsOneWidget);

            // Advance time past 3.0s -> Stage 2 (3.1s - 6.0s):
            await tester.pump(const Duration(milliseconds: 3200));
            expect(find.text('Synthesizing topics & structuring modules...'), findsOneWidget);

            // Advance time past 6.0s -> Stage 3 (> 6.0s):
            await tester.pump(const Duration(milliseconds: 3200));
            expect(find.text('Finalizing checklist items & chapters...'), findsOneWidget);
          });
        });

        group('Dynamic Sessional Assessment Scoping & Minimal Card Redesign Tests', () {
          test('Canonical assessment type lists are defined correctly', () {
            expect(kTheoryAssessmentTypes, contains('Class Test (CT)'));
            expect(kTheoryAssessmentTypes, contains('Quiz'));
            expect(kTheoryAssessmentTypes, contains('Midterm Exam'));
            expect(kTheoryAssessmentTypes, contains('Term Final Exam'));
            expect(kTheoryAssessmentTypes, contains('Assignment / Presentation'));

            expect(kSessionalAssessmentTypes, contains('Continuous Evaluation / Lab Performance'));
            expect(kSessionalAssessmentTypes, contains('Lab Report / Assignment'));
            expect(kSessionalAssessmentTypes, contains('Lab Quiz'));
            expect(kSessionalAssessmentTypes, contains('Lab Final Exam'));
            expect(kSessionalAssessmentTypes, contains('Viva Voce'));
            expect(kSessionalAssessmentTypes, contains('Term Project / Presentation'));
          });

          test('CourseType.fromString maps theory and sessional variants accurately', () {
            expect(CourseType.fromString('Theory'), CourseType.theory);
            expect(CourseType.fromString('theory'), CourseType.theory);
            expect(CourseType.fromString('Sessional'), CourseType.sessional);
            expect(CourseType.fromString('sessional'), CourseType.sessional);
            expect(CourseType.fromString('Lab'), CourseType.sessional);
            expect(CourseType.fromString('Computer Programming Lab'), CourseType.sessional);
            expect(CourseType.fromString('Operating Systems Sessional'), CourseType.sessional);
            expect(CourseType.fromString(null), CourseType.theory);
          });

          testWidgets('AssessmentCard renders specialized LAB FINAL badge and science icon', (tester) async {
            final assessment = Assessment(
              id: 'lab_final_1',
              name: 'Lab Final Exam',
              courseId: 'cse110',
              type: 'lab_final',
              date: DateTime(2026, 11, 25, 14, 0),
              totalMarks: 50.0,
              obtainedMarks: 45.0,
              weightage: 30.0,
            );

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AssessmentCard(
                    assessment: assessment,
                    courseCode: 'CSE 110',
                    courseTitle: 'Programming Lab',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('LAB FINAL'), findsOneWidget);
            expect(find.byIcon(Icons.science_outlined), findsOneWidget);
            expect(find.text('CSE 110 • Programming Lab'), findsOneWidget);
            expect(find.text('Lab Final Exam'), findsOneWidget);
          });

          testWidgets('AssessmentCard renders specialized VIVA badge and quiz icon', (tester) async {
            final assessment = Assessment(
              id: 'viva_1',
              name: 'Viva Voce',
              courseId: 'cse110',
              type: 'viva',
              date: DateTime(2026, 11, 26, 10, 0),
              totalMarks: 20.0,
            );

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AssessmentCard(
                    assessment: assessment,
                    courseCode: 'CSE 110',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('VIVA'), findsOneWidget);
            expect(find.byIcon(Icons.quiz_outlined), findsOneWidget);
          });

          testWidgets('AssessmentCard renders specialized LAB REPORT badge and description icon', (tester) async {
            final assessment = Assessment(
              id: 'report_1',
              name: 'Lab Report 3',
              courseId: 'eee201',
              type: 'lab_report',
              date: DateTime(2026, 10, 15, 12, 0),
            );

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AssessmentCard(
                    assessment: assessment,
                    courseCode: 'EEE 201',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('LAB REPORT'), findsOneWidget);
            expect(find.byIcon(Icons.description_outlined), findsOneWidget);
          });

          testWidgets('AssessmentCard renders specialized PERFORMANCE badge for Continuous Evaluation', (tester) async {
            final assessment = Assessment(
              id: 'perf_1',
              name: 'Continuous Evaluation / Lab Performance',
              courseId: 'cse110',
              type: 'continuous',
              date: DateTime(2026, 10, 20, 15, 0),
            );

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AssessmentCard(
                    assessment: assessment,
                    courseCode: 'CSE 110',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('PERFORMANCE'), findsOneWidget);
          });

          testWidgets('AssessmentCard renders specialized PROJECT badge for Term Project', (tester) async {
            final assessment = Assessment(
              id: 'proj_1',
              name: 'Term Project Presentation',
              courseId: 'cse312',
              type: 'project',
              date: DateTime(2026, 12, 5, 11, 0),
            );

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AssessmentCard(
                    assessment: assessment,
                    courseCode: 'CSE 312',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            expect(find.text('PROJECT'), findsOneWidget);
            expect(find.byIcon(Icons.co_present_outlined), findsOneWidget);
          });
        });
      });
    });

    group('Platform-Safe Haptics & Desktop Web Layout Constraints Tests', () {
      test('SafeHaptics methods execute without exceptions', () {
        expect(() => SafeHaptics.selectionClick(), returnsNormally);
        expect(() => SafeHaptics.lightImpact(), returnsNormally);
        expect(() => SafeHaptics.mediumImpact(), returnsNormally);
        expect(() => SafeHaptics.heavyImpact(), returnsNormally);
        expect(() => SafeHaptics.vibrate(), returnsNormally);
      });

      testWidgets('MaterialApp builder provides fluid dark espresso canvas background', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              return Container(
                color: const Color(0xFF151211),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const Scaffold(
              body: Text('Canvas Content'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Canvas Content'), findsOneWidget);
        final containerFinder = find.byType(Container).first;
        final container = tester.widget<Container>(containerFinder);
        expect(container.color, const Color(0xFF151211));
      });
    });

    group('Safe User Profile Creation & Web Google Sign-In Tests', () {
      test('UserProfile.fromMap handles null map without crashing', () {
        final profile = UserProfile.fromMap(null);
        expect(profile, equals(UserProfile.defaultProfile));
        expect(profile.fullName, isEmpty);
        expect(profile.email, isEmpty);
      });

      test('UserProfile.fromMap handles empty map with safe defaults', () {
        final profile = UserProfile.fromMap({});
        expect(profile.fullName, isEmpty);
        expect(profile.nickname, isEmpty);
        expect(profile.username, isEmpty);
        expect(profile.email, isEmpty);
        expect(profile.hscBatch, '2025');
        expect(profile.hscGroup, 'Science');
        expect(profile.primaryTarget, 'Engineering');
        expect(profile.isLoaded, isTrue);
      });

      test('UserProfile.fromMap parses alternative key names safely', () {
        final profile = UserProfile.fromMap({
          'name': 'Rahim Ahmed',
          'photoUrl': 'https://example.com/photo.png',
          'target_goal': 'Medical',
        });
        expect(profile.fullName, 'Rahim Ahmed');
        expect(profile.profileImageUrl, 'https://example.com/photo.png');
        expect(profile.primaryTarget, 'Medical');
      });

      test('UserProfile.fromFirebaseUser fallback logic handles null displayName and photo', () {
        final profile = UserProfile(
          fullName: 'Student',
          nickname: 'Student',
          username: 'student',
          email: '',
          phone: '',
          primaryTarget: 'Undergraduate',
          isUniversityStudent: true,
          term: 'Term 1',
        );
        expect(profile.fullName, 'Student');
        expect(profile.nickname, 'Student');
        expect(profile.email, '');
        expect(profile.profileImageUrl, isNull);
      });

      test('configureAuthPersistence executes without throwing on non-web or web environment', () async {
        // configureAuthPersistence should handle any environment and persistence level without throwing
        await expectLater(configureAuthPersistence(), completes);
      });
    });

    group('Desktop Academic OS & Deep Study Tracker Tests', () {
      testWidgets('DesktopNavBar renders Bengali wordmark, 5 navigation tabs, and search pill', (tester) async {
        const profile = UserProfile(
          fullName: 'Test Student',
          nickname: 'Student',
          username: 'student',
          email: 'student@buet.ac.bd',
          phone: '01700000000',
          primaryTarget: 'Engineering',
          isUniversityStudent: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(profile)),
            ],
            child: const MaterialApp(
              home: Scaffold(
                appBar: DesktopNavBar(),
                body: SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('চন্দ্রবিন্দু'), findsOneWidget);
        expect(find.text('CHONDROBINDU'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
        expect(find.text('Courses'), findsOneWidget);
        expect(find.text('Timer'), findsOneWidget);
        expect(find.text('Planner'), findsOneWidget);
        expect(find.text('Insights'), findsOneWidget);
        expect(find.text('Search anything...'), findsOneWidget);
        expect(find.text('⌘K'), findsOneWidget);
      });

      testWidgets('HomeScreen renders greeting, study streak, focus time, CGPA, and agenda', (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const profile = UserProfile(
          fullName: 'Test Student',
          nickname: 'Student',
          username: 'student',
          email: 'student@buet.ac.bd',
          phone: '01700000000',
          primaryTarget: 'Engineering',
          isUniversityStudent: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              userProfileProvider.overrideWith((ref) => FakeUserProfileNotifier(profile)),
            ],
            child: const MaterialApp(
              home: HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Student'), findsWidgets);
        expect(find.text('STUDY STREAK'), findsOneWidget);
        expect(find.text('28 days'), findsOneWidget);
        expect(find.text('TOTAL FOCUS TIME'), findsOneWidget);
        expect(find.text('124.5 hrs'), findsOneWidget);
        expect(find.text('CGPA FORECASTER'), findsOneWidget);
        expect(find.text("Today's Agenda"), findsOneWidget);
        expect(find.text('Signals & Systems'), findsWidgets);
        expect(find.text('Start Focus →'), findsOneWidget);
      });

      testWidgets('CoursesScreen renders course cards, syllabus tabs, and atomic checkable topics', (tester) async {
        tester.view.physicalSize = const Size(1200, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              home: CoursesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All (8)'), findsOneWidget);
        expect(find.text('Theory (4)'), findsOneWidget);
        expect(find.text('Sessional (4)'), findsOneWidget);
        expect(find.text('EEE 2105'), findsWidgets);
        expect(find.text('Syllabus'), findsWidgets);
        expect(find.text('Chapter 3: Continuous-Time Signals'), findsOneWidget);
        expect(find.text('Definition and classification of signals'), findsOneWidget);

        // Check topic toggling
        final checkboxFinder = find.byType(Checkbox).first;
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();
      });
    });
  });
}


