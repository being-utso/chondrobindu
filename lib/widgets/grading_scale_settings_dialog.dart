import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../screens/grading_setup_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Helper wrapper holding controllers for an editable row in GradingScaleSettingsDialog
class _RowControllerHolder {
  GradingRow row;
  final TextEditingController letterCtrl;
  final TextEditingController gpaCtrl;
  final TextEditingController minPctCtrl;

  _RowControllerHolder({
    required this.row,
  })  : letterCtrl = TextEditingController(text: row.letterGrade),
        gpaCtrl = TextEditingController(text: row.gradePoint.toStringAsFixed(2)),
        minPctCtrl = TextEditingController(text: row.minPercentage.toString());

  void dispose() {
    letterCtrl.dispose();
    gpaCtrl.dispose();
    minPctCtrl.dispose();
  }
}

/// Stitch-styled modal dialog & bottom sheet for configuring letter grade cutoffs and GPA weights.
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

  /// Static helper to display this dialog as a modal bottom sheet (e.g. on mobile)
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

  /// Static helper to display this dialog as a centered modal (e.g. on desktop web)
  static Future<void> showAsDialog({
    required BuildContext context,
    required String universityName,
    required List<GradingRow> currentScale,
    required ValueChanged<List<GradingRow>> onSave,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: GradingScaleSettingsDialog(
            universityName: universityName,
            currentScale: currentScale,
            onSave: onSave,
          ),
        ),
      ),
    );
  }

  /// Adaptive helper showing centered dialog on wide screens and modal bottom sheet on narrow screens
  static Future<void> showAdaptive({
    required BuildContext context,
    required String universityName,
    required List<GradingRow> currentScale,
    required ValueChanged<List<GradingRow>> onSave,
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    if (isDesktop) {
      return showAsDialog(
        context: context,
        universityName: universityName,
        currentScale: currentScale,
        onSave: onSave,
      );
    } else {
      return showAsBottomSheet(
        context: context,
        universityName: universityName,
        currentScale: currentScale,
        onSave: onSave,
      );
    }
  }

  @override
  State<GradingScaleSettingsDialog> createState() => _GradingScaleSettingsDialogState();
}

class _GradingScaleSettingsDialogState extends State<GradingScaleSettingsDialog> {
  late List<_RowControllerHolder> _rowHolders;
  String? _selectedPreset;

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
    final sourceList = widget.currentScale.isNotEmpty ? widget.currentScale : buetUgcScale;
    _rowHolders = sourceList
        .map((r) => _RowControllerHolder(
              row: GradingRow(
                letterGrade: r.letterGrade,
                gradePoint: r.gradePoint,
                minPercentage: r.minPercentage,
                maxPercentage: r.maxPercentage,
              ),
            ))
        .toList();

