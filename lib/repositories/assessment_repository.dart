import 'dart:async';
import 'package:flutter/foundation.dart';
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
    List<Assessment> groupAssessments = [];
    final Map<String, List<Assessment>> courseSubcollectionMap = {};
    final Map<String, StreamSubscription> courseSubcollectionSubs = {};

    void emitMerged() {
      final Map<String, Assessment> map = {};
      for (final a in courseDocAssessments) {
        if (a.id.isNotEmpty) {
          map[a.id] = a;
        } else if (a.name.isNotEmpty) {
          map['${a.courseId}_${a.name}'] = a;
        }
      }
      for (final aList in courseSubcollectionMap.values) {
        for (final a in aList) {
          if (a.id.isNotEmpty) {
            map[a.id] = a;
          } else if (a.name.isNotEmpty) {
            map['${a.courseId}_${a.name}'] = a;
          }
        }
      }
      for (final a in groupAssessments) {
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
        final dA = a.dueDate ?? a.date;
        final dB = b.dueDate ?? b.date;
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
    StreamSubscription? subGroup;

    controller = StreamController<List<Assessment>>.broadcast(
      onListen: () {
        // 1. Direct user assessments: users/$uid/assessments
        sub1 = _assessmentsRef(uid)?.snapshots().listen(
          (snap) {
            directAssessments = snap.docs.map((doc) => Assessment.fromFirestore(doc)).toList();
            emitMerged();
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        // 2. Course documents (embedded assessments and per-course subcollections)
        sub2 = _coursesRef(uid)?.snapshots().listen(
          (snap) {
            final List<Assessment> fromCourses = [];
            final currentCourseIds = <String>{};

            for (final doc in snap.docs) {
              currentCourseIds.add(doc.id);
              fromCourses.addAll(Assessment.fromCourseData(doc.data(), courseId: doc.id));

              // Listen to per-course assessments subcollection: users/$uid/courses/$courseId/assessments
              if (!courseSubcollectionSubs.containsKey(doc.id)) {
                courseSubcollectionSubs[doc.id] = doc.reference.collection('assessments').snapshots().listen(
                  (subSnap) {
                    final fromSub = subSnap.docs.map((d) {
                      final ass = Assessment.fromMap(d.data(), defaultId: d.id, defaultCourseId: doc.id);
                      if (ass.courseId.isEmpty) ass.courseId = doc.id;
                      return ass;
                    }).toList();
                    courseSubcollectionMap[doc.id] = fromSub;
                    emitMerged();
                  },
                  onError: (_) {},
                );
              }
            }

            // Cleanup removed courses
            courseSubcollectionSubs.removeWhere((cId, sub) {
              if (!currentCourseIds.contains(cId)) {
                sub.cancel();
                courseSubcollectionMap.remove(cId);
                return true;
              }
              return false;
            });

            courseDocAssessments = fromCourses;
            emitMerged();
          },
          onError: (e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        // 3. Collection group 'assessments' (matching Android exams_screen.dart logic)
        subGroup = _firestore?.collectionGroup('assessments').snapshots().listen(
          (groupSnap) {
            final List<Assessment> fromGroup = [];
            for (final doc in groupSnap.docs) {
              final data = doc.data();
              final path = doc.reference.path;
              final bool isUserDoc = (data['userId'] == uid) ||
                  path.startsWith('users/$uid/') ||
                  path.contains('users/$uid/') ||
                  path.contains('/users/$uid/');

              if (isUserDoc) {
                String derivedCourseId = '';
                final pathSegments = path.split('/');
                final courseIdx = pathSegments.indexOf('courses');
                if (courseIdx != -1 && courseIdx + 1 < pathSegments.length) {
                  derivedCourseId = pathSegments[courseIdx + 1];
                }
                final ass = Assessment.fromMap(
                  data,
                  defaultId: doc.id,
                  defaultCourseId: derivedCourseId.isNotEmpty ? derivedCourseId : null,
                );
                if (ass.courseId.isEmpty && derivedCourseId.isNotEmpty) {
                  ass.courseId = derivedCourseId;
                }
                fromGroup.add(ass);
              }
            }
            groupAssessments = fromGroup;
            emitMerged();
          },
          onError: (_) {
            // Silently ignore if collectionGroup lacks permissions or index
          },
        );
      },
      onCancel: () {
        sub1?.cancel();
        sub2?.cancel();
        subGroup?.cancel();
        for (final sub in courseSubcollectionSubs.values) {
          sub.cancel();
        }
        courseSubcollectionSubs.clear();
      },
    );

    return controller.stream;
  }

  Future<void> createAssessment(String uid, Assessment assessment) async {
    if (_firestore == null || uid.isEmpty) return;
    await _assessmentsRef(uid)!.doc(assessment.id).set(assessment.toMap(), SetOptions(merge: true));
    if (assessment.courseId.isNotEmpty) {
      try {
        await _coursesRef(uid)!
            .doc(assessment.courseId)
            .collection('assessments')
            .doc(assessment.id)
            .set(assessment.toMap(), SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> updateAssessment(String uid, Assessment assessment) async {
    await createAssessment(uid, assessment);
  }

  Future<void> toggleAssessmentCompleted(
    String uid,
    String assessmentId,
    bool isCompleted, [
    double? obtainedMarks,
    String? courseId,
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
    await _assessmentsRef(uid)!.doc(assessmentId).set(updates, SetOptions(merge: true));
    if (courseId != null && courseId.isNotEmpty) {
      try {
        await _coursesRef(uid)!
            .doc(courseId)
            .collection('assessments')
            .doc(assessmentId)
            .set(updates, SetOptions(merge: true));
      } catch (_) {}
    }
  }

  Future<void> deleteAssessment(
    String uid,
    String assessmentId, [
    String? courseId,
    String? assessmentName,
    int? itemIndex,
  ]) async {
    if (_firestore == null || uid.isEmpty) return;

    if (assessmentId.isNotEmpty) {
      try {
        await _assessmentsRef(uid)!.doc(assessmentId).delete();
      } catch (_) {}
    }

    if (courseId != null && courseId.isNotEmpty) {
      if (assessmentId.isNotEmpty) {
        try {
          await _coursesRef(uid)!
              .doc(courseId)
              .collection('assessments')
              .doc(assessmentId)
              .delete();
        } catch (_) {}
      }

      // Also clean up any embedded assessment in course document (both map and array structures)
      try {
        final docRef = _coursesRef(uid)!.doc(courseId);
        final snap = await docRef.get();
        if (snap.exists) {
          final data = snap.data();
          if (data != null) {
            bool modified = false;
            final updates = <String, dynamic>{};

            final rawAss = data['assessments'];
            if (rawAss is Map) {
              final assMap = Map<String, dynamic>.from(rawAss);
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
                  bool removed = false;
                  for (int i = 0; i < list.length; i++) {
                    final it = list[i];
                    if (it is Map) {
                      final matchId = assessmentId.isNotEmpty && it['id'] == assessmentId;
                      final matchName = assessmentName != null &&
                          assessmentName.isNotEmpty &&
                          (it['name'] == assessmentName || it['title'] == assessmentName);
                      if (matchId || matchName) {
                        list.removeAt(i);
                        removed = true;
                        break;
                      }
                    }
                  }
                  if (removed) {
                    assMap[key] = list;
                    modified = true;
                    break;
                  }
                }
              }
              if (modified) {
                updates['assessments'] = assMap;
              }
            } else if (rawAss is List) {
              final list = List<dynamic>.from(rawAss);
              for (int i = 0; i < list.length; i++) {
                final it = list[i];
                if (it is Map) {
                  final matchId = assessmentId.isNotEmpty && it['id'] == assessmentId;
                  final matchName = assessmentName != null &&
                      assessmentName.isNotEmpty &&
                      (it['name'] == assessmentName || it['title'] == assessmentName);
                  if (matchId || matchName) {
                    list.removeAt(i);
                    updates['assessments'] = list;
                    modified = true;
                    break;
                  }
                }
              }
            }

            const topLevelKeys = ['classTests', 'quizzes', 'assignments'];
            for (final k in topLevelKeys) {
              if (data[k] is List) {
                final list = List<dynamic>.from(data[k]);
                for (int i = 0; i < list.length; i++) {
                  final it = list[i];
                  if (it is Map) {
                    final matchId = assessmentId.isNotEmpty && it['id'] == assessmentId;
                    final matchName = assessmentName != null &&
                        assessmentName.isNotEmpty &&
                        (it['name'] == assessmentName || it['title'] == assessmentName);
                    if (matchId || matchName) {
                      list.removeAt(i);
                      updates[k] = list;
                      modified = true;
                      break;
                    }
                  }
                }
              }
            }

            if (modified) {
              updates['lastUpdated'] = FieldValue.serverTimestamp();
              await docRef.set(updates, SetOptions(merge: true));
            }
          }
        }
      } catch (e) {
        debugPrint('Error removing embedded assessment from course doc: $e');
      }
    }
  }
}
