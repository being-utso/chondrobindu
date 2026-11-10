import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';
import '../providers/firestore_providers.dart';
import '../providers/user_profile_provider.dart';
import '../services/auth_service.dart';
import '../services/tour_service.dart';
import '../utils/safe_haptics.dart';
import '../widgets/app_logo.dart';

enum AuthMode { signIn, signUp }
enum AcademicTrack { university, college }

class AdmissionTargetOption {
  final String id;
  final String name;
  final IconData icon;
  final String tag;

  const AdmissionTargetOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.tag,
  });
}

/// Dynamic Admission Targets catalog mapped strictly by HSC Division / Group
const Map<String, List<AdmissionTargetOption>> kAdmissionTargetsByGroup = {
  'Science': [
    AdmissionTargetOption(
      id: 'eng',
      name: 'BUET / Engineering',
      icon: Icons.precision_manufacturing_rounded,
      tag: 'Core Eng',
    ),
    AdmissionTargetOption(
      id: 'med',
      name: 'Medical / Dental',
      icon: Icons.medical_services_rounded,
      tag: 'MBBS / BDS',
    ),
    AdmissionTargetOption(
      id: 'varsity_a',
      name: 'Varsity A-Unit (Science)',
      icon: Icons.biotech_rounded,
      tag: 'DU / JU / RU',
    ),
    AdmissionTargetOption(
      id: 'iba_sci',
      name: 'IBA / BBA',
      icon: Icons.leaderboard_rounded,
      tag: 'Aptitude',
    ),
  ],
  'Humanities': [
    AdmissionTargetOption(
      id: 'varsity_b',
      name: 'Varsity B-Unit (Arts & Law)',
      icon: Icons.gavel_rounded,
      tag: 'DU / Law / Arts',
    ),
    AdmissionTargetOption(
      id: 'bup_fass',
      name: 'BUP FASS / FBS',
      icon: Icons.menu_book_rounded,
      tag: 'Security Studies',
    ),
    AdmissionTargetOption(
      id: 'iba_hum',
      name: 'IBA / General',
      icon: Icons.psychology_rounded,
      tag: 'Aptitude & GK',
    ),
  ],
  'Commerce': [
    AdmissionTargetOption(
      id: 'varsity_c',
      name: 'Varsity C-Unit (Business)',
      icon: Icons.account_balance_rounded,
      tag: 'DU FBS',
    ),
    AdmissionTargetOption(
      id: 'iba_comm',
      name: 'IBA / BBA (DU/JU)',
      icon: Icons.trending_up_rounded,
      tag: 'Finance & Mgmt',
    ),
    AdmissionTargetOption(
      id: 'bup_fbs',
      name: 'BUP FBS',
      icon: Icons.corporate_fare_rounded,
      tag: 'Business Adm.',
    ),
  ],
};

