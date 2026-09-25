import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'tour_service.dart';

/// Unified Authentication Service wrapping [FirebaseAuth] and [GoogleSignIn].
class AuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  AuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  /// Stream of authentication state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Currently logged in [User], or null if signed out.
  User? get currentUser => _auth.currentUser;

  /// Current user UID, or null.
  String? get currentUid => _auth.currentUser?.uid;

  /// Whether a user is currently logged in.
  bool get isAuthenticated => _auth.currentUser != null;

  /// 1. Sign in with Email and Password.
  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Alias for signInWithEmail
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await signInWithEmail(email, password);
  }

  /// 2. Sign up with Email and Password + automatically trigger verification email.
  Future<UserCredential> signUpWithEmail(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // Automatically send email verification link
    final user = credential.user;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }

    return credential;
  }

  /// Alias for signUpWithEmail
  Future<UserCredential> signUpWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    return await signUpWithEmail(email, password);
  }

  /// Send verification email to currently signed in user.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// Reload current user profile to update emailVerified flag.
  Future<void> reloadUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      await user.reload();
    }
  }

  /// 3. Sign in with Google (supports modern web popup flow and mobile native flow).
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Guard web persistence right before triggering popup flow in Safari/WebKit
        try {
          await _auth.setPersistence(Persistence.LOCAL);
        } catch (e) {
          debugPrint('Notice: Local persistence failed before popup, falling back to SESSION: $e');
          try {
            await _auth.setPersistence(Persistence.SESSION);
          } catch (_) {
            try {
              await _auth.setPersistence(Persistence.NONE);
            } catch (_) {}
          }
        }

        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('email');
        googleProvider.addScope('profile');
        return await _auth.signInWithPopup(googleProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) {
          // User cancelled the sign-in flow
          return null;
        }

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        return await _auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') {
        debugPrint('Google Sign-In popup closed by user: ${e.code}');
        return null;
      }
      debugPrint('FirebaseAuthException during Google Sign-In: ${e.code} - ${e.message}');
      rethrow;
    } catch (e, stack) {
      debugPrint('Error during Google Sign-In: $e\n$stack');
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('database is closing') ||
          errorStr.contains('closing/hidden') ||
          errorStr.contains('popup-closed') ||
          errorStr.contains('cancelled')) {
        debugPrint('Handled WebKit/popup sign-in interruption: $e');
        return null;
      }
      rethrow;
    }
  }

  /// 4. Phone Number Verification (Sends 6-digit SMS OTP).
  Future<void> verifyPhone({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    required Function(String errorMessage) onError,
    Function(PhoneAuthCredential credential)? verificationCompleted,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (verificationCompleted != null) {
          verificationCompleted(credential);
        } else {
          await _auth.signInWithCredential(credential);
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        onError(e.message ?? 'Phone verification failed. Please try again.');
      },
      codeSent: (String verificationId, int? resendToken) {
        codeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// 5. Sign in using 6-digit SMS code and verificationId.
  Future<UserCredential> signInWithOTP({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return await _auth.signInWithCredential(credential);
  }

  /// Sign out current user from Firebase and GoogleSignIn.
  Future<void> signOut() async {
    try {
      TourService().clearCache();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  /// Send password reset email.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Re-authenticate current user with Email & Password
  Future<void> reauthenticateWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('No authenticated user with email found.');
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Re-authenticate current user with Google Sign-In
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No authenticated user found.');
    }
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in was cancelled.');
    }
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Task 2: Complete User Account Deletion complying with Play Store data privacy:
  /// Step 1: Delete profile picture from Firebase Storage
  /// Step 2: Delete main user document & subcollections (focus_sessions, exams, syllabus) from Firestore
  /// Step 3: Delete user record from FirebaseAuth
  Future<void> deleteAccount({String? profileImageUrl}) async {
    print('--- DEBUG: ATTEMPTING ACCOUNT DELETION ---');
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No user is currently signed in.');
    }
    final uid = user.uid;

    // Step 1: Delete profile picture from Firebase Storage (if URL exists)
    if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
      try {
        final storageRef = FirebaseStorage.instance.refFromURL(profileImageUrl);
        await storageRef.delete();
      } catch (e) {
        debugPrint('Warning deleting profile image URL: $e');
      }
    }
    try {
      final listResult = await FirebaseStorage.instance.ref().child('users/$uid').listAll();
      for (final item in listResult.items) {
        await item.delete();
      }
    } catch (e) {
      debugPrint('Storage directory cleanup note: $e');
    }

    // Step 2: Delete all subcollections and main user document from Cloud Firestore
    final firestore = FirebaseFirestore.instance;
    final userDocRef = firestore.collection('users').doc(uid);

    // Delete focus_sessions subcollection
    try {
      final sessions = await userDocRef.collection('focus_sessions').get();
      if (sessions.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in sessions.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error deleting focus_sessions on account deletion: $e');
    }

    // Delete exams subcollection
    try {
      final exams = await userDocRef.collection('exams').get();
      if (exams.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in exams.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error deleting exams on account deletion: $e');
    }

    // Delete syllabus & syllabus_state subcollections
    try {
      final syllabus = await userDocRef.collection('syllabus').get();
      if (syllabus.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in syllabus.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
      final syllabusState = await userDocRef.collection('syllabus_state').get();
      if (syllabusState.docs.isNotEmpty) {
        final batch = firestore.batch();
        for (final doc in syllabusState.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Error deleting syllabus on account deletion: $e');
    }

    // Delete main document
    try {
      await userDocRef.delete();
    } catch (e) {
      debugPrint('Error deleting main user document on account deletion: $e');
    }

    // Step 3: Delete from FirebaseAuth
    try {
      await _googleSignIn.signOut();
    } catch (_) {}

    await user.delete();
  }
}

/// Riverpod Provider wrapping [AuthService].
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

/// StreamProvider listening to [FirebaseAuth.authStateChanges].
final authStateChangesProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Provider for current [User] from auth state stream.
final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).asData?.value;
});
