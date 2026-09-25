import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/assessment_model.dart';
import 'notification_service.dart';

/// AssessmentService for managing assessments across Firestore
/// (both the course doc assessments list and the subcollection:
/// users/{uid}/courses/{courseId}/assessments/{assessmentId}).
class AssessmentService {
  final FirebaseFirestore _firestore;

  AssessmentService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Subcollection reference: users/{uid}/courses/{courseId}/assessments
  CollectionReference<Map<String, dynamic>> _assessmentCol(String uid, String courseId) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('courses')
        .doc(courseId)
        .collection('assessments');
  }

  /// Course document reference: users/{uid}/courses/{courseId}
  DocumentReference<Map<String, dynamic>> _courseDoc(String uid, String courseId) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('courses')
        .doc(courseId);
  }

  /// Real-time stream of assessments for a specific course from subcollection
  Stream<List<Assessment>> getAssessmentsStream({
    String? uid,
    required String courseId,
  }) {
    final effectiveUid = uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    if (effectiveUid.isEmpty || courseId.isEmpty) return Stream.value([]);
    return _assessmentCol(effectiveUid, courseId).snapshots().map((snap) {
      return snap.docs
          .map((doc) => Assessment.fromMap(doc.data(), defaultCourseId: courseId))
          .toList();
    });
  }

  /// Create a new assessment and persist to both subcollection & course doc
  Future<void> createAssessment({
    required String uid,
    required Assessment assessment,
    String? courseCode,
  }) async {
    final map = assessment.toMap();
    map['userId'] = uid;

    // 1. Write to subcollection: users/{uid}/courses/{courseId}/assessments/{id}
    try {
      await _assessmentCol(uid, assessment.courseId)
          .doc(assessment.id)
          .set(map, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error writing assessment to subcollection: $e');
    }

    // 2. Persist/merge within course document 'assessments'
    try {
      final docRef = _courseDoc(uid, assessment.courseId);
      final snap = await docRef.get();
      if (snap.exists) {
        final cData = snap.data() ?? {};
        final rawAss = cData['assessments'];
        if (rawAss is Map) {
          final assMap = Map<String, dynamic>.from(rawAss);
          if (assessment.type == 'ct') {
            final cts = List<dynamic>.from(assMap['classTests'] is List ? assMap['classTests'] : []);
            final idx = cts.indexWhere((it) => it is Map && it['name'] == assessment.name);
            if (idx >= 0) {
              cts[idx] = map;
            } else {
              cts.add(map);
            }
            assMap['classTests'] = cts;
          }
          await docRef.set({
            'assessments': assMap,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (rawAss is List) {
          await docRef.update({
            'assessments': FieldValue.arrayUnion([map]),
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        } else {
          // assessments map does not exist yet
          if (assessment.type == 'ct') {
            await docRef.set({
              'assessments': {
                'classTests': [map],
              },
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        }
      }
    } catch (e) {
      debugPrint('Error writing assessment to course doc: $e');
    }

    // 3. Schedule 24h smart reminder
    if (assessment.date != null) {
      try {
        await NotificationService().scheduleAssessmentReminder(
          assessmentName: assessment.name,
          courseName: courseCode ?? 'Course',
          date: assessment.date ?? DateTime.now(),
          id: assessment.id,
        );
      } catch (e) {
        debugPrint('Error scheduling reminder: $e');
      }
    }
  }

  /// Update an existing assessment in both subcollection & course doc array
  Future<void> updateAssessment({
    required String uid,
    required Assessment assessment,
  }) async {
    final map = assessment.toMap();

    // 1. Update subcollection document
    try {
      await _assessmentCol(uid, assessment.courseId)
          .doc(assessment.id)
          .set(map, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating assessment in subcollection: $e');
    }

    // 2. Update within course document array or category map
    try {
      final docRef = _courseDoc(uid, assessment.courseId);
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data();
        final rawAss = data?['assessments'];

        if (rawAss is Map) {
          final assMap = Map<String, dynamic>.from(rawAss);
          bool found = false;
          const catKeys = [
            'classTests',
            'quizzesViva',
            'quizzes',
            'labReportsAssignments',
            'labReports',
            'continuousAssessment',
            'labFinalPractical',
            'assignments',
            'items',
          ];

          for (final key in catKeys) {
            if (assMap[key] is List) {
              final list = List<dynamic>.from(assMap[key]);
              for (int i = 0; i < list.length; i++) {
                if (list[i] is Map &&
                    (list[i]['id'] == assessment.id ||
                        (list[i]['name'] != null && list[i]['name'] == assessment.name))) {
                  list[i] = map;
                  found = true;
                  break;
                }
              }
              if (found) {
                assMap[key] = list;
                break;
              }
            }
          }

          if (!found) {
            final targetKey = assessment.type == 'quiz'
                ? 'quizzesViva'
                : (assessment.type == 'assignment' ? 'labReportsAssignments' : 'classTests');
            final list = List<dynamic>.from(assMap[targetKey] is List ? assMap[targetKey] : []);
            list.add(map);
            assMap[targetKey] = list;
          }

          await docRef.set({
            'assessments': assMap,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else if (rawAss is List) {
          final items = List<dynamic>.from(rawAss);
          bool found = false;
          for (int i = 0; i < items.length; i++) {
            if (items[i] is Map && items[i]['id'] == assessment.id) {
              items[i] = map;
              found = true;
              break;
            }
          }
          if (!found) {
            items.add(map);
          }

          await docRef.update({
            'assessments': items,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Error updating assessment in course doc array: $e');
    }
  }

  /// Updates only the status / attendance of an assessment in both subcollection and course doc array.
  /// If [status] is null or 'unmarked', resets to 'Pending' (unmarked/scheduled).
  Future<void> updateAssessmentStatus({
    required String uid,
    required String courseId,
    required String assessmentId,
    required String? status,
  }) async {
    final effectiveStatus = (status == null || status.isEmpty || status == 'unmarked') ? 'Pending' : status;

    // 1. Update subcollection doc
    try {
      final docUpdate = <String, dynamic>{
        'status': effectiveStatus,
        'attendanceStatus': status,
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (status == null || status.isEmpty || status == 'unmarked') {
        docUpdate['obtainedMarks'] = null;
      } else if (status.toLowerCase() == 'missed') {
        docUpdate['obtainedMarks'] = 0.0;
      }
      await _assessmentCol(uid, courseId).doc(assessmentId).set(docUpdate, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating assessment status in subcollection: $e');
    }

    // 2. Update within course doc array/map
    try {
      final docRef = _courseDoc(uid, courseId);
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data();
        final rawAss = data?['assessments'];

        if (rawAss is Map) {
          final assMap = Map<String, dynamic>.from(rawAss);
          bool found = false;
          const catKeys = [
            'classTests',
            'quizzesViva',
            'quizzes',
            'labReportsAssignments',
            'labReports',
            'continuousAssessment',
            'labFinalPractical',
            'assignments',
            'items',
          ];

          for (final key in catKeys) {
            if (assMap[key] is List) {
              final list = List<dynamic>.from(assMap[key]);
              for (int i = 0; i < list.length; i++) {
                if (list[i] is Map && list[i]['id'] == assessmentId) {
                  final updated = Map<String, dynamic>.from(list[i]);
                  updated['status'] = effectiveStatus;
                  updated['attendanceStatus'] = status;
                  if (status == null || status.isEmpty || status == 'unmarked') {
                    updated['obtainedMarks'] = null;
                  } else if (status.toLowerCase() == 'missed') {
                    updated['obtainedMarks'] = 0.0;
                  }
                  list[i] = updated;
                  found = true;
                  break;
                }
              }
              if (found) {
                assMap[key] = list;
                break;
              }
            }
          }

          if (found) {
            await docRef.set({
              'assessments': assMap,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } else if (rawAss is List) {
          final items = List<dynamic>.from(rawAss);
          bool found = false;
          for (int i = 0; i < items.length; i++) {
            if (items[i] is Map && items[i]['id'] == assessmentId) {
              final updated = Map<String, dynamic>.from(items[i]);
              updated['status'] = effectiveStatus;
              updated['attendanceStatus'] = status;
              if (status == null || status.isEmpty || status == 'unmarked') {
                updated['obtainedMarks'] = null;
              } else if (status.toLowerCase() == 'missed') {
                updated['obtainedMarks'] = 0.0;
              }
              items[i] = updated;
              found = true;
              break;
            }
          }

          if (found) {
            await docRef.update({
              'assessments': items,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating assessment status in course doc array: $e');
    }
  }

  /// Delete an assessment from both subcollection and course doc array/map
  Future<void> deleteAssessment({
    required String uid,
    required String courseId,
    required String assessmentId,
  }) async {
    // 1. Delete from subcollection
    try {
      await _assessmentCol(uid, courseId).doc(assessmentId).delete();
    } catch (e) {
      debugPrint('Error deleting assessment from subcollection: $e');
    }

    // 2. Remove from course document array/map
    try {
      final docRef = _courseDoc(uid, courseId);
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data();
        final rawAss = data?['assessments'];

        if (rawAss is Map) {
          final assMap = Map<String, dynamic>.from(rawAss);
          bool found = false;
          const catKeys = [
            'classTests',
            'quizzesViva',
            'quizzes',
            'labReportsAssignments',
            'labReports',
            'continuousAssessment',
            'labFinalPractical',
            'assignments',
            'items',
          ];

          for (final key in catKeys) {
            if (assMap[key] is List) {
              final list = List<dynamic>.from(assMap[key]);
              final originalLen = list.length;
              list.removeWhere((item) => item is Map && item['id'] == assessmentId);
              if (list.length != originalLen) {
                assMap[key] = list;
                found = true;
                break;
              }
            }
          }

          if (found) {
            await docRef.set({
              'assessments': assMap,
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } else if (rawAss is List) {
          final items = List<dynamic>.from(rawAss);
          items.removeWhere((item) => item is Map && item['id'] == assessmentId);

          await docRef.update({
            'assessments': items,
            'lastUpdated': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Error deleting assessment from course doc array: $e');
    }
  }

  /// Fetch assessments for a course, querying subcollection first and falling back to course doc array
  Future<List<Assessment>> getAssessments({
    required String uid,
    required String courseId,
  }) async {
    try {
      final subSnap = await _assessmentCol(uid, courseId).get();
      if (subSnap.docs.isNotEmpty) {
        return subSnap.docs
            .map((doc) => Assessment.fromMap(doc.data(), defaultCourseId: courseId))
            .toList();
      }
    } catch (e) {
      debugPrint('Subcollection fetch failed, falling back to course doc: $e');
    }

    try {
      final courseSnap = await _courseDoc(uid, courseId).get();
      if (courseSnap.exists) {
        final rawAss = courseSnap.data()?['assessments'];
        return Assessment.fromRawListOrMap(rawAss, defaultCourseId: courseId);
      }
    } catch (e) {
      debugPrint('Error fetching assessments from course doc: $e');
    }

    return [];
  }
}
