import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/user_profile_provider.dart';
import '../services/auth_service.dart';
import '../services/tour_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_preloader.dart';
import 'package:google_fonts/google_fonts.dart';

enum AuthMode { signIn, signUp }

/// Unified Authentication Screen featuring Email/Password, Google Sign-In, and Phone Auth (OTP).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  AuthMode _authMode = AuthMode.signIn;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  final _nameController = TextEditingController();
  final _institutionController = TextEditingController();
  final _majorController = TextEditingController();
  final _termController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _institutionController.dispose();
    _majorController.dispose();
    _termController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _authMode = _authMode == AuthMode.signIn ? AuthMode.signUp : AuthMode.signIn;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submitEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isLoading = true);

    final authService = ref.read(authServiceProvider);
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      if (_authMode == AuthMode.signIn) {
        await authService.signInWithEmail(email, password);
      } else {
        final credential = await authService.signUpWithEmail(email, password);
        final user = credential.user;
        final fullName = _nameController.text.trim();
        final institution = _institutionController.text.trim();
        final major = _majorController.text.trim();
        final term = _termController.text.trim();

        if (user != null) {
          final nickname = fullName.isNotEmpty
              ? (fullName.contains(' ') ? fullName.split(' ').first : fullName)
              : 'Student';

          await ref.read(userProfileProvider.notifier).saveProfile(
                UserProfile(
                  fullName: fullName.isNotEmpty ? fullName : 'Student',
                  nickname: nickname,
                  username: email.split('@').first,
                  email: email,
                  phone: '',
                  college: institution,
                  universityName: institution,
                  major: major,
                  term: term.isNotEmpty ? term : 'Term 1',
                  isUniversityStudent: true,
                  isOnboarded: true,
                  hscBatch: 'Varsity',
                  hscGroup: 'Science',
                  district: 'Dhaka',
                  primaryTarget: 'Undergraduate',
                  secondaryTarget: 'None',
                ),
                uid: user.uid,
              );

          await TourService().initializeForNewUser(user.uid);

          if (mounted) {
            _showVerificationDialog(email);
          }
        }
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error loading profile: Timed out waiting for response (${e.message ?? e.toString()})');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        _handleFirebaseAuthError(e);
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error loading profile: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    final authService = ref.read(authServiceProvider);

    try {
      final credential = await authService.signInWithGoogle();
      if (credential == null || credential.user == null) {
        // User cancelled or closed the sign-in popup
        return;
      }

      final user = credential.user!;
      final uid = user.uid;

      // Check if user profile exists in Firestore and has completed onboarding with 10s timeout failsafe
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      final data = doc.data();

      if (doc.exists && data != null) {
        final profile = UserProfile.fromMap(data);
        final bool isComplete = profile.isOnboarded &&
            profile.fullName.trim().isNotEmpty &&
            (profile.isUniversityStudent
                ? (profile.universityName?.trim().isNotEmpty ?? false)
                : profile.college.trim().isNotEmpty);

        await ref.read(userProfileProvider.notifier).saveProfile(
              profile.copyWith(
                profileImageUrl: (profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty)
                    ? profile.profileImageUrl
                    : user.photoURL,
                isOnboarded: isComplete,
              ),
              uid: uid,
            );
      } else {
        // New Google Sign-In user (first-time web or mobile login):
        // Initialize user record with default profile values before attempting to parse or load profile into state
        final initialProfile = UserProfile.fromFirebaseUser(user);

        await ref.read(userProfileProvider.notifier).saveProfile(
              initialProfile,
              uid: uid,
            );

        await TourService().initializeForNewUser(uid);
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        _showErrorSnackBar('Error loading profile: Timed out waiting for profile response (${e.message ?? e.toString()})');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request') {
          _handleFirebaseAuthError(e);
        }
      }
    } catch (e) {
      if (mounted) {
        final errText = e.toString();
        if (errText.toLowerCase().contains('closing/hidden') ||
            errText.toLowerCase().contains('database is closing')) {
          _showErrorSnackBar('Web browser storage error: IndexedDB was closed or restricted. Please try again.');
        } else {
          _showErrorSnackBar('Error loading profile: $errText');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  void _showPhoneAuthBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PhoneAuthBottomSheet(),
    );
  }

  void _showVerificationDialog(String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF382A24)),
        ),
        icon: const Icon(Icons.mark_email_read_rounded, color: Color(0xFFF2B78A), size: 48),
        title: Text(
          'Verification Email Sent',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'We have sent a verification link to $email.\n\nPlease check your inbox and click the link to verify your email address.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Got It', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleFirebaseAuthError(FirebaseAuthException e) {
    String message = 'Authentication error. Please try again.';
    switch (e.code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Invalid email or password.';
        break;
      case 'email-already-in-use':
        message = 'An account is already registered with this email.';
        break;
      case 'invalid-email':
        message = 'Please enter a valid email address.';
        break;
      case 'weak-password':
        message = 'Password must be at least 6 characters long.';
        break;
      case 'user-disabled':
        message = 'This user account has been disabled.';
        break;
      default:
        if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
    }
    _showErrorSnackBar(message);
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text.trim());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF382A24)),
        ),
        title: Text(
          'Reset Password',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your registered email address to receive a password reset link.',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
              decoration: _buildInputDecoration(
                hintText: 'Enter your email',
                prefixIcon: Icons.email_outlined,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final email = resetEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                _showErrorSnackBar('Please enter a valid email address.');
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref.read(authServiceProvider).sendPasswordResetEmail(email);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      content: Text(
                        'Password reset email sent! Check your inbox.',
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  _showErrorSnackBar('Failed to send reset email: $e');
                }
              }
            },
            child: Text('Send Link', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF382A24);

    final isSignIn = _authMode == AuthMode.signIn;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. App Branded Hero Header with Master Logo
                const Center(
                  child: AppLogo(size: 76),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'Chondrobindu',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Academic operating system & deep study tracker',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFABA093),
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Email & Password Form Card
                Container(
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSignIn ? 'Sign In' : 'Create an Account',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isSignIn
                              ? 'Access your synchronized study syllabus & exams'
                              : 'Structure your semester, courses, and focus sessions.',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFABA093),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Full Name (Only on Sign Up)
                        if (!isSignIn) ...[
                          _buildInputLabel('Full Name'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _nameController,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                            textCapitalization: TextCapitalization.words,
                            decoration: _buildInputDecoration(
                              hintText: 'e.g. Shahriyer Sayem',
                              prefixIcon: Icons.person_outline_rounded,
                            ),
                            validator: (val) {
                              if (!isSignIn && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your full name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Institution / University
                          _buildInputLabel('Institution / University'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _institutionController,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                            textCapitalization: TextCapitalization.words,
                            decoration: _buildInputDecoration(
                              hintText: 'e.g. BUET, DU, etc.',
                              prefixIcon: Icons.account_balance_outlined,
                            ),
                            validator: (val) {
                              if (!isSignIn && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your institution/university';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Department / Major
                          _buildInputLabel('Department / Major'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _majorController,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                            textCapitalization: TextCapitalization.words,
                            decoration: _buildInputDecoration(
                              hintText: 'e.g. Electrical & Electronic Engineering',
                              prefixIcon: Icons.school_outlined,
                            ),
                            validator: (val) {
                              if (!isSignIn && (val == null || val.trim().isEmpty)) {
                                return 'Please enter your department/major';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Current Term / Semester (Optional)
                          _buildInputLabel('Current Term / Semester (Optional)'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _termController,
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                            textCapitalization: TextCapitalization.words,
                            decoration: _buildInputDecoration(
                              hintText: 'e.g. Level 1 / Term 2',
                              prefixIcon: Icons.calendar_today_outlined,
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Email Field
                        _buildInputLabel('Email Address'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                          decoration: _buildInputDecoration(
                            hintText: 'you@example.com',
                            prefixIcon: Icons.email_outlined,
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val.trim())) {
                              return 'Please enter a valid email address';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Password Field
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInputLabel('Password'),
                            if (isSignIn)
                              GestureDetector(
                                onTap: _showForgotPasswordDialog,
                                child: Text(
                                  'Forgot password?',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: accentColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                          decoration: _buildInputDecoration(
                            hintText: '••••••••',
                            prefixIcon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: const Color(0xFFABA093),
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter your password';
                            }
                            if (val.trim().length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Primary Action Button
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submitEmailAuth,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: const Color(0xFF110D0C),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const AppPreloader(
                                    size: 20,
                                    strokeWidth: 2,
                                    color: Color(0xFF110D0C),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        isSignIn ? 'Sign In' : 'Create Account',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14.5,
                                          color: const Color(0xFF110D0C),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Icon(Icons.arrow_forward_rounded, size: 17, color: Color(0xFF110D0C)),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Toggle Sign In / Sign Up mode
                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _toggleAuthMode,
                    child: RichText(
                      text: TextSpan(
                        text: isSignIn
                            ? "Don't have an account? "
                            : 'Already have an account? ',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFABA093),
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text: isSignIn ? 'Create Account' : 'Sign In',
                            style: GoogleFonts.plusJakartaSans(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 3. Social / Phone Divider
                Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0),
                      child: Text(
                        'Or continue with',
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFABA093),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        thickness: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. Alternative Buttons: Google & Phone
                Row(
                  children: [
                    // Continue with Google Button
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF241C1A),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isGoogleLoading
                              ? const AppPreloader(
                                  size: 18,
                                  strokeWidth: 2,
                                  color: accentColor,
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'G',
                                      style: TextStyle(
                                        color: Color(0xFFEA4335),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Google',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Continue with Phone Button
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed: _showPhoneAuthBottomSheet,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: const Color(0xFF241C1A),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: borderColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.phone_iphone_rounded,
                                color: accentColor,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Phone',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFFF2B78A), size: 18),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFF241C1A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFF4A3830)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFF4A3830)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.0),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}

/// Phone Authentication Modal BottomSheet managing 2-step OTP flow.
class _PhoneAuthBottomSheet extends ConsumerStatefulWidget {
  const _PhoneAuthBottomSheet();

  @override
  ConsumerState<_PhoneAuthBottomSheet> createState() => _PhoneAuthBottomSheetState();
}

class _PhoneAuthBottomSheetState extends ConsumerState<_PhoneAuthBottomSheet> {
  final _phoneController = TextEditingController(text: '+880');
  final _otpController = TextEditingController();

  bool _isCodeSent = false;
  bool _isLoading = false;
  String? _verificationId;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 10) {
      setState(() => _errorMessage = 'Please enter a valid phone number with country code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);

    try {
      await authService.verifyPhone(
        phoneNumber: phone,
        codeSent: (verificationId) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _isCodeSent = true;
              _isLoading = false;
            });
          }
        },
        onError: (err) {
          if (mounted) {
            setState(() {
              _errorMessage = err;
              _isLoading = false;
            });
          }
        },
        verificationCompleted: (credential) async {
          if (mounted) {
            Navigator.pop(context);
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '$e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    final smsCode = _otpController.text.trim();
    if (smsCode.length < 6 || _verificationId == null) {
      setState(() => _errorMessage = 'Please enter the 6-digit SMS code');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = ref.read(authServiceProvider);

    try {
      final credential = await authService.signInWithOTP(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );

      final user = credential.user;
      if (user != null) {
        final phone = _phoneController.text.trim();
        await ref.read(userProfileProvider.notifier).saveProfile(
              UserProfile(
                fullName: 'Phone User',
                nickname: 'Student',
                username: 'user_${phone.replaceAll(RegExp(r'\D'), '')}',
                email: '',
                phone: phone,
                primaryTarget: 'Engineering',
                secondaryTarget: 'None',
                isOnboarded: true,
              ),
              uid: user.uid,
            );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.code == 'invalid-verification-code'
              ? 'Invalid SMS code. Please check and try again.'
              : (e.message ?? 'Verification failed');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to verify OTP: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFF2B78A);
    const cardColor = Color(0xFF1C1412);
    const borderColor = Color(0xFF382A24);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: const BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: borderColor),
            left: BorderSide(color: borderColor),
            right: BorderSide(color: borderColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A3830),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.phone_iphone_rounded, color: accentColor, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCodeSent ? 'Enter 6-Digit Code' : 'Phone Authentication',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _isCodeSent
                          ? 'Sent to ${_phoneController.text}'
                          : 'Sign in quickly with an SMS OTP code',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFFABA093),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (!_isCodeSent) ...[
              // Step 1: Input Phone Number
              Text(
                'Phone Number (with country code)',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14, letterSpacing: 0.5),
                decoration: InputDecoration(
                  hintText: '+8801700000000',
                  hintStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF6E5B52), fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFF241C1A),
                  prefixIcon: const Icon(Icons.phone_rounded, color: accentColor, size: 18),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4A3830)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4A3830)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accentColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF110D0C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const AppPreloader(size: 20, strokeWidth: 2, color: Color(0xFF110D0C))
                      : Text('Send Verification Code', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: const Color(0xFF110D0C))),
                ),
              ),
            ] else ...[
              // Step 2: Input 6-digit OTP
              Text(
                '6-Digit SMS Code',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: GoogleFonts.jetBrainsMono(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '123456',
                  hintStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF6E5B52), fontSize: 18, letterSpacing: 6),
                  filled: true,
                  fillColor: const Color(0xFF241C1A),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4A3830)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4A3830)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accentColor, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF110D0C),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const AppPreloader(size: 20, strokeWidth: 2, color: Color(0xFF110D0C))
                      : Text('Verify & Sign In', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: const Color(0xFF110D0C))),
                ),
              ),
              const SizedBox(height: 8),

              TextButton(
                onPressed: () => setState(() => _isCodeSent = false),
                child: Text('Change phone number', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
