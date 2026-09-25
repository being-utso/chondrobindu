import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/syllabus_models.dart';
import '../services/course_service.dart';
import 'syllabus_provider.dart';
import 'user_profile_provider.dart';

const List<String> kDefaultTimerSubjects = [
  'Physics 1st Paper',
  'Physics 2nd Paper',
  'Chemistry 1st Paper',
  'Chemistry 2nd Paper',
  'Higher Mathematics 1st Paper',
  'Higher Mathematics 2nd Paper',
  'Biology 1st Paper',
  'Biology 2nd Paper',
  'English',
  'Bangla',
  'ICT',
  'General Study',
  'Model Test Practice',
];

const List<String> kDefaultUniversityTimerSubjects = [
  'General Study',
  'Assignment',
  'Lab Report',
  'Term Paper',
  'Self Study',
];

/// Provider for managing timer-specific subjects, dynamically synced with Syllabus / University Courses
final timerSubjectsProvider = StateNotifierProvider<TimerSubjectsNotifier, List<String>>((ref) {
  final userProfile = ref.watch(userProfileProvider);
  final syllabusSubjects = ref.watch(syllabusProvider).map((s) => s.title).toList();
  
  final notifier = TimerSubjectsNotifier(
    ref: ref,
    isUniversityStudent: userProfile.isUniversityStudent,
    initialSyllabusSubjects: syllabusSubjects,
  );

  ref.listen<List<Subject>>(syllabusProvider, (_, next) {
    notifier.updateSyllabusSubjects(next.map((s) => s.title).toList());
  });

  ref.listen<UserProfile>(userProfileProvider, (_, next) {
    notifier.updateUniversityMode(next.isUniversityStudent);
  });

  return notifier;
});

class TimerSubjectsNotifier extends StateNotifier<List<String>> {
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final Ref? _ref;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _coursesSubscription;

  bool _isUniversityStudent;
  List<String> _syllabusSubjects = [];
  List<String> _universityCourses = [];
  List<String> _customSubjects = [];

  FirebaseFirestore? get _firestore {
    if (_customFirestore != null) return _customFirestore;
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseAuth? get _auth {
    if (_customAuth != null) return _customAuth;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  TimerSubjectsNotifier({
    Ref? ref,
    bool isUniversityStudent = false,
    List<String> initialSyllabusSubjects = const [],
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _ref = ref,
        _isUniversityStudent = isUniversityStudent,
        _customFirestore = firestore,
        _customAuth = auth,
        _syllabusSubjects = initialSyllabusSubjects,
        super([]) {
    _initListeners();
    _recomputeState();
  }

  void _recomputeState() {
    final merged = <String>{};

    if (_isUniversityStudent) {
      // University Mode: populate with enrolled course codes and university custom subjects
      final sortedUniCourses = List<String>.from(_universityCourses);
      sortedUniCourses.sort(compareCourseCodes);
      for (final c in sortedUniCourses) {
        if (c.trim().isNotEmpty) merged.add(c.trim());
      }
      for (final cs in _customSubjects) {
        if (cs.trim().isNotEmpty) merged.add(cs.trim());
      }
      if (merged.isEmpty) {
        merged.addAll(kDefaultUniversityTimerSubjects);
      }
    } else {
      // Admission Mode: populate with syllabus subjects and admission custom subjects
      for (final s in _syllabusSubjects) {
        if (s.trim().isNotEmpty) merged.add(s.trim());
      }
      for (final cs in _customSubjects) {
        if (cs.trim().isNotEmpty) merged.add(cs.trim());
      }
      if (merged.isEmpty) {
        merged.addAll(kDefaultTimerSubjects);
      }
    }

    state = merged.toList();
  }

  void updateUniversityMode(bool isUni) {
    if (_isUniversityStudent != isUni) {
      _isUniversityStudent = isUni;
      _recomputeState();
    }
  }

  void updateSyllabusSubjects(List<String> subjects) {
    _syllabusSubjects = subjects;
    if (!_isUniversityStudent) {
      _recomputeState();
    }
  }

  void _initListeners() {
    final firestore = _firestore;
    final auth = _auth;
    if (firestore == null || auth == null) {
      _recomputeState();
      return;
    }

    final uid = auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      _recomputeState();
      return;
    }

    // 1. Listen to user profile document for custom timer subjects
    _userSubscription = firestore.collection('users').doc(uid).snapshots().listen((doc) async {
      if (!doc.exists) return;
      final data = doc.data();

      if (data != null) {
        final rawCustom = data['custom_timer_subjects'] ?? data['timer_subjects'];
        if (rawCustom is List) {
          _customSubjects = rawCustom
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
          _recomputeState();
          return;
        }
      }

      _recomputeState();
    });

    // 2. Listen to active university courses subcollection
    _coursesSubscription = firestore
        .collection('users')
        .doc(uid)
        .collection('courses')
        .snapshots()
        .listen((snapshot) {
      final sortedDocs = List.from(snapshot.docs);
      sortedDocs.sort((a, b) {
        final codeA = (a.data() as Map<String, dynamic>)['courseCode'] as String? ?? a.id;
        final codeB = (b.data() as Map<String, dynamic>)['courseCode'] as String? ?? b.id;
        return compareCourseCodes(codeA, codeB);
      });
      final courses = sortedDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final code = data['courseCode'] as String? ?? '';
        final name = data['courseName'] as String? ?? '';
        if (code.isNotEmpty && name.isNotEmpty) {
          return '$code: $name';
        }
        return code.isNotEmpty ? code : (name.isNotEmpty ? name : 'Course');
      }).where((c) => c.isNotEmpty).toList();

      _universityCourses = courses;
      if (_isUniversityStudent) {
        _recomputeState();
      }
    });
  }

  /// Add a custom subject explicitly for the Study Timer
  Future<void> addCustomSubject(String subject) async {
    final trimmed = subject.trim();
    if (trimmed.isEmpty || _customSubjects.contains(trimmed)) return;

    _customSubjects.add(trimmed);
    _recomputeState();

    final firestore = _firestore;
    final auth = _auth;
    if (firestore != null && auth != null) {
      final uid = auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await firestore.collection('users').doc(uid).set({
            'custom_timer_subjects': FieldValue.arrayUnion([trimmed]),
            'timer_subjects': FieldValue.arrayUnion([trimmed]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Error adding custom timer subject to Firestore: $e');
        }
      }
    }
  }

  /// Delete a subject explicitly from the Study Timer
  Future<void> deleteSubject(String subject) async {
    final trimmed = subject.trim();
    if (trimmed.isEmpty) return;

    _customSubjects.remove(trimmed);
    _recomputeState();

    final firestore = _firestore;
    final auth = _auth;
    if (firestore != null && auth != null) {
      final uid = auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await firestore.collection('users').doc(uid).set({
            'custom_timer_subjects': FieldValue.arrayRemove([trimmed]),
            'timer_subjects': FieldValue.arrayRemove([trimmed]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Error removing timer subject from Firestore: $e');
        }
      }
    }
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _coursesSubscription?.cancel();
    super.dispose();
  }
}
