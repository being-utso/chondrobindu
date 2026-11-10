import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/syllabus_provider.dart';
import '../services/syllabus_factory.dart';
import '../providers/user_profile_provider.dart';
import 'university_dashboard_screen.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';
import '../core/theme/app_colors.dart';

/// Syllabus Screen featuring dynamic Subjects, Chapters, and StudySections
/// with Global Section Management (Add/Delete across subjects via WriteBatch),
/// Bulk Select & Delete mode (random sections via WriteBatch), and real-time state sync.
class SyllabusScreen extends ConsumerStatefulWidget {
  const SyllabusScreen({super.key});

  @override
  ConsumerState<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends ConsumerState<SyllabusScreen> {
  ChondrobinduThemeColors get colors => AppColors.of(context);
  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  List<Subject> mySyllabus = [];
  String? _lastTarget;
  final Set<String> expandedSubjectIds = {};
  final Set<String> expandedChapterIds = {};
  bool isEditMode = false;
  bool isSelectionMode = false;
  final Set<String> selectedSectionKeys = {};
  bool _isLoadingFirestore = false;

  @override
  void initState() {
    super.initState();
  }

  /// Load Syllabus with Cloud Firestore persistence & cache
  
  Future<void> _loadSyllabusForTarget(String target) async {
    _lastTarget = target;
    setState(() {
      _isLoadingFirestore = true;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('syllabus_state')
            .doc('active_syllabus') // STRICTLY USE THIS ID
            .get();

        if (doc.exists && doc.data() != null && doc.data()!['subjects'] != null) {
          // 🚨 THE ASSASSIN IS DEAD 🚨
          // We removed the 'if (savedTarget == target)' check.
          // If the active_syllabus exists in the database, we TRUST IT unconditionally!
          final rawSubjects = doc.data()!['subjects'] as List<dynamic>;
          mySyllabus = rawSubjects
              .map((s) => Subject.fromMap(Map<String, dynamic>.from(s)))
              .toList();
          ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);
          setState(() {
            _isLoadingFirestore = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('Error loading syllabus from Firestore: $e');
      }
    }

    // Fallback to Factory Default Syllabus ONLY if DB is genuinely empty
    mySyllabus = SyllabusFactory.generateInitialSyllabus(target);
    ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);
    expandedSubjectIds.clear();
    expandedChapterIds.clear();
    
    _autoSaveToFirestore(); // Auto-save the fallback so it exists next time
    
    setState(() {
      _isLoadingFirestore = false;
    });
  }

  /// Auto-Save Syllabus Edits to Cloud Firestore
  Future<void> _autoSaveToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || mySyllabus.isEmpty) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('syllabus_state')
          .doc('active_syllabus'); // Always write here

      final data = mySyllabus.map((s) => s.toMap()).toList();
      await docRef.set({
        'target': _lastTarget ?? 'default',
        'subjects': data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error auto-saving syllabus: $e');
    }
  }
  
  String _generateUniqueId(String prefix) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return '${prefix}_$timestamp';
  }

  IconData _getSubjectIcon(String? iconName, String title) {
    final lower = title.toLowerCase();
    if (iconName == 'physics' || lower.contains('physics') || title.contains('পদার্থ')) {
      return Icons.bolt_rounded;
    }
    if (iconName == 'chemistry' || lower.contains('chemistry') || title.contains('রসায়ন')) {
      return Icons.science_rounded;
    }
    if (iconName == 'math' || lower.contains('math') || title.contains('গণিত')) {
      return Icons.functions_rounded;
    }
    if (iconName == 'biology' || lower.contains('biology') || title.contains('জীব')) {
      return Icons.biotech_rounded;
    }
    if (iconName == 'language' || lower.contains('bangla') || lower.contains('english') || title.contains('বাংলা')) {
      return Icons.translate_rounded;
    }
    if (iconName == 'globe' || lower.contains('knowledge') || title.contains('জ্ঞান')) {
      return Icons.public_rounded;
    }
    return Icons.menu_book_rounded;
  }

