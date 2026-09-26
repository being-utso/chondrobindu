import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';

import '../models/syllabus_node.dart' hide SyllabusTopic;

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

  /// Parses Android-canonical `syllabusData` list from Firestore course doc into List<SyllabusTopic>
  List<SyllabusTopic> _topicsFromSyllabusData(dynamic rawData) {
    if (rawData == null) return [];
    List<dynamic> rawList = [];
    if (rawData is List) {
      rawList = rawData;
    } else if (rawData is Map) {
      if (rawData['nodes'] is List) {
        rawList = rawData['nodes'] as List;
      } else if (rawData['chapters'] is List) {
        rawList = rawData['chapters'] as List;
      }
    }
    if (rawList.isEmpty) return [];

    final nodes = rawList
        .whereType<Map>()
        .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
        .toList();

    final List<SyllabusTopic> topics = [];
    for (int chIdx = 0; chIdx < nodes.length; chIdx++) {
      final ch = nodes[chIdx];
      if (ch.children.isEmpty) {
        topics.add(SyllabusTopic(
          id: ch.id,
          chapterTitle: ch.title,
          topicIndex: '${chIdx + 1}.1',
          title: ch.title,
          chapterOrder: chIdx + 1,
          isCompleted: ch.isCompleted,
        ));
      } else {
        for (int tIdx = 0; tIdx < ch.children.length; tIdx++) {
          final t = ch.children[tIdx];
          topics.add(SyllabusTopic(
            id: t.id,
            chapterTitle: ch.title,
            topicIndex: '${chIdx + 1}.${tIdx + 1}',
            title: t.title,
            chapterOrder: chIdx + 1,
            isCompleted: t.isCompleted,
          ));
        }
      }
    }
    return topics;
  }

  Stream<List<SyllabusTopic>> watchSyllabus(String uid, String courseId) {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty) return Stream.value([]);

    return _coursesRef(uid)!.doc(courseId).snapshots().asyncExpand((doc) {
      final data = doc.data();
      final rawSyllabus = data?['syllabusData'] ?? data?['syllabus'];
      final parsedTopics = _topicsFromSyllabusData(rawSyllabus);

      if (parsedTopics.isNotEmpty) {
        return Stream.value(parsedTopics);
      }

      // Fallback to legacy topics subcollection if syllabusData on course doc is empty
      return _topicsRef(uid, courseId)!
          .orderBy('chapterOrder')
          .snapshots()
          .map((snapshot) {
        final topics = snapshot.docs.map((d) => SyllabusTopic.fromFirestore(d)).toList();
        topics.sort((a, b) {
          final cOrder = a.chapterOrder.compareTo(b.chapterOrder);
          if (cOrder != 0) return cOrder;
          return a.topicIndex.compareTo(b.topicIndex);
        });
        return topics;
      });
    });
  }

  Future<void> toggleTopicStatus(
    String uid,
    String courseId,
    String topicId,
    bool isCompleted,
  ) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty || topicId.isEmpty) return;

    final courseDocRef = _coursesRef(uid)!.doc(courseId);
    final courseSnap = await courseDocRef.get();
    final data = courseSnap.data();

    final rawSyllabus = data?['syllabusData'] ?? data?['syllabus'];
    if (rawSyllabus != null) {
      List<dynamic> rawList = [];
      if (rawSyllabus is List) rawList = List.from(rawSyllabus);

      final nodes = rawList
          .whereType<Map>()
          .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
          .toList();

      bool found = false;
      bool toggleNode(SyllabusNode node) {
        if (node.id == topicId) {
          node.isCompleted = isCompleted;
          node.setCompletedCascading(isCompleted);
          return true;
        }
        for (final child in node.children) {
          if (toggleNode(child)) {
            node.updateHierarchicalCompletion();
            return true;
          }
        }
        return false;
      }

      for (final root in nodes) {
        if (toggleNode(root)) {
          found = true;
          break;
        }
      }

      if (found) {
        final totalLeaves = nodes.fold<int>(0, (acc, n) => acc + n.totalLeafCount);
        final completedLeaves = nodes.fold<int>(0, (acc, n) => acc + n.completedLeafCount);

        await courseDocRef.update({
          'syllabusData': nodes.map((n) => n.toMap()).toList(),
          'totalTopicsCount': totalLeaves,
          'completedTopicsCount': completedLeaves,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        return;
      }
    }

    // Fallback: update topics subcollection if legacy document exists
    final topicDoc = _topicsRef(uid, courseId)!.doc(topicId);
    await _firestore!.runTransaction((transaction) async {
      transaction.update(topicDoc, {
        'isCompleted': isCompleted,
        'completedAt': isCompleted ? FieldValue.serverTimestamp() : null,
      });

      final allTopicsSnap = await _topicsRef(uid, courseId)!.get();
      int completed = 0;
      int total = allTopicsSnap.docs.length;

      for (final doc in allTopicsSnap.docs) {
        if (doc.id == topicId) {
          if (isCompleted) completed++;
        } else {
          final d = doc.data();
          if (d['isCompleted'] == true) completed++;
        }
      }

      transaction.update(courseDocRef, {
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

  Future<void> saveSyllabusNodes(String uid, String courseId, List<SyllabusNode> nodes) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty) return;
    final totalLeaves = nodes.fold<int>(0, (acc, n) => acc + n.totalLeafCount);
    final completedLeaves = nodes.fold<int>(0, (acc, n) => acc + n.completedLeafCount);
    await _coursesRef(uid)!.doc(courseId).update({
      'syllabusData': nodes.map((n) => n.toMap()).toList(),
      'totalTopicsCount': totalLeaves,
      'completedTopicsCount': completedLeaves,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addSyllabusChapter(String uid, String courseId, String chapterTitle) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty || chapterTitle.isEmpty) return;
    final courseDocRef = _coursesRef(uid)!.doc(courseId);
    final snap = await courseDocRef.get();
    final data = snap.data();
    final rawSyllabus = data?['syllabusData'] ?? data?['syllabus'];
    List<dynamic> rawList = [];
    if (rawSyllabus is List) rawList = List.from(rawSyllabus);

    final nodes = rawList
        .whereType<Map>()
        .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
        .toList();

    nodes.add(SyllabusNode(
      title: chapterTitle,
      isLeaf: false,
      children: [],
    ));

    await saveSyllabusNodes(uid, courseId, nodes);
  }

  Future<void> addSyllabusTopicToChapter(
    String uid,
    String courseId,
    String chapterTitle,
    String topicTitle,
  ) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty || topicTitle.isEmpty) return;
    final courseDocRef = _coursesRef(uid)!.doc(courseId);
    final snap = await courseDocRef.get();
    final data = snap.data();
    final rawSyllabus = data?['syllabusData'] ?? data?['syllabus'];
    List<dynamic> rawList = [];
    if (rawSyllabus is List) rawList = List.from(rawSyllabus);

    final nodes = rawList
        .whereType<Map>()
        .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
        .toList();

    SyllabusNode? targetChapter;
    for (final node in nodes) {
      if (node.title.trim().toLowerCase() == chapterTitle.trim().toLowerCase()) {
        targetChapter = node;
        break;
      }
    }

    final newTopicNode = SyllabusNode(
      title: topicTitle,
      isLeaf: true,
      children: [],
    );

    if (targetChapter != null) {
      targetChapter.children.add(newTopicNode);
    } else {
      nodes.add(SyllabusNode(
        title: chapterTitle.isNotEmpty ? chapterTitle : 'General',
        isLeaf: false,
        children: [newTopicNode],
      ));
    }

    await saveSyllabusNodes(uid, courseId, nodes);
  }

  Future<void> archiveCourse(String uid, String courseId, bool isArchived) async {
    if (_firestore == null || uid.isEmpty || courseId.isEmpty) return;
    await _coursesRef(uid)!.doc(courseId).update({'isArchived': isArchived});
  }
}
