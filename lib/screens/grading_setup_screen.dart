import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_profile_provider.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Grading Row Model for Grade Point Average (GPA) scaling
class GradingRow {
  String letterGrade;
  double gradePoint;
  int minPercentage;
  int maxPercentage;

  GradingRow({
    required this.letterGrade,
    required this.gradePoint,
    required this.minPercentage,
    required this.maxPercentage,
  });

  Map<String, dynamic> toMap() {
    return {
      'letterGrade': letterGrade,
      'gradePoint': gradePoint,
      'minPercentage': minPercentage,
      'maxPercentage': maxPercentage,
    };
  }

  factory GradingRow.fromMap(Map<String, dynamic> map) {
    return GradingRow(
      letterGrade: map['letterGrade'] as String? ?? 'A+',
      gradePoint: (map['gradePoint'] as num?)?.toDouble() ?? 4.0,
      minPercentage: (map['minPercentage'] as num?)?.toInt() ?? 80,
      maxPercentage: (map['maxPercentage'] as num?)?.toInt() ?? 100,
    );
  }
}

/// Grading Setup Wizard Screen for University Mode
class GradingSetupScreen extends ConsumerStatefulWidget {
  final String? universityNameOverride;

  const GradingSetupScreen({super.key, this.universityNameOverride});

  @override
  ConsumerState<GradingSetupScreen> createState() => _GradingSetupScreenState();
}

