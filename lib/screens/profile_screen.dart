import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/group_constants.dart';
import '../providers/analytics_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/performance_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_profile_provider.dart';
import '../providers/user_provider.dart';
import '../services/archive_service.dart';
import '../services/auth_service.dart';
import '../services/pdf_report_service.dart';
import '../services/syllabus_factory.dart';
import '../services/timer_service.dart';
import '../services/tour_service.dart';
import 'admission_archive_screen.dart';
import 'archived_terms_screen.dart';
import 'auth_screen.dart';
import 'help_screen.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_preloader.dart';
import '../widgets/compact_loading_dialog.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Comprehensive Profile Screen for Chondrobindu engineering prep app.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isUploadingImage = false;

  // Underlying Signup Method ('email' or 'phone') to dictate field lock status
  final String _signUpMethod = 'email';

  // Text Controllers initialized with userProfileProvider data
  late final TextEditingController _fullNameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _collegeController;
  late final TextEditingController _districtController;

  // University Mode State & Controllers
  bool _isUniversityStudent = false;
  late final TextEditingController _universityController;
  late final TextEditingController _majorController;
  String _selectedLevel = '1';
  String _selectedTerm = '1';

  // Dropdown Selections
  String _hscBatch = '2025';
  String _hscGroup = 'Science';
  String _primaryTarget = 'Engineering (BUET, CKRUET)';
  String? _secondaryTarget = 'None'; // Default initialized to 'None'

  // Options Lists
  final List<String> _batchOptions = ['2024', '2025', '2026', '2027', '2028', '2029'];
  List<String> get _groupOptions => GroupConstants.hscGroups;
  List<String> get _allTargetOptions => GroupConstants.getTargetsForGroup(_hscGroup);

  // Tap gesture recognizer for developer website link
  late final TapGestureRecognizer _developerTapRecognizer;

  @override
  void initState() {
    super.initState();
    _developerTapRecognizer = TapGestureRecognizer()
      ..onTap = () {
        _safeLaunchUrl(context, 'https://being-utso.github.io/');
      };

    final profile = ref.read(userProfileProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    final initialName = profile.fullName.isNotEmpty
        ? profile.fullName
        : (currentUser?.displayName ?? '');
    final initialEmail = profile.email.isNotEmpty
        ? profile.email
        : (currentUser?.email ?? '');

    _fullNameController = TextEditingController(text: initialName);
    _nicknameController = TextEditingController(
      text: profile.nickname.isNotEmpty
          ? profile.nickname
          : (initialName.isNotEmpty ? initialName.split(' ').first : ''),
    );
    _usernameController = TextEditingController(text: profile.username);
    _emailController = TextEditingController(text: initialEmail);
    _phoneController = TextEditingController(text: profile.phone);
    _collegeController = TextEditingController(text: profile.college);
    _districtController = TextEditingController(text: profile.district);

    _isUniversityStudent = profile.isUniversityStudent;
    _universityController = TextEditingController(text: profile.universityName ?? '');
    _majorController = TextEditingController(text: profile.major ?? '');
    _selectedLevel = (profile.level != null && ['1', '2', '3', '4'].contains(profile.level))
        ? profile.level!
        : '1';
    _selectedTerm = (profile.term != null && ['1', '2'].contains(profile.term))
        ? profile.term!
        : '1';

    _hscBatch = _batchOptions.contains(profile.hscBatch) ? profile.hscBatch : '2025';
    _hscGroup = _groupOptions.contains(profile.hscGroup) ? profile.hscGroup : 'Science';

    final target = profile.primaryTarget;
    if (_allTargetOptions.contains(target)) {
      _primaryTarget = target;
    } else {
      _primaryTarget = _allTargetOptions.firstWhere(
        (opt) => opt.toLowerCase().contains(target.toLowerCase()),
        orElse: () => _allTargetOptions.first,
      );
    }
    _secondaryTarget = profile.secondaryTarget;
  }

  @override
  void dispose() {
    _developerTapRecognizer.dispose();
    _fullNameController.dispose();
    _nicknameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _collegeController.dispose();
    _districtController.dispose();
    _universityController.dispose();
    _majorController.dispose();
    super.dispose();
  }

  Future<void> _safeLaunchUrl(BuildContext context, String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFEF4444),
                behavior: SnackBarBehavior.floating,
                content: Text('Could not open link: $urlString'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            content: Text('Error launching URL: $e'),
          ),
        );
      }
    }
  }

  /// Get list of secondary targets with 'None' as default first option
  /// and dynamically excluding the currently selected primary target
  List<String> get _secondaryTargetOptions {
    return [
      'None',
      ..._allTargetOptions.where((option) => option != _primaryTarget)
    ];
  }

  void _onPrimaryTargetChanged(String? newTarget) {
    if (newTarget == null) return;
    setState(() {
      _primaryTarget = newTarget;
      // CRITICAL LOGIC: If secondary target matches new primary target, reset to 'None'
      if (_secondaryTarget != 'None' && _secondaryTarget == _primaryTarget) {
        _secondaryTarget = 'None';
      }
    });
  }

  bool _isSavingProfile = false;

 Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingProfile = true);

    try {
      final newSyllabus = SyllabusFactory.generateInitialSyllabus(_primaryTarget, _hscGroup);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      
      // 1. WRITE SYLLABUS TO FIRESTORE FIRST (Prevents Race Condition)
      if (uid != null) {
        final firestore = FirebaseFirestore.instance;
        final subjectsData = newSyllabus.map((s) => s.toMap()).toList();
        
        await firestore
            .collection('users')
            .doc(uid)
            .collection('syllabus_state')
            .doc('active_syllabus')
            .set({
          'target': _primaryTarget,
          'subjects': subjectsData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 2. NOW UPDATE PROFILE (This triggers the SyllabusScreen to listen)
      await ref.read(userProfileProvider.notifier).updateProfile(
        fullName: _fullNameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        college: _isUniversityStudent
            ? (_universityController.text.trim().isNotEmpty ? _universityController.text.trim() : 'University')
            : _collegeController.text.trim(),
        district: _districtController.text.trim(),
        hscBatch: _isUniversityStudent ? 'Varsity' : _hscBatch,
        hscGroup: _isUniversityStudent ? 'Science' : _hscGroup,
        primaryTarget: _isUniversityStudent ? 'University Studies' : _primaryTarget,
        secondaryTarget: _isUniversityStudent ? 'None' : (_secondaryTarget ?? 'None'),
        isUniversityStudent: _isUniversityStudent,
        universityName: _isUniversityStudent ? _universityController.text.trim() : null,
        major: _isUniversityStudent ? _majorController.text.trim() : null,
        level: _isUniversityStudent ? _selectedLevel : null,
        term: _isUniversityStudent ? _selectedTerm : null,
      );

      // 3. UPDATE PROVIDERS
      ref.invalidate(syllabusProvider);
      ref.read(admissionTargetProvider.notifier).state = _primaryTarget;
      ref.read(syllabusProvider.notifier).setSubjects(newSyllabus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFF2B78A),
            content: Text(
              'Profile updated!',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF110D0C),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }
 
 
  Future<void> _pickAndUploadProfileImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() => _isUploadingImage = true);

      final bytes = await pickedFile.readAsBytes();
      final ext = pickedFile.name.split('.').last.toLowerCase();
      final validExt = (ext == 'png' || ext == 'webp') ? ext : 'jpg';

      await ref.read(userProfileProvider.notifier).uploadProfileImageBytes(bytes, validExt);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text(
              'Profile picture updated successfully!',
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
              'Failed to upload image: $e',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);

    // 1. State Checking: Show AppLoadingScreen while loading profile
    if (!profile.isLoaded) {
      return const AppLoadingScreen(message: 'Loading profile settings...');
    }

    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    final currentUser = FirebaseAuth.instance.currentUser;
    final displayPhotoUrl = (profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty)
        ? profile.profileImageUrl
        : currentUser?.photoURL;
    final bool hasProfileImage = displayPhotoUrl != null && displayPhotoUrl.isNotEmpty;

    final bool isEmailReadOnly = _signUpMethod == 'email';
    final bool isPhoneReadOnly = _signUpMethod == 'phone';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Personal Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          // TASK 4: Clean history icon in AppBar for university students to access previous admission data
          if (profile.isUniversityStudent)
            IconButton(
              icon: const Icon(Icons.history_rounded, color: accentColor, size: 22),
              tooltip: 'Access Previous Admission Data',
              onPressed: () {
                SafeHaptics.lightImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdmissionArchiveScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 22),
            tooltip: 'Sign Out',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: cardColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  content: const Text('Are you sure you want to sign out?', style: TextStyle(color: Colors.blueGrey)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(authServiceProvider).signOut();
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Avatar & Camera Button
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.4),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.2),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: cardColor,
                          backgroundImage: hasProfileImage
                              ? NetworkImage(displayPhotoUrl)
                              : null,
                          child: !hasProfileImage
                              ? (_isUploadingImage
                                  ? const AppPreloader(size: 26, strokeWidth: 2.5)
                                  : Icon(Icons.person_rounded, size: 48, color: Colors.blueGrey.shade400))
                              : (_isUploadingImage
                                  ? Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: AppPreloader(size: 26, strokeWidth: 2.5),
                                      ),
                                    )
                                  : null),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isUploadingImage ? null : _pickAndUploadProfileImage,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8C5D3E),
                              shape: BoxShape.circle,
                              border: Border.all(color: backgroundColor, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    profile.fullName.isNotEmpty
                        ? profile.fullName
                        : (_fullNameController.text.isNotEmpty ? _fullNameController.text : 'Candidate'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4A3830)),
                      ),
                      child: Text(
                        profile.profileSubtitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: const Color(0xFFF2B78A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live Stats Overview Row (Total Focus Time, Streak, Exams Logged)
                _buildProfileStatsRow(
                cardColor,
                accentColor,
                ref.watch(totalFocusMinutesProvider),
                ref.watch(currentStreakProvider),
                ref.watch(totalCompletedExamsCountProvider),
              ),
              const SizedBox(height: 20),

              // University Mode Toggle Switch Card
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF4A3830),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isUniversityStudent ? Icons.account_balance_rounded : Icons.school_rounded,
                          color: _isUniversityStudent ? accentColor : Colors.blueGrey.shade300,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Are you a University Student?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _isUniversityStudent ? 'University Mode Active' : 'HSC / Admission Mode Active',
                              style: TextStyle(
                                color: Colors.blueGrey.shade400,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: _isUniversityStudent,
                      activeColor: accentColor,
                      onChanged: (val) {
                        setState(() {
                          _isUniversityStudent = val;
                        });
                      },
                    ),
                  ],
                ),
              ),

              // 2. Personal Information Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20.0),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, color: accentColor, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Personal Information',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Full Name
                    _buildFieldLabel('Full Name', isRequired: false),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _fullNameController,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'Enter your full name',
                        prefixIcon: Icons.badge_outlined,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),

                    // Nickname*
                    _buildFieldLabel('Nickname', isRequired: true),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nicknameController,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., Sayem',
                        prefixIcon: Icons.face_outlined,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Nickname is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Username*
                    _buildFieldLabel('Username', isRequired: true),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _usernameController,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., sayem_25',
                        prefixIcon: Icons.alternate_email_rounded,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Email*
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildFieldLabel('Email Address', isRequired: true),
                        if (isEmailReadOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 10, color: Colors.grey),
                                SizedBox(width: 4),
                                Text(
                                  'Primary Signup (Locked)',
                                  style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      readOnly: isEmailReadOnly,
                      style: GoogleFonts.plusJakartaSans(
                        color: isEmailReadOnly ? const Color(0xFF786B63) : Colors.white,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        hintText: 'Email address',
                        prefixIcon: Icons.email_outlined,
                        isReadOnly: isEmailReadOnly,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty || !value.contains('@')) {
                          return 'Valid email is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Phone Number
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildFieldLabel('Phone Number', isRequired: false),
                        if (isPhoneReadOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline_rounded, size: 10, color: Color(0xFF786B63)),
                                const SizedBox(width: 4),
                                Text(
                                  'Primary Signup (Locked)',
                                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF786B63), fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _phoneController,
                      readOnly: isPhoneReadOnly,
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.plusJakartaSans(
                        color: isPhoneReadOnly ? const Color(0xFF786B63) : Colors.white,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        hintText: '+8801XXXXXXXXX',
                        prefixIcon: Icons.phone_android_outlined,
                        isReadOnly: isPhoneReadOnly,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Conditional Fields: University vs HSC
                    if (_isUniversityStudent) ...[
                      // University Name
                      _buildFieldLabel('University Name', isRequired: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _universityController,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'e.g., BUET, DU, CUET, RUET',
                          prefixIcon: Icons.account_balance_rounded,
                        ),
                        validator: (value) {
                          if (_isUniversityStudent && (value == null || value.trim().isEmpty)) {
                            return 'University name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Major / Department
                      _buildFieldLabel('Major / Department', isRequired: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _majorController,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'e.g., EEE, CSE, Mechanical',
                          prefixIcon: Icons.domain_rounded,
                        ),
                        validator: (value) {
                          if (_isUniversityStudent && (value == null || value.trim().isEmpty)) {
                            return 'Major / Department is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Level & Term Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Level', isRequired: true),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedLevel,
                                  dropdownColor: cardColor,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Level',
                                    prefixIcon: Icons.layers_rounded,
                                  ),
                                  items: ['1', '2', '3', '4']
                                      .map((l) => DropdownMenuItem(value: l, child: Text('Level $l')))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedLevel = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Term', isRequired: true),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedTerm,
                                  dropdownColor: cardColor,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Term',
                                    prefixIcon: Icons.timelapse_rounded,
                                  ),
                                  items: ['1', '2']
                                      .map((t) => DropdownMenuItem(value: t, child: Text('Term $t')))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _selectedTerm = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Semester Lifecycle & Archived Terms Section
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                        ),
                        child: Column(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.inventory_2_rounded, color: accentColor, size: 20),
                                ),
                                title: const Text('Archived Semesters', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                                subtitle: const Text('View past courses, routines & scoped PDF reports', style: TextStyle(color: Colors.blueGrey, fontSize: 11.5)),
                                trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.blueGrey, size: 14),
                                onTap: () {
                                  SafeHaptics.lightImpact();
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedTermsScreen()));
                                },
                              ),
                            ),
                            const Divider(color: Colors.white10, height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFF59E0B), width: 1.2),
                                  foregroundColor: const Color(0xFFF59E0B),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _showArchiveTermModal(context, profile),
                                icon: const Icon(Icons.archive_rounded, size: 16),
                                label: const Text('Archive Current Term', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // College*
                      _buildFieldLabel('College / Institution', isRequired: true),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _collegeController,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'Enter college name',
                          prefixIcon: Icons.account_balance_outlined,
                        ),
                        validator: (value) {
                          if (!_isUniversityStudent && (value == null || value.trim().isEmpty)) {
                            return 'College name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // HSC Batch* & Group* Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('HSC Batch', isRequired: true),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _hscBatch,
                                  dropdownColor: cardColor,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Batch',
                                    prefixIcon: Icons.calendar_today_outlined,
                                  ),
                                  items: _batchOptions
                                      .map((b) => DropdownMenuItem(value: b, child: Text('HSC $b')))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _hscBatch = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('HSC Group / Division', isRequired: true),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _hscGroup,
                                  dropdownColor: cardColor,
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Group',
                                    prefixIcon: Icons.category_outlined,
                                  ),
                                  items: _groupOptions
                                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _hscGroup = val;
                                        final available = GroupConstants.getTargetsForGroup(val);
                                        if (!available.contains(_primaryTarget)) {
                                          _primaryTarget = available.first;
                                        }
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Home District
                    _buildFieldLabel('Home District', isRequired: false),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _districtController,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., Dhaka, Chattogram',
                        prefixIcon: Icons.location_on_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Admission Targets Section (Dynamic Dropdowns with "None" option)
              if (!_isUniversityStudent) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.track_changes_rounded, color: accentColor, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Admission Target Goals',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Primary Admission Target Goal*
                      _buildFieldLabel('Admission Target Goal', isRequired: true),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _primaryTarget,
                        dropdownColor: cardColor,
                        isExpanded: true,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hintText: 'Select primary target',
                          prefixIcon: Icons.stars_rounded,
                        ),
                        items: _allTargetOptions
                            .map((opt) => DropdownMenuItem(
                                  value: opt,
                                  child: Text(
                                    opt,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: _onPrimaryTargetChanged,
                      ),
                      const SizedBox(height: 14),

                      // 2nd Admission Target Goal (Optional Dynamic Dropdown with "None")
                      _buildFieldLabel('2nd Admission Target Goal', isRequired: false),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _secondaryTargetOptions.contains(_secondaryTarget) ? _secondaryTarget : 'None',
                        dropdownColor: cardColor,
                        isExpanded: true,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hintText: 'Select secondary target',
                          prefixIcon: Icons.flag_outlined,
                        ),
                        items: _secondaryTargetOptions
                            .map((opt) => DropdownMenuItem(
                                  value: opt,
                                  child: Text(
                                    opt,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          setState(() => _secondaryTarget = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 4. Save Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSavingProfile ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF110D0C),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                    shadowColor: accentColor.withValues(alpha: 0.4),
                  ),
                  child: _isSavingProfile
                      ? const AppPreloader(
                          size: 20,
                          strokeWidth: 2,
                          color: Color(0xFF110D0C),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Save Profile',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // 5. Help & Support Tile
              Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HelpScreen()),
                    );
                  },
                  splashColor: accentColor.withValues(alpha: 0.15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.help_outline_rounded, color: accentColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Help & Support',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Contact support & launch AI tutors',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),

              // Feature Tours Replay Card
              _buildFeatureToursCard(cardColor, accentColor),

              // About the Developer Section
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.code_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'About the Developer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFABA093),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                                children: [
                                  const TextSpan(text: 'Crafted by '),
                                  TextSpan(
                                    text: 'Shahriyer Sayem',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: const Color(0xFFF2B78A),
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                      decorationColor: const Color(0xFFF2B78A).withValues(alpha: 0.6),
                                    ),
                                    recognizer: _developerTapRecognizer
                                      ..onTap = () async {
                                        final Uri url = Uri.parse('https://being-utso.github.io/');
                                        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                                          await launchUrl(url, mode: LaunchMode.platformDefault);
                                        }
                                      },
                                  ),
                                  const TextSpan(
                                    text:
                                        ' — a distraction-free academic workspace built for university undergraduates, college, and admission students.',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Task 2: Support the Project / Donate Section
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.favorite_rounded, color: Color(0xFFF59E0B), size: 16),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Support the Project / Donate',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Support continuous app updates, study tools, and server maintenance:',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _safeLaunchUrl(context, 'https://being-utso.github.io/contact.html'),
                            icon: const Icon(Icons.coffee_rounded, size: 15, color: Colors.black87),
                            label: const Text(
                              'Buy Me a Coffee',
                              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFDD00),
                              foregroundColor: Colors.black87,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _safeLaunchUrl(context, 'https://github.com/being-utso'),
                            icon: const Icon(Icons.code_rounded, size: 15, color: Color(0xFFF2B78A)),
                            label: const Text(
                              'GitHub',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                              backgroundColor: const Color(0xFFF2B78A).withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _safeLaunchUrl(context, AppConstants.privacyPolicyUrl),
                            icon: const Icon(Icons.policy_rounded, size: 15, color: Colors.blueGrey),
                            label: const Text(
                              'Privacy Policy',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.4)),
                              backgroundColor: Colors.blueGrey.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Task 3: Export Academic Progress Report PDF Button
              Padding(
                padding: const EdgeInsets.only(top: 24.0),
                child: InkWell(
                  onTap: () => _exportPdfReport(context, ref),
                  borderRadius: BorderRadius.circular(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF2B78A), size: 20),
                        SizedBox(width: 10),
                        Text(
                          'Export Academic Progress Report (PDF)',
                          style: TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Clean Duplicate Sessions Utility Button
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: InkWell(
                  onTap: () async {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid == null) return;

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Clean Duplicate Sessions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text(
                          'This will inspect all your study and focus sessions, merge multi-device duplicates, and preserve all your completed study time and notes. Proceed?',
                          style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Clean Now', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      if (!mounted) return;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Cleaning duplicate sessions across cloud records...'),
                          duration: Duration(seconds: 2),
                        ),
                      );

                      final removedCount = await purgeHistoricalSessionDuplicates(uid);

                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              removedCount > 0
                                  ? 'Cleaned up $removedCount duplicate session records successfully!'
                                  : 'No duplicate sessions found. All records are clean!',
                            ),
                            backgroundColor: removedCount > 0 ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                          ),
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.35)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cleaning_services_rounded, color: Color(0xFF60A5FA), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Clean Duplicate Sessions',
                          style: TextStyle(
                            color: Color(0xFF60A5FA),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Sign Out Button
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: InkWell(
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: cardColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        content: Text('Are you sure you want to sign out of your account?', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13.5)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await ref.read(authServiceProvider).signOut();
                      if (mounted) {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Task 1: Delete Account Button (Google Play Data Privacy Compliance)
              Padding(
                padding: const EdgeInsets.only(top: 14.0),
                child: InkWell(
                  onTap: () => _handleDeleteAccount(context, ref, profile),
                  borderRadius: BorderRadius.circular(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Delete Account & Data',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildDeletionWarningPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context, WidgetRef ref, UserProfile profile) async {
    SafeHaptics.heavyImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            SizedBox(width: 10),
            Text(
              'Delete Account?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action is permanent and cannot be undone. All your data will be wiped immediately:',
              style: TextStyle(color: Colors.blueGrey, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _buildDeletionWarningPoint('All focus sessions, study stats & streak'),
            _buildDeletionWarningPoint('All mock exam records & merit rankings'),
            _buildDeletionWarningPoint('Syllabus checklists & chapter progress'),
            _buildDeletionWarningPoint('Profile photo & personal account info'),
            const SizedBox(height: 14),
            Text(
              'Are you sure you want to permanently delete your account?',
              style: TextStyle(color: Colors.red.shade300, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    bool localLoading = true;
    bool dialogShown = false;

    // 1. Show Loading Dialog/Spinner
    CompactLoadingDialog.show(
      context: context,
      message: 'Deleting account and wiping data...',
      indicatorColor: const Color(0xFFEF4444),
    );
    dialogShown = true;

    try {
      print('--- DEBUG: ATTEMPTING ACCOUNT DELETION ---');
      debugPrint('[DELETE ACCOUNT] Starting account deletion...');
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid;
      debugPrint('[DELETE ACCOUNT] User UID: $uid');

      // 2. Delete Firestore data and storage assets
      if (profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty) {
        try {
          final storageRef = FirebaseStorage.instance.refFromURL(profile.profileImageUrl!);
          await storageRef.delete();
        } catch (_) {}
      }
      if (uid != null) {
        try {
          final listResult = await FirebaseStorage.instance.ref().child('users/$uid').listAll();
          for (final item in listResult.items) {
            await item.delete();
          }
        } catch (_) {}
      }

      if (uid != null) {
        final firestore = FirebaseFirestore.instance;
        final userDocRef = firestore.collection('users').doc(uid);

        for (final subcol in ['focus_sessions', 'exams', 'syllabus', 'syllabus_state']) {
          try {
            final snap = await userDocRef.collection(subcol).get();
            if (snap.docs.isNotEmpty) {
              final batch = firestore.batch();
              for (final doc in snap.docs) {
                batch.delete(doc.reference);
              }
              await batch.commit();
            }
          } catch (_) {}
        }

        try {
          await userDocRef.delete();
        } catch (_) {}
      }

      // 3. Delete Firebase Auth user
      await FirebaseAuth.instance.currentUser?.delete();

      // Reset in-memory state
      ref.read(userProfileProvider.notifier).resetProfile();
      ref.read(navigationIndexProvider.notifier).state = 0;

      // 4. Route to Login Screen
      if (mounted) {
        if (dialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
          dialogShown = false;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            content: Text('Your account and all associated data have been deleted.'),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      print('DEBUG: FIREBASE AUTH ERROR CODE: ${e.code}');
      print('Firebase Auth Error: ${e.code}');
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (e.code == 'requires-recent-login') {
        // Show specific dialog: "Please sign out and sign back in to delete your account."
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF241C1A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: Color(0xFFEF4444), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Re-Authentication Required',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: const Text(
                'Please sign out and sign back in to verify your identity before deleting your account.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF2B78A),
                    foregroundColor: const Color(0xFF110D0C),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(authServiceProvider).signOut();
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                        (route) => false,
                      );
                    }
                  },
                  child: const Text('Sign Out Now', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              content: Text('Deletion failed: ${e.message ?? e.code}'),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: GENERAL DELETION ERROR: $e');
      print('General Error: $e');
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            content: Text('An unexpected error occurred: $e'),
          ),
        );
      }
    } finally {
      // THIS MUST RUN. Dismiss the loading dialog or set isLoading = false.
      localLoading = false;
      if (dialogShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
    }
  }

  void _showRecentLoginReauthDialog(BuildContext context, WidgetRef ref, UserProfile profile) {
    final passwordController = TextEditingController();
    final isGoogleUser = ref.read(authServiceProvider).currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;

    showDialog(
      context: context,
      builder: (reauthCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          String? errorMessage;

          return AlertDialog(
            backgroundColor: const Color(0xFF241C1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: Color(0xFFF2B78A), size: 22),
                SizedBox(width: 10),
                Text(
                  'Verify Your Identity',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'For your security, Firebase requires a fresh sign-in before deleting your account.',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                if (isGoogleUser) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(authServiceProvider).reauthenticateWithGoogle();
                        if (reauthCtx.mounted) Navigator.pop(reauthCtx);
                        if (context.mounted) {
                          _handleDeleteAccount(context, ref, profile);
                        }
                      } catch (err) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFFEF4444),
                              content: Text('Re-authentication failed: $err'),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.g_mobiledata_rounded, size: 24),
                    label: const Text('Re-authenticate with Google', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF110D0C),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Enter your account password',
                      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF786B63), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF241C1A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(reauthCtx),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
              ),
              if (!isGoogleUser)
                ElevatedButton(
                  onPressed: () async {
                    final pass = passwordController.text.trim();
                    if (pass.isEmpty) return;
                    try {
                      await ref.read(authServiceProvider).reauthenticateWithPassword(pass);
                      if (reauthCtx.mounted) Navigator.pop(reauthCtx);
                      if (context.mounted) {
                        _handleDeleteAccount(context, ref, profile);
                      }
                    } catch (e) {
                      setState(() {
                        errorMessage = 'Incorrect password or authentication error.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF2B78A), foregroundColor: const Color(0xFF110D0C)),
                  child: Text('Confirm & Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Helper widget to build field labels with required (*) indicators
  Widget _buildFieldLabel(String label, {required bool isRequired}) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFABA093),
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFF2B78A),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  /// Live global stats overview row (Study Time, Streak, Exams Logged)
  Widget _buildProfileStatsRow(
    Color cardColor,
    Color accentColor,
    int totalFocusMinutes,
    int streak,
    int completedExamsCount,
  ) {
    final hours = (totalFocusMinutes / 60).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Study', '${hours}h', Icons.timer_outlined, accentColor),
          Container(width: 1, height: 30, color: const Color(0xFF4A3830)),
          _buildStatItem('Streak', '$streak Days', Icons.local_fire_department_rounded, const Color(0xFFF97316)),
          Container(width: 1, height: 30, color: const Color(0xFF4A3830)),
          _buildStatItem('Exams Logged', '$completedExamsCount', Icons.assignment_turned_in_outlined, const Color(0xFF34D399)),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFABA093),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showBkashNagadModal(BuildContext context) {
    const bkashNumber = AppConstants.donationBkashNumber;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.volunteer_activism_rounded, color: Color(0xFFEC4899), size: 22),
            SizedBox(width: 10),
            Text(
              'Donate via bKash',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send your support directly via Send Money (Personal):',
              style: TextStyle(color: Colors.blueGrey, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            _buildProfileDonationTile('bKash Personal', bkashNumber, const Color(0xFFD82A74), ctx),
            const SizedBox(height: 10),
            Text(
              'Thank you so much for supporting Chondrobindu! ❤️',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDonationTile(String label, String number, Color color, BuildContext ctx) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                number,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, color: Color(0xFFF2B78A), size: 18),
            tooltip: 'Copy Number',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: number));
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                  content: Text('Copied $label number to clipboard!'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Helper method for unified input decoration
  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    bool isReadOnly = false,
  }) {
    const accentColor = Color(0xFFF2B78A);
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF786B63), fontSize: 13),
      filled: true,
      fillColor: isReadOnly ? const Color(0xFF191311) : const Color(0xFF241C1A),
      prefixIcon: Icon(prefixIcon, color: isReadOnly ? const Color(0xFF786B63) : accentColor, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? const Color(0xFF33241F) : const Color(0xFF4A3830),
          width: 0.8,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? const Color(0xFF33241F) : const Color(0xFF4A3830),
          width: 0.8,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? const Color(0xFF33241F) : accentColor,
          width: 1.2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
    );
  }

  /// Task 3: Export Academic Progress Report PDF
  Future<void> _exportPdfReport(BuildContext context, WidgetRef ref) async {
    await PdfReportService.handleExportPdfAction(context, ref);
  }

  /// Task 1: Level-Term Archiving Modal Dialog
  Future<void> _showArchiveTermModal(BuildContext context, UserProfile profile) async {
    final defaultTermName = 'Level ${profile.level ?? _selectedLevel} Term ${profile.term ?? _selectedTerm}';
    final nameCtrl = TextEditingController(text: defaultTermName);
    bool isArchiving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.archive_rounded, color: Color(0xFFF59E0B), size: 22),
                        SizedBox(width: 10),
                        Text(
                          'Archive Current Term',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.blueGrey, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This will package all current courses, assessments, routine, and attendance records into Archived Semesters, and reset your active dashboard for the next term.',
                          style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'SEMESTER / TERM NAME',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Level 1 Term 1, Spring 2026',
                    hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF786B63), fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF241C1A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: const Color(0xFF110D0C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isArchiving
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) return;

                            setModalState(() => isArchiving = true);

                            try {
                              await ArchiveService.archiveCurrentTerm(
                                termName: name,
                                userProfile: profile,
                              );

                              if (context.mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFF10B981),
                                    content: Text('Successfully archived "$name" and reset dashboard!'),
                                  ),
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ArchivedTermsScreen()),
                                );
                              }
                            } catch (e) {
                              setModalState(() => isArchiving = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: const Color(0xFFEF4444),
                                    content: Text('Failed to archive term: $e'),
                                  ),
                                );
                              }
                            }
                          },
                    icon: isArchiving
                        ? const AppPreloader(
                            size: 18,
                            strokeWidth: 2,
                            color: Color(0xFF110D0C),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      isArchiving ? 'Archiving Term...' : 'Confirm & Archive Term',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeatureToursCard(Color cardColor, Color accentColor) {
    final tourItems = [
      (
        section: TourSection.syllabus,
        title: 'Course Syllabus',
        subtitle: 'PDF syllabus import, progress tallies & chapter actions',
        icon: Icons.menu_book_rounded,
      ),
      (
        section: TourSection.planner,
        title: 'Academic Planner',
        subtitle: 'Exam calendar, assessments & class attendance',
        icon: Icons.calendar_month_rounded,
      ),
      (
        section: TourSection.timer,
        title: 'Focus Timer',
        subtitle: 'Study timer dial, interactive modes & stopwatch',
        icon: Icons.timer_rounded,
      ),
      (
        section: TourSection.timeline,
        title: 'Study Timeline',
        subtitle: 'Chronological session log & unlogged gap tracking',
        icon: Icons.timeline_rounded,
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 14.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.explore_rounded, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feature Tours',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Replay interactive guided walkthroughs',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              TextButton(
                onPressed: () async {
                  SafeHaptics.lightImpact();
                  await TourService().resetAllTours();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'All onboarding tours have been reset and will display on next visit.',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: const Color(0xFF241C1A),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                      ),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  'Reset All',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          ...tourItems.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, color: Colors.blueGrey.shade300, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: TextStyle(
                            color: Colors.blueGrey.shade400,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      SafeHaptics.lightImpact();
                      await TourService().resetTour(item.section);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${item.title} tour reset. It will replay when you open the screen.',
                              style: const TextStyle(color: Colors.white),
                            ),
                            backgroundColor: const Color(0xFF241C1A),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.replay_rounded, color: accentColor, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'Replay',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
