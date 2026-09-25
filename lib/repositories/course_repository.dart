import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';

class CourseRepository {
  final FirebaseFirestore? _firestore;

  CourseRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  CollectionReference<Map<String, dynamic>>? _coursesRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('courses');

  CollectionReference<Map<String, dynamic>>? _topicsRef(String uid, String courseId) =>
      _coursesRef(uid)?.doc(courseId).collection('topics');

  Stream<List<Course>> watchCourses(String uid) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _coursesRef(uid)!.snapshots().map((snapshot) {
      final courses = snapshot.docs.map((doc) => Course.fromFirestore(doc)).toList();
      courses.sort((a, b) => CourseService.compareCourseCodes(a.code, b.code));
      return courses;
    });
  }

  Stream<List<SyllabusTopic>> watchSyllabus(String uid, String courseId) {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty) return Stream.value([]);
    return _topicsRef(uid, courseId)!
        .orderBy('chapterOrder')
        .snapshots()
        .map((snapshot) {
      final topics = snapshot.docs.map((doc) => SyllabusTopic.fromFirestore(doc)).toList();
      topics.sort((a, b) {
        final cOrder = a.chapterOrder.compareTo(b.chapterOrder);
        if (cOrder != 0) return cOrder;
        return a.topicIndex.compareTo(b.topicIndex);
      });
      return topics;
    });
  }

  Future<void> toggleTopicStatus(
    String uid,
    String courseId,
    String topicId,
    bool isCompleted,
  ) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty || topicId.isEmpty) return;

    final topicDoc = _topicsRef(uid, courseId)!.doc(topicId);
    final courseDoc = _coursesRef(uid)!.doc(courseId);

    await _firestore!.runTransaction((transaction) async {
      transaction.update(topicDoc, {
        'isCompleted': isCompleted,
        'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
      });

      // Recalculate completed count
      final allTopicsSnap = await _topicsRef(uid, courseId)!.get();
      int completed = 0;
      int total = allTopicsSnap.docs.length;

      for (final doc in allTopicsSnap.docs) {
        if (doc.id == topicId) {
          if (isCompleted) completed++;
        } else {
          final data = doc.data();
          if (data['isCompleted'] == true) completed++;
        }
      }

      transaction.update(courseDoc, {
        'totalTopicsCount': total,
        'completedTopicsCount': completed,
      });
    });
  }

  Future<void> addCourse(String uid, Course course) async {
    if (_firestore == null || uid.isEmpty) return;
    await _coursesRef(uid)!.doc(course.id).set(course.toMap(), SetOptions(merge: true));
  }

  Future<void> addTopics(String uid, String courseId, List<SyllabusTopic> topics) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty || topics.isEmpty) return;
    final batch = _firestore!.batch();
    for (final topic in topics) {
      final ref = _topicsRef(uid, courseId)!.doc(topic.id);
      batch.set(ref, topic.toMap(), SetOptions(merge: true));
    }

    // Update parent course total topics count
    final courseDoc = _coursesRef(uid)!.doc(courseId);
    batch.update(courseDoc, {
      'totalTopicsCount': FieldValue.increment(topics.length),
    });

    await batch.commit();
  }

  Future<void> archiveCourse(String uid, String courseId, bool isArchived) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty) return;
    await _coursesRef(uid)!.doc(courseId).update({'isArchived': isArchived});
  }
}