class _GradingSetupScreenState extends ConsumerState<GradingSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasPresetAvailable = false;
  List<GradingRow> _foundPresetRows = [];
  List<GradingRow> _editableRows = [];
  late String _universityName;

  @override
  void initState() {
    super.initState();
    _initUniversityNameAndCheckDb();
  }

  void _initUniversityNameAndCheckDb() {
    final userProfile = ref.read(userProfileProvider);
    final uniName = widget.universityNameOverride ??
        (userProfile.universityName?.trim().isNotEmpty == true
            ? userProfile.universityName!.trim()
            : 'BUET');
    _universityName = uniName;

    _checkFirestoreGradingScale();
  }

  Future<void> _checkFirestoreGradingScale() async {
    setState(() => _isLoading = true);

    try {
      final docRef = FirebaseFirestore.instance
          .collection('university_grading')
          .doc(_universityName);
      final doc = await docRef.get();

      if (doc.exists && doc.data() != null) {
        final rawRows = doc.data()?['rows'] as List<dynamic>?;
        if (rawRows != null && rawRows.isNotEmpty) {
          _foundPresetRows = rawRows
              .map((r) => GradingRow.fromMap(Map<String, dynamic>.from(r)))
              .toList();
          _hasPresetAvailable = true;
        }
      }
    } catch (e) {
      debugPrint('Error fetching university grading scale: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _importPresetScale() {
    SafeHaptics.lightImpact();
    setState(() {
      _editableRows = _foundPresetRows
          .map((r) => GradingRow(
                letterGrade: r.letterGrade,
                gradePoint: r.gradePoint,
                minPercentage: r.minPercentage,
                maxPercentage: r.maxPercentage,
              ))
          .toList();
      _hasPresetAvailable = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFF2B78A),
        behavior: SnackBarBehavior.floating,
        content: Text(
          'Imported $_universityName grading scale!',
          style: const TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void _loadDefaultStandardPreset() {
    SafeHaptics.lightImpact();
    setState(() {
      _editableRows = [
        GradingRow(letterGrade: 'A+', gradePoint: 4.0, minPercentage: 80, maxPercentage: 100),
        GradingRow(letterGrade: 'A', gradePoint: 3.75, minPercentage: 75, maxPercentage: 79),
        GradingRow(letterGrade: 'A-', gradePoint: 3.5, minPercentage: 70, maxPercentage: 74),
        GradingRow(letterGrade: 'B+', gradePoint: 3.25, minPercentage: 65, maxPercentage: 69),
        GradingRow(letterGrade: 'B', gradePoint: 3.0, minPercentage: 60, maxPercentage: 64),
        GradingRow(letterGrade: 'C+', gradePoint: 2.5, minPercentage: 55, maxPercentage: 59),
        GradingRow(letterGrade: 'C', gradePoint: 2.25, minPercentage: 50, maxPercentage: 54),
        GradingRow(letterGrade: 'D', gradePoint: 2.0, minPercentage: 45, maxPercentage: 49),
        GradingRow(letterGrade: 'F', gradePoint: 0.0, minPercentage: 0, maxPercentage: 44),
      ];
      _hasPresetAvailable = false;
    });
  }

  void _addGradingRow() {
    SafeHaptics.lightImpact();
    setState(() {
      _editableRows.add(
        GradingRow(letterGrade: 'A', gradePoint: 3.75, minPercentage: 75, maxPercentage: 79),
      );
    });
  }

  void _removeGradingRow(int index) {
    SafeHaptics.lightImpact();
    setState(() {
      _editableRows.removeAt(index);
    });
  }

  Future<void> _saveGradingScale() async {
    if (_editableRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please add at least one grading row before saving.'),
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final rowsData = _editableRows.map((r) => r.toMap()).toList();

      await FirebaseFirestore.instance
          .collection('university_grading')
          .doc(_universityName)
          .set({
        'universityName': _universityName,
        'updatedBy': user?.uid ?? 'anonymous',
        'updatedAt': FieldValue.serverTimestamp(),
        'rows': rowsData,
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              'Grading scale for $_universityName saved successfully!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to save grading scale: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          'Grading Setup ($_universityName)',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AppPreloader(size: 44),
                    SizedBox(height: 16),
                    Text(
                      'Checking university grading database...',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Preset Import Card (If Firestore doc exists)
                      if (_hasPresetAvailable) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                cardColor,
                                accentColor.withValues(alpha: 0.15),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.stars_rounded, color: accentColor, size: 22),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Default $_universityName Grading Scale Found',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'A pre-configured grading scale was found in the database. Would you like to import it for your setup?',
                                style: TextStyle(
                                  color: Colors.blueGrey.shade300,
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentColor,
                                      foregroundColor: const Color(0xFF110D0C),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _importPresetScale,
                                    icon: const Icon(Icons.download_rounded, size: 18),
                                    label: const Text(
                                      'Import Scale',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: () {
                                      setState(() => _hasPresetAvailable = false);
                                    },
                                    child: const Text(
                                      'Create Custom',
                                      style: TextStyle(color: Color(0xFF94A3B8)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Header & Description
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Grading Scale Matrix',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cardColor,
                              foregroundColor: accentColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
                              ),
                            ),
                            onPressed: _addGradingRow,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Row'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Empty State
                      if (_editableRows.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.assessment_outlined, size: 48, color: Colors.blueGrey.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                'No Grading Rows Defined',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Add custom letter grades and percentage bounds or load standard preset defaults.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentColor,
                                      foregroundColor: const Color(0xFF110D0C),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _addGradingRow,
                                    child: const Text('Add Grade Row', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _loadDefaultStandardPreset,
                                    child: const Text('Load Standard Preset'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _editableRows.length,
                          itemBuilder: (context, index) {
                            final row = _editableRows[index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Row(
                                children: [
                                  // Letter Grade
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: row.letterGrade,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'Grade',
                                        labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                                        filled: true,
                                        fillColor: const Color(0xFF241C1A),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      onChanged: (val) => row.letterGrade = val.trim(),
                                      validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Grade Point
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: row.gradePoint.toString(),
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'GPA',
                                        labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                                        filled: true,
                                        fillColor: const Color(0xFF241C1A),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      onChanged: (val) {
                                        final parsed = double.tryParse(val);
                                        if (parsed != null) row.gradePoint = parsed;
                                      },
                                      validator: (val) => (double.tryParse(val ?? '') == null) ? 'Invalid' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Min %
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: row.minPercentage.toString(),
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Min %',
                                        labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                                        filled: true,
                                        fillColor: const Color(0xFF241C1A),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      onChanged: (val) {
                                        final parsed = int.tryParse(val);
                                        if (parsed != null) row.minPercentage = parsed;
                                      },
                                      validator: (val) => (int.tryParse(val ?? '') == null) ? 'Invalid' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Max %
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: row.maxPercentage.toString(),
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Max %',
                                        labelStyle: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                                        filled: true,
                                        fillColor: const Color(0xFF241C1A),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF382A24))),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      ),
                                      onChanged: (val) {
                                        final parsed = int.tryParse(val);
                                        if (parsed != null) row.maxPercentage = parsed;
                                      },
                                      validator: (val) => (int.tryParse(val ?? '') == null) ? 'Invalid' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 4),

                                  // Remove Button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                                    onPressed: () => _removeGradingRow(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 24),

                      // Save & Continue Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: const Color(0xFF110D0C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _isSaving ? null : _saveGradingScale,
                          child: _isSaving
                              ? const AppPreloader(
                                  size: 20,
                                  strokeWidth: 2,
                                  color: Color(0xFF110D0C),
                                )
                              : const Text(
                                  'Save & Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
