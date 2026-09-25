import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/routine_models.dart';
import '../providers/user_profile_provider.dart';
import 'add_course_screen.dart';
import 'admission_archive_screen.dart';
import 'attendance_matrix_screen.dart';
import 'course_syllabus_screen.dart';
import 'routine_screen.dart';
import 'term_performance_screen.dart';
import '../services/course_service.dart';
import '../widgets/app_preloader.dart';
import '../widgets/attendance_override_dialog.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// University Dashboard Screen displaying registered courses for University Mode
class UniversityDashboardScreen extends ConsumerStatefulWidget {
  const UniversityDashboardScreen({super.key});

  @override
  ConsumerState<UniversityDashboardScreen> createState() => _UniversityDashboardScreenState();
}

class _UniversityDashboardScreenState extends ConsumerState<UniversityDashboardScreen> {
  bool _isSyncingCourses = false;

  /// TASK 1: Scans active routine across all 7 days and creates missing course entries
  Future<void> _syncCoursesWithRoutine() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    setState(() => _isSyncingCourses = true);
    SafeHaptics.mediumImpact();

    try {
      final newlyCreated = await RoutineCourseSyncService.syncCoursesFromFirestoreRoutine(uid);
      if (!mounted) return;

      if (newlyCreated.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF110D0C), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Synced ${newlyCreated.length} course(s): ${newlyCreated.join(', ')}',
                    style: const TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1C1412),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFF2B78A), width: 0.5),
            ),
            content: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFF2B78A), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All routine courses are already synchronized.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to sync courses with routine: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingCourses = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);

    final userProfile = ref.watch(userProfileProvider);
    final universityName = userProfile.universityName?.trim().isNotEmpty == true
        ? userProfile.universityName!.trim()
        : 'University';

    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'University Dashboard',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              universityName,
              style: const TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_view_week_rounded, color: accentColor, size: 22),
            tooltip: 'Weekly Class Routine',
            onPressed: () {
              SafeHaptics.lightImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoutineScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: accentColor, size: 22),
            color: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF4A3830)),
            ),
            onSelected: (val) {
              SafeHaptics.lightImpact();
              if (val == 'sync') {
                if (!_isSyncingCourses) _syncCoursesWithRoutine();
              } else if (val == 'matrix') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AttendanceMatrixScreen()),
                );
              } else if (val == 'cgpa') {
                final uni = userProfile.universityName?.trim();
                final term = userProfile.term?.trim() ?? '1';
                if (uni == null || uni.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: Color(0xFF241C1A),
                      behavior: SnackBarBehavior.floating,
                      content: Text('Loading profile data...'),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TermPerformanceScreen(
                      universityName: uni,
                      term: term,
                    ),
                  ),
                );
              } else if (val == 'settings') {
                _showUniversitySettingsModal(context, userProfile);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'sync',
                child: Row(
                  children: [
                    Icon(Icons.sync_rounded, color: accentColor, size: 18),
                    SizedBox(width: 8),
                    Text('Sync with Routine', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'matrix',
                child: Row(
                  children: [
                    Icon(Icons.fact_check_rounded, color: accentColor, size: 18),
                    SizedBox(width: 8),
                    Text('Attendance Matrix', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'cgpa',
                child: Row(
                  children: [
                    Icon(Icons.assessment_outlined, color: accentColor, size: 18),
                    SizedBox(width: 8),
                    Text('Term Performance & CGPA', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: accentColor, size: 18),
                    SizedBox(width: 8),
                    Text('Profile & Mode Settings', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: uid == null || uid.isEmpty
            ? const Center(
                child: Text(
                  'User authentication required to view courses.',
                  style: TextStyle(color: Colors.white),
                ),
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('attendance_records')
                    .snapshots(),
                builder: (context, attSnapshot) {
                  final allAttendanceDocs = attSnapshot.data?.docs ?? [];
                  final allRecords = allAttendanceDocs
                      .map((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id))
                      .toList();

                  final semesterStats = AttendanceStats.fromRecords(allRecords);

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('courses')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: AppPreloader(size: 44),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error loading courses: ${snapshot.error}',
                            style: const TextStyle(color: Color(0xFFEF4444)),
                          ),
                        );
                      }

                      final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(snapshot.data?.docs ?? []);
                      docs.sort((a, b) {
                        final dataA = a.data();
                        final dataB = b.data();
                        final codeA = dataA['courseCode'] as String? ?? a.id;
                        final codeB = dataB['courseCode'] as String? ?? b.id;
                        return compareCourseCodes(codeA, codeB);
                      });

                      // Empty State
                      if (docs.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: cardColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                  ),
                                  child: const Icon(
                                    Icons.school_outlined,
                                    size: 56,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                const Text(
                                  'No Courses Added Yet',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'No courses added yet. Tap + to add a course or auto-import from your weekly routine.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: const Color(0xFF110D0C),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  onPressed: _isSyncingCourses ? null : _syncCoursesWithRoutine,
                                  icon: _isSyncingCourses
                                      ? const AppPreloader(size: 16, strokeWidth: 2, color: Color(0xFF140F0E))
                                      : const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text(
                                    'Sync Courses with Routine',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: docs.length + 1, // +1 for the top quick attendance & routine summary banner
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF4A3830)),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${semesterStats.percentage.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: semesterStats.percentage >= 75.0 ? const Color(0xFF06D6A0) : const Color(0xFFEF4444),
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${semesterStats.attended + semesterStats.extra}/${semesterStats.validClassesCount} classes',
                                    style: const TextStyle(color: Color(0xFFABA093), fontSize: 12),
                                  ),
                                  const Spacer(),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: accentColor,
                                      side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: _isSyncingCourses ? null : _syncCoursesWithRoutine,
                                    icon: _isSyncingCourses
                                        ? const AppPreloader(size: 14, strokeWidth: 1.5)
                                        : const Icon(Icons.sync_rounded, size: 14),
                                    label: const Text('Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: cardColor,
                                      foregroundColor: accentColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        side: const BorderSide(color: Color(0xFF4A3830)),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      SafeHaptics.lightImpact();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => const RoutineScreen()),
                                      );
                                    },
                                    icon: const Icon(Icons.calendar_view_week_rounded, size: 14),
                                    label: const Text('Routine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                            );
                          }

                          final doc = docs[index - 1];
                          final courseData = doc.data();
                          final docId = doc.id;

                          final courseCode = courseData['courseCode'] as String? ?? 'COURSE';
                          final courseName = courseData['courseName'] as String? ?? 'Untitled Course';
                          final creditHours = (courseData['creditHours'] as num?)?.toDouble() ?? 3.0;
                          final courseType = courseData['courseType'] as String? ?? 'Theory';
                          final useManualOverride = courseData['useManualAttendanceOverride'] as bool? ?? false;
                          final manualAttended = (courseData['manualAttendedClasses'] as num?)?.toInt();
                          final manualTotal = (courseData['manualTotalClasses'] as num?)?.toInt();

                          // TASK 2: Resilient Attendance Queries matching courseId, courseCode, and name
                          final courseRecords = allRecords.where((rec) => RoutineCourseSyncService.recordMatchesCourse(
                            record: rec,
                            courseId: docId,
                            courseCode: courseCode,
                            courseName: courseName,
                          )).toList();
                          final rawCalendarStats = AttendanceStats.fromRecords(courseRecords);
                          final courseStats = RoutineCourseSyncService.computeCourseAttendance(
                            courseRecords: courseRecords,
                            useManualAttendanceOverride: useManualOverride,
                            manualAttendedClasses: manualAttended,
                            manualTotalClasses: manualTotal,
                          );

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  SafeHaptics.lightImpact();
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CourseSyllabusScreen(courseId: docId),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Course Code Badge Icon
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                                        ),
                                        child: const Icon(
                                          Icons.class_rounded,
                                          color: accentColor,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Title & Subtitle + Course Attendance Percentage
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              courseCode,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              courseName,
                                              style: TextStyle(
                                                color: Colors.blueGrey.shade300,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle_outline_rounded,
                                                  size: 12,
                                                  color: courseStats.percentage >= 75.0
                                                      ? const Color(0xFF10B981)
                                                      : const Color(0xFFEF4444),
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    '${courseStats.percentage.toStringAsFixed(0)}% Attendance (${courseStats.attended}/${courseStats.totalClasses})',
                                                    style: TextStyle(
                                                      color: courseStats.percentage >= 75.0
                                                          ? const Color(0xFF10B981)
                                                          : const Color(0xFFEF4444),
                                                      fontSize: 11.5,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                // Bulk Override / Sync Action Button (TASK 3)
                                                InkResponse(
                                                  radius: 16,
                                                  onTap: () {
                                                    SafeHaptics.lightImpact();
                                                    showDialog(
                                                      context: context,
                                                      builder: (_) => AttendanceOverrideDialog(
                                                        courseId: docId,
                                                        courseCode: courseCode,
                                                        calendarAttended: rawCalendarStats.attended + rawCalendarStats.extra,
                                                        calendarTotal: rawCalendarStats.totalClasses,
                                                        currentlyUsingOverride: useManualOverride,
                                                        existingManualAttended: manualAttended,
                                                        existingManualTotal: manualTotal,
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(5),
                                                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          useManualOverride ? Icons.edit_note_rounded : Icons.tune_rounded,
                                                          size: 10,
                                                          color: const Color(0xFFF59E0B),
                                                        ),
                                                        const SizedBox(width: 2),
                                                        Text(
                                                          useManualOverride ? 'Override' : 'Sync',
                                                          style: const TextStyle(
                                                            color: Color(0xFFF59E0B),
                                                            fontSize: 9.5,
                                                            fontWeight: FontWeight.bold,
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
                                      ),

                                      // Trailing Credit Hours & Type Badge
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.06),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${creditHours.toStringAsFixed(1)} Cr',
                                              style: const TextStyle(
                                                color: accentColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            courseType,
                                            style: TextStyle(
                                              color: Colors.blueGrey.shade400,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.blueGrey.shade400,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: accentColor,
        foregroundColor: const Color(0xFF140F0E),
        elevation: 4,
        onPressed: () {
          SafeHaptics.lightImpact();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddCourseScreen(universityName: universityName),
            ),
          );
        },
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  void _showUniversitySettingsModal(BuildContext context, UserProfile profile) {
    final uniCtrl = TextEditingController(text: profile.universityName ?? '');
    final majorCtrl = TextEditingController(text: profile.major ?? '');
    String level = (profile.level != null && ['1', '2', '3', '4'].contains(profile.level))
        ? profile.level!
        : '1';
    String term = (profile.term != null && ['1', '2'].contains(profile.term))
        ? profile.term!
        : '1';
    bool isUni = profile.isUniversityStudent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            const accentColor = Color(0xFFF2B78A);
            const cardColor = Color(0xFF241C1A);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'University Profile Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.blueGrey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // University Mode Switch
                    SwitchListTile.adaptive(
                      value: isUni,
                      activeColor: accentColor,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'University Student Mode Active',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        isUni ? 'University Mode active' : 'Switch back to HSC / Admission mode',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          isUni = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    if (isUni) ...[
                      // University Name
                      const Text('University Name', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: uniCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. BUET, DU, CUET',
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Major / Department
                      const Text('Major / Department', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: majorCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. EEE, CSE, Mechanical',
                          filled: true,
                          fillColor: const Color(0xFF170F0D),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Level & Term Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Level', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: level,
                                  dropdownColor: cardColor,
                                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF170F0D),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: ['1', '2', '3', '4']
                                      .map((l) => DropdownMenuItem(value: l, child: Text('Level $l')))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => level = val);
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
                                const Text('Term', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: term,
                                  dropdownColor: cardColor,
                                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: const Color(0xFF170F0D),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  items: ['1', '2']
                                      .map((t) => DropdownMenuItem(value: t, child: Text('Term $t')))
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) setModalState(() => term = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    if (isUni) ...[
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accentColor,
                            side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const AdmissionArchiveScreen()),
                            );
                          },
                          icon: const Icon(Icons.history_edu_rounded, size: 20),
                          label: const Text(
                            'Access Previous Admission Data',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: const Color(0xFF140F0E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          await ref.read(userProfileProvider.notifier).updateProfile(
                                fullName: profile.fullName,
                                nickname: profile.nickname,
                                username: profile.username,
                                email: profile.email,
                                phone: profile.phone,
                                college: isUni
                                    ? (uniCtrl.text.trim().isNotEmpty ? uniCtrl.text.trim() : 'University')
                                    : profile.college,
                                district: profile.district,
                                hscBatch: isUni ? 'Varsity' : profile.hscBatch,
                                hscGroup: isUni ? 'Science' : profile.hscGroup,
                                primaryTarget: isUni ? 'University Studies' : profile.primaryTarget,
                                secondaryTarget: isUni ? 'None' : profile.secondaryTarget,
                                isUniversityStudent: isUni,
                                universityName: isUni ? uniCtrl.text.trim() : null,
                                major: isUni ? majorCtrl.text.trim() : null,
                                level: isUni ? level : null,
                                term: isUni ? term : null,
                              );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                backgroundColor: Color(0xFFF2B78A),
                                content: Text(
                                  'Profile settings updated!',
                                  style: TextStyle(color: Color(0xFF140F0E), fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          }
                        },
                        child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
