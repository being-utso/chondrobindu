import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/routine_models.dart';
import '../widgets/app_preloader.dart';
import 'add_course_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Single item representing a scheduled or recorded class session
class CourseClassSessionItem {
  final DateTime date;
  final String? routineId;
  final String? teacherId;
  final String time;
  final String classType;
  final AttendanceStatus status;
  final AttendanceRecord? record;
  final bool isExtra;
  final bool isBlockedAlternating;

  CourseClassSessionItem({
    required this.date,
    this.routineId,
    this.teacherId,
    required this.time,
    required this.classType,
    required this.status,
    this.record,
    this.isExtra = false,
    this.isBlockedAlternating = false,
  });
}

/// Course-Specific Attendance Screen providing Class History & Summary / Manual Count Adjustment
class CourseAttendanceScreen extends ConsumerStatefulWidget {
  final String courseId;
  final String courseCode;
  final String? courseName;
  final String? userId;

  const CourseAttendanceScreen({
    super.key,
    required this.courseId,
    required this.courseCode,
    this.courseName,
    this.userId,
  });

  @override
  ConsumerState<CourseAttendanceScreen> createState() => _CourseAttendanceScreenState();
}

/// Backward compatibility alias for any existing references
typedef CourseAttendanceAuditScreen = CourseAttendanceScreen;

class _CourseAttendanceScreenState extends ConsumerState<CourseAttendanceScreen> {
  String _statusFilter = 'All';
  DateTime? _selectedFilterDate;
  String? _selectedTeacherId; // null = 'All Teachers'

  // Manual Override Form Controllers for Tab 2
  late TextEditingController _manualAttendedController;
  late TextEditingController _manualTotalController;
  bool _useManualOverride = false;
  bool _isSavingOverride = false;
  bool _manualOverrideControllersInitialized = false;

  static const _bgColor = Color(0xFF110D0C);
  static const _cardColor = Color(0xFF241C1A);
  static const _accentColor = Color(0xFFF2B78A);
  static const _presentColor = Color(0xFF10B981); // Green
  static const _absentColor = Color(0xFFEF4444);  // Red
  static const _canceledColor = Color(0xFF64748B); // Grey
  static const _unmarkedColor = Color(0xFF94A3B8); // Neutral Slate
  static const _extraColor = Color(0xFFA855F7);    // Purple

  @override
  void initState() {
    super.initState();
    _manualAttendedController = TextEditingController();
    _manualTotalController = TextEditingController();
  }

  @override
  void dispose() {
    _manualAttendedController.dispose();
    _manualTotalController.dispose();
    super.dispose();
  }

  /// Cycles attendance status: Unmarked -> Present -> Absent -> Canceled -> Unmarked
  AttendanceStatus _getNextStatus(AttendanceStatus current) {
    switch (current) {
      case AttendanceStatus.unmarked:
        return AttendanceStatus.attended; // Present
      case AttendanceStatus.attended:
      case AttendanceStatus.extra:
        return AttendanceStatus.missed;   // Absent
      case AttendanceStatus.missed:
        return AttendanceStatus.canceled; // Canceled
      case AttendanceStatus.canceled:
        return AttendanceStatus.unmarked; // Unmarked
    }
  }

