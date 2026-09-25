import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/profile_models.dart';
import '../services/home_widget_service.dart';

export '../models/profile_models.dart';

class UserProfileNotifier extends StateNotifier<UserProfile> {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final FirebaseStorage? _storage;

  UserProfileNotifier({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? (Firebase.apps.isNotEmpty ? FirebaseFirestore.instance : null),
        _auth = auth ?? (Firebase.apps.isNotEmpty ? FirebaseAuth.instance : null),
        _storage = storage ?? (Firebase.apps.isNotEmpty ? FirebaseStorage.instance : null),
        super(UserProfile.defaultProfile) {
    if (_auth != null) {
      _initAuthListener();
    }
  }

  void _initAuthListener() {
    _auth?.authStateChanges().listen((User? user) {
      if (user != null) {
        fetchProfile(user.uid);
      } else {
        state = UserProfile.defaultProfile;
      }
    });
  }

  Future<void> fetchProfile(String uid) async {
    if (_firestore == null) return;
    try {
      final doc = await _firestore!.collection('users').doc(uid).get().timeout(const Duration(seconds: 10));
      final currentUser = _auth?.currentUser;

      final data = doc.data();

      if (doc.exists && data != null) {
        var profile = UserProfile.fromMap(data);

        if (currentUser != null) {
          bool needsUpdate = false;
          String updatedEmail = profile.email;
          String? updatedPhotoUrl = profile.profileImageUrl;

          if (profile.email.isEmpty && (currentUser.email?.isNotEmpty ?? false)) {
            updatedEmail = currentUser.email!;
            needsUpdate = true;
          }
          if ((profile.profileImageUrl == null || profile.profileImageUrl!.isEmpty) &&
              (currentUser.photoURL?.isNotEmpty ?? false)) {
            updatedPhotoUrl = currentUser.photoURL;
            needsUpdate = true;
          }

          if (needsUpdate && _firestore != null) {
            profile = profile.copyWith(email: updatedEmail, profileImageUrl: updatedPhotoUrl);
            await _firestore!.collection('users').doc(uid).set({
              'email': updatedEmail,
              'profileImageUrl': updatedPhotoUrl,
            }, SetOptions(merge: true));
          }
        }

        state = profile.copyWith(isLoaded: true);
        await HomeWidgetService.updateHomeWidget(
          targetEventName: profile.targetEventName,
          targetEventDate: profile.targetEventDate,
        );
      } else {
        final initial = currentUser != null
            ? UserProfile.fromFirebaseUser(currentUser)
            : UserProfile.defaultProfile.copyWith(isLoaded: true);
        await saveProfile(initial, uid: uid);
      }
    } on TimeoutException catch (e) {
      debugPrint('Timeout fetching user profile: $e');
      state = state.copyWith(isLoaded: true);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      state = state.copyWith(isLoaded: true);
    }
  }

  /// Master method for handling all pin combinations safely
  Future<void> updatePinnedExams({
    String? examTabId,
    bool clearExamTab = false,
    String? homeTabId,
    bool clearHomeTab = false,
  }) async {
    state = state.copyWith(
      pinnedExamId: examTabId,
      clearPinnedExamId: clearExamTab,
      pinnedHomeExamId: homeTabId,
      clearPinnedHomeExamId: clearHomeTab,
    );

    final uid = _auth?.currentUser?.uid;
    if (uid == null || uid.isEmpty || _firestore == null) return;

    try {
      final Map<String, dynamic> updates = {'updatedAt': FieldValue.serverTimestamp()};
      
      if (clearExamTab) {
        updates['pinned_exam_id'] = null;
      } else if (examTabId != null) {
        updates['pinned_exam_id'] = examTabId;
      }

      if (clearHomeTab) {
        updates['pinned_home_exam_id'] = null;
      } else if (homeTabId != null) {
        updates['pinned_home_exam_id'] = homeTabId;
      }

      await _firestore!.collection('users').doc(uid).set(updates, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating pinned exams in Firestore: $e');
    }
  }

  Future<void> updateScratchpad(String text) async {
    state = state.copyWith(scratchpadText: text);
    final uid = _auth?.currentUser?.uid;
    if (uid == null || uid.isEmpty || _firestore == null) return;

    try {
      await _firestore!.collection('users').doc(uid).set({
        'scratchpad_text': text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating scratchpad_text: $e');
      rethrow;
    }
  }

  Future<String> uploadProfilePicture(Uint8List bytes, String fileExtension) async {
    final uid = _auth?.currentUser?.uid;
    if (uid == null || _storage == null) throw Exception('User not logged in');

    if (state.profileImageUrl != null && state.profileImageUrl!.isNotEmpty) {
      try {
        final existingRef = _storage!.refFromURL(state.profileImageUrl!);
        await existingRef.delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') debugPrint('Ignored expected error: ${e.code}');
      } catch (e) {
        debugPrint('Ignored error deleting old profile image: $e');
      }
    }

    try {
      final ref = _storage!.ref().child('users/$uid/profile_image.$fileExtension');
      final uploadTask = await ref.putData(bytes, SettableMetadata(contentType: 'image/$fileExtension'));
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      final updated = state.copyWith(profileImageUrl: downloadUrl);
      await saveProfile(updated, uid: uid);
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading profile picture: $e');
      rethrow;
    }
  }

  Future<String> uploadProfileImageBytes(Uint8List bytes, String fileExtension) {
    return uploadProfilePicture(bytes, fileExtension);
  }

  Future<void> addFocusMinutes(int additionalMinutes) async {
    if (additionalMinutes <= 0) return;
    final newTodaysFocus = state.todaysFocusMinutes + additionalMinutes;
    final newTotalFocus = state.totalFocusMinutes + additionalMinutes;
    int newStreak = state.streakDays;

    if (newTodaysFocus >= state.targetFocusMinutes && state.todaysFocusMinutes < state.targetFocusMinutes) {
      newStreak += 1;
    }

    final updated = state.copyWith(
      todaysFocusMinutes: newTodaysFocus,
      totalFocusMinutes: newTotalFocus,
      streakDays: newStreak,
    );

    await saveProfile(updated);
  }

  Future<void> saveProfile(UserProfile updatedProfile, {String? uid}) async {
    state = updatedProfile;
    final targetUid = uid ?? _auth?.currentUser?.uid;

    if (targetUid != null && targetUid.isNotEmpty && _firestore != null) {
      try {
        await _firestore!.collection('users').doc(targetUid).set(updatedProfile.toMap(), SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error saving user profile: $e');
      }
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? nickname,
    String? username,
    String? email,
    String? phone,
    String? college,
    String? hscBatch,
    String? hscGroup,
    String? district,
    String? primaryTarget,
    String? secondaryTarget,
    bool? isOnboarded,
    String? profileImageUrl,
    int? todaysFocusMinutes,
    int? totalFocusMinutes,
    int? streakDays,
    int? targetFocusMinutes,
    String? scratchpadText,
    bool? isUniversityStudent,
    String? universityName,
    String? major,
    String? level,
    String? term,
    String? uid,
  }) async {
    final updated = state.copyWith(
      fullName: fullName,
      nickname: nickname,
      username: username,
      email: email,
      phone: phone,
      college: college,
      hscBatch: hscBatch,
      hscGroup: hscGroup,
      district: district,
      primaryTarget: primaryTarget,
      secondaryTarget: secondaryTarget,
      isOnboarded: isOnboarded,
      profileImageUrl: profileImageUrl,
      todaysFocusMinutes: todaysFocusMinutes,
      totalFocusMinutes: totalFocusMinutes,
      streakDays: streakDays,
      targetFocusMinutes: targetFocusMinutes,
      scratchpadText: scratchpadText,
      isUniversityStudent: isUniversityStudent,
      universityName: universityName,
      major: major,
      level: level,
      term: term,
    );

    await saveProfile(updated, uid: uid);
  }

  Future<void> updateTargetEvent({required String eventName, required DateTime eventDate}) async {
    final uid = _auth?.currentUser?.uid;
    if (uid == null || _firestore == null) return;

    state = state.copyWith(targetEventName: eventName, targetEventDate: eventDate);

    try {
      await _firestore!.collection('users').doc(uid).set({
        'target_event_name': eventName,
        'target_event_date': Timestamp.fromDate(eventDate),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await HomeWidgetService.updateHomeWidget(targetEventName: eventName, targetEventDate: eventDate);
    } catch (e) {
      debugPrint('Error updating target event: $e');
    }
  }

  Future<void> addCustomTimerSubject(String subject) async {
    final trimmed = subject.trim();
    if (trimmed.isEmpty || state.customTimerSubjects.contains(trimmed)) return;

    final updatedSubjects = [...state.customTimerSubjects, trimmed];
    state = state.copyWith(customTimerSubjects: updatedSubjects);

    final uid = _auth?.currentUser?.uid;
    if (uid != null && _firestore != null) {
      try {
        await _firestore!.collection('users').doc(uid).set({
          'custom_timer_subjects': FieldValue.arrayUnion([trimmed]),
          'timer_subjects': FieldValue.arrayUnion([trimmed]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error adding custom timer subject: $e');
      }
    }
  }

  void setUserProfile(UserProfile profile) => state = profile;

  void resetProfile() => state = UserProfile.defaultProfile;
}

final userProfileProvider = StateNotifierProvider<UserProfileNotifier, UserProfile>((ref) {
  return UserProfileNotifier();
});