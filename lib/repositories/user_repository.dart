import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/user_profile.dart';

class UserRepository {
  final FirebaseFirestore? _firestore;

  UserRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null);

  Stream<UserProfile> watchUserProfile(String uid) {
    if (_firestore == null || uid.isEmpty) {
      return Stream.value(UserProfile.defaultProfile);
    }
    return _firestore!.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return UserProfile.defaultProfile.copyWith(uid: uid);
      }
      return UserProfile.fromFirestore(doc);
    });
  }

  Future<void> updateUserContext(String uid, {
    String? level,
    String? term,
    String? collegeClass,
    String? academicGroup,
    double? targetGpa,
    String? department,
    String? batch,
    InstitutionType? institutionType,
    int? streakDays,
    DateTime? lastStudiedAt,
  }) async {
    if (uid.isEmpty) return;
    final Map<String, dynamic> updates = {};
    if (level != null) updates['level'] = level;
    if (term != null) updates['term'] = term;
    if (collegeClass != null) updates['collegeClass'] = collegeClass;
    if (academicGroup != null) {
      updates['academicGroup'] = academicGroup;
      updates['hscGroup'] = academicGroup;
    }
    if (targetGpa != null) updates['targetGpa'] = targetGpa;
    if (department != null) {
      updates['department'] = department;
      updates['major'] = department;
    }
    if (batch != null) {
      updates['batch'] = batch;
      updates['hscBatch'] = batch;
    }
    if (institutionType != null) {
      updates['institutionType'] = institutionType.name;
      updates['isUniversityStudent'] = institutionType == InstitutionType.university;
    }
    if (streakDays != null) updates['streakDays'] = streakDays;
    if (lastStudiedAt != null) updates['lastStudiedAt'] = Timestamp.fromDate(lastStudiedAt);

    if (updates.isNotEmpty && _firestore != null) {
      await _firestore!.collection('users').doc(uid).set(updates, SetOptions(merge: true));
    }
  }

  Future<void> setInstitutionType(String uid, InstitutionType type) async {
    await updateUserContext(
      uid,
      institutionType: type,
      targetGpa: type == InstitutionType.college ? 5.00 : 3.75,
    );
  }
}
