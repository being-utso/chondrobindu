import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/assessment_model.dart';
import '../models/exam_model.dart';
import '../models/routine_models.dart';
import '../models/syllabus_models.dart';
import '../providers/analytics_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

class PdfReportService {
  /// Generates a structured 1-page PDF document summarizing student academic progress
  static Future<Uint8List> generateProgressReport({
    required UserProfile userProfile,
    required double focusHoursLast30Days,
    required List<Subject> syllabusSubjects,
    required List<ExamModel> recentExams,
  }) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final formattedDate = dateFormat.format(now);

    final primaryColor = PdfColor.fromHex('#181211');
    final accentColor = PdfColor.fromHex('#C2410C');
    final darkTextColor = PdfColor.fromHex('#110D0C');
    final greyTextColor = PdfColor.fromHex('#475569');
    final lightBgColor = PdfColor.fromHex('#F8FAFC');

    // Calculate overall syllabus progress
    double overallSyllabusProgress = 0.0;
    if (syllabusSubjects.isNotEmpty) {
      final totalProg = syllabusSubjects.fold<double>(0.0, (sum, s) => sum + s.totalProgress);
      overallSyllabusProgress = (totalProg / syllabusSubjects.length) * 100;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Block
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Chondrobindu',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Academic Progress Report',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#F2B78A'),
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Report Generated',
                          style: pw.TextStyle(color: PdfColor.fromHex('#94A3B8'), fontSize: 8),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formattedDate,
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Section 1: Student Profile & Monthly Focus Time Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            userProfile.displayName.isNotEmpty ? userProfile.displayName : 'Student',
                            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: darkTextColor),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Target: ${userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'HSC Prep'}  |  Batch: ${userProfile.hscBatch.isNotEmpty ? userProfile.hscBatch : '2025'}',
                            style: pw.TextStyle(fontSize: 10, color: greyTextColor),
                          ),
                          if (userProfile.college.isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'College: ${userProfile.college}',
                              style: pw.TextStyle(fontSize: 9.5, color: greyTextColor),
                            ),
                          ],
                        ],
                      ),
                    ),
                    pw.Container(
                      width: 1,
                      height: 38,
                      color: PdfColor.fromHex('#CBD5E1'),
                      margin: const pw.EdgeInsets.symmetric(horizontal: 12),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            '30-Day Focus Time',
                            style: pw.TextStyle(fontSize: 9, color: greyTextColor),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '${focusHoursLast30Days.toStringAsFixed(1)} Hours',
                            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: accentColor),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Syllabus Done: ${overallSyllabusProgress.toStringAsFixed(1)}%',
                            style: pw.TextStyle(fontSize: 8.5, color: PdfColor.fromHex('#10B981'), fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Section 2: Syllabus Progress Table
              pw.Text(
                'Syllabus Coverage Breakdown',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: darkTextColor),
              ),
              pw.SizedBox(height: 6),
              _buildSyllabusTable(syllabusSubjects),
              pw.SizedBox(height: 14),

              // Section 3: Exam Performance Table
              pw.Text(
                'Recent Exam Performance',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: darkTextColor),
              ),
              pw.SizedBox(height: 6),
              _buildExamTable(recentExams),

              pw.Spacer(),

              // Footer
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Chondrobindu • Academic Tracking & Admission Prep Companion',
                    style: pw.TextStyle(fontSize: 8, color: greyTextColor),
                  ),
                  pw.Text(
                    'Official Progress Report',
                    style: pw.TextStyle(fontSize: 8, color: primaryColor, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Builds Syllabus Progress Table
  static pw.Widget _buildSyllabusTable(List<Subject> subjects) {
    if (subjects.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F8FAFC'),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No syllabus tracking data available.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );
    }

    final headers = ['Subject Title', 'Completed Sections', 'Progress'];

    final data = subjects.take(8).map((subject) {
      final totalSections = subject.chapters.fold<int>(0, (sum, c) => sum + c.sections.length);
      final completedSections = subject.chapters.fold<int>(
        0,
        (sum, c) => sum + c.sections.where((s) => s.isCompleted).length,
      );
      final percentage = (subject.totalProgress * 100).toStringAsFixed(0);

      return [
        subject.title,
        '$completedSections / $totalSections Sections',
        '$percentage%',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#110D0C')),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'), width: 0.5)),
      ),
    );
  }

  /// Builds Recent Exam Performance Table
  static pw.Widget _buildExamTable(List<ExamModel> exams) {
    if (exams.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F8FAFC'),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No exam scores recorded yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );
    }

    final headers = ['Exam Title', 'Subject', 'Score (%)', 'Merit Rank'];

    final data = exams.take(6).map((exam) {
      final scoreStr = exam.isAbsent ? 'Absent' : '${exam.scorePercentage.toStringAsFixed(1)}%';
      final rankStr = exam.meritPosition > 0 ? '#${exam.meritPosition}' : 'N/A';

      return [
        exam.examName,
        exam.subject,
        scoreStr,
        rankStr,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#181211')),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'), width: 0.5)),
      ),
    );
  }

  /// Triggers system print/share sheet with the generated PDF
  static Future<void> exportAndShareReport({
    required UserProfile userProfile,
    required double focusHoursLast30Days,
    required List<Subject> syllabusSubjects,
    required List<ExamModel> recentExams,
  }) async {
    final pdfBytes = await generateProgressReport(
      userProfile: userProfile,
      focusHoursLast30Days: focusHoursLast30Days,
      syllabusSubjects: syllabusSubjects,
      recentExams: recentExams,
    );

    final cleanName = userProfile.displayName.replaceAll(RegExp(r'[^\w\s]+'), '').trim();
    final filename = cleanName.isNotEmpty
        ? 'Chondrobindu_Progress_Report_${cleanName.replaceAll(' ', '_')}.pdf'
        : 'Chondrobindu_Progress_Report.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  /// Generates a structured 1-page PDF document summarizing university student term progress
  static Future<Uint8List> generateUniversityTermReport({
    required UserProfile userProfile,
    required double focusHoursLast30Days,
    required List<Map<String, dynamic>> courses,
    required List<Assessment> assessments,
    required Map<String, String> courseCodeMap,
    AttendanceStats? attendanceStats,
  }) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final formattedDate = dateFormat.format(now);

    final primaryColor = PdfColor.fromHex('#181211');
    final accentColor = PdfColor.fromHex('#C2410C');
    final darkTextColor = PdfColor.fromHex('#110D0C');
    final greyTextColor = PdfColor.fromHex('#475569');
    final lightBgColor = PdfColor.fromHex('#F8FAFC');

    final uniName = userProfile.universityName?.isNotEmpty == true ? userProfile.universityName! : 'University';
    final major = userProfile.major?.isNotEmpty == true ? userProfile.major! : 'Engineering / Science';
    final level = userProfile.level?.isNotEmpty == true ? userProfile.level! : '1';
    final term = userProfile.term?.isNotEmpty == true ? userProfile.term! : '1';

    final attendancePercentage = attendanceStats?.percentage ?? 100.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Block
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: primaryColor,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Chondrobindu',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'University Academic Term Report',
                          style: pw.TextStyle(
                            color: PdfColor.fromHex('#F2B78A'),
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Report Generated',
                          style: pw.TextStyle(color: PdfColor.fromHex('#94A3B8'), fontSize: 8),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          formattedDate,
                          style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Student Profile & Term Overview
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: lightBgColor,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
                ),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            userProfile.displayName.isNotEmpty ? userProfile.displayName : 'Student',
                            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: darkTextColor),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '$uniName • $major',
                            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: primaryColor),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Academic Term: Level $level, Term $term  |  Courses: ${courses.length} Registered',
                            style: pw.TextStyle(fontSize: 9.5, color: greyTextColor),
                          ),
                        ],
                      ),
                    ),
                    pw.Container(
                      width: 1,
                      height: 38,
                      color: PdfColor.fromHex('#CBD5E1'),
                      margin: const pw.EdgeInsets.symmetric(horizontal: 12),
                    ),
                    pw.Expanded(
                      flex: 2,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Term Attendance',
                            style: pw.TextStyle(fontSize: 9, color: greyTextColor),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '${attendancePercentage.toStringAsFixed(1)}%',
                            style: pw.TextStyle(
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                              color: attendancePercentage >= 75.0 ? PdfColor.fromHex('#10B981') : PdfColor.fromHex('#EF4444'),
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '30-Day Focus: ${focusHoursLast30Days.toStringAsFixed(1)} Hours',
                            style: pw.TextStyle(fontSize: 8.5, color: accentColor, fontWeight: pw.FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Section 1: Enrolled Courses Table
              pw.Text(
                'Registered University Courses',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: darkTextColor),
              ),
              pw.SizedBox(height: 6),
              _buildUniversityCoursesTable(courses),
              pw.SizedBox(height: 14),

              // Section 2: Assessments & Continuous Evaluations
              pw.Text(
                'Term Assessments & Continuous Evaluation',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: darkTextColor),
              ),
              pw.SizedBox(height: 6),
              _buildUniversityAssessmentsTable(assessments, courseCodeMap),

              pw.Spacer(),

              // Footer
              pw.Divider(color: PdfColor.fromHex('#E2E8F0')),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Chondrobindu • University Academic Tracking & Term Management Companion',
                    style: pw.TextStyle(fontSize: 8, color: greyTextColor),
                  ),
                  pw.Text(
                    'Official Academic Report',
                    style: pw.TextStyle(fontSize: 8, color: primaryColor, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Builds Enrolled Courses Table for PDF
  static pw.Widget _buildUniversityCoursesTable(List<Map<String, dynamic>> courses) {
    if (courses.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F8FAFC'),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No courses registered for this term.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );
    }

    final headers = ['Course Code', 'Course Title', 'Type', 'Credit Hours'];

    final data = courses.take(8).map((c) {
      final code = c['courseCode'] as String? ?? 'Course';
      final name = c['courseName'] as String? ?? 'Untitled';
      final type = c['courseType'] as String? ?? 'Theory';
      final credits = (c['creditHours'] as num?)?.toDouble() ?? 3.0;

      return [
        code,
        name,
        type,
        '${credits.toStringAsFixed(1)} Cr',
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#110D0C')),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'), width: 0.5)),
      ),
    );
  }

  /// Builds University Assessments Table for PDF
  static pw.Widget _buildUniversityAssessmentsTable(List<Assessment> assessments, Map<String, String> courseCodeMap) {
    if (assessments.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromHex('#F8FAFC'),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Text('No term assessments recorded yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );
    }

    final headers = ['Course', 'Assessment', 'Date', 'Marks (Obt / Total)', 'Weightage'];

    final data = assessments.take(8).map((a) {
      final courseCode = courseCodeMap[a.courseId] ?? 'Course';
      final dateStr = a.date != null ? DateFormat('dd MMM yyyy').format(a.date!) : 'Unscheduled';
      final marksStr = '${a.obtainedMarks?.toStringAsFixed(1) ?? "--"} / ${a.totalMarks.toStringAsFixed(0)} (${a.percentage.toStringAsFixed(0)}%)';
      final weightStr = '${a.weightage.toStringAsFixed(0)}%';

      return [
        courseCode,
        a.name,
        dateStr,
        marksStr,
        weightStr,
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: PdfColors.white),
      headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#181211')),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
      rowDecoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E2E8F0'), width: 0.5)),
      ),
    );
  }

  /// Triggers system print/share sheet with the generated University PDF
  static Future<void> exportAndShareUniversityReport({
    required UserProfile userProfile,
    required double focusHoursLast30Days,
    required List<Map<String, dynamic>> courses,
    required List<Assessment> assessments,
    required Map<String, String> courseCodeMap,
    AttendanceStats? attendanceStats,
  }) async {
    final pdfBytes = await generateUniversityTermReport(
      userProfile: userProfile,
      focusHoursLast30Days: focusHoursLast30Days,
      courses: courses,
      assessments: assessments,
      courseCodeMap: courseCodeMap,
      attendanceStats: attendanceStats,
    );

    final cleanName = userProfile.displayName.replaceAll(RegExp(r'[^\w\s]+'), '').trim();
    final filename = cleanName.isNotEmpty
        ? 'Chondrobindu_University_Report_${cleanName.replaceAll(' ', '_')}.pdf'
        : 'Chondrobindu_University_Report.pdf';

    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: filename,
    );
  }

  /// Intercepts PDF export with dynamic dialog if the user is a university student with potential legacy/previous data
  static Future<void> handleExportPdfAction(BuildContext context, WidgetRef ref) async {
    final userProfile = ref.read(userProfileProvider);

    if (userProfile.isUniversityStudent) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1412),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFF2B78A), size: 22),
              SizedBox(width: 10),
              Text(
                'Export PDF Report',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            'Which data would you like to export?',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
          ),
          actionsPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                foregroundColor: const Color(0xFFF2B78A),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _exportAdmissionData(context, ref, userProfile);
              },
              child: const Text('Previous/Admission Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF110D0C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _exportUniversityData(context, ref, userProfile);
              },
              child: const Text('Current Term Data', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          ],
        ),
      );
    } else {
      await _exportAdmissionData(context, ref, userProfile);
    }
  }

  /// Exports legacy Admission / HSC progress report
  static Future<void> _exportAdmissionData(BuildContext context, WidgetRef ref, UserProfile userProfile) async {
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
                'Generating Academic Progress PDF Report...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final focusHours30 = ref.read(thirtyDayFocusHoursProvider);
      final syllabusSubjects = ref.read(syllabusProvider);
      final examsAsync = ref.read(examsStreamProvider);
      final recentExams = examsAsync.asData?.value ?? [];

      await exportAndShareReport(
        userProfile: userProfile,
        focusHoursLast30Days: focusHours30,
        syllabusSubjects: syllabusSubjects,
        recentExams: recentExams,
      );
    } catch (e) {
      debugPrint('Error exporting admission PDF progress report: $e');
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

  /// Exports active University term report
  static Future<void> _exportUniversityData(BuildContext context, WidgetRef ref, UserProfile userProfile) async {
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
                'Generating University Term PDF Report...',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final focusHours30 = ref.read(thirtyDayFocusHoursProvider);

      List<Map<String, dynamic>> courses = [];
      List<Assessment> assessments = [];
      final Map<String, String> courseCodeMap = {};
      AttendanceStats? attendanceStats;

      if (uid != null) {
        final coursesSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('courses')
            .orderBy('createdAt', descending: true)
            .get();

        for (final doc in coursesSnap.docs) {
          final data = doc.data();
          courses.add(data);
          final code = data['courseCode'] as String? ?? 'Course';
          courseCodeMap[doc.id] = code;

          assessments.addAll(
            Assessment.fromRawListOrMap(data['assessments'], defaultCourseId: doc.id),
          );
        }

        try {
          final attendanceSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('attendance_records')
              .get();
          final records = attendanceSnap.docs
              .map<AttendanceRecord>((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id))
              .toList();
          if (records.isNotEmpty) {
            attendanceStats = AttendanceStats.fromRecords(records);
          }
        } catch (e) {
          debugPrint('Error loading attendance stats for PDF: $e');
        }
      }

      await exportAndShareUniversityReport(
        userProfile: userProfile,
        focusHoursLast30Days: focusHours30,
        courses: courses,
        assessments: assessments,
        courseCodeMap: courseCodeMap,
        attendanceStats: attendanceStats,
      );
    } catch (e) {
      debugPrint('Error exporting university PDF report: $e');
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
}
