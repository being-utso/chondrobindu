import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/assessment_model.dart';

class AssessmentRepository {
  final FirebaseFirestore? _firestore;

  AssessmentRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  CollectionReference<Map<String, dynamic>>? _assessmentsRef(String uid) =>
      _firestore?.collection('users').doc(uid).collection('assessments');

  Stream<List<Assessment>> watchUpcomingAssessments(String uid) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _assessmentsRef(uid)!.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => Assessment.fromFirestore(doc)).where((a) {
        return !a.isCompleted && a.status.toLowerCase() != 'attended';
      }).toList();

      list.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return list;
    });
  }

  Stream<List<Assessment>> watchAllAssessments(String uid) {
    if (_firestore == null || uid.isEmpty) return Stream.value([]);
    return _assessmentsRef(uid)!.snapshots().map((snapshot) {
      final list = snapshot.docs.map((doc) => Assessment.fromFirestore(doc)).toList();
      list.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return list;
    });
  }

  Future<void> createAssessment(String uid, Assessment assessment) async {
    if (_firestore == null || uid.isEmpty) return;
    await _assessmentsRef(uid)!.doc(assessment.id).set(assessment.toMap(), SetOptions(merge: true));
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
