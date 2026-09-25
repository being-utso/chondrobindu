import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/profile_models.dart';
import '../models/routine_models.dart';

/// Service for archiving completed semester/term data and resetting active collections
class ArchiveService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Archives the current university term by packaging all active data and resetting active collections
  static Future<String> archiveCurrentTerm({
    required String termName,
    UserProfile? userProfile,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception('User is not signed in.');
    }

    final userDocRef = _firestore.collection('users').doc(uid);

    // 1. Fetch all active courses (with their nested assessments)
    final coursesSnapshot = await userDocRef.collection('courses').get();
    final List<Map<String, dynamic>> coursesData = coursesSnapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();

    // 2. Fetch all active class routines
    final routineSnapshot = await userDocRef.collection('routine').get();
    final List<Map<String, dynamic>> routineData = routineSnapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();

    // 3. Fetch all active attendance records
    final attendanceSnapshot = await userDocRef.collection('attendance_records').get();
    final List<Map<String, dynamic>> attendanceData = attendanceSnapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      return data;
    }).toList();

    // 4. Calculate Summary Statistics
    double totalCredits = 0.0;
    for (final c in coursesData) {
      final cr = (c['creditHours'] as num?)?.toDouble() ?? 0.0;
      totalCredits += cr;
    }

    final attendanceRecords = attendanceData
        .map((d) => AttendanceRecord.fromMap(d, defaultId: d['id'] as String?))
        .toList();
    final attendanceStats = AttendanceStats.fromRecords(attendanceRecords);

    // 5. Generate Archived Term document ID & package data
    final termId = 'term_${DateTime.now().millisecondsSinceEpoch}';
    final archivedTermDocRef = userDocRef.collection('archived_terms').doc(termId);

    final archivePackage = {
      'id': termId,
      'termName': termName.trim().isNotEmpty ? termName.trim() : 'Semester Archive',
      'universityName': userProfile?.universityName ?? '',
      'major': userProfile?.major ?? '',
      'level': userProfile?.level ?? '1',
      'term': userProfile?.term ?? '1',
      'totalCourses': coursesData.length,
      'totalCredits': totalCredits,
      'attendancePercentage': attendanceStats.percentage,
      'attendedClasses': attendanceStats.attended + attendanceStats.extra,
      'totalClasses': attendanceStats.validClassesCount,
      'courses': coursesData,
      'routine': routineData,
      'attendanceRecords': attendanceData,
      'archivedAt': FieldValue.serverTimestamp(),
    };

    // Save archive document
    await archivedTermDocRef.set(archivePackage);

    // Also store courses in subcollection for granular access if needed
    for (final course in coursesData) {
      final cId = course['id'] as String;
      await archivedTermDocRef.collection('courses').doc(cId).set(course);
    }

    // 6. Reset / Clear active collections for the new semester
    final batch = _firestore.batch();

    for (final doc in coursesSnapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in routineSnapshot.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in attendanceSnapshot.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();

    debugPrint('Archived term "$termName" ($termId) with ${coursesData.length} courses and reset active dashboard.');
    return termId;
  }

  /// Live stream of all archived terms for the current user
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamArchivedTerms() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Stream.empty();
    }

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('archived_terms')
        .orderBy('archivedAt', descending: true)
        .snapshots();
  }

  /// Fetches a specific archived term document
  static Future<Map<String, dynamic>?> fetchArchivedTerm(String termId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('archived_terms')
        .doc(termId)
        .get();

    return doc.data();
  }

  /// Deletes a specific archived term document
  static Future<void> deleteArchivedTerm(String termId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('archived_terms')
        .doc(termId)
        .delete();
  }
}
