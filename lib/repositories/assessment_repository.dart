import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/assessment_model.dart';

class AssessmentRepository {
  final FirebaseFirestore? _firestore;

  AssessmentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  CollectionReference<Map<String, dynamic>>? _assessmentsRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('assessments');

  CollectionReference<Map<String, dynamic>>? _coursesRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('courses');

  Stream<List<Assessment>> watchUpcomingAssessments(String uid) {
    return watchAllAssessments(uid).map((list) {
      return list.where((a) => !a.isCompleted && a.status.toLowerCase() != 'attended').toList();
    });
  }

  Stream<List<Assessment>> watchAllAssessments(String uid) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);

    late StreamController<List<Assessment>> controller;
    List<Assessment> directAssessments = [];
    List<Assessment> courseDocAssessments = [];

    void emitMerged() {
      final Map<String, Assessment> map = {};
      for (final a in courseDocAssessments) {
        if (a.id.isNotEmpty) {
          map[a.id] = a;
        } else if (a.name.isNotEmpty) {
          map['${a.courseId}_${a.name}'] = a;
        }
      }
      for (final a in directAssessments) {
        if (a.id.isNotEmpty) {
          map[a.id] = a;
        } else if (a.name.isNotEmpty) {
          map['${a.courseId}_${a.name}'] = a;
        }
      }
      final merged = map.values.toList();
      merged.sort((a, b) {
        final dA = a.date ?? a.dueDate;
        final dB = b.date ?? b.dueDate;
        if (dA == null && dB == null) return 0;
        if (dA == null) return 1;
        if (dB == null) return -1;
        return dA.compareTo(dB);
      });
      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    StreamSubscription? sub1;
    StreamSubscription? sub2;

    controller = StreamController<List<Assessment>>.broadcast(
      onListen: () {
        sub1 = _assessmentsRef(uid)?.snapshots().listen(
          (snap) {
            directAssessments = snap.docs.map((doc) => Assessment.fromFirestore(doc)).toList();
            emitMerged();
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        sub2 = _coursesRef(uid)?.snapshots().listen(
          (snap) {
            final List<Assessment> fromCourses = [];
            for (final doc in snap.docs) {
              fromCourses.addAll(Assessment.fromCourseData(doc.data(), courseId: doc.id));
            }
            courseDocAssessments = fromCourses;
            emitMerged();
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> createAssessment(String uid, Assessment assessment) async {
    if (_firestore == null || uid.isEmpty) return;
    await _assessmentsRef(uid)!.doc(assessment.id).set(assessment.toMap(), SetOptions(merge: true));
  }

  Future<void> updateAssessment(String uid, Assessment assessment) async {
    await createAssessment(uid, assessment);
  }

  Future<void> toggleAssessmentCompleted(
    String uid,
    String assessmentId,
    bool isCompleted, [
    double? obtainedMarks,
  ]) async {
    if (_firestore == null || uid.isEmpty || assessmentId.isEmpty) return;
    final Map<String, dynamic> updates = {
      'status': isCompleted ? 'Attended' : 'Pending',
      'isCompleted': isCompleted,
    };
    if (obtainedMarks != null) {
      updates['obtainedMarks'] = obtainedMarks;
      updates['obtained'] = obtainedMarks;
    }
    await _assessmentsRef(uid)!.doc(assessmentId).update(updates);
  }

  Future<void> deleteAssessment(String uid, String assessmentId) async {
    if (_firestore == null || uid.isEmpty || assessmentId.isEmpty) return;
    await _assessmentsRef(uid)!.doc(assessmentId).delete();
  }
}
