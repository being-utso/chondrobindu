import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme/app_colors.dart';
import '../screens/grading_setup_screen.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

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
          constraints: const BoxConstraints(maxWidth: 520),
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
      _selectedPreset = 'custom';
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

  Color _getBadgeTextColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80);
    if (letter == 'A') return colors.primary;
    if (letter.startsWith('A-')) return colors.secondary;
    if (letter.startsWith('F')) return const Color(0xFFEF4444);
    return colors.textPrimary;
  }

  Color _getBadgeBgColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.15);
    if (letter == 'A') return colors.primary.withValues(alpha: 0.20);
    if (letter.startsWith('A-')) return colors.secondary.withValues(alpha: 0.20);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.15);
    return colors.surface;
  }

  Color _getBadgeBorderColor(String letter, double gradePoint, ChondrobinduThemeColors colors) {
    if (letter.startsWith('A+')) return const Color(0xFF4ADE80).withValues(alpha: 0.35);
    if (letter == 'A') return colors.primary.withValues(alpha: 0.35);
    if (letter.startsWith('A-')) return colors.secondary.withValues(alpha: 0.35);
    if (letter.startsWith('F')) return const Color(0xFFEF4444).withValues(alpha: 0.35);
    return colors.surfaceBorder;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.surfaceBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modal Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.recessed,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colors.surfaceBorder),
                        ),
                        child: Icon(Icons.tune_rounded, color: colors.secondary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Grading Scale Settings',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textPrimary,
                                fontSize: 16.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Configure letter grade cutoffs & GPA weights for simulation',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                    child: Icon(Icons.close_rounded, color: colors.textMuted, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Segmented Preset Switcher
            Text(
              'GRADING PRESET',
              style: GoogleFonts.jetBrainsMono(
                color: colors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(3),
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
            const SizedBox(height: 18),

            // Grid Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Letter & Grade Point',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Minimum Marks (%)',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Compact 2-Column Grade Cutoff Grid
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (int i = 0; i < _editableScale.length; i += 2) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildGradeCutoffTile(
                                row: _editableScale[i],
                                colors: colors,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (i + 1 < _editableScale.length)
                              Expanded(
                                child: _buildGradeCutoffTile(
                                  row: _editableScale[i + 1],
                                  colors: colors,
                                ),
                              )
                            else
                              const Expanded(child: SizedBox()),
                          ],
                        ),
                      ),
                    ],
                  ],
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
                    onPressed: () {
                      Navigator.pop(context);
                      SafeHaptics.mediumImpact();
                      widget.onSave(_editableScale);
                    },
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

  Widget _buildGradeCutoffTile({
    required GradingRow row,
    required ChondrobinduThemeColors colors,
  }) {
    final isF = row.letterGrade.toUpperCase() == 'F';
    final controller = _controllers[row.letterGrade] ??=
        TextEditingController(text: row.minPercentage.toString());

    final badgeColor = _getBadgeTextColor(row.letterGrade, row.gradePoint, colors);
    final badgeBg = _getBadgeBgColor(row.letterGrade, row.gradePoint, colors);
    final badgeBorder = _getBadgeBorderColor(row.letterGrade, row.gradePoint, colors);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Letter Badge + Grade Point
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 24,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeBorder),
                ),
                alignment: Alignment.center,
                child: Text(
                  row.letterGrade,
                  style: GoogleFonts.jetBrainsMono(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                row.gradePoint.toStringAsFixed(2),
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          // Minimum % field
          if (isF)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.surfaceBorder),
              ),
              child: Text(
                '< 40%',
                style: GoogleFonts.jetBrainsMono(
                  color: colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 44,
                  height: 28,
                  child: TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.jetBrainsMono(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      filled: true,
                      fillColor: colors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.surfaceBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.surfaceBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.primary, width: 1.2),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null) {
                        row.minPercentage = parsed;
                        setState(() {
                          _selectedPreset = 'custom';
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '%',
                  style: GoogleFonts.jetBrainsMono(
                    color: colors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
