import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/group_constants.dart';
import '../providers/profile_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_provider.dart';
import '../services/syllabus_factory.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_preloader.dart';
import 'main_nav.dart';

/// Onboarding / Profile Setup Screen synchronized with ProfileScreen fields and Firestore persistence.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _nicknameController;
  late TextEditingController _collegeController;
  late TextEditingController _districtController;

  String _selectedBatch = '2025';
  String _selectedGroup = 'Science';
  String _primaryTarget = 'Engineering (BUET, CKRUET)';
  String _secondaryTarget = 'None';

  bool _isSubmitting = false;

  bool _isUniversityStudent = false;
  late TextEditingController _universityController;
  late TextEditingController _majorController;
  String _selectedLevel = '1';
  String _selectedTerm = '1';
  String _nonUniRole = 'hsc'; // 'hsc' or 'admission'

  final List<String> _batchOptions = ['2024', '2025', '2026', '2027', '2028', '2029'];
  List<String> get _groupOptions => GroupConstants.hscGroups;
  List<String> get _targetOptions => GroupConstants.getTargetsForGroup(_selectedGroup);
  List<String> get _admissionTargetOptions => _targetOptions
      .where((opt) => !opt.toLowerCase().contains('hsc') && !opt.toLowerCase().contains('board'))
      .toList();

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    final currentUser = FirebaseAuth.instance.currentUser;
    final initialName = profile.fullName.isNotEmpty
        ? profile.fullName
        : (currentUser?.displayName ?? '');

    _nameController = TextEditingController(text: initialName);
    _nicknameController = TextEditingController(
      text: profile.nickname.isNotEmpty
          ? profile.nickname
          : (initialName.isNotEmpty ? initialName.split(' ').first : ''),
    );
    _collegeController = TextEditingController(text: profile.college);
    _districtController = TextEditingController(
      text: profile.district.isNotEmpty ? profile.district : 'Dhaka',
    );

    _isUniversityStudent = profile.isUniversityStudent;
    _universityController = TextEditingController(text: profile.universityName ?? '');
    _majorController = TextEditingController(text: profile.major ?? '');
    _selectedLevel = (profile.level != null && ['1', '2', '3', '4'].contains(profile.level))
        ? profile.level!
        : '1';
    _selectedTerm = (profile.term != null && ['1', '2'].contains(profile.term))
        ? profile.term!
        : '1';

    _selectedBatch = _batchOptions.contains(profile.hscBatch) ? profile.hscBatch : '2025';
    _selectedGroup = _groupOptions.contains(profile.hscGroup) ? profile.hscGroup : 'Science';

    final currentTarget = profile.primaryTarget;
    if (currentTarget.toLowerCase().contains('hsc') || currentTarget.toLowerCase().contains('board')) {
      _nonUniRole = 'hsc';
      _primaryTarget = 'HSC Candidate / Board Exam';
    } else if (currentTarget.isNotEmpty && currentTarget != 'University Studies') {
      _nonUniRole = 'admission';
      if (_admissionTargetOptions.contains(currentTarget)) {
        _primaryTarget = currentTarget;
      } else {
        _primaryTarget = _admissionTargetOptions.firstWhere(
          (opt) => opt.toLowerCase().contains(currentTarget.toLowerCase()),
          orElse: () => _admissionTargetOptions.isNotEmpty
              ? _admissionTargetOptions.first
              : 'Engineering (BUET, CKRUET)',
        );
      }
    } else {
      _nonUniRole = 'hsc';
      _primaryTarget = 'HSC Candidate / Board Exam';
    }

    _secondaryTarget = profile.secondaryTarget.isNotEmpty ? profile.secondaryTarget : 'None';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nicknameController.dispose();
    _collegeController.dispose();
    _districtController.dispose();
    _universityController.dispose();
    _majorController.dispose();
    super.dispose();
  }

  /// Dynamic list of secondary options excluding currently chosen primary target
  List<String> get _secondaryTargetOptions {
    final targets = _nonUniRole == 'admission' ? _admissionTargetOptions : _targetOptions;
    return [
      'None',
      ...targets.where((option) => option != _primaryTarget)
    ];
  }

  /// Return compulsory and group-specific syllabus subjects for HSC group
  List<String> getSubjectsForGroup(String group) {
    const compulsory = [
      'Bangla (1st & 2nd)',
      'English (1st & 2nd)',
      'ICT',
    ];
    final grp = group.trim().toLowerCase();
    if (grp.contains('com') || grp.contains('bus')) {
      return [
        ...compulsory,
        'Accounting (1st & 2nd)',
        'Business Org & Mgmt',
        'Finance & Banking',
        'Production Mgmt & Mkt',
      ];
    } else if (grp.contains('human') || grp.contains('arts')) {
      return [
        ...compulsory,
        'Civics & Good Governance',
        'Economics (1st & 2nd)',
        'Geography (1st & 2nd)',
        'History / Islamic History',
      ];
    } else {
      // Science
      return [
        ...compulsory,
        'Physics (1st & 2nd)',
        'Chemistry (1st & 2nd)',
        'Higher Math (1st & 2nd)',
        'Biology (1st & 2nd)',
      ];
    }
  }

  /// Generator function for dynamic syllabus preview badges based on selected target and group
  List<String> _getSyllabusPreviewSubjects(String target, [String group = 'Science']) {
    final lower = target.toLowerCase();
    if (lower.contains('hsc') || lower.contains('candidate') || lower.contains('board')) {
      return getSubjectsForGroup(group);
    } else if (lower.contains('engineering') || lower.contains('buet')) {
      return [
        'Higher Math (1st & 2nd)',
        'Physics (1st & 2nd)',
        'Chemistry (1st & 2nd)',
      ];
    } else if (lower.contains('medical') || lower.contains('mbbs')) {
      return [
        'Biology (Botany & Zoology)',
        'Chemistry (1st & 2nd)',
        'Physics (1st & 2nd)',
        'General Knowledge & English',
      ];
    } else if (lower.contains('versity "a"') || (lower.contains('versity') && lower.contains('a'))) {
      return [
        'Physics (1st & 2nd)',
        'Chemistry (1st & 2nd)',
        'Higher Math (1st & 2nd)',
        'Biology (Botany & Zoology)',
      ];
    } else if (lower.contains('versity "b"') || (lower.contains('versity') && lower.contains('b'))) {
      return [
        'Bangla (1st & 2nd)',
        'English Grammar & Vocabulary',
        'General Knowledge & Current Affairs',
      ];
    } else if (lower.contains('versity "c"') || (lower.contains('versity') && lower.contains('c'))) {
      return [
        'Accounting (1st & 2nd)',
        'Business Org & Management',
        'Bangla & English',
        'Finance / Marketing',
      ];
    } else if (lower.contains('iba')) {
      return [
        'Quantitative Math Aptitude',
        'English Vocabulary & Grammar',
        'Analytical Logic & Essay',
      ];
    } else {
      final grp = group.trim().toLowerCase();
      if (grp.contains('com')) {
        return ['Accounting & Finance', 'Business Management', 'Model Tests'];
      } else if (grp.contains('human')) {
        return ['Economics & Civics', 'General Knowledge', 'Model Tests'];
      }
      return ['Core Science Subjects', 'Model Test Series'];
    }
  }

