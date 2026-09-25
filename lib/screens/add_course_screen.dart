import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Instructor model for multi-instructor university courses
class Teacher {
  final String id;
  final String name;
  final String initials;
  final bool isActive;

  const Teacher({
    required this.id,
    required this.name,
    required this.initials,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'initials': initials,
      'isActive': isActive,
    };
  }

  factory Teacher.fromMap(Map<String, dynamic> map) {
    return Teacher(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      initials: map['initials'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  Teacher copyWith({
    String? id,
    String? name,
    String? initials,
    bool? isActive,
  }) {
    return Teacher(
      id: id ?? this.id,
      name: name ?? this.name,
      initials: initials ?? this.initials,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Course classification enum
enum CourseType {
  theory,
  sessional;

  String get displayName => this == CourseType.theory ? 'Theory' : 'Sessional/Lab';

  static CourseType fromString(String? val) {
    final v = val?.toLowerCase() ?? '';
    if (v.contains('sessional') || v.contains('lab')) {
      return CourseType.sessional;
    }
    return CourseType.theory;
  }
}

/// Dynamic CGPA Weightage Distribution model for courses
class WeightageDistribution {
  final String assessmentType;
  final double weightPercentage;
  final double totalMarks;
  final double obtainedMarks;
  final bool isActive;

  const WeightageDistribution({
    required this.assessmentType,
    required this.weightPercentage,
    this.totalMarks = 100.0,
    this.obtainedMarks = 0.0,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'assessmentType': assessmentType,
      'weightPercentage': weightPercentage,
      'totalMarks': totalMarks,
      'obtainedMarks': obtainedMarks,
      'isActive': isActive,
    };
  }

  factory WeightageDistribution.fromMap(Map<String, dynamic> map) {
    return WeightageDistribution(
      assessmentType: map['assessmentType'] as String? ?? '',
      weightPercentage: (map['weightPercentage'] as num?)?.toDouble() ?? 0.0,
      totalMarks: (map['totalMarks'] as num?)?.toDouble() ?? 100.0,
      obtainedMarks: (map['obtainedMarks'] as num?)?.toDouble() ?? 0.0,
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  WeightageDistribution copyWith({
    String? assessmentType,
    double? weightPercentage,
    double? totalMarks,
    double? obtainedMarks,
    bool? isActive,
  }) {
    return WeightageDistribution(
      assessmentType: assessmentType ?? this.assessmentType,
      weightPercentage: weightPercentage ?? this.weightPercentage,
      totalMarks: totalMarks ?? this.totalMarks,
      obtainedMarks: obtainedMarks ?? this.obtainedMarks,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Data Model for University Courses
class CourseModel {
  final String id;
  final String courseCode;
  final String courseName;
  final double creditHours;
  final String courseType;
  final String universityName;
  final Map<String, dynamic>? syllabusData;
  final DateTime createdAt;
  final bool useManualAttendanceOverride;
  final int? manualAttendedClasses;
  final int? manualTotalClasses;
  final List<Teacher> teachers;
  final List<WeightageDistribution> weightages;

  const CourseModel({
    required this.id,
    required this.courseCode,
    required this.courseName,
    required this.creditHours,
    required this.courseType,
    required this.universityName,
    this.syllabusData,
    required this.createdAt,
    this.useManualAttendanceOverride = false,
    this.manualAttendedClasses,
    this.manualTotalClasses,
    this.teachers = const [],
    this.weightages = const [],
  });

  String get code => courseCode;
  CourseType get courseTypeEnum => CourseType.fromString(courseType);
  bool get isTheory => courseTypeEnum == CourseType.theory;
  bool get isSessional => courseTypeEnum == CourseType.sessional;

  Teacher? getTeacher(String? teacherId) {
    if (teacherId == null || teacherId.isEmpty) return null;
    for (final t in teachers) {
      if (t.id == teacherId) return t;
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'courseCode': courseCode,
      'courseName': courseName,
      'creditHours': creditHours,
      'courseType': courseType,
      'universityName': universityName,
      'syllabusData': syllabusData,
      'createdAt': Timestamp.fromDate(createdAt),
      'useManualAttendanceOverride': useManualAttendanceOverride,
      if (manualAttendedClasses != null) 'manualAttendedClasses': manualAttendedClasses,
      if (manualTotalClasses != null) 'manualTotalClasses': manualTotalClasses,
      'teachers': teachers.map((t) => t.toMap()).toList(),
      'weightages': weightages.map((w) => w.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory CourseModel.fromMap(Map<String, dynamic> map, String docId) {
    DateTime parseDate(dynamic d) {
      if (d is Timestamp) return d.toDate();
      if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
      return DateTime.now();
    }

    Map<String, dynamic>? parsedSyllabus;
    final rawSyllabus = map['syllabusData'];
    if (rawSyllabus is Map<String, dynamic>) {
      parsedSyllabus = rawSyllabus;
    } else if (rawSyllabus is Map) {
      parsedSyllabus = Map<String, dynamic>.from(rawSyllabus);
    } else if (rawSyllabus is List) {
      parsedSyllabus = {'topics': rawSyllabus};
    }

    final rawTeachers = map['teachers'];
    List<Teacher> parsedTeachers = [];
    if (rawTeachers is List) {
      parsedTeachers = rawTeachers
          .whereType<Map>()
          .map((m) => Teacher.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    final rawWeightages = map['weightages'];
    List<WeightageDistribution> parsedWeightages = [];
    if (rawWeightages is List) {
      parsedWeightages = rawWeightages
          .whereType<Map>()
          .map((m) => WeightageDistribution.fromMap(Map<String, dynamic>.from(m)))
          .toList();
    }

    return CourseModel(
      id: docId,
      courseCode: map['courseCode'] as String? ?? '',
      courseName: map['courseName'] as String? ?? '',
      creditHours: (map['creditHours'] as num?)?.toDouble() ?? 3.0,
      courseType: map['courseType'] as String? ?? 'Theory',
      universityName: map['universityName'] as String? ?? '',
      syllabusData: parsedSyllabus,
      createdAt: parseDate(map['createdAt']),
      useManualAttendanceOverride: map['useManualAttendanceOverride'] as bool? ?? false,
      manualAttendedClasses: (map['manualAttendedClasses'] as num?)?.toInt(),
      manualTotalClasses: (map['manualTotalClasses'] as num?)?.toInt(),
      teachers: parsedTeachers,
      weightages: parsedWeightages,
    );
  }

  CourseModel copyWith({
    String? id,
    String? courseCode,
    String? courseName,
    double? creditHours,
    String? courseType,
    String? universityName,
    Map<String, dynamic>? syllabusData,
    DateTime? createdAt,
    bool? useManualAttendanceOverride,
    int? manualAttendedClasses,
    int? manualTotalClasses,
    List<Teacher>? teachers,
    List<WeightageDistribution>? weightages,
  }) {
    return CourseModel(
      id: id ?? this.id,
      courseCode: courseCode ?? this.courseCode,
      courseName: courseName ?? this.courseName,
      creditHours: creditHours ?? this.creditHours,
      courseType: courseType ?? this.courseType,
      universityName: universityName ?? this.universityName,
      syllabusData: syllabusData ?? this.syllabusData,
      createdAt: createdAt ?? this.createdAt,
      useManualAttendanceOverride: useManualAttendanceOverride ?? this.useManualAttendanceOverride,
      manualAttendedClasses: manualAttendedClasses ?? this.manualAttendedClasses,
      manualTotalClasses: manualTotalClasses ?? this.manualTotalClasses,
      teachers: teachers ?? this.teachers,
      weightages: weightages ?? this.weightages,
    );
  }
}

/// Global alias for CourseModel
typedef Course = CourseModel;

/// Add Course Screen for University Mode
class AddCourseScreen extends ConsumerStatefulWidget {
  final String universityName;

  const AddCourseScreen({super.key, required this.universityName});

  @override
  ConsumerState<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends ConsumerState<AddCourseScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _codeController;
  late TextEditingController _nameController;
  late TextEditingController _creditsController;

  String _selectedCourseType = 'Theory';
  bool _isCheckingGlobal = false;
  bool _isSaving = false;
  Map<String, dynamic>? _importedSyllabusData;

  final List<String> _courseTypes = ['Theory', 'Sessional/Lab'];

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _nameController = TextEditingController();
    _creditsController = TextEditingController(text: '3.0');
  }

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    _creditsController.dispose();
    super.dispose();
  }

  /// Query Firestore global_courses collection for pre-existing syllabus schema
  Future<void> _checkForGlobalSyllabus() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          content: Text('Please enter a Course Code first.'),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isCheckingGlobal = true);

    // Format Document ID cleanly (e.g. BUET_EEE101)
    final cleanCode = code.replaceAll(' ', '').toUpperCase();
    final docId = '${widget.universityName.replaceAll(' ', '')}_$cleanCode';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('global_courses')
          .doc(docId)
          .get();

      if (doc.exists && doc.data() != null) {
        SafeHaptics.lightImpact();
        _importedSyllabusData = doc.data();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              content: Text('Syllabus found and ready to import!'),
            ),
          );
        }
      } else {
        _importedSyllabusData = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF64748B),
              behavior: SnackBarBehavior.floating,
              content: Text('No global syllabus found. You can add topics manually later.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Error checking global syllabus: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingGlobal = false);
      }
    }
  }

  /// Save new course to user's courses subcollection in Firestore
  Future<void> _saveCourse() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('User authentication required to save courses.'),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    try {
      final courseCode = _codeController.text.trim();
      final courseName = _nameController.text.trim();
      final creditHours = double.tryParse(_creditsController.text.trim()) ?? 3.0;

      final courseDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc();

      final newCourse = CourseModel(
        id: courseDocRef.id,
        courseCode: courseCode,
        courseName: courseName,
        creditHours: creditHours,
        courseType: _selectedCourseType,
        universityName: widget.universityName,
        syllabusData: _importedSyllabusData,
        createdAt: DateTime.now(),
      );

      await courseDocRef.set(newCourse.toMap());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              'Course $courseCode saved successfully!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to save course: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add Course (${widget.universityName})',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Banner Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        cardColor,
                        accentColor.withValues(alpha: 0.15),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.class_outlined, color: accentColor, size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'University Course Registration',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Register new theory or sessional courses for ${widget.universityName}.',
                              style: TextStyle(
                                color: Colors.blueGrey.shade300,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Course Code & Auto-Check Button
                _buildFieldLabel('COURSE CODE *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _codeController,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: _buildInputDecoration(
                    hintText: 'e.g. EEE 101, CSE 205',
                    icon: Icons.code_rounded,
                    cardColor: cardColor,
                    accentColor: accentColor,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a course code';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // Check for Global Syllabus Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: _importedSyllabusData != null
                            ? const Color(0xFF10B981)
                            : accentColor.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isCheckingGlobal ? null : _checkForGlobalSyllabus,
                    icon: _isCheckingGlobal
                        ? const AppPreloader(
                            size: 16,
                            strokeWidth: 2,
                            color: accentColor,
                          )
                        : Icon(
                            _importedSyllabusData != null
                                ? Icons.check_circle_rounded
                                : Icons.travel_explore_rounded,
                            size: 18,
                            color: _importedSyllabusData != null ? const Color(0xFF10B981) : accentColor,
                          ),
                    label: Text(
                      _importedSyllabusData != null
                          ? 'Syllabus Imported'
                          : 'Check for Global Syllabus',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _importedSyllabusData != null ? const Color(0xFF10B981) : accentColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Course Name
                _buildFieldLabel('COURSE NAME *'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: _buildInputDecoration(
                    hintText: 'e.g. Electrical Circuits I, Data Structures',
                    icon: Icons.book_outlined,
                    cardColor: cardColor,
                    accentColor: accentColor,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a course name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // 3. Credit Hours & Course Type Row
                Row(
                  children: [
                    // Credit Hours
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('CREDIT HOURS *'),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _creditsController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: _buildInputDecoration(
                              hintText: 'e.g. 3.0, 1.5',
                              icon: Icons.timelapse_rounded,
                              cardColor: cardColor,
                              accentColor: accentColor,
                            ),
                            validator: (val) {
                              if (val == null || double.tryParse(val.trim()) == null) {
                                return 'Invalid credit';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Course Type Dropdown
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('COURSE TYPE *'),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCourseType,
                            dropdownColor: cardColor,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: _buildInputDecoration(
                              hintText: 'Type',
                              icon: Icons.category_outlined,
                              cardColor: cardColor,
                              accentColor: accentColor,
                            ),
                            items: _courseTypes.map((type) {
                              return DropdownMenuItem(value: type, child: Text(type));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCourseType = val);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Save Course Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: const Color(0xFF110D0C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _isSaving ? null : _saveCourse,
                    child: _isSaving
                        ? const AppPreloader(
                            size: 20,
                            strokeWidth: 2,
                            color: Color(0xFF110D0C),
                          )
                        : const Text(
                            'Save Course',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
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
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      prefixIcon: Icon(icon, color: Colors.blueGrey.shade400, size: 20),
      filled: true,
      fillColor: const Color(0xFF241C1A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF382A24)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF382A24)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accentColor, width: 1.5),
      ),
    );
  }
}