  Color _getStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.attended:
        return _presentColor;
      case AttendanceStatus.missed:
        return _absentColor;
      case AttendanceStatus.canceled:
        return _canceledColor;
      case AttendanceStatus.extra:
        return _extraColor;
      case AttendanceStatus.unmarked:
        return _unmarkedColor;
    }
  }

  String _getStatusLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.attended:
        return 'Present';
      case AttendanceStatus.missed:
        return 'Absent';
      case AttendanceStatus.canceled:
        return 'Canceled';
      case AttendanceStatus.extra:
        return 'Extra';
      case AttendanceStatus.unmarked:
        return 'Unmarked';
    }
  }

  /// Updates status in Firestore in real time with bidirectional synchronization
  Future<void> _updateSessionStatus({
    required String uid,
    required DateTime date,
    required String? routineId,
    String? teacherId,
    required String classType,
    required String time,
    required AttendanceStatus newStatus,
  }) async {
    SafeHaptics.mediumImpact();

    try {
      final canonicalCourseId = await RoutineCourseSyncService.resolveCanonicalCourseId(
        uid: uid,
        courseId: widget.courseId,
        rawName: widget.courseName ?? widget.courseCode,
      );
      final courseCode = widget.courseCode.isNotEmpty
          ? widget.courseCode
          : RoutineCourseSyncService.parseCourseCode(widget.courseName ?? '');

      final dateKey = '${date.year}_${date.month.toString().padLeft(2, '0')}_${date.day.toString().padLeft(2, '0')}';
      final docId = '${canonicalCourseId}_${routineId ?? 'extra'}_$dateKey';

      final record = AttendanceRecord(
        id: docId,
        courseId: canonicalCourseId,
        courseCode: courseCode,
        date: date,
        status: newStatus,
        routineId: routineId,
        teacherId: teacherId,
        courseName: widget.courseName ?? courseCode,
        classType: classType,
        time: time,
      );

      final batch = FirebaseFirestore.instance.batch();
      final attRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .doc(docId);

      batch.set(attRef, {
        ...record.toMap(),
        'courseId': canonicalCourseId,
        'courseCode': courseCode,
        'teacherId': teacherId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Touch course document to trigger reactive refresh across all screens
      final courseRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(canonicalCourseId);

      batch.set(courseRef, {
        'lastAttendanceSync': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: _getStatusColor(newStatus),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text(
              '${DateFormat('EEE, MMM d').format(date)}: Marked ${_getStatusLabel(newStatus)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _absentColor, content: Text('Error updating status: $e')),
      );
    }
  }

  Future<void> _bulkMarkTeacherSessionsAttended({
    required String uid,
    required String teacherId,
    required List<CourseClassSessionItem> sessions,
  }) async {
    final unmarkedForTeacher = sessions.where(
      (s) => s.teacherId == teacherId && s.status == AttendanceStatus.unmarked,
    ).toList();

    if (unmarkedForTeacher.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No unmarked sessions for this instructor.'),
        ),
      );
      return;
    }

    final batch = FirebaseFirestore.instance.batch();
    final canonicalCourseId = await RoutineCourseSyncService.resolveCanonicalCourseId(
      uid: uid,
      courseId: widget.courseId,
      rawName: widget.courseName ?? widget.courseCode,
    );
    final courseCode = widget.courseCode.isNotEmpty
        ? widget.courseCode
        : RoutineCourseSyncService.parseCourseCode(widget.courseName ?? '');

    for (final s in unmarkedForTeacher) {
      final dateKey = '${s.date.year}_${s.date.month.toString().padLeft(2, '0')}_${s.date.day.toString().padLeft(2, '0')}';
      final docId = '${canonicalCourseId}_${s.routineId ?? 'extra'}_$dateKey';

      final record = AttendanceRecord(
        id: docId,
        courseId: canonicalCourseId,
        courseCode: courseCode,
        date: s.date,
        status: AttendanceStatus.attended,
        routineId: s.routineId,
        teacherId: teacherId,
        courseName: widget.courseName ?? courseCode,
        classType: s.classType,
        time: s.time,
      );

      final attRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .doc(docId);

      batch.set(attRef, {
        ...record.toMap(),
        'courseId': canonicalCourseId,
        'courseCode': courseCode,
        'teacherId': teacherId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    final courseRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('courses')
        .doc(canonicalCourseId);
    batch.set(courseRef, {'lastAttendanceSync': FieldValue.serverTimestamp()}, SetOptions(merge: true));

    await batch.commit();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _presentColor,
        content: Text('Marked ${unmarkedForTeacher.length} classes as Attended for this instructor!'),
      ),
    );
  }

  /// Dialog to add an extra / makeup class strictly scoped to this course
  Future<void> _showAddExtraClassDialog(BuildContext context, String uid) async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay startTime = TimeOfDay.now();
    String classType = 'Extra Lecture';
    AttendanceStatus initialStatus = AttendanceStatus.attended;
    final topicController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardColor,
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
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                              color: _presentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.add_task_rounded, color: _presentColor, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Add Extra Class Session',
                                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                widget.courseCode,
                                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.blueGrey, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Session Date
                  const Text('CLASS DATE', style: TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 180)),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: _accentColor,
                                surface: _cardColor,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1412),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF382A24)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, color: _accentColor, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat('EEEE, MMMM d, yyyy').format(selectedDate),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Time Slot
                  const Text('TIME', style: TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                        builder: (context, child) {
                          return Theme(
                            data: ThemeData.dark().copyWith(
                              colorScheme: const ColorScheme.dark(
                                primary: _accentColor,
                                surface: _cardColor,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() => startTime = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1412),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF382A24)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_rounded, color: _accentColor, size: 18),
                          const SizedBox(width: 10),
                          Text(
                            startTime.format(context),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Initial Status
                  const Text('INITIAL STATUS', style: TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Present'),
                        selected: initialStatus == AttendanceStatus.attended,
                        selectedColor: _presentColor.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: initialStatus == AttendanceStatus.attended ? _presentColor : Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) setModalState(() => initialStatus = AttendanceStatus.attended);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Extra'),
                        selected: initialStatus == AttendanceStatus.extra,
                        selectedColor: _extraColor.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: initialStatus == AttendanceStatus.extra ? _extraColor : Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) setModalState(() => initialStatus = AttendanceStatus.extra);
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Absent'),
                        selected: initialStatus == AttendanceStatus.missed,
                        selectedColor: _absentColor.withValues(alpha: 0.25),
                        labelStyle: TextStyle(
                          color: initialStatus == AttendanceStatus.missed ? _absentColor : Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) setModalState(() => initialStatus = AttendanceStatus.missed);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Record Topic (Optional)
                  const Text('RECORD TOPIC (OPTIONAL)', style: TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: topicController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Chapter 5 Problem Solving',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF1C1412),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF382A24)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _accentColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Save Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _presentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final routineId = 'extra_${DateTime.now().millisecondsSinceEpoch}';
                        final formattedTime = startTime.format(context);
                        await _updateSessionStatus(
                          uid: uid,
                          date: selectedDate,
                          routineId: routineId,
                          classType: classType,
                          time: formattedTime,
                          newStatus: initialStatus,
                        );
                      },
                      child: const Text('Save Extra Class', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Safely deserializes routines from dynamic raw data (List or Map)
  List<ClassRoutine> _parseRoutines(dynamic rawData, {String? defaultId}) {
    if (rawData == null) return [];
    final List<ClassRoutine> results = [];
    if (rawData is List) {
      for (int i = 0; i < rawData.length; i++) {
        final item = rawData[i];
        if (item is Map) {
          try {
            results.add(ClassRoutine.fromMap(
              Map<String, dynamic>.from(item),
              defaultId: '${defaultId ?? 'routine'}_$i',
            ));
          } catch (_) {}
        }
      }
    } else if (rawData is Map) {
      final map = Map<String, dynamic>.from(rawData);
      dynamic nestedList = map['schedule'] ?? map['routines'] ?? map['routine'] ?? map['classes'] ?? map['items'];
      if (nestedList is List) {
        results.addAll(_parseRoutines(nestedList, defaultId: defaultId));
      } else {
        try {
          results.add(ClassRoutine.fromMap(map, defaultId: defaultId));
        } catch (_) {}
      }
    }
    return results;
  }

  /// Safely deserializes attendance records from dynamic raw data (List or Map)
  List<AttendanceRecord> _parseAttendanceRecords(dynamic rawData, {String? defaultId}) {
    if (rawData == null) return [];
    final List<AttendanceRecord> results = [];
    if (rawData is List) {
      for (int i = 0; i < rawData.length; i++) {
        final item = rawData[i];
        if (item is Map) {
          try {
            results.add(AttendanceRecord.fromMap(
              Map<String, dynamic>.from(item),
              defaultId: '${defaultId ?? 'att'}_$i',
            ));
          } catch (_) {}
        }
      }
    } else if (rawData is Map) {
      final map = Map<String, dynamic>.from(rawData);
      dynamic nestedList = map['records'] ?? map['attendance'] ?? map['attendance_records'] ?? map['items'];
      if (nestedList is List) {
        results.addAll(_parseAttendanceRecords(nestedList, defaultId: defaultId));
      } else {
        try {
          results.add(AttendanceRecord.fromMap(map, defaultId: defaultId));
        } catch (_) {}
      }
    }
    return results;
  }

  /// Builds a chronological list of class session dates between semesterStart and semesterEnd
  List<CourseClassSessionItem> _buildClassSessions({
    required List<ClassRoutine> allRoutines,
    required List<AttendanceRecord> allRecords,
    required HolidaySettings holidays,
  }) {
    // 1. Filter routines for this course
    final courseRoutines = allRoutines.where((r) => RoutineCourseSyncService.routineMatchesCourse(
      routine: r,
      courseId: widget.courseId,
      courseCode: widget.courseCode,
      courseName: widget.courseName,
    )).toList();

    // 2. Filter attendance records for this course
    final courseRecords = allRecords.where((rec) => RoutineCourseSyncService.recordMatchesCourse(
      record: rec,
      courseId: widget.courseId,
      courseCode: widget.courseCode,
      courseName: widget.courseName,
    )).toList();

    // Fast lookup map by dateKey
    String makeDateKey(DateTime d) => '${d.year}_${d.month.toString().padLeft(2, '0')}_${d.day.toString().padLeft(2, '0')}';
    final Map<String, List<AttendanceRecord>> dateRecordsMap = {};
    for (final rec in courseRecords) {
      final k = makeDateKey(rec.date);
      dateRecordsMap.putIfAbsent(k, () => []).add(rec);
    }

    final List<CourseClassSessionItem> sessions = [];
    final Set<String> processedKeys = {};

    // 3. Determine semester boundary
    final now = DateTime.now();
    final start = holidays.semesterStart ?? now.subtract(const Duration(days: 90));
    final rawEnd = holidays.semesterEnd ?? now.add(const Duration(days: 90));
    final end = rawEnd.isAfter(now.add(const Duration(days: 30)))
        ? now.add(const Duration(days: 30))
        : rawEnd;

    DateTime cur = DateTime(start.year, start.month, start.day);
    final limit = DateTime(end.year, end.month, end.day);

    while (!cur.isAfter(limit)) {
      final dKey = makeDateKey(cur);

      // Scheduled routines on this date strictly respecting lifecycle boundaries
      final dayRoutines = courseRoutines.where((r) => r.isActiveOnDate(cur)).toList();

      for (final r in dayRoutines) {
        final routineKey = '${dKey}_${r.id}';
        processedKeys.add(routineKey);

        final isBlocked = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
          routine: r,
          records: allRecords,
          selectedDate: cur,
        );

        final matchingRecs = dateRecordsMap[dKey] ?? [];
        final rec = matchingRecs.cast<AttendanceRecord?>().firstWhere(
          (rc) => rc != null && (rc.routineId == r.id || rc.time == r.startTime),
          orElse: () => null,
        );

        sessions.add(CourseClassSessionItem(
          date: cur,
          routineId: r.id,
          teacherId: r.teacherId ?? rec?.teacherId,
          time: '${r.startTime} - ${r.endTime}',
          classType: r.classType,
          status: rec?.status ?? AttendanceStatus.unmarked,
          record: rec,
          isExtra: false,
          isBlockedAlternating: isBlocked,
        ));
      }

      // Check extra sessions or past routine sessions on this day
      final dayRecs = dateRecordsMap[dKey] ?? [];
      for (final rec in dayRecs) {
        final bool isExplicitlyExtra = rec.status == AttendanceStatus.extra ||
            (rec.routineId != null && rec.routineId!.startsWith('extra'));
        final bool isCoveredByRoutine =
            dayRoutines.any((r) => r.id == rec.routineId || r.startTime == rec.time);

        if (isExplicitlyExtra || !isCoveredByRoutine) {
          final recKey = '${dKey}_${rec.routineId ?? rec.id}';
          if (!processedKeys.contains(recKey)) {
            processedKeys.add(recKey);
            sessions.add(CourseClassSessionItem(
              date: cur,
              routineId: rec.routineId,
              teacherId: rec.teacherId,
              time: rec.time ?? 'Class Session',
              classType: rec.classType ?? (isExplicitlyExtra ? 'Extra' : 'Lecture'),
              status: rec.status,
              record: rec,
              isExtra: isExplicitlyExtra,
            ));
          }
        }
      }

      cur = cur.add(const Duration(days: 1));
    }

    // Include existing recorded classes outside boundary
    for (final rec in courseRecords) {
      final dKey = makeDateKey(rec.date);
      final recKey = '${dKey}_${rec.routineId ?? rec.id}';
      if (!processedKeys.contains(recKey)) {
        processedKeys.add(recKey);
        final bool isExplicitlyExtra = rec.status == AttendanceStatus.extra ||
            (rec.routineId != null && rec.routineId!.startsWith('extra'));
        sessions.add(CourseClassSessionItem(
          date: rec.date,
          routineId: rec.routineId,
          teacherId: rec.teacherId,
          time: rec.time ?? 'Class Session',
          classType: rec.classType ?? (isExplicitlyExtra ? 'Extra' : 'Lecture'),
          status: rec.status,
          record: rec,
          isExtra: isExplicitlyExtra,
        ));
      }
    }

    // Sort latest to earliest (most recent class first)
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  @override
  Widget build(BuildContext context) {
    String? uid = widget.userId;
    if (uid == null) {
      try {
        uid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {
        uid = null;
      }
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _bgColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Attendance: ${widget.courseCode}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (widget.courseName != null && widget.courseName!.isNotEmpty)
                Text(
                  widget.courseName!,
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          bottom: const TabBar(
            indicatorColor: _accentColor,
            indicatorWeight: 3,
            labelColor: _accentColor,
            unselectedLabelColor: Colors.blueGrey,
            tabs: [
              Tab(icon: Icon(Icons.calendar_month_rounded, size: 20), text: 'Timeline'),
              Tab(icon: Icon(Icons.tune_rounded, size: 20), text: 'Summary & Tally'),
            ],
          ),
        ),
        body: uid == null || uid.isEmpty
            ? const Center(child: Text('User authentication required.', style: TextStyle(color: Colors.white)))
            : Builder(
                builder: (context) {
                  final currentUid = uid!;
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('courses').doc(widget.courseId).snapshots(),
                    builder: (context, courseSnap) {
                      final courseData = courseSnap.data?.data() ?? {};
                      final courseModel = CourseModel.fromMap(courseData, widget.courseId);

                      if (!_manualOverrideControllersInitialized && courseSnap.hasData) {
                        _useManualOverride = courseModel.useManualAttendanceOverride;
                        if (courseModel.manualAttendedClasses != null) {
                          _manualAttendedController.text = courseModel.manualAttendedClasses.toString();
                        }
                        if (courseModel.manualTotalClasses != null) {
                          _manualTotalController.text = courseModel.manualTotalClasses.toString();
                        }
                        _manualOverrideControllersInitialized = true;
                      }

                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('settings').doc('holidays').snapshots(),
                        builder: (context, holidaySnap) {
                          final holidayData = holidaySnap.data?.data();
                          final holidays = holidayData != null ? HolidaySettings.fromMap(holidayData) : HolidaySettings.defaultSettings;

                          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('routine').snapshots(),
                            builder: (context, routineSnap) {
                              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                stream: FirebaseFirestore.instance.collection('users').doc(currentUid).collection('attendance_records').snapshots(),
                                builder: (context, attSnap) {
                                  if (attSnap.connectionState == ConnectionState.waiting && !attSnap.hasData) {
                                    return const Center(child: AppPreloader(size: 44));
                                  }

                                  // Safely parse routines from collection and course document
                                  final List<ClassRoutine> allRoutines = [];
                                  for (final d in routineSnap.data?.docs ?? []) {
                                    allRoutines.addAll(_parseRoutines(d.data(), defaultId: d.id));
                                  }
                                  if (courseData['schedule'] != null) {
                                    allRoutines.addAll(_parseRoutines(courseData['schedule'], defaultId: widget.courseId));
                                  }
                                  if (courseData['routine'] != null) {
                                    allRoutines.addAll(_parseRoutines(courseData['routine'], defaultId: widget.courseId));
                                  }
                                  if (courseData['routines'] != null) {
                                    allRoutines.addAll(_parseRoutines(courseData['routines'], defaultId: widget.courseId));
                                  }
                                  if (courseData['classSchedule'] != null) {
                                    allRoutines.addAll(_parseRoutines(courseData['classSchedule'], defaultId: widget.courseId));
                                  }

                                  // Safely parse attendance records from collection and course document
                                  final List<AttendanceRecord> allRecords = [];
                                  for (final d in attSnap.data?.docs ?? []) {
                                    allRecords.addAll(_parseAttendanceRecords(d.data(), defaultId: d.id));
                                  }
                                  if (courseData['attendance'] != null) {
                                    allRecords.addAll(_parseAttendanceRecords(courseData['attendance'], defaultId: widget.courseId));
                                  }
                                  if (courseData['attendance_records'] != null) {
                                    allRecords.addAll(_parseAttendanceRecords(courseData['attendance_records'], defaultId: widget.courseId));
                                  }

                                  final courseSessions = _buildClassSessions(
                                    allRoutines: allRoutines,
                                    allRecords: allRecords,
                                    holidays: holidays,
                                  );

                                  final courseRecords = allRecords.where((rec) => RoutineCourseSyncService.recordMatchesCourse(
                                    record: rec,
                                    courseId: widget.courseId,
                                    courseCode: widget.courseCode,
                                    courseName: widget.courseName,
                                  )).toList();

                                  final rawCalendarStats = AttendanceStats.fromRecords(courseRecords);

                                  return TabBarView(
                                    children: [
                                      // TAB 1: Timeline
                                      _buildTimelineTab(
                                        context: context,
                                        uid: currentUid,
                                        sessions: courseSessions,
                                        teachers: courseModel.teachers,
                                      ),

                                      // TAB 2: Summary & Tally
                                      _buildSummaryAndTallyTab(
                                        context: context,
                                        uid: currentUid,
                                        rawCalendarStats: rawCalendarStats,
                                        courseModel: courseModel,
                                        courseSessions: courseSessions,
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: TIMELINE
  // =========================================================================

  Widget _buildTimelineTab({
    required BuildContext context,
    required String uid,
    required List<CourseClassSessionItem> sessions,
    required List<Teacher> teachers,
  }) {
    List<CourseClassSessionItem> filtered = sessions;

    if (_selectedTeacherId != null) {
      filtered = filtered.where((s) => s.teacherId == _selectedTeacherId).toList();
    }

    if (_selectedFilterDate != null) {
      filtered = filtered.where((s) =>
          s.date.year == _selectedFilterDate!.year &&
          s.date.month == _selectedFilterDate!.month &&
          s.date.day == _selectedFilterDate!.day).toList();
    }

    if (_statusFilter != 'All') {
      filtered = filtered.where((s) {
        if (_statusFilter == 'Present') return s.status == AttendanceStatus.attended || s.status == AttendanceStatus.extra;
        if (_statusFilter == 'Absent') return s.status == AttendanceStatus.missed;
        if (_statusFilter == 'Canceled') return s.status == AttendanceStatus.canceled;
        if (_statusFilter == 'Unmarked') return s.status == AttendanceStatus.unmarked;
        return true;
      }).toList();
    }

    final selectedTeacher = teachers.where((t) => t.id == _selectedTeacherId).firstOrNull;
    final int teacherAttended = _selectedTeacherId != null
        ? sessions.where((s) => s.teacherId == _selectedTeacherId && (s.status == AttendanceStatus.attended || s.status == AttendanceStatus.extra)).length
        : 0;
    final int teacherTotal = _selectedTeacherId != null
        ? sessions.where((s) => s.teacherId == _selectedTeacherId && s.status != AttendanceStatus.canceled && s.status != AttendanceStatus.unmarked).length
        : 0;
    final double teacherPct = teacherTotal > 0 ? (teacherAttended / teacherTotal) * 100.0 : 100.0;
    final int teacherUnmarked = _selectedTeacherId != null
        ? sessions.where((s) => s.teacherId == _selectedTeacherId && s.status == AttendanceStatus.unmarked).length
        : 0;

    return Column(
      children: [
        // Teacher Filter Bar (if multiple teachers)
        if (teachers.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: _bgColor,
            child: Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 15, color: _accentColor),
                const SizedBox(width: 6),
                const Text('Instructor:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All Teachers'),
                          selected: _selectedTeacherId == null,
                          selectedColor: _accentColor.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            color: _selectedTeacherId == null ? _accentColor : Colors.blueGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _selectedTeacherId = null);
                          },
                        ),
                        const SizedBox(width: 6),
                        for (final t in teachers) ...[
                          ChoiceChip(
                            label: Text(t.initials.isNotEmpty ? '${t.name} (${t.initials})' : t.name),
                            selected: _selectedTeacherId == t.id,
                            selectedColor: _accentColor.withValues(alpha: 0.25),
                            labelStyle: TextStyle(
                              color: _selectedTeacherId == t.id ? _accentColor : Colors.blueGrey,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _selectedTeacherId = t.id);
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Teacher Metrics Banner & Bulk Override
        if (selectedTeacher != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${selectedTeacher.name} (${selectedTeacher.initials.isNotEmpty ? selectedTeacher.initials : "Instructor"})',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Attended: $teacherAttended / $teacherTotal (${teacherPct.toStringAsFixed(1)}%) • $teacherUnmarked Unmarked',
                        style: const TextStyle(color: _accentColor, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                if (teacherUnmarked > 0)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _presentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _bulkMarkTeacherSessionsAttended(
                      uid: uid,
                      teacherId: selectedTeacher.id,
                      sessions: sessions,
                    ),
                    child: const Text('Mark All Present', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),

        // Top Filter Bar & Add Extra Class
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _bgColor,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_selectedFilterDate != null) ...[
                        InputChip(
                          backgroundColor: _accentColor.withValues(alpha: 0.2),
                          label: Text(
                            DateFormat('MMM d').format(_selectedFilterDate!),
                            style: const TextStyle(color: _accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          onDeleted: () => setState(() => _selectedFilterDate = null),
                          deleteIconColor: _accentColor,
                        ),
                        const SizedBox(width: 6),
                      ],
                      for (final filter in ['All', 'Present', 'Absent', 'Unmarked', 'Canceled']) ...[
                        ChoiceChip(
                          label: Text(filter),
                          selected: _statusFilter == filter,
                          selectedColor: _accentColor.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            color: _statusFilter == filter ? _accentColor : Colors.blueGrey,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _statusFilter = filter);
                          },
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: const Color(0xFF140F0E),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showAddExtraClassDialog(context, uid),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Extra Class', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        // Session List or Empty State
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.event_busy_rounded, color: Colors.blueGrey.shade600, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'No classes scheduled within the semester period.',
                          style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ensure your class routines are set in the Planner or tap "Add Extra Class" above.',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        if (_selectedFilterDate != null || _statusFilter != 'All' || _selectedTeacherId != null) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => setState(() {
                              _selectedFilterDate = null;
                              _statusFilter = 'All';
                              _selectedTeacherId = null;
                            }),
                            child: const Text('Reset All Filters', style: TextStyle(color: _accentColor)),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildClassCard(context, uid, item, teachers: teachers);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildClassCard(BuildContext context, String uid, CourseClassSessionItem item, {required List<Teacher> teachers}) {
    final statusColor = _getStatusColor(item.status);
    final isToday = DateTime.now().year == item.date.year &&
        DateTime.now().month == item.date.month &&
        DateTime.now().day == item.date.day;

    final teacherObj = item.teacherId != null
        ? teachers.where((t) => t.id == item.teacherId).firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday ? _accentColor.withValues(alpha: 0.6) : const Color(0xFF4A3830),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            // Tap directly cycles status
            final next = _getNextStatus(item.status);
            _updateSessionStatus(
              uid: uid,
              date: item.date,
              routineId: item.routineId,
              teacherId: item.teacherId,
              classType: item.classType,
              time: item.time,
              newStatus: next,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Date & Day Pillar
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF170F0D),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF4A3830)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        DateFormat('MMM').format(item.date).toUpperCase(),
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${item.date.day}',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        DateFormat('EEE').format(item.date),
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Details & Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              DateFormat('EEEE, MMMM d').format(item.date),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isExtra) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _extraColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Extra',
                                style: TextStyle(color: _extraColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          if (isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Today',
                                style: TextStyle(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, color: Colors.blueGrey.shade400, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            item.time,
                            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12)),
                          const SizedBox(width: 8),
                          Text(
                            item.classType,
                            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                          ),
                          if (teacherObj != null) ...[
                            const SizedBox(width: 8),
                            Text('•', style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                teacherObj.initials.isNotEmpty ? teacherObj.initials : teacherObj.name,
                                style: const TextStyle(color: _accentColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.record?.topic != null && item.record!.topic!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Recorded Topic: ${item.record!.topic!}',
                          style: const TextStyle(color: _accentColor, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Status Chip (Tap cycles status)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    final next = _getNextStatus(item.status);
                    _updateSessionStatus(
                      uid: uid,
                      date: item.date,
                      routineId: item.routineId,
                      classType: item.classType,
                      time: item.time,
                      newStatus: next,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      _getStatusLabel(item.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
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

  // =========================================================================
  // TAB 2: SUMMARY & TALLY
  // =========================================================================

  Widget _buildSummaryAndTallyTab({
    required BuildContext context,
    required String uid,
    required AttendanceStats rawCalendarStats,
    required CourseModel courseModel,
    required List<CourseClassSessionItem> courseSessions,
  }) {
    final effectiveStats = RoutineCourseSyncService.computeCourseAttendance(
      courseRecords: const [],
      useManualAttendanceOverride: courseModel.useManualAttendanceOverride,
      manualAttendedClasses: courseModel.manualAttendedClasses,
      manualTotalClasses: courseModel.manualTotalClasses,
    );

    final autoAttended = rawCalendarStats.attended + rawCalendarStats.extra;
    final autoTotal = rawCalendarStats.totalClasses;
    final autoPct = autoTotal > 0 ? (autoAttended / autoTotal) * 100.0 : 100.0;
    final isSafe = autoPct >= 75.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Statistics Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                            color: _accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.analytics_rounded, color: _accentColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Live Course Attendance',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isSafe ? _presentColor : _absentColor).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: (isSafe ? _presentColor : _absentColor).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        isSafe ? 'Good Standing' : 'Shortage Alert',
                        style: TextStyle(
                          color: isSafe ? _presentColor : _absentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Live Stats Numbers
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$autoAttended Attended / $autoTotal Classes Held',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Present: ${rawCalendarStats.attended} • Absent: ${rawCalendarStats.missed} • Canceled: ${rawCalendarStats.canceled}',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                        ),
                      ],
                    ),
                    Text(
                      '${autoPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: isSafe ? _presentColor : _absentColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Linear Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: autoTotal > 0 ? (autoAttended / autoTotal).clamp(0.0, 1.0) : 0.0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFF382A24),
                    valueColor: AlwaysStoppedAnimation<Color>(isSafe ? _presentColor : _absentColor),
                  ),
                ),

                if (courseModel.useManualAttendanceOverride) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Active for Grades: ${effectiveStats.attended}/${effectiveStats.totalClasses} classes (${effectiveStats.percentage.toStringAsFixed(1)}%) via Manual Override',
                            style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (courseModel.teachers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people_alt_rounded, color: _accentColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Instructor Attendance Breakdown',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final t in courseModel.teachers) ...[
                    Builder(
                      builder: (context) {
                        final tSessions = courseSessions.where((s) => s.teacherId == t.id).toList();
                        final tAtt = tSessions.where((s) => s.status == AttendanceStatus.attended || s.status == AttendanceStatus.extra).length;
                        final tTot = tSessions.where((s) => s.status != AttendanceStatus.canceled && s.status != AttendanceStatus.unmarked).length;
                        final tPct = tTot > 0 ? (tAtt / tTot) * 100.0 : 100.0;
                        final tSafe = tPct >= 75.0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF170F0D),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF382A24)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundColor: _accentColor.withValues(alpha: 0.2),
                                        child: Text(
                                          t.initials.isNotEmpty ? t.initials : 'T',
                                          style: const TextStyle(color: _accentColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        t.name,
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    tTot > 0 ? '${tPct.toStringAsFixed(1)}%' : 'No classes',
                                    style: TextStyle(
                                      color: tTot > 0 ? (tSafe ? _presentColor : _absentColor) : Colors.blueGrey,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$tAtt / $tTot classes attended',
                                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                                  ),
                                  Text(
                                    '${tSessions.where((s) => s.status == AttendanceStatus.missed).length} missed',
                                    style: TextStyle(color: _absentColor.withValues(alpha: 0.8), fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: tTot > 0 ? (tAtt / tTot).clamp(0.0, 1.0) : 0.0,
                                  minHeight: 4,
                                  backgroundColor: const Color(0xFF382A24),
                                  valueColor: AlwaysStoppedAnimation<Color>(tSafe ? _presentColor : _absentColor),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Manual Count Adjustment Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _useManualOverride ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.08),
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
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Color(0xFFF59E0B), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Manual Count Adjustment',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'For mid-semester onboarding',
                              style: TextStyle(color: Colors.blueGrey, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: _useManualOverride,
                      activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      activeThumbColor: const Color(0xFFF59E0B),
                      onChanged: (val) {
                        SafeHaptics.lightImpact();
                        setState(() {
                          _useManualOverride = val;
                          if (val && _manualTotalController.text.isEmpty) {
                            _manualAttendedController.text = autoAttended.toString();
                            _manualTotalController.text = autoTotal.toString();
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_useManualOverride) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Classes Attended',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _manualAttendedController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: '0',
                                filled: true,
                                fillColor: const Color(0xFF1C1412),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF382A24)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF382A24)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Classes',
                              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _manualTotalController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: '0',
                                filled: true,
                                fillColor: const Color(0xFF1C1412),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF382A24)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFF382A24)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Color(0xFFF59E0B)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Conflict note if manual count differs from calendar records
                  Builder(
                    builder: (context) {
                      final mAtt = int.tryParse(_manualAttendedController.text.trim()) ?? 0;
                      final mTot = int.tryParse(_manualTotalController.text.trim()) ?? 0;
                      final differs = autoTotal > 0 && (mAtt != autoAttended || mTot != autoTotal);

                      if (differs) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Manual count ($mAtt/$mTot) differs from timeline records ($autoAttended/$autoTotal).',
                                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Action Buttons
                  Row(
                    children: [
                      if (courseModel.useManualAttendanceOverride) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.blueGrey.shade600),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _isSavingOverride ? null : () => _revertToCalendar(uid),
                            child: const Text('Revert to Auto Count', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isSavingOverride ? null : () => _saveManualOverride(uid, autoAttended, autoTotal),
                          child: _isSavingOverride
                              ? const AppPreloader(size: 18, strokeWidth: 2, color: Colors.black)
                              : const Text('Save Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Enable manual count if you enrolled mid-semester and want to enter total attended classes directly without recording past dates.',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                  ),
                  if (courseModel.useManualAttendanceOverride) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _accentColor),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _revertToCalendar(uid),
                      child: const Text('Revert to Automatic Tracking', style: TextStyle(color: _accentColor)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveManualOverride(String uid, int autoAttended, int autoTotal) async {
    final attended = int.tryParse(_manualAttendedController.text.trim());
    final total = int.tryParse(_manualTotalController.text.trim());

    if (attended == null || total == null || total <= 0 || attended < 0 || attended > total) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _absentColor,
          content: Text('Please enter valid numbers. Attended must be <= Total and Total > 0.'),
        ),
      );
      return;
    }

    // Check conflict with calendar date tally
    final hasConflict = autoTotal > 0 && (attended != autoAttended || total != autoTotal);
    if (hasConflict) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Expanded(
                child: Text('Count Conflict', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Text(
            'Your manual count ($attended/$total) differs from timeline records ($autoAttended/$autoTotal). Use manual count for grade calculations?',
            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.black),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Use Manual Count', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isSavingOverride = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').doc(widget.courseId).set({
        'useManualAttendanceOverride': true,
        'manualAttendedClasses': attended,
        'manualTotalClasses': total,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      SafeHaptics.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _presentColor,
          content: Text('Manual count active: $attended/$total classes'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _absentColor, content: Text('Error saving override: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingOverride = false);
    }
  }

  Future<void> _revertToCalendar(String uid) async {
    setState(() => _isSavingOverride = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').doc(widget.courseId).set({
        'useManualAttendanceOverride': false,
        'manualAttendedClasses': FieldValue.delete(),
        'manualTotalClasses': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      SafeHaptics.mediumImpact();
      if (!mounted) return;
      setState(() {
        _useManualOverride = false;
        _manualAttendedController.clear();
        _manualTotalController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _accentColor,
          content: Text('Reverted to automatic timeline tracking.', style: TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _absentColor, content: Text('Error reverting: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingOverride = false);
    }
  }
}
