import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../models/assessment_model.dart';
import '../services/assessment_calculator.dart';
import '../widgets/grading_scale_settings_dialog.dart';
import '../services/course_service.dart';
import 'grading_setup_screen.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Type alias for CgpaCalculatorScreen
typedef CgpaCalculatorScreen = TermPerformanceScreen;

/// Breakdown of secured and pending marks for a university course
class CourseScoreBreakdown {
  final double attendanceSecured;
  final double attendanceWeight;
  final double ctSecured;
  final double ctWeight;
  final double midSecured;
  final double midWeight;
  final double otherSecured;
  final double otherWeight;
  final double totalSecured;
  final double totalSecuredWeight;
  final double remainingWeight;

  const CourseScoreBreakdown({
    required this.attendanceSecured,
    required this.attendanceWeight,
    required this.ctSecured,
    required this.ctWeight,
    required this.midSecured,
    required this.midWeight,
    required this.otherSecured,
    required this.otherWeight,
    required this.totalSecured,
    required this.totalSecuredWeight,
    required this.remainingWeight,
  });

  /// Safely extracts and computes course score breakdown from Firestore data,
  /// resilient against both Map and List assessment structures.
  static CourseScoreBreakdown compute(Map<String, dynamic> courseData) {
    double attSec = 0.0;
    double attW = 0.0;
    double ctSec = 0.0;
    double ctW = 0.0;
    double midSec = 0.0;
    double midW = 0.0;
    double othSec = 0.0;
    double othW = 0.0;

    final rawAss = courseData['assessments'];

    if (rawAss is Map) {
      final map = Map<String, dynamic>.from(rawAss);

      // Check if this map is just a key-value store of Assessment items
      final isGenericAssessmentMap = map.isNotEmpty &&
          map.values.every((v) => v is Map && (v.containsKey('totalMarks') || v.containsKey('total')));

      if (isGenericAssessmentMap) {
        return _computeFromAssessmentList(map.values.toList());
      }

      // Extract configured weightages if present on course
      double? configuredAttWeight;
      double? configuredCtWeight;
      double? configuredMidWeight;
      double? configuredOtherWeight;

      final rawWeightages = courseData['weightages'];
      if (rawWeightages is List && rawWeightages.isNotEmpty) {
        for (final w in rawWeightages) {
          if (w is Map) {
            final isActive = w['isActive'] as bool? ?? true;
            final weight = (w['weightPercentage'] as num?)?.toDouble() ?? 0.0;
            if (isActive && weight > 0) {
              final typeName = (w['assessmentType'] as String? ?? '').toLowerCase();
              if (typeName.contains('attend')) {
                configuredAttWeight = weight;
              } else if (typeName.contains('ct') || typeName.contains('quiz') || typeName.contains('continuous')) {
                configuredCtWeight = (configuredCtWeight ?? 0.0) + weight;
              } else if (typeName.contains('mid') || typeName.contains('lab report')) {
                configuredMidWeight = (configuredMidWeight ?? 0.0) + weight;
              } else {
                configuredOtherWeight = (configuredOtherWeight ?? 0.0) + weight;
              }
            }
          }
        }
      }

      // 1. Attendance Marks
      final attWeight = configuredAttWeight ?? ((map['attendanceWeightage'] as num?)?.toDouble() ?? 10.0);
      int attended = (map['classesAttended'] as num?)?.toInt() ?? 0;
      int totalClasses = (map['totalClasses'] as num?)?.toInt() ?? 0;

      // Handle manual attendance override if enabled on course
      if (courseData['useManualAttendanceOverride'] == true) {
        attended = (courseData['manualAttendedClasses'] as num?)?.toInt() ?? attended;
        totalClasses = (courseData['manualTotalClasses'] as num?)?.toInt() ?? totalClasses;
      }

      if (totalClasses > 0 && attWeight > 0) {
        attW = attWeight;
        attSec = ((attended / totalClasses) * attWeight).clamp(0.0, attWeight);
      }

      // 2. Class Tests / Quizzes
      final rawCts = map['classTests'];
      final ctWeight = configuredCtWeight ?? ((map['ctWeightage'] as num?)?.toDouble() ?? 20.0);
      final useBestOf = map['ctUseBestOf'] as bool? ?? (map['dropLowestCt'] as bool? ?? true);
      final bestCount = (map['ctBestCount'] as num?)?.toInt() ?? 3;

      List<dynamic> ctList = [];
      if (rawCts is List) {
        ctList = rawCts;
      } else if (rawCts is Map) {
        ctList = rawCts.values.toList();
      }

      if (ctList.isNotEmpty && ctWeight > 0) {
        final items = ctList
            .whereType<Map>()
            .map((c) => Assessment.fromMap(Map<String, dynamic>.from(c)))
            .where((it) => it.total > 0)
            .toList();

        if (items.isNotEmpty) {
          ctW = ctWeight;
          final catRes = AssessmentCalculationHelper.calculateCategoryScore(
            items: items,
            weightagePercentage: ctWeight,
            useBestOf: useBestOf,
            bestCount: bestCount,
          );
          ctSec = catRes.weightedScore;
        }
      }

      // 3. Midterm Evaluation
      final midObtained = (map['midtermObtained'] as num?)?.toDouble() ?? 0.0;
      final midTotal = (map['midtermTotal'] as num?)?.toDouble() ?? 0.0;
      final midWeight = configuredMidWeight ?? ((map['midtermWeightage'] as num?)?.toDouble() ?? 30.0);
      if (midTotal > 0 && midObtained > 0 && midWeight > 0) {
        midW = midWeight;
        midSec = ((midObtained / midTotal) * midWeight).clamp(0.0, midWeight);
      }

      // 4. Final Exam if recorded
      final finalObt = (map['finalObtained'] as num?)?.toDouble() ?? 0.0;
      final finalTot = (map['finalTotal'] as num?)?.toDouble() ?? 0.0;
      final finalWeight = configuredOtherWeight ?? ((map['finalWeightage'] as num?)?.toDouble() ?? 40.0);
      if (finalTot > 0 && finalObt > 0 && finalWeight > 0) {
        othW += finalWeight;
        othSec += ((finalObt / finalTot) * finalWeight).clamp(0.0, finalWeight);
      }

      // 5. Sessional Lab Reports & Viva
      final rawLabs = map['labReports'];
      List<dynamic> labList = [];
      if (rawLabs is List) {
        labList = rawLabs;
      } else if (rawLabs is Map) {
        labList = rawLabs.values.toList();
      }
      final labWeight = (map['labReportsWeightage'] as num?)?.toDouble() ?? 20.0;
      if (labList.isNotEmpty && labWeight > 0) {
        final labItems = labList
            .whereType<Map>()
            .map((l) => Assessment.fromMap(Map<String, dynamic>.from(l)))
            .where((it) => it.total > 0)
            .toList();
        if (labItems.isNotEmpty) {
          final labRes = AssessmentCalculationHelper.calculateCategoryScore(
            items: labItems,
            weightagePercentage: labWeight,
          );
          othW += labWeight;
          othSec += labRes.weightedScore;
        }
      }

      final vivaObt = (map['vivaObtained'] as num?)?.toDouble() ?? 0.0;
      final vivaTot = (map['vivaTotal'] as num?)?.toDouble() ?? 0.0;
      final vivaWeight = (map['vivaWeightage'] as num?)?.toDouble() ?? 20.0;
      if (vivaTot > 0 && vivaObt > 0 && vivaWeight > 0) {
        othW += vivaWeight;
        othSec += ((vivaObt / vivaTot) * vivaWeight).clamp(0.0, vivaWeight);
      }
    } else if (rawAss is List) {
      return _computeFromAssessmentList(rawAss);
    }

    final totalSec = attSec + ctSec + midSec + othSec;
    final totalW = (attW + ctW + midW + othW).clamp(0.0, 100.0);
    final remainingW = (100.0 - totalW).clamp(0.0, 100.0);

    return CourseScoreBreakdown(
      attendanceSecured: attSec,
      attendanceWeight: attW,
      ctSecured: ctSec,
      ctWeight: ctW,
      midSecured: midSec,
      midWeight: midW,
      otherSecured: othSec,
      otherWeight: othW,
      totalSecured: totalSec,
      totalSecuredWeight: totalW,
      remainingWeight: remainingW,
    );
  }

