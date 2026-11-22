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
import '../core/theme/app_colors.dart';
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
import '../services/soundscape_service.dart';
import '../services/tour_service.dart';
import 'admission_archive_screen.dart';
import 'archived_terms_screen.dart';
import 'auth_screen.dart';
import 'help_screen.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_preloader.dart';
import '../widgets/compact_loading_dialog.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// 3 Core Academic Pathways supported by Chondrobindu
enum AcademicTrack {
  university('University', Icons.account_balance_rounded),
  college('College / HSC', Icons.school_rounded),
  admission('Admission Prep', Icons.stars_rounded);

  final String label;
  final IconData icon;
  const AcademicTrack(this.label, this.icon);
}

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

  // Academic Track Selection
  AcademicTrack _selectedTrack = AcademicTrack.university;
  late final TextEditingController _universityController;
  late final TextEditingController _majorController;
  late final TextEditingController _targetCgpaController;
  DateTime? _termStartDate;
  String _selectedLevel = '1';
  String _selectedTerm = '1';
  double _dailyFocusGoal = 1.0;

  // Ambient Audio & Soundscape State
  String _selectedSoundscape = 'Rainfall';
  double _ambientVolume = 0.65;
  bool _isPreviewPlaying = false;

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

  User? get _currentUser {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _developerTapRecognizer = TapGestureRecognizer()
      ..onTap = () {
        _safeLaunchUrl(context, 'https://being-utso.github.io/');
      };

    final profile = ref.read(userProfileProvider);
    final currentUser = _currentUser;
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

    if (profile.isUniversityStudent) {
      _selectedTrack = AcademicTrack.university;
    } else if (profile.primaryTarget == 'HSC Candidate / Board Exam') {
      _selectedTrack = AcademicTrack.college;
    } else {
      _selectedTrack = AcademicTrack.admission;
    }

    _universityController = TextEditingController(text: profile.universityName ?? '');
    _majorController = TextEditingController(text: profile.major ?? '');
    _targetCgpaController = TextEditingController(
      text: profile.targetGpa > 0 ? profile.targetGpa.toStringAsFixed(2) : '3.75',
    );
    _termStartDate = profile.termStartDate;
    _selectedLevel = (profile.level != null && ['1', '2', '3', '4'].contains(profile.level))
        ? profile.level!
        : '1';
    _selectedTerm = (profile.term != null && ['1', '2'].contains(profile.term))
        ? profile.term!
        : '1';
    _dailyFocusGoal = profile.dailyFocusGoalHours > 0 ? profile.dailyFocusGoalHours : 1.0;

    _ambientVolume = SoundscapeService.instance.volume;
    final currentSoundTrack = SoundscapeService.toLabel(SoundscapeService.instance.currentTrack);
    _selectedSoundscape = currentSoundTrack != 'None' ? currentSoundTrack : 'Rainfall';
    _isPreviewPlaying = SoundscapeService.instance.isPlaying;

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
    _targetCgpaController.dispose();
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

  Widget _buildAcademicTrackSelector(ChondrobinduThemeColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_rounded, color: colors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Academic Track',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select your primary academic pathway to personalize routines, metrics, and syllabus.',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              final items = AcademicTrack.values.map((track) {
                final isSelected = _selectedTrack == track;
                final itemWidget = InkWell(
                  onTap: () {
                    SafeHaptics.selectionClick();
                    setState(() {
                      _selectedTrack = track;
                      if (track == AcademicTrack.college) {
                        _primaryTarget = 'HSC Candidate / Board Exam';
                      } else if (track == AcademicTrack.admission) {
                        if (_primaryTarget == 'HSC Candidate / Board Exam' || _primaryTarget == 'University Studies') {
                          _primaryTarget = 'Engineering (BUET, CKRUET)';
                        }
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? colors.primary.withValues(alpha: 0.15) : colors.recessed,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? colors.primary : colors.surfaceBorder,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          track.icon,
                          size: 15,
                          color: isSelected ? colors.primary : colors.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            track.label,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: GoogleFonts.plusJakartaSans(
                              color: isSelected ? colors.textPrimary : colors.textMuted,
                              fontSize: 12.0,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

                if (isNarrow) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: itemWidget,
                  );
                } else {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0),
                      child: itemWidget,
                    ),
                  );
                }
              }).toList();

              return isNarrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items)
                  : Row(children: items);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientAudioPreferencesCard(ChondrobinduThemeColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, color: colors.secondary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Ambient Audio & Soundscapes',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: _isPreviewPlaying ? 'Stop Audio' : 'Preview Soundscape',
                icon: Icon(
                  _isPreviewPlaying ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
                  color: _isPreviewPlaying ? const Color(0xFFEF4444) : colors.secondary,
                  size: 24,
                ),
                onPressed: () async {
                  SafeHaptics.selectionClick();
                  if (_isPreviewPlaying) {
                    await SoundscapeService.instance.stop();
                    setState(() => _isPreviewPlaying = false);
                  } else {
                    final track = SoundscapeService.fromLabel(_selectedSoundscape);
                    if (track != SoundscapeTrack.none) {
                      await SoundscapeService.instance.play(track);
                      setState(() => _isPreviewPlaying = true);
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Background acoustic masking for focus timer sessions and deep work.',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Rainfall', 'Heavy Rain', 'Brown Noise', 'Cafe Ambiance', 'Forest Birds', 'None'].map((label) {
              final isSelected = _selectedSoundscape == label;
              return InkWell(
                onTap: () async {
                  SafeHaptics.selectionClick();
                  setState(() => _selectedSoundscape = label);
                  if (_isPreviewPlaying) {
                    final track = SoundscapeService.fromLabel(label);
                    if (track == SoundscapeTrack.none) {
                      await SoundscapeService.instance.stop();
                      setState(() => _isPreviewPlaying = false);
                    } else {
                      await SoundscapeService.instance.play(track);
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? colors.secondary : colors.recessed,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? colors.secondary : colors.surfaceBorder,
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      color: isSelected ? const Color(0xFF171C24) : colors.textPrimary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.volume_down_rounded, color: colors.textMuted, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: colors.secondary,
                    inactiveTrackColor: colors.surfaceBorder,
                    thumbColor: colors.secondary,
                    overlayColor: colors.secondary.withValues(alpha: 0.2),
                    trackHeight: 3.5,
                  ),
                  child: Slider(
                    value: _ambientVolume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (val) {
                      setState(() => _ambientVolume = val);
                      SoundscapeService.instance.setVolume(val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(_ambientVolume * 100).round()}%',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTermStartDate(BuildContext context) async {
    SafeHaptics.lightImpact();
    final colors = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = _termStartDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: colors.primary,
                    onPrimary: colors.background,
                    surface: colors.surface,
                    onSurface: colors.textPrimary,
                  )
                : ColorScheme.light(
                    primary: colors.primary,
                    onPrimary: Colors.white,
                    surface: colors.surface,
                    onSurface: colors.textPrimary,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _termStartDate = picked);
    }
  }

  bool _isSavingProfile = false;

 Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSavingProfile = true);

    try {
      final isUni = _selectedTrack == AcademicTrack.university;
      final double parsedTargetCgpa = (double.tryParse(_targetCgpaController.text.trim()) ?? 3.75).clamp(0.0, 4.0);
      final String primaryTargetToSave = isUni
          ? 'University Studies'
          : (_selectedTrack == AcademicTrack.college ? 'HSC Candidate / Board Exam' : _primaryTarget);

      final uid = _currentUser?.uid;
      
      // 1. WRITE SYLLABUS TO FIRESTORE FIRST (Only for non-university college/admission candidates)
      if (uid != null && !isUni) {
        final newSyllabus = SyllabusFactory.generateInitialSyllabus(primaryTargetToSave, _hscGroup);
        final firestore = FirebaseFirestore.instance;
        final subjectsData = newSyllabus.map((s) => s.toMap()).toList();
        
        await firestore
            .collection('users')
            .doc(uid)
            .collection('syllabus_state')
            .doc('active_syllabus')
            .set({
          'target': primaryTargetToSave,
          'subjects': subjectsData,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        ref.invalidate(syllabusProvider);
        ref.read(admissionTargetProvider.notifier).state = primaryTargetToSave;
        ref.read(syllabusProvider.notifier).setSubjects(newSyllabus);
      }

      // 2. NOW UPDATE PROFILE
      await ref.read(userProfileProvider.notifier).updateProfile(
        fullName: _fullNameController.text.trim(),
        nickname: _nicknameController.text.trim(),
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        college: isUni
            ? (_universityController.text.trim().isNotEmpty ? _universityController.text.trim() : 'University')
            : _collegeController.text.trim(),
        district: _districtController.text.trim(),
        hscBatch: isUni ? 'Varsity' : _hscBatch,
        hscGroup: isUni ? 'Science' : _hscGroup,
        primaryTarget: primaryTargetToSave,
        secondaryTarget: isUni ? 'None' : (_secondaryTarget ?? 'None'),
        isUniversityStudent: isUni,
        institutionType: isUni ? InstitutionType.university : InstitutionType.college,
        universityName: isUni ? _universityController.text.trim() : null,
        major: isUni ? _majorController.text.trim() : null,
        level: isUni ? _selectedLevel : null,
        term: isUni ? _selectedTerm : null,
        targetGpa: isUni ? parsedTargetCgpa : 5.00,
        termStartDate: isUni ? _termStartDate : null,
        clearTermStartDate: !isUni || _termStartDate == null,
        dailyFocusGoalHours: _dailyFocusGoal,
      );

      // 3. UPDATE FOCUS GOAL & PROVIDERS
      await ref.read(userProfileProvider.notifier).updateDailyFocusGoal(_dailyFocusGoal);

      if (mounted) {
        final colors = AppColors.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: colors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            content: Text(
              'Profile updated!',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
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

    final colors = AppColors.of(context);
    final backgroundColor = colors.background;
    final cardColor = colors.surface;
    final accentColor = colors.secondary;
    final currentUser = _currentUser;
    final displayPhotoUrl = (profile.profileImageUrl != null && profile.profileImageUrl!.isNotEmpty)
        ? profile.profileImageUrl
        : currentUser?.photoURL;
    final bool hasProfileImage = displayPhotoUrl != null && displayPhotoUrl.isNotEmpty;

    final bool isEmailReadOnly = _signUpMethod == 'email';
    final bool isPhoneReadOnly = _signUpMethod == 'phone';

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Personal Profile',
          style: GoogleFonts.plusJakartaSans(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          // TASK 4: Clean history icon in AppBar for university students to access previous admission data
          if (profile.isUniversityStudent)
            IconButton(
              icon: Icon(Icons.history_rounded, color: accentColor, size: 22),
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
                  backgroundColor: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: colors.surfaceBorder),
                  ),
                  title: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                  content: Text('Are you sure you want to sign out?', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await ref.read(authServiceProvider).signOut();
                if (!context.mounted) return;
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                                      : Icon(Icons.person_rounded, size: 48, color: colors.textMuted))
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
                                  color: colors.secondary,
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
                                  color: Color(0xFF171C24),
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
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
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
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Text(
                        profile.profileSubtitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.secondary,
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
                colors: colors,
              ),
              const SizedBox(height: 20),

              // Academic Track Selector (University / College / Admission)
              _buildAcademicTrackSelector(colors),

              // Ambient Audio & Soundscape Preferences Card
              _buildAmbientAudioPreferencesCard(colors),

              // Daily Focus Goal Setting Card
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.surfaceBorder,
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.track_changes_rounded, color: colors.secondary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Daily Focus Goal',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textPrimary,
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${_dailyFocusGoal.toStringAsFixed(1)}h / day',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.secondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Target focus time benchmarked in Insights charts and daily focus distribution.',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [1.0, 1.5, 2.0, 3.0, 4.0, 6.0].map((goal) {
                        final isSelected = (_dailyFocusGoal - goal).abs() < 0.05;
                        return InkWell(
                          onTap: () {
                            SafeHaptics.selectionClick();
                            setState(() => _dailyFocusGoal = goal);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected ? colors.secondary : colors.recessed,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected ? colors.secondary : colors.surfaceBorder,
                              ),
                            ),
                            child: Text(
                              '${goal.toStringAsFixed(goal.truncateToDouble() == goal ? 0 : 1)}h',
                              style: GoogleFonts.jetBrainsMono(
                                color: isSelected ? const Color(0xFF171C24) : colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
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
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.person_outline_rounded, color: accentColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Personal Information',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textPrimary,
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
                    _buildFieldLabel('Full Name', isRequired: false, colors: colors),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _fullNameController,
                      style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'Enter your full name',
                        prefixIcon: Icons.badge_outlined,
                        colors: colors,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 14),

                    // Nickname*
                    _buildFieldLabel('Nickname', isRequired: true, colors: colors),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nicknameController,
                      style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., Sayem',
                        prefixIcon: Icons.face_outlined,
                        colors: colors,
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
                    _buildFieldLabel('Username', isRequired: true, colors: colors),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _usernameController,
                      style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., sayem_25',
                        prefixIcon: Icons.alternate_email_rounded,
                        colors: colors,
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
                        _buildFieldLabel('Email Address', isRequired: true, colors: colors),
                        if (isEmailReadOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 10, color: colors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Primary Signup (Locked)',
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
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
                        color: isEmailReadOnly ? colors.textMuted : colors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        hintText: 'Email address',
                        prefixIcon: Icons.email_outlined,
                        isReadOnly: isEmailReadOnly,
                        colors: colors,
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
                        _buildFieldLabel('Phone Number', isRequired: false, colors: colors),
                        if (isPhoneReadOnly)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 10, color: colors.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  'Primary Signup (Locked)',
                                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
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
                        color: isPhoneReadOnly ? colors.textMuted : colors.textPrimary,
                        fontSize: 14,
                      ),
                      decoration: _buildInputDecoration(
                        hintText: '+8801XXXXXXXXX',
                        prefixIcon: Icons.phone_android_outlined,
                        isReadOnly: isPhoneReadOnly,
                        colors: colors,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Conditional Fields: University vs HSC
                    if (_selectedTrack == AcademicTrack.university) ...[
                      // University Name
                      _buildFieldLabel('University Name', isRequired: true, colors: colors),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _universityController,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'e.g., BUET, DU, CUET, RUET',
                          prefixIcon: Icons.account_balance_rounded,
                          colors: colors,
                        ),
                        validator: (value) {
                          if (_selectedTrack == AcademicTrack.university && (value == null || value.trim().isEmpty)) {
                            return 'University name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Major / Department
                      _buildFieldLabel('Major / Department', isRequired: true, colors: colors),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _majorController,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'e.g., EEE, CSE, Mechanical',
                          prefixIcon: Icons.domain_rounded,
                          colors: colors,
                        ),
                        validator: (value) {
                          if (_selectedTrack == AcademicTrack.university && (value == null || value.trim().isEmpty)) {
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
                                _buildFieldLabel('Level', isRequired: true, colors: colors),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedLevel,
                                  dropdownColor: cardColor,
                                  isExpanded: true,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Level',
                                    prefixIcon: Icons.layers_rounded,
                                    colors: colors,
                                  ),
                                  items: ['1', '2', '3', '4']
                                      .map((l) => DropdownMenuItem(
                                            value: l,
                                            child: Text('Level $l', overflow: TextOverflow.ellipsis),
                                          ))
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
                                _buildFieldLabel('Term', isRequired: true, colors: colors),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedTerm,
                                  dropdownColor: cardColor,
                                  isExpanded: true,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Term',
                                    prefixIcon: Icons.timelapse_rounded,
                                    colors: colors,
                                  ),
                                  items: ['1', '2']
                                      .map((t) => DropdownMenuItem(
                                            value: t,
                                            child: Text('Term $t', overflow: TextOverflow.ellipsis),
                                          ))
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

                      // Target CGPA & Term Start Date Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildFieldLabel('Target CGPA', isRequired: true, colors: colors),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _targetCgpaController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  style: GoogleFonts.jetBrainsMono(color: colors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                  decoration: _buildInputDecoration(
                                    hintText: 'e.g. 3.75',
                                    prefixIcon: Icons.emoji_events_outlined,
                                    colors: colors,
                                  ),
                                  validator: (val) {
                                    if (val == null || val.trim().isEmpty) return 'Target CGPA is required';
                                    final n = double.tryParse(val.trim());
                                    if (n == null || n < 0.0 || n > 4.0) return 'Enter 0.00 - 4.00';
                                    return null;
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
                                _buildFieldLabel('Term Start Date', isRequired: false, colors: colors),
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _pickTermStartDate(context),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: colors.recessed,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: colors.surfaceBorder, width: 0.8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_month_outlined, color: colors.primary, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _termStartDate != null
                                                ? '${_termStartDate!.day}/${_termStartDate!.month}/${_termStartDate!.year}'
                                                : 'Set Start Date',
                                            style: GoogleFonts.jetBrainsMono(
                                              color: _termStartDate != null ? colors.textPrimary : colors.textMuted,
                                              fontSize: 13,
                                              fontWeight: _termStartDate != null ? FontWeight.w600 : FontWeight.normal,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (_termStartDate != null)
                                          GestureDetector(
                                            onTap: () => setState(() => _termStartDate = null),
                                            child: Icon(Icons.close_rounded, size: 16, color: colors.textMuted),
                                          ),
                                      ],
                                    ),
                                  ),
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
                          border: Border.all(color: colors.surfaceBorder, width: 0.8),
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
                                  child: Icon(Icons.inventory_2_rounded, color: accentColor, size: 20),
                                ),
                                title: Text('Archived Semesters', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                                subtitle: Text('View past courses, routines & scoped PDF reports', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5)),
                                trailing: Icon(Icons.arrow_forward_ios_rounded, color: colors.textMuted, size: 14),
                                onTap: () {
                                  SafeHaptics.lightImpact();
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedTermsScreen()));
                                },
                              ),
                            ),
                            Divider(color: colors.surfaceBorder, height: 16),
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
                                label: Text('Archive Current Term', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // College*
                      _buildFieldLabel('College / Institution', isRequired: true, colors: colors),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _collegeController,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: _buildInputDecoration(
                          hintText: 'Enter college name',
                          prefixIcon: Icons.account_balance_outlined,
                          colors: colors,
                        ),
                        validator: (value) {
                          if (_selectedTrack != AcademicTrack.university && (value == null || value.trim().isEmpty)) {
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
                                _buildFieldLabel('HSC Batch', isRequired: true, colors: colors),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _hscBatch,
                                  dropdownColor: cardColor,
                                  isExpanded: true,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Batch',
                                    prefixIcon: Icons.calendar_today_outlined,
                                    colors: colors,
                                  ),
                                  items: _batchOptions
                                      .map((b) => DropdownMenuItem(
                                            value: b,
                                            child: Text('HSC $b', overflow: TextOverflow.ellipsis),
                                          ))
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
                                _buildFieldLabel('HSC Group / Division', isRequired: true, colors: colors),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _hscGroup,
                                  dropdownColor: cardColor,
                                  isExpanded: true,
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                                  decoration: _buildInputDecoration(
                                    hintText: 'Group',
                                    prefixIcon: Icons.category_outlined,
                                    colors: colors,
                                  ),
                                  items: _groupOptions
                                      .map((g) => DropdownMenuItem(
                                            value: g,
                                            child: Text(g, overflow: TextOverflow.ellipsis),
                                          ))
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
                    _buildFieldLabel('Home District', isRequired: false, colors: colors),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _districtController,
                      style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'e.g., Dhaka, Chattogram',
                        prefixIcon: Icons.location_on_outlined,
                        colors: colors,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Admission Targets Section (Only for Admission Prep track)
              if (_selectedTrack == AcademicTrack.admission) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.stars_rounded, color: accentColor, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Admission Target Goals',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Primary Admission Target Goal*
                      _buildFieldLabel('Admission Target Goal', isRequired: true, colors: colors),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _primaryTarget,
                        dropdownColor: cardColor,
                        isExpanded: true,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hintText: 'Select primary target',
                          prefixIcon: Icons.stars_rounded,
                          colors: colors,
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
                      _buildFieldLabel('2nd Admission Target Goal', isRequired: false, colors: colors),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _secondaryTargetOptions.contains(_secondaryTarget) ? _secondaryTarget : 'None',
                        dropdownColor: cardColor,
                        isExpanded: true,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hintText: 'Select secondary target',
                          prefixIcon: Icons.flag_outlined,
                          colors: colors,
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
                    backgroundColor: colors.secondary,
                    foregroundColor: const Color(0xFF171C24),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                    shadowColor: colors.secondary.withValues(alpha: 0.4),
                  ),
                  child: _isSavingProfile
                      ? const AppPreloader(
                          size: 20,
                          strokeWidth: 2,
                          color: Color(0xFF171C24),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Save Profile',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF171C24),
                              ),
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
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.help_outline_rounded, color: accentColor, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Help & Support',
                                style: GoogleFonts.plusJakartaSans(
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Contact support & launch AI tutors',
                                style: GoogleFonts.plusJakartaSans(
                                  color: colors.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: colors.textMuted),
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
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.code_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'About the Developer',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textPrimary,
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 3),
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.plusJakartaSans(
                                  color: colors.textMuted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                                children: [
                                  const TextSpan(text: 'Crafted by '),
                                  TextSpan(
                                    text: 'Shahriyer Sayem',
                                    style: GoogleFonts.plusJakartaSans(
                                      color: colors.secondary,
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                      decorationColor: colors.secondary.withValues(alpha: 0.6),
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

              // Support the Project / Donate Section
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
                          Text(
                            'Support the Project / Donate',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Support continuous app updates, study tools, and server maintenance:',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _showBkashNagadModal(context),
                            icon: const Icon(Icons.volunteer_activism_rounded, size: 15, color: Colors.white),
                            label: const Text(
                              'Donate via bKash',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD82A74),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                          ),
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
                            icon: Icon(Icons.code_rounded, size: 15, color: colors.secondary),
                            label: Text(
                              'GitHub',
                              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.secondary.withValues(alpha: 0.4)),
                              backgroundColor: colors.secondary.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _safeLaunchUrl(context, AppConstants.privacyPolicyUrl),
                            icon: Icon(Icons.policy_rounded, size: 15, color: colors.textMuted),
                            label: Text(
                              'Privacy Policy',
                              style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.surfaceBorder),
                              backgroundColor: colors.recessed,
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
                      color: colors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: colors.secondary.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, color: colors.secondary, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          'Export Academic Progress Report (PDF)',
                          style: TextStyle(
                            color: colors.secondary,
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
                    final uid = _currentUser?.uid;
                    if (uid == null) return;

                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.surfaceBorder),
                        ),
                        title: Text('Clean Duplicate Sessions', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                        content: Text(
                          'This will inspect all your study and focus sessions, merge multi-device duplicates, and preserve all your completed study time and notes. Proceed?',
                          style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: colors.background,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Clean Now', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      if (!context.mounted) return;
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('Cleaning duplicate sessions across cloud records...'),
                          duration: Duration(seconds: 2),
                        ),
                      );

                      final removedCount = await purgeHistoricalSessionDuplicates(uid);

                      if (context.mounted) {
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: colors.surfaceBorder),
                        ),
                        title: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                        content: Text('Are you sure you want to sign out of your account?', style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13.5)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Sign Out', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      await ref.read(authServiceProvider).signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((route) => route.isFirst);
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFEF4444),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Delete Account Button
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Delete Account & Data',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFEF4444),
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
  ),
),
);
}

  Widget _buildDeletionWarningPoint(String text, ChondrobinduThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount(BuildContext context, WidgetRef ref, UserProfile profile) async {
    SafeHaptics.heavyImpact();
    final colors = AppColors.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 10),
            Text(
              'Delete Account?',
              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This action is permanent and cannot be undone. All your data will be wiped immediately:',
              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _buildDeletionWarningPoint('All focus sessions, study stats & streak', colors),
            _buildDeletionWarningPoint('All mock exam records & merit rankings', colors),
            _buildDeletionWarningPoint('Syllabus checklists & chapter progress', colors),
            _buildDeletionWarningPoint('Profile photo & personal account info', colors),
            const SizedBox(height: 14),
            Text(
              'Are you sure you want to permanently delete your account?',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete Permanently', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;

    bool dialogShown = false;

    // 1. Show Loading Dialog/Spinner
    CompactLoadingDialog.show(
      context: context,
      message: 'Deleting account and wiping data...',
      indicatorColor: const Color(0xFFEF4444),
    );
    dialogShown = true;

    try {
      debugPrint('--- DEBUG: ATTEMPTING ACCOUNT DELETION ---');
      debugPrint('[DELETE ACCOUNT] Starting account deletion...');
      final user = _currentUser;
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
      if (context.mounted) {
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
      debugPrint('DEBUG: FIREBASE AUTH ERROR CODE: ${e.code}');
      debugPrint('Firebase Auth Error: ${e.code}');
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }

      if (e.code == 'requires-recent-login') {
        if (context.mounted) {
          _showRecentLoginReauthDialog(context, ref, profile);
        }
      } else {
        if (context.mounted) {
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
      debugPrint('DEBUG: GENERAL DELETION ERROR: $e');
      debugPrint('General Error: $e');
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
      if (context.mounted) {
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
      if (dialogShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogShown = false;
      }
    }
  }

  void _showRecentLoginReauthDialog(BuildContext context, WidgetRef ref, UserProfile profile) {
    final colors = AppColors.of(context);
    final passwordController = TextEditingController();
    final isGoogleUser = ref.read(authServiceProvider).currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;

    showDialog(
      context: context,
      builder: (reauthCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            title: Row(
              children: [
                Icon(Icons.security_rounded, color: colors.secondary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Verify Your Identity',
                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'For your security, Firebase requires a fresh sign-in before deleting your account.',
                  style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
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
                      foregroundColor: const Color(0xFF171C24),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Enter your account password',
                      hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                      filled: true,
                      fillColor: colors.recessed,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.surfaceBorder, width: 0.8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.surfaceBorder, width: 0.8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.primary, width: 1.2),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(reauthCtx),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textMuted)),
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
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFFEF4444),
                            content: Text('Incorrect password or authentication error.'),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.secondary,
                    foregroundColor: const Color(0xFF171C24),
                  ),
                  child: Text('Confirm & Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Helper widget to build field labels with required (*) indicators
  Widget _buildFieldLabel(String label, {required bool isRequired, ChondrobinduThemeColors? colors}) {
    final effectiveColors = colors ?? AppColors.of(context);
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: effectiveColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isRequired) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: GoogleFonts.plusJakartaSans(
              color: effectiveColors.secondary,
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
    int completedExamsCount, {
    ChondrobinduThemeColors? colors,
  }) {
    final effectiveColors = colors ?? AppColors.of(context);
    final hours = (totalFocusMinutes / 60).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: effectiveColors.surfaceBorder, width: 0.8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Total Study', '${hours}h', Icons.timer_outlined, accentColor, colors: effectiveColors),
          Container(width: 1, height: 30, color: effectiveColors.surfaceBorder),
          _buildStatItem('Streak', '$streak Days', Icons.local_fire_department_rounded, effectiveColors.secondary, colors: effectiveColors),
          Container(width: 1, height: 30, color: effectiveColors.surfaceBorder),
          _buildStatItem('Exams Logged', '$completedExamsCount', Icons.assignment_turned_in_outlined, effectiveColors.success, colors: effectiveColors),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color, {ChondrobinduThemeColors? colors}) {
    final effectiveColors = colors ?? AppColors.of(context);
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
                color: effectiveColors.textPrimary,
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
            color: effectiveColors.textMuted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showBkashNagadModal(BuildContext context) {
    const bkashNumber = AppConstants.donationBkashNumber;
    final colors = AppColors.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.volunteer_activism_rounded, color: Color(0xFFEC4899), size: 22),
            const SizedBox(width: 10),
            Text(
              'Donate via bKash',
              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send your support directly via Send Money (Personal):',
              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            _buildProfileDonationTile('bKash Personal', bkashNumber, const Color(0xFFD82A74), ctx, colors: colors),
            const SizedBox(height: 10),
            Text(
              'Thank you so much for supporting Chondrobindu! ❤️',
              style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.secondary,
              foregroundColor: const Color(0xFF171C24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDonationTile(String label, String number, Color color, BuildContext ctx, {ChondrobinduThemeColors? colors}) {
    final effectiveColors = colors ?? AppColors.of(ctx);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: effectiveColors.recessed,
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
                style: TextStyle(color: effectiveColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.copy_rounded, color: effectiveColors.secondary, size: 18),
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
    ChondrobinduThemeColors? colors,
  }) {
    final effectiveColors = colors ?? AppColors.of(context);
    return InputDecoration(
      hintText: hintText,
      hintStyle: GoogleFonts.plusJakartaSans(color: effectiveColors.textMuted, fontSize: 13),
      filled: true,
      fillColor: isReadOnly ? effectiveColors.recessed.withValues(alpha: 0.5) : effectiveColors.recessed,
      prefixIcon: Icon(prefixIcon, color: isReadOnly ? effectiveColors.textMuted : effectiveColors.primary, size: 18),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? effectiveColors.surfaceBorder.withValues(alpha: 0.5) : effectiveColors.surfaceBorder,
          width: 0.8,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? effectiveColors.surfaceBorder.withValues(alpha: 0.5) : effectiveColors.surfaceBorder,
          width: 0.8,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isReadOnly ? effectiveColors.surfaceBorder : effectiveColors.primary,
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

    final colors = AppColors.of(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
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
                    Row(
                      children: [
                        Icon(Icons.archive_rounded, color: colors.secondary, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Archive Current Term',
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: colors.textMuted, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.secondary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: colors.secondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This will package all current courses, assessments, routine, and attendance records into Archived Semesters, and reset your active dashboard for the next term.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 12, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'SEMESTER / TERM NAME',
                  style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Level 1 Term 1, Spring 2026',
                    hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: colors.recessed,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.surfaceBorder, width: 0.8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.surfaceBorder, width: 0.8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.primary, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.secondary,
                      foregroundColor: const Color(0xFF171C24),
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
                            color: Color(0xFF171C24),
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
    final colors = AppColors.of(context);
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
        border: Border.all(color: colors.surfaceBorder),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Feature Tours',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Replay interactive guided walkthroughs',
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textMuted,
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
                        content: Text(
                          'All onboarding tours have been reset and will display on next visit.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary),
                        ),
                        backgroundColor: cardColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: colors.surfaceBorder),
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
                  style: GoogleFonts.plusJakartaSans(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 8),
          ...tourItems.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, color: colors.textMuted, size: 16),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textMuted,
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
                              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary),
                            ),
                            backgroundColor: cardColor,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: colors.surfaceBorder),
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
                            style: GoogleFonts.plusJakartaSans(
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
