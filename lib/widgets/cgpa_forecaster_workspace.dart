import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/theme/app_colors.dart';
import '../models/assessment_model.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart' show AttendanceRecord, AttendanceStatus;
import '../models/user_profile.dart';
import '../providers/firestore_providers.dart';
import '../providers/user_profile_provider.dart';
import '../screens/grading_setup_screen.dart';
import '../screens/term_performance_screen.dart' show CourseScoreBreakdown;
import '../services/assessment_calculator.dart';
import '../utils/safe_haptics.dart';
import 'grading_scale_settings_dialog.dart';

/// Representation of a simulated course with real calculated marks and weightages
typedef SimulatedCourseData = ({
  Course course,
  GradingRow gradingRow,
  double totalPct,
  double courseTotalMarks,
  double termMaxMarks,
  double earnedTermMarks,
  double attMaxMarks,
  double effectiveAttMarks,
  double ctMaxMarks,
  double effectiveCtMarks,
  double midMaxMarks,
  double effectiveMidMarks,
  double finalMaxMarks,
  double projectedFinalMarks,
  double sliderPct,
  bool isSelected,
});

/// Full interactive CGPA Forecaster & Term Simulator Workspace strictly designed from Stitch MCP.
/// Renders inline in Desktop Web and Mobile Insights without requiring a launcher screen.
class CgpaForecasterWorkspace extends ConsumerStatefulWidget {
  final List<Course> courses;
  final UserProfile profile;
  final bool isDesktop;
  final VoidCallback? onNavigateToCourses;

  const CgpaForecasterWorkspace({
    super.key,
    required this.courses,
    required this.profile,
    required this.isDesktop,
    this.onNavigateToCourses,
  });

  @override
  ConsumerState<CgpaForecasterWorkspace> createState() => _CgpaForecasterWorkspaceState();
}

class _CgpaForecasterWorkspaceState extends ConsumerState<CgpaForecasterWorkspace> {
  // Multi-select Course State (courseId -> isSelected)
  final Set<String> _selectedCourseIds = {};
  bool _initialized = false;

  // Predictive Final Exam Slider State (courseId -> expected final exam percentage 0.0 - 100.0)
  final Map<String, double> _projectedPendingPercentages = {};

  // Hypothetical / Simulated Marks State (courseId -> marks)
  final Map<String, double> _simulatedAttendanceMarks = {};
  final Map<String, double> _simulatedCtMarks = {};

  // Accordion open/closed state (courseId -> isOpen)
  final Set<String> _expandedAccordions = {};

  // Active Grading Scale
  List<GradingRow> _gradingScale = [];

  static List<GradingRow> get _defaultBUETScale => [
        GradingRow(letterGrade: 'A+', gradePoint: 4.00, minPercentage: 80, maxPercentage: 100),
        GradingRow(letterGrade: 'A', gradePoint: 3.75, minPercentage: 75, maxPercentage: 79),
        GradingRow(letterGrade: 'A-', gradePoint: 3.50, minPercentage: 70, maxPercentage: 74),
        GradingRow(letterGrade: 'B+', gradePoint: 3.25, minPercentage: 65, maxPercentage: 69),
        GradingRow(letterGrade: 'B', gradePoint: 3.00, minPercentage: 60, maxPercentage: 64),
        GradingRow(letterGrade: 'B-', gradePoint: 2.75, minPercentage: 55, maxPercentage: 59),
        GradingRow(letterGrade: 'C+', gradePoint: 2.50, minPercentage: 50, maxPercentage: 54),
        GradingRow(letterGrade: 'C', gradePoint: 2.25, minPercentage: 45, maxPercentage: 49),
        GradingRow(letterGrade: 'D', gradePoint: 2.00, minPercentage: 40, maxPercentage: 44),
        GradingRow(letterGrade: 'F', gradePoint: 0.00, minPercentage: 0, maxPercentage: 39),
      ];

  @override
  void initState() {
    super.initState();
    _gradingScale = _defaultBUETScale;
    _initCourseState();
    _fetchGradingScale();
  }