    _detectInitialPreset();
  }

  void _detectInitialPreset() {
    final currentRows = _rowHolders.map((h) => h.row).toList();
    if (_matchesPreset(currentRows, buetUgcScale)) {
      _selectedPreset = 'buet';
    } else if (_matchesPreset(currentRows, northAmericanScale)) {
      _selectedPreset = 'na';
    } else {
      _selectedPreset = 'custom';
    }
  }

  bool _matchesPreset(List<GradingRow> current, List<GradingRow> preset) {
    if (current.length != preset.length) return false;
    for (int i = 0; i < current.length; i++) {
      if (current[i].letterGrade != preset[i].letterGrade ||
          (current[i].gradePoint - preset[i].gradePoint).abs() > 0.01 ||
          current[i].minPercentage != preset[i].minPercentage) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    for (final h in _rowHolders) {
      h.dispose();
    }
    super.dispose();
  }

  void _applyPreset(String presetKey, List<GradingRow> presetRows) {
    SafeHaptics.lightImpact();
    for (final h in _rowHolders) {
      h.dispose();
    }
    setState(() {
      _selectedPreset = presetKey;
      _rowHolders = presetRows
          .map((r) => _RowControllerHolder(
                row: GradingRow(
                  letterGrade: r.letterGrade,
                  gradePoint: r.gradePoint,
                  minPercentage: r.minPercentage,
                  maxPercentage: r.maxPercentage,
                ),
              ))
          .toList();
    });
  }

  void _removeRow(int index) {
    SafeHaptics.mediumImpact();
    setState(() {
      _selectedPreset = 'custom';
      final removed = _rowHolders.removeAt(index);
      removed.dispose();
    });
  }

  void _addGradeTier() {
    SafeHaptics.mediumImpact();
    setState(() {
      _selectedPreset = 'custom';
      final lastRow = _rowHolders.isNotEmpty ? _rowHolders.last.row : null;
      final newMin = lastRow != null ? (lastRow.minPercentage - 5).clamp(0, 100) : 35;
      final newGpa = lastRow != null ? (lastRow.gradePoint - 0.25).clamp(0.0, 4.0) : 1.75;
      final newRow = GradingRow(
        letterGrade: 'C-',
        gradePoint: newGpa,
        minPercentage: newMin,
        maxPercentage: lastRow != null ? lastRow.minPercentage - 1 : 39,
      );
      _rowHolders.add(_RowControllerHolder(row: newRow));
    });
  }

  void _saveAndApply() {
    final List<GradingRow> savedRows = [];
    for (final h in _rowHolders) {
      final letter = h.letterCtrl.text.trim().isNotEmpty ? h.letterCtrl.text.trim() : h.row.letterGrade;
      final gpa = double.tryParse(h.gpaCtrl.text.trim()) ?? h.row.gradePoint;
      final minPct = int.tryParse(h.minPctCtrl.text.trim()) ?? h.row.minPercentage;
      savedRows.add(GradingRow(
        letterGrade: letter,
        gradePoint: gpa,
        minPercentage: minPct.clamp(0, 100),
        maxPercentage: 100,
      ));
    }

    // Sort descending by minPercentage so highest grade is first
    savedRows.sort((a, b) => b.minPercentage.compareTo(a.minPercentage));

    // Ensure maxPercentages are contiguous
    for (int i = 0; i < savedRows.length; i++) {
      if (i == 0) {
        savedRows[i].maxPercentage = 100;
      } else {
        savedRows[i].maxPercentage = savedRows[i - 1].minPercentage - 1;
      }
    }

    Navigator.pop(context);
    SafeHaptics.mediumImpact();
    widget.onSave(savedRows);
  }

  Color _getBadgeTextColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80);
    if (letter == 'A') return colors.primary;
    if (letter.startsWith('A-')) return colors.secondary;
    if (letter.startsWith('B')) return colors.primary;
    if (letter.startsWith('C') || letter.startsWith('D')) return colors.secondary;
    if (letter.startsWith('F')) return const Color(0xFFEF4444);
    return colors.textPrimary;
  }

  Color _getBadgeBgColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.15);
    if (letter == 'A') return colors.primary.withValues(alpha: 0.15);
    if (letter.startsWith('A-')) return colors.secondary.withValues(alpha: 0.15);
    if (letter.startsWith('B')) return colors.primary.withValues(alpha: 0.12);
    if (letter.startsWith('C') || letter.startsWith('D')) return colors.secondary.withValues(alpha: 0.12);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.15);
    return colors.recessed;
  }

  Color _getBadgeBorderColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.35);
    if (letter == 'A') return colors.primary.withValues(alpha: 0.35);
    if (letter.startsWith('A-')) return colors.secondary.withValues(alpha: 0.35);
    if (letter.startsWith('B')) return colors.primary.withValues(alpha: 0.3);
    if (letter.startsWith('C') || letter.startsWith('D')) return colors.secondary.withValues(alpha: 0.3);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.35);
    return colors.surfaceBorder;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Modal Header: Title & Close Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Grading Scale Settings',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.universityName.isNotEmpty
                          ? '${widget.universityName} Letter Grade & GPA Conversion'
                          : 'Letter Grade & GPA Conversion Matrix',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.recessed,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.surfaceBorder),
                    ),
                    child: Icon(Icons.close_rounded, size: 18, color: colors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Segmented Preset Switcher
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.recessed,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Row(
                children: [
                  _buildPresetButton(
                    keyName: 'buet',
                    label: 'BUET / UGC (80% A+)',
                    isSelected: _selectedPreset == 'buet',
                    onTap: () => _applyPreset('buet', buetUgcScale),
                    colors: colors,
                  ),
                  const SizedBox(width: 4),
                  _buildPresetButton(
                    keyName: 'na',
                    label: 'North American (90% A)',
                    isSelected: _selectedPreset == 'na',
                    onTap: () => _applyPreset('na', northAmericanScale),
                    colors: colors,
                  ),
                  const SizedBox(width: 4),
                  _buildPresetButton(
                    keyName: 'custom',
                    label: 'Custom',
                    isSelected: _selectedPreset == 'custom',
                    onTap: () {
                      SafeHaptics.lightImpact();
                      setState(() => _selectedPreset = 'custom');
                    },
                    colors: colors,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Table Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      'GRADE',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 68,
                    child: Text(
                      'GPA',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MINIMUM %',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    width: 32,
                    alignment: Alignment.center,
                    child: Text(
                      'DEL',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Fully Interactive Grade Rows List
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    for (int i = 0; i < _rowHolders.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _buildInteractiveGradeRow(
                          holder: _rowHolders[i],
                          index: i,
                          colors: colors,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Add Grade Tier Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.primary,
                side: BorderSide(color: colors.surfaceBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              ),
              onPressed: _addGradeTier,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                '+ Add Grade Tier',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Modal Footer: Cancel & Save Buttons
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.surfaceBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      backgroundColor: colors.recessed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colors.surfaceBorder),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.plusJakartaSans(
                        color: colors.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.secondary,
                      foregroundColor: const Color(0xFF171C24),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _saveAndApply,
                    icon: const Icon(Icons.check_rounded, size: 16, color: Color(0xFF171C24)),
                    label: Text(
                      'Save & Apply Scale',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF171C24),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton({
    required String keyName,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ChondrobinduThemeColors colors,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: isSelected ? null : Border.all(color: Colors.transparent),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                color: isSelected ? const Color(0xFF171C24) : colors.textMuted,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInteractiveGradeRow({
    required _RowControllerHolder holder,
    required int index,
    required ChondrobinduThemeColors colors,
  }) {
    final badgeColor = _getBadgeTextColor(holder.row.letterGrade, holder.row.gradePoint, colors);
    final badgeBg = _getBadgeBgColor(holder.row.letterGrade, holder.row.gradePoint, colors);
    final badgeBorder = _getBadgeBorderColor(holder.row.letterGrade, holder.row.gradePoint, colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        children: [
          // 1. Editable Letter Grade Field
          Container(
            width: 56,
            height: 32,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: badgeBorder),
            ),
            child: TextFormField(
              controller: holder.letterCtrl,
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                color: badgeColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: InputBorder.none,
              ),
              onChanged: (val) {
                holder.row.letterGrade = val.trim();
                if (_selectedPreset != 'custom') {
                  setState(() => _selectedPreset = 'custom');
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // 2. Editable Grade Point (GPA) Field
          Container(
            width: 64,
            height: 32,
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: TextFormField(
              controller: holder.gpaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                border: InputBorder.none,
              ),
              onChanged: (val) {
                final d = double.tryParse(val.trim());
                if (d != null) {
                  holder.row.gradePoint = d;
                  if (_selectedPreset != 'custom') {
                    setState(() => _selectedPreset = 'custom');
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // 3. Editable Minimum Marks (%) Field (Fully editable for ALL rows, including F)
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: TextFormField(
                    controller: holder.minPctCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      border: InputBorder.none,
                    ),
                    onChanged: (val) {
                      final p = int.tryParse(val.trim());
                      if (p != null) {
                        holder.row.minPercentage = p;
                        if (_selectedPreset != 'custom') {
                          setState(() => _selectedPreset = 'custom');
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '%',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // 4. Delete Tier Icon Button
          InkWell(
            onTap: _rowHolders.length > 1 ? () => _removeRow(index) : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4.0),
              child: Icon(
                Icons.close_rounded,
                size: 17,
                color: _rowHolders.length > 1
                    ? colors.textMuted
                    : colors.textMuted.withValues(alpha: 0.25),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
