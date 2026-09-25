import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';

import '../constants/app_config.dart';
import '../core/constants/app_constants.dart';
import '../models/course_model.dart';
import '../models/routine_models.dart';
import '../widgets/app_preloader.dart';
import '../widgets/compact_loading_dialog.dart';
import '../widgets/multi_modal_import_sheet.dart';
import 'attendance_matrix_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Type alias for WeeklyClassRoutineScreen
typedef WeeklyClassRoutineScreen = RoutineScreen;

/// Weekly Class Routine Builder & Schedule Manager Screen
class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> {
  // Days of week ordered Saturday to Friday (Standard Bangladesh University week)
  final List<int> _weekdays = [
    DateTime.saturday,
    DateTime.sunday,
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  ];

  late int _selectedDay;

  @override
  void initState() {
    super.initState();
    // Default to today's weekday
    final today = DateTime.now().weekday;
    _selectedDay = _weekdays.contains(today) ? today : DateTime.sunday;
  }

  String _getDayName(int day) {
    switch (day) {
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

  String _getDayShort(int day) {
    switch (day) {
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      default:
        return 'Day';
    }
  }

  /// TASK 2: Routine Auto-Sync helper ensuring baseline Course document exists in Firestore
  Future<String> _ensureCourseExists({
    required String uid,
    required String courseId,
    required String rawName,
    required String classType,
  }) async {
    final coursesCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('courses');

    String code = rawName.trim();
    if (rawName.contains(' - ')) {
      final parts = rawName.split(' - ');
      code = parts.first.trim();
    } else if (rawName.contains(': ')) {
      final parts = rawName.split(': ');
      code = parts.first.trim();
    } else if (rawName.contains(' • ')) {
      final parts = rawName.split(' • ');
      code = parts.first.trim();
    }

    if (courseId.isNotEmpty) {
      final docSnap = await coursesCol.doc(courseId).get();
      if (docSnap.exists) return courseId;
    }

    // Check users/{uid}/courses for this code
    final existing = await coursesCol.get();
    for (final doc in existing.docs) {
      final existingCode = (doc.data()['courseCode'] as String? ?? '').toLowerCase().trim();
      if (code.isNotEmpty && existingCode == code.toLowerCase()) {
        return doc.id;
      }
    }

    // If missing, create a new Course document setting courseCode: routineCode and courseName: "Tap to edit name"
    final newDoc = courseId.isNotEmpty ? coursesCol.doc(courseId) : coursesCol.doc();
    final isLab = classType.toLowerCase().contains('lab') || classType.toLowerCase().contains('sessional');

    await newDoc.set({
      'id': newDoc.id,
      'courseCode': code.isNotEmpty ? code : 'COURSE',
      'courseName': 'Tap to edit name',
      'creditHours': isLab ? 1.5 : 3.0,
      'courseType': isLab ? 'Sessional/Lab' : 'Theory',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return newDoc.id;
  }

  /// Helper to format raw course names, fixing duplicates like "MATH 159 - MATH 159"
  /// and ensuring clean display like "MATH 159 • Calculus II"
  String _formatCourseTitle(String rawName, List<QueryDocumentSnapshot<Map<String, dynamic>>> courses) {
    String code = rawName.trim();
    String title = '';

    if (rawName.contains(' • ')) {
      final parts = rawName.split(' • ');
      code = parts.first.trim();
      title = parts.length > 1 ? parts.sublist(1).join(' • ').trim() : '';
    } else if (rawName.contains(' - ')) {
      final parts = rawName.split(' - ');
      code = parts.first.trim();
      title = parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '';
    } else if (rawName.contains(': ')) {
      final parts = rawName.split(': ');
      code = parts.first.trim();
      title = parts.length > 1 ? parts.sublist(1).join(': ').trim() : '';
    } else if (rawName.contains('(') && rawName.contains(')')) {
      final open = rawName.indexOf('(');
      final close = rawName.lastIndexOf(')');
      code = rawName.substring(0, open).trim();
      title = rawName.substring(open + 1, close).trim();
    }

    // Check if title is redundant, placeholder, or identical to code
    final isRedundant = title.isEmpty ||
        title.toLowerCase() == code.toLowerCase() ||
        title.toLowerCase() == 'tap to edit name';

    if (isRedundant) {
      for (final doc in courses) {
        final dCode = (doc.data()['courseCode'] as String? ?? '').trim();
        if (dCode.isNotEmpty && dCode.toLowerCase() == code.toLowerCase()) {
          final dName = (doc.data()['courseName'] as String? ?? '').trim();
          if (dName.isNotEmpty &&
              dName.toLowerCase() != 'tap to edit name' &&
              dName.toLowerCase() != code.toLowerCase()) {
            title = dName;
            break;
          }
        }
      }
    }

    if (title.isNotEmpty &&
        title.toLowerCase() != code.toLowerCase() &&
        title.toLowerCase() != 'tap to edit name') {
      return '$code • $title';
    }
    return code;
  }

  static TimeOfDay parseTimeString(String? raw, TimeOfDay fallback) {
    if (raw == null || raw.trim().isEmpty) return fallback;
    try {
      final str = raw.trim();
      final isPM = str.toUpperCase().contains('PM');
      final isAM = str.toUpperCase().contains('AM');
      final clean = str.replaceAll(RegExp(r'[a-zA-Z]'), '').trim();
      final parts = clean.split(':');
      if (parts.length >= 2) {
        int h = int.parse(parts[0].trim());
        int m = int.parse(parts[1].trim());
        if (isPM && h < 12) h += 12;
        if (isAM && h == 12) h = 0;
        return TimeOfDay(hour: h % 24, minute: m % 60);
      }
    } catch (_) {}
    return fallback;
  }

  static TimeOfDay calculateDefaultEndTime(TimeOfDay start, String type) {
    if (type == 'Sessional' || type == 'Lab') {
      return TimeOfDay(hour: (start.hour + 3) % 24, minute: start.minute);
    } else {
      final totalMins = start.minute + 50;
      return TimeOfDay(hour: (start.hour + (totalMins ~/ 60)) % 24, minute: totalMins % 60);
    }
  }

  Widget _buildRecurrenceChip(
    String label,
    String value,
    String current,
    ValueChanged<String> onSelected,
  ) {
    final isSel = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSel,
      selectedColor: const Color(0xFFF2B78A),
      backgroundColor: const Color(0xFF1C1412),
      side: BorderSide(
        color: isSel ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
        width: 0.8,
      ),
      labelStyle: GoogleFonts.plusJakartaSans(
        color: isSel ? const Color(0xFF140F0E) : const Color(0xFFABA093),
        fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
        fontSize: 11.5,
      ),
      onSelected: (sel) {
        if (sel) onSelected(value);
      },
    );
  }

  void _showAddClassModal(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> courses, {ClassRoutine? existing}) {
    final sortedCourses = CourseService.sortByCourseCode(
      courses,
      (d) => d.data()['courseCode'] as String? ?? '',
    );
    final customCourseCtrl = TextEditingController(text: existing?.courseName ?? '');
    String selectedCourseId = existing?.courseId ?? (sortedCourses.isNotEmpty ? sortedCourses.first.id : generateRoutineId('course'));
    String selectedCourseName = existing?.courseName ?? (sortedCourses.isNotEmpty ? (sortedCourses.first.data()['courseCode'] as String? ?? 'Course') : '');
    bool isCustomCourse = courses.isEmpty;
    int selectedDay = existing?.dayOfWeek ?? _selectedDay;
    String classType = existing?.classType ?? 'Theory';
    final initialStart = parseTimeString(existing?.startTime, const TimeOfDay(hour: 9, minute: 0));
    TimeOfDay startTime = initialStart;
    TimeOfDay endTime = existing?.endTime != null
        ? parseTimeString(existing!.endTime, calculateDefaultEndTime(initialStart, classType))
        : calculateDefaultEndTime(initialStart, classType);
    // Mid-semester additions default strictly to 'weekly' unless explicitly chosen as Biweekly
    String recurrence = existing != null
        ? (existing.recurrence.isNotEmpty ? existing.recurrence : (existing.isAlternating ? 'biweekly_a' : 'weekly'))
        : 'weekly';
    String? pairedClassId = existing?.pairedClassId;
    final roomCtrl = TextEditingController(text: existing?.roomNumber ?? '');
    DateTime? effectiveFrom = existing?.effectiveFrom;
    DateTime? effectiveUntil = existing?.effectiveUntil;
    String? selectedTeacherId = existing?.teacherId;
    final altLabelCtrl = TextEditingController(
      text: (existing != null && existing.courseName.contains('(Alt')
          ? existing.courseName.split('(Alt').last.replaceAll(')', '').trim()
          : (existing != null && existing.courseName.contains('(')
              ? existing.courseName.split('(').last.replaceAll(')', '').trim()
              : '')),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final int startMins = startTime.hour * 60 + startTime.minute;
          final int endMins = endTime.hour * 60 + endTime.minute;
          final bool isTimeInvalid = endMins <= startMins;

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
                          const Icon(Icons.schedule_rounded, color: Color(0xFFF2B78A), size: 22),
                          const SizedBox(width: 10),
                          Text(
                            existing != null ? 'Edit Class' : 'Add Class to Routine',
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

                  // Course Selector / Input
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('COURSE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                      if (courses.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              isCustomCourse = !isCustomCourse;
                              if (isCustomCourse) {
                                selectedCourseId = generateRoutineId('course');
                              } else {
                                selectedCourseId = sortedCourses.first.id;
                                final d = sortedCourses.first.data();
                                selectedCourseName = d['courseCode'] as String? ?? 'Course';
                              }
                            });
                          },
                          child: Text(
                            isCustomCourse ? 'Choose from list' : '+ Type new course',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (isCustomCourse || courses.isEmpty)
                    TextField(
                      controller: customCourseCtrl,
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
                      decoration: InputDecoration(
                        hintText: 'e.g. CSE 101 - Algorithms',
                        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF140F0E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2)),
                      ),
                      onChanged: (val) {
                        selectedCourseName = val.trim();
                      },
                    )
                  else
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
                          items: sortedCourses.map((doc) {
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
                                final doc = sortedCourses.firstWhere((d) => d.id == val);
                                final code = doc.data()['courseCode'] as String? ?? 'Course';
                                final name = doc.data()['courseName'] as String? ?? '';
                                selectedCourseName = name.isNotEmpty && name != 'Tap to edit name' ? '$code • $name' : code;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),

                  // Day of Week Selector
                  Text('DAY OF WEEK', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _weekdays.map((day) {
                        final isSel = day == selectedDay;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(_getDayShort(day)),
                            selected: isSel,
                            selectedColor: const Color(0xFFF2B78A),
                            backgroundColor: const Color(0xFF1C1412),
                            side: BorderSide(color: isSel ? const Color(0xFFF2B78A) : const Color(0xFF4A3830), width: 0.8),
                            labelStyle: GoogleFonts.plusJakartaSans(
                              color: isSel ? const Color(0xFF140F0E) : const Color(0xFFABA093),
                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                              fontSize: 12,
                            ),
                            onSelected: (val) {
                              if (val) setModalState(() => selectedDay = day);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Time Selectors
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('START TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: startTime);
                                if (t != null) {
                                  setModalState(() {
                                    startTime = t;
                                    final sM = t.hour * 60 + t.minute;
                                    final eM = endTime.hour * 60 + endTime.minute;
                                    if (eM <= sM) {
                                      endTime = calculateDefaultEndTime(t, classType);
                                    }
                                  });
                                }
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('END TIME', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final t = await showTimePicker(context: context, initialTime: endTime);
                                if (t != null) setModalState(() => endTime = t);
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF140F0E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isTimeInvalid ? const Color(0xFFEF4444) : const Color(0xFF4A3830),
                                    width: isTimeInvalid ? 1.2 : 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      endTime.format(context),
                                      style: GoogleFonts.jetBrainsMono(
                                        color: isTimeInvalid ? const Color(0xFFEF4444) : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Icon(
                                      Icons.access_time_filled_rounded,
                                      color: isTimeInvalid ? const Color(0xFFEF4444) : const Color(0xFFF2B78A),
                                      size: 16,
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
                  if (isTimeInvalid) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'End time cannot precede or equal start time (${startTime.format(context)}).',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Class Type & Room
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
                                  items: ['Theory', 'Lab', 'Sessional', 'Tutorial'].map((t) {
                                    return DropdownMenuItem(value: t, child: Text(t));
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setModalState(() {
                                        classType = val;
                                        if (existing == null) {
                                          endTime = calculateDefaultEndTime(startTime, val);
                                        }
                                      });
                                    }
                                  },
                                ),
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
                            Text('ROOM / LAB (OPTIONAL)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: roomCtrl,
                              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. Room 402',
                                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                                filled: true,
                                fillColor: const Color(0xFF140F0E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Assigned Instructor (Optional)
                  Builder(
                    builder: (context) {
                      List<Map<String, dynamic>> availableTeachers = [];
                      if (!isCustomCourse && courses.isNotEmpty) {
                        final match = courses.where((d) => d.id == selectedCourseId).firstOrNull;
                        if (match != null) {
                          final rawT = match.data()['teachers'];
                          if (rawT is List) {
                            availableTeachers = rawT
                                .whereType<Map>()
                                .map((m) => Map<String, dynamic>.from(m))
                                .where((m) => (m['isActive'] as bool? ?? true))
                                .toList();
                          }
                        }
                      }

                      if (availableTeachers.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ASSIGNED INSTRUCTOR (OPTIONAL)',
                              style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF140F0E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: availableTeachers.any((t) => t['id'] == selectedTeacherId)
                                    ? selectedTeacherId
                                    : null,
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1C1412),
                                style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Unassigned / Common Class',
                                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                                  ),
                                  ...availableTeachers.map((t) {
                                    final id = t['id'] as String? ?? '';
                                    final name = t['name'] as String? ?? 'Instructor';
                                    final initials = t['initials'] as String? ?? '';
                                    final label = initials.isNotEmpty ? '$name ($initials)' : name;
                                    return DropdownMenuItem<String?>(
                                      value: id,
                                      child: Text(label, overflow: TextOverflow.ellipsis),
                                    );
                                  }),
                                ],
                                onChanged: (val) {
                                  setModalState(() => selectedTeacherId = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                  ),

                  // Recurrence / Frequency Selector (Screenshot 1)
                  Text(
                    'Class Schedule',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildRecurrenceChip(
                          'Every Week',
                          'weekly',
                          recurrence,
                          (val) => setModalState(() => recurrence = val),
                        ),
                        const SizedBox(width: 8),
                        _buildRecurrenceChip(
                          'Every Other Week (Week A)',
                          'biweekly_a',
                          recurrence,
                          (val) => setModalState(() => recurrence = val),
                        ),
                        const SizedBox(width: 8),
                        _buildRecurrenceChip(
                          'Every Other Week (Week B)',
                          'biweekly_b',
                          recurrence,
                          (val) => setModalState(() => recurrence = val),
                        ),
                      ],
                    ),
                  ),

                  // Quick Flip Rotation Button for Biweekly Slots
                  if (recurrence == 'biweekly_a' || recurrence == 'biweekly_b') ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {
                        SafeHaptics.mediumImpact();
                        setModalState(() {
                          recurrence = recurrence == 'biweekly_a' ? 'biweekly_b' : 'biweekly_a';
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF241C1A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.5), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF2B78A), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '⇄ Flip Rotation (Current: ${recurrence == 'biweekly_a' ? 'Week A / Odd' : 'Week B / Even'})',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFF2B78A),
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // If either Biweekly option is selected: reveal optional dropdown
                  if (recurrence == 'biweekly_a' || recurrence == 'biweekly_b') ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'LINK ALTERNATING CLASS (OPTIONAL)',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        if (pairedClassId != null && pairedClassId!.isNotEmpty)
                          GestureDetector(
                            onTap: () => setModalState(() => pairedClassId = null),
                            child: Text(
                              'Clear link',
                              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF140F0E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: pairedClassId,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1C1412),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          hint: Text(
                            'None / Keep Blank (Free week)',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                          ),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'None / Keep Blank (Free week)',
                                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                              ),
                            ),
                            ...sortedCourses.map((doc) {
                              final data = doc.data();
                              final code = data['courseCode'] as String? ?? 'Course';
                              final name = data['courseName'] as String? ?? '';
                              final baseLabel = (name.isNotEmpty && name != 'Tap to edit name') ? '$code • $name' : code;
                              final isCurrentCourse = doc.id == selectedCourseId;
                              final label = isCurrentCourse ? '$baseLabel (Same Course / Alt Section)' : baseLabel;
                              return DropdownMenuItem<String?>(
                                value: doc.id,
                                child: Text(label, overflow: TextOverflow.ellipsis),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            setModalState(() => pairedClassId = val);
                          },
                        ),
                      ),
                    ),
                    if (pairedClassId != null && pairedClassId == selectedCourseId) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: altLabelCtrl,
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. Section B, Alt Week, or Room 302',
                          labelText: 'DISTINGUISHING ROOM / SECTION LABEL (OPTIONAL)',
                          labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 10.5, fontWeight: FontWeight.bold),
                          hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                          filled: true,
                          fillColor: const Color(0xFF140F0E),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      recurrence == 'biweekly_a'
                          ? 'Active on Odd weeks (Week A). On Even weeks, ${pairedClassId != null ? "automatically swaps to alternating class." : "free week."}'
                          : 'Active on Even weeks (Week B). On Odd weeks, ${pairedClassId != null ? "automatically swaps to alternating class." : "free week."}',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // When does this class run? / Lifecycle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'When does this class run?',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      if (effectiveFrom != null || effectiveUntil != null)
                        GestureDetector(
                          onTap: () => setModalState(() {
                            effectiveFrom = null;
                            effectiveUntil = null;
                          }),
                          child: Text(
                            'Reset to Term',
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: effectiveFrom ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              builder: (context, child) => Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFF2B78A),
                                    onPrimary: Color(0xFF110D0C),
                                    surface: Color(0xFF1C1412),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setModalState(() => effectiveFrom = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF140F0E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: effectiveFrom != null ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('First Class', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  effectiveFrom != null
                                      ? '${effectiveFrom!.day}/${effectiveFrom!.month}/${effectiveFrom!.year}'
                                      : 'First Class: Term Start',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: effectiveFrom != null ? const Color(0xFFF2B78A) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: effectiveUntil ?? (effectiveFrom ?? DateTime.now()).add(const Duration(days: 90)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                              builder: (context, child) => Theme(
                                data: ThemeData.dark().copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFF2B78A),
                                    onPrimary: Color(0xFF110D0C),
                                    surface: Color(0xFF1C1412),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null) {
                              setModalState(() => effectiveUntil = picked);
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF140F0E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: effectiveUntil != null ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Last Class', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  effectiveUntil != null
                                      ? '${effectiveUntil!.day}/${effectiveUntil!.month}/${effectiveUntil!.year}'
                                      : 'Last Class: Term End',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: effectiveUntil != null ? const Color(0xFFF2B78A) : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return;

                        if (isTimeInvalid) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFFEF4444),
                              content: Text('End time cannot precede or equal start time.'),
                            ),
                          );
                          return;
                        }

                        final courseNameToSave = isCustomCourse ? customCourseCtrl.text.trim() : selectedCourseName.trim();
                        if (courseNameToSave.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFFEF4444),
                              content: Text('Please enter or select a course name.'),
                            ),
                          );
                          return;
                        }

                        // Ensure course exists using RoutineCourseSyncService
                        final effectiveCourseId = await RoutineCourseSyncService.ensureCourseExists(
                          uid: uid,
                          courseId: selectedCourseId,
                          rawName: courseNameToSave,
                          classType: classType,
                        );

                        final item = ClassRoutine(
                          id: existing?.id,
                          courseId: effectiveCourseId,
                          courseName: courseNameToSave,
                          dayOfWeek: selectedDay,
                          startTime: startTime.format(context),
                          endTime: endTime.format(context),
                          classType: classType,
                          roomNumber: roomCtrl.text.trim().isNotEmpty ? roomCtrl.text.trim() : null,
                          teacherId: selectedTeacherId,
                          isAlternating: recurrence == 'biweekly_a' || recurrence == 'biweekly_b',
                          recurrence: (recurrence == 'biweekly_a' || recurrence == 'biweekly_b') ? recurrence : 'weekly',
                          pairedClassId: (recurrence == 'biweekly_a' || recurrence == 'biweekly_b') ? pairedClassId : null,
                          effectiveFrom: effectiveFrom,
                          effectiveUntil: effectiveUntil,
                        );

                        try {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc(item.id)
                              .set(item.toMap(), SetOptions(merge: true));

                          // Symmetrically link counterpart if selected
                          if (pairedClassId != null && pairedClassId!.isNotEmpty) {
                            try {
                              final pairedCourseDocs = courses.where((d) => d.id == pairedClassId).toList();
                              if (pairedCourseDocs.isNotEmpty) {
                                final pData = pairedCourseDocs.first.data();
                                final pCode = pData['courseCode'] as String? ?? 'Course';
                                final pName = pData['courseName'] as String? ?? '';
                                final pBaseTitle = (pName.isNotEmpty && pName != 'Tap to edit name') ? '$pCode • $pName' : pCode;
                                final altDistinguisher = altLabelCtrl.text.trim();
                                final pTitle = (pairedClassId == effectiveCourseId && altDistinguisher.isNotEmpty)
                                    ? '$pBaseTitle ($altDistinguisher)'
                                    : pBaseTitle;
                                final oppositeRecurrence = recurrence == 'biweekly_a' ? 'biweekly_b' : 'biweekly_a';

                                final existingCounterpart = await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .collection('routine')
                                    .where('dayOfWeek', isEqualTo: selectedDay)
                                    .where('courseId', isEqualTo: pairedClassId)
                                    .get();

                                final candidateDocs = existingCounterpart.docs.where((d) => d.id != item.id).toList();

                                if (candidateDocs.isNotEmpty) {
                                  await candidateDocs.first.reference.set({
                                    'isAlternating': true,
                                    'recurrence': oppositeRecurrence,
                                    'pairedClassId': effectiveCourseId,
                                    if (pairedClassId == effectiveCourseId && altDistinguisher.isNotEmpty)
                                      'courseName': pTitle,
                                    'startTime': startTime.format(context),
                                    'endTime': endTime.format(context),
                                    if (effectiveFrom != null) 'effectiveFrom': Timestamp.fromDate(effectiveFrom!),
                                    if (effectiveUntil != null) 'effectiveUntil': Timestamp.fromDate(effectiveUntil!),
                                    'updatedAt': FieldValue.serverTimestamp(),
                                  }, SetOptions(merge: true));
                                } else {
                                  final counterpart = ClassRoutine(
                                    courseId: pairedClassId!,
                                    courseName: pTitle,
                                    dayOfWeek: selectedDay,
                                    startTime: startTime.format(context),
                                    endTime: endTime.format(context),
                                    classType: classType,
                                    roomNumber: roomCtrl.text.trim().isNotEmpty ? roomCtrl.text.trim() : null,
                                    isAlternating: true,
                                    recurrence: oppositeRecurrence,
                                    pairedClassId: effectiveCourseId,
                                    effectiveFrom: effectiveFrom,
                                    effectiveUntil: effectiveUntil,
                                  );
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(uid)
                                      .collection('routine')
                                      .doc(counterpart.id)
                                      .set(counterpart.toMap(), SetOptions(merge: true));
                                }
                              }
                            } catch (e) {
                              debugPrint('Error syncing alternating class: $e');
                            }
                          }
                        } catch (e) {
                          debugPrint('Error saving class routine: $e');
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              content: Text('Saved class on ${_getDayName(selectedDay)}!'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                      label: Text(
                        existing != null ? 'Update Class' : 'Save to Routine',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF140F0E), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
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

  void _deleteClass(BuildContext context, String uid, String routineId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF382A24), width: 0.8),
        ),
        title: Text('Remove Class Routine', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How would you like to remove this recurring class?',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF241C1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4A3830)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.archive_rounded, color: Color(0xFFF2B78A), size: 18),
                      const SizedBox(width: 8),
                      Text('End from today forward (Default)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Preserves all previous attendance records and past class history intact.',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete_all'),
            child: Text('Delete All Records', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 12)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, 'end_today'),
            child: Text('End From Today', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result == 'end_today') {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('routine').doc(routineId).update({
        'effectiveUntil': Timestamp.fromDate(yesterday),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            content: Text('Class ended from today forward. Past attendance history preserved!'),
          ),
        );
      }
    } else if (result == 'delete_all') {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('routine').doc(routineId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Routine template deleted.'),
          ),
        );
      }
    }
  }

  static Map<String, dynamic>? _findTeacherInCourses(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
    String courseId,
    String teacherId,
  ) {
    for (final c in courses) {
      if (c.id == courseId) {
        final raw = c.data()['teachers'];
        if (raw is List) {
          for (final t in raw) {
            if (t is Map && t['id'] == teacherId) {
              return Map<String, dynamic>.from(t);
            }
          }
        }
        break;
      }
    }
    return null;
  }

  void _showClassSwapDialog(
    BuildContext context,
    String uid,
    ClassRoutine routine,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    bool isTemporary = true;
    DateTime swapDate = DateTime.now();
    while (swapDate.weekday != routine.dayOfWeek) {
      swapDate = swapDate.add(const Duration(days: 1));
    }
    String selectedRepCourseId = routine.courseId;
    String? selectedRepTeacherId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final repCourseDoc = courses.where((d) => d.id == selectedRepCourseId).firstOrNull;
          final repCourseName = repCourseDoc != null
              ? (repCourseDoc.data()['courseCode'] as String? ?? 'Course')
              : routine.courseName;

          List<Map<String, dynamic>> repTeachers = [];
          if (repCourseDoc != null) {
            final raw = repCourseDoc.data()['teachers'];
            if (raw is List) {
              repTeachers = raw
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .where((m) => (m['isActive'] as bool? ?? true))
                  .toList();
            }
          }

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
                          const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF2B78A), size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Class Swap / Substitution',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Substitute an individual lecture or permanently adjust schedule slot.',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),

                  // Swap mode selection
                  Text('SUBSTITUTION TYPE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('One-off Date')),
                          selected: isTemporary,
                          selectedColor: const Color(0xFFF2B78A),
                          backgroundColor: const Color(0xFF140F0E),
                          side: BorderSide(color: isTemporary ? const Color(0xFFF2B78A) : const Color(0xFF4A3830)),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            color: isTemporary ? const Color(0xFF140F0E) : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => isTemporary = true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Permanent Swap')),
                          selected: !isTemporary,
                          selectedColor: const Color(0xFFF2B78A),
                          backgroundColor: const Color(0xFF140F0E),
                          side: BorderSide(color: !isTemporary ? const Color(0xFFF2B78A) : const Color(0xFF4A3830)),
                          labelStyle: GoogleFonts.plusJakartaSans(
                            color: !isTemporary ? const Color(0xFF140F0E) : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            if (val) setModalState(() => isTemporary = false);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  if (isTemporary) ...[
                    Text('TARGET DATE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: swapDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (picked != null) {
                          setModalState(() => swapDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF140F0E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${swapDate.day}/${swapDate.month}/${swapDate.year} (${_getDayShort(swapDate.weekday)})',
                              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                            ),
                            const Icon(Icons.calendar_today_rounded, color: Color(0xFFF2B78A), size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Replacement Course Selector
                  Text('REPLACEMENT COURSE', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
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
                        value: selectedRepCourseId,
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
                              selectedRepCourseId = val;
                              selectedRepTeacherId = null;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Replacement Instructor
                  if (repTeachers.isNotEmpty) ...[
                    Text('REPLACEMENT INSTRUCTOR (OPTIONAL)', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF140F0E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: selectedRepTeacherId,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1C1412),
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Same / Default Instructor', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                            ),
                            ...repTeachers.map((t) {
                              final id = t['id'] as String? ?? '';
                              final name = t['name'] as String? ?? 'Instructor';
                              final initials = t['initials'] as String? ?? '';
                              final label = initials.isNotEmpty ? '$name ($initials)' : name;
                              return DropdownMenuItem<String?>(value: id, child: Text(label, overflow: TextOverflow.ellipsis));
                            }),
                          ],
                          onChanged: (val) => setModalState(() => selectedRepTeacherId = val),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF140F0E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          if (isTemporary) {
                            final overrideRef = FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('routine_overrides')
                                .doc();
                            final override = RoutineSlotOverride(
                              overrideId: overrideRef.id,
                              originalSlotId: routine.id,
                              targetDate: DateFormat('yyyy-MM-dd').format(swapDate),
                              replacementCourseId: selectedRepCourseId,
                              replacementCourseName: repCourseName,
                              replacementTeacherId: selectedRepTeacherId,
                              isTemporarySwap: true,
                            );
                            await overrideRef.set(override.toMap());
                          } else {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('routine')
                                .doc(routine.id)
                                .update({
                              'courseId': selectedRepCourseId,
                              'courseName': repCourseName,
                              'teacherId': selectedRepTeacherId,
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          }

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                content: Text(isTemporary
                                    ? 'Class substitution recorded for ${swapDate.day}/${swapDate.month}!'
                                    : 'Routine slot permanently updated!'),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error swapping routine slot: $e');
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                      label: Text(
                        isTemporary ? 'Apply Substitution' : 'Apply Permanent Swap',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF140F0E), fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
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

  void _showHandoverDialog(
    BuildContext context,
    String uid,
    ClassRoutine routine,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    DateTime handoverDate = DateTime.now();
    String? incomingTeacherId;

    final courseDoc = courses.where((d) => d.id == routine.courseId).firstOrNull;
    List<Map<String, dynamic>> courseTeachers = [];
    if (courseDoc != null) {
      final raw = courseDoc.data()['teachers'];
      if (raw is List) {
        courseTeachers = raw
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((m) => (m['isActive'] as bool? ?? true))
            .toList();
      }
    }

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
                          const Icon(Icons.transfer_within_a_station_rounded, color: Color(0xFFF2B78A), size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Split-Semester Handover',
                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Seamlessly transfer this course slot to another instructor mid-semester. Prior attendance and routine history remain completely preserved.',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),

                  Text('HANDOVER DATE (LAST DATE OF CURRENT TEACHER)',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: handoverDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 60)),
                        lastDate: DateTime.now().add(const Duration(days: 120)),
                      );
                      if (picked != null) {
                        setModalState(() => handoverDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF140F0E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${handoverDate.day}/${handoverDate.month}/${handoverDate.year}',
                            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                          ),
                          const Icon(Icons.calendar_today_rounded, color: Color(0xFFF2B78A), size: 16),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text('INCOMING INSTRUCTOR',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140F0E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: incomingTeacherId,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF1C1412),
                        style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Select incoming instructor...', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
                          ),
                          ...courseTeachers.map((t) {
                            final id = t['id'] as String? ?? '';
                            final name = t['name'] as String? ?? 'Instructor';
                            final initials = t['initials'] as String? ?? '';
                            final label = initials.isNotEmpty ? '$name ($initials)' : name;
                            return DropdownMenuItem<String?>(value: id, child: Text(label, overflow: TextOverflow.ellipsis));
                          }),
                        ],
                        onChanged: (val) => setModalState(() => incomingTeacherId = val),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF140F0E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        try {
                          final batch = FirebaseFirestore.instance.batch();

                          // 1. Current slot concludes on handoverDate
                          final currRef = FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc(routine.id);
                          batch.update(currRef, {
                            'effectiveUntil': handoverDate.toIso8601String(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });

                          // 2. New slot starts the next day
                          final newRef = FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc();
                          final nextDay = handoverDate.add(const Duration(days: 1));
                          final newRoutine = routine.copyWith(
                            id: newRef.id,
                            teacherId: incomingTeacherId,
                            effectiveFrom: nextDay,
                            effectiveUntil: null,
                          );
                          batch.set(newRef, newRoutine.toMap());

                          await batch.commit();

                          if (context.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                content: Text('Handover recorded! Previous slot concludes on ${handoverDate.day}/${handoverDate.month}, incoming instructor starts ${nextDay.day}/${nextDay.month}.'),
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Error executing phased handover: $e');
                        }
                      },
                      icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                      label: Text(
                        'Transfer Classes (Execute Handover)',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFF140F0E), fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
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

  void _showEndClassesDialog(
    BuildContext context,
    String uid,
    ClassRoutine routine,
  ) {
    bool teacherOnly = routine.teacherId != null;
    DateTime endDate = DateTime.now();

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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_busy_rounded, color: Color(0xFFEF4444), size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Conclude / End Classes',
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'End recurring lectures from a specific date. Historical attendance records will not be deleted.',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12.5),
                ),
                const SizedBox(height: 16),

                if (routine.teacherId != null) ...[
                  Text('SCOPE OF CONCLUSION',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    value: true,
                    groupValue: teacherOnly,
                    activeColor: const Color(0xFFF2B78A),
                    contentPadding: EdgeInsets.zero,
                    title: Text('This Teacher Only (This Slot)', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Only concludes this specific instructor routine slot.', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5)),
                    onChanged: (val) => setModalState(() => teacherOnly = val ?? true),
                  ),
                  RadioListTile<bool>(
                    value: false,
                    groupValue: teacherOnly,
                    activeColor: const Color(0xFFF2B78A),
                    contentPadding: EdgeInsets.zero,
                    title: Text('All Classes for ${routine.courseName}', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Concludes all routine slots for this course across the semester.', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5)),
                    onChanged: (val) => setModalState(() => teacherOnly = val ?? false),
                  ),
                  const SizedBox(height: 12),
                ],

                Text('EFFECTIVE END DATE',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: endDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 60)),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (picked != null) {
                      setModalState(() => endDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF140F0E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${endDate.day}/${endDate.month}/${endDate.year}',
                          style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                        ),
                        const Icon(Icons.calendar_today_rounded, color: Color(0xFFF2B78A), size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      try {
                        if (teacherOnly) {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .doc(routine.id)
                              .update({
                            'effectiveUntil': endDate.toIso8601String(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          });
                        } else {
                          final snap = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .collection('routine')
                              .where('courseId', isEqualTo: routine.courseId)
                              .get();
                          final batch = FirebaseFirestore.instance.batch();
                          for (final doc in snap.docs) {
                            batch.update(doc.reference, {
                              'effectiveUntil': endDate.toIso8601String(),
                              'updatedAt': FieldValue.serverTimestamp(),
                            });
                          }
                          await batch.commit();
                        }

                        if (context.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              content: Text('Classes concluded as of ${endDate.day}/${endDate.month}/${endDate.year}. Past attendance is preserved!'),
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint('Error concluding classes: $e');
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
                    label: Text(
                      'Confirm Class Conclusion',
                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
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

  /// Dialog allowing students to update or replace their entire routine mid-semester
  /// with explicit options to preserve historical attendance vs reset fresh.
  void _showResetReplaceRoutineModal(
    BuildContext context,
    String uid, {
    List<ClassRoutine>? newBatchClasses,
    VoidCallback? onCompleted,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A3830),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.sync_rounded, color: Color(0xFFF2B78A), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Update Term Routine',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              newBatchClasses != null
                                  ? 'Applying ${newBatchClasses.length} classes to timetable'
                                  : 'Modifying or replacing weekly timetable',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFABA093),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093)),
                        onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'You are modifying or replacing the weekly timetable. How should historical class attendance be handled?',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFD8CFC7),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Option 1: Preserve Past Attendance Records (Default / Recommended)
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            setSheetState(() => isProcessing = true);
                            try {
                              await RoutineCourseSyncService.preserveHistoricalRoutineAndApplyNew(
                                uid: uid,
                                newRoutines: newBatchClasses,
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                onCompleted?.call();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFF10B981),
                                    content: Text('Past attendance records preserved! Timetable updated from today forward.'),
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() => isProcessing = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF2B78A), width: 1.2),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.verified_user_rounded, color: Color(0xFFF2B78A), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        'Preserve Past Attendance Records',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF2B78A).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Recommended',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: const Color(0xFFF2B78A),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Sets effective-until for existing routines to yesterday. New routine activates starting today. Past logs remain locked, untouched, and regular.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFABA093),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Option 2: Clear All Previous Attendance & Reset Fresh
                  InkWell(
                    onTap: isProcessing
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (dCtx) => AlertDialog(
                                backgroundColor: const Color(0xFF1C1412),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(color: Color(0xFF382A24)),
                                ),
                                title: Text(
                                  'Wipe All Past Attendance?',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                content: Text(
                                  'This action will permanently delete all attendance logs recorded for routine classes this term. This cannot be undone.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFABA093),
                                    fontSize: 13,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dCtx, false),
                                    child: Text(
                                      'Cancel',
                                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093)),
                                    ),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.pop(dCtx, true),
                                    child: Text(
                                      'Confirm Reset Fresh',
                                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirm != true) return;

                            setSheetState(() => isProcessing = true);
                            try {
                              await RoutineCourseSyncService.resetFreshRoutineAndAttendance(
                                uid: uid,
                                newRoutines: newBatchClasses,
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                onCompleted?.call();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Color(0xFFEF4444),
                                    content: Text('Timetable and past attendance records reset fresh.'),
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() => isProcessing = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Error: $e')),
                                );
                              }
                            }
                          },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.0),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFEF4444), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Clear All Previous Attendance & Reset Fresh',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Fully deletes orphaned class attendance logs and routine templates for this term; replaces cleanly with the new routine starting from term start.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFFABA093),
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (isProcessing) ...[
                    const SizedBox(height: 16),
                    const Center(child: AppPreloader(size: 28, strokeWidth: 2)),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Open Multi-Modal Intake Sheet for Smart Routine Scan
  void _showSmartImportSource(BuildContext context, List<QueryDocumentSnapshot<Map<String, dynamic>>> courses) {
    MultiModalImportSheet.show(
      context: context,
      targetType: ImportTargetType.routine,
      title: 'Smart Import Routine (AI)',
      subtitle: 'Upload timetable PDF, capture photo, or paste routine text',
      onProcessText: (text) => _processRoutineText(context, text, courses),
      onProcessImage: (bytes) => _processRoutineImageBytes(context, bytes, courses),
    );
  }

  void _processRoutineText(
    BuildContext context,
    String rawText,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    final cleanedText = rawText.trim();
    if (cleanedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Provided timetable text is empty.')),
      );
      return;
    }

    final prompt = '''You are an expert university class routine timetable parser.
Analyze the provided routine schedule text and extract all classes into a strict JSON array.
For each scheduled class, extract:
- "courseCode": String (e.g. "CSE 201", "PHY 101", etc.)
- "courseName": String (e.g. "Object Oriented Programming", or fallback to courseCode)
- "dayOfWeek": int (1 for Monday, 2 for Tuesday, 3 for Wednesday, 4 for Thursday, 5 for Friday, 6 for Saturday, 7 for Sunday)
- "startTime": String (e.g. "09:00 AM" or "08:00 AM")
- "endTime": String (e.g. "10:30 AM" or "11:00 AM")
- "classType": String ("Theory", "Lab", "Sessional", or "Tutorial")
- "roomNumber": String (e.g. "Room 302", "Lab 2", or null)
- "isAlternating": bool (Set to true if this is a bi-weekly, alternate week, odd/even week, or A/B group lab/class; otherwise false)
- "teacher": String? (Teacher name or initials if listed in the routine, or null)

Return ONLY the JSON array without any markdown fences, backticks, or extra text.

Routine Schedule Text:
$cleanedText''';

    _executeRoutineExtraction(context, courses, promptText: prompt);
  }

  void _processRoutineImageBytes(
    BuildContext context,
    Uint8List imageBytes,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    const prompt = '''You are an expert university class routine timetable parser.
Analyze the provided routine image and extract all classes into a strict JSON array.
For each scheduled class, extract:
- "courseCode": String (e.g. "CSE 201", "PHY 101", etc.)
- "courseName": String (e.g. "Object Oriented Programming", or fallback to courseCode)
- "dayOfWeek": int (1 for Monday, 2 for Tuesday, 3 for Wednesday, 4 for Thursday, 5 for Friday, 6 for Saturday, 7 for Sunday)
- "startTime": String (e.g. "09:00 AM" or "08:00 AM")
- "endTime": String (e.g. "10:30 AM" or "11:00 AM")
- "classType": String ("Theory", "Lab", "Sessional", or "Tutorial")
- "roomNumber": String (e.g. "Room 302", "Lab 2", or null)
- "isAlternating": bool (Set to true if this is a bi-weekly, alternate week, odd/even week, or A/B group lab/class; otherwise false)
- "teacher": String? (Teacher name or initials if listed on the routine, or null)

Return ONLY the JSON array without any markdown fences, backticks, or extra text.''';

    _executeRoutineExtraction(context, courses, promptText: prompt, imageBytes: imageBytes);
  }

  /// Process routine using Gemini AI with fallback models and teacher matching
  Future<void> _executeRoutineExtraction(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses, {
    required String promptText,
    Uint8List? imageBytes,
  }) async {
    if (!context.mounted) return;

    CompactLoadingDialog.show(
      context: context,
      message: 'Gemini AI is parsing your class schedule...',
    );

    try {
      final candidateModels = [
        'gemini-2.5-flash',
        AppConfig.geminiPrimaryModel,
        'gemini-3.1-flash-lite',
      ];

      String rawText = '';
      Object? lastError;

      for (final modelName in candidateModels) {
        try {
          final model = GenerativeModel(
            model: modelName,
            apiKey: AppConstants.geminiApiKey,
          );

          final GenerateContentResponse response;
          if (imageBytes != null) {
            response = await model.generateContent([
              Content.multi([
                TextPart(promptText),
                DataPart('image/jpeg', imageBytes),
              ]),
            ]);
          } else {
            response = await model.generateContent([
              Content.text(promptText),
            ]);
          }

          final candidateText = response.text?.trim() ?? '';
          if (candidateText.isNotEmpty) {
            rawText = candidateText;
            break;
          }
        } catch (e) {
          lastError = e;
          debugPrint('Gemini Routine Extraction Error ($modelName): $e');
        }
      }

      if (context.mounted) Navigator.pop(context); // Dismiss loading dialog

      if (rawText.isEmpty) {
        throw lastError ?? Exception('AI returned an empty response.');
      }

      String cleanJson = rawText;
      if (cleanJson.startsWith('```json')) cleanJson = cleanJson.substring(7);
      if (cleanJson.startsWith('```')) cleanJson = cleanJson.substring(3);
      if (cleanJson.endsWith('```')) cleanJson = cleanJson.substring(0, cleanJson.length - 3);
      cleanJson = cleanJson.trim();

      final decoded = jsonDecode(cleanJson);
      if (decoded is! List) {
        throw Exception('Unexpected response format from AI.');
      }

      final List<ClassRoutine> parsedClasses = [];
      for (final item in decoded) {
        if (item is Map) {
          final code = (item['courseCode'] as String? ?? 'Course').trim();
          final name = (item['courseName'] as String? ?? code).trim();
          final day = (item['dayOfWeek'] as num?)?.toInt() ?? DateTime.monday;
          final start = item['startTime'] as String? ?? '09:00 AM';
          final end = item['endTime'] as String? ?? '10:00 AM';
          final type = item['classType'] as String? ?? 'Theory';
          final room = item['roomNumber'] as String?;
          final isAlt = item['isAlternating'] as bool? ?? false;
          final teacherNameOrInitials = (item['teacher'] as String? ?? item['teacherInitials'] as String? ?? '').trim();

          String matchedCourseId = '';
          QueryDocumentSnapshot<Map<String, dynamic>>? matchedCourseDoc;

          for (final c in courses) {
            final cCode = (c.data()['courseCode'] as String? ?? '').toLowerCase().replaceAll(' ', '');
            final parsedClean = code.toLowerCase().replaceAll(' ', '');
            if (cCode.isNotEmpty && (cCode == parsedClean || parsedClean.contains(cCode) || cCode.contains(parsedClean))) {
              matchedCourseId = c.id;
              matchedCourseDoc = c;
              break;
            }
          }

          // Match teacher if initials/name provided and course has registered teachers
          String? matchedTeacherId;
          if (matchedCourseDoc != null && teacherNameOrInitials.isNotEmpty) {
            final courseTeachersRaw = matchedCourseDoc.data()['teachers'];
            if (courseTeachersRaw is List) {
              for (final tr in courseTeachersRaw) {
                if (tr is Map) {
                  final initials = (tr['initials'] ?? '').toString().trim().toLowerCase();
                  final tName = (tr['name'] ?? '').toString().trim().toLowerCase();
                  final query = teacherNameOrInitials.toLowerCase();
                  if ((initials.isNotEmpty && (initials == query || query.contains(initials))) ||
                      (tName.isNotEmpty && (tName == query || query.contains(tName) || tName.contains(query)))) {
                    matchedTeacherId = tr['id']?.toString();
                    break;
                  }
                }
              }
            }
          }

          // Avoid duplicated course titles like "MATH 159 - MATH 159"
          final cleanTitle = (name.isNotEmpty && name.toLowerCase() != code.toLowerCase())
              ? '$code • $name'
              : code;

          parsedClasses.add(ClassRoutine(
            courseId: matchedCourseId,
            courseName: cleanTitle,
            dayOfWeek: (day >= 1 && day <= 7) ? day : DateTime.monday,
            startTime: start,
            endTime: end,
            classType: type,
            roomNumber: room,
            isAlternating: isAlt,
            teacherId: matchedTeacherId, // Gracefully defaults to null if missing or unrecognized
          ));
        }
      }

      if (parsedClasses.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Could not detect any classes in the schedule.')),
          );
        }
        return;
      }

      if (context.mounted) {
        _showRoutineConfirmationModal(context, parsedClasses, courses);
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route is! DialogRoute);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Failed to parse routine: $e')),
        );
      }
    }
  }

  /// Review & Confirmation Modal with alternating schedule dropdown/toggles
  void _showRoutineConfirmationModal(
    BuildContext context,
    List<ClassRoutine> initialClasses,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> courses,
  ) {
    final classes = List<ClassRoutine>.from(initialClasses);
    bool isSaving = false;

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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFF2B78A), size: 20),
                            const SizedBox(width: 8),
                            Text('Confirm Scanned Routine', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('${classes.length} class(es) detected from schedule', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final c = classes[index];

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF140F0E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: c.isAlternating ? const Color(0xFFF59E0B).withValues(alpha: 0.5) : const Color(0xFF4A3830),
                            width: 0.8,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _formatCourseTitle(c.courseName, courses),
                                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () {
                                    setModalState(() => classes.removeAt(index));
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${c.dayName} • ${c.startTime} - ${c.endTime} • ${c.classType}${c.roomNumber != null ? ' (${c.roomNumber})' : ''}',
                              style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12.5),
                            ),
                            const SizedBox(height: 10),
                            const Divider(color: Color(0xFF382A24), height: 1),
                            const SizedBox(height: 10),

                            // Alternating Schedule Toggle/Dropdown
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      c.isAlternating ? Icons.sync_problem_rounded : Icons.repeat_rounded,
                                      color: c.isAlternating ? const Color(0xFFF59E0B) : const Color(0xFFF2B78A),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Schedule Type:',
                                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF241C1A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: c.isAlternating ? const Color(0xFFF59E0B) : const Color(0xFF4A3830),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<bool>(
                                      value: c.isAlternating,
                                      dropdownColor: const Color(0xFF1C1412),
                                      style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                      items: const [
                                        DropdownMenuItem(
                                          value: false,
                                          child: Text('Every Week'),
                                        ),
                                        DropdownMenuItem(
                                          value: true,
                                          child: Text('Alternating (Bi-Weekly)'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setModalState(() {
                                            classes[index] = c.copyWith(isAlternating: val);
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Assigned Instructor Selector Dropdown
                            () {
                              final matchedCourseDoc = courses.where((cd) => cd.id == c.courseId).firstOrNull;
                              final List<Teacher> teachersList = [];
                              if (matchedCourseDoc != null) {
                                final teachersRaw = matchedCourseDoc.data()['teachers'];
                                if (teachersRaw is List) {
                                  for (final tr in teachersRaw) {
                                    if (tr is Map) {
                                      teachersList.add(Teacher.fromMap(Map<String, dynamic>.from(tr)));
                                    }
                                  }
                                }
                              }

                              if (teachersList.isEmpty) return const SizedBox.shrink();

                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.person_outline_rounded, color: Color(0xFFF2B78A), size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Assigned Teacher:',
                                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF241C1A),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFF4A3830), width: 0.8),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String?>(
                                          value: c.teacherId != null && teachersList.any((t) => t.id == c.teacherId) ? c.teacherId : null,
                                          dropdownColor: const Color(0xFF1C1412),
                                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                          items: [
                                            const DropdownMenuItem<String?>(
                                              value: null,
                                              child: Text('No instructor assigned'),
                                            ),
                                            ...teachersList.map((t) => DropdownMenuItem<String?>(
                                              value: t.id,
                                              child: Text('${t.name} (${t.initials})'),
                                            )),
                                          ],
                                          onChanged: (val) {
                                            setModalState(() {
                                              classes[index] = c.copyWith(teacherId: val);
                                            });
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }(),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
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
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            if (uid == null) return;

                            // Check if student already has active routine entries in their term
                            final existingSnap = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('routine')
                                .get();
                            final yesterday = DateTime.now().subtract(const Duration(days: 1));
                            final hasActiveRoutines = existingSnap.docs.any((d) {
                              final r = ClassRoutine.fromMap(d.data(), defaultId: d.id);
                              return r.effectiveUntil == null || r.effectiveUntil!.isAfter(yesterday);
                            });

                            if (hasActiveRoutines && context.mounted) {
                              _showResetReplaceRoutineModal(
                                context,
                                uid,
                                newBatchClasses: classes,
                                onCompleted: () {
                                  Navigator.pop(ctx);
                                },
                              );
                              return;
                            }

                            setModalState(() => isSaving = true);
                            final batch = FirebaseFirestore.instance.batch();

                            await RoutineCourseSyncService.syncCoursesFromRoutines(
                              uid: uid,
                              routines: classes,
                            );

                            for (final routine in classes) {
                              final effectiveCourseId = await RoutineCourseSyncService.ensureCourseExists(
                                uid: uid,
                                courseId: routine.courseId,
                                rawName: routine.courseName,
                                classType: routine.classType,
                              );
                              final updatedRoutine = routine.copyWith(courseId: effectiveCourseId);
                              final ref = FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('routine')
                                  .doc(updatedRoutine.id);
                              batch.set(ref, updatedRoutine.toMap(), SetOptions(merge: true));
                            }

                            await batch.commit();

                            if (context.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF10B981),
                                  content: Text('Successfully imported ${classes.length} classes into your routine!'),
                                ),
                              );
                            }
                          },
                    icon: isSaving
                        ? const AppPreloader(size: 18, strokeWidth: 2, color: Color(0xFF140F0E))
                        : const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF140F0E)),
                    label: Text(
                      isSaving ? 'Saving to Routine...' : 'Confirm & Save All (${classes.length} Classes)',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFF140F0E), fontWeight: FontWeight.bold, fontSize: 14),
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
    const borderColor = Color(0xFF4A3830);
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
          'Weekly Class Routine',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, color: accentColor, size: 22),
            tooltip: 'Reset / Replace Routine',
            onPressed: () {
              SafeHaptics.lightImpact();
              if (uid != null) {
                _showResetReplaceRoutineModal(context, uid);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: accentColor, size: 22),
            tooltip: 'Smart Import Routine (AI)',
            onPressed: () async {
              SafeHaptics.lightImpact();
              if (uid == null) return;
              final courseSnap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').get();
              if (context.mounted) {
                _showSmartImportSource(context, courseSnap.docs);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_rounded, color: accentColor, size: 22),
            tooltip: 'Open Attendance Matrix',
            onPressed: () {
              SafeHaptics.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: uid == null
            ? Center(child: Text('Please sign in to view routine.', style: GoogleFonts.plusJakartaSans(color: Colors.white)))
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').snapshots(),
                builder: (context, courseSnap) {
                  final courses = courseSnap.data?.docs ?? [];

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('routine').snapshots(),
                    builder: (context, routineSnap) {
                      if (routineSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: AppPreloader(size: 44));
                      }

                      final allRoutineDocs = routineSnap.data?.docs ?? [];
                      final allRoutines = allRoutineDocs
                          .map((d) => ClassRoutine.fromMap(d.data(), defaultId: d.id))
                          .toList();

                      final today = DateTime.now();
                      final activeRoutines = allRoutines.where((r) {
                        if (r.effectiveUntil != null) {
                          final end = DateTime(r.effectiveUntil!.year, r.effectiveUntil!.month, r.effectiveUntil!.day, 23, 59, 59);
                          if (today.isAfter(end)) return false;
                        }
                        return true;
                      }).toList();

                      // Filter for selected day
                      final dayRoutines = RoutineCourseSyncService.sortRoutinesByTime(
                        activeRoutines.where((r) => r.dayOfWeek == _selectedDay).toList(),
                      );

                      return Column(
                        children: [
                          // 7-Day Weekday Tab Bar
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF140F0E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor, width: 0.8),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              child: Row(
                                children: _weekdays.map((day) {
                                  final isSel = day == _selectedDay;
                                  final count = activeRoutines.where((r) => r.dayOfWeek == day).length;

                                  return GestureDetector(
                                    onTap: () {
                                      SafeHaptics.lightImpact();
                                      setState(() => _selectedDay = day);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 160),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSel ? accentColor : const Color(0xFF1C1412),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSel ? accentColor : borderColor.withValues(alpha: 0.5),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            _getDayShort(day),
                                            style: GoogleFonts.plusJakartaSans(
                                              color: isSel ? const Color(0xFF140F0E) : const Color(0xFFABA093),
                                              fontWeight: isSel ? FontWeight.bold : FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isSel ? const Color(0xFF140F0E).withValues(alpha: 0.18) : const Color(0xFF241C1A),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$count',
                                              style: GoogleFonts.jetBrainsMono(
                                                color: isSel ? const Color(0xFF140F0E) : const Color(0xFFABA093),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),

                          // Header Action Bar
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${_getDayName(_selectedDay)} Classes',
                                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  '${dayRoutines.length} Sessions',
                                  style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12),
                                ),
                              ],
                            ),
                          ),

                          // Routine Cards List
                          Expanded(
                            child: dayRoutines.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24.0),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.calendar_today_rounded, size: 50, color: Color(0xFF4A3830)),
                                          const SizedBox(height: 14),
                                          Text(
                                            'No classes on ${_getDayName(_selectedDay)}',
                                            style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Tap "+" to add lectures or use Smart Import to scan your timetable.',
                                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
                                          ),
                                          const SizedBox(height: 16),
                                          OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: accentColor, width: 0.8),
                                              foregroundColor: accentColor,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            onPressed: () => _showSmartImportSource(context, courses),
                                            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                            label: Text('Smart Import Routine (AI)', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    physics: const BouncingScrollPhysics(),
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                                    itemCount: dayRoutines.length,
                                    itemBuilder: (context, idx) {
                                      final routine = dayRoutines[idx];
                                      final displayTitle = _formatCourseTitle(routine.courseName, courses);

                                      ClassRoutine? pairedRoutine;
                                      if (routine.pairedClassId != null) {
                                        for (final r in allRoutines) {
                                          if (r.id != routine.id &&
                                              (r.id == routine.pairedClassId || r.courseId == routine.pairedClassId)) {
                                            pairedRoutine = r;
                                            break;
                                          }
                                        }
                                      }
                                      final pairedTitle = pairedRoutine != null
                                          ? _formatCourseTitle(pairedRoutine.courseName, courses)
                                          : (routine.pairedClassId != null
                                              ? courses.where((d) => d.id == routine.pairedClassId).map((d) {
                                                  final data = d.data();
                                                  final code = data['courseCode'] as String? ?? '';
                                                  final name = data['courseName'] as String? ?? '';
                                                  final formatted = (name.isNotEmpty && name != 'Tap to edit name') ? '$code • $name' : code;
                                                  return formatted.isNotEmpty ? formatted : null;
                                                }).firstOrNull
                                              : null);

                                      final teacherMap = routine.teacherId != null
                                          ? _findTeacherInCourses(courses, routine.courseId, routine.teacherId!)
                                          : null;

                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: cardColor,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: routine.isAlternating ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : borderColor,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            // Time & Type Column
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: routine.isAlternating
                                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                                    : accentColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Icon(
                                                routine.isAlternating ? Icons.sync_problem_rounded : Icons.access_time_filled_rounded,
                                                color: routine.isAlternating ? const Color(0xFFF59E0B) : accentColor,
                                                size: 22,
                                              ),
                                            ),
                                            const SizedBox(width: 14),

                                            // Details
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          displayTitle,
                                                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                                        ),
                                                      ),
                                                      if (routine.isAlternating)
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35), width: 0.6),
                                                          ),
                                                          child: Text(
                                                            routine.recurrence == 'biweekly_a'
                                                                ? 'Week A (Odd)'
                                                                : (routine.recurrence == 'biweekly_b' ? 'Week B (Even)' : 'Alternating'),
                                                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                  if (pairedTitle != null) ...[
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.sync_alt_rounded, size: 12, color: Color(0xFFABA093)),
                                                        const SizedBox(width: 4),
                                                        Expanded(
                                                          child: Text(
                                                            'Alternates with $pairedTitle',
                                                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11, fontStyle: FontStyle.italic),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                  const SizedBox(height: 4),
                                                  Row(
                                                    children: [
                                                      Text(
                                                        '${routine.startTime} - ${routine.endTime}',
                                                        style: GoogleFonts.jetBrainsMono(
                                                          color: routine.isAlternating ? const Color(0xFFF59E0B) : accentColor,
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 12.5,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1C1412),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: borderColor, width: 0.6),
                                                        ),
                                                        child: Text(
                                                          routine.classType,
                                                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11),
                                                        ),
                                                      ),
                                                      if (routine.roomNumber != null && routine.roomNumber!.isNotEmpty) ...[
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          '• ${routine.roomNumber}',
                                                          style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 11),
                                                        ),
                                                      ],
                                                      if (teacherMap != null) ...[
                                                        const SizedBox(width: 6),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                                                            borderRadius: BorderRadius.circular(6),
                                                            border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.35), width: 0.6),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                              const Icon(Icons.person_outline_rounded, size: 11, color: Color(0xFFF2B78A)),
                                                              const SizedBox(width: 3),
                                                              Text(
                                                                teacherMap['initials']?.toString().isNotEmpty == true
                                                                    ? teacherMap['initials'].toString()
                                                                    : (teacherMap['name']?.toString() ?? 'T'),
                                                                style: GoogleFonts.plusJakartaSans(
                                                                  color: const Color(0xFFF2B78A),
                                                                  fontSize: 10.5,
                                                                  fontWeight: FontWeight.bold,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Actions
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFABA093), size: 18),
                                              color: const Color(0xFF1C1412),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                                side: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                                              ),
                                              onSelected: (val) {
                                                if (val == 'edit') {
                                                  _showAddClassModal(context, courses, existing: routine);
                                                } else if (val == 'swap') {
                                                  _showClassSwapDialog(context, uid, routine, courses);
                                                } else if (val == 'handover') {
                                                  _showHandoverDialog(context, uid, routine, courses);
                                                } else if (val == 'end_classes') {
                                                  _showEndClassesDialog(context, uid, routine);
                                                } else if (val == 'delete') {
                                                  _deleteClass(context, uid, routine.id);
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                PopupMenuItem(
                                                  value: 'swap',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.swap_horiz_rounded, color: Color(0xFFF2B78A), size: 16),
                                                      const SizedBox(width: 8),
                                                      Text('Class Swap / Substitution', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'handover',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.transfer_within_a_station_rounded, color: Color(0xFF38BDF8), size: 16),
                                                      const SizedBox(width: 8),
                                                      Text('Split-Semester Handover', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'end_classes',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.event_busy_rounded, color: Color(0xFFF59E0B), size: 16),
                                                      const SizedBox(width: 8),
                                                      Text('End Classes', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'edit',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.edit_rounded, color: Color(0xFFABA093), size: 16),
                                                      const SizedBox(width: 8),
                                                      Text('Edit Class', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                                PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 16),
                                                      const SizedBox(width: 8),
                                                      Text('Delete', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEF4444), fontSize: 13)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: accentColor,
        foregroundColor: const Color(0xFF140F0E),
        elevation: 2,
        onPressed: () {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid == null) return;
          FirebaseFirestore.instance.collection('users').doc(uid).collection('courses').get().then((snap) {
            if (context.mounted) _showAddClassModal(context, snap.docs);
          });
        },
        icon: const Icon(Icons.add_rounded, size: 22, color: Color(0xFF140F0E)),
        label: Text('Add Class to Routine', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13.5, color: const Color(0xFF140F0E))),
      ),
    );
  }
}