  // --- BottomSheet dialog to Add / Edit Subject ---
  void _showSubjectBottomSheet({Subject? existingSubject}) {
    final titleController = TextEditingController(text: existingSubject?.title ?? '');
    final isEditing = existingSubject != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Subject' : 'Add New Subject',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: TextField(
                  controller: titleController,
                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Subject Title (e.g. Physics 1st Paper)',
                    hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (isEditing) ...[
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          mySyllabus.removeWhere((s) => s.id == existingSubject.id);
                          expandedSubjectIds.remove(existingSubject.id);
                        });
                        _autoSaveToFirestore();
                        Navigator.pop(ctx);
                      },
                      tooltip: 'Delete Subject',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final text = titleController.text.trim();
                          if (text.isNotEmpty) {
                            setState(() {
                              if (isEditing) {
                                final idx = mySyllabus.indexOf(existingSubject);
                                if (idx != -1) {
                                  mySyllabus[idx] = Subject(
                                    id: existingSubject.id,
                                    title: text,
                                    chapters: existingSubject.chapters,
                                    iconName: existingSubject.iconName,
                                  );
                                }
                              } else {
                                final newId = _generateUniqueId('subj');
                                mySyllabus.add(Subject(
                                  id: newId,
                                  title: text,
                                  chapters: [],
                                ));
                                expandedSubjectIds.add(newId);
                              }
                            });
                            _autoSaveToFirestore();
                          }
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: Text(
                          isEditing ? 'Save Changes' : 'Add Subject',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Add Chapter with Dynamic Default Sections from existing chapters
  void _showChapterBottomSheet(Subject subject, {Chapter? existingChapter}) {
    final titleController = TextEditingController(text: existingChapter?.title ?? '');
    final isEditing = existingChapter != null;

    final Set<String> distinctSectionsInSubject = {};
    for (var ch in subject.chapters) {
      for (var sec in ch.sections) {
        if (sec.title.trim().isNotEmpty) {
          distinctSectionsInSubject.add(sec.title.trim());
        }
      }
    }
    if (distinctSectionsInSubject.isEmpty) {
      distinctSectionsInSubject.addAll([
        'Main Textbook / Theory',
        'Concept book (কনসেপ্ট বুক)',
        'Question Bank (প্রশ্নব্যাংক)',
        'Probable question (সম্ভাব্য প্রশ্ন)',
        'Class note (ক্লাস নোট)',
        'Weekly solution',
        'Exercise MCQ',
      ]);
    }

    final List<TextEditingController> sectionControllers = [];
    if (isEditing) {
      for (var sec in existingChapter.sections) {
        sectionControllers.add(TextEditingController(text: sec.title));
      }
    } else {
      final initialSeeds = distinctSectionsInSubject.take(3).toList();
      for (var seed in initialSeeds) {
        sectionControllers.add(TextEditingController(text: seed));
      }
      if (sectionControllers.isEmpty) {
        sectionControllers.add(TextEditingController(text: 'Main Textbook / Theory'));
        sectionControllers.add(TextEditingController(text: 'Question Bank (প্রশ্নব্যাংক)'));
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            isEditing ? 'Edit Chapter' : 'Add Chapter to ${subject.title}',
                            style: GoogleFonts.plusJakartaSans(
                              color: colors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'CHAPTER NAME',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: titleController,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. Chapter 3: Dynamics',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'AVAILABLE SUBJECT SECTIONS (TAP TO ADD/REMOVE)',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: distinctSectionsInSubject.map((secName) {
                        final isAlreadyAdded = sectionControllers.any((c) => c.text.trim() == secName);
                        return ChoiceChip(
                          label: Text(
                            secName,
                            style: GoogleFonts.plusJakartaSans(
                              color: isAlreadyAdded ? colors.primary : colors.textMuted,
                              fontSize: 11,
                              fontWeight: isAlreadyAdded ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isAlreadyAdded,
                          selectedColor: colors.primary.withValues(alpha: 0.15),
                          backgroundColor: colors.recessed,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isAlreadyAdded ? colors.primary : colors.surfaceBorder,
                            ),
                          ),
                          onSelected: (selected) {
                            setModalState(() {
                              if (selected) {
                                sectionControllers.add(TextEditingController(text: secName));
                              } else {
                                final idx = sectionControllers.indexWhere((c) => c.text.trim() == secName);
                                if (idx != -1) {
                                  final removed = sectionControllers.removeAt(idx);
                                  removed.dispose();
                                }
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CONFIGURED CHAPTER SECTIONS',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          '${sectionControllers.length} Section(s)',
                          style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    ...List.generate(sectionControllers.length, (idx) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  color: colors.recessed,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: colors.surfaceBorder),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                child: TextField(
                                  controller: sectionControllers[idx],
                                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: 'Section ${idx + 1}',
                                    hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () {
                                setModalState(() {
                                  final removed = sectionControllers.removeAt(idx);
                                  removed.dispose();
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),

                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          sectionControllers.add(TextEditingController());
                        });
                      },
                      icon: Icon(Icons.add_rounded, size: 16, color: colors.secondary),
                      label: Text('Add Custom Section Field', style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        if (isEditing) ...[
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () {
                              setState(() {
                                subject.chapters.removeWhere((c) => c.id == existingChapter.id);
                              });
                              _autoSaveToFirestore();
                              for (var ctrl in sectionControllers) {
                                ctrl.dispose();
                              }
                              titleController.dispose();
                              Navigator.pop(ctx);
                            },
                            tooltip: 'Delete Chapter',
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final text = titleController.text.trim();
                              if (text.isNotEmpty) {
                                final List<StudySection> newSections = [];
                                for (int i = 0; i < sectionControllers.length; i++) {
                                  final labelText = sectionControllers[i].text.trim();
                                  if (labelText.isNotEmpty) {
                                    newSections.add(
                                      StudySection(
                                        id: _generateUniqueId('sec'),
                                        title: labelText,
                                        isCompleted: false,
                                      ),
                                    );
                                  }
                                }

                                setState(() {
                                  if (isEditing) {
                                    final chIdx = subject.chapters.indexOf(existingChapter);
                                    if (chIdx != -1) {
                                      subject.chapters[chIdx] = Chapter(
                                        id: existingChapter.id,
                                        title: text,
                                        sections: newSections,
                                      );
                                    }
                                  } else {
                                    subject.chapters.add(
                                      Chapter(
                                        id: _generateUniqueId('chap'),
                                        title: text,
                                        sections: newSections,
                                      ),
                                    );
                                  }
                                });
                                _autoSaveToFirestore();
                              }

                              for (var ctrl in sectionControllers) {
                                ctrl.dispose();
                              }
                              titleController.dispose();
                              Navigator.pop(ctx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: Text(
                              isEditing ? 'Save Changes' : 'Save Chapter',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
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

  /// Global Section Management Modal (Add or Remove across Subjects with WriteBatch)
  void _showManageGlobalSectionsModal({String? initialSubjectId}) {
    final sectionNameController = TextEditingController(text: 'Exercise MCQ');
    bool isAddAction = true;
    final Set<String> selectedSubjectIds = initialSubjectId != null
        ? {initialSubjectId}
        : mySyllabus.map((s) => s.id).toSet();

    final popularSuggestions = [
      'Exercise MCQ',
      'Question Bank (প্রশ্নব্যাংক)',
      'Concept Book (কনসেপ্ট বুক)',
      'Class Note (ক্লাস নোট)',
      'Weekly Solution',
      'Probable Question (সম্ভাব্য প্রশ্ন)',
      'Formula Revision Sheet',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = selectedSubjectIds.length == mySyllabus.length && mySyllabus.isNotEmpty;

            final affectedChaptersCount = mySyllabus
                .where((s) => selectedSubjectIds.contains(s.id))
                .fold<int>(0, (total, s) => total + s.chapters.length);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.layers_rounded, color: colors.primary, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Manage Global Sections',
                              style: GoogleFonts.plusJakartaSans(
                                color: colors.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textMuted),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Section Name Field
                    Text(
                      'SECTION NAME',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: sectionNameController,
                        style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'e.g. Exercise MCQ',
                          hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Quick Suggestion Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: popularSuggestions.map((suggestion) {
                        return ActionChip(
                          label: Text(
                            suggestion,
                            style: GoogleFonts.plusJakartaSans(color: colors.primary, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: colors.recessed,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: colors.surfaceBorder),
                          ),
                          onPressed: () {
                            setModalState(() {
                              sectionNameController.text = suggestion;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Action Selector (Add to Subjects vs Remove from Subjects)
                    Text(
                      'ACTION',
                      style: GoogleFonts.jetBrainsMono(
                        color: colors.textMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  isAddAction = true;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isAddAction ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: isAddAction
                                      ? Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 15,
                                        color: isAddAction ? const Color(0xFF10B981) : colors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Add to Subject(s)',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: isAddAction ? colors.textPrimary : colors.textMuted,
                                          fontSize: 12,
                                          fontWeight: isAddAction ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  isAddAction = false;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: !isAddAction ? const Color(0xFFEF4444).withValues(alpha: 0.2) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: !isAddAction
                                      ? Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5))
                                      : null,
                                ),
                                child: Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.remove_circle_outline_rounded,
                                        size: 15,
                                        color: !isAddAction ? const Color(0xFFEF4444) : colors.textMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Remove from Subject(s)',
                                        style: GoogleFonts.plusJakartaSans(
                                          color: !isAddAction ? colors.textPrimary : colors.textMuted,
                                          fontSize: 12,
                                          fontWeight: !isAddAction ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Target Subjects Checklist Header with Select/Deselect All
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'TARGET SUBJECTS',
                          style: GoogleFonts.jetBrainsMono(
                            color: colors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (allSelected) {
                                selectedSubjectIds.clear();
                              } else {
                                selectedSubjectIds.addAll(mySyllabus.map((s) => s.id));
                              }
                            });
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            allSelected ? 'Deselect All' : 'Select All',
                            style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Multi-Select Subjects Checklist
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: colors.recessed,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.surfaceBorder),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: mySyllabus.map((subj) {
                          final isSel = selectedSubjectIds.contains(subj.id);
                          return CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              subj.title,
                              style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${subj.chapters.length} chapter(s)',
                              style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
                            ),
                            value: isSel,
                            activeColor: colors.primary,
                            checkColor: isDark ? const Color(0xFF171C24) : Colors.white,
                            onChanged: (checked) {
                              setModalState(() {
                                if (checked == true) {
                                  selectedSubjectIds.add(subj.id);
                                } else {
                                  selectedSubjectIds.remove(subj.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Preview info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isAddAction ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAddAction ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                            size: 16,
                            color: isAddAction ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isAddAction
                                  ? 'Will append "${sectionNameController.text.trim()}" across $affectedChaptersCount chapter(s) in ${selectedSubjectIds.length} subject(s).'
                                  : 'Will delete all instances of "${sectionNameController.text.trim()}" across $affectedChaptersCount chapter(s) in ${selectedSubjectIds.length} subject(s).',
                              style: GoogleFonts.plusJakartaSans(
                                color: isAddAction ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Submit Button with WriteBatch
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: selectedSubjectIds.isEmpty || sectionNameController.text.trim().isEmpty
                            ? null
                            : () async {
                                final sectionTitle = sectionNameController.text.trim();
                                Navigator.pop(ctx);
                                await _executeGlobalSectionWriteBatch(
                                  sectionName: sectionTitle,
                                  isAdd: isAddAction,
                                  subjectIds: selectedSubjectIds,
                                );
                              },
                        icon: Icon(
                          isAddAction ? Icons.add_task_rounded : Icons.delete_sweep_rounded,
                          size: 18,
                        ),
                        label: Text(
                          isAddAction ? 'Apply Global Add' : 'Apply Global Delete',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAddAction ? colors.primary : const Color(0xFFEF4444),
                          foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
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

  /// Executes Global Section WriteBatch to Cloud Firestore
  Future<void> _executeGlobalSectionWriteBatch({
    required String sectionName,
    required bool isAdd,
    required Set<String> subjectIds,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || mySyllabus.isEmpty) return;

    int affectedChapters = 0;
    int affectedSections = 0;

    setState(() {
      for (var sIdx = 0; sIdx < mySyllabus.length; sIdx++) {
        final subject = mySyllabus[sIdx];
        if (!subjectIds.contains(subject.id)) continue;

        for (var cIdx = 0; cIdx < subject.chapters.length; cIdx++) {
          final chapter = subject.chapters[cIdx];
          if (isAdd) {
            final alreadyExists = chapter.sections.any(
              (s) => s.title.trim().toLowerCase() == sectionName.toLowerCase(),
            );
            if (!alreadyExists) {
              chapter.sections.add(StudySection(
                id: _generateUniqueId('sec'),
                title: sectionName,
                isCompleted: false,
              ));
              affectedChapters++;
              affectedSections++;
            }
          } else {
            final initialLen = chapter.sections.length;
            chapter.sections.removeWhere(
              (s) => s.title.trim().toLowerCase() == sectionName.toLowerCase(),
            );
            final removedCount = initialLen - chapter.sections.length;
            if (removedCount > 0) {
              affectedChapters++;
              affectedSections += removedCount;
            }
          }
        }
      }
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('syllabus_state')
          .doc('active_syllabus'); // FIXED: USE ACTIVE SYLLABUS

      final data = mySyllabus.map((s) => s.toMap()).toList();
      batch.set(docRef, {
        'target': _lastTarget ?? 'default',
        'subjects': data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);

      SafeHaptics.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: isAdd ? const Color(0xFF10B981) : const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              isAdd
                  ? '✅ Added "$sectionName" to $affectedChapters chapter(s) across ${subjectIds.length} subject(s).'
                  : '🗑️ Removed $affectedSections instance(s) of "$sectionName" from $affectedChapters chapter(s).',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error applying global section write batch: $e');
    }
  }

  /// Executes Bulk Delete of Selected Random Sections via WriteBatch
  Future<void> _executeBulkDeleteRandomSections() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || selectedSectionKeys.isEmpty) return;

    final countToDelete = selectedSectionKeys.length;

    setState(() {
      for (var sIdx = 0; sIdx < mySyllabus.length; sIdx++) {
        final subject = mySyllabus[sIdx];
        for (var cIdx = 0; cIdx < subject.chapters.length; cIdx++) {
          final chapter = subject.chapters[cIdx];
          chapter.sections.removeWhere((sec) {
            final compositeKey = '${subject.id}|${chapter.id}|${sec.id}';
            return selectedSectionKeys.contains(compositeKey) ||
                selectedSectionKeys.contains(sec.id) ||
                selectedSectionKeys.contains('${subject.id}|${chapter.id}');
          });
        }
        // Also remove any chapter that was directly selected
        subject.chapters.removeWhere((ch) => selectedSectionKeys.contains('${subject.id}|${ch.id}'));
      }
      isSelectionMode = false;
      selectedSectionKeys.clear();
    });

    try {
      final batch = FirebaseFirestore.instance.batch();
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('syllabus_state')
          .doc('active_syllabus'); // FIXED: USE ACTIVE SYLLABUS

      final data = mySyllabus.map((s) => s.toMap()).toList();
      batch.set(docRef, {
        'target': _lastTarget ?? 'default',
        'subjects': data,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);

      SafeHaptics.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              '🗑️ Successfully deleted $countToDelete selected section(s).',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error executing bulk delete write batch: $e');
    }
  }

  // --- BottomSheet dialog to Add / Edit Section ---
  void _showSectionBottomSheet(Chapter chapter, {StudySection? existingSection}) {
    final titleController = TextEditingController(text: existingSection?.title ?? '');
    final isEditing = existingSection != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: colors.surfaceBorder),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Section' : 'Add Section',
                    style: GoogleFonts.plusJakartaSans(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.recessed,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: TextField(
                  controller: titleController,
                  style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Section Title (e.g. Theory & Formulas)',
                    hintStyle: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (isEditing) ...[
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: () {
                        setState(() {
                          chapter.sections.removeWhere((s) => s.id == existingSection.id);
                        });
                        _autoSaveToFirestore();
                        Navigator.pop(ctx);
                      },
                      tooltip: 'Delete Section',
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          final text = titleController.text.trim();
                          if (text.isNotEmpty) {
                            setState(() {
                              if (isEditing) {
                                final secIdx = chapter.sections.indexOf(existingSection);
                                if (secIdx != -1) {
                                  chapter.sections[secIdx] = StudySection(
                                    id: existingSection.id,
                                    title: text,
                                    isCompleted: existingSection.isCompleted,
                                  );
                                }
                              } else {
                                chapter.sections.add(StudySection(
                                  id: _generateUniqueId('sec'),
                                  title: text,
                                  isCompleted: false,
                                ));
                              }
                            });
                            _autoSaveToFirestore();
                          }
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: isDark ? const Color(0xFF171C24) : Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: Text(
                          isEditing ? 'Save Changes' : 'Add Section',
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider);

    if (!userProfile.isLoaded) {
      return const AppLoadingScreen(message: 'Loading syllabus...');
    }

    if (userProfile.isUniversityStudent) {
      return const UniversityDashboardScreen();
    }

    final backgroundColor = colors.background;
    final cardColor = colors.surface;
    final accentColor = colors.primary;
    final rustColor = colors.secondary;

    final currentTarget = userProfile.primaryTarget.isNotEmpty ? userProfile.primaryTarget : 'Engineering';
    final providerSubjects = ref.watch(syllabusProvider);

    // 1. FORCE SYNC: If the global provider receives new subjects from a profile save, update the UI instantly
    ref.listen<List<Subject>>(syllabusProvider, (previous, next) {
      if (next.isNotEmpty) {
        setState(() {
          mySyllabus = List<Subject>.from(next);
        });
      }
    });

    // 2. SAFELY listen to the TRUE profile target
    ref.listen<UserProfile>(userProfileProvider, (previous, next) {
      if (next.primaryTarget != _lastTarget && !_isLoadingFirestore && next.primaryTarget.isNotEmpty) {
        _loadSyllabusForTarget(next.primaryTarget);
      }
    });

    // 3. Safe initial load
    if (_lastTarget == null && !_isLoadingFirestore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadSyllabusForTarget(currentTarget);
      });
    }

    // 4. Initial sync
    if (!_isLoadingFirestore && mySyllabus.isEmpty && providerSubjects.isNotEmpty) {
      mySyllabus = List<Subject>.from(providerSubjects);
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        await _autoSaveToFirestore();
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        floatingActionButton: isSelectionMode && selectedSectionKeys.isNotEmpty
            ? FloatingActionButton.extended(
                backgroundColor: const Color(0xFFEF4444),
                elevation: 4,
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
                label: Text(
                  'Delete Selected (${selectedSectionKeys.length})',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  SafeHaptics.lightImpact();
                  showDialog(
                    context: context,
                    builder: (dCtx) {
                      return AlertDialog(
                        backgroundColor: colors.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: colors.surfaceBorder),
                        ),
                        title: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                            const SizedBox(width: 8),
                            Text('Confirm Delete', style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: Text(
                          'Are you sure you want to delete ${selectedSectionKeys.length} selected section(s)? This will atomically remove them from your syllabus.',
                          style: GoogleFonts.plusJakartaSans(color: colors.textSecondary, fontSize: 13.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textSecondary)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(dCtx);
                              _executeBulkDeleteRandomSections();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text('Delete Permanently', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    },
                  );
                },
              )
            : null,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Section / Selection Mode Bar
              if (isSelectionMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(bottom: BorderSide(color: colors.surfaceBorder)),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: colors.textPrimary),
                        onPressed: () {
                          setState(() {
                            isSelectionMode = false;
                            selectedSectionKeys.clear();
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${selectedSectionKeys.length} Section(s) Selected',
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            final allKeys = <String>{};
                            for (var subj in mySyllabus) {
                              for (var ch in subj.chapters) {
                                for (var sec in ch.sections) {
                                  allKeys.add('${subj.id}|${ch.id}|${sec.id}');
                                }
                              }
                            }
                            if (selectedSectionKeys.length == allKeys.length) {
                              selectedSectionKeys.clear();
                            } else {
                              selectedSectionKeys.addAll(allKeys);
                            }
                          });
                        },
                        child: Text(
                          selectedSectionKeys.isNotEmpty ? 'Deselect' : 'Select All',
                          style: GoogleFonts.plusJakartaSans(color: colors.secondary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentTarget,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: colors.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Complete coverage for ${userProfile.hscBatch.isNotEmpty ? 'HSC ${userProfile.hscBatch}' : 'your academic journey'}',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: colors.textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: 'Reset Syllabus',
                            child: InkWell(
                              onTap: _showResetPresetConfirmation,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: colors.surfaceBorder),
                                ),
                                child: Icon(Icons.restart_alt_rounded, color: colors.textMuted, size: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Overall Progress Indicator
                      _buildOverallProgressBar(rustColor),
                      const SizedBox(height: 12),

                      // Mode Toggles & Action Bar (2-Row Responsive Layout)
                      Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: cardColor,
                                      foregroundColor: colors.textPrimary,
                                      side: BorderSide(color: colors.surfaceBorder),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () => _showSubjectBottomSheet(),
                                    icon: Icon(Icons.add_rounded, size: 16, color: colors.textPrimary),
                                    label: Text(
                                      'Add Subject',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: cardColor,
                                      foregroundColor: colors.textPrimary,
                                      side: BorderSide(color: colors.surfaceBorder),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () => _showManageGlobalSectionsModal(),
                                    icon: Icon(Icons.tune_rounded, size: 16, color: colors.textPrimary),
                                    label: Text(
                                      'Global Sections',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: rustColor.withValues(alpha: 0.12),
                                      foregroundColor: rustColor,
                                      side: BorderSide(color: rustColor.withValues(alpha: 0.35)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () {
                                      SafeHaptics.lightImpact();
                                      setState(() {
                                        isSelectionMode = true;
                                        selectedSectionKeys.clear();
                                      });
                                    },
                                    icon: Icon(Icons.checklist_rounded, size: 16, color: rustColor),
                                    label: Text(
                                      'Bulk Select',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: isEditMode ? accentColor : cardColor,
                                      foregroundColor: isEditMode
                                          ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                          : colors.textPrimary,
                                      side: BorderSide(
                                        color: isEditMode ? accentColor : colors.surfaceBorder,
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        isEditMode = !isEditMode;
                                      });
                                      if (!isEditMode) {
                                        _autoSaveToFirestore();
                                      }
                                    },
                                    icon: Icon(
                                      isEditMode ? Icons.check_circle_rounded : Icons.edit_note_rounded,
                                      size: 16,
                                      color: isEditMode
                                          ? (isDark ? const Color(0xFF171C24) : Colors.white)
                                          : colors.textPrimary,
                                    ),
                                    label: Text(
                                      isEditMode ? 'Done' : 'Edit Order',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 4),

              // Subject List via ListView.builder
              Expanded(
                child: _isLoadingFirestore
                    ? const Center(child: AppPreloader(size: 44))
                    : (mySyllabus.isEmpty
                        ? Center(
                            child: Text(
                              'No subjects found for this target.',
                              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 14),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                            itemCount: mySyllabus.length,
                            itemBuilder: (context, index) {
                              final subject = mySyllabus[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: _buildSubjectCard(
                                  subject: subject,
                                  cardColor: cardColor,
                                  accentColor: accentColor,
                                ),
                              );
                            },
                          )),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectCard({
    required Subject subject,
    required Color cardColor,
    required Color accentColor,
  }) {
    final isExpanded = expandedSubjectIds.contains(subject.id);
    final totalSecs = subject.chapters.fold<int>(0, (total, c) => total + c.sections.length);
    final doneSecs = subject.chapters.fold<int>(0, (total, c) => total + c.sections.where((s) => s.isCompleted).length);
    final percent = totalSecs > 0 ? (doneSecs / totalSecs * 100) : 0.0;
    final iconData = _getSubjectIcon(subject.iconName, subject.title);

    final allSubjSectionKeys = <String>{};
    for (final ch in subject.chapters) {
      for (final sec in ch.sections) {
        allSubjSectionKeys.add('${subject.id}|${ch.id}|${sec.id}');
      }
    }
    final bool isAllSubjSelected = allSubjSectionKeys.isNotEmpty &&
        allSubjSectionKeys.every((k) => selectedSectionKeys.contains(k));
    final bool isPartialSubjSelected = !isAllSubjSelected &&
        allSubjSectionKeys.any((k) => selectedSectionKeys.contains(k));

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isExpanded ? accentColor.withValues(alpha: 0.5) : colors.surfaceBorder,
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  expandedSubjectIds.remove(subject.id);
                } else {
                  expandedSubjectIds.add(subject.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(16.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    InkWell(
                      onTap: () {
                        SafeHaptics.lightImpact();
                        setState(() {
                          if (isAllSubjSelected) {
                            selectedSectionKeys.removeAll(allSubjSectionKeys);
                          } else {
                            selectedSectionKeys.addAll(allSubjSectionKeys);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Icon(
                          isAllSubjSelected
                              ? Icons.check_box_rounded
                              : (isPartialSubjSelected
                                  ? Icons.indeterminate_check_box_rounded
                                  : Icons.check_box_outline_blank_rounded),
                          color: (isAllSubjSelected || isPartialSubjSelected)
                              ? const Color(0xFFEF4444)
                              : colors.textMuted,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(iconData, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '$doneSecs / $totalSecs Done (${percent.round()}%)',
                              style: GoogleFonts.jetBrainsMono(
                                color: colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: totalSecs > 0 ? (doneSecs / totalSecs) : 0,
                            backgroundColor: colors.recessed,
                            color: accentColor,
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEditMode) ...[
                        IconButton(
                          icon: Icon(Icons.edit_outlined, color: colors.textMuted, size: 18),
                          onPressed: () => _showSubjectBottomSheet(existingSubject: subject),
                          tooltip: 'Edit Subject',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.add_rounded, color: accentColor, size: 20),
                          onPressed: () => _showChapterBottomSheet(subject),
                          tooltip: 'Add Chapter',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(6),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: colors.textMuted,
                        size: 22,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (isExpanded) ...[
            Divider(height: 1, color: colors.surfaceBorder),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...subject.chapters.map((chapter) {
                    return _buildChapterItem(subject, chapter, accentColor);
                  }),
                  if (subject.chapters.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'No chapters in this subject.',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12.5),
                      ),
                    ),
                  if (isEditMode)
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _showChapterBottomSheet(subject),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: Text('Add Chapter', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(foregroundColor: accentColor),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChapterItem(Subject subject, Chapter chapter, Color accentColor) {
    final isChapterExpanded = expandedChapterIds.contains(chapter.id);
    final totalSecs = chapter.sections.length;
    final doneSecs = chapter.sections.where((s) => s.isCompleted).length;

    final chapterSectionKeys = chapter.sections.map((s) => '${subject.id}|${chapter.id}|${s.id}').toSet();
    final bool isAllChapterSelected = chapterSectionKeys.isNotEmpty &&
        chapterSectionKeys.every((k) => selectedSectionKeys.contains(k));
    final bool isPartialChapterSelected = !isAllChapterSelected &&
        chapterSectionKeys.any((k) => selectedSectionKeys.contains(k));

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: colors.recessed,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isChapterExpanded ? accentColor.withValues(alpha: 0.4) : colors.surfaceBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isChapterExpanded) {
                  expandedChapterIds.remove(chapter.id);
                } else {
                  expandedChapterIds.add(chapter.id);
                }
              });
            },
            borderRadius: BorderRadius.circular(12.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    InkWell(
                      onTap: () {
                        SafeHaptics.lightImpact();
                        setState(() {
                          if (isAllChapterSelected) {
                            selectedSectionKeys.removeAll(chapterSectionKeys);
                            selectedSectionKeys.remove('${subject.id}|${chapter.id}');
                          } else {
                            selectedSectionKeys.addAll(chapterSectionKeys);
                            if (chapterSectionKeys.isEmpty) {
                              selectedSectionKeys.add('${subject.id}|${chapter.id}');
                            }
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10.0),
                        child: Icon(
                          isAllChapterSelected
                              ? Icons.check_box_rounded
                              : (isPartialChapterSelected
                                  ? Icons.indeterminate_check_box_rounded
                                  : Icons.check_box_outline_blank_rounded),
                          color: (isAllChapterSelected || isPartialChapterSelected)
                              ? const Color(0xFFEF4444)
                              : colors.textMuted,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chapter.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: colors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (totalSecs > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '$doneSecs / $totalSecs done',
                            style: GoogleFonts.jetBrainsMono(
                              color: colors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isEditMode) ...[
                    IconButton(
                      icon: Icon(Icons.edit_outlined, color: colors.textMuted, size: 16),
                      onPressed: () => _showChapterBottomSheet(subject, existingChapter: chapter),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                    IconButton(
                      icon: Icon(Icons.add_rounded, color: accentColor, size: 18),
                      onPressed: () => _showSectionBottomSheet(chapter),
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                  Icon(
                    isChapterExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: colors.textMuted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isChapterExpanded) ...[
            Divider(height: 1, color: colors.surfaceBorder),
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 8.0),
              child: Column(
                children: [
                  ...chapter.sections.map((section) {
                    final compositeKey = '${subject.id}|${chapter.id}|${section.id}';
                    final isSelectedInBatch = selectedSectionKeys.contains(compositeKey) ||
                        selectedSectionKeys.contains(section.id);

                    if (isSelectionMode) {
                      return InkWell(
                        onTap: () {
                          SafeHaptics.lightImpact();
                          setState(() {
                            if (isSelectedInBatch) {
                              selectedSectionKeys.remove(compositeKey);
                              selectedSectionKeys.remove(section.id);
                            } else {
                              selectedSectionKeys.add(compositeKey);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelectedInBatch
                                ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelectedInBatch
                                ? Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4))
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelectedInBatch
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: isSelectedInBatch
                                    ? const Color(0xFFEF4444)
                                    : colors.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  section.title,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: isSelectedInBatch ? colors.textPrimary : colors.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: isSelectedInBatch ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return GestureDetector(
                      onLongPress: () {
                        SafeHaptics.heavyImpact();
                        setState(() {
                          isSelectionMode = true;
                          selectedSectionKeys.add(compositeKey);
                        });
                      },
                      child: Theme(
                        data: ThemeData.dark().copyWith(
                          unselectedWidgetColor: colors.textMuted,
                        ),
                        child: CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                          activeColor: accentColor,
                          checkColor: isDark ? const Color(0xFF171C24) : Colors.white,
                          value: section.isCompleted,
                          onChanged: (bool? value) {
                            if (value == true) {
                              SafeHaptics.heavyImpact();
                            } else {
                              SafeHaptics.lightImpact();
                            }
                            setState(() {
                              final secIdx = chapter.sections.indexOf(section);
                              if (secIdx != -1) {
                                chapter.sections[secIdx] = section.copyWith(
                                  isCompleted: value ?? false,
                                  lastModified: DateTime.now(),
                                );
                              }
                            });
                            _autoSaveToFirestore();
                          },
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  section.title,
                                  style: GoogleFonts.plusJakartaSans(
                                    color: section.isCompleted ? colors.textMuted : colors.textPrimary,
                                    fontSize: 12.5,
                                    decoration:
                                        section.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                                    decorationColor: colors.textMuted,
                                  ),
                                ),
                              ),
                              if (isEditMode)
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: colors.textMuted, size: 14),
                                  onPressed: () =>
                                      _showSectionBottomSheet(chapter, existingSection: section),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(4),
                                ),
                            ],
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    );
                  }),
                  if (chapter.sections.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'No sections added yet.',
                        style: GoogleFonts.plusJakartaSans(color: colors.textMuted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showResetPresetConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.surfaceBorder),
        ),
        title: Text(
          'Reset Syllabus to Presets?',
          style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'This will overwrite any custom syllabus changes and restore the default syllabus preset for your current target.',
          style: GoogleFonts.plusJakartaSans(color: colors.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final target = _lastTarget ?? 'Engineering';
              mySyllabus = SyllabusFactory.generateInitialSyllabus(target);
              ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);
              _autoSaveToFirestore();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.surfaceBorder),
                  ),
                  content: Text(
                    'Syllabus successfully reset to presets!',
                    style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
            child: Text('Reset', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgressBar(Color accentColor) {
    if (mySyllabus.isEmpty) return const SizedBox.shrink();
    final totalSections = mySyllabus.fold<int>(
      0,
      (total, s) => total + s.chapters.fold<int>(0, (cSum, c) => cSum + c.sections.length),
    );
    final completedSections = mySyllabus.fold<int>(
      0,
      (total, s) => total + s.chapters.fold<int>(
        0,
        (cSum, c) => cSum + c.sections.where((sec) => sec.isCompleted).length,
      ),
    );
    final progress = totalSections > 0 ? (completedSections / totalSections) : 0.0;
    final percentage = (progress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall Syllabus Completion',
                style: GoogleFonts.plusJakartaSans(color: colors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                '$percentage%',
                style: GoogleFonts.jetBrainsMono(color: accentColor, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colors.recessed,
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$completedSections of $totalSections sections completed',
            style: GoogleFonts.jetBrainsMono(color: colors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}