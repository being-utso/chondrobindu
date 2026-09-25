import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/routine_models.dart';
import '../models/assessment_model.dart';
import '../services/assessment_calculator.dart';
import '../services/assessment_service.dart';
import '../services/attendance_grading_service.dart';
import '../widgets/attendance_override_dialog.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Aliases for assessment screens requested by user specifications
typedef AssessmentMarksScreen = CourseAssessmentScreen;
typedef CourseAssessmentsTab = CourseAssessmentScreen;
typedef CourseAssessmentsList = CourseAssessmentScreen;
typedef TheoryAssessmentMarksScreen = CourseAssessmentScreen;

/// Dynamic Assessment & Marks Screen supporting both Theory & Sessional Courses
/// with flexible percentage weightages and "Best of N" calculation support.
class CourseAssessmentScreen extends ConsumerStatefulWidget {
  final String courseId;
  final String courseCode;
  final String courseType;

  const CourseAssessmentScreen({
    super.key,
    required this.courseId,
    this.courseCode = '',
    required this.courseType,
  });

  @override
  ConsumerState<CourseAssessmentScreen> createState() => _CourseAssessmentScreenState();
}

class _CourseAssessmentScreenState extends ConsumerState<CourseAssessmentScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;

  // Real-time Attendance Tracker state synced from AttendanceRecord
  int _liveAttendedCount = 0;
  int _liveTotalHeld = 0;

  // ----------------------------------------------------
  // ATTENDANCE WEIGHTAGE & BULK OVERRIDE (TASK 1 & 3)
  // ----------------------------------------------------
  late TextEditingController _attendanceWeightageController;
  bool _useManualAttendanceOverride = false;
  int? _manualAttendedClasses;
  int? _manualTotalClasses;
  List<AttendanceMarkSlab> _attendanceSlabs = List.from(AttendanceGradingService.defaultSlabs);

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1) % 12];
  }

  // ----------------------------------------------------
  // THEORY CATEGORIES (CTs, Midterm, Final)
  // ----------------------------------------------------
  List<AssessmentItem> _classTests = [];
  late TextEditingController _ctWeightageController;
  bool _ctUseBestOf = true;
  late TextEditingController _ctBestCountController;

  late TextEditingController _midtermObtainedController;
  late TextEditingController _midtermTotalController;
  late TextEditingController _midtermWeightageController;

  late TextEditingController _finalObtainedController;
  late TextEditingController _finalTotalController;
  late TextEditingController _finalWeightageController;

  // ----------------------------------------------------
  // SESSIONAL / LAB DEDICATED CATEGORIES
  // ----------------------------------------------------
  List<AssessmentItem> _quizzesViva = [];
  late TextEditingController _quizzesWeightageController;
  bool _quizzesUseBestOf = false;
  late TextEditingController _quizzesBestCountController;

  List<AssessmentItem> _labReportsAssignments = [];
  late TextEditingController _labReportsWeightageController;
  bool _labReportsUseBestOf = false;
  late TextEditingController _labReportsBestCountController;

  List<AssessmentItem> _labFinalPractical = [];
  late TextEditingController _labFinalWeightageController;
  bool _labFinalUseBestOf = false;
  late TextEditingController _labFinalBestCountController;

  List<AssessmentItem> _continuousAssessment = [];
  late TextEditingController _continuousWeightageController;
  bool _continuousUseBestOf = false;
  late TextEditingController _continuousBestCountController;

  bool get isSessionalOrLab =>
      widget.courseType.toLowerCase().contains('sessional') ||
      widget.courseType.toLowerCase().contains('lab');

  bool get isTheory => !isSessionalOrLab;
  double _whatIfPendingScorePercent = 75.0;

  @override
  void initState() {
    super.initState();
    // Attendance initializations
    _attendanceWeightageController = TextEditingController(text: '10');

    // Theory initializations
    _ctWeightageController = TextEditingController(text: '20');
    _ctBestCountController = TextEditingController(text: '3');
    _midtermObtainedController = TextEditingController(text: '0');
    _midtermTotalController = TextEditingController(text: '30');
    _midtermWeightageController = TextEditingController(text: '30');
    _finalObtainedController = TextEditingController(text: '0');
    _finalTotalController = TextEditingController(text: '210');
    _finalWeightageController = TextEditingController(text: '50');

    // Sessional initializations
    _quizzesWeightageController = TextEditingController(text: '20');
    _quizzesBestCountController = TextEditingController(text: '2');
    _labReportsWeightageController = TextEditingController(text: '30');
    _labReportsBestCountController = TextEditingController(text: '3');
    _labFinalWeightageController = TextEditingController(text: '30');
    _labFinalBestCountController = TextEditingController(text: '1');
    _continuousWeightageController = TextEditingController(text: '20');
    _continuousBestCountController = TextEditingController(text: '1');

    _loadAssessmentData();
    _initAssessmentStream();
  }

  StreamSubscription<List<Assessment>>? _assessmentStreamSub;

  void _initAssessmentStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || widget.courseId.isEmpty) return;

    _assessmentStreamSub = AssessmentService()
        .getAssessmentsStream(uid: uid, courseId: widget.courseId)
        .listen((assessments) {
      if (!mounted) return;
      _mergeStreamedAssessments(assessments);
    });
  }

  void _mergeStreamedAssessments(List<Assessment> assessments) {
    if (assessments.isEmpty && _classTests.isNotEmpty) return;

    final streamedCts = assessments
        .where((a) => a.type == 'ct' || a.name.toLowerCase().startsWith('ct'))
        .toList();

    if (streamedCts.isEmpty && _classTests.isEmpty) return;

    final List<Assessment> updated = List.from(_classTests);

    for (final sAss in streamedCts) {
      final idx = updated.indexWhere((c) => c.name.toLowerCase() == sAss.name.toLowerCase() || c.id == sAss.id);
      if (idx >= 0) {
        final cur = updated[idx];
        updated[idx] = cur.copyWith(
          id: sAss.id,
          date: sAss.date ?? cur.date,
          status: sAss.status,
          syllabusSummary: sAss.syllabusSummary ?? cur.syllabusSummary,
          obtainedMarks: cur.isRecorded ? cur.obtainedMarks : sAss.obtainedMarks,
          totalMarks: cur.totalMarks,
          weightage: sAss.weightage,
        );
      } else {
        updated.add(sAss);
      }
    }

    // Auto-backfill preceding CTs if a higher CT exists
    int maxCtNum = 0;
    final Set<int> existingCtNums = {};
    for (final ct in updated) {
      final match = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(ct.name);
      if (match != null) {
        final n = int.tryParse(match.group(1) ?? '');
        if (n != null) {
          existingCtNums.add(n);
          if (n > maxCtNum) maxCtNum = n;
        }
      }
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    for (int i = 1; i < maxCtNum; i++) {
      if (!existingCtNums.contains(i)) {
        final backfilled = Assessment(
          courseId: widget.courseId,
          name: 'CT $i',
          type: 'ct',
          date: null,
          totalMarks: 20.0,
          obtainedMarks: null,
          weightage: double.tryParse(_ctWeightageController.text.trim()) ?? 10.0,
          status: 'Pending',
        );
        updated.add(backfilled);
        existingCtNums.add(i);

        if (uid != null) {
          try {
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('courses')
                .doc(widget.courseId)
                .collection('assessments')
                .doc(backfilled.id)
                .set(backfilled.toMap(), SetOptions(merge: true));
          } catch (_) {}
        }
      }
    }

    // Sort sequentially (CT 1, CT 2, CT 3, ...)
    updated.sort((a, b) {
      final matchA = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(a.name);
      final matchB = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(b.name);
      final numA = matchA != null ? int.tryParse(matchA.group(1) ?? '') ?? 999 : 999;
      final numB = matchB != null ? int.tryParse(matchB.group(1) ?? '') ?? 999 : 999;
      return numA.compareTo(numB);
    });

    setState(() {
      _classTests = updated;
    });
  }

  @override
  void dispose() {
    _assessmentStreamSub?.cancel();
    _attendanceWeightageController.dispose();
    _ctWeightageController.dispose();
    _ctBestCountController.dispose();
    _midtermObtainedController.dispose();
    _midtermTotalController.dispose();
    _midtermWeightageController.dispose();
    _finalObtainedController.dispose();
    _finalTotalController.dispose();
    _finalWeightageController.dispose();

    _quizzesWeightageController.dispose();
    _quizzesBestCountController.dispose();
    _labReportsWeightageController.dispose();
    _labReportsBestCountController.dispose();
    _labFinalWeightageController.dispose();
    _labFinalBestCountController.dispose();
    _continuousWeightageController.dispose();
    _continuousBestCountController.dispose();
    super.dispose();
  }

  /// Load initial assessment data from Firestore
  Future<void> _loadAssessmentData() async {
    setState(() => _isLoading = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(widget.courseId)
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _useManualAttendanceOverride = data['useManualAttendanceOverride'] as bool? ?? false;
        _manualAttendedClasses = (data['manualAttendedClasses'] as num?)?.toInt();
        _manualTotalClasses = (data['manualTotalClasses'] as num?)?.toInt();

        Map<String, dynamic>? rawAssessments;
        final rawAssData = data['assessments'];
        if (rawAssData is Map<String, dynamic>) {
          rawAssessments = rawAssData;
        } else if (rawAssData is Map) {
          rawAssessments = Map<String, dynamic>.from(rawAssData);
        }

        if (rawAssessments != null) {
          _attendanceWeightageController.text =
              ((rawAssessments['attendanceWeightage'] as num?)?.toDouble() ?? 10.0).toStringAsFixed(0);
          _liveAttendedCount = (rawAssessments['classesAttended'] as num?)?.toInt() ?? 0;
          _liveTotalHeld = (rawAssessments['totalClasses'] as num?)?.toInt() ?? 0;
          _attendanceSlabs = AttendanceGradingService.parseSlabs(rawAssessments['attendanceSlabs']);

          // Load Theory CTs & Weightages
          final rawCts = rawAssessments['classTests'] as List<dynamic>?;
          List<Assessment> loadedCts = [];
          if (rawCts != null) {
            loadedCts = rawCts
                .map((item) => Assessment.fromMap(Map<String, dynamic>.from(item), defaultCourseId: widget.courseId))
                .toList();
          }

          // Also merge any CTs scheduled via Planner from the course's assessments subcollection
          try {
            final subSnap = await FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('courses')
                .doc(widget.courseId)
                .collection('assessments')
                .get();

            for (final doc in subSnap.docs) {
              final ass = Assessment.fromMap(doc.data(), defaultCourseId: widget.courseId);
              if (ass.type == 'ct' || ass.name.toLowerCase().startsWith('ct')) {
                final existingIdx = loadedCts.indexWhere((c) => c.name.toLowerCase() == ass.name.toLowerCase());
                if (existingIdx >= 0) {
                  final cur = loadedCts[existingIdx];
                  if (cur.date == null && ass.date != null) {
                    loadedCts[existingIdx] = cur.copyWith(
                      date: ass.date,
                      status: ass.status,
                      syllabusSummary: ass.syllabusSummary,
                      obtainedMarks: cur.obtainedMarks ?? ass.obtainedMarks,
                    );
                  }
                } else {
                  loadedCts.add(ass);
                }
              }
            }
          } catch (e) {
            debugPrint('Error syncing subcollection assessments: $e');
          }

          // Auto-backfill preceding CTs if a higher CT exists
          int maxCtNum = 0;
          final Set<int> existingCtNums = {};
          for (final ct in loadedCts) {
            final match = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(ct.name);
            if (match != null) {
              final n = int.tryParse(match.group(1) ?? '');
              if (n != null) {
                existingCtNums.add(n);
                if (n > maxCtNum) maxCtNum = n;
              }
            }
          }

          for (int i = 1; i < maxCtNum; i++) {
            if (!existingCtNums.contains(i)) {
              final backfilled = Assessment(
                courseId: widget.courseId,
                name: 'CT $i',
                type: 'ct',
                date: null,
                totalMarks: 20.0,
                obtainedMarks: null,
                weightage: double.tryParse(_ctWeightageController.text.trim()) ?? 10.0,
                status: 'Pending',
              );
              loadedCts.add(backfilled);
              existingCtNums.add(i);

              try {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('courses')
                    .doc(widget.courseId)
                    .collection('assessments')
                    .doc(backfilled.id)
                    .set(backfilled.toMap(), SetOptions(merge: true));
              } catch (_) {}
            }
          }

          // Sort CTs by their sequence number
          loadedCts.sort((a, b) {
            final matchA = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(a.name);
            final matchB = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(b.name);
            final numA = matchA != null ? int.tryParse(matchA.group(1) ?? '') ?? 999 : 999;
            final numB = matchB != null ? int.tryParse(matchB.group(1) ?? '') ?? 999 : 999;
            return numA.compareTo(numB);
          });

          _classTests = loadedCts;

          _ctWeightageController.text =
              ((rawAssessments['ctWeightage'] as num?)?.toDouble() ?? 20.0).toStringAsFixed(0);
          _ctUseBestOf = rawAssessments['ctUseBestOf'] as bool? ??
              (rawAssessments['dropLowestCt'] as bool? ?? true);
          _ctBestCountController.text =
              ((rawAssessments['ctBestCount'] as num?)?.toInt() ?? 3).toString();

          _midtermObtainedController.text =
              ((rawAssessments['midtermObtained'] as num?)?.toDouble() ?? 0.0).toString();
          _midtermTotalController.text =
              ((rawAssessments['midtermTotal'] as num?)?.toDouble() ?? 30.0).toString();
          _midtermWeightageController.text =
              ((rawAssessments['midtermWeightage'] as num?)?.toDouble() ?? 30.0).toStringAsFixed(0);

          _finalObtainedController.text =
              ((rawAssessments['finalObtained'] as num?)?.toDouble() ?? 0.0).toString();
          _finalTotalController.text =
              ((rawAssessments['finalTotal'] as num?)?.toDouble() ?? 210.0).toString();
          _finalWeightageController.text =
              ((rawAssessments['finalWeightage'] as num?)?.toDouble() ?? 50.0).toStringAsFixed(0);

          // Load Sessional / Lab Categories
          final rawQuizzesViva = rawAssessments['quizzesViva'] as List<dynamic>?;
          if (rawQuizzesViva != null) {
            _quizzesViva = rawQuizzesViva
                .map((item) => AssessmentItem.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          } else if (rawAssessments['vivaObtained'] != null) {
            final vObt = (rawAssessments['vivaObtained'] as num?)?.toDouble() ?? 0.0;
            final vTot = (rawAssessments['vivaTotal'] as num?)?.toDouble() ?? 50.0;
            _quizzesViva = [AssessmentItem(name: 'Viva / Quiz 1', obtained: vObt, total: vTot)];
          }

          _quizzesWeightageController.text =
              ((rawAssessments['quizzesWeightage'] as num?)?.toDouble() ?? 20.0).toStringAsFixed(0);
          _quizzesUseBestOf = rawAssessments['quizzesUseBestOf'] as bool? ?? false;
          _quizzesBestCountController.text =
              ((rawAssessments['quizzesBestCount'] as num?)?.toInt() ?? 2).toString();

          final rawLabReports = rawAssessments['labReportsAssignments'] as List<dynamic>? ??
              rawAssessments['labReports'] as List<dynamic>?;
          if (rawLabReports != null) {
            _labReportsAssignments = rawLabReports
                .map((item) => AssessmentItem.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          }

          _labReportsWeightageController.text =
              ((rawAssessments['labReportsWeightage'] as num?)?.toDouble() ?? 30.0).toStringAsFixed(0);
          _labReportsUseBestOf = rawAssessments['labReportsUseBestOf'] as bool? ?? false;
          _labReportsBestCountController.text =
              ((rawAssessments['labReportsBestCount'] as num?)?.toInt() ?? 3).toString();

          final rawLabFinal = rawAssessments['labFinalPractical'] as List<dynamic>?;
          if (rawLabFinal != null) {
            _labFinalPractical = rawLabFinal
                .map((item) => AssessmentItem.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          }

          _labFinalWeightageController.text =
              ((rawAssessments['labFinalWeightage'] as num?)?.toDouble() ?? 30.0).toStringAsFixed(0);
          _labFinalUseBestOf = rawAssessments['labFinalUseBestOf'] as bool? ?? false;
          _labFinalBestCountController.text =
              ((rawAssessments['labFinalBestCount'] as num?)?.toInt() ?? 1).toString();

          final rawContinuous = rawAssessments['continuousAssessment'] as List<dynamic>?;
          if (rawContinuous != null) {
            _continuousAssessment = rawContinuous
                .map((item) => AssessmentItem.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          }

          _continuousWeightageController.text =
              ((rawAssessments['continuousWeightage'] as num?)?.toDouble() ?? 20.0).toStringAsFixed(0);
          _continuousUseBestOf = rawAssessments['continuousUseBestOf'] as bool? ?? false;
          _continuousBestCountController.text =
              ((rawAssessments['continuousBestCount'] as num?)?.toInt() ?? 1).toString();
        }
      }
    } catch (e) {
      debugPrint('Error loading assessment data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Open Attendance Settings & Manual Override Dialog
  void _openAttendanceOverrideDialog(
    BuildContext context, {
    int calendarAttended = 0,
    int calendarTotal = 0,
  }) {
    SafeHaptics.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AttendanceOverrideDialog(
        courseId: widget.courseId,
        courseCode: widget.courseCode,
        calendarAttended: calendarAttended,
        calendarTotal: calendarTotal,
        currentlyUsingOverride: _useManualAttendanceOverride,
        existingManualAttended: _manualAttendedClasses,
        existingManualTotal: _manualTotalClasses,
        onSaved: () {
          _loadAssessmentData();
          setState(() {});
        },
      ),
    );
  }

  void _showEditWeightageDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController(text: _attendanceWeightageController.text);
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1412),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF382A24)),
          ),
          title: Text(
            'Attendance Weightage',
            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the overall course percentage weightage for attendance (e.g., 10% or 8%):',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF241C1A),
                  suffixText: '%',
                  suffixStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFFF2B78A), fontWeight: FontWeight.bold),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4A3830))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFF2B78A))),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text.trim());
                if (val != null && val >= 0) {
                  setState(() {
                    _attendanceWeightageController.text = ctrl.text.trim();
                  });
                  _saveAssessmentData(silent: true);
                }
                Navigator.pop(ctx);
              },
              child: Text('Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttendanceStatTile({
    required String label,
    required String value,
    required String sublabel,
    bool highlight = false,
    VoidCallback? onTap,
  }) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFF2B78A).withValues(alpha: 0.08) : const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFFF2B78A).withValues(alpha: 0.3) : const Color(0xFF382A24),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFABA093),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              color: highlight ? const Color(0xFFF2B78A) : Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            sublabel,
            style: GoogleFonts.plusJakartaSans(
              color: highlight ? const Color(0xFFF2B78A).withValues(alpha: 0.8) : const Color(0xFF7E726B),
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      );
    }
    return tile;
  }

  /// Save all current assessment state to Firestore
  Future<void> _saveAssessmentData({bool silent = false}) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('User authentication required.'),
        ),
      );
      setState(() => _isSaving = false);
      return;
    }

    try {
      final attendanceWeight = double.tryParse(_attendanceWeightageController.text.trim()) ?? 10.0;
      final ctWeight = double.tryParse(_ctWeightageController.text.trim()) ?? 20.0;
      final ctBestCount = int.tryParse(_ctBestCountController.text.trim()) ?? 3;

      final midtermObtained = double.tryParse(_midtermObtainedController.text.trim()) ?? 0.0;
      final midtermTotal = double.tryParse(_midtermTotalController.text.trim()) ?? 30.0;
      final midtermWeight = double.tryParse(_midtermWeightageController.text.trim()) ?? 30.0;

      final finalObtained = double.tryParse(_finalObtainedController.text.trim()) ?? 0.0;
      final finalTotal = double.tryParse(_finalTotalController.text.trim()) ?? 210.0;
      final finalWeight = double.tryParse(_finalWeightageController.text.trim()) ?? 50.0;

      final quizzesWeight = double.tryParse(_quizzesWeightageController.text.trim()) ?? 20.0;
      final quizzesBestCount = int.tryParse(_quizzesBestCountController.text.trim()) ?? 2;

      final labReportsWeight = double.tryParse(_labReportsWeightageController.text.trim()) ?? 30.0;
      final labReportsBestCount = int.tryParse(_labReportsBestCountController.text.trim()) ?? 3;

      final labFinalWeight = double.tryParse(_labFinalWeightageController.text.trim()) ?? 30.0;
      final labFinalBestCount = int.tryParse(_labFinalBestCountController.text.trim()) ?? 1;

      final continuousWeight = double.tryParse(_continuousWeightageController.text.trim()) ?? 20.0;
      final continuousBestCount = int.tryParse(_continuousBestCountController.text.trim()) ?? 1;

      // Compute current predicted grade for persistence
      final gradeResult = _computeOverallPredictedGrade();

      final Map<String, dynamic> assessmentMap = {
        'attendanceWeightage': attendanceWeight,
        'classesAttended': _liveAttendedCount,
        'totalClasses': _liveTotalHeld > 0 ? _liveTotalHeld : 30,

        // Theory Fields
        'dropLowestCt': _ctUseBestOf,
        'ctUseBestOf': _ctUseBestOf,
        'ctBestCount': ctBestCount,
        'ctWeightage': ctWeight,
        'classTests': _classTests.map((ct) => ct.toMap()).toList(),
        'midtermObtained': midtermObtained,
        'midtermTotal': midtermTotal,
        'midtermWeightage': midtermWeight,
        'finalObtained': finalObtained,
        'finalTotal': finalTotal,
        'finalWeightage': finalWeight,

        // Sessional Categories
        'quizzesViva': _quizzesViva.map((item) => item.toMap()).toList(),
        'quizzesWeightage': quizzesWeight,
        'quizzesUseBestOf': _quizzesUseBestOf,
        'quizzesBestCount': quizzesBestCount,

        'labReportsAssignments': _labReportsAssignments.map((item) => item.toMap()).toList(),
        'labReports': _labReportsAssignments.map((item) => item.toMap()).toList(),
        'labReportsWeightage': labReportsWeight,
        'labReportsUseBestOf': _labReportsUseBestOf,
        'labReportsBestCount': labReportsBestCount,

        'labFinalPractical': _labFinalPractical.map((item) => item.toMap()).toList(),
        'labFinalWeightage': labFinalWeight,
        'labFinalUseBestOf': _labFinalUseBestOf,
        'labFinalBestCount': labFinalBestCount,

        'continuousAssessment': _continuousAssessment.map((item) => item.toMap()).toList(),
        'continuousWeightage': continuousWeight,
        'continuousUseBestOf': _continuousUseBestOf,
        'continuousBestCount': continuousBestCount,

        // Attendance Slabs (Step-based)
        'attendanceSlabs': _attendanceSlabs.map((s) => s.toMap()).toList(),

        // Computed stats
        'predictedGrade': gradeResult.letterGrade,
        'predictedCgpa': gradeResult.gradePoint,
        'totalWeightedScore': gradeResult.totalWeightedScore,
        'normalizedPercentage': gradeResult.normalizedPercentage,

        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(widget.courseId)
          .set({'assessments': assessmentMap}, SetOptions(merge: true));

      // Synchronize all assessment categories into subcollection so Planner/Calendar gets updated immediately
      final allToSync = [
        ..._classTests,
        ..._quizzesViva,
        ..._labReportsAssignments,
        ..._labFinalPractical,
        ..._continuousAssessment,
      ];
      for (final item in allToSync) {
        try {
          final itemMap = item.toMap();
          itemMap['userId'] = uid;
          itemMap['courseId'] = widget.courseId;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('courses')
              .doc(widget.courseId)
              .collection('assessments')
              .doc(item.id)
              .set(itemMap, SetOptions(merge: true));
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isSaving = false);
        if (!silent) {
          SafeHaptics.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Assessment marks saved! Predicted: ${gradeResult.letterGrade} (${gradeResult.gradePoint.toStringAsFixed(2)})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving assessment data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to save assessment marks: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _addClassTestRow() {
    SafeHaptics.lightImpact();
    setState(() {
      int nextNum = 1;
      for (final ct in _classTests) {
        final match = RegExp(r'CT\s*(\d+)', caseSensitive: false).firstMatch(ct.name);
        if (match != null) {
          final n = int.tryParse(match.group(1) ?? '') ?? 0;
          if (n >= nextNum) nextNum = n + 1;
        }
      }
      _classTests.add(Assessment(
        courseId: widget.courseId,
        name: 'CT $nextNum',
        type: 'ct',
        totalMarks: 20.0,
        obtainedMarks: null,
        weightage: double.tryParse(_ctWeightageController.text.trim()) ?? 10.0,
        status: 'Pending',
      ));
      if (_ctUseBestOf && _classTests.length > 3) {
        _ctBestCountController.text = '${_classTests.length - 1}';
      }
    });
  }

  void _addQuizVivaRow() {
    SafeHaptics.lightImpact();
    setState(() {
      final num = _quizzesViva.length + 1;
      _quizzesViva.add(AssessmentItem(name: 'Quiz/Viva $num', obtainedMarks: null, totalMarks: 20.0, status: 'Pending'));
    });
  }

  void _addLabReportAssignmentRow() {
    SafeHaptics.lightImpact();
    setState(() {
      final num = _labReportsAssignments.length + 1;
      _labReportsAssignments.add(AssessmentItem(name: 'Report $num', obtainedMarks: null, totalMarks: 10.0, status: 'Pending'));
    });
  }

  void _addLabFinalPracticalRow() {
    SafeHaptics.lightImpact();
    setState(() {
      final num = _labFinalPractical.length + 1;
      _labFinalPractical.add(AssessmentItem(name: 'Final $num', obtainedMarks: null, totalMarks: 50.0, status: 'Pending'));
    });
  }

  void _addContinuousAssessmentRow() {
    SafeHaptics.lightImpact();
    setState(() {
      final num = _continuousAssessment.length + 1;
      _continuousAssessment.add(AssessmentItem(name: 'Performance $num', obtainedMarks: null, totalMarks: 10.0, status: 'Pending'));
    });
  }

  /// Calculates overall predicted grade result across active categories
  PredictedGradeResult _computeOverallPredictedGrade() {
    // Attendance Weightage for CGPA via Step-tier Slabs
    final attWeight = double.tryParse(_attendanceWeightageController.text.trim()) ?? 10.0;
    final attPercentage = _liveTotalHeld > 0 ? (_liveAttendedCount / _liveTotalHeld) * 100.0 : 100.0;
    final attEarnedMarks = AttendanceGradingService.calculateAttendanceMarks(
      attendanceRate: attPercentage,
      attendanceWeightage: attWeight,
      customSlabs: _attendanceSlabs,
    );
    final attResult = CategoryCalculationResult(
      obtained: attEarnedMarks,
      total: attWeight,
      percentage: attPercentage,
      weightedScore: attEarnedMarks,
      weightage: attWeight,
      useBestOf: false,
      bestCount: 1,
      totalItems: _liveTotalHeld,
      countedItems: _liveAttendedCount,
      activeItems: const [],
    );

    if (isTheory) {
      final ctWeight = double.tryParse(_ctWeightageController.text.trim()) ?? 20.0;
      final ctBestCount = int.tryParse(_ctBestCountController.text.trim()) ?? 3;
      final ctResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _classTests,
        weightagePercentage: ctWeight,
        useBestOf: _ctUseBestOf,
        bestCount: ctBestCount,
      );

      final midObt = double.tryParse(_midtermObtainedController.text.trim()) ?? 0.0;
      final midTot = double.tryParse(_midtermTotalController.text.trim()) ?? 30.0;
      final midWeight = double.tryParse(_midtermWeightageController.text.trim()) ?? 30.0;
      final midResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: [AssessmentItem(name: 'Midterm', obtained: midObt, total: midTot)],
        weightagePercentage: midWeight,
      );

      final finObt = double.tryParse(_finalObtainedController.text.trim()) ?? 0.0;
      final finTot = double.tryParse(_finalTotalController.text.trim()) ?? 210.0;
      final finWeight = double.tryParse(_finalWeightageController.text.trim()) ?? 50.0;
      final finResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: [AssessmentItem(name: 'Final', obtained: finObt, total: finTot)],
        weightagePercentage: finWeight,
      );

      return AssessmentCalculationHelper.calculatePredictedGrade(
        categoryResults: [attResult, ctResult, midResult, finResult],
      );
    } else {
      final quizzesWeight = double.tryParse(_quizzesWeightageController.text.trim()) ?? 20.0;
      final quizzesBestCount = int.tryParse(_quizzesBestCountController.text.trim()) ?? 2;
      final quizzesResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _quizzesViva,
        weightagePercentage: quizzesWeight,
        useBestOf: _quizzesUseBestOf,
        bestCount: quizzesBestCount,
      );

      final labReportsWeight = double.tryParse(_labReportsWeightageController.text.trim()) ?? 30.0;
      final labReportsBestCount = int.tryParse(_labReportsBestCountController.text.trim()) ?? 3;
      final labReportsResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _labReportsAssignments,
        weightagePercentage: labReportsWeight,
        useBestOf: _labReportsUseBestOf,
        bestCount: labReportsBestCount,
      );

      final labFinalWeight = double.tryParse(_labFinalWeightageController.text.trim()) ?? 30.0;
      final labFinalBestCount = int.tryParse(_labFinalBestCountController.text.trim()) ?? 1;
      final labFinalResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _labFinalPractical,
        weightagePercentage: labFinalWeight,
        useBestOf: _labFinalUseBestOf,
        bestCount: labFinalBestCount,
      );

      final continuousWeight = double.tryParse(_continuousWeightageController.text.trim()) ?? 20.0;
      final continuousBestCount = int.tryParse(_continuousBestCountController.text.trim()) ?? 1;
      final continuousResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _continuousAssessment,
        weightagePercentage: continuousWeight,
        useBestOf: _continuousUseBestOf,
        bestCount: continuousBestCount,
      );

      return AssessmentCalculationHelper.calculatePredictedGrade(
        categoryResults: [attResult, quizzesResult, labReportsResult, labFinalResult, continuousResult],
      );
    }
  }

  Color _getGradeColor(String letterGrade) {
    if (letterGrade.startsWith('A')) return const Color(0xFF10B981);
    if (letterGrade.startsWith('B')) return const Color(0xFFF2B78A);
    if (letterGrade.startsWith('C')) return const Color(0xFFF59E0B);
    if (letterGrade.startsWith('D')) return const Color(0xFFFB923C);
    return const Color(0xFFEF4444);
  }

  Widget _buildWhatIfSimulationCard(Color cardColor, Color accentColor) {
    // 1. Calculate secured marks vs pending weight
    final attWeight = double.tryParse(_attendanceWeightageController.text.trim()) ?? 10.0;
    final attRate = _liveTotalHeld > 0 ? (_liveAttendedCount / _liveTotalHeld) * 100.0 : 100.0;
    final attSecured = AttendanceGradingService.calculateAttendanceMarks(
      attendanceRate: attRate,
      attendanceWeightage: attWeight,
      customSlabs: _attendanceSlabs,
    );

    double ctSecured = 0.0;
    double ctWeight = 0.0;
    double otherSecured = 0.0;
    double otherWeight = 0.0;

    if (isTheory) {
      ctWeight = double.tryParse(_ctWeightageController.text.trim()) ?? 20.0;
      final ctResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _classTests,
        weightagePercentage: ctWeight,
        useBestOf: _ctUseBestOf,
        bestCount: int.tryParse(_ctBestCountController.text.trim()) ?? 3,
      );
      if (_classTests.isNotEmpty) {
        ctSecured = ctResult.weightedScore;
      }

      final midObt = double.tryParse(_midtermObtainedController.text.trim()) ?? 0.0;
      final midTot = double.tryParse(_midtermTotalController.text.trim()) ?? 30.0;
      final midWeight = double.tryParse(_midtermWeightageController.text.trim()) ?? 30.0;
      if (midObt > 0) {
        otherSecured = (midObt / midTot) * midWeight;
        otherWeight = midWeight;
      }
    } else {
      ctWeight = double.tryParse(_quizzesWeightageController.text.trim()) ?? 20.0;
      final quizResult = AssessmentCalculationHelper.calculateCategoryScore(
        items: _quizzesViva,
        weightagePercentage: ctWeight,
        useBestOf: _quizzesUseBestOf,
        bestCount: int.tryParse(_quizzesBestCountController.text.trim()) ?? 2,
      );
      if (_quizzesViva.isNotEmpty) {
        ctSecured = quizResult.weightedScore;
      }
    }

    final finTot = double.tryParse(_finalTotalController.text.trim()) ?? 210.0;

    final evaluatedSecured = attSecured + ctSecured + otherSecured;
    final evaluatedWeight = attWeight + ctWeight + otherWeight;
    final pendingWeight = (100.0 - evaluatedWeight).clamp(0.0, 100.0);

    // Final Exam score calculation
    final simulatedFinalPercent = _whatIfPendingScorePercent;
    final simulatedFinalExamMarks = (simulatedFinalPercent / 100.0) * finTot;
    final simulatedFinalWeighted = (simulatedFinalPercent / 100.0) * pendingWeight;

    final projectedTotal = (evaluatedSecured + simulatedFinalWeighted).clamp(0.0, 100.0);
    final projectedGrade = AssessmentCalculationHelper.percentageToGrade(projectedTotal);

    final targets = [
      {'grade': 'A+', 'point': 4.00, 'cutoff': 80.0},
      {'grade': 'A', 'point': 3.75, 'cutoff': 75.0},
      {'grade': 'A-', 'point': 3.50, 'cutoff': 70.0},
      {'grade': 'B+', 'point': 3.25, 'cutoff': 65.0},
      {'grade': 'B', 'point': 3.00, 'cutoff': 60.0},
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_graph_rounded, color: Color(0xFF8B5CF6), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Course Grade Projector',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Simulate Final Exam & pending assessments in real time',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Overview stats with real-time projected letter grade and course GPA
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF170F0D),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text('Secured Marks', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '${evaluatedSecured.toStringAsFixed(1)} / ${evaluatedWeight.toStringAsFixed(0)}',
                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
                Container(width: 1, height: 28, color: Colors.white12),
                Column(
                  children: [
                    const Text('Projected Total', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '${projectedTotal.toStringAsFixed(1)}%',
                      style: const TextStyle(color: Color(0xFFF2B78A), fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
                Container(width: 1, height: 28, color: Colors.white12),
                Column(
                  children: [
                    const Text('Course GPA', style: TextStyle(color: Colors.white54, fontSize: 11)),
                    const SizedBox(height: 3),
                    Text(
                      '${projectedGrade.letterGrade} (${projectedGrade.gradePoint.toStringAsFixed(2)})',
                      style: TextStyle(color: _getGradeColor(projectedGrade.letterGrade), fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Breakdown pills: Secured Attendance + Secured CT + Projected Final
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildProjectionPill('Attendance', '${attSecured.toStringAsFixed(1)} pts', const Color(0xFF10B981)),
                const SizedBox(width: 6),
                const Text('+', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                _buildProjectionPill(isTheory ? 'CT Scores' : 'Quizzes', '${ctSecured.toStringAsFixed(1)} pts', const Color(0xFFF2B78A)),
                const SizedBox(width: 6),
                const Text('+', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                _buildProjectionPill('Final Exam', '${simulatedFinalWeighted.toStringAsFixed(1)} pts', const Color(0xFF8B5CF6)),
                const SizedBox(width: 6),
                const Text('=', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                _buildProjectionPill('Total', '${projectedTotal.toStringAsFixed(1)}%', _getGradeColor(projectedGrade.letterGrade)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Dynamic Slider for Projected Final Exam Score
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Projected Final Exam Score:',
                style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Text(
                '${simulatedFinalExamMarks.toStringAsFixed(1)} / ${finTot.toStringAsFixed(0)} Marks (${simulatedFinalPercent.toStringAsFixed(0)}%)',
                style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: const Color(0xFF8B5CF6),
              inactiveTrackColor: Colors.white12,
              thumbColor: const Color(0xFF8B5CF6),
              overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
            ),
            child: Slider(
              value: _whatIfPendingScorePercent,
              min: 0.0,
              max: 100.0,
              divisions: 100,
              onChanged: (val) {
                setState(() {
                  _whatIfPendingScorePercent = val;
                });
              },
            ),
          ),
          const SizedBox(height: 6),

          // Target Grade Threshold Matrix
          const Text(
            'Target Grade Threshold Matrix:',
            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...targets.map((t) {
            final cutoff = t['cutoff'] as double;
            final reqPercent = pendingWeight > 0
                ? ((cutoff - evaluatedSecured) / pendingWeight) * 100.0
                : 0.0;

            final isSecured = reqPercent <= 0;
            final isImpossible = reqPercent > 100;
            final badgeColor = isSecured
                ? const Color(0xFF10B981)
                : (isImpossible ? const Color(0xFFEF4444) : const Color(0xFFF2B78A));

            final statusText = isSecured
                ? 'Secured ✓'
                : (isImpossible
                    ? 'Impossible (>100%)'
                    : 'Need ${reqPercent.toStringAsFixed(1)}% on remaining');

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF170F0D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: _getGradeColor(t['grade'] as String).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        t['grade'] as String,
                        style: TextStyle(
                          color: _getGradeColor(t['grade'] as String),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${cutoff.toStringAsFixed(0)}% (${(t['point'] as double).toStringAsFixed(2)})',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  Widget _buildProjectionPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const successColor = Color(0xFF10B981);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final predictedGrade = _computeOverallPredictedGrade();
    final gradeColor = _getGradeColor(predictedGrade.letterGrade);

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
          'Assessment & Marks (${widget.courseType})',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: AppPreloader(size: 44),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ==========================================
                      // 1. ATTENDANCE GRADING CARD & CGPA WEIGHTAGE (TASK 1 & 3)
                      // ==========================================
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .collection('attendance_records')
                            .snapshots(),
                        builder: (context, attSnap) {
                          final attDocs = attSnap.data?.docs ?? [];
                          final allRecords = attDocs
                              .map((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id))
                              .toList();
                          final records = allRecords
                              .where((rec) => RoutineCourseSyncService.recordMatchesCourse(
                                    record: rec,
                                    courseId: widget.courseId,
                                    courseCode: widget.courseCode,
                                  ))
                              .toList();
                          final rawCalendarStats = AttendanceStats.fromRecords(records);
                          final attStats = RoutineCourseSyncService.computeCourseAttendance(
                            courseRecords: records,
                            useManualAttendanceOverride: _useManualAttendanceOverride,
                            manualAttendedClasses: _manualAttendedClasses,
                            manualTotalClasses: _manualTotalClasses,
                          );

                          final attendedCount = attStats.attended;
                          final totalHeld = attStats.totalClasses;
                          final double attendanceRate = totalHeld > 0
                              ? ((attendedCount / totalHeld) * 100.0).clamp(0.0, 100.0)
                              : 100.0;
                          final bool isSafe = attendanceRate >= 75.0;
                          final statusColor = totalHeld == 0
                              ? const Color(0xFF94A3B8)
                              : (isSafe ? successColor : const Color(0xFFEF4444));

                          _liveAttendedCount = attendedCount;
                          _liveTotalHeld = totalHeld;

                          final attWeight = double.tryParse(_attendanceWeightageController.text.trim()) ?? 10.0;
                          final earnedMarks = AttendanceGradingService.calculateAttendanceMarks(
                            attendanceRate: attendanceRate,
                            attendanceWeightage: attWeight,
                            customSlabs: _attendanceSlabs,
                          );

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1412),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF3D2D26), width: 0.8),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header Row: Icon + Title + Tune Button
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.co_present_rounded, color: Color(0xFFF2B78A), size: 18),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Attendance Grading',
                                              style: GoogleFonts.plusJakartaSans(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14.5,
                                              ),
                                            ),
                                            Text(
                                              _useManualAttendanceOverride
                                                  ? 'Manual bulk override active'
                                                  : 'Synced with daily routine',
                                              style: GoogleFonts.plusJakartaSans(
                                                color: const Color(0xFFABA093),
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.tune_rounded, size: 20, color: Color(0xFFF2B78A)),
                                      tooltip: 'Attendance Settings & Override',
                                      onPressed: () => _openAttendanceOverrideDialog(
                                        context,
                                        calendarAttended: rawCalendarStats.attended,
                                        calendarTotal: rawCalendarStats.totalClasses,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // Metrics Summary Row (3 Tiles)
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildAttendanceStatTile(
                                        label: 'Classes Attended',
                                        value: '$attendedCount',
                                        sublabel: _useManualAttendanceOverride
                                            ? 'Manual count'
                                            : 'Regular: ${rawCalendarStats.attended}${rawCalendarStats.extra > 0 ? ' +${rawCalendarStats.extra}' : ''}',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildAttendanceStatTile(
                                        label: 'Total Sessions',
                                        value: '$totalHeld',
                                        sublabel: _useManualAttendanceOverride
                                            ? 'Manual total'
                                            : 'Missed: ${rawCalendarStats.missed}${rawCalendarStats.canceled > 0 ? ' • Can: ${rawCalendarStats.canceled}' : ''}',
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildAttendanceStatTile(
                                        label: 'Weightage',
                                        value: '${attWeight.toStringAsFixed(0)}%',
                                        sublabel: 'Earned: ${earnedMarks.toStringAsFixed(1)} pts',
                                        highlight: true,
                                        onTap: _showEditWeightageDialog,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 14),

                                // Progress Bar & Standing
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: totalHeld > 0 ? (attendanceRate / 100.0).clamp(0.0, 1.0) : 0.0,
                                    backgroundColor: const Color(0xFF2E221E),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isSafe ? const Color(0xFF06D6A0) : const Color(0xFFFF5964),
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isSafe ? 'Good Standing (≥75%)' : 'Short Attendance (<75%)',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: isSafe ? const Color(0xFF06D6A0) : const Color(0xFFFF5964),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    Text(
                                      '${attendanceRate.toStringAsFixed(1)}%',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: isSafe ? const Color(0xFF06D6A0) : const Color(0xFFFF5964),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // ==========================================
                      // 2. THEORY OR SESSIONAL ASSESSMENT BREAKDOWN
                      // ==========================================
                      if (isTheory) ...[
                        // 2A. CLASS TESTS (CT) WITH WEIGHTAGE & BEST OF N
                        _buildAssessmentCategorySection(
                          title: 'Class Tests (CT)',
                          icon: Icons.quiz_rounded,
                          categoryColor: accentColor,
                          cardColor: cardColor,
                          items: _classTests,
                          weightageController: _ctWeightageController,
                          useBestOf: _ctUseBestOf,
                          bestCountController: _ctBestCountController,
                          onUseBestOfChanged: (val) {
                            setState(() => _ctUseBestOf = val);
                          },
                          onAdd: _addClassTestRow,
                          addLabel: 'Add CT',
                          emptyLabel: 'No class tests added yet. Tap "+ Add CT" to create one.',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 20),

                        // 2B. MAJOR EXAMS CARD (MIDTERM & FINAL WITH WEIGHTAGE)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF4A3830)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.assignment_turned_in_rounded, color: accentColor, size: 20),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'Major Exams (Midterm & Final)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Midterm Exam Row
                              _buildExamInputRow(
                                title: 'Midterm Exam',
                                obtainedController: _midtermObtainedController,
                                totalController: _midtermTotalController,
                                weightageController: _midtermWeightageController,
                                accentColor: accentColor,
                                onChanged: () => setState(() {}),
                              ),
                              const SizedBox(height: 16),

                              // Final Exam Row
                              _buildExamInputRow(
                                title: 'Final Exam',
                                obtainedController: _finalObtainedController,
                                totalController: _finalTotalController,
                                weightageController: _finalWeightageController,
                                accentColor: accentColor,
                                onChanged: () => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // ------------------------------------------
                        // SESSIONAL / LAB DEDICATED CATEGORIES
                        // ------------------------------------------
                        // 1. Quizzes / Viva
                        _buildAssessmentCategorySection(
                          title: 'Quizzes / Viva',
                          icon: Icons.record_voice_over_rounded,
                          categoryColor: const Color(0xFFF2B78A),
                          cardColor: cardColor,
                          items: _quizzesViva,
                          weightageController: _quizzesWeightageController,
                          useBestOf: _quizzesUseBestOf,
                          bestCountController: _quizzesBestCountController,
                          onUseBestOfChanged: (val) {
                            setState(() => _quizzesUseBestOf = val);
                          },
                          onAdd: _addQuizVivaRow,
                          addLabel: 'Add',
                          emptyLabel: 'No quizzes or viva entries recorded yet.',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 20),

                        // 2. Lab Reports / Assignments
                        _buildAssessmentCategorySection(
                          title: 'Lab Reports / Assignments',
                          icon: Icons.assignment_rounded,
                          categoryColor: const Color(0xFF10B981),
                          cardColor: cardColor,
                          items: _labReportsAssignments,
                          weightageController: _labReportsWeightageController,
                          useBestOf: _labReportsUseBestOf,
                          bestCountController: _labReportsBestCountController,
                          onUseBestOfChanged: (val) {
                            setState(() => _labReportsUseBestOf = val);
                          },
                          onAdd: _addLabReportAssignmentRow,
                          addLabel: 'Add',
                          emptyLabel: 'No lab reports or assignments recorded yet.',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 20),

                        // 3. Lab Final / Practical Exam
                        _buildAssessmentCategorySection(
                          title: 'Lab Final / Practical Exam',
                          icon: Icons.terminal_rounded,
                          categoryColor: const Color(0xFFF59E0B),
                          cardColor: cardColor,
                          items: _labFinalPractical,
                          weightageController: _labFinalWeightageController,
                          useBestOf: _labFinalUseBestOf,
                          bestCountController: _labFinalBestCountController,
                          onUseBestOfChanged: (val) {
                            setState(() => _labFinalUseBestOf = val);
                          },
                          onAdd: _addLabFinalPracticalRow,
                          addLabel: 'Add',
                          emptyLabel: 'No practical exams or lab finals recorded yet.',
                          onChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 20),

                        // 4. Continuous Assessment / Performance
                        _buildAssessmentCategorySection(
                          title: 'Continuous Assessment / Performance',
                          icon: Icons.speed_rounded,
                          categoryColor: const Color(0xFFA855F7),
                          cardColor: cardColor,
                          items: _continuousAssessment,
                          weightageController: _continuousWeightageController,
                          useBestOf: _continuousUseBestOf,
                          bestCountController: _continuousBestCountController,
                          onUseBestOfChanged: (val) {
                            setState(() => _continuousUseBestOf = val);
                          },
                          onAdd: _addContinuousAssessmentRow,
                          addLabel: 'Add',
                          emptyLabel: 'No continuous assessment entries recorded yet.',
                          onChanged: () => setState(() {}),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // ==========================================
                      // 3. PREDICTED GRADE & CGPA CONVERSION DASHBOARD
                      // ==========================================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: gradeColor.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: gradeColor.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.auto_graph_rounded, color: gradeColor, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Predicted Performance',
                                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: predictedGrade.isFullWeightage
                                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                        : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: predictedGrade.isFullWeightage
                                          ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                          : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    'Total Weight: ${predictedGrade.totalWeightage.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      color: predictedGrade.isFullWeightage
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFF59E0B),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Score & CGPA Column
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'WEIGHTED SCORE',
                                        style: TextStyle(
                                          color: Colors.blueGrey.shade400,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${predictedGrade.totalWeightedScore.toStringAsFixed(1)} / ${predictedGrade.totalWeightage.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'CGPA: ${predictedGrade.gradePoint.toStringAsFixed(2)} / 4.00',
                                        style: TextStyle(
                                          color: gradeColor,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Big Letter Grade Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: gradeColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: gradeColor.withValues(alpha: 0.4), width: 1.5),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        predictedGrade.letterGrade,
                                        style: TextStyle(
                                          color: gradeColor,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      Text(
                                        predictedGrade.remarks,
                                        style: TextStyle(
                                          color: gradeColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            if (!predictedGrade.isFullWeightage) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 14),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'Category weights sum to ${predictedGrade.totalWeightage.toStringAsFixed(0)}% (adjust to 100% for standard final grade).',
                                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3.5 WHAT-IF SIMULATION & GRADE TARGETS (TASK 3)
                      _buildWhatIfSimulationCard(cardColor, accentColor),
                      const SizedBox(height: 24),

                      // 4. SAVE MARKS BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: const Color(0xFF140F0E),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSaving ? null : _saveAssessmentData,
                          child: _isSaving
                              ? const AppPreloader(
                                  size: 20,
                                  strokeWidth: 2,
                                  color: Color(0xFF140F0E),
                                )
                              : Text(
                                  'Save Marks',
                                  style: GoogleFonts.plusJakartaSans(
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

  /// Reusable Assessment Category Section builder with overflow protection,
  /// flexible weightage, and "Best-of-N" support.
  Widget _buildAssessmentCategorySection({
    required String title,
    required IconData icon,
    required Color categoryColor,
    required Color cardColor,
    required List<AssessmentItem> items,
    required TextEditingController weightageController,
    required bool useBestOf,
    required TextEditingController bestCountController,
    required ValueChanged<bool> onUseBestOfChanged,
    required VoidCallback onAdd,
    required String addLabel,
    required String emptyLabel,
    required VoidCallback onChanged,
  }) {
    final catWeight = double.tryParse(weightageController.text.trim()) ?? 0.0;
    final catBestCount = int.tryParse(bestCountController.text.trim()) ?? 1;

    final catResult = AssessmentCalculationHelper.calculateCategoryScore(
      items: items,
      weightagePercentage: catWeight,
      useBestOf: useBestOf,
      bestCount: catBestCount,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A3830)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Overflow Protection
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(icon, color: categoryColor, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  backgroundColor: categoryColor.withValues(alpha: 0.15),
                  foregroundColor: categoryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(addLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Percentage Weightage & Best-of-N Settings Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF170F0D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              spacing: 12,
              children: [
                // Weightage Input
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Weight:',
                      style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 46,
                      height: 30,
                      child: TextFormField(
                        controller: weightageController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: categoryColor, fontWeight: FontWeight.bold, fontSize: 12.5),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: const Color(0xFF241C1A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                        ),
                        onChanged: (_) => onChanged(),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text('%', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                // Best-of-N Switch & Input
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Best of N',
                      style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch.adaptive(
                        value: useBestOf,
                        activeTrackColor: categoryColor.withValues(alpha: 0.5),
                        activeThumbColor: categoryColor,
                        onChanged: onUseBestOfChanged,
                      ),
                    ),
                    if (useBestOf) ...[
                      const SizedBox(width: 2),
                      const Text('N:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 36,
                        height: 28,
                        child: TextFormField(
                          controller: bestCountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          decoration: InputDecoration(
                            contentPadding: EdgeInsets.zero,
                            filled: true,
                            fillColor: const Color(0xFF241C1A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                          ),
                          onChanged: (_) => onChanged(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'of ${items.length}',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Items List or Empty Label
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                emptyLabel,
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return Dismissible(
                  key: ValueKey(item.id.isNotEmpty ? item.id : '${item.name}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.delete_forever, color: Color(0xFFEF4444), size: 24),
                  ),
                  confirmDismiss: (direction) async {
                    return await _confirmDeleteDialog(context, item);
                  },
                  onDismissed: (direction) {
                    _deleteAssessment(item, items, index, onChanged);
                  },
                  child: _buildClassTestCard(context, item, index, onChanged, categoryColor, items),
                );
              },
            ),
          const SizedBox(height: 8),

          // Category Subtotal & Weighted Contribution
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: categoryColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    useBestOf
                        ? 'Avg (Best ${catResult.countedItems} of ${catResult.totalItems}): ${catResult.percentage.toStringAsFixed(1)}%'
                        : 'Avg: ${catResult.percentage.toStringAsFixed(1)}%',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${catResult.weightedScore.toStringAsFixed(2)} / ${catResult.weightage.toStringAsFixed(0)} pts',
                  style: GoogleFonts.jetBrainsMono(color: categoryColor, fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Minimal scannable assessment card widget
  Widget _buildClassTestCard(
    BuildContext context,
    Assessment ct,
    int index,
    VoidCallback onChanged,
    Color categoryColor,
    List<Assessment> items,
  ) {
    final typeLower = ct.type.toLowerCase().trim();
    final nameLower = ct.title.toLowerCase().trim();

    IconData glyphIcon;
    Color glyphColor;

    if (nameLower.contains('viva') ||
        typeLower.contains('viva') ||
        nameLower.contains('quiz') ||
        typeLower.contains('quiz')) {
      glyphIcon = Icons.quiz_outlined;
      glyphColor = const Color(0xFFF2B78A); // Warm peach
    } else if (nameLower.contains('report') ||
        typeLower.contains('report') ||
        nameLower.contains('assignment') ||
        typeLower.contains('assignment') ||
        typeLower.contains('hw') ||
        nameLower.contains('homework')) {
      glyphIcon = Icons.description_outlined;
      glyphColor = const Color(0xFF10B981); // Emerald
    } else if (nameLower.contains('final') ||
        typeLower.contains('final') ||
        nameLower.contains('midterm') ||
        typeLower.contains('mid')) {
      glyphIcon = (nameLower.contains('lab') || typeLower.contains('lab'))
          ? Icons.science_outlined
          : Icons.school_outlined;
      glyphColor = const Color(0xFFF59E0B); // Soft amber
    } else if (nameLower.contains('project') ||
        typeLower.contains('project') ||
        nameLower.contains('presentation') ||
        typeLower.contains('presentation')) {
      glyphIcon = Icons.co_present_outlined;
      glyphColor = const Color(0xFFA855F7); // Lavender
    } else {
      glyphIcon = Icons.assignment_outlined;
      glyphColor = categoryColor;
    }

    final String dateStr;
    if (ct.date != null) {
      final now = DateTime.now();
      final isFuture = ct.date!.isAfter(DateTime(now.year, now.month, now.day, 23, 59, 59));
      final formattedDate = DateFormat('dd MMM').format(ct.date!);
      dateStr = isFuture ? 'Scheduled $formattedDate' : 'Held $formattedDate';
    } else {
      dateStr = 'Unscheduled';
    }

    final marksStr = ct.obtainedMarks != null
        ? '${ct.obtainedMarks!.toStringAsFixed(1)} / ${ct.totalMarks.toStringAsFixed(0)} pts'
        : '-- / ${ct.totalMarks.toStringAsFixed(0)} pts';

    final Color pctColor;
    final String pctStr;
    if (ct.obtainedMarks != null) {
      final pct = ct.percentage;
      pctStr = '(${pct.toStringAsFixed(1)}%)';
      if (pct >= 80.0) {
        pctColor = const Color(0xFF10B981);
      } else if (pct >= 50.0) {
        pctColor = const Color(0xFFF2B78A);
      } else {
        pctColor = const Color(0xFFEF4444);
      }
    } else {
      pctStr = ct.date != null ? 'Scheduled' : 'Pending';
      pctColor = const Color(0xFF9E8C82);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1816),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF382A24), width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showEnterMarksDialog(context, ct, onChanged),
          onLongPress: () async {
            final confirmed = await _confirmDeleteDialog(context, ct);
            if (confirmed == true) {
              _deleteAssessment(ct, items, index, onChanged);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Category Glyph + Title + Marks
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: glyphColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Icon(glyphIcon, size: 17, color: glyphColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              ct.title,
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFF5EBE6),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (ct.topicsSummary != null && ct.topicsSummary!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _showEditItemTopicDialog(context, ct, onChanged),
                              borderRadius: BorderRadius.circular(4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(Icons.menu_book_outlined, size: 15, color: Color(0xFFABA093)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      marksStr,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFFF5EBE6),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Row 2: Weight & Date metadata + Percentage / Chevron
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: ct.date ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setState(() {
                              ct.date = picked;
                            });
                            onChanged();
                            _saveAssessmentData(silent: true);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            'Weight: ${ct.weightage.toStringAsFixed(0)}% • $dateStr',
                            style: GoogleFonts.jetBrainsMono(
                              color: const Color(0xFF9E8C82),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          pctStr,
                          style: GoogleFonts.jetBrainsMono(
                            color: pctColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Color(0xFF786B63),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditMarksDialog(Assessment ct, VoidCallback onChanged) {
    _showEnterMarksDialog(context, ct, onChanged);
  }

  Future<bool> _confirmDeleteDialog(BuildContext context, Assessment ct) async {
    SafeHaptics.lightImpact();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF382A24)),
        ),
        title: Text(
          'Delete ${ct.title}?',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to remove this assessment? This will permanently delete it from both Course Dashboard and Planner.',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _deleteAssessment(
    Assessment ct,
    List<Assessment> items,
    int index,
    VoidCallback onChanged,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    items.removeWhere((item) => item.id == ct.id || item.name == ct.name);
    _classTests.removeWhere((item) => item.id == ct.id || item.name == ct.name);
    onChanged();

    if (uid != null && uid.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('courses')
            .doc(widget.courseId)
            .collection('assessments')
            .doc(ct.id)
            .delete();
      } catch (e) {
        debugPrint('Error deleting assessment from subcollection: $e');
      }

      try {
        await AssessmentService().deleteAssessment(
          uid: uid,
          courseId: widget.courseId,
          assessmentId: ct.id,
        );
      } catch (e) {
        debugPrint('Error deleting assessment from course doc: $e');
      }
    }
  }

  /// Helper to build Theory Major Exam input rows with responsive flex and weightage
  Widget _buildExamInputRow({
    required String title,
    required TextEditingController obtainedController,
    required TextEditingController totalController,
    required TextEditingController weightageController,
    required Color accentColor,
    required VoidCallback onChanged,
  }) {
    final obt = double.tryParse(obtainedController.text.trim()) ?? 0.0;
    final tot = double.tryParse(totalController.text.trim()) ?? 1.0;
    final weight = double.tryParse(weightageController.text.trim()) ?? 0.0;
    final weighted = tot > 0 ? (obt / tot) * weight : 0.0;
    final pct = tot > 0 ? (obt / tot) * 100.0 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${weighted.toStringAsFixed(2)} / ${weight.toStringAsFixed(0)} pts (${pct.toStringAsFixed(1)}%)',
              style: TextStyle(color: accentColor, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: obtainedController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Color(0xFFF2B78A), fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Obtained',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF170F0D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                validator: (val) => (double.tryParse(val ?? '') == null) ? 'Invalid' : null,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: totalController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Total',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF170F0D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                validator: (val) => (double.tryParse(val ?? '') == null) ? 'Invalid' : null,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: weightageController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Weight %',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 11),
                  filled: true,
                  fillColor: const Color(0xFF170F0D),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                validator: (val) => (double.tryParse(val ?? '') == null) ? 'Invalid' : null,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showEnterMarksDialog(BuildContext context, AssessmentItem item, VoidCallback onSaved) {
    SafeHaptics.lightImpact();
    final obtCtrl = TextEditingController(text: item.obtainedMarks != null ? item.obtainedMarks.toString() : '');
    final totCtrl = TextEditingController(text: item.totalMarks.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF140F0E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF4A3830)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Enter Marks: ${item.name}',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (item.date != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Held on ${item.date!.day} ${_getMonthName(item.date!.month)}, ${item.date!.year}',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OBTAINED',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: obtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            autofocus: true,
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'e.g. 18.5',
                              hintStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 13),
                              filled: true,
                              fillColor: const Color(0xFF241C1A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4A3830))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TOTAL',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: totCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: '20',
                              filled: true,
                              fillColor: const Color(0xFF241C1A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF4A3830))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF2B78A),
                      foregroundColor: const Color(0xFF140F0E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final rawObt = obtCtrl.text.trim();
                      final obt = double.tryParse(rawObt);
                      final tot = double.tryParse(totCtrl.text.trim()) ?? item.totalMarks;

                      if (rawObt.isEmpty) {
                        item.obtainedMarks = null;
                        item.totalMarks = tot;
                        item.status = 'Pending';
                      } else if (obt != null) {
                        item.obtainedMarks = obt;
                        item.totalMarks = tot;
                        item.status = 'Attended';
                      } else {
                        return;
                      }

                      onSaved();
                      Navigator.pop(ctx);

                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid != null && item.id.isNotEmpty) {
                        AssessmentService().updateAssessment(
                          uid: uid,
                          assessment: item,
                        );
                      }
                      _saveAssessmentData(silent: true);

                      if (context.mounted) {
                        SafeHaptics.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF1C1412),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF382A24)),
                            ),
                            content: Row(
                              children: [
                                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.obtainedMarks != null
                                        ? 'Marks for ${item.name} saved: ${item.obtainedMarks!.toStringAsFixed(item.obtainedMarks!.truncateToDouble() == item.obtainedMarks! ? 0 : 1)}/${tot.toStringAsFixed(0)}'
                                        : 'Marks for ${item.name} reset to pending',
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                    child: Text('Save Marks', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(
                      'Delete Assessment',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    onPressed: () async {
                      final confirmed = await _confirmDeleteDialog(context, item);
                      if (confirmed == true && ctx.mounted) {
                        Navigator.pop(ctx);
                        _deleteAssessment(item, _classTests, 0, onSaved);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditItemTopicDialog(
    BuildContext context,
    AssessmentItem item,
    VoidCallback onChanged,
  ) async {
    final ctrl = TextEditingController(text: item.syllabusSummary ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.menu_book_rounded, color: Color(0xFFF2B78A), size: 18),
            const SizedBox(width: 8),
            Text(
              'Topics for ${item.name}',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter syllabus topics or chapters covered:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'e.g., K-Maps, Quine-McCluskey, Multiplexers',
                hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              item.syllabusSummary = ctrl.text.trim().isNotEmpty ? ctrl.text.trim() : null;
              Navigator.pop(ctx);
              onChanged();
            },
            child: const Text('Save Topic', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