  static CourseScoreBreakdown _computeFromAssessmentList(List<dynamic> list) {
    double attSec = 0.0;
    double attW = 0.0;
    double ctSec = 0.0;
    double ctW = 0.0;
    double midSec = 0.0;
    double midW = 0.0;
    double othSec = 0.0;
    double othW = 0.0;

    for (final item in list) {
      if (item is Map) {
        final m = Map<String, dynamic>.from(item);
        final name = (m['name'] as String? ?? (m['examName'] as String? ?? '')).toLowerCase();
        final obt = (m['obtainedMarks'] as num?)?.toDouble() ??
            ((m['obtained'] as num?)?.toDouble() ?? ((m['marks'] as num?)?.toDouble() ?? 0.0));
        final tot = (m['totalMarks'] as num?)?.toDouble() ??
            ((m['total'] as num?)?.toDouble() ?? 0.0);
        final w = (m['weightage'] as num?)?.toDouble() ?? 10.0;

        if (tot > 0 && w > 0) {
          final score = ((obt / tot) * w).clamp(0.0, w);
          if (name.contains('attend')) {
            attSec += score;
            attW += w;
          } else if (name.contains('ct') || name.contains('quiz')) {
            ctSec += score;
            ctW += w;
          } else if (name.contains('mid')) {
            midSec += score;
            midW += w;
          } else {
            othSec += score;
            othW += w;
          }
        }
      }
    }

    final totalSec = attSec + ctSec + midSec + othSec;
    final totalW = (attW + ctW + midW + othW).clamp(0.0, 100.0);
    final remainingW = (100.0 - totalW).clamp(0.0, 100.0);

    return CourseScoreBreakdown(
      attendanceSecured: attSec,
      attendanceWeight: attW,
      ctSecured: ctSec,
      ctWeight: ctW,
      midSecured: midSec,
      midWeight: midW,
      otherSecured: othSec,
      otherWeight: othW,
      totalSecured: totalSec,
      totalSecuredWeight: totalW,
      remainingWeight: remainingW,
    );
  }
}

/// Term Performance & CGPA Simulator Screen for University Mode
class TermPerformanceScreen extends ConsumerStatefulWidget {
  final String universityName;
  final String term;

  const TermPerformanceScreen({
    super.key,
    this.universityName = 'BUET',
    this.term = '',
  });

