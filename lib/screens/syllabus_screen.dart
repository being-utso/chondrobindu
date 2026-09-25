import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/syllabus_provider.dart';
import '../services/syllabus_factory.dart';
import '../providers/user_profile_provider.dart';
import 'university_dashboard_screen.dart';
import '../widgets/app_loading_screen.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Syllabus Screen featuring dynamic Subjects, Chapters, and StudySections
/// with Global Section Management (Add/Delete across subjects via WriteBatch),
/// Bulk Select & Delete mode (random sections via WriteBatch), and real-time state sync.
class SyllabusScreen extends ConsumerStatefulWidget {
  const SyllabusScreen({super.key});

  @override
  ConsumerState<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends ConsumerState<SyllabusScreen> {
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
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Subject Title',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF241C1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFF2B78A)),
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
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF110D0C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isEditing ? 'Save Changes' : 'Add Subject',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.blueGrey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'CHAPTER NAME',
                      style: TextStyle(
                        color: Color(0xFFF2B78A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: titleController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. Chapter 3: Dynamics',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF241C1A),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF382A24)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF382A24)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'AVAILABLE SUBJECT SECTIONS (TAP TO ADD/REMOVE)',
                      style: TextStyle(
                        color: Color(0xFFF2B78A),
                        fontSize: 10,
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
                            style: TextStyle(
                              color: isAlreadyAdded ? const Color(0xFF110D0C) : Colors.blueGrey.shade300,
                              fontSize: 11,
                              fontWeight: isAlreadyAdded ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          selected: isAlreadyAdded,
                          selectedColor: const Color(0xFFF2B78A),
                          backgroundColor: const Color(0xFF241C1A),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        const Text(
                          'CONFIGURED CHAPTER SECTIONS',
                          style: TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          '${sectionControllers.length} Section(s)',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
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
                              child: TextField(
                                controller: sectionControllers[idx],
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Section ${idx + 1}',
                                  hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
                                  filled: true,
                                  fillColor: const Color(0xFF241C1A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF382A24)),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFF382A24)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(color: Color(0xFFF2B78A)),
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
                      icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFFF2B78A)),
                      label: const Text('Add Custom Section Field', style: TextStyle(color: Color(0xFFF2B78A))),
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
                              backgroundColor: const Color(0xFFF2B78A),
                              foregroundColor: const Color(0xFF110D0C),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              isEditing ? 'Save Changes' : 'Save Chapter',
                              style: const TextStyle(fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final allSelected = selectedSubjectIds.length == mySyllabus.length && mySyllabus.isNotEmpty;

            final affectedChaptersCount = mySyllabus
                .where((s) => selectedSubjectIds.contains(s.id))
                .fold<int>(0, (sum, s) => sum + s.chapters.length);

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
                        const Row(
                          children: [
                            Icon(Icons.layers_rounded, color: Color(0xFFF2B78A), size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Manage Global Sections',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.blueGrey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Section Name Field
                    const Text(
                      'SECTION NAME',
                      style: TextStyle(
                        color: Color(0xFFF2B78A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: sectionNameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'e.g. Exercise MCQ',
                        hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF241C1A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF382A24)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF382A24)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 11),
                          ),
                          backgroundColor: const Color(0xFF241C1A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: const Color(0xFFF2B78A).withValues(alpha: 0.3)),
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
                    const Text(
                      'ACTION',
                      style: TextStyle(
                        color: Color(0xFFF2B78A),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF382A24)),
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
                                        color: isAddAction ? const Color(0xFF10B981) : Colors.blueGrey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Add to Subject(s)',
                                        style: TextStyle(
                                          color: isAddAction ? Colors.white : Colors.blueGrey,
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
                                        color: !isAddAction ? const Color(0xFFEF4444) : Colors.blueGrey,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Remove from Subject(s)',
                                        style: TextStyle(
                                          color: !isAddAction ? Colors.white : Colors.blueGrey,
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
                        const Text(
                          'TARGET SUBJECTS',
                          style: TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
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
                            style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Multi-Select Subjects Checklist
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF382A24)),
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
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              '${subj.chapters.length} chapter(s)',
                              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                            ),
                            value: isSel,
                            activeColor: const Color(0xFFF2B78A),
                            checkColor: const Color(0xFF110D0C),
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
                              style: TextStyle(
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
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAddAction ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            return selectedSectionKeys.contains(compositeKey) || selectedSectionKeys.contains(sec.id);
          });
        }
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
      backgroundColor: const Color(0xFF1C1412),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Section Title',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF241C1A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF382A24))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF382A24))),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFF2B78A)),
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
                        backgroundColor: const Color(0xFFF2B78A),
                        foregroundColor: const Color(0xFF110D0C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isEditing ? 'Save Changes' : 'Add Section',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

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
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  SafeHaptics.lightImpact();
                  showDialog(
                    context: context,
                    builder: (dCtx) {
                      return AlertDialog(
                        backgroundColor: const Color(0xFF1C1412),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFF382A24)),
                        ),
                        title: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                            SizedBox(width: 8),
                            Text('Confirm Delete', style: TextStyle(color: Colors.white, fontSize: 17)),
                          ],
                        ),
                        content: Text(
                          'Are you sure you want to delete ${selectedSectionKeys.length} selected section(s)? This will atomically remove them from your syllabus.',
                          style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13.5),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dCtx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
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
                            child: const Text('Delete Permanently', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  color: const Color(0xFF1C1412),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
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
                          style: const TextStyle(
                            color: Colors.white,
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
                          style: const TextStyle(color: Color(0xFFF2B78A), fontWeight: FontWeight.bold),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Complete coverage for ${userProfile.hscBatch.isNotEmpty ? 'HSC ${userProfile.hscBatch}' : 'your academic journey'}',
                                  style: TextStyle(
                                    color: Colors.blueGrey.shade400,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.download_rounded, color: Colors.blueGrey),
                            tooltip: 'Reset to Presets',
                            onPressed: _showResetPresetConfirmation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Overall Progress Indicator
                      _buildOverallProgressBar(accentColor),
                      const SizedBox(height: 12),

                      // Mode Toggles & Action Bar
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionChip(
                              label: const Text('Add Subject', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              avatar: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                              backgroundColor: cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              onPressed: () => _showSubjectBottomSheet(),
                            ),
                            const SizedBox(width: 8),

                            ActionChip(
                              label: const Text('Manage Global Sections', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              avatar: const Icon(Icons.tune_rounded, size: 16, color: Colors.white),
                              backgroundColor: cardColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              onPressed: () => _showManageGlobalSectionsModal(),
                            ),
                            const SizedBox(width: 8),

                            ActionChip(
                              label: const Text(
                                'Bulk Select',
                                style: TextStyle(
                                  color: Color(0xFFF2B78A),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                              avatar: const Icon(
                                Icons.checklist_rounded,
                                size: 16,
                                color: Color(0xFFF2B78A),
                              ),
                              backgroundColor: const Color(0xFFF2B78A).withValues(alpha: 0.12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: const Color(0xFFF2B78A).withValues(alpha: 0.35)),
                              ),
                              onPressed: () {
                                SafeHaptics.lightImpact();
                                setState(() {
                                  isSelectionMode = true;
                                  selectedSectionKeys.clear();
                                });
                              },
                            ),
                            const SizedBox(width: 8),

                            FilterChip(
                              label: Text(
                                isEditMode ? 'Done' : 'Edit',
                                style: TextStyle(
                                  color: isEditMode ? const Color(0xFF110D0C) : Colors.blueGrey.shade300,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                              selected: isEditMode,
                              onSelected: (val) {
                                setState(() {
                                  isEditMode = val;
                                });
                                if (!val) {
                                  _autoSaveToFirestore();
                                }
                              },
                              selectedColor: accentColor,
                              backgroundColor: cardColor,
                              avatar: Icon(
                                isEditMode ? Icons.check_circle_rounded : Icons.edit_note_rounded,
                                size: 16,
                                color: isEditMode ? const Color(0xFF110D0C) : Colors.blueGrey.shade300,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isEditMode ? accentColor : Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              showCheckmark: false,
                            ),
                          ],
                        ),
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
    final totalSecs = subject.chapters.fold<int>(0, (sum, c) => sum + c.sections.length);
    final doneSecs = subject.chapters.fold<int>(0, (sum, c) => sum + c.sections.where((s) => s.isCompleted).length);
    final percent = totalSecs > 0 ? (doneSecs / totalSecs * 100) : 0.0;
    final iconData = _getSubjectIcon(subject.iconName, subject.title);
    return Container(

      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isExpanded ? accentColor.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
          width: isExpanded ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  expandedSubjectIds.remove(subject.id);
                } else {
                  expandedSubjectIds.add(subject.id);
                }
              });
            },
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: accentColor, size: 22),
            ),
            title: Text(
              subject.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '$doneSecs / $totalSecs Done (${percent.round()}%)',
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
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
                    backgroundColor: const Color(0xFF382A24),
                    color: accentColor,
                    minHeight: 4,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEditMode) ...[
                  IconButton(
                    icon: const Icon(Icons.layers_rounded, color: Color(0xFF10B981), size: 20),
                    onPressed: () => _showManageGlobalSectionsModal(initialSubjectId: subject.id),
                    tooltip: 'Manage Global Sections for Subject',
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 18),
                    onPressed: () => _showSubjectBottomSheet(existingSubject: subject),
                    tooltip: 'Edit Subject',
                  ),
                  IconButton(
                    icon: Icon(Icons.add_rounded, color: accentColor, size: 20),
                    onPressed: () => _showChapterBottomSheet(subject),
                    tooltip: 'Add Chapter',
                  ),
                ],
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.blueGrey.shade400,
                  size: 26,
                ),
              ],
            ),
          ),

          if (isExpanded) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
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
                        style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12.5),
                      ),
                    ),
                  if (isEditMode)
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => _showChapterBottomSheet(subject),
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text('Add Chapter'),
                          style: TextButton.styleFrom(foregroundColor: accentColor),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _showManageGlobalSectionsModal(initialSubjectId: subject.id),
                          icon: const Icon(Icons.layers_rounded, size: 16),
                          label: const Text('Global Section'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: isChapterExpanded ? accentColor.withValues(alpha: 0.3) : const Color(0xFF382A24),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chapter.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (totalSecs > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '$doneSecs / $totalSecs done',
                            style: TextStyle(
                              color: Colors.blueGrey.shade400,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isEditMode) ...[
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 16),
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
                    color: Colors.blueGrey.shade400,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (isChapterExpanded) ...[
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
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
                                    : Colors.blueGrey.shade500,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  section.title,
                                  style: TextStyle(
                                    color: isSelectedInBatch ? Colors.white : Colors.blueGrey.shade200,
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
                          unselectedWidgetColor: Colors.blueGrey.shade500,
                        ),
                        child: CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                          activeColor: accentColor,
                          checkColor: const Color(0xFF110D0C),
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
                                  style: TextStyle(
                                    color: section.isCompleted ? Colors.blueGrey.shade400 : Colors.white,
                                    fontSize: 12.5,
                                    decoration:
                                        section.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
                                    decorationColor: Colors.blueGrey.shade400,
                                  ),
                                ),
                              ),
                              if (isEditMode)
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 14),
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
                        style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 12),
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
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reset Syllabus to Presets?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: const Text(
          'This will overwrite any custom syllabus changes and restore the default syllabus preset for your current target.',
          style: TextStyle(color: Color(0xFFABA093), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              final target = _lastTarget ?? 'Engineering';
              mySyllabus = SyllabusFactory.generateInitialSyllabus(target);
              ref.read(syllabusProvider.notifier).setSubjects(mySyllabus);
              _autoSaveToFirestore();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF10B981),
                  content: Text(
                    'Syllabus successfully reset to presets!',
                    style: TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
            child: const Text('Reset', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallProgressBar(Color accentColor) {
    if (mySyllabus.isEmpty) return const SizedBox.shrink();
    final totalSections = mySyllabus.fold<int>(
      0,
      (sum, s) => sum + s.chapters.fold<int>(0, (cSum, c) => cSum + c.sections.length),
    );
    final completedSections = mySyllabus.fold<int>(
      0,
      (sum, s) => sum + s.chapters.fold<int>(
        0,
        (cSum, c) => cSum + c.sections.where((sec) => sec.isCompleted).length,
      ),
    );
    final progress = totalSections > 0 ? (completedSections / totalSections) : 0.0;
    final percentage = (progress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1412),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF382A24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Syllabus Completion',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              Text(
                '$percentage%',
                style: TextStyle(color: accentColor, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF382A24),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$completedSections of $totalSections sections completed',
            style: const TextStyle(color: Color(0xFFABA093), fontSize: 11),
          ),
        ],
      ),
    );
  }
}