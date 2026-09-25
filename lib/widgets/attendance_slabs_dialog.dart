import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/attendance_grading_service.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Modal dialog allowing students to view and customize their step-tier attendance mark slabs
class AttendanceSlabsDialog extends StatefulWidget {
  final List<AttendanceMarkSlab> currentSlabs;
  final double currentAttendanceRate;
  final double attendanceWeightage;
  final Function(List<AttendanceMarkSlab> updatedSlabs) onSave;

  const AttendanceSlabsDialog({
    super.key,
    required this.currentSlabs,
    required this.currentAttendanceRate,
    required this.attendanceWeightage,
    required this.onSave,
  });

  @override
  State<AttendanceSlabsDialog> createState() => _AttendanceSlabsDialogState();
}

class _AttendanceSlabsDialogState extends State<AttendanceSlabsDialog> {
  late List<AttendanceMarkSlab> _slabs;

  @override
  void initState() {
    super.initState();
    _slabs = widget.currentSlabs.isNotEmpty
        ? List.from(widget.currentSlabs)
        : List.from(AttendanceGradingService.defaultSlabs);
  }

  void _resetToDefault() {
    SafeHaptics.lightImpact();
    setState(() {
      _slabs = List.from(AttendanceGradingService.defaultSlabs);
    });
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);
    const borderColor = Color(0xFF4A3830);
    const emeraldColor = Color(0xFF06D6A0);

    final matchingSlab = AttendanceGradingService.getMatchingSlab(
      attendanceRate: widget.currentAttendanceRate,
      customSlabs: _slabs,
    );

    final earnedMarks = AttendanceGradingService.calculateAttendanceMarks(
      attendanceRate: widget.currentAttendanceRate,
      attendanceWeightage: widget.attendanceWeightage,
      customSlabs: _slabs,
    );

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor, width: 0.8),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.bar_chart_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Attendance Mark Slabs',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'BUET / UGC style tier-based marks calculation. Earned points scale dynamically with your attendance weightage.',
                style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
              ),
              const SizedBox(height: 16),

              // Current Status Preview Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: emeraldColor.withOpacity(0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR ATTENDANCE',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.currentAttendanceRate.toStringAsFixed(1)}%',
                          style: GoogleFonts.jetBrainsMono(color: emeraldColor, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'POINTS AWARDED',
                          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${earnedMarks.toStringAsFixed(1)} / ${widget.attendanceWeightage.toStringAsFixed(1)} pts',
                          style: GoogleFonts.jetBrainsMono(color: accentColor, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Slab List
              Text(
                'ACTIVE DISTRIBUTION TIERS',
                style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),

              ..._slabs.map((slab) {
                final isCurrent = slab == matchingSlab;
                final tierAward = (slab.awardRatio * widget.attendanceWeightage).toStringAsFixed(1);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent ? accentColor.withOpacity(0.12) : cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent ? accentColor : borderColor,
                      width: isCurrent ? 1.2 : 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isCurrent ? Icons.check_circle_rounded : Icons.circle_outlined,
                            size: 16,
                            color: isCurrent ? accentColor : const Color(0xFFABA093),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            slab.label,
                            style: GoogleFonts.plusJakartaSans(
                              color: isCurrent ? Colors.white : const Color(0xFFABA093),
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCurrent ? accentColor : const Color(0xFF140F0E),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderColor, width: 0.6),
                        ),
                        child: Text(
                          '$tierAward pts',
                          style: GoogleFonts.jetBrainsMono(
                            color: isCurrent ? const Color(0xFF140F0E) : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 14),

              // Actions
              Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFABA093),
                    ),
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Reset to BUET/UGC', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: const Color(0xFF140F0E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      widget.onSave(_slabs);
                      Navigator.pop(context);
                    },
                    child: Text('Done', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