  @override
  ConsumerState<TermPerformanceScreen> createState() => _TermPerformanceScreenState();
}

class _TermPerformanceScreenState extends ConsumerState<TermPerformanceScreen> {
  final bool _isLoadingGradingScale = false;
  List<GradingRow> _gradingScale = [];

  // Multi-select Course State (courseId -> isSelected)
  final Set<String> _selectedCourseIds = {};
  bool _initialSelectionInitialized = false;

  // Predictive Slider State (courseId -> projected pending percentage 0.0 - 100.0)
  final Map<String, double> _projectedPendingPercentages = {};

  // Hypothetical / Simulated Marks State (courseId -> marks)
  final Map<String, double> _simulatedAttendanceMarks = {};
  final Map<String, double> _simulatedCtMarks = {};

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _gradingScale = _defaultStandardScale;
    _fetchGradingScale();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Default fallback BUET / UGC Standard Grading Scale
  List<GradingRow> get _defaultStandardScale => [
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

  /// Fetch letter-grade scale table from Firestore university_grading collection
  Future<void> _fetchGradingScale() async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('university_grading')
          .doc(widget.universityName);
      final doc = await docRef.get();

      if (doc.exists && doc.data() != null) {
        final rawRows = doc.data()?['rows'] as List<dynamic>?;
        if (rawRows != null && rawRows.isNotEmpty && mounted) {
          setState(() {
            _gradingScale = rawRows
                .map((r) => GradingRow.fromMap(Map<String, dynamic>.from(r)))
                .toList();
          });
        }
      }
    } catch (_) {
      // Retain _defaultStandardScale if offline or uninitialized in test
    }
  }

  /// Find matching GradingRow from percentage score
  GradingRow _getGradingRowForPercentage(double percentage) {
    final rounded = percentage.roundToDouble();

    for (final row in _gradingScale) {
      if (rounded >= row.minPercentage && rounded <= row.maxPercentage) {
        return row;
      }
    }
    if (percentage >= 80) return _gradingScale.isNotEmpty ? _gradingScale.first : _defaultStandardScale.first;
    return _gradingScale.isNotEmpty ? _gradingScale.last : _defaultStandardScale.last;
  }

  /// Preset simulator action: Set all pending sliders to a targeted percentage
  void _applyTargetPreset(double targetPct, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    SafeHaptics.mediumImpact();
    setState(() {
      for (final doc in docs) {
        _projectedPendingPercentages[doc.id] = targetPct;
      }
    });
  }

  Color _getGradeColor(double gradePoint) {
    if (gradePoint >= 3.75) return AppColors.success;
    if (gradePoint >= 3.00) return AppColors.primary;
    if (gradePoint >= 2.25) return AppColors.amber;
    return AppColors.error;
  }

  void _showGradingScaleSettingsSheet() {
    GradingScaleSettingsDialog.showAsBottomSheet(
      context: context,
      universityName: widget.universityName,
      currentScale: _gradingScale,
      onSave: (editableScale) async {
        setState(() {
          _gradingScale = editableScale;
        });

        try {
          await FirebaseFirestore.instance
              .collection('university_grading')
              .doc(widget.universityName)
              .set({
            'university': widget.universityName,
            'rows': editableScale.map((r) => r.toMap()).toList(),
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('Error saving grading scale: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.success,
              content: Text('Grading scale updated! Real-time CGPA recalculated.'),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      uid = null;
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Term Performance & CGPA',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${widget.universityName} • ${widget.term.isNotEmpty ? widget.term : 'Current Term'}',
              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppColors.primary, size: 22),
            tooltip: 'Grading Scale Settings',
            onPressed: _showGradingScaleSettingsSheet,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoadingGradingScale
            ? const Center(child: AppPreloader(size: 44))
            : uid == null || uid.isEmpty
                ? const Center(
                    child: Text(
                      'User authentication required.',
                      style: TextStyle(color: Colors.white),
                    ),
                  )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('courses')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: AppPreloader(size: 44));
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error loading course data: ${snapshot.error}',
                            style: const TextStyle(color: AppColors.error),
                          ),
                        );
                      }

                      final allDocs = snapshot.data?.docs ?? [];

                      // Filter by term if provided
                      final docs = allDocs.where((doc) {
                        if (widget.term.isEmpty) return true;
                        final termVal = doc.data()['term'] as String?;
                        if (termVal == null || termVal.isEmpty) return true;
                        return termVal == widget.term;
                      }).toList();

                      // Numerical course sorting (101, 102, 106, 109, 110, 121, 157, 159)
                      docs.sort((a, b) {
                        final dataA = a.data();
                        final dataB = b.data();
                        final codeA = dataA['courseCode'] as String? ?? a.id;
                        final codeB = dataB['courseCode'] as String? ?? b.id;
                        return compareCourseCodes(codeA, codeB);
                      });

                      // Initialize default selection & slider state on first snapshot arrival
                      if (!_initialSelectionInitialized && docs.isNotEmpty) {
                        for (final doc in docs) {
                          _selectedCourseIds.add(doc.id);
                          _projectedPendingPercentages.putIfAbsent(doc.id, () => 80.0);
                        }
                        _initialSelectionInitialized = true;
                      }

                      // Compute Real-Time Term CGPA Engine
                      double totalWeightedGradePoints = 0.0;
                      double totalSelectedCredits = 0.0;
                      final List<({String code, String letter, double gpa, double totalPct, bool isSelected})> coursePills = [];

                      for (final doc in docs) {
                        final data = doc.data();
                        final docId = doc.id;
                        final isSelected = _selectedCourseIds.contains(docId);
                        final creditHours = (data['creditHours'] as num?)?.toDouble() ?? 3.0;
                        final courseCode = data['courseCode'] as String? ?? 'COURSE';

                        // Safely compute score breakdown
                        final breakdown = CourseScoreBreakdown.compute(data);
                        final pendingSlider = _projectedPendingPercentages[docId] ?? 80.0;
                        final simAttendance = _simulatedAttendanceMarks[docId] ?? breakdown.attendanceSecured;
                        final simCT = _simulatedCtMarks[docId] ?? breakdown.ctSecured;
                        final totalSecured = simAttendance + simCT + breakdown.midSecured + breakdown.otherSecured;
                        final projectedMarks = (pendingSlider / 100.0) * breakdown.remainingWeight;
                        final totalPct = (totalSecured + projectedMarks).clamp(0.0, 100.0);

                        final gradingRow = _getGradingRowForPercentage(totalPct);

                        if (isSelected && creditHours > 0) {
                          totalWeightedGradePoints += (gradingRow.gradePoint * creditHours);
                          totalSelectedCredits += creditHours;
                        }

                        coursePills.add((
                          code: courseCode,
                          letter: gradingRow.letterGrade,
                          gpa: gradingRow.gradePoint,
                          totalPct: totalPct,
                          isSelected: isSelected,
                        ));
                      }

                      final double simulatedCgpa =
                          totalSelectedCredits > 0 ? (totalWeightedGradePoints / totalSelectedCredits) : 0.0;

                      return SingleChildScrollView(
                        key: const PageStorageKey<String>('term_performance_scroll_key'),
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. REAL-TIME PERSISTENT TERM CGPA HEADER
                            _buildTermCgpaHeroHeader(
                              simulatedCgpa: simulatedCgpa,
                              totalCredits: totalSelectedCredits,
                              selectedCount: _selectedCourseIds.length,
                              totalCount: docs.length,
                              coursePills: coursePills,
                              onPresetSelected: (target) => _applyTargetPreset(target, docs),
                            ),
                            const SizedBox(height: 20),

                            // 2. SECTION HEADER & MULTI-SELECT OVERVIEW (FIX 17px OVERFLOW)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Course Simulations',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Toggle courses & drag sliders to simulate final grades',
                                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  onPressed: () {
                                    SafeHaptics.lightImpact();
                                    setState(() {
                                      if (_selectedCourseIds.length == docs.length) {
                                        _selectedCourseIds.clear();
                                      } else {
                                        _selectedCourseIds.addAll(docs.map((d) => d.id));
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    _selectedCourseIds.length == docs.length
                                        ? Icons.check_box_rounded
                                        : Icons.select_all_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    _selectedCourseIds.length == docs.length ? 'Deselect All' : 'Select All',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (docs.isEmpty)
                              _buildEmptyCoursesCard()
                            else
                              Column(
                                children: [
                                  for (int i = 0; i < docs.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 14),
                                    _CourseSimulationCard(
                                      key: ValueKey(docs[i].id),
                                      docId: docs[i].id,
                                      courseCode: docs[i].data()['courseCode'] as String? ?? 'COURSE',
                                      courseName: docs[i].data()['courseName'] as String? ?? 'Untitled Course',
                                      creditHours: (docs[i].data()['creditHours'] as num?)?.toDouble() ?? 3.0,
                                      courseType: docs[i].data()['courseType'] as String? ?? 'Theory',
                                      breakdown: CourseScoreBreakdown.compute(docs[i].data()),
                                      isSelected: _selectedCourseIds.contains(docs[i].id),
                                      finalExamTotal: (docs[i].data()['finalExamTotal'] as num?)?.toDouble() ??
                                          ((docs[i].data()['finalTotal'] as num?)?.toDouble() ?? 210.0),
                                      externalSliderValue: _projectedPendingPercentages[docs[i].id] ?? 80.0,
                                      initialSimulatedAttendance: _simulatedAttendanceMarks[docs[i].id],
                                      initialSimulatedCT: _simulatedCtMarks[docs[i].id],
                                      gradingScale: _gradingScale,
                                      defaultScale: _defaultStandardScale,
                                      onToggleSelected: (val) {
                                        SafeHaptics.lightImpact();
                                        setState(() {
                                          if (val) {
                                            _selectedCourseIds.add(docs[i].id);
                                          } else {
                                            _selectedCourseIds.remove(docs[i].id);
                                          }
                                        });
                                      },
                                      onSimulationChanged: (sliderVal, simAtt, simCt) {
                                        setState(() {
                                          _projectedPendingPercentages[docs[i].id] = sliderVal;
                                          _simulatedAttendanceMarks[docs[i].id] = simAtt;
                                          _simulatedCtMarks[docs[i].id] = simCt;
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  /// 1. REAL-TIME PERSISTENT HERO HEADER WITH PRESETS AND PILLS
  Widget _buildTermCgpaHeroHeader({
    required double simulatedCgpa,
    required double totalCredits,
    required int selectedCount,
    required int totalCount,
    required List<({String code, String letter, double gpa, double totalPct, bool isSelected})> coursePills,
    required ValueChanged<double> onPresetSelected,
  }) {
    return buildGlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Big CGPA Counter + Credits Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'SIMULATED TERM CGPA',
                        style: AppTypography.geist(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      simulatedCgpa.toStringAsFixed(2),
                      key: ValueKey(simulatedCgpa.toStringAsFixed(2)),
                      style: AppTypography.cgpaDisplay.copyWith(
                        fontSize: 40,
                        height: 1.1,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderMedium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${totalCredits.toStringAsFixed(1)} Cr',
                      style: AppTypography.geist(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$selectedCount of $totalCount Selected',
                      style: AppTypography.subtext,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Course-by-course Letter Grade Pills
          if (coursePills.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: coursePills.map((pill) {
                  final pillColor = pill.isSelected ? _getGradeColor(pill.gpa) : AppColors.textSecondary;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: pill.isSelected ? pillColor.withValues(alpha: 0.15) : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: pill.isSelected ? pillColor.withValues(alpha: 0.35) : AppColors.borderMedium,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${pill.code}: ',
                          style: AppTypography.geistMono(
                            color: pill.isSelected ? Colors.white70 : AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${pill.letter} (${pill.gpa.toStringAsFixed(2)})',
                          style: AppTypography.geistMono(
                            color: pillColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Quick Simulation Presets
          Row(
            children: [
              Text(
                'Targets:',
                style: AppTypography.subtext.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildPresetChip('A+ (100%)', 100.0, onPresetSelected),
                      _buildPresetChip('A (80%)', 80.0, onPresetSelected),
                      _buildPresetChip('B (60%)', 60.0, onPresetSelected),
                      _buildPresetChip('Pass (40%)', 40.0, onPresetSelected),
                      _buildPresetChip('Reset (0%)', 0.0, onPresetSelected),
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

  Widget _buildPresetChip(String label, double target, ValueChanged<double> onSelected) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onSelected(target),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderMedium),
          ),
          child: Text(
            label,
            style: AppTypography.geist(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCoursesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(Icons.assessment_outlined, size: 48, color: Colors.blueGrey.shade400),
          const SizedBox(height: 12),
          const Text(
            'No Courses Enrolled for this Term',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add courses from the University Dashboard to track marks and CGPA.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey.shade400,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 2. COURSE SIMULATION CARD (SELECTION + SECURED BREAKDOWN + WHAT-IF SLIDER + WHAT DO I NEED ON THE FINAL ACCORDION)
typedef _CourseSimulationCard = CourseSimulationCard;

class CourseSimulationCard extends StatefulWidget {
  final String docId;
  final String courseCode;
  final String courseName;
  final double creditHours;
  final String courseType;
  final CourseScoreBreakdown breakdown;
  final bool isSelected;
  final double finalExamTotal;
  final double externalSliderValue;
  final double? initialSimulatedAttendance;
  final double? initialSimulatedCT;
  final List<GradingRow> gradingScale;
  final List<GradingRow> defaultScale;
  final ValueChanged<bool> onToggleSelected;
  final Function(double sliderVal, double simAttendance, double simCT) onSimulationChanged;

  const CourseSimulationCard({
    super.key,
    required this.docId,
    required this.courseCode,
    required this.courseName,
    required this.creditHours,
    required this.courseType,
    required this.breakdown,
    required this.isSelected,
    required this.finalExamTotal,
    required this.externalSliderValue,
    this.initialSimulatedAttendance,
    this.initialSimulatedCT,
    required this.gradingScale,
    required this.defaultScale,
    required this.onToggleSelected,
    required this.onSimulationChanged,
  });

  @override
  State<CourseSimulationCard> createState() => _CourseSimulationCardState();
}

class _CourseSimulationCardState extends State<CourseSimulationCard> {
  bool _isExpanded = false;
  late double _sliderValue;
  double? _simulatedAttendance;
  double? _simulatedCT;

  @override
  void initState() {
    super.initState();
    _sliderValue = widget.externalSliderValue;
    _simulatedAttendance = widget.initialSimulatedAttendance;
    _simulatedCT = widget.initialSimulatedCT;
  }

  @override
  void didUpdateWidget(covariant _CourseSimulationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externalSliderValue != oldWidget.externalSliderValue) {
      _sliderValue = widget.externalSliderValue;
    }
    if (widget.initialSimulatedAttendance != oldWidget.initialSimulatedAttendance &&
        widget.initialSimulatedAttendance != null) {
      _simulatedAttendance = widget.initialSimulatedAttendance;
    }
    if (widget.initialSimulatedCT != oldWidget.initialSimulatedCT &&
        widget.initialSimulatedCT != null) {
      _simulatedCT = widget.initialSimulatedCT;
    }
  }

  double get _effectiveAttendance => (_simulatedAttendance ?? widget.breakdown.attendanceSecured)
      .clamp(0.0, widget.breakdown.attendanceWeight > 0 ? widget.breakdown.attendanceWeight : 100.0);

  double get _effectiveCT => (_simulatedCT ?? widget.breakdown.ctSecured)
      .clamp(0.0, widget.breakdown.ctWeight > 0 ? widget.breakdown.ctWeight : 100.0);

  bool get _isAttendanceSimulated =>
      _simulatedAttendance != null && (_simulatedAttendance! - widget.breakdown.attendanceSecured).abs() > 0.01;

  bool get _isCtSimulated =>
      _simulatedCT != null && (_simulatedCT! - widget.breakdown.ctSecured).abs() > 0.01;

  void _notifySimulationChanged() {
    widget.onSimulationChanged(_sliderValue, _effectiveAttendance, _effectiveCT);
  }

  GradingRow _findGradingRow(double percentage) {
    final rounded = percentage.roundToDouble();
    for (final row in widget.gradingScale) {
      if (rounded >= row.minPercentage && rounded <= row.maxPercentage) {
        return row;
      }
    }
    if (percentage >= 80) {
      return widget.gradingScale.isNotEmpty ? widget.gradingScale.first : widget.defaultScale.first;
    }
    return widget.gradingScale.isNotEmpty ? widget.gradingScale.last : widget.defaultScale.last;
  }

  Color _getGradeColor(double gradePoint) {
    if (gradePoint >= 3.75) return AppColors.success;
    if (gradePoint >= 3.00) return AppColors.primary;
    if (gradePoint >= 2.25) return AppColors.amber;
    return AppColors.error;
  }

  Color _getGradeColorByLetter(String grade) {
    if (grade.startsWith('A')) return AppColors.success;
    if (grade.startsWith('B')) return AppColors.primary;
    if (grade.startsWith('C')) return AppColors.amber;
    return AppColors.error;
  }

  void _showScoreSimulationDialog({
    required BuildContext context,
    required String title,
    required String label,
    required double actualSecured,
    required double maxWeight,
    required double currentValue,
    required ValueChanged<double> onApply,
  }) {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(1));
    double selectedValue = currentValue;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF191312),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(top: BorderSide(color: Color(0xFF382924), width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        widget.courseCode,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Actual recorded marks: ${actualSecured.toStringAsFixed(1)} / ${maxWeight.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Hypothetical $label Marks (0 - ${maxWeight.toStringAsFixed(0)})',
                    labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
                    suffixText: '/ ${maxWeight.toStringAsFixed(0)}',
                    suffixStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFF120D0C),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF382924)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val);
                    if (parsed != null) {
                      selectedValue = parsed.clamp(0.0, maxWeight);
                    }
                  },
                ),
                const SizedBox(height: 14),
                // Quick-select preset pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildModalPill(
                        label: 'Full (${maxWeight.toStringAsFixed(0)})',
                        onTap: () {
                          selectedValue = maxWeight;
                          controller.text = selectedValue.toStringAsFixed(1);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildModalPill(
                        label: '90% (${(maxWeight * 0.9).toStringAsFixed(1)})',
                        onTap: () {
                          selectedValue = (maxWeight * 0.9);
                          controller.text = selectedValue.toStringAsFixed(1);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildModalPill(
                        label: '80% (${(maxWeight * 0.8).toStringAsFixed(1)})',
                        onTap: () {
                          selectedValue = (maxWeight * 0.8);
                          controller.text = selectedValue.toStringAsFixed(1);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildModalPill(
                        label: '70% (${(maxWeight * 0.7).toStringAsFixed(1)})',
                        onTap: () {
                          selectedValue = (maxWeight * 0.7);
                          controller.text = selectedValue.toStringAsFixed(1);
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildModalPill(
                        label: 'Actual (${actualSecured.toStringAsFixed(1)})',
                        color: AppColors.primary,
                        onTap: () {
                          selectedValue = actualSecured;
                          controller.text = selectedValue.toStringAsFixed(1);
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Color(0xFF382924)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          onApply(actualSecured);
                        },
                        child: const Text('Reset to Actual'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final parsed = double.tryParse(controller.text);
                          final finalVal = (parsed ?? selectedValue).clamp(0.0, maxWeight);
                          Navigator.pop(ctx);
                          onApply(finalVal);
                        },
                        child: const Text('Apply Simulation', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModalPill({required String label, required VoidCallback onTap, Color? color}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (color ?? Colors.white).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: (color ?? Colors.white).withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color ?? Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEditableBreakdownItem({
    required String label,
    required String value,
    required bool hasWeight,
    required bool isSimulated,
    VoidCallback? onTap,
  }) {
    final content = Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSimulated ? const Color(0xFFF2B78A) : Colors.blueGrey.shade400,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.edit_rounded,
                size: 10,
                color: isSimulated ? const Color(0xFFF2B78A) : Colors.blueGrey.shade500,
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hasWeight ? value : '—',
          style: TextStyle(
            color: isSimulated ? const Color(0xFFF2B78A) : (hasWeight ? Colors.white : Colors.blueGrey.shade600),
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (isSimulated)
          const Text(
            '(Simulated)',
            style: TextStyle(color: Color(0xFFF2B78A), fontSize: 9.5, fontWeight: FontWeight.bold),
          ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: content,
      ),
    );
  }

  Widget _buildGradeTargetRow({
    required String grade,
    required String percentage,
    required String gpa,
    required double marksNeeded,
    required double totalFinalMarks,
    required Color gradeColor,
  }) {
    final bool isImpossible = marksNeeded > totalFinalMarks;
    final bool isAlreadyAchieved = marksNeeded <= 0;
    final double safeTotalMarks = totalFinalMarks > 0 ? totalFinalMarks : 100.0;
    final double ratio = isImpossible ? 1.0 : (marksNeeded / safeTotalMarks).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF191210),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E221E), width: 0.6),
      ),
      child: Row(
        children: [
          // Left: Grade Badge + Threshold
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              grade,
              style: GoogleFonts.jetBrainsMono(
                color: gradeColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$percentage ($gpa)',
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFFABA093),
              fontSize: 11.5,
            ),
          ),

          const Spacer(),

          // Right: Target text + Mini Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isAlreadyAchieved
                    ? 'Already secured'
                    : isImpossible
                        ? 'Not reachable (>100%)'
                        : 'Need at least ${marksNeeded.toStringAsFixed(1)}',
                style: GoogleFonts.jetBrainsMono(
                  color: isImpossible ? const Color(0xFFFF5964) : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 90,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 3.0,
                    backgroundColor: const Color(0xFF2E221E),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isImpossible
                          ? const Color(0xFFFF5964)
                          : (ratio > 0.85 ? const Color(0xFFF2B78A) : const Color(0xFF06D6A0)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: Color(0xFF4A3830), size: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSecured = _effectiveAttendance +
        _effectiveCT +
        widget.breakdown.midSecured +
        widget.breakdown.otherSecured;
    final remainingWeight = widget.breakdown.remainingWeight;
    final projectedMarks = (_sliderValue / 100.0) * remainingWeight;
    final totalPercentage = (totalSecured + projectedMarks).clamp(0.0, 100.0);
    final gradingRow = _findGradingRow(totalPercentage);
    final gradeColor = _getGradeColor(gradingRow.gradePoint);

    final finTot = widget.finalExamTotal > 0 ? widget.finalExamTotal : 210.0;
    final simulatedFinalExamMarks = (_sliderValue / 100.0) * finTot;

    final targetRows = widget.gradingScale
        .where((r) => ['A+', 'A', 'A-', 'B+', 'B'].contains(r.letterGrade))
        .toList();
    final targets = targetRows.isNotEmpty
        ? targetRows
            .map((r) => {
                  'grade': r.letterGrade,
                  'cutoff': r.minPercentage.toDouble(),
                  'point': r.gradePoint
                })
            .toList()
        : [
            {'grade': 'A+', 'cutoff': 80.0, 'point': 4.00},
            {'grade': 'A', 'cutoff': 75.0, 'point': 3.75},
            {'grade': 'A-', 'cutoff': 70.0, 'point': 3.50},
            {'grade': 'B+', 'cutoff': 65.0, 'point': 3.25},
            {'grade': 'B', 'cutoff': 60.0, 'point': 3.00},
          ];

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: widget.isSelected ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? (remainingWeight > 0
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : AppColors.borderMedium)
                : AppColors.borderMedium.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Code, Name, Credit, Toggle Switch
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            widget.courseCode,
                            style: AppTypography.courseCode.copyWith(fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${widget.creditHours.toStringAsFixed(1)} Cr',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.courseName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: widget.isSelected,
                  activeColor: AppColors.primary,
                  onChanged: widget.onToggleSelected,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Grade Projection Badge & Percent Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: gradeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: gradeColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.workspace_premium_rounded, size: 13, color: gradeColor),
                          const SizedBox(width: 5),
                          Text(
                            'Projected: ${gradingRow.letterGrade} (${gradingRow.gradePoint.toStringAsFixed(2)})',
                            style: TextStyle(
                              color: gradeColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  '${totalPercentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: AppFonts.isTestEnvironment ? null : 'GeistMono',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Score Distribution Mini Grid (Interactive Hypothetical Attendance & CT)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderMedium.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildEditableBreakdownItem(
                      label: 'Attendance',
                      value:
                          '${_effectiveAttendance.toStringAsFixed(1)} / ${widget.breakdown.attendanceWeight.toStringAsFixed(0)}',
                      hasWeight: widget.breakdown.attendanceWeight > 0,
                      isSimulated: _isAttendanceSimulated,
                      onTap: widget.breakdown.attendanceWeight > 0 && widget.isSelected
                          ? () {
                              _showScoreSimulationDialog(
                                context: context,
                                title: 'Simulate Attendance Marks',
                                label: 'Attendance',
                                actualSecured: widget.breakdown.attendanceSecured,
                                maxWeight: widget.breakdown.attendanceWeight,
                                currentValue: _effectiveAttendance,
                                onApply: (val) {
                                  setState(() {
                                    _simulatedAttendance = val;
                                  });
                                  _notifySimulationChanged();
                                },
                              );
                            }
                          : null,
                    ),
                  ),
                  Container(width: 1, height: 28, color: AppColors.borderMedium),
                  Expanded(
                    child: _buildEditableBreakdownItem(
                      label: 'CT / Quizzes',
                      value:
                          '${_effectiveCT.toStringAsFixed(1)} / ${widget.breakdown.ctWeight.toStringAsFixed(0)}',
                      hasWeight: widget.breakdown.ctWeight > 0,
                      isSimulated: _isCtSimulated,
                      onTap: widget.breakdown.ctWeight > 0 && widget.isSelected
                          ? () {
                              _showScoreSimulationDialog(
                                context: context,
                                title: 'Simulate CT / Quiz Marks',
                                label: 'CT',
                                actualSecured: widget.breakdown.ctSecured,
                                maxWeight: widget.breakdown.ctWeight,
                                currentValue: _effectiveCT,
                                onApply: (val) {
                                  setState(() {
                                    _simulatedCT = val;
                                  });
                                  _notifySimulationChanged();
                                },
                              );
                            }
                          : null,
                    ),
                  ),
                  Container(width: 1, height: 28, color: AppColors.borderMedium),
                  Expanded(
                    child: _buildEditableBreakdownItem(
                      label: widget.courseType.toLowerCase().contains('theory') ? 'Midterm' : 'Continuous',
                      value:
                          '${widget.breakdown.midSecured.toStringAsFixed(1)} / ${widget.breakdown.midWeight.toStringAsFixed(0)}',
                      hasWeight: widget.breakdown.midWeight > 0,
                      isSimulated: false,
                      onTap: null,
                    ),
                  ),
                ],
              ),
            ),

            if (_isAttendanceSimulated || _isCtSimulated) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () {
                    SafeHaptics.lightImpact();
                    setState(() {
                      _simulatedAttendance = null;
                      _simulatedCT = null;
                    });
                    _notifySimulationChanged();
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 12, color: Color(0xFFF2B78A)),
                      SizedBox(width: 4),
                      Text(
                        'Reset hypothetical marks to actual',
                        style: TextStyle(
                          color: Color(0xFFF2B78A),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),

            // Secured vs Remaining Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    if (totalSecured > 0)
                      Expanded(
                        flex: totalSecured.round().clamp(1, 100),
                        child: Container(color: AppColors.success),
                      ),
                    if (projectedMarks > 0)
                      Expanded(
                        flex: projectedMarks.round().clamp(1, 100),
                        child: Container(color: const Color(0xFFA78BFA)),
                      ),
                    if ((100.0 - totalPercentage) > 0)
                      Expanded(
                        flex: (100.0 - totalPercentage).round().clamp(1, 100),
                        child: Container(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Term Marks: ${totalSecured.toStringAsFixed(1)} / ${widget.breakdown.totalSecuredWeight.toStringAsFixed(0)}',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                ),
                Text(
                  remainingWeight > 0
                      ? 'Pending: ${remainingWeight.toStringAsFixed(0)}% weight'
                      : 'All 100% evaluated',
                  style: TextStyle(
                    color: remainingWeight > 0 ? const Color(0xFFA78BFA) : AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            // Interactive What-If Predictive Slider (Quick slider)
            if (remainingWeight > 0) ...[
              const SizedBox(height: 12),
              const Divider(color: AppColors.borderMedium, height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'Expected Final Exam Score:',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${_sliderValue.round()}% (${projectedMarks.toStringAsFixed(1)} / ${remainingWeight.toStringAsFixed(0)} marks)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackShape: const GradientSliderTrackShape(),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.borderMedium,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _sliderValue.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: widget.isSelected
                      ? (val) {
                          setState(() {
                            _sliderValue = val;
                          });
                          _notifySimulationChanged();
                        }
                      : null,
                ),
              ),
            ],

            const SizedBox(height: 10),

            // What Do I Need on the Final? Accordion Toggle Button (Local state, zero scroll reset!)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                SafeHaptics.lightImpact();
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _isExpanded
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isExpanded
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.grid_view_rounded,
                          size: 15,
                          color: _isExpanded ? AppColors.primary : Colors.blueGrey.shade300,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'What Do I Need on the Final?',
                          style: TextStyle(
                            color: _isExpanded ? AppColors.primary : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: _isExpanded ? AppColors.primary : Colors.blueGrey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),

            if (_isExpanded) ...[
              const SizedBox(height: 14),

              // 1. Interactive "Projected Final Exam Score" slider
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Projected Final Exam Score:',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${simulatedFinalExamMarks.toStringAsFixed(1)} / ${finTot.toStringAsFixed(0)} Marks (${_sliderValue.round()}%)',
                    style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: const Color(0xFF8B5CF6),
                  inactiveTrackColor: Colors.white12,
                  thumbColor: const Color(0xFF8B5CF6),
                  overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  trackHeight: 4,
                ),
                child: Slider(
                  value: _sliderValue.clamp(0.0, 100.0),
                  min: 0.0,
                  max: 100.0,
                  divisions: 100,
                  onChanged: widget.isSelected
                      ? (val) {
                          setState(() {
                            _sliderValue = val;
                          });
                          _notifySimulationChanged();
                        }
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // 2. Clean Two-Sided Subheader: Left Title + Info Icon | Right "Out of X marks"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Text(
                        'Score Needed in Final Exam',
                        style: TextStyle(
                          color: Color(0xFFABA093),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.info_outline_rounded,
                        size: 13,
                        color: Color(0xFFABA093),
                      ),
                    ],
                  ),
                  Text(
                    'Out of ${finTot.toStringAsFixed(0)} marks',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF786B63),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 3. Redesigned Grade Target Rows (No RenderFlex overflow)
              ...targets.map((t) {
                final cutoff = (t['cutoff'] as num).toDouble();
                final finalExamWeight = remainingWeight > 0 ? remainingWeight : 70.0;
                final marksNeeded = cutoff - totalSecured;
                final finalExamMarksRequired = (marksNeeded / finalExamWeight) * finTot;

                return _buildGradeTargetRow(
                  grade: t['grade'] as String,
                  percentage: '${cutoff.toStringAsFixed(0)}%',
                  gpa: (t['point'] as num).toStringAsFixed(2),
                  marksNeeded: finalExamMarksRequired,
                  totalFinalMarks: finTot,
                  gradeColor: _getGradeColorByLetter(t['grade'] as String),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
