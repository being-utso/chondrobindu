import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Dialog for manually overriding attendance data (mid-semester onboarding).
/// Shows conflict resolution when calendar-tracked data differs from manual input.
class AttendanceOverrideDialog extends StatefulWidget {
  final String courseId;
  final String courseCode;
  final int calendarAttended;
  final int calendarTotal;
  final bool currentlyUsingOverride;
  final int? existingManualAttended;
  final int? existingManualTotal;
  final VoidCallback? onSaved;

  const AttendanceOverrideDialog({
    super.key,
    required this.courseId,
    required this.courseCode,
    required this.calendarAttended,
    required this.calendarTotal,
    this.currentlyUsingOverride = false,
    this.existingManualAttended,
    this.existingManualTotal,
    this.onSaved,
  });

  @override
  State<AttendanceOverrideDialog> createState() => _AttendanceOverrideDialogState();
}

class _AttendanceOverrideDialogState extends State<AttendanceOverrideDialog> {
  late TextEditingController _attendedController;
  late TextEditingController _totalController;
  bool _isSaving = false;

  static const _bgColor = Color(0xFF1C1412);
  static const _cardColor = Color(0xFF241C1A);
  static const _borderColor = Color(0xFF382A24);
  static const _accentColor = Color(0xFFF2B78A);
  static const _successColor = Color(0xFF10B981);
  static const _warningColor = Color(0xFFF59E0B);
  static const _dangerColor = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    // Pre-populate with existing manual values or calendar-tracked values
    _attendedController = TextEditingController(
      text: widget.currentlyUsingOverride
          ? (widget.existingManualAttended ?? widget.calendarAttended).toString()
          : widget.calendarAttended.toString(),
    );
    _totalController = TextEditingController(
      text: widget.currentlyUsingOverride
          ? (widget.existingManualTotal ?? widget.calendarTotal).toString()
          : widget.calendarTotal.toString(),
    );
  }

  @override
  void dispose() {
    _attendedController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _saveOverride() async {
    final attended = int.tryParse(_attendedController.text.trim());
    final total = int.tryParse(_totalController.text.trim());

    if (attended == null || total == null || total <= 0 || attended < 0 || attended > total) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: _dangerColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('Please enter valid values. Attended must be <= Total and > 0.'),
          ),
        );
      return;
    }

    // Conflict check: if calendar data exists and differs
    final calendarDiffers = widget.calendarTotal > 0 &&
        (attended != widget.calendarAttended || total != widget.calendarTotal);

    if (calendarDiffers && !widget.currentlyUsingOverride) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: _borderColor),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _warningColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Override Calendar Data?',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calendar tracking shows ${widget.calendarAttended}/${widget.calendarTotal} classes.',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 13),
              ),
              const SizedBox(height: 8),
              Text(
                'Your manual input: $attended/$total classes.',
                style: GoogleFonts.jetBrainsMono(color: _accentColor, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Override calendar data with manual values?',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFF7E726B), fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _warningColor,
                foregroundColor: const Color(0xFF140F0E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Override', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(widget.courseId)
          .set({
        'useManualAttendanceOverride': true,
        'manualAttendedClasses': attended,
        'manualTotalClasses': total,
      }, SetOptions(merge: true));

      SafeHaptics.mediumImpact();
      widget.onSaved?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: _successColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text(
                'Attendance override saved: $attended/$total',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: _dangerColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text('Failed to save override: $e'),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _revertToCalendar() async {
    setState(() => _isSaving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(widget.courseId)
          .set({
        'useManualAttendanceOverride': false,
        'manualAttendedClasses': FieldValue.delete(),
        'manualTotalClasses': FieldValue.delete(),
      }, SetOptions(merge: true));

      SafeHaptics.mediumImpact();
      widget.onSaved?.call();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: _accentColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text(
                'Reverted to calendar tracking',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: const Color(0xFF140F0E)),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: _dangerColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              content: Text('Failed to revert: $e', style: GoogleFonts.plusJakartaSans()),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attended = int.tryParse(_attendedController.text.trim()) ?? 0;
    final total = int.tryParse(_totalController.text.trim()) ?? 0;
    final previewRate = total > 0 ? (attended / total * 100).clamp(0.0, 100.0) : 0.0;

    return AlertDialog(
      backgroundColor: _bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _borderColor, width: 0.8),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_note_rounded, color: _accentColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual Attendance Tally',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  widget.courseCode,
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calendar info chip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: _accentColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calendar tracked: ${widget.calendarAttended}/${widget.calendarTotal} classes',
                      style: GoogleFonts.plusJakartaSans(color: _accentColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            if (widget.currentlyUsingOverride) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _warningColor.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: _warningColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Currently using manual override',
                        style: GoogleFonts.plusJakartaSans(color: _warningColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Input fields
            Text(
              'Total Classes Held',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _totalController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 30',
                hintStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF7E726B)),
                filled: true,
                fillColor: _cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accentColor, width: 1.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.class_rounded, color: _accentColor, size: 18),
              ),
            ),

            const SizedBox(height: 14),

            Text(
              'Total Classes Attended',
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _attendedController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'e.g. 25',
                hintStyle: GoogleFonts.jetBrainsMono(color: const Color(0xFF7E726B)),
                filled: true,
                fillColor: _cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _successColor, width: 1.2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefixIcon: const Icon(Icons.check_circle_outline_rounded, color: _successColor, size: 18),
              ),
            ),

            const SizedBox(height: 14),

            // Live preview
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Preview: $attended / $total',
                    style: GoogleFonts.jetBrainsMono(color: const Color(0xFFABA093), fontSize: 12),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (previewRate >= 75 ? _successColor : _dangerColor).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${previewRate.toStringAsFixed(1)}%',
                      style: GoogleFonts.jetBrainsMono(
                        color: previewRate >= 75 ? _successColor : _dangerColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.currentlyUsingOverride)
          TextButton.icon(
            onPressed: _isSaving ? null : _revertToCalendar,
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: Text('Revert to Calendar', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: _accentColor),
          ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
        ),
        const SizedBox(width: 6),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: const Color(0xFF140F0E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _isSaving ? null : _saveOverride,
          child: _isSaving
              ? const AppPreloader(size: 18, strokeWidth: 2, color: Color(0xFF140F0E))
              : Text('Save Override', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
