import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../screens/grading_setup_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Modal dialog and bottom sheet for configuring letter grade cutoffs and GPA weights.
class GradingScaleSettingsDialog extends StatefulWidget {
  final String universityName;
  final List<GradingRow> currentScale;
  final ValueChanged<List<GradingRow>> onSave;

  const GradingScaleSettingsDialog({
    super.key,
    required this.universityName,
    required this.currentScale,
    required this.onSave,
  });

  /// Static helper to display this dialog as a modal bottom sheet
  static Future<void> showAsBottomSheet({
    required BuildContext context,
    required String universityName,
    required List<GradingRow> currentScale,
    required ValueChanged<List<GradingRow>> onSave,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GradingScaleSettingsDialog(
        universityName: universityName,
        currentScale: currentScale,
        onSave: onSave,
      ),
    );
  }

  @override
  State<GradingScaleSettingsDialog> createState() => _GradingScaleSettingsDialogState();
}

class _GradingScaleSettingsDialogState extends State<GradingScaleSettingsDialog> {
  late List<GradingRow> _editableScale;
  String? _selectedPreset;
  final Map<String, TextEditingController> _controllers = {};

  static List<GradingRow> get buetUgcScale => [
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

  static List<GradingRow> get northAmericanScale => [
        GradingRow(letterGrade: 'A', gradePoint: 4.00, minPercentage: 90, maxPercentage: 100),
        GradingRow(letterGrade: 'A-', gradePoint: 3.70, minPercentage: 85, maxPercentage: 89),
        GradingRow(letterGrade: 'B+', gradePoint: 3.30, minPercentage: 80, maxPercentage: 84),
        GradingRow(letterGrade: 'B', gradePoint: 3.00, minPercentage: 75, maxPercentage: 79),
        GradingRow(letterGrade: 'B-', gradePoint: 2.70, minPercentage: 70, maxPercentage: 74),
        GradingRow(letterGrade: 'C+', gradePoint: 2.30, minPercentage: 65, maxPercentage: 69),
        GradingRow(letterGrade: 'C', gradePoint: 2.00, minPercentage: 60, maxPercentage: 64),
        GradingRow(letterGrade: 'D', gradePoint: 1.00, minPercentage: 50, maxPercentage: 59),
        GradingRow(letterGrade: 'F', gradePoint: 0.00, minPercentage: 0, maxPercentage: 49),
      ];

  @override
  void initState() {
    super.initState();
    _editableScale = widget.currentScale.map((r) => GradingRow(
          letterGrade: r.letterGrade,
          gradePoint: r.gradePoint,
          minPercentage: r.minPercentage,
          maxPercentage: r.maxPercentage,
        )).toList();

    _detectInitialPreset();
    _syncControllers();
  }

  void _detectInitialPreset() {
    if (_matchesPreset(_editableScale, buetUgcScale)) {
      _selectedPreset = 'buet';
    } else if (_matchesPreset(_editableScale, northAmericanScale)) {
      _selectedPreset = 'na';
    } else {
      _selectedPreset = null;
    }
  }

  bool _matchesPreset(List<GradingRow> current, List<GradingRow> preset) {
    if (current.length != preset.length) return false;
    for (int i = 0; i < current.length; i++) {
      if (current[i].letterGrade != preset[i].letterGrade ||
          current[i].gradePoint != preset[i].gradePoint ||
          current[i].minPercentage != preset[i].minPercentage) {
        return false;
      }
    }
    return true;
  }

  void _syncControllers() {
    for (final row in _editableScale) {
      if (_controllers.containsKey(row.letterGrade)) {
        _controllers[row.letterGrade]!.text = row.minPercentage.toString();
      } else {
        _controllers[row.letterGrade] = TextEditingController(text: row.minPercentage.toString());
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String presetKey, List<GradingRow> presetRows) {
    SafeHaptics.lightImpact();
    setState(() {
      _selectedPreset = presetKey;
      _editableScale = presetRows.map((r) => GradingRow(
            letterGrade: r.letterGrade,
            gradePoint: r.gradePoint,
            minPercentage: r.minPercentage,
            maxPercentage: r.maxPercentage,
          )).toList();

      for (final row in _editableScale) {
        if (_controllers.containsKey(row.letterGrade)) {
          _controllers[row.letterGrade]!.text = row.minPercentage.toString();
        } else {
          _controllers[row.letterGrade] = TextEditingController(text: row.minPercentage.toString());
        }
      }
    });
  }

  Color _getGradeColor(double gradePoint) {
    if (gradePoint >= 3.75) return AppColors.success;
    if (gradePoint >= 3.00) return const Color(0xFFF2B78A);
    if (gradePoint >= 2.25) return AppColors.amber;
    return AppColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF241C1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 24,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: Color(0xFFF2B78A), size: 22),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grading Scale Settings',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.universityName} Letter Grade Cutoffs',
                          style: GoogleFonts.plusJakartaSans(
                            color: const Color(0xFFABA093),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFFABA093), size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Preset Selector Pills
            Row(
              children: [
                Text(
                  'Presets:',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFABA093),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 10),
                // BUET / UGC Pill
                Expanded(
                  child: InkWell(
                    onTap: () => _applyPreset('buet', buetUgcScale),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedPreset == 'buet'
                            ? const Color(0xFFF2B78A)
                            : const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedPreset == 'buet'
                              ? const Color(0xFFF2B78A)
                              : const Color(0xFF4A3830),
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'BUET / UGC (80% A+)',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: _selectedPreset == 'buet'
                                ? const Color(0xFF140F0E)
                                : const Color(0xFFABA093),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // North American Pill
                Expanded(
                  child: InkWell(
                    onTap: () => _applyPreset('na', northAmericanScale),
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedPreset == 'na'
                            ? const Color(0xFFF2B78A)
                            : const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedPreset == 'na'
                              ? const Color(0xFFF2B78A)
                              : const Color(0xFF4A3830),
                          width: 1.0,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'North American (90% A)',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: _selectedPreset == 'na'
                                ? const Color(0xFF140F0E)
                                : const Color(0xFFABA093),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Table of editable rows
            Expanded(
              child: ListView.separated(
                key: ValueKey('grading_list_${_selectedPreset ?? 'custom'}_${_editableScale.length}'),
                itemCount: _editableScale.length,
                separatorBuilder: (_, __) => const Divider(color: Color(0xFF382A24), height: 1),
                itemBuilder: (ctx, index) {
                  final row = _editableScale[index];
                  final controller = _controllers[row.letterGrade] ??=
                      TextEditingController(text: row.minPercentage.toString());

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        // Letter Grade Tag
                        Container(
                          width: 46,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: _getGradeColor(row.gradePoint).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getGradeColor(row.gradePoint).withValues(alpha: 0.4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              row.letterGrade,
                              style: GoogleFonts.plusJakartaSans(
                                color: _getGradeColor(row.gradePoint),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // GPA Display
                        Expanded(
                          child: Row(
                            children: [
                              Text(
                                'GPA: ',
                                style: GoogleFonts.plusJakartaSans(
                                  color: const Color(0xFFABA093),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                row.gradePoint.toStringAsFixed(2),
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Min % Input
                        Row(
                          children: [
                            Text(
                              'Min: ',
                              style: GoogleFonts.plusJakartaSans(
                                color: const Color(0xFFABA093),
                                fontSize: 12,
                              ),
                            ),
                            SizedBox(
                              width: 58,
                              child: TextFormField(
                                key: ValueKey('ctrl_${row.letterGrade}_${row.minPercentage}'),
                                controller: controller,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  filled: true,
                                  fillColor: const Color(0xFF1A1412),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                                  ),
                                ),
                                onChanged: (v) {
                                  final val = int.tryParse(v);
                                  if (val != null) {
                                    row.minPercentage = val;
                                    setState(() {
                                      _selectedPreset = null; // Custom modified
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '%',
                              style: GoogleFonts.jetBrainsMono(
                                color: const Color(0xFFABA093),
                                fontSize: 12,
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
            const SizedBox(height: 14),

            // Save & Apply Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2B78A),
                  foregroundColor: const Color(0xFF140F0E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  SafeHaptics.mediumImpact();
                  widget.onSave(_editableScale);
                },
                icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFF140F0E)),
                label: Text(
                  'Save & Apply Scale',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFF140F0E),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
