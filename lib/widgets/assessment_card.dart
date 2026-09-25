import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/assessment_model.dart';

/// Dedicated high-contrast Assessment & Class Test (CT) card for Academic Planner
class AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final String courseCode;
  final String? courseTitle;
  final Color? cardColor;
  final Color? accentColor;
  final VoidCallback? onAttended;
  final VoidCallback? onEditMarks;
  final VoidCallback? onMissed;
  final VoidCallback? onPostponed;
  final VoidCallback? onEditDetails;
  final VoidCallback? onDelete;

  const AssessmentCard({
    super.key,
    required this.assessment,
    required this.courseCode,
    this.courseTitle,
    this.cardColor,
    this.accentColor,
    this.onAttended,
    this.onEditMarks,
    this.onMissed,
    this.onPostponed,
    this.onEditDetails,
    this.onDelete,
  });

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'All Day';
    final hour = dt.hour;
    final minute = dt.minute;
    final isAssign = assessment.type.toLowerCase().contains('assign') ||
        assessment.name.toLowerCase().contains('assign') ||
        assessment.type.toLowerCase() == 'hw' ||
        assessment.type.toLowerCase() == 'homework';
    final prefix = isAssign ? 'Due ' : '';
    if (hour == 0 && minute == 0) return isAssign ? 'Due Today' : 'All Day';
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final mStr = minute.toString().padLeft(2, '0');
    return '$prefix$h12:$mStr $period';
  }

  String _getBadgeLabel() {
    final typeLower = assessment.type.toLowerCase().trim();
    final nameUpper = assessment.name.toUpperCase().trim();
    if (nameUpper.contains('LAB FINAL') || typeLower.contains('lab_final') || typeLower.contains('lab final')) {
      return 'LAB FINAL';
    }
    if (nameUpper.contains('VIVA') || typeLower.contains('viva')) {
      return 'VIVA';
    }
    if (nameUpper.contains('LAB QUIZ') || typeLower.contains('lab_quiz') || typeLower.contains('lab quiz')) {
      return 'LAB QUIZ';
    }
    if (nameUpper.contains('LAB REPORT') || typeLower.contains('lab_report') || typeLower.contains('lab report')) {
      return 'LAB REPORT';
    }
    if (nameUpper.contains('PERFORMANCE') ||
        nameUpper.contains('CONTINUOUS') ||
        typeLower.contains('performance') ||
        typeLower.contains('continuous')) {
      return 'PERFORMANCE';
    }
    if (nameUpper.contains('PROJECT') || typeLower.contains('project')) {
      return 'PROJECT';
    }
    if (nameUpper.contains('PRESENTATION') || typeLower.contains('presentation')) {
      return 'PRESENTATION';
    }
    if (typeLower.contains('assign') ||
        nameUpper.contains('ASSIGNMENT') ||
        typeLower == 'hw' ||
        typeLower == 'homework' ||
        nameUpper.contains('HOMEWORK') ||
        nameUpper.contains('REPORT')) {
      return 'ASSIGNMENT';
    }
    if (typeLower == 'ct' || typeLower == 'class test' || nameUpper.contains('CT') || nameUpper.contains('CLASS TEST')) {
      return 'CT';
    }
    if (typeLower == 'quiz' || nameUpper.contains('QUIZ')) {
      return 'QUIZ';
    }
    if (typeLower == 'midterm' || typeLower == 'mid' || nameUpper.contains('MIDTERM') || nameUpper.contains('MID')) {
      return 'MIDTERM';
    }
    if (typeLower == 'final' || nameUpper.contains('FINAL')) {
      return 'FINAL';
    }
    return 'ASSESSMENT';
  }

  IconData _getBadgeIcon(String label) {
    switch (label) {
      case 'LAB FINAL':
        return Icons.science_outlined;
      case 'VIVA':
      case 'LAB QUIZ':
      case 'QUIZ':
        return Icons.quiz_outlined;
      case 'LAB REPORT':
      case 'ASSIGNMENT':
        return Icons.description_outlined;
      case 'PROJECT':
      case 'PRESENTATION':
        return Icons.co_present_outlined;
      default:
        return Icons.assignment_turned_in_rounded;
    }
  }

  Widget _buildStatusButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? color : color.withOpacity(0.35),
              width: isSelected ? 1.2 : 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: isSelected ? color : color.withOpacity(0.85)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : color.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const amberAccent = Color(0xFFF59E0B);
    final isPostponed = assessment.isPostponed;
    final isAttended = assessment.isAttended;
    final isMissed = assessment.isMissed;

    final postponedDateStr = assessment.postponedToDate != null
        ? '${assessment.postponedToDate!.day}/${assessment.postponedToDate!.month}/${assessment.postponedToDate!.year}'
        : '';

    final badgeLabel = _getBadgeLabel();

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isPostponed ? 0.65 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor ?? const Color(0xFF241C1A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor ?? amberAccent.withOpacity(0.65),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: (accentColor ?? amberAccent).withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Amber Badge + Course Code + Time Chip + Status / Menu
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // Amber CT / Assessment Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: amberAccent.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: amberAccent.withOpacity(0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_getBadgeIcon(badgeLabel), color: amberAccent, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              badgeLabel,
                              style: const TextStyle(
                                color: amberAccent,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Course Code & Title Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: amberAccent.withOpacity(0.25)),
                        ),
                        child: Text(
                          (courseTitle != null && courseTitle!.trim().isNotEmpty)
                              ? '$courseCode • ${courseTitle!.trim()}'
                              : courseCode,
                          style: AppTypography.courseCode.copyWith(fontSize: 11.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Time Chip with Amber Clock Icon
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: amberAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: amberAccent.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_rounded, color: amberAccent, size: 11),
                            const SizedBox(width: 4),
                            Text(
                              _formatTime(assessment.date),
                              style: const TextStyle(
                                color: Color(0xFFE2D9D2),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Status Pill & Options Popup Menu
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isPostponed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.warningContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_clock_rounded, color: AppColors.warning, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'Postponed ➔ $postponedDateStr',
                              style: const TextStyle(color: AppColors.warning, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else if (isAttended)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.presentBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.present.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.present, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              (assessment.obtainedMarks ?? 0) > 0
                                  ? 'Attended • ${assessment.obtainedMarks?.toStringAsFixed(1) ?? "--"} / ${assessment.totalMarks.toStringAsFixed(1)}'
                                  : 'Attended',
                              style: const TextStyle(color: AppColors.presentText, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    else if (isMissed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cancel_rounded, color: AppColors.missed, size: 12),
                            SizedBox(width: 4),
                            Text(
                              'Missed (0.0)',
                              style: TextStyle(color: AppColors.missed, fontSize: 10.5, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    if (onEditDetails != null || onEditMarks != null || onDelete != null) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.borderMedium),
                        ),
                        tooltip: 'Options',
                        onSelected: (val) {
                          if (val == 'edit_details') {
                            onEditDetails?.call();
                          } else if (val == 'edit_marks') {
                            onEditMarks?.call();
                          } else if (val == 'delete') {
                            onDelete?.call();
                          }
                        },
                        itemBuilder: (ctx) => [
                          if (onEditDetails != null)
                            PopupMenuItem(
                              value: 'edit_details',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit_note_rounded, color: AppColors.primary, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Edit Details & Topics', style: AppTypography.bodyText),
                                ],
                              ),
                            ),
                          if (onEditMarks != null)
                            PopupMenuItem(
                              value: 'edit_marks',
                              child: Row(
                                children: [
                                  const Icon(Icons.grade_rounded, color: AppColors.primary, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Add / Edit Marks', style: AppTypography.bodyText),
                                ],
                              ),
                            ),
                          if (onDelete != null)
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Text('Delete Assessment', style: AppTypography.bodyText.copyWith(color: AppColors.error)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Assessment Title
            Text(
              assessment.name,
              style: AppTypography.cardTitle.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),

            // Marks & Weightage
            Text(
              'Marks: ${assessment.obtainedMarks?.toStringAsFixed(1) ?? "--"} / ${assessment.totalMarks.toStringAsFixed(1)} • Weightage: ${assessment.weightage.toStringAsFixed(1)}%',
              style: AppTypography.subtext.copyWith(fontSize: 12),
            ),

            // Topics / Syllabus Covered Capsule Pill
            if (assessment.syllabusSummary != null && assessment.syllabusSummary!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: amberAccent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded, color: amberAccent, size: 13),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Topic: ${assessment.syllabusSummary!.trim()}',
                        style: AppTypography.bodySmall.copyWith(
                          color: const Color(0xFFF2B78A),
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action Buttons (Attended, Edit Marks, Missed, Postponed)
            if (!isPostponed && (onAttended != null || onMissed != null || onPostponed != null)) ...[
              const SizedBox(height: 10),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onAttended != null)
                      _buildStatusButton(
                        label: 'Attended',
                        icon: Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                        isSelected: isAttended,
                        onTap: onAttended,
                      ),
                    if (isAttended && onEditMarks != null) ...[
                      const SizedBox(width: 8),
                      _buildStatusButton(
                        label: (assessment.obtainedMarks ?? 0) > 0 ? 'Edit Marks' : 'Add Marks',
                        icon: Icons.edit_note_rounded,
                        color: AppColors.primary,
                        isSelected: false,
                        onTap: onEditMarks,
                      ),
                    ],
                    if (onMissed != null) ...[
                      const SizedBox(width: 8),
                      _buildStatusButton(
                        label: 'Missed',
                        icon: Icons.highlight_off_rounded,
                        color: AppColors.error,
                        isSelected: isMissed,
                        onTap: onMissed,
                      ),
                    ],
                    if (onPostponed != null) ...[
                      const SizedBox(width: 8),
                      _buildStatusButton(
                        label: 'Postponed',
                        icon: Icons.update_rounded,
                        color: AppColors.warning,
                        isSelected: false,
                        onTap: onPostponed,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
