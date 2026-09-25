import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_profile.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';
import '../models/routine_slot_model.dart';
import '../models/assessment_model.dart';

class DataSeedService {
  final FirebaseFirestore? _firestore;

  DataSeedService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  Future<bool> hasUserData(String uid) async {
    if (_firestore == null || uid.isEmpty) return false;
    final coursesSnap = await _firestore!
        .collection('users')
        .doc(uid)
        .collection('courses')
        .limit(1)
        .get();
    return coursesSnap.docs.isNotEmpty;
  }

  Future<void> seedInitialTrackData(String uid, InstitutionType track) async {
    if (_firestore == null || uid.isEmpty) return;

    final batch = _firestore!.batch();
    final userRef = _firestore!.collection('users').doc(uid);

    if (track == InstitutionType.university) {
      // 1. Update Profile for University
      batch.set(userRef, {
        'institutionType': 'university',
        'isUniversityStudent': true,
        'department': 'EEE',
        'major': 'EEE',
        'level': 'Level 2',
        'term': 'Term 1',
        'universityName': 'BUET',
        'batch': '2023',
        'targetGpa': 3.75,
        'streakDays': 28,
        'totalFocusMinutes': 7470, // 124.5 hrs
        'todaysFocusMinutes': 130, // 2h 10m
        'lastStudiedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));

      // 2. Seed University Courses
      final courses = [
        const Course(
          id: 'course_eee2105',
          code: 'EEE 2105',
          title: 'Signals & Systems',
          courseType: CourseType.theory,
          credits: 3.0,
          colorHex: '#F2B78A',
          teacherInitials: ['MSR', 'ARH'],
          totalTopicsCount: 12,
          completedTopicsCount: 3,
        ),
        const Course(
          id: 'course_eee2106',
          code: 'EEE 2106',
          title: 'Signals & Systems Sessional',
          courseType: CourseType.sessional,
          credits: 1.5,
          colorHex: '#34D399',
          teacherInitials: ['ARH'],
          totalTopicsCount: 8,
          completedTopicsCount: 2,
        ),
        const Course(
          id: 'course_cse2101',
          code: 'CSE 2101',
          title: 'Data Structures & Algorithms',
          courseType: CourseType.theory,
          credits: 3.0,
          colorHex: '#60A5FA',
          teacherInitials: ['TBA'],
          totalTopicsCount: 15,
          completedTopicsCount: 5,
        ),
        const Course(
          id: 'course_math2103',
          code: 'MATH 2103',
          title: 'Complex Variables & Laplace',
          courseType: CourseType.theory,
          credits: 3.0,
          colorHex: '#F472B6',
          teacherInitials: ['KMA'],
          totalTopicsCount: 10,
          completedTopicsCount: 4,
        ),
      ];

      for (final c in courses) {
        final cRef = userRef.collection('courses').doc(c.id);
        batch.set(cRef, c.toMap(), SetOptions(merge: true));
      }

      // 3. Seed Syllabus Topics for EEE 2105
      final topics = [
        const SyllabusTopic(
          id: 'topic_3_1',
          chapterTitle: 'Chapter 3: Continuous-Time Signals',
          chapterOrder: 3,
          topicIndex: '3.1',
          title: 'Definition and classification of signals',
          isCompleted: true,
        ),
        const SyllabusTopic(
          id: 'topic_3_2',
          chapterTitle: 'Chapter 3: Continuous-Time Signals',
          chapterOrder: 3,
          topicIndex: '3.2',
          title: 'Elementary continuous-time signals',
          isCompleted: true,
        ),
        const SyllabusTopic(
          id: 'topic_3_3',
          chapterTitle: 'Chapter 3: Continuous-Time Signals',
          chapterOrder: 3,
          topicIndex: '3.3',
          title: 'Time shifting and scaling',
          isInProgress: true,
          isCompleted: false,
        ),
        const SyllabusTopic(
          id: 'topic_3_4',
          chapterTitle: 'Chapter 3: Continuous-Time Signals',
          chapterOrder: 3,
          topicIndex: '3.4',
          title: 'Signal addition and multiplication',
          isCompleted: false,
        ),
        const SyllabusTopic(
          id: 'topic_4_1',
          chapterTitle: 'Chapter 4: Fourier Series Representation',
          chapterOrder: 4,
          topicIndex: '4.1',
          title: 'Trigonometric Fourier Series formulation',
          isCompleted: false,
        ),
        const SyllabusTopic(
          id: 'topic_4_2',
          chapterTitle: 'Chapter 4: Fourier Series Representation',
          chapterOrder: 4,
          topicIndex: '4.2',
          title: 'Exponential Fourier Series & Dirichlet conditions',
          isCompleted: false,
        ),
      ];

      for (final t in topics) {
        final tRef = userRef
            .collection('courses')
            .doc('course_eee2105')
            .collection('topics')
            .doc(t.id);
        batch.set(tRef, t.toMap(), SetOptions(merge: true));
      }

      // 4. Seed University Routine Slots
      final slots = [
        // Monday
        const RoutineSlot(
          id: 'slot_mon_1',
          courseId: 'course_eee2105',
          courseCode: 'EEE 2105',
          courseTitle: 'Signals & Systems',
          dayOfWeek: 1, // Monday
          startTime: '08:00 AM',
          endTime: '09:00 AM',
          room: 'ECE 302',
          teacherBadge: 'MSR',
          slotType: CourseType.theory,
        ),
        const RoutineSlot(
          id: 'slot_mon_2',
          courseId: 'course_cse2101',
          courseCode: 'CSE 2101',
          courseTitle: 'Data Structures',
          dayOfWeek: 1,
          startTime: '10:00 AM',
          endTime: '11:30 AM',
          room: 'ECE 401',
          teacherBadge: 'TBA',
          slotType: CourseType.theory,
        ),
        // Tuesday
        const RoutineSlot(
          id: 'slot_tue_1',
          courseId: 'course_eee2106',
          courseCode: 'EEE 2106',
          courseTitle: 'Signals Lab',
          dayOfWeek: 2, // Tuesday
          startTime: '02:00 PM',
          endTime: '05:00 PM',
          room: 'DSP Lab',
          teacherBadge: 'ARH',
          slotType: CourseType.sessional,
        ),
        // Wednesday
        const RoutineSlot(
          id: 'slot_wed_1',
          courseId: 'course_math2103',
          courseCode: 'MATH 2103',
          courseTitle: 'Complex Variables',
          dayOfWeek: 3,
          startTime: '09:00 AM',
          endTime: '10:00 AM',
          room: 'ECE 302',
          teacherBadge: 'KMA',
          slotType: CourseType.theory,
        ),
        // Thursday
        const RoutineSlot(
          id: 'slot_thu_1',
          courseId: 'course_eee2105',
          courseCode: 'EEE 2105',
          courseTitle: 'Signals & Systems',
          dayOfWeek: 4,
          startTime: '08:00 AM',
          endTime: '09:00 AM',
          room: 'ECE 302',
          teacherBadge: 'MSR',
          slotType: CourseType.theory,
        ),
        const RoutineSlot(
          id: 'slot_thu_2',
          courseId: 'course_cse2101',
          courseCode: 'CSE 2101',
          courseTitle: 'Data Structures',
          dayOfWeek: 4,
          startTime: '11:00 AM',
          endTime: '12:30 PM',
          room: 'ECE 401',
          teacherBadge: 'TBA',
          slotType: CourseType.theory,
        ),
        // Sunday
        const RoutineSlot(
          id: 'slot_sun_1',
          courseId: 'course_eee2105',
          courseCode: 'EEE 2105',
          courseTitle: 'Signals & Systems',
          dayOfWeek: 7, // Sunday
          startTime: '10:00 AM',
          endTime: '11:00 AM',
          room: 'ECE 302',
          teacherBadge: 'MSR',
          slotType: CourseType.theory,
        ),
      ];

      for (final s in slots) {
        final sRef = userRef.collection('routine_slots').doc(s.id);
        batch.set(sRef, s.toMap(), SetOptions(merge: true));
      }

      // 5. Seed University Assessments
      final now = DateTime.now();
      final assessments = [
        Assessment(
          id: 'assess_1',
          courseId: 'course_eee2105',
          courseCode: 'EEE 2105',
          title: 'Class Test 2 (Fourier Transform)',
          type: 'ct',
          dueDate: now.add(const Duration(days: 4)),
          totalMarks: 20.0,
          weightPercentage: 10.0,
          assignedTeacher: 'MSR',
          status: 'Pending',
        ),
        Assessment(
          id: 'assess_2',
          courseId: 'course_cse2101',
          courseCode: 'CSE 2101',
          title: 'Midterm Examination',
          type: 'midterm',
          dueDate: now.add(const Duration(days: 12)),
          totalMarks: 50.0,
          weightPercentage: 25.0,
          assignedTeacher: 'TBA',
          status: 'Pending',
        ),
        Assessment(
          id: 'assess_3',
          courseId: 'course_eee2106',
          courseCode: 'EEE 2106',
          title: 'Lab Report 3: Filter Design',
          type: 'lab_report',
          dueDate: now.add(const Duration(days: 7)),
          totalMarks: 15.0,
          weightPercentage: 5.0,
          assignedTeacher: 'ARH',
          status: 'Pending',
        ),
      ];

      for (final a in assessments) {
        final aRef = userRef.collection('assessments').doc(a.id);
        batch.set(aRef, a.toMap(), SetOptions(merge: true));
      }
    } else {
      // 1. Update Profile for College
      batch.set(userRef, {
        'institutionType': 'college',
        'isUniversityStudent': false,
        'collegeClass': 'Class 12',
        'academicGroup': 'Science',
        'college': 'Dhaka College',
        'batch': 'HSC 2026',
        'targetGpa': 5.00,
        'streakDays': 21,
        'totalFocusMinutes': 6120, // 102 hrs
        'todaysFocusMinutes': 90,
        'lastStudiedAt': Timestamp.fromDate(DateTime.now()),
      }, SetOptions(merge: true));

      // 2. Seed College Courses
      final courses = [
        const Course(
          id: 'course_phy101',
          code: 'PHY 101',
          title: 'Physics 1st Paper',
          courseType: CourseType.theory,
          credits: 1.0,
          colorHex: '#F2B78A',
          totalTopicsCount: 16,
          completedTopicsCount: 8,
        ),
        const Course(
          id: 'course_chem101',
          code: 'CHEM 101',
          title: 'Chemistry 1st Paper',
          courseType: CourseType.theory,
          credits: 1.0,
          colorHex: '#34D399',
          totalTopicsCount: 14,
          completedTopicsCount: 6,
        ),
        const Course(
          id: 'course_math101',
          code: 'MATH 101',
          title: 'Higher Mathematics 1st Paper',
          courseType: CourseType.theory,
          credits: 1.0,
          colorHex: '#60A5FA',
          totalTopicsCount: 18,
          completedTopicsCount: 9,
        ),
        const Course(
          id: 'course_bio101',
          code: 'BIO 101',
          title: 'Biology 1st Paper',
          courseType: CourseType.theory,
          credits: 1.0,
          colorHex: '#F472B6',
          totalTopicsCount: 12,
          completedTopicsCount: 4,
        ),
      ];

      for (final c in courses) {
        final cRef = userRef.collection('courses').doc(c.id);
        batch.set(cRef, c.toMap(), SetOptions(merge: true));
      }

      // 3. Seed College Topics for PHY 101
      final topics = [
        const SyllabusTopic(
          id: 'topic_phy_1',
          chapterTitle: 'Chapter 2: Vector Mechanics',
          chapterOrder: 2,
          topicIndex: '2.1',
          title: 'Dot and Cross Products of Vectors',
          isCompleted: true,
        ),
        const SyllabusTopic(
          id: 'topic_phy_2',
          chapterTitle: 'Chapter 2: Vector Mechanics',
          chapterOrder: 2,
          topicIndex: '2.2',
          title: 'Vector Calculus: Gradient and Divergence',
          isCompleted: true,
        ),
        const SyllabusTopic(
          id: 'topic_phy_3',
          chapterTitle: 'Chapter 3: Dynamics',
          chapterOrder: 3,
          topicIndex: '3.1',
          title: 'Newtonian Dynamics and Friction',
          isInProgress: true,
          isCompleted: false,
        ),
      ];

      for (final t in topics) {
        final tRef = userRef
            .collection('courses')
            .doc('course_phy101')
            .collection('topics')
            .doc(t.id);
        batch.set(tRef, t.toMap(), SetOptions(merge: true));
      }

      // 4. Seed College Routine Slots
      final slots = [
        const RoutineSlot(
          id: 'slot_col_1',
          courseId: 'course_phy101',
          courseCode: 'PHY 101',
          courseTitle: 'Physics 1st Paper',
          dayOfWeek: 1, // Monday
          startTime: '09:00 AM',
          endTime: '10:00 AM',
          room: 'Room 204',
          slotType: CourseType.theory,
        ),
        const RoutineSlot(
          id: 'slot_col_2',
          courseId: 'course_chem101',
          courseCode: 'CHEM 101',
          courseTitle: 'Chemistry 1st Paper',
          dayOfWeek: 1,
          startTime: '10:15 AM',
          endTime: '11:15 AM',
          room: 'Lab 1',
          slotType: CourseType.practical,
        ),
      ];

      for (final s in slots) {
        final sRef = userRef.collection('routine_slots').doc(s.id);
        batch.set(sRef, s.toMap(), SetOptions(merge: true));
      }

      // 5. Seed College Assessments
      final now = DateTime.now();
      final assessments = [
        Assessment(
          id: 'col_assess_1',
          courseId: 'course_phy101',
          courseCode: 'PHY 101',
          title: 'Monthly Test (Mechanics)',
          type: 'Monthly Assessment',
          dueDate: now.add(const Duration(days: 5)),
          totalMarks: 25.0,
          weightPercentage: 15.0,
          status: 'Pending',
        ),
        Assessment(
          id: 'col_assess_2',
          courseId: 'course_math101',
          courseCode: 'MATH 101',
          title: 'Pre-Test Exam: Calculus',
          type: 'Pre-Test Exam',
          dueDate: now.add(const Duration(days: 14)),
          totalMarks: 50.0,
          weightPercentage: 30.0,
          status: 'Pending',
        ),
      ];

      for (final a in assessments) {
        final aRef = userRef.collection('assessments').doc(a.id);
        batch.set(aRef, a.toMap(), SetOptions(merge: true));
      }
    }

    await batch.commit();
  }
}
