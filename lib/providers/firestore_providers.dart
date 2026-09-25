import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';
import '../models/routine_slot_model.dart';
import '../models/assessment_model.dart';
import '../models/study_session_model.dart';
import '../repositories/user_repository.dart';
import '../repositories/course_repository.dart';
import '../repositories/routine_repository.dart';
import '../repositories/assessment_repository.dart';
import '../repositories/study_session_repository.dart';
import '../services/data_seed_service.dart';
import 'user_profile_provider.dart';

// --- Repositories ---
final userRepositoryProvider = Provider<UserRepository>((ref) => UserRepository());
final courseRepositoryProvider = Provider<CourseRepository>((ref) => CourseRepository());
final routineRepositoryProvider = Provider<RoutineRepository>((ref) => RoutineRepository());
final assessmentRepositoryProvider = Provider<AssessmentRepository>((ref) => AssessmentRepository());
final studySessionRepositoryProvider = Provider<StudySessionRepository>((ref) => StudySessionRepository());
final dataSeedServiceProvider = Provider<DataSeedService>((ref) => DataSeedService());

String _getSafeCurrentUid() {
  if (Firebase.apps.isEmpty) return '';
  return FirebaseAuth.instance.currentUser?.uid ?? '';
}

// --- Current User ID Provider ---
final currentUserIdProvider = StreamProvider<String>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value('');
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid ?? '');
});

// --- User Profile Stream Provider ---
final liveUserProfileProvider = StreamProvider<UserProfile>((ref) {
  final fallback = ref.watch(userProfileProvider);
  if (Firebase.apps.isEmpty) return Stream.value(fallback);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) {
    return Stream.value(fallback);
  }
  return ref.watch(userRepositoryProvider).watchUserProfile(uid);
});

// --- Courses Stream Provider ---
final coursesStreamProvider = StreamProvider<List<Course>>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(courseRepositoryProvider).watchCourses(uid);
});

// --- Syllabus Topics Family Stream Provider ---
final syllabusTopicsStreamProvider = StreamProvider.family<List<SyllabusTopic>, String>((ref, courseId) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty || courseId.isEmpty) return Stream.value([]);
  return ref.watch(courseRepositoryProvider).watchSyllabus(uid, courseId);
});

// --- Weekly Routine Stream Provider ---
final weeklyRoutineStreamProvider = StreamProvider<List<RoutineSlot>>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(routineRepositoryProvider).watchWeeklyRoutine(uid);
});

// --- Daily Agenda Stream Provider ---
final dailyAgendaStreamProvider = StreamProvider.family<List<RoutineSlot>, DateTime>((ref, date) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(routineRepositoryProvider).watchDailyAgenda(uid, date);
});

// --- Upcoming Assessments Stream Provider ---
final upcomingAssessmentsStreamProvider = StreamProvider<List<Assessment>>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(assessmentRepositoryProvider).watchUpcomingAssessments(uid);
});

// --- All Assessments Stream Provider ---
final allAssessmentsStreamProvider = StreamProvider<List<Assessment>>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(assessmentRepositoryProvider).watchAllAssessments(uid);
});

// --- Study Sessions for Date Stream Provider ---
final studySessionsDateStreamProvider = StreamProvider.family<List<StudySession>, DateTime>((ref, date) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(studySessionRepositoryProvider).watchSessionsForDate(uid, date);
});

// --- Study Sessions Range Parameter Class ---
class DateRangeParam {
  final DateTime start;
  final DateTime end;
  const DateRangeParam(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateRangeParam &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => start.hashCode ^ end.hashCode;
}

final studySessionsRangeStreamProvider = StreamProvider.family<List<StudySession>, DateRangeParam>((ref, range) {
  if (Firebase.apps.isEmpty) return Stream.value([]);
  final uidAsync = ref.watch(currentUserIdProvider);
  final uid = uidAsync.value ?? _getSafeCurrentUid();
  if (uid.isEmpty) return Stream.value([]);
  return ref.watch(studySessionRepositoryProvider).watchSessionsRange(uid, range.start, range.end);
});