  @override
  void didUpdateWidget(covariant CgpaForecasterWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.courses.length != oldWidget.courses.length) {
      _initCourseState();
    }
  }

  void _initCourseState() {
    if (widget.courses.isNotEmpty && !_initialized) {
      for (final course in widget.courses) {
        _selectedCourseIds.add(course.id);
        _projectedPendingPercentages.putIfAbsent(course.id, () => 80.0);
      }
      _initialized = true;
    }
  }

  Future<void> _fetchGradingScale() async {
    final uniName = widget.profile.universityName?.isNotEmpty == true
        ? widget.profile.universityName!
        : 'BUET';
    try {
      if (Firebase.apps.isNotEmpty) {
        final doc = await FirebaseFirestore.instance
            .collection('university_grading')
            .doc(uniName)
            .get();

        if (doc.exists && doc.data() != null && mounted) {
          final rawRows = doc.data()?['rows'] as List<dynamic>?;
          if (rawRows != null && rawRows.isNotEmpty) {
            setState(() {
              _gradingScale = rawRows
                  .map((r) => GradingRow.fromMap(Map<String, dynamic>.from(r)))
                  .toList();
            });
          }
        }
      }
    } catch (_) {
      // Retain _defaultBUETScale fallback
    }
  }

  GradingRow _getGradingRowForPercentage(double percentage) {
    final rounded = percentage.roundToDouble();
    for (final row in _gradingScale) {
      if (rounded >= row.minPercentage && rounded <= row.maxPercentage) {
        return row;
      }
    }
    if (percentage >= 80) return _gradingScale.isNotEmpty ? _gradingScale.first : _defaultBUETScale.first;
    return _gradingScale.isNotEmpty ? _gradingScale.last : _defaultBUETScale.last;
  }

  void _applyTargetPreset(double targetPct) {
    SafeHaptics.mediumImpact();
    setState(() {
      for (final course in widget.courses) {
        _projectedPendingPercentages[course.id] = targetPct;
      }
    });
  }

  void _toggleAllCourses() {
    SafeHaptics.lightImpact();
    setState(() {
      if (_selectedCourseIds.length == widget.courses.length) {
        _selectedCourseIds.clear();
      } else {
        _selectedCourseIds.clear();
        for (final c in widget.courses) {
          _selectedCourseIds.add(c.id);
        }
      }
    });
  }

  void _openGradingScaleModal(BuildContext context) {
    final colors = AppColors.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final uniName = widget.profile.universityName?.isNotEmpty == true
        ? widget.profile.universityName!
        : 'BUET';

    GradingScaleSettingsDialog.showAdaptive(
      context: context,
      universityName: uniName,
      currentScale: _gradingScale,
      onSave: (updatedScale) async {
        setState(() {
          _gradingScale = updatedScale;
        });

        try {
          if (Firebase.apps.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('university_grading')
                .doc(uniName)
                .set({
              'university': uniName,
              'rows': updatedScale.map((r) => r.toMap()).toList(),
              'lastUpdated': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } catch (_) {}

        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            backgroundColor: colors.surface,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.surfaceBorder),
            ),
            content: Text(
              'Grading scale updated! All simulated courses recalculated.',
              style: GoogleFonts.plusJakartaSans(
                color: colors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getGradeColor(String letter) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80);
    if (letter == 'A') return const Color(0xFF8FA8C8);
    if (letter.startsWith('A-')) return const Color(0xFFC88256);
    if (letter.startsWith('F')) return const Color(0xFFEF4444);
    return const Color(0xFFEDEAE0);
  }

  Color _getGradeBgColor(String letter) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.15);
    if (letter == 'A') return const Color(0xFF8FA8C8).withValues(alpha: 0.20);
    if (letter.startsWith('A-')) return const Color(0xFFC88256).withValues(alpha: 0.20);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.20);
    return const Color(0xFF2E3846).withValues(alpha: 0.5);
  }

  Color _getGradeBorderColor(String letter) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.35);
    if (letter == 'A') return const Color(0xFF8FA8C8).withValues(alpha: 0.35);
    if (letter.startsWith('A-')) return const Color(0xFFC88256).withValues(alpha: 0.35);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.35);
    return const Color(0xFF2E3846);
  }

  SimulatedCourseData _computeCourseSimulationData({
    required Course course,
    required List<Assessment> allAssessments,
    required List<AttendanceRecord> attendanceRecords,
    required bool isSelected,
  }) {
    final rawData = course.rawData ?? {
      'courseCode': course.code,
      'creditHours': course.credits,
      'courseType': course.courseType.name,
    };

    // 1. Total marks for course: 100 marks per credit (e.g. 3.0 Cr -> 300 marks; 1.5 Cr -> 150 marks)
    final double rawTotalMarks = (rawData['totalMarks'] as num?)?.toDouble() ?? 0.0;
    final double courseTotalMarks = rawTotalMarks > 0
        ? rawTotalMarks
        : (course.credits > 0 ? course.credits * 100.0 : 100.0);

    // 2. Determine Weightages & Max Marks for Term Final and Continuous Components
    double finalWeightPct = course.isTheory ? 70.0 : 40.0;
    double attWeightPct = course.isTheory ? 10.0 : 30.0;
    double ctWeightPct = course.isTheory ? 20.0 : 30.0;
    double midWeightPct = 0.0;

    double? customFinalMarks;
    double? customAttMarks;
    double? customCtMarks;
    double? customMidMarks;

    final rawWeightages = rawData['weightages'];
    if (rawWeightages is List && rawWeightages.isNotEmpty) {
      for (final w in rawWeightages) {
        if (w is Map) {
          final isActive = w['isActive'] as bool? ?? true;
          final pct = (w['weightPercentage'] as num?)?.toDouble() ?? 0.0;
          final totalM = (w['totalMarks'] as num?)?.toDouble();
          if (isActive) {
            final type = (w['assessmentType'] as String? ?? '').toLowerCase();
            if (type.contains('final')) {
              if (pct > 0) finalWeightPct = pct;
              if (totalM != null && totalM > 0) customFinalMarks = totalM;
            } else if (type.contains('attend')) {
              if (pct > 0) attWeightPct = pct;
              if (totalM != null && totalM > 0) customAttMarks = totalM;
            } else if (type.contains('ct') || type.contains('quiz') || type.contains('continuous')) {
              if (pct > 0) ctWeightPct = pct;
              if (totalM != null && totalM > 0) customCtMarks = totalM;
            } else if (type.contains('mid') || type.contains('lab report')) {
              if (pct > 0) midWeightPct = pct;
              if (totalM != null && totalM > 0) customMidMarks = totalM;
            }
          }
        }
      }
    }

    // Check direct fields on course
    final rawFinalExamMarks = (rawData['finalExamMarks'] as num?)?.toDouble() ??
        (rawData['finalTotal'] as num?)?.toDouble() ??
        (rawData['assessments'] is Map ? (rawData['assessments']['finalTotal'] as num?)?.toDouble() : null);
    if (rawFinalExamMarks != null && rawFinalExamMarks > 0) {
      customFinalMarks = rawFinalExamMarks;
    }

    // Compute finalMaxMarks (e.g. 210 marks for 3.0 Cr theory)
    final double finalMaxMarks = customFinalMarks ??
        ((finalWeightPct / 100.0) * courseTotalMarks).clamp(1.0, courseTotalMarks);

    // Continuous assessment max marks (e.g. 90 marks for 3.0 Cr theory)
    final double termMaxMarks = (courseTotalMarks - finalMaxMarks).clamp(0.0, courseTotalMarks);

    // Compute component max marks
    double attMaxMarks = customAttMarks ?? ((attWeightPct / 100.0) * courseTotalMarks);
    double ctMaxMarks = customCtMarks ?? ((ctWeightPct / 100.0) * courseTotalMarks);
    double midMaxMarks = customMidMarks ?? (midWeightPct > 0 ? (midWeightPct / 100.0) * courseTotalMarks : 0.0);

    // If components don't sum to termMaxMarks (e.g. when mid is 0), proportionally balance them
    final double sumComponents = attMaxMarks + ctMaxMarks + midMaxMarks;
    if (sumComponents > 0 && (sumComponents - termMaxMarks).abs() > 0.5) {
      attMaxMarks = (attMaxMarks / sumComponents) * termMaxMarks;
      ctMaxMarks = (ctMaxMarks / sumComponents) * termMaxMarks;
      if (midMaxMarks > 0) {
        midMaxMarks = (midMaxMarks / sumComponents) * termMaxMarks;
      }
    } else if (sumComponents == 0 && termMaxMarks > 0) {
      attMaxMarks = termMaxMarks * (1.0 / 3.0);
      ctMaxMarks = termMaxMarks * (2.0 / 3.0);
    }

    // 3. Real Earned Attendance Marks
    double realAttMarks = 0.0;
    if (course.useManualAttendanceOverride && (course.manualTotalClasses ?? 0) > 0) {
      final attended = (course.manualAttendedClasses ?? 0).clamp(0, course.manualTotalClasses!);
      realAttMarks = (attended / course.manualTotalClasses!) * attMaxMarks;
    } else if (rawData['assessments'] is Map &&
        ((rawData['assessments']['totalClasses'] as num?)?.toInt() ?? 0) > 0) {
      final total = (rawData['assessments']['totalClasses'] as num).toInt();
      final attended = ((rawData['assessments']['classesAttended'] as num?)?.toInt() ?? 0).clamp(0, total);
      realAttMarks = (attended / total) * attMaxMarks;
    } else {
      final courseAttRecs = attendanceRecords.where((r) =>
          r.courseId == course.id ||
          (r.courseCode != null &&
              r.courseCode!.trim().toLowerCase() == course.code.trim().toLowerCase())).toList();
      if (courseAttRecs.isNotEmpty) {
        final attended = courseAttRecs.where((r) =>
            r.status == AttendanceStatus.attended || r.status == AttendanceStatus.extra).length;
        final totalActioned = courseAttRecs.where((r) =>
            r.status == AttendanceStatus.attended ||
            r.status == AttendanceStatus.missed ||
            r.status == AttendanceStatus.extra).length;
        if (totalActioned > 0) {
          realAttMarks = (attended / totalActioned) * attMaxMarks;
        }
      }
    }
    final double effectiveAttMarks = (_simulatedAttendanceMarks[course.id] ?? realAttMarks)
        .clamp(0.0, attMaxMarks);

    // 4. Real Earned CT / Quiz Marks
    double realCtMarks = 0.0;
    final courseAssessments = allAssessments.where((a) =>
        a.courseId == course.id ||
        (a.courseCode.isNotEmpty &&
            a.courseCode.trim().toLowerCase() == course.code.trim().toLowerCase())).toList();

    final ctItems = courseAssessments
        .where((a) =>
            a.type.toLowerCase().contains('ct') ||
            a.type.toLowerCase().contains('quiz') ||
            a.name.toLowerCase().contains('ct') ||
            a.name.toLowerCase().contains('quiz'))
        .where((a) => a.isCompleted && a.totalMarks > 0 && a.obtainedMarks != null)
        .map((a) => AssessmentItem(name: a.name, obtainedMarks: a.obtainedMarks, totalMarks: a.totalMarks))
        .toList();

    if (ctItems.isNotEmpty) {
      final catRes = AssessmentCalculationHelper.calculateCategoryScore(
        items: ctItems,
        weightagePercentage: ctWeightPct,
        useBestOf: true,
        bestCount: 3,
      );
      realCtMarks = (catRes.percentage / 100.0) * ctMaxMarks;
    } else {
      // Fallback to course.rawData['assessments']
      final breakdown = CourseScoreBreakdown.compute(rawData);
      if (breakdown.ctWeight > 0 && breakdown.ctSecured > 0) {
        realCtMarks = (breakdown.ctSecured / breakdown.ctWeight).clamp(0.0, 1.0) * ctMaxMarks;
      }
    }
    final double effectiveCtMarks = (_simulatedCtMarks[course.id] ?? realCtMarks)
        .clamp(0.0, ctMaxMarks);

    // 5. Real Earned Midterm Marks
    double realMidMarks = 0.0;
    if (midMaxMarks > 0) {
      final midAssessments = courseAssessments
          .where((a) =>
              a.type.toLowerCase().contains('mid') ||
              a.name.toLowerCase().contains('mid'))
          .where((a) => a.isCompleted && a.totalMarks > 0 && a.obtainedMarks != null)
          .toList();
      if (midAssessments.isNotEmpty) {
        final totalMidTotal = midAssessments.fold<double>(0.0, (acc, a) => acc + a.totalMarks);
        final totalMidObt = midAssessments.fold<double>(0.0, (acc, a) => acc + (a.obtainedMarks ?? 0.0));
        if (totalMidTotal > 0) {
          realMidMarks = (totalMidObt / totalMidTotal).clamp(0.0, 1.0) * midMaxMarks;
        }
      } else {
        final breakdown = CourseScoreBreakdown.compute(rawData);
        if (breakdown.midWeight > 0 && breakdown.midSecured > 0) {
          realMidMarks = (breakdown.midSecured / breakdown.midWeight).clamp(0.0, 1.0) * midMaxMarks;
        }
      }
    }
    final double effectiveMidMarks = realMidMarks.clamp(0.0, midMaxMarks);

    // 6. Earned Term Total Marks (Strictly clamped to termMaxMarks)
    final double earnedTermMarks = (effectiveAttMarks + effectiveCtMarks + effectiveMidMarks)
        .clamp(0.0, termMaxMarks);

    // 7. Projected Final Marks from Slider
    final double sliderPct = _projectedPendingPercentages[course.id] ?? 80.0;
    final double projectedFinalMarks = ((sliderPct / 100.0) * finalMaxMarks).clamp(0.0, finalMaxMarks);

    // 8. Total Course Marks and Percentage
    final double totalCourseMarks = (earnedTermMarks + projectedFinalMarks).clamp(0.0, courseTotalMarks);
    final double totalPct = courseTotalMarks > 0
        ? ((totalCourseMarks / courseTotalMarks) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final gradingRow = _getGradingRowForPercentage(totalPct);

    return (
      course: course,
      gradingRow: gradingRow,
      totalPct: totalPct,
      courseTotalMarks: courseTotalMarks,
      termMaxMarks: termMaxMarks,
      earnedTermMarks: earnedTermMarks,
      attMaxMarks: attMaxMarks,
      effectiveAttMarks: effectiveAttMarks,
      ctMaxMarks: ctMaxMarks,
      effectiveCtMarks: effectiveCtMarks,
      midMaxMarks: midMaxMarks,
      effectiveMidMarks: effectiveMidMarks,
      finalMaxMarks: finalMaxMarks,
      projectedFinalMarks: projectedFinalMarks,
      sliderPct: sliderPct,
      isSelected: isSelected,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enrolled = widget.courses.where((c) => !c.isArchived).toList();

    // Sort numerically by course code sequence
    enrolled.sort((a, b) => CourseService.compareCourseCodes(a.code, b.code));

    if (enrolled.isEmpty) {
      return _buildEmptyState(colors);
    }

    // Watch real live assessments & attendance records from Firestore streams
    final allAssessments = ref.watch(allAssessmentsStreamProvider).value ?? [];
    final attendanceRecords = ref.watch(attendanceRecordsStreamProvider).value ?? [];

    // Calculations across all enrolled courses
    double totalWeightedQualityPoints = 0.0;
    double totalSelectedCredits = 0.0;
    final List<SimulatedCourseData> simulatedCourses = [];

    for (final course in enrolled) {
      final isSelected = _selectedCourseIds.contains(course.id);
      final item = _computeCourseSimulationData(
        course: course,
        allAssessments: allAssessments,
        attendanceRecords: attendanceRecords,
        isSelected: isSelected,
      );

      if (isSelected && course.credits > 0) {
        totalWeightedQualityPoints += (item.gradingRow.gradePoint * course.credits);
        totalSelectedCredits += course.credits;
      }

      simulatedCourses.add(item);
    }

    // Safely guard against division by zero (e.g. when 0 credits selected)
    final double simulatedTermCgpa = totalSelectedCredits > 0
        ? (totalWeightedQualityPoints / totalSelectedCredits)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. TOP COMMAND HERO CARD
        _buildCommandHeroCard(
          colors: colors,
          simulatedCgpa: simulatedTermCgpa,
          totalSelectedCredits: totalSelectedCredits,
          selectedCount: _selectedCourseIds.length,
          totalCount: enrolled.length,
          simulatedCourses: simulatedCourses,
        ),

        const SizedBox(height: 24),

        // 2. SECTION TITLE & META BAR
        _buildSectionTitleBar(colors),

        const SizedBox(height: 14),

        // 3. COURSE SIMULATION CARDS (2-Column Responsive Grid on Desktop, 1-Column on Mobile)
        if (widget.isDesktop)
          _buildDesktopCourseGrid(colors, simulatedCourses)
        else
          _buildMobileCourseStack(colors, simulatedCourses),

        const SizedBox(height: 20),

        // 4. BOTTOM ADVISORY NOTE
        _buildAdvisoryNote(colors),
      ],
    );
  }

  Widget _buildEmptyState(ChondrobinduThemeColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.recessed,
              shape: BoxShape.circle,
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: Icon(Icons.school_rounded, color: colors.primary, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'No Courses Enrolled for Simulation',
            style: GoogleFonts.plusJakartaSans(
              color: colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Add your semester courses in the Courses workspace to simulate marks, test final exam cutoffs, and forecast your term CGPA in real time.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: colors.textMuted,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
          ),
          if (widget.onNavigateToCourses != null) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.secondary,
                foregroundColor: const Color(0xFF171C24),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: widget.onNavigateToCourses,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Enroll Semester Courses',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommandHeroCard({
    required ChondrobinduThemeColors colors,
    required double simulatedCgpa,
    required double totalSelectedCredits,
    required int selectedCount,
    required int totalCount,
    required List<SimulatedCourseData> simulatedCourses,
  }) {
    final uniStr = widget.profile.universityName?.isNotEmpty == true ? widget.profile.universityName!.toUpperCase() : 'BUET';
    final deptStr = widget.profile.department?.isNotEmpty == true ? widget.profile.department!.toUpperCase() : 'EEE';
    final levelStr = widget.profile.level?.isNotEmpty == true ? widget.profile.level! : '1';
    final termStr = widget.profile.term?.isNotEmpty == true ? widget.profile.term! : '1';

    final double targetCgpa = widget.profile.targetGpa > 0 ? widget.profile.targetGpa : 3.75;
    final delta = simulatedCgpa - targetCgpa;
    final isAboveTarget = delta >= 0;

    return Container(
      padding: EdgeInsets.all(widget.isDesktop ? 24 : 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Left CGPA & Right Actions
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left: Eyebrow + Simulated Term CGPA + Target Pill
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Eyebrow
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'UNIVERSITY TRACK • $uniStr $deptStr • LEVEL $levelStr, TERM $termStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // CGPA Numbers + Target Pill
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              simulatedCgpa.toStringAsFixed(2),
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textPrimary,
                                fontSize: widget.isDesktop ? 46 : 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '/ 4.00',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: widget.isDesktop ? 16 : 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),

                        // Target Delta Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isAboveTarget
                                ? const Color(0xFF4ADE80).withValues(alpha: 0.12)
                                : colors.secondary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isAboveTarget
                                  ? const Color(0xFF4ADE80).withValues(alpha: 0.35)
                                  : colors.secondary.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAboveTarget ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                                size: 15,
                                color: isAboveTarget ? const Color(0xFF4ADE80) : colors.secondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Target: ${targetCgpa.toStringAsFixed(2)} (${isAboveTarget ? '+' : ''}${delta.toStringAsFixed(2)} ${isAboveTarget ? 'above' : 'below'})',
                                style: GoogleFonts.jetBrainsMono(
                                  color: isAboveTarget ? const Color(0xFF4ADE80) : colors.secondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right: Credits Chip & Grading Scale Trigger
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Calculated Credits Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.pie_chart_rounded, size: 18, color: colors.primary),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'CALCULATED CREDITS',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            Text(
                              '${totalSelectedCredits.toStringAsFixed(1)} Cr • $selectedCount of $totalCount Selected',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Grading Scale Settings Trigger
                  InkWell(
                    onTap: () => _openGradingScaleModal(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.settings_rounded, size: 16, color: colors.secondary),
                          const SizedBox(width: 6),
                          Text(
                            'Grading Scale',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 14),

          // Middle Strip: Course Live Projected Grade Pills
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PROJECTED COURSE GRADES',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                'Weighted by credit hours',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.primary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Horizontal scroll/wrap of grade pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: simulatedCourses.map((item) {
                final c = item.course;
                final grade = item.gradingRow;
                final isSelected = item.isSelected;
                final gradeColor = _getGradeColor(grade.letterGrade);
                final gradeBg = _getGradeBgColor(grade.letterGrade);

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isSelected ? 1.0 : 0.45,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? _getGradeBorderColor(grade.letterGrade)
                              : colors.surfaceBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${c.code}:',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: gradeBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${grade.letterGrade} (${grade.gradePoint.toStringAsFixed(2)})',
                              style: GoogleFonts.jetBrainsMono(
                                color: gradeColor,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${c.credits.toStringAsFixed(1)} Cr',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 14),
          Divider(color: colors.surfaceBorder, height: 1),
          const SizedBox(height: 12),

          // Bottom Action Strip: Quick Target Presets & Toggle All
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Text(
                        'Simulate Target:',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildPresetChip('A+ (80%+)', 82.0, colors),
                      const SizedBox(width: 6),
                      _buildPresetChip('A (75%)', 76.0, colors),
                      const SizedBox(width: 6),
                      _buildPresetChip('B (60%)', 62.0, colors),
                      const SizedBox(width: 6),
                      _buildPresetChip('Pass (40%)', 45.0, colors),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _applyTargetPreset(80.0),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: colors.recessed,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.surfaceBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded, size: 13, color: colors.secondary),
                              const SizedBox(width: 4),
                              Text(
                                'Reset',
                                style: GoogleFonts.jetBrainsMono(
                                  color: colors.secondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Select / Deselect All Toggle
              InkWell(
                onTap: _toggleAllCourses,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.checklist_rounded, size: 16, color: colors.primary),
                      const SizedBox(width: 5),
                      Text(
                        _selectedCourseIds.length == widget.courses.length
                            ? 'Deselect All'
                            : 'Select All',
                        style: GoogleFonts.jetBrainsMono(
                          color: colors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, double targetPct, ChondrobinduThemeColors colors) {
    return InkWell(
      onTap: () => _applyTargetPreset(targetPct),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colors.recessed,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            color: colors.textPrimary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitleBar(ChondrobinduThemeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enrolled Course Simulations',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Adjust sliders to forecast required final exam performance per subject',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text('Earned Term Marks', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5)),
            const SizedBox(width: 14),
            Container(width: 8, height: 8, decoration: BoxDecoration(color: colors.secondary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text('Projected Final Exam', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10.5)),
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopCourseGrid(
    ChondrobinduThemeColors colors,
    List<SimulatedCourseData> items,
  ) {
    // 2-Column Responsive Pairing (Safe from IntrinsicHeight crash on Flutter Web)
    return Column(
      children: [
        for (int i = 0; i < items.length; i += 2) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildCourseSimulationCard(colors, items[i]),
                ),
                const SizedBox(width: 16),
                if (i + 1 < items.length)
                  Expanded(
                    child: _buildCourseSimulationCard(colors, items[i + 1]),
                  )
                else
                  const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMobileCourseStack(
    ChondrobinduThemeColors colors,
    List<SimulatedCourseData> items,
  ) {
    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 14.0),
          child: _buildCourseSimulationCard(colors, item),
        );
      }).toList(),
    );
  }

  Widget _buildCourseSimulationCard(
    ChondrobinduThemeColors colors,
    SimulatedCourseData item,
  ) {
    final c = item.course;
    final isSelected = item.isSelected;
    final grade = item.gradingRow;
    final isExpanded = _expandedAccordions.contains(c.id);
    final isTheory = c.isTheory;

    final gradeColor = _getGradeColor(grade.letterGrade);
    final gradeBg = _getGradeBgColor(grade.letterGrade);
    final gradeBorder = _getGradeBorderColor(grade.letterGrade);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: isSelected ? 1.0 : 0.45,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header: Course code, credit badge, course title, live projected %, grade pill, and toggle switch
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            c.code,
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: colors.recessed,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: colors.surfaceBorder),
                            ),
                            child: Text(
                              '${c.credits.toStringAsFixed(1)} Cr',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isTheory
                                  ? colors.primary.withValues(alpha: 0.12)
                                  : colors.secondary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isTheory ? 'Theory' : 'Sessional / Lab',
                              style: GoogleFonts.jetBrainsMono(
                                color: isTheory ? colors.primary : colors.secondary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: colors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${item.totalPct.toStringAsFixed(1)}%',
                          style: GoogleFonts.jetBrainsMono(
                            color: gradeColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: gradeBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: gradeBorder),
                          ),
                          child: Text(
                            '${grade.letterGrade} • ${grade.gradePoint.toStringAsFixed(2)}',
                            style: GoogleFonts.jetBrainsMono(
                              color: gradeColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),

                    // Include / Exclude Toggle Switch
                    Switch(
                      value: isSelected,
                      activeThumbColor: colors.secondary,
                      activeTrackColor: colors.secondary.withValues(alpha: 0.3),
                      inactiveThumbColor: colors.textMuted,
                      inactiveTrackColor: colors.recessed,
                      onChanged: (val) {
                        SafeHaptics.lightImpact();
                        setState(() {
                          if (val) {
                            _selectedCourseIds.add(c.id);
                          } else {
                            _selectedCourseIds.remove(c.id);
                          }
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 14),

            // 2. Recessed 3-column breakdown strip with real marks and inline editing
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                children: [
                  // Col 1: Attendance
                  Expanded(
                    child: _buildBreakdownCol(
                      label: isTheory ? 'Attendance' : 'Lab Reports',
                      secured: item.effectiveAttMarks,
                      weight: item.attMaxMarks,
                      colors: colors,
                      onEdit: () => _openScoreSimulationDialog(
                        courseId: c.id,
                        label: isTheory ? 'Attendance' : 'Lab Reports',
                        maxWeight: item.attMaxMarks,
                        currentVal: item.effectiveAttMarks,
                        onApplied: (v) => setState(() => _simulatedAttendanceMarks[c.id] = v),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 26, color: colors.surfaceBorder),

                  // Col 2: CT / Quizzes
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: _buildBreakdownCol(
                        label: isTheory ? 'CT / Quizzes' : 'Quiz & Viva',
                        secured: item.effectiveCtMarks,
                        weight: item.ctMaxMarks,
                        colors: colors,
                        onEdit: () => _openScoreSimulationDialog(
                          courseId: c.id,
                          label: isTheory ? 'CT / Quizzes' : 'Quiz & Viva',
                          maxWeight: item.ctMaxMarks,
                          currentVal: item.effectiveCtMarks,
                          onApplied: (v) => setState(() => _simulatedCtMarks[c.id] = v),
                        ),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 26, color: colors.surfaceBorder),

                  // Col 3: Term Total (Continuous)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isTheory ? 'Term Total' : 'Continuous',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${item.earnedTermMarks.toStringAsFixed(1)} / ${item.termMaxMarks.toStringAsFixed(0)}',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3. Segmented marks progress bar (Real marks out of real totals)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'Earned: ',
                      style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                      children: [
                        TextSpan(
                          text: '${item.earnedTermMarks.toStringAsFixed(1)} / ${item.termMaxMarks.toStringAsFixed(0)}',
                          style: GoogleFonts.jetBrainsMono(color: colors.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: 'Final: ',
                      style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                      children: [
                        TextSpan(
                          text: '${item.projectedFinalMarks.toStringAsFixed(1)} / ${item.finalMaxMarks.toStringAsFixed(0)} (${item.sliderPct.toStringAsFixed(0)}%)',
                          style: GoogleFonts.jetBrainsMono(color: colors.secondary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Progress track
            ClipRRect(
              borderRadius: BorderRadius.circular(9999),
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    if (item.earnedTermMarks > 0)
                      Expanded(
                        flex: ((item.earnedTermMarks / item.courseTotalMarks) * 100).round().clamp(1, 100),
                        child: Container(color: colors.primary),
                      ),
                    if (item.projectedFinalMarks > 0)
                      Expanded(
                        flex: ((item.projectedFinalMarks / item.courseTotalMarks) * 100).round().clamp(1, 100),
                        child: Container(color: colors.secondary),
                      ),
                    if ((item.courseTotalMarks - (item.earnedTermMarks + item.projectedFinalMarks)) > 0)
                      Expanded(
                        flex: (((item.courseTotalMarks - (item.earnedTermMarks + item.projectedFinalMarks)) / item.courseTotalMarks) * 100).round().clamp(1, 100),
                        child: Container(color: colors.recessed),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // 4. Interactive Final Exam Score slider (Exact required marks out of real Term Final total)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isTheory ? 'Expected Final Exam Score' : 'Expected Lab Final Score',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.projectedFinalMarks.toStringAsFixed(1)} / ${item.finalMaxMarks.toStringAsFixed(0)} marks (${item.sliderPct.toStringAsFixed(0)}%)',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.secondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colors.primary,
                inactiveTrackColor: colors.recessed,
                thumbColor: colors.secondary,
                overlayColor: colors.secondary.withValues(alpha: 0.15),
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: item.sliderPct,
                min: 0.0,
                max: 100.0,
                onChanged: isSelected
                    ? (val) {
                        setState(() {
                          _projectedPendingPercentages[c.id] = val;
                        });
                      }
                    : null,
              ),
            ),

            // Tick marks scaled to real final marks
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0% (0)', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                  Text('40% (${(0.40 * item.finalMaxMarks).toStringAsFixed(0)})', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                  Text('75% (${(0.75 * item.finalMaxMarks).toStringAsFixed(0)})', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                  Text('100% (${item.finalMaxMarks.toStringAsFixed(0)})', style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 10)),
                ],
              ),
            ),

            const SizedBox(height: 14),
            Divider(color: colors.surfaceBorder, height: 1),
            const SizedBox(height: 10),

            // 5. Collapsible 'What Do I Need on the Final?' accordion
            InkWell(
              onTap: () {
                SafeHaptics.lightImpact();
                setState(() {
                  if (isExpanded) {
                    _expandedAccordions.remove(c.id);
                  } else {
                    _expandedAccordions.add(c.id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                          size: 16,
                          color: colors.secondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'What Do I Need on the Final?',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.primary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Cutoff Targets',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (isExpanded) ...[
              const SizedBox(height: 10),
              _buildCutoffTargetsGrid(
                courseTotalMarks: item.courseTotalMarks,
                termMaxMarks: item.termMaxMarks,
                earnedTermMarks: item.earnedTermMarks,
                finalMaxMarks: item.finalMaxMarks,
                colors: colors,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownCol({
    required String label,
    required double secured,
    required double weight,
    required ChondrobinduThemeColors colors,
    required VoidCallback onEdit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 10,
              ),
            ),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(Icons.edit_rounded, size: 12, color: colors.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${secured.toStringAsFixed(1)} / ${weight.toStringAsFixed(0)}',
          style: GoogleFonts.jetBrainsMono(
            color: colors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildCutoffTargetsGrid({
    required double courseTotalMarks,
    required double termMaxMarks,
    required double earnedTermMarks,
    required double finalMaxMarks,
    required ChondrobinduThemeColors colors,
  }) {
    // Cutoff targets derived from active grading scale
    final passingRows = _gradingScale.where((r) => r.gradePoint >= 2.0 && r.minPercentage > 0).toList();
    passingRows.sort((a, b) => b.minPercentage.compareTo(a.minPercentage));

    final targets = <({String label, double cutoff, Color color})>[];
    if (passingRows.isNotEmpty) {
      final r0 = passingRows[0];
      targets.add((
        label: 'For ${r0.letterGrade} (${r0.minPercentage.toStringAsFixed(0)}%)',
        cutoff: r0.minPercentage.toDouble(),
        color: const Color(0xFF4ADE80),
      ));
      if (passingRows.length > 1) {
        final r1 = passingRows[1];
        targets.add((
          label: 'For ${r1.letterGrade} (${r1.minPercentage.toStringAsFixed(0)}%)',
          cutoff: r1.minPercentage.toDouble(),
          color: colors.primary,
        ));
      }
      if (passingRows.length > 2) {
        final r2 = passingRows[2];
        targets.add((
          label: 'For ${r2.letterGrade} (${r2.minPercentage.toStringAsFixed(0)}%)',
          cutoff: r2.minPercentage.toDouble(),
          color: colors.secondary,
        ));
      }
    }

    if (targets.isEmpty) {
      targets.addAll([
        (label: 'For A+ (80%)', cutoff: 80.0, color: const Color(0xFF4ADE80)),
        (label: 'For A (75%)', cutoff: 75.0, color: colors.primary),
        (label: 'For A- (70%)', cutoff: 70.0, color: colors.secondary),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: targets.map((t) {
          // Exact formula: requiredFinalMarks = ((targetPercent / 100) * courseTotalMarks) - earnedTermMarks
          final requiredFinalMarks = ((t.cutoff / 100.0) * courseTotalMarks) - earnedTermMarks;
          final clampedFinalMarks = requiredFinalMarks.clamp(0.0, finalMaxMarks);
          final neededFinalPct = finalMaxMarks > 0 ? (requiredFinalMarks / finalMaxMarks) * 100.0 : 0.0;
          final isSecured = requiredFinalMarks <= 0;
          final isOutOfReach = requiredFinalMarks > finalMaxMarks;

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.color.withValues(alpha: 0.25)),
              ),
              child: Column(
                children: [
                  Text(
                    t.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: t.color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isSecured)
                    Text(
                      'Already Secured ✓',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF4ADE80),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else if (isOutOfReach)
                    Column(
                      children: [
                        Text(
                          'Out of Reach',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFFEF4444),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '(Needs > ${finalMaxMarks.toStringAsFixed(0)})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        Text(
                          '${clampedFinalMarks.toStringAsFixed(1)} / ${finalMaxMarks.toStringAsFixed(0)} marks',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '(${neededFinalPct.round()}% on Final)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openScoreSimulationDialog({
    required String courseId,
    required String label,
    required double maxWeight,
    required double currentVal,
    required ValueChanged<double> onApplied,
  }) {
    final colors = AppColors.of(context);
    final controller = TextEditingController(text: currentVal.toStringAsFixed(1));

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.surfaceBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Simulate $label Marks',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Enter hypothetical score out of ${maxWeight.toStringAsFixed(0)} to test what-if scenarios.',
                style: GoogleFonts.plusJakartaSans(
                  color: colors.textMuted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: '$label (0 - ${maxWeight.toStringAsFixed(0)})',
                  labelStyle: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: colors.recessed,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.surfaceBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.surfaceBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(color: colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.secondary,
                      foregroundColor: const Color(0xFF171C24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null) {
                        onApplied(val.clamp(0.0, maxWeight));
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Apply Marks',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvisoryNote(ChondrobinduThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Academic Operating System Calibration Notice',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Course assessments follow the official university ordinance (e.g., BUET: 30% Continuous Assessment = 10% Attendance + 20% Best 3 of 4 Class Tests; 70% Term Final Written Examination). GPAs are calculated on a 4.00 discrete step scale. Toggle any course off to simulate minor term drops or credit exemptions.',
                  style: GoogleFonts.plusJakartaSans(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
