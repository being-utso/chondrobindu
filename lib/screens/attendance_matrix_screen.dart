import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/routine_models.dart';
import '../widgets/app_preloader.dart';
import 'routine_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Daily Agenda & State-Based Attendance Matrix Screen
class AttendanceMatrixScreen extends ConsumerStatefulWidget {
  const AttendanceMatrixScreen({super.key});

  @override
  ConsumerState<AttendanceMatrixScreen> createState() => _AttendanceMatrixScreenState();
}

class _AttendanceMatrixScreenState extends ConsumerState<AttendanceMatrixScreen> {
  DateTime _selectedDate = DateTime.now();

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _getDayName(int weekday) {
    switch (weekday) {
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      default:
        return 'Day';
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Cycle attendance state: Unmarked -> Attended -> Missed -> Canceled -> Unmarked
  AttendanceStatus _getNextStatus(AttendanceStatus current) {
    switch (current) {
      case AttendanceStatus.unmarked:
        return AttendanceStatus.attended;
      case AttendanceStatus.attended:
        return AttendanceStatus.missed;
      case AttendanceStatus.missed:
        return AttendanceStatus.canceled;
      case AttendanceStatus.canceled:
      case AttendanceStatus.extra:
        return AttendanceStatus.unmarked;
    }
  }

  Color _getStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.attended:
      case AttendanceStatus.extra:
        return const Color(0xFF06D6A0); // Emerald Green
      case AttendanceStatus.missed:
        return const Color(0xFFEF4444); // Rose Red
      case AttendanceStatus.canceled:
        return const Color(0xFFABA093); // Muted Taupe / Slate
      case AttendanceStatus.unmarked:
        return const Color(0xFF4A3830); // Charcoal border
    }
  }

  IconData _getStatusIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.attended:
      case AttendanceStatus.extra:
        return Icons.check_circle_rounded;
      case AttendanceStatus.missed:
        return Icons.cancel_rounded;
      case AttendanceStatus.canceled:
        return Icons.block_rounded;
      case AttendanceStatus.unmarked:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Future<void> _updateAttendanceStatus({
    required String uid,
    required String courseId,
    required String? routineId,
    required String courseName,
    required String classType,
    required String time,
    required AttendanceStatus newStatus,
  }) async {
    SafeHaptics.mediumImpact();

    final dateKey = '${_selectedDate.year}_${_selectedDate.month.toString().padLeft(2, '0')}_${_selectedDate.day.toString().padLeft(2, '0')}';
    final docId = '${courseId}_${routineId ?? 'extra'}_$dateKey';

    final record = AttendanceRecord(
      id: docId,
      courseId: courseId,
      date: _selectedDate,
      status: newStatus,
      routineId: routineId,
      courseName: courseName,
      classType: classType,
      time: time,
    );

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .doc(docId)
          .set(record.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating attendance: $e');
    }
  }