/// Refactored Authentication & Academic Onboarding Portal
/// Features:
/// 1. Unified smooth scrollable page wrapper (`min-h-screen overflow-y-auto`).
/// 2. Desktop 960px centered dual-pane card: 
///    - Left Pane (45%): Deep Natural Indigo (#2F4A6D) Brand Poster with Chondrobindu mark,
///      feature bullets, discipline quote, dynamically matching the expanded height of the right pane.
///    - Right Pane (55%): Warm Chalk (#F7F5F0 Light / #202733 Dark) authentication card.
/// 3. Interactive segmented switcher ([ Sign In | Create Account ]).   
/// 4. Full conditional academic track logic (University vs College / Admission). 
/// 5. Conditional target cards with contrast specs (#EDEAE0 text, #2A3444 surface, #C88256 rust border).
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  AuthMode _authMode = AuthMode.signIn;
  AcademicTrack _academicTrack = AcademicTrack.university;
  String? _hscGroup;
  bool _isAdmissionCandidate = false;
  String? _selectedPrimaryTarget;
  String? _selectedSecondaryTarget;

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  // Text Editing Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // University Fields (starts blank with clean placeholders)
  final _uniInstitutionController = TextEditingController();
  final _deptBatchController = TextEditingController();
  final _levelTermController = TextEditingController();

  // College Fields (starts blank with clean placeholders)
  final _collegeNameController = TextEditingController();
  final _hscBatchController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _uniInstitutionController.dispose();
    _deptBatchController.dispose();
    _levelTermController.dispose();
    _collegeNameController.dispose();
    _hscBatchController.dispose();
    super.dispose();
  }

  void _switchAuthMode(AuthMode mode) {
    if (_authMode == mode) return;
    SafeHaptics.selectionClick();
    setState(() {
      _authMode = mode;
      _formKey.currentState?.reset();
    });
  }

  void _switchAcademicTrack(AcademicTrack track) {
    if (_academicTrack == track) return;
    SafeHaptics.selectionClick();
    setState(() {
      _academicTrack = track;
    });
  }

  void _onHscGroupChanged(String newGroup) {
    if (_hscGroup == newGroup) return;
    SafeHaptics.selectionClick();
    setState(() {
      _hscGroup = newGroup;
      _selectedPrimaryTarget = null;
      _selectedSecondaryTarget = null;
    });
  }

  Future<void> _submitAuth() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    SafeHaptics.mediumImpact();

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
        final nickname = fullName.isNotEmpty
            ? (fullName.contains(' ') ? fullName.split(' ').first : fullName)
            : 'Student';

        if (user != null) {
          final isUni = _academicTrack == AcademicTrack.university;
          final userProfile = UserProfile(
            uid: user.uid,
            fullName: fullName.isNotEmpty ? fullName : 'Student',
            nickname: nickname,
            username: email.split('@').first,
            email: email,
            phone: '',
            institutionType: isUni ? InstitutionType.university : InstitutionType.college,
            universityName: isUni ? _uniInstitutionController.text.trim() : null,
            major: isUni ? _deptBatchController.text.trim() : null,
            department: isUni ? _deptBatchController.text.trim() : null,
            term: isUni ? _levelTermController.text.trim() : null,
            college: !isUni ? _collegeNameController.text.trim() : '',
            batch: !isUni ? _hscBatchController.text.trim() : '2025',
            academicGroup: !isUni ? _hscGroup : null,
            primaryTarget: !isUni && _isAdmissionCandidate ? (_selectedPrimaryTarget ?? 'General') : 'Undergraduate',
            secondaryTarget: !isUni && _isAdmissionCandidate ? (_selectedSecondaryTarget ?? 'None') : 'None',
            isUniversityStudent: isUni,
            isOnboarded: true,
          );

          await ref.read(userProfileProvider.notifier).saveProfile(userProfile, uid: user.uid);
          try {
            await ref.read(dataSeedServiceProvider).seedInitialTrackData(
                  user.uid,
                  isUni ? InstitutionType.university : InstitutionType.college,
                );
          } catch (_) {}

          await TourService().initializeForNewUser(user.uid);

          if (mounted) {
            _showVerificationDialog(email);
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) _handleFirebaseAuthError(e);
    } catch (e) {
      if (mounted) _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isGoogleLoading = true);
    SafeHaptics.selectionClick();
    final authService = ref.read(authServiceProvider);

    try {
      final credential = await authService.signInWithGoogle();
      if (credential == null || credential.user == null) return;

      final user = credential.user!;
      final uid = user.uid;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      final data = doc.data();
      if (doc.exists && data != null) {
        final profile = UserProfile.fromMap(data);
        await ref.read(userProfileProvider.notifier).saveProfile(
              profile.copyWith(
                profileImageUrl: (profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty)
                    ? profile.profileImageUrl
                    : user.photoURL,
              ),
              uid: uid,
            );
      } else {
        final initialProfile = UserProfile.fromFirebaseUser(user);
        await ref.read(userProfileProvider.notifier).saveProfile(initialProfile, uid: uid);
        await TourService().initializeForNewUser(uid);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted && e.code != 'popup-closed-by-user' && e.code != 'cancelled-popup-request') {
        _handleFirebaseAuthError(e);
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _showVerificationDialog(String email) {
    final colors = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        icon: Icon(Icons.mark_email_read_rounded, color: colors.secondary, size: 48),
        title: Text(
          'Verification Email Sent',
          style: GoogleFonts.plusJakartaSans(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: Text(
          'We have sent a verification link to $email.\n\nPlease check your inbox and verify to access all features.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
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
    String message = 'Authentication error. Please check your credentials.';
    switch (e.code) {
      case 'user-not-found':
        message = 'No scholar account found with this email.';
        break;
      case 'wrong-password':
      case 'invalid-credential':
        message = 'Invalid email or password.';
        break;
      case 'email-already-in-use':
        message = 'An account with this email already exists.';
        break;
      case 'weak-password':
        message = 'Password should be at least 6 characters.';
        break;
      case 'invalid-email':
        message = 'Please enter a valid email address.';
        break;
      case 'network-request-failed':
        message = 'Network error. Please check your connection.';
        break;
      default:
        message = e.message ?? message;
    }
    _showErrorSnackBar(message);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
        ),
        backgroundColor: const Color(0xFFBA1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= 800;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isDesktop ? 32.0 : 16.0,
            vertical: isDesktop ? 48.0 : 28.0,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: isDesktop
                  ? _buildDesktopDualPane(colors, isDark)
                  : _buildMobilePortal(colors, isDark),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // 1. DESKTOP 960px DUAL-PANE CARD
  // =========================================================================
  Widget _buildDesktopDualPane(ChondrobinduThemeColors colors, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Pane (45% width): Deep Natural Indigo Brand Poster (#2F4A6D Light / #13171E Dark)
            Expanded(
              flex: 45,
              child: _buildLeftBrandPoster(colors, isDark),
            ),

            // Vertical 1px Divider
            Container(
              width: 1.0,
              color: colors.surfaceBorder,
            ),

            // Right Pane (55% width): Warm Chalk Authentication Card
            Expanded(
              flex: 55,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(40.0, 36.0, 40.0, 64.0),
                child: _buildAuthFormContent(colors, isDark, isDesktop: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Left Brand Poster (#2F4A6D Deep Natural Indigo Light / #13171E Dark)
  Widget _buildLeftBrandPoster(ChondrobinduThemeColors colors, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF13171E) : const Color(0xFF2F4A6D),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(36.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top Tag
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2A3A).withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF8FA8C8).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFB68A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '• CHONDROBINDU ACADEMIC OS',
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFFEDEAE0),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Logo Mark
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F5F0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCD7C8)),
                ),
                padding: const EdgeInsets.all(8),
                child: const AppLogo(size: 36, showContainer: false, isDark: false),
              ),
              const SizedBox(height: 20),

              // Hero Title
              Text(
                'Built for rigorous semesters & deep focus.',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDEAE0),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 24),

              // Feature Bullets
              _buildFeatureBullet(Icons.account_tree_rounded, '3-Level Syllabus Tree'),
              const SizedBox(height: 12),
              _buildFeatureBullet(Icons.calendar_month_rounded, 'Exam-Aware Routine & CT Ledger'),
              const SizedBox(height: 12),
              _buildFeatureBullet(Icons.analytics_rounded, 'Live Pomodoro & CGPA Forecaster'),
            ],
          ),

          const SizedBox(height: 32),

          // Classical Discipline Quote
          Container(
            padding: const EdgeInsets.only(top: 16),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0x338FA8C8), width: 1.0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '“Discipline is choosing between what you want now and what you want most.”',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFEDEAE0).withValues(alpha: 0.8),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— SCHOLASTIC MAXIM',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFEDEAE0).withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBullet(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: const Color(0x3389502A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0x66FFB68A)),
          ),
          child: Icon(icon, color: const Color(0xFFFFB68A), size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFEDEAE0).withValues(alpha: 0.95),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 2. MOBILE RESPONSIVE WRAPPER
  // =========================================================================
  Widget _buildMobilePortal(ChondrobinduThemeColors colors, bool isDark) {
    return Column(
      children: [
        // Compact Branded Header
        Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 32, showContainer: false),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'চন্দ্রবিন্দু',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'CHONDROBINDU ACADEMIC OS',
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.secondary,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Mobile Card Wrapper
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.surfaceBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20.0),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _buildAuthFormContent(colors, isDark, isDesktop: false),
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // 3. CORE FORM CONTENT (Switchable Sign In vs Create Account)
  // =========================================================================
  Widget _buildAuthFormContent(
    ChondrobinduThemeColors colors,
    bool isDark, {
    required bool isDesktop,
  }) {
    final isSignIn = _authMode == AuthMode.signIn;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Segmented Pill Switcher [ Sign In | Create Account ]
          _buildSegmentedSwitcher(colors, isDark),
          const SizedBox(height: 24),

          // Header Text
          Text(
            isSignIn ? 'Welcome back' : 'Create Scholar Account',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isSignIn
                ? 'Sign in to synchronize your academic workspace.'
                : 'Initialize your academic profile, syllabus & track.',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 18),

          // Google OAuth Button
          _buildGoogleSignInButton(colors, isDark, isSignIn),
          const SizedBox(height: 18),

          // Divider with "or"
          Row(
            children: [
              Expanded(child: Divider(color: colors.surfaceBorder, height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Text(
                  isSignIn ? 'OR SIGN IN WITH EMAIL' : 'OR REGISTER WITH EMAIL',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Expanded(child: Divider(color: colors.surfaceBorder, height: 1)),
            ],
          ),
          const SizedBox(height: 18),

          // Dynamic Form Fields: Sign In vs Create Account
          if (isSignIn)
            _buildSignInFields(colors)
          else
            _buildCreateAccountFields(colors, isDark, isDesktop),

          const SizedBox(height: 24),

          // Primary Submit Button ("Enter Workspace →" / "Create Account & Initialize →")
          _buildPrimarySubmitButton(colors, isSignIn),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Segmented Switcher [ Sign In | Create Account ]
  Widget _buildSegmentedSwitcher(ChondrobinduThemeColors colors, bool isDark) {
    final isSignIn = _authMode == AuthMode.signIn;

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _switchAuthMode(AuthMode.signIn),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSignIn ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSignIn
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Sign In',
                  style: GoogleFonts.plusJakartaSans(
                    color: isSignIn ? colors.textPrimary : colors.textMuted,
                    fontWeight: isSignIn ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _switchAuthMode(AuthMode.signUp),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !isSignIn ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: !isSignIn
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  'Create Account',
                  style: GoogleFonts.plusJakartaSans(
                    color: !isSignIn ? colors.textPrimary : colors.textMuted,
                    fontWeight: !isSignIn ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Google OAuth Button
  Widget _buildGoogleSignInButton(ChondrobinduThemeColors colors, bool isDark, bool isSignIn) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: _isGoogleLoading ? null : _signInWithGoogle,
      child: _isGoogleLoading
          ? SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.network(
                  'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                  width: 16,
                  height: 16,
                  errorBuilder: (_, __, ___) => Icon(Icons.g_mobiledata_rounded, color: colors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  isSignIn ? 'Continue with Google' : 'Sign up with Google',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
    );
  }

  // Sign In Form Fields
  Widget _buildSignInFields(ChondrobinduThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Email address', colors),
        const SizedBox(height: 6),
        _buildTextInput(
          controller: _emailController,
          hintText: 'scholar@university.edu',
          keyboardType: TextInputType.emailAddress,
          colors: colors,
          validator: (val) {
            if (val == null || val.trim().isEmpty) return 'Email is required';
            if (!val.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 14),

        _buildFieldLabel('Password', colors),
        const SizedBox(height: 6),
        _buildPasswordInput(_passwordController, colors),
      ],
    );
  }

  // Create Account Form Fields
  Widget _buildCreateAccountFields(
    ChondrobinduThemeColors colors,
    bool isDark,
    bool isDesktop,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Name & Email (2-column on desktop, single column on mobile)
        if (isDesktop)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Full Name', colors),
                    const SizedBox(height: 6),
                    _buildTextInput(
                      controller: _nameController,
                      hintText: 'e.g. Shahriyer Sayem',
                      colors: colors,
                      validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Email address', colors),
                    const SizedBox(height: 6),
                    _buildTextInput(
                      controller: _emailController,
                      hintText: 'scholar@buet.ac.bd',
                      keyboardType: TextInputType.emailAddress,
                      colors: colors,
                      validator: (val) => val == null || !val.contains('@') ? 'Valid email required' : null,
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          _buildFieldLabel('Full Name', colors),
          const SizedBox(height: 6),
          _buildTextInput(
            controller: _nameController,
            hintText: 'e.g. Shahriyer Sayem',
            colors: colors,
            validator: (val) => val == null || val.trim().isEmpty ? 'Full name is required' : null,
          ),
          const SizedBox(height: 12),
          _buildFieldLabel('Email address', colors),
          const SizedBox(height: 6),
          _buildTextInput(
            controller: _emailController,
            hintText: 'scholar@buet.ac.bd',
            keyboardType: TextInputType.emailAddress,
            colors: colors,
            validator: (val) => val == null || !val.contains('@') ? 'Valid email required' : null,
          ),
        ],

        const SizedBox(height: 12),

        // Create Password
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildFieldLabel('Create Password', colors),
            Text(
              'Min. 6 characters',
              style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _buildPasswordInput(_passwordController, colors),

        const SizedBox(height: 16),
        Divider(color: colors.surfaceBorder.withValues(alpha: 0.6), height: 1),
        const SizedBox(height: 14),

        // Academic Track Switcher
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACADEMIC TRACK',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            Text(
              _academicTrack == AcademicTrack.university
                  ? 'University (4.00 CGPA)'
                  : 'College / Admission (5.00)',
              style: GoogleFonts.jetBrainsMono(
                color: colors.secondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Track Selector Buttons [ University (4.00) ] vs [ College / Admission (5.00) ]
        Row(
          children: [
            Expanded(
              child: _buildTrackOptionButton(
                label: '🏛️ University (4.00)',
                isSelected: _academicTrack == AcademicTrack.university,
                colors: colors,
                onTap: () => _switchAcademicTrack(AcademicTrack.university),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTrackOptionButton(
                label: '📚 College / Admission (5.00)',
                isSelected: _academicTrack == AcademicTrack.college,
                colors: colors,
                onTap: () => _switchAcademicTrack(AcademicTrack.college),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Conditional Track Fields
        if (_academicTrack == AcademicTrack.university)
          _buildUniversityFields(colors)
        else
          _buildCollegeAdmissionFields(colors, isDark),
      ],
    );
  }

  Widget _buildTrackOptionButton({
    required String label,
    required bool isSelected,
    required ChondrobinduThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : colors.recessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.surfaceBorder,
            width: 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? Colors.white : colors.textMuted,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // University Track Specific Fields
  Widget _buildUniversityFields(ChondrobinduThemeColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Institution', colors, isSmall: true),
              const SizedBox(height: 4),
              _buildTextInput(
                controller: _uniInstitutionController,
                hintText: 'e.g. BUET',
                colors: colors,
                isDense: true,
                height: 48,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Dept / Batch', colors, isSmall: true),
              const SizedBox(height: 4),
              _buildTextInput(
                controller: _deptBatchController,
                hintText: "e.g. EEE '25",
                colors: colors,
                isDense: true,
                height: 48,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Level / Term', colors, isSmall: true),
              const SizedBox(height: 4),
              _buildTextInput(
                controller: _levelTermController,
                hintText: 'e.g. L-1 • T-1',
                colors: colors,
                isDense: true,
                height: 48,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // College / Admission Track Specific Fields
  Widget _buildCollegeAdmissionFields(ChondrobinduThemeColors colors, bool isDark) {
    final targets = _hscGroup != null ? (kAdmissionTargetsByGroup[_hscGroup] ?? []) : <AdmissionTargetOption>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Last Attended College / Institution
        _buildFieldLabel('LAST ATTENDED COLLEGE / INSTITUTION', colors, isSmall: true),
        const SizedBox(height: 4),
        SizedBox(
          height: 48,
          child: _buildTextInput(
            controller: _collegeNameController,
            hintText: 'e.g. Notre Dame College',
            colors: colors,
            isDense: true,
            height: 48,
          ),
        ),
        const SizedBox(height: 10),

        // 2. HSC Batch & 3. HSC Group / Division (Science, Humanities, Commerce)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('HSC BATCH', colors, isSmall: true),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: _buildTextInput(
                      controller: _hscBatchController,
                      hintText: 'e.g. 2025',
                      colors: colors,
                      isDense: true,
                      height: 48,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('HSC GROUP / DIVISION', colors, isSmall: true),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.surfaceBorder, width: 1.0),
                      ),
                      alignment: Alignment.center,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _hscGroup,
                          isExpanded: true,
                          isDense: true,
                          hint: Text(
                            'Select group...',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textMuted.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          dropdownColor: colors.surface,
                          icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.textMuted, size: 18),
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Science', child: Text('Science')),
                            DropdownMenuItem(value: 'Humanities', child: Text('Humanities')),
                            DropdownMenuItem(value: 'Commerce', child: Text('Commerce')),
                          ],
                          onChanged: (val) {
                            if (val != null) _onHscGroupChanged(val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 4. Admission Candidate Checkbox Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.recessed.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _isAdmissionCandidate,
                      activeColor: colors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) {
                        SafeHaptics.selectionClick();
                        setState(() => _isAdmissionCandidate = val ?? false);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Admission Candidate',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Entrance Prep',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 5. Conditional Target Cards (Shown ONLY when Admission Candidate is checked)
        if (_isAdmissionCandidate) ...[
          const SizedBox(height: 12),
          Divider(color: colors.surfaceBorder.withValues(alpha: 0.6), height: 1),
          const SizedBox(height: 10),

          if (_hscGroup == null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.recessed.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: colors.secondary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Select your HSC Group above to load target choices.',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PRIMARY ADMISSION TARGET',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  _selectedPrimaryTarget != null ? '1 Selected' : '0 Selected',
                  style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Primary Target Cards (Built with pure Flex Rows to guarantee perfect intrinsic height calculation)
            Column(
              children: [
                for (int i = 0; i < targets.length; i += 2) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPrimaryTargetCard(targets[i], colors, isDark),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i + 1 < targets.length
                            ? _buildPrimaryTargetCard(targets[i + 1], colors, isDark)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // Secondary Target (Optional backup selection)
            Text(
              'SECONDARY TARGET (OPTIONAL)',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: targets.where((t) => t.name != _selectedPrimaryTarget).map((t) {
                final isSec = t.name == _selectedSecondaryTarget;
                return InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() {
                      _selectedSecondaryTarget = isSec ? null : t.name;
                    });
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSec ? colors.secondary.withValues(alpha: 0.15) : colors.recessed,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSec ? colors.secondary : colors.surfaceBorder,
                      ),
                    ),
                    child: Text(
                      isSec ? '✓ ${t.name}' : '+ ${t.name}',
                      style: GoogleFonts.plusJakartaSans(
                        color: isSec ? colors.secondary : colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: isSec ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildPrimaryTargetCard(
    AdmissionTargetOption target,
    ChondrobinduThemeColors colors,
    bool isDark,
  ) {
    final isSelected = target.name == _selectedPrimaryTarget;

    final bgColor = isSelected
        ? (isDark ? const Color(0xFF2A3444) : colors.primary.withValues(alpha: 0.12))
        : colors.recessed;
    final borderSideColor = isSelected
        ? (isDark ? const Color(0xFFC88256) : colors.primary)
        : colors.surfaceBorder;
    final textColor = isSelected
        ? (isDark ? const Color(0xFFEDEAE0) : colors.primary)
        : colors.textMuted;

    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() {
          _selectedPrimaryTarget = target.name;
          if (_selectedSecondaryTarget == target.name) {
            _selectedSecondaryTarget = null;
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderSideColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  target.icon,
                  color: isSelected ? (isDark ? const Color(0xFFC88256) : colors.primary) : colors.textMuted,
                  size: 15,
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFFC88256) : colors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'TARGET 1',
                      style: GoogleFonts.jetBrainsMono(
                        color: isDark ? const Color(0xFF13171E) : Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Text(
                    target.tag,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.secondary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              target.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                color: textColor,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Primary Submit Button
  Widget _buildPrimarySubmitButton(ChondrobinduThemeColors colors, bool isSignIn) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
      onPressed: _isLoading ? null : _submitAuth,
      child: _isLoading
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isSignIn ? 'Enter Workspace' : 'Create Account & Initialize',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 16),
              ],
            ),
    );
  }

  // Helpers
  Widget _buildFieldLabel(String text, ChondrobinduThemeColors colors, {bool isSmall = false}) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        color: colors.textPrimary,
        fontSize: isSmall ? 10.5 : 12,
        fontWeight: FontWeight.w600,
        letterSpacing: isSmall ? 0.4 : 0,
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String hintText,
    required ChondrobinduThemeColors colors,
    TextInputType keyboardType = TextInputType.text,
    bool isDense = false,
    double? height,
    String? Function(String?)? validator,
  }) {
    final inputWidget = TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      textAlignVertical: TextAlignVertical.center,
      style: GoogleFonts.plusJakartaSans(
        color: colors.textPrimary,
        fontSize: isDense ? 12 : 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: GoogleFonts.plusJakartaSans(
          color: colors.textMuted.withValues(alpha: 0.7),
          fontSize: isDense ? 12 : 13,
        ),
        filled: true,
        fillColor: colors.recessed,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.surfaceBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.surfaceBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.2),
        ),
      ),
    );

    if (height != null) {
      return SizedBox(
        height: height,
        child: inputWidget,
      );
    }
    return inputWidget;
  }

  Widget _buildPasswordInput(TextEditingController controller, ChondrobinduThemeColors colors) {
    return TextFormField(
      controller: controller,
      obscureText: _obscurePassword,
      validator: (val) {
        if (val == null || val.isEmpty) return 'Password is required';
        if (val.length < 6) return 'Minimum 6 characters';
        return null;
      },
      style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: '••••••••',
        hintStyle: GoogleFonts.plusJakartaSans(
          color: colors.textMuted.withValues(alpha: 0.7),
          fontSize: 13,
        ),
        filled: true,
        fillColor: colors.recessed,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colors.primary, width: 1.2),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: colors.textMuted,
            size: 18,
          ),
          onPressed: () {
            setState(() => _obscurePassword = !_obscurePassword);
          },
        ),
      ),
    );
  }
}
