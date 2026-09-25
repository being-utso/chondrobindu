import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/tour_service.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_preloader.dart';
import 'auth_screen.dart';
import 'main_nav.dart';

/// AuthWrapper gatekeeper widget that checks authentication state & email verification.
/// Prevents auth state flicker by rendering a deep #181211 splash screen while waiting.
class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // While Firebase Auth state is initializing / waiting, show #181211 splash screen
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSplashLoading();
        }

        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFF110D0C),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Authentication Error',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF140F0E),
                      ),
                      onPressed: () => ref.refresh(authStateChangesProvider),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          // No user is logged in -> Show AuthScreen
          return const AuthScreen();
        }

        // Check if user registered via Password and needs email verification
        final isPasswordProvider = user.providerData.any(
          (provider) => provider.providerId == 'password',
        );

        if (isPasswordProvider && !user.emailVerified) {
          // Unverified email account -> Route to VerifyEmailScreen
          return VerifyEmailScreen(user: user);
        }

        // Sync onboarding tour state asynchronously from Firestore
        unawaited(TourService().syncFromFirestore(user.uid));

        // Authenticated & verified user -> Route to Main Navigation
        return const MainNavigationScreen();
      },
    );
  }

  Widget _buildSplashLoading() {
    return const AppLoadingScreen();
  }
}

/// Screen displayed when user must verify their email address before accessing the app.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  final User user;

  const VerifyEmailScreen({super.key, required this.user});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Periodically poll auth state every 4 seconds to auto-detect email verification
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _checkEmailVerified());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkEmailVerified() async {
    setState(() => _isChecking = true);
    final authService = ref.read(authServiceProvider);
    await authService.reloadUser();

    final currentUser = authService.currentUser;
    if (currentUser != null && currentUser.emailVerified) {
      _timer?.cancel();
      // Refresh authStateChangesProvider to rebuild AuthWrapper and route to MainNav
      ref.refresh(authStateChangesProvider);
    } else {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    setState(() => _isResending = true);
    final authService = ref.read(authServiceProvider);

    try {
      await authService.sendEmailVerification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text(
              'Verification email resent! Please check your inbox.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              'Failed to resend email: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const borderColor = Color(0xFF382A24);
    const accentColor = Color(0xFFF2B78A);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: borderColor, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Verification Icon
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1.5),
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_rounded,
                      color: accentColor,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Verify Your Email',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'We sent a verification link to:\n${widget.user.email ?? ''}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFABA093),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),

                  Text(
                    'Please click the link in your email to activate your account and access your syllabus.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFF7E726B),
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Check Status / Verified Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isChecking ? null : _checkEmailVerified,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: const Color(0xFF140F0E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: _isChecking
                          ? const AppPreloader(size: 20, strokeWidth: 2, color: Color(0xFF140F0E))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle_outline_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  "I've Verified",
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14.5),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Resend Email Button
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _isResending ? null : _resendVerificationEmail,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: borderColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isResending
                          ? const AppPreloader(size: 18, strokeWidth: 2)
                          : Text(
                              'Resend Verification Email',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sign Out option
                  TextButton(
                    onPressed: () async {
                      _timer?.cancel();
                      await ref.read(authServiceProvider).signOut();
                    },
                    child: Text(
                      'Use a different account / Sign Out',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