  /// Open Extra Class Modal
  void _showAddExtraClassModal(BuildContext context, String uid, List<QueryDocumentSnapshot<Map<String, dynamic>>> courses) {
    if (courses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please add at least one course first before logging extra classes.'),
        ),
      );
      return;
    }

    String selectedCourseId = courses.first.id;
    String selectedCourseName = courses.first.data()['courseCode'] as String? ?? 'Course';
    String classType = 'Extra Lecture';
    TimeOfDay startTime = TimeOfDay(hour: DateTime.now().hour, minute: 0);

    showModalBottomSheet(
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
                          const Icon(Icons.add_task_rounded, color: Color(0xFFF2B78A), size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Add Extra / Makeup Class',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Course Dropdown
                  Text('COURSE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140F0E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCourseId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1C1412),
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                        items: courses.map((doc) {
                          final data = doc.data();
                          final code = data['courseCode'] as String? ?? 'Course';
                          final name = data['courseName'] as String? ?? '';
                          return DropdownMenuItem(
                            value: doc.id,
                            child: Text(name.isNotEmpty && name != 'Tap to edit name' ? '$code • $name' : code, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedCourseId = val;
                              final doc = courses.firstWhere((d) => d.id == val);
                              final code = doc.data()['courseCode'] as String? ?? 'Course';
                              selectedCourseName = code;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Time Picker
                  Text('CLASS TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final t = await showTimePicker(context: context, initialTime: startTime);
                      if (t != null) setModalState(() => startTime = t);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF140F0E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            startTime.format(context),
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const Icon(Icons.access_time_rounded, color: Color(0xFFF2B78A), size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Class Type
                  Text('CLASS TYPE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140F0E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: classType,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1C1412),
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        items: ['Extra Lecture', 'Makeup Lab', 'Review Session', 'Special Sessional'].map((t) {
                          return DropdownMenuItem(value: t, child: Text(t));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setModalState(() => classType = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF140F0E),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final extraId = 'extra_${DateTime.now().millisecondsSinceEpoch}';
                        await _updateAttendanceStatus(
                          uid: uid,
                          courseId: selectedCourseId,
                          routineId: extraId,
                          courseName: selectedCourseName,
                          classType: classType,
                          time: startTime.format(context),
                          newStatus: AttendanceStatus.extra,
                        );

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF06D6A0),
                              content: Text('Logged extra class as Attended!'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                      label: Text('Log Extra Class', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF140F0E))),
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

  /// Manage Holidays Bottom Sheet Modal
  void _showHolidayManagementModal(BuildContext context, String uid, HolidaySettings current) {
    List<int> weekly = List<int>.from(current.weeklyHolidays);
    List<DateTime> specific = List<DateTime>.from(current.specificHolidays);
    bool isSaving = false;

    final days = [
      {'day': DateTime.saturday, 'label': 'Saturday'},
      {'day': DateTime.sunday, 'label': 'Sunday'},
      {'day': DateTime.monday, 'label': 'Monday'},
      {'day': DateTime.tuesday, 'label': 'Tuesday'},
      {'day': DateTime.wednesday, 'label': 'Wednesday'},
      {'day': DateTime.thursday, 'label': 'Thursday'},
      {'day': DateTime.friday, 'label': 'Friday'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(ctx).size.height * 0.85,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFF4A3830), borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.beach_access_rounded, color: Color(0xFFF2B78A), size: 22),
                        const SizedBox(width: 10),
                        Text('Manage Holidays & Off-Days', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Section 1: Weekly Off-Days
                      Text('WEEKLY OFF-DAYS', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Classes will be automatically paused on these recurring days of the week:', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12)),
                      const SizedBox(height: 10),
                      ...days.map((item) {
                        final dInt = item['day'] as int;
                        final label = item['label'] as String;
                        final isChecked = weekly.contains(dInt);

                        return CheckboxListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            label,
                            style: GoogleFonts.plusJakartaSans(
                              color: isChecked ? Colors.white : const Color(0xFFABA093),
                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                              fontSize: 14,
                            ),
                          ),
                          value: isChecked,
                          activeColor: const Color(0xFFF2B78A),
                          checkColor: const Color(0xFF140F0E),
                          onChanged: (val) {
                            setModalState(() {
                              if (val == true) {
                                if (!weekly.contains(dInt)) weekly.add(dInt);
                              } else {
                                weekly.remove(dInt);
                              }
                            });
                          },
                        );
                      }),

                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFF382A24), height: 1),
                      const SizedBox(height: 20),

                      // Section 2: Specific One-Off Holidays
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ONE-OFF HOLIDAYS', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 2),
                              Text('${specific.length} specific date(s) added', style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12)),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF2B78A),
                              foregroundColor: const Color(0xFF140F0E),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                final norm = DateTime(picked.year, picked.month, picked.day);
                                if (!specific.any((s) => s.year == norm.year && s.month == norm.month && s.day == norm.day)) {
                                  setModalState(() => specific.add(norm));
                                }
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF140F0E)),
                            label: Text('Add Date', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF140F0E))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (specific.isEmpty)
                        Text('No one-off holidays set (e.g. Eid, Puja, National holidays).', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12, fontStyle: FontStyle.italic))
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: specific.map((dt) {
                            return Chip(
                              backgroundColor: const Color(0xFF140F0E),
                              side: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                              label: Text('${dt.day}/${dt.month}/${dt.year}', style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFEF4444)),
                              onDeleted: () {
                                setModalState(() => specific.remove(dt));
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF2B78A),
                      foregroundColor: const Color(0xFF140F0E),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: isSaving
                        ? null
                        : () async {
                            setModalState(() => isSaving = true);
                            final updatedSettings = HolidaySettings(
                              weeklyHolidays: weekly,
                              specificHolidays: specific,
                            );

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('settings')
                                .doc('holidays')
                                .set(updatedSettings.toMap(), SetOptions(merge: true));

                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  backgroundColor: Color(0xFF06D6A0),
                                  content: Text('Holiday settings saved successfully!'),
                                ),
                              );
                            }
                          },
                    icon: isSaving
                        ? const AppPreloader(size: 18, strokeWidth: 2, color: Color(0xFF140F0E))
                        : const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                    label: Text(
                      isSaving ? 'Saving...' : 'Save Holiday Settings',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF140F0E)),
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

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const emeraldColor = Color(0xFF06D6A0);
    const borderColor = Color(0xFF4A3830);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final isToday = _isSameDay(_selectedDate, DateTime.now());

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
          'Attendance Matrix',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.beach_access_rounded, color: Color(0xFFABA093), size: 22),
            tooltip: 'Manage Holidays',
            onPressed: () async {
              SafeHaptics.lightImpact();
              if (uid == null) return;
              final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('holidays').get();
              final data = snap.data();
              final settings = data != null ? HolidaySettings.fromMap(data) : HolidaySettings.defaultSettings;
              if (context.mounted) {
                _showHolidayManagementModal(context, uid, settings);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.calendar_view_week_rounded, color: accentColor, size: 22),
            tooltip: 'Weekly Routine Builder',
            onPressed: () {
              SafeHaptics.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoutineScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: uid == null
            ? Center(child: Text('Please sign in to log attendance.', style: GoogleFonts.plusJakartaSans(color: Colors.white)))
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('settings').doc('holidays').snapshots(),
                builder: (context, holidaySnap) {
                  final holidayData = holidaySnap.data?.data();
                  final holidaySettings = holidayData != null
                      ? HolidaySettings.fromMap(holidayData)
                      : HolidaySettings.defaultSettings;
                  final isHoliday = holidaySettings.isHoliday(_selectedDate);

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').snapshots(),
                    builder: (context, courseSnap) {
                      final courses = courseSnap.data?.docs ?? [];

                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('routine').snapshots(),
                        builder: (context, routineSnap) {
                          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('attendance_records').snapshots(),
                            builder: (context, attSnap) {
                              final allRoutines = (routineSnap.data?.docs ?? [])
                                  .map((d) => ClassRoutine.fromMap(d.data(), defaultId: d.id))
                                  .toList();

                              final allRecords = (attSnap.data?.docs ?? [])
                                  .map((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id))
                                  .toList();

                              // Overall stats across semester
                              final semesterStats = AttendanceStats.fromRecords(allRecords);

                              // Expected routines strictly respecting lifecycle boundaries on selected date
                              final expectedRoutines = RoutineCourseSyncService.sortRoutinesByTime(
                                allRoutines.where((r) => r.isActiveOnDate(_selectedDate)).toList(),
                              );

                              // Records for selected day
                              final dayRecords = allRecords.where((r) => _isSameDay(r.date, _selectedDate)).toList();
                              final Map<String, AttendanceRecord> recordMap = {
                                for (var r in dayRecords) '${r.courseId}_${r.routineId}': r,
                              };

                              // Extra classes for selected day
                              final extraRecords = dayRecords.where((r) => r.status == AttendanceStatus.extra || (r.routineId != null && r.routineId!.startsWith('extra_'))).toList();

                              // Pre-evaluate alternating locks for expected routines
                              final Map<String, bool> blockedRoutineMap = {};
                              for (var routine in expectedRoutines) {
                                final isBlocked = RoutineCourseSyncService.isAlternatingCounterpartBlocked(
                                  routine: routine,
                                  records: allRecords,
                                  selectedDate: _selectedDate,
                                );
                                blockedRoutineMap[routine.id] = isBlocked;
                              }

                              // Daily stats
                              int todayAttended = 0;
                              int todayMissed = 0;
                              int todayCanceled = 0;

                              for (var routine in expectedRoutines) {
                                final key = '${routine.courseId}_${routine.id}';
                                final rec = recordMap[key];
                                final status = rec?.status ?? AttendanceStatus.unmarked;
                                if (status == AttendanceStatus.attended || status == AttendanceStatus.extra) todayAttended++;
                                if (status == AttendanceStatus.missed) todayMissed++;
                                if (status == AttendanceStatus.canceled) todayCanceled++;
                              }
                              todayAttended += extraRecords.where((e) => e.status == AttendanceStatus.attended || e.status == AttendanceStatus.extra).length;

                              return Column(
                                children: [
                                  // Semester Stats Top Banner
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: borderColor, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Overall Attendance',
                                              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5, fontWeight: FontWeight.w600),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${semesterStats.percentage.toStringAsFixed(1)}%',
                                              style: GoogleFonts.jetBrainsMono(
                                                color: semesterStats.percentage >= 75.0 ? emeraldColor : const Color(0xFFEF4444),
                                                fontSize: 26,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${semesterStats.attended + semesterStats.extra} attended • ${semesterStats.missed} missed • ${semesterStats.canceled} canceled',
                                              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: semesterStats.percentage >= 75.0 ? emeraldColor.withValues(alpha: 0.16) : const Color(0xFFEF4444).withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            semesterStats.percentage >= 75.0 ? 'SAFE (>75%)' : 'WARNING (<75%)',
                                            style: GoogleFonts.plusJakartaSans(
                                              color: semesterStats.percentage >= 75.0 ? emeraldColor : const Color(0xFFEF4444),
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Date Navigation Bar
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: borderColor, width: 0.8),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.chevron_left_rounded, color: Color(0xFFABA093), size: 28),
                                          onPressed: () {
                                            SafeHaptics.lightImpact();
                                            setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                                          },
                                        ),
                                        InkWell(
                                          onTap: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: _selectedDate,
                                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                              lastDate: DateTime.now().add(const Duration(days: 365)),
                                            );
                                            if (picked != null) setState(() => _selectedDate = picked);
                                          },
                                          child: Column(
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    _getDayName(_selectedDate.weekday),
                                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                                  ),
                                                  if (isToday) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: accentColor.withValues(alpha: 0.18),
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Text('TODAY', style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 9.5, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _formatDate(_selectedDate),
                                                style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFABA093), size: 28),
                                          onPressed: () {
                                            SafeHaptics.lightImpact();
                                            setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                                          },
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 12),

                                  // Quick Day Stats & Add Extra Action
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          isHoliday
                                              ? 'Holiday Observed (${extraRecords.length} Makeup Classes)'
                                              : 'Daily Classes ($todayAttended Attended • $todayMissed Missed)',
                                          style: GoogleFonts.plusJakartaSans(
                                            color: isHoliday ? const Color(0xFFF59E0B) : Colors.white,
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            visualDensity: VisualDensity.compact,
                                            foregroundColor: accentColor,
                                          ),
                                          onPressed: () => _showAddExtraClassModal(context, uid, courses),
                                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                                          label: Text('Extra Class', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12, color: accentColor)),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // List of Daily Classes
                                  Expanded(
                                    child: isHoliday
                                        ? ListView(
                                            physics: const BouncingScrollPhysics(),
                                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                                            children: [
                                              // Holiday Banner
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 14),
                                                padding: const EdgeInsets.all(16),
                                                decoration: BoxDecoration(
                                                  color: cardColor,
                                                  borderRadius: BorderRadius.circular(16),
                                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(10),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: const Icon(Icons.beach_access_rounded, color: Color(0xFFF59E0B), size: 24),
                                                        ),
                                                        const SizedBox(width: 14),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                holidaySettings.weeklyHolidays.contains(_selectedDate.weekday)
                                                                    ? 'Weekly Holiday / Off-Day'
                                                                    : 'Special Holiday Observed',
                                                                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                                              ),
                                                              const SizedBox(height: 2),
                                                              Text(
                                                                'Regular class routine is paused for ${_getDayName(_selectedDate.weekday)}. You can still log makeup or extra classes using the button above.',
                                                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    if (extraRecords.isEmpty) ...[
                                                      const SizedBox(height: 14),
                                                      SizedBox(
                                                        width: double.infinity,
                                                        child: OutlinedButton.icon(
                                                          style: OutlinedButton.styleFrom(
                                                            side: const BorderSide(color: accentColor, width: 1),
                                                            foregroundColor: accentColor,
                                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                          ),
                                                          onPressed: () => _showAddExtraClassModal(context, uid, courses),
                                                          icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                                                          label: Text('Log Makeup Class on Holiday', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12)),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),

                                              // Extra / Makeup Classes on this holiday
                                              if (extraRecords.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  'MAKEUP & EXTRA CLASSES TODAY',
                                                  style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                                                ),
                                                const SizedBox(height: 8),
                                                ...extraRecords.map((extra) {
                                                  return Container(
                                                    margin: const EdgeInsets.only(bottom: 10),
                                                    padding: const EdgeInsets.all(14),
                                                    decoration: BoxDecoration(
                                                      color: cardColor,
                                                      borderRadius: BorderRadius.circular(14),
                                                      border: Border.all(color: emeraldColor.withValues(alpha: 0.3), width: 0.8),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.all(8),
                                                          decoration: BoxDecoration(
                                                            color: emeraldColor.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(10),
                                                          ),
                                                          child: const Icon(Icons.star_rounded, color: emeraldColor, size: 20),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                extra.courseName ?? 'Extra Class',
                                                                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                              ),
                                                              const SizedBox(height: 2),
                                                              Text(
                                                                '${extra.time ?? 'Extra'} • ${extra.classType ?? 'Makeup'}',
                                                                style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: emeraldColor.withValues(alpha: 0.18),
                                                            borderRadius: BorderRadius.circular(8),
                                                          ),
                                                          child: Text('EXTRA ATTENDED', style: GoogleFonts.plusJakartaSans(color: emeraldColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                }),
                                              ],
                                            ],
                                          )
                                        : (expectedRoutines.isEmpty && extraRecords.isEmpty
                                            ? Center(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(24.0),
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      const Icon(Icons.event_available_rounded, size: 50, color: Color(0xFF4A3830)),
                                                      const SizedBox(height: 14),
                                                      Text(
                                                        'No classes scheduled for ${_getDayName(_selectedDate.weekday)}',
                                                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        'Set up your weekly routine in Routine Builder or add an extra class.',
                                                        textAlign: TextAlign.center,
                                                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            : ListView(
                                                physics: const BouncingScrollPhysics(),
                                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                                                children: [
                                                  // Regular Expected Classes
                                                  ...expectedRoutines.map((routine) {
                                                    final isAlternateDetected = blockedRoutineMap[routine.id] == true;
                                                    final key = '${routine.courseId}_${routine.id}';
                                                    final rec = recordMap[key];
                                                    final status = rec?.status ?? AttendanceStatus.unmarked;
                                                    final statusColor = _getStatusColor(status);

                                                    return GestureDetector(
                                                      onTap: () {
                                                        final nextStatus = _getNextStatus(status);
                                                        _updateAttendanceStatus(
                                                          uid: uid,
                                                          courseId: routine.courseId,
                                                          routineId: routine.id,
                                                          courseName: routine.courseName,
                                                          classType: routine.classType,
                                                          time: '${routine.startTime} - ${routine.endTime}',
                                                          newStatus: nextStatus,
                                                        );
                                                      },
                                                      child: Container(
                                                        margin: const EdgeInsets.only(bottom: 12),
                                                        padding: const EdgeInsets.all(16),
                                                        decoration: BoxDecoration(
                                                          color: cardColor,
                                                          borderRadius: BorderRadius.circular(16),
                                                          border: Border.all(
                                                            color: status == AttendanceStatus.unmarked
                                                                ? borderColor
                                                                : statusColor.withValues(alpha: 0.5),
                                                            width: 0.8,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            // State-Based Interactive Indicator Icon
                                                            Container(
                                                              padding: const EdgeInsets.all(10),
                                                              decoration: BoxDecoration(
                                                                color: status == AttendanceStatus.unmarked
                                                                    ? const Color(0xFF140F0E)
                                                                    : statusColor.withValues(alpha: 0.15),
                                                                borderRadius: BorderRadius.circular(12),
                                                                border: Border.all(
                                                                  color: status == AttendanceStatus.unmarked
                                                                      ? borderColor
                                                                      : Colors.transparent,
                                                                  width: 0.8,
                                                                ),
                                                              ),
                                                              child: Icon(
                                                                _getStatusIcon(status),
                                                                color: status == AttendanceStatus.unmarked
                                                                    ? const Color(0xFFABA093)
                                                                    : statusColor,
                                                                size: 22,
                                                              ),
                                                            ),
                                                            const SizedBox(width: 14),

                                                            // Class Details
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    routine.courseName,
                                                                    style: GoogleFonts.plusJakartaSans(
                                                                      color: Colors.white,
                                                                      fontWeight: FontWeight.bold,
                                                                      fontSize: 15,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 4),
                                                                  Row(
                                                                    children: [
                                                                      Text(
                                                                        '${routine.startTime} - ${routine.endTime}',
                                                                        style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12.5),
                                                                      ),
                                                                      const SizedBox(width: 8),
                                                                      Container(
                                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                                        decoration: BoxDecoration(
                                                                          color: const Color(0xFF1C1412),
                                                                          borderRadius: BorderRadius.circular(6),
                                                                          border: Border.all(color: borderColor, width: 0.6),
                                                                        ),
                                                                        child: Text(routine.classType, style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11)),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  if (isAlternateDetected) ...[
                                                                    const SizedBox(height: 4),
                                                                    Text(
                                                                      'Alternate week slot detected',
                                                                      style: GoogleFonts.plusJakartaSans(
                                                                        color: const Color(0xFFF59E0B).withValues(alpha: 0.9),
                                                                        fontSize: 11,
                                                                        fontWeight: FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                            ),

                                                            // State Badge (Tap to Cycle status)
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                              decoration: BoxDecoration(
                                                                color: status == AttendanceStatus.unmarked
                                                                    ? const Color(0xFF1E1614)
                                                                    : statusColor.withValues(alpha: 0.18),
                                                                borderRadius: BorderRadius.circular(10),
                                                                border: Border.all(
                                                                  color: status == AttendanceStatus.unmarked
                                                                      ? borderColor
                                                                      : statusColor.withValues(alpha: 0.3),
                                                                  width: 0.8,
                                                                ),
                                                              ),
                                                              child: Text(
                                                                status.displayName,
                                                                style: GoogleFonts.plusJakartaSans(
                                                                  color: status == AttendanceStatus.unmarked
                                                                      ? const Color(0xFFABA093)
                                                                      : statusColor,
                                                                  fontWeight: FontWeight.bold,
                                                                  fontSize: 12,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }),

                                                  // Extra / Makeup Classes on this date
                                                  if (extraRecords.isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      'EXTRA & MAKEUP CLASSES',
                                                      style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    ...extraRecords.map((extra) {
                                                      return Container(
                                                        margin: const EdgeInsets.only(bottom: 10),
                                                        padding: const EdgeInsets.all(14),
                                                        decoration: BoxDecoration(
                                                          color: cardColor,
                                                          borderRadius: BorderRadius.circular(14),
                                                          border: Border.all(color: emeraldColor.withValues(alpha: 0.3), width: 0.8),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding: const EdgeInsets.all(8),
                                                              decoration: BoxDecoration(
                                                                color: emeraldColor.withValues(alpha: 0.15),
                                                                borderRadius: BorderRadius.circular(10),
                                                              ),
                                                              child: const Icon(Icons.star_rounded, color: emeraldColor, size: 20),
                                                            ),
                                                            const SizedBox(width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Text(
                                                                    extra.courseName ?? 'Extra Class',
                                                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                                                  ),
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    '${extra.time ?? 'Extra'} • ${extra.classType ?? 'Makeup'}',
                                                                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                              decoration: BoxDecoration(
                                                                color: emeraldColor.withValues(alpha: 0.18),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: Text('EXTRA ATTENDED', style: GoogleFonts.plusJakartaSans(color: emeraldColor, fontWeight: FontWeight.bold, fontSize: 10)),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }),
                                                  ],
                                                ],
                                              )),
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
              ),
      ),
    );
  }
}
