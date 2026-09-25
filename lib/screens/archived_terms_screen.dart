import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/assessment_model.dart';
import '../models/profile_models.dart';
import '../models/routine_models.dart';
import '../services/archive_service.dart';
import '../services/pdf_report_service.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Screen listing all archived semesters and academic terms
class ArchivedTermsScreen extends ConsumerWidget {
  const ArchivedTermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        title: const Text(
          'Archived Semesters',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ArchiveService.streamArchivedTerms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AppPreloader(size: 44));
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 56, color: Colors.blueGrey.shade600),
                    const SizedBox(height: 16),
                    const Text(
                      'No Archived Semesters Yet',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'When you complete a semester, use "Archive Current Term" to save a permanent snapshot and reset your active courses and routine.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final termName = data['termName'] as String? ?? 'Archived Term';
              final uniName = data['universityName'] as String? ?? '';
              final major = data['major'] as String? ?? '';
              final totalCourses = (data['totalCourses'] as num?)?.toInt() ?? 0;
              final totalCredits = (data['totalCredits'] as num?)?.toDouble() ?? 0.0;
              final attendanceRate = (data['attendancePercentage'] as num?)?.toDouble() ?? 100.0;

              DateTime archivedDate = DateTime.now();
              if (data['archivedAt'] is Timestamp) {
                archivedDate = (data['archivedAt'] as Timestamp).toDate();
              }

              final dateStr = DateFormat('dd MMM yyyy').format(archivedDate);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArchivedTermDetailScreen(termData: data),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(Icons.history_edu_rounded, color: accentColor, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      termName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: attendanceRate >= 75.0
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${attendanceRate.toStringAsFixed(1)}% Attended',
                                style: TextStyle(
                                  color: attendanceRate >= 75.0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (uniName.isNotEmpty) ...[
                          Text(
                            '$uniName • $major',
                            style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12.5),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$totalCourses Courses (${totalCredits.toStringAsFixed(1)} Credits)',
                              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                            ),
                            Text(
                              'Archived: $dateStr',
                              style: const TextStyle(color: accentColor, fontSize: 11.5, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Read-only snapshot dashboard for a specific archived semester
class ArchivedTermDetailScreen extends ConsumerWidget {
  final Map<String, dynamic> termData;

  const ArchivedTermDetailScreen({super.key, required this.termData});

  Future<void> _exportArchivedPdf(BuildContext context, WidgetRef ref) async {
    SafeHaptics.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF241C1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
        ),
        content: const Row(
          children: [
            AppPreloader(size: 20, strokeWidth: 2),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Generating Scoped Term PDF Report...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final rawCourses = termData['courses'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> courses = rawCourses.map((c) => Map<String, dynamic>.from(c as Map)).toList();

      final List<Assessment> assessments = [];
      final Map<String, String> courseCodeMap = {};

      for (final c in courses) {
        final cId = c['id'] as String? ?? '';
        final cCode = c['courseCode'] as String? ?? 'Course';
        if (cId.isNotEmpty) courseCodeMap[cId] = cCode;

        assessments.addAll(Assessment.fromRawListOrMap(c['assessments'], defaultCourseId: cId));
      }

      final rawAttendance = termData['attendanceRecords'] as List<dynamic>? ?? [];
      final attendanceRecords = rawAttendance
          .map((r) => AttendanceRecord.fromMap(Map<String, dynamic>.from(r as Map), defaultId: r['id'] as String?))
          .toList();
      final attendanceStats = AttendanceStats.fromRecords(attendanceRecords);

      final termName = termData['termName'] as String? ?? 'Semester Archive';
      final uniName = termData['universityName'] as String? ?? 'University';
      final major = termData['major'] as String? ?? 'Engineering';
      final level = termData['level'] as String? ?? '1';
      final term = termData['term'] as String? ?? '1';

      final scopedProfile = UserProfile(
        fullName: termName,
        nickname: termName,
        username: 'archived',
        email: '',
        phone: '',
        primaryTarget: 'University Archive',
        universityName: uniName,
        major: major,
        level: level,
        term: term,
        isUniversityStudent: true,
      );

      await PdfReportService.exportAndShareUniversityReport(
        userProfile: scopedProfile,
        focusHoursLast30Days: 0.0,
        courses: courses,
        assessments: assessments,
        courseCodeMap: courseCodeMap,
        attendanceStats: attendanceStats,
      );
    } catch (e) {
      debugPrint('Error exporting archived term PDF: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text('Failed to export PDF: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    final termName = termData['termName'] as String? ?? 'Archived Term';
    final uniName = termData['universityName'] as String? ?? '';
    final major = termData['major'] as String? ?? '';
    final level = termData['level'] as String? ?? '1';
    final term = termData['term'] as String? ?? '1';
    final totalCredits = (termData['totalCredits'] as num?)?.toDouble() ?? 0.0;
    final attendanceRate = (termData['attendancePercentage'] as num?)?.toDouble() ?? 100.0;

    final rawCourses = termData['courses'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> courses = rawCourses.map((c) => Map<String, dynamic>.from(c as Map)).toList();

    final rawRoutine = termData['routine'] as List<dynamic>? ?? [];
    final List<ClassRoutine> routines = rawRoutine
        .map((r) => ClassRoutine.fromMap(Map<String, dynamic>.from(r as Map), defaultId: r['id'] as String?))
        .toList();

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
          termName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: accentColor, size: 22),
            tooltip: 'Export Scoped Term PDF',
            onPressed: () => _exportArchivedPdf(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Overview Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.school_rounded, color: accentColor, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uniName.isNotEmpty ? uniName : 'University Term',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$major • Level $level, Term $term',
                                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF241C1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF382A24)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('COURSES & CREDITS', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  '${courses.length} (${totalCredits.toStringAsFixed(1)} Cr)',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF241C1A),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF382A24)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TERM ATTENDANCE', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  '${attendanceRate.toStringAsFixed(1)}%',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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

              const SizedBox(height: 20),

              // Export Scoped PDF Banner Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF110D0C),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _exportArchivedPdf(context, ref),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('Export Scoped Semester PDF Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),

              const SizedBox(height: 24),

              // Courses Section
              Text(
                'Archived Courses (${courses.length})',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (courses.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('No courses recorded in this archived term.', style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
                  ),
                )
              else
                ...courses.map((c) {
                  final code = (c['courseCode'] ?? c['code']) as String? ?? 'Course';
                  final name = (c['courseName'] ?? c['name']) as String? ?? 'Untitled';
                  final type = (c['courseType'] ?? c['type']) as String? ?? 'Theory';
                  final cr = ((c['creditHours'] ?? c['credits'] ?? c['cr']) as num?)?.toDouble() ?? 0.0;
                  final dynamic rawAssessData = c['assessments'];
                  final List<dynamic> rawAssess = rawAssessData is List
                      ? rawAssessData
                      : (rawAssessData is Map ? rawAssessData.values.toList() : []);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(code, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('$type • ${cr.toStringAsFixed(1)} Cr', style: const TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(name, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5)),
                        if (rawAssess.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Divider(color: Colors.white12, height: 1),
                          const SizedBox(height: 8),
                          Text('${rawAssess.length} Assessment(s) Recorded', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 24),

              // Routine Section
              Text(
                'Class Schedule (${routines.length} Classes)',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              if (routines.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Text('No class routine saved in this archive.', style: TextStyle(color: Colors.blueGrey, fontSize: 13)),
                  ),
                )
              else
                ...routines.map((r) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.courseName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5)),
                            const SizedBox(height: 2),
                            Text('${r.dayName} • ${r.startTime} - ${r.endTime}', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5)),
                          ],
                        ),
                        if (r.isAlternating)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Alternating', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  );
                }),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