Future<void> _completeOnboarding() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);

    final name = _nameController.text.trim();
    final nickname = _nicknameController.text.trim().isNotEmpty
        ? _nicknameController.text.trim()
        : (name.contains(' ') ? name.split(' ').first : name);
    final college = _collegeController.text.trim();
    final district = _districtController.text.trim();

    final existingProfile = ref.read(userProfileProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final resolvedPrimaryTarget = _isUniversityStudent
        ? 'University Studies'
        : (_nonUniRole == 'hsc' ? 'HSC Candidate / Board Exam' : _primaryTarget);
    final resolvedSecondaryTarget = (_isUniversityStudent || _nonUniRole == 'hsc')
        ? 'None'
        : _secondaryTarget;

    final updatedProfile = existingProfile.copyWith(
      fullName: name,
      nickname: nickname,
      college: _isUniversityStudent
          ? (_universityController.text.trim().isNotEmpty
              ? _universityController.text.trim()
              : 'University')
          : college,
      district: district,
      hscBatch: _isUniversityStudent ? 'Varsity' : _selectedBatch,
      hscGroup: _isUniversityStudent ? 'Science' : _selectedGroup,
      primaryTarget: resolvedPrimaryTarget,
      secondaryTarget: resolvedSecondaryTarget,
      isUniversityStudent: _isUniversityStudent,
      universityName: _isUniversityStudent ? _universityController.text.trim() : null,
      major: _isUniversityStudent ? _majorController.text.trim() : null,
      level: _isUniversityStudent ? _selectedLevel : null,
      term: _isUniversityStudent ? _selectedTerm : null,
      isOnboarded: true,
    );

    try {
      final newSyllabus = SyllabusFactory.generateSyllabus(resolvedPrimaryTarget, _selectedGroup);

      // 1. WRITE SYLLABUS TO FIRESTORE FIRST
      if (uid != null) {
        final firestore = FirebaseFirestore.instance;
        final subjectsData = newSyllabus.map((s) => s.toMap()).toList();
        
        await firestore
            .collection('users')
            .doc(uid)
            .collection('syllabus_state')
            .doc('active_syllabus')
            .set({
          'target': resolvedPrimaryTarget,
          'subjects': subjectsData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 2. NOW UPDATE PROFILE
      await ref.read(userProfileProvider.notifier).saveProfile(updatedProfile, uid: uid);

      // 3. UPDATE PROVIDERS
      ref.invalidate(syllabusProvider);
      ref.read(admissionTargetProvider.notifier).state = resolvedPrimaryTarget;
      ref.read(syllabusProvider.notifier).setSubjects(newSyllabus);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);
    const mutedTextColor = Color(0xFFABA093);

    final currentTargetForPreview = _nonUniRole == 'hsc' ? 'HSC Candidate / Board Exam' : _primaryTarget;
    final previewSubjects = _getSyllabusPreviewSubjects(currentTargetForPreview, _selectedGroup);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Logo & Title
                Row(
                  children: [
                    const AppLogo(size: 44),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chondrobindu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          _isUniversityStudent
                              ? 'University Student Profile Setup'
                              : (_nonUniRole == 'hsc' ? 'HSC & College Academic Setup' : 'Admission Preparation Setup'),
                          style: const TextStyle(
                            color: mutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Welcome Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        cardColor,
                        Color(0xFF2E221F),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.stars_rounded, color: accentColor, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Complete Your Profile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isUniversityStudent
                            ? 'Configure your university, department, level, and term to unlock course assessment analytics and academic planning.'
                            : 'Fill out your student information and target goal to customize your dynamic syllabus, exam schedules, and performance analytics.',
                        style: const TextStyle(
                          color: mutedTextColor,
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // University Student Toggle Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isUniversityStudent ? accentColor : borderColor,
                      width: _isUniversityStudent ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isUniversityStudent ? Icons.account_balance_rounded : Icons.school_rounded,
                            color: _isUniversityStudent ? accentColor : mutedTextColor,
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
                                _isUniversityStudent
                                    ? 'University Mode Enabled'
                                    : (_nonUniRole == 'hsc' ? 'HSC / College Mode Enabled' : 'Admission Mode Enabled'),
                                style: const TextStyle(
                                  color: mutedTextColor,
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
                const SizedBox(height: 16),

                // Segmented Selector (Shown ONLY when NOT University Student)
                if (!_isUniversityStudent) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1715),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _nonUniRole = 'hsc';
                                _primaryTarget = 'HSC Candidate / Board Exam';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _nonUniRole == 'hsc' ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'HSC / College Student',
                                  style: TextStyle(
                                    color: _nonUniRole == 'hsc' ? const Color(0xFF110D0C) : mutedTextColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _nonUniRole = 'admission';
                                final admissionOpts = _admissionTargetOptions;
                                if (admissionOpts.isNotEmpty && !admissionOpts.contains(_primaryTarget)) {
                                  _primaryTarget = admissionOpts.first;
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _nonUniRole == 'admission' ? accentColor : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'Admission Candidate',
                                  style: TextStyle(
                                    color: _nonUniRole == 'admission' ? const Color(0xFF110D0C) : mutedTextColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 1. Full Name
                _buildSectionHeader('FULL NAME *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _buildInputDecoration(
                    hintText: 'Enter your full name',
                    icon: Icons.person_outline_rounded,
                    cardColor: cardColor,
                    accentColor: accentColor,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    if (val.trim().length < 2) {
                      return 'Name must be at least 2 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // 2. Nickname
                _buildSectionHeader('NICKNAME (SHORT NAME) *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nicknameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _buildInputDecoration(
                    hintText: 'e.g. Sayem, Anika',
                    icon: Icons.badge_outlined,
                    cardColor: cardColor,
                    accentColor: accentColor,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your nickname';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // 3. District / Division
                _buildSectionHeader('DISTRICT / DIVISION *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _districtController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _buildInputDecoration(
                    hintText: 'e.g. Dhaka, Chattogram, Rajshahi',
                    icon: Icons.location_on_outlined,
                    cardColor: cardColor,
                    accentColor: accentColor,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter your district';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // Conditional Fields: University vs HSC/Admission
                if (_isUniversityStudent) ...[
                  // University Name
                  _buildSectionHeader('UNIVERSITY NAME *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _universityController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _buildInputDecoration(
                      hintText: 'e.g. BUET, DU, CUET, RUET, MIST',
                      icon: Icons.account_balance_rounded,
                      cardColor: cardColor,
                      accentColor: accentColor,
                    ),
                    validator: (val) {
                      if (_isUniversityStudent && (val == null || val.trim().isEmpty)) {
                        return 'Please enter your university name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Major / Department
                  _buildSectionHeader('MAJOR / DEPARTMENT *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _majorController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _buildInputDecoration(
                      hintText: 'e.g. EEE, CSE, Mechanical Engineering',
                      icon: Icons.domain_rounded,
                      cardColor: cardColor,
                      accentColor: accentColor,
                    ),
                    validator: (val) {
                      if (_isUniversityStudent && (val == null || val.trim().isEmpty)) {
                        return 'Please enter your major / department';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Level & Term Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('LEVEL *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedLevel,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: _buildInputDecoration(
                                hintText: 'Level',
                                icon: Icons.layers_rounded,
                                cardColor: cardColor,
                                accentColor: accentColor,
                              ),
                              items: ['1', '2', '3', '4'].map((l) {
                                return DropdownMenuItem(value: l, child: Text('Level $l'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedLevel = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('TERM *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedTerm,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: _buildInputDecoration(
                                hintText: 'Term',
                                icon: Icons.timelapse_rounded,
                                cardColor: cardColor,
                                accentColor: accentColor,
                              ),
                              items: ['1', '2'].map((t) {
                                return DropdownMenuItem(value: t, child: Text('Term $t'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedTerm = val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // College / Institution
                  _buildSectionHeader(_nonUniRole == 'admission' ? 'LAST ATTENDED COLLEGE / INSTITUTION *' : 'COLLEGE / INSTITUTION *'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _collegeController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: _buildInputDecoration(
                      hintText: 'e.g. Notre Dame College, Dhaka College',
                      icon: Icons.school_outlined,
                      cardColor: cardColor,
                      accentColor: accentColor,
                    ),
                    validator: (val) {
                      if (!_isUniversityStudent && (val == null || val.trim().isEmpty)) {
                        return 'Please enter your college name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // HSC Batch & Group Row
                  Row(
                    children: [
                      // HSC Batch Dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('HSC BATCH *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedBatch,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: _buildInputDecoration(
                                hintText: 'Batch',
                                icon: Icons.calendar_today_rounded,
                                cardColor: cardColor,
                                accentColor: accentColor,
                              ),
                              items: _batchOptions.map((b) {
                                return DropdownMenuItem(value: b, child: Text('HSC $b'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedBatch = val);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // HSC Group Dropdown
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('HSC GROUP / DIVISION *'),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: _selectedGroup,
                              dropdownColor: cardColor,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                              decoration: _buildInputDecoration(
                                hintText: 'Group',
                                icon: Icons.category_outlined,
                                cardColor: cardColor,
                                accentColor: accentColor,
                              ),
                              items: _groupOptions.map((g) {
                                return DropdownMenuItem(value: g, child: Text(g));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedGroup = val;
                                    if (_nonUniRole == 'admission') {
                                      final available = _admissionTargetOptions;
                                      if (!available.contains(_primaryTarget) && available.isNotEmpty) {
                                        _primaryTarget = available.first;
                                      }
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
                  const SizedBox(height: 24),

                  // If Admission Candidate, show Primary Admission Target & Secondary Target
                  if (_nonUniRole == 'admission') ...[
                    // 6. Primary Admission Target
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader('PRIMARY ADMISSION TARGET *'),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Required',
                            style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Target Options Radio Grid
                    Column(
                      children: _admissionTargetOptions.map((target) {
                        final isSelected = _primaryTarget == target;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10.0),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _primaryTarget = target;
                                if (_secondaryTarget == target) {
                                  _secondaryTarget = 'None';
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected ? accentColor.withOpacity(0.12) : cardColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? accentColor : borderColor,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Radio<String>(
                                    value: target,
                                    groupValue: _primaryTarget,
                                    activeColor: accentColor,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _primaryTarget = val;
                                          if (_secondaryTarget == val) {
                                            _secondaryTarget = 'None';
                                          }
                                        });
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          target,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : const Color(0xFFDDD2C8),
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          _getTargetSubtitle(target),
                                          style: const TextStyle(
                                            color: mutedTextColor,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // 7. Secondary Target Dropdown (Optional)
                    _buildSectionHeader('SECONDARY TARGET (OPTIONAL)'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _secondaryTargetOptions.contains(_secondaryTarget) ? _secondaryTarget : 'None',
                      dropdownColor: cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: _buildInputDecoration(
                        hintText: 'Secondary Track',
                        icon: Icons.alt_route_rounded,
                        cardColor: cardColor,
                        accentColor: accentColor,
                      ),
                      items: _secondaryTargetOptions.map((opt) {
                        return DropdownMenuItem(value: opt, child: Text(opt));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _secondaryTarget = val);
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 8. Dynamic Syllabus Auto-Load Preview Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bolt_rounded, color: Color(0xFFF59E0B), size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Dynamic Syllabus Generator',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _nonUniRole == 'hsc'
                              ? 'Pre-loading HSC ($_selectedGroup) syllabus modules:'
                              : 'Pre-loading syllabus modules for $currentTargetForPreview:',
                          style: const TextStyle(color: mutedTextColor, fontSize: 11.5),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: previewSubjects.map((sub) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: accentColor.withOpacity(0.25)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_rounded, color: accentColor, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    sub,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // Complete Action Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _completeOnboarding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: const Color(0xFF110D0C),
                      elevation: 4,
                      shadowColor: accentColor.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isSubmitting
                        ? const AppPreloader(
                            size: 20,
                            strokeWidth: 2,
                            color: Color(0xFF110D0C),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.arrow_forward_rounded, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Complete Profile & Start Preparation',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFABA093),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hintText,
    required IconData icon,
    required Color cardColor,
    required Color accentColor,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: cardColor,
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF7A6D66), fontSize: 13),
      prefixIcon: Icon(icon, color: accentColor, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4A3830)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF4A3830)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
    );
  }

  String _getTargetSubtitle(String target) {
    switch (target) {
      case 'HSC Prep/HSC Candidate':
      case 'HSC Candidate / Board Exam':
        return 'All 13 Board Subjects & NCTB Textbook Sections';
      case 'Engineering (BUET, CKRUET)':
        return 'BUET, CKRUET, MIST, IUT & Engineering Colleges';
      case 'Medical (MBBS & BDS)':
        return 'DMC, Government Medical Colleges, AFMC & Dental';
      case 'Versity "A" Unit':
      case 'Varsity A Unit':
        return 'Dhaka University A-Unit, JU, RU, CU Science';
      case 'Versity "B" Unit':
      case 'Varsity B Unit':
      case 'Versity "C" Unit':
      case 'Varsity C Unit':
        return 'Arts, Commerce, Social Science & Business Units';
      case 'IBA/BBA Admission':
      case 'IBA Prep':
        return 'DU IBA, JU IBA & BUP Faculty of Business';
      default:
        return 'General Admission Preparation';
    }
  }
}
