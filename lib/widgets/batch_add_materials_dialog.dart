import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/syllabus_node.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

/// Multi-select dialog allowing the user to select multiple topic items within a section
/// and choose one or more categories ("Class Note", "Lecture Sheet", "Ref Book", "Term Final Question",
/// or "+ Custom") to attach to all selected topics at once.
class BatchAddMaterialsDialog extends StatefulWidget {
  final SyllabusNode sectionNode;
  final List<SyllabusNode> allNodes;
  final Future<void> Function(List<SyllabusNode> allNodes)? onSave;

  const BatchAddMaterialsDialog({
    super.key,
    required this.sectionNode,
    required this.allNodes,
    this.onSave,
  });

  @override
  State<BatchAddMaterialsDialog> createState() => _BatchAddMaterialsDialogState();
}

class _BatchAddMaterialsDialogState extends State<BatchAddMaterialsDialog> {
  late final List<SyllabusNode> _topics;
  late final Set<SyllabusNode> _selectedTopics;
  final Set<String> _selectedCategories = {'Class Note', 'Lecture Sheet'};
  final List<String> _customCategories = [];

  bool _isAddingCustom = false;
  final TextEditingController _customTitleController = TextEditingController();

  static const List<Map<String, dynamic>> _standardCategories = [
    {'title': 'Class Note', 'icon': Icons.edit_note_rounded, 'color': Color(0xFFF2B78A)},
    {'title': 'Lecture Sheet', 'icon': Icons.description_outlined, 'color': Color(0xFF10B981)},
    {'title': 'Ref Book', 'icon': Icons.menu_book_rounded, 'color': Color(0xFFF59E0B)},
    {'title': 'Term Final Question', 'icon': Icons.quiz_outlined, 'color': Color(0xFFA855F7)},
  ];

  @override
  void initState() {
    super.initState();
    // Direct child filtering (one level down only): immediate direct child topics under sectionNode
    _topics = List<SyllabusNode>.from(widget.sectionNode.children);
    _selectedTopics = Set.from(_topics);
  }

  @override
  void dispose() {
    _customTitleController.dispose();
    super.dispose();
  }

  void _addCustomCategory() {
    final text = _customTitleController.text.trim();
    if (text.isNotEmpty) {
      SafeHaptics.lightImpact();
      setState(() {
        if (!_customCategories.any((c) => c.toLowerCase() == text.toLowerCase())) {
          _customCategories.add(text);
        }
        _selectedCategories.add(text);
        _customTitleController.clear();
        _isAddingCustom = false;
      });
    }
  }

  Future<void> _handleAttach() async {
    if (_selectedTopics.isEmpty || _selectedCategories.isEmpty) return;

    int addedCount = 0;
    int skippedCount = 0;

    for (final topic in _selectedTopics) {
      for (final cat in _selectedCategories) {
        final catName = cat.trim();
        final exists = topic.children.any(
          (c) => c.title.trim().toLowerCase() == catName.toLowerCase(),
        );
        if (!exists) {
          topic.children.add(
            SyllabusNode(
              title: catName,
              isLeaf: true,
              isCompleted: false,
              parentId: topic.id,
            ),
          );
          addedCount++;
        } else {
          skippedCount++;
        }
      }
    }

    for (final root in widget.allNodes) {
      root.updateHierarchicalCompletion();
    }

    if (widget.onSave != null) {
      await widget.onSave!(widget.allNodes);
    }

    if (mounted) {
      Navigator.pop(context);

      final String message;
      if (skippedCount > 0) {
        if (addedCount > 0) {
          message = 'Added $addedCount material(s) ($skippedCount duplicate(s) skipped).';
        } else {
          message = 'Materials already attached. Skipped $skippedCount existing item(s).';
        }
      } else {
        message = 'Successfully attached $addedCount material(s) across ${_selectedTopics.length} topic(s)!';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: (skippedCount > 0 && addedCount == 0)
              ? const Color(0xFFF59E0B)
              : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Text(message),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF1C1412);
    const cardColor = Color(0xFF241C1A);
    const borderColor = Color(0xFF382A24);
    const accentColor = Color(0xFFF2B78A);

    if (_topics.isEmpty) {
      return AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: borderColor),
        ),
        title: Text('No Topics Found', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          'No topics found inside "${widget.sectionNode.title}". Please add topics first.',
          style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.plusJakartaSans(color: accentColor, fontWeight: FontWeight.bold)),
          ),
        ],
      );
    }

    final totalToCreate = _selectedTopics.length * _selectedCategories.length;

    return AlertDialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor, width: 0.8),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.library_add_rounded, color: accentColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Add Materials',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Section: "${widget.sectionNode.title}"',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 11.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step 1: Select Categories
              Text(
                '1. SELECT CATEGORIES TO ATTACH',
                style: GoogleFonts.plusJakartaSans(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Standard categories
                  ..._standardCategories.map((cat) {
                    final cTitle = cat['title'] as String;
                    final icon = cat['icon'] as IconData;
                    final color = cat['color'] as Color;
                    final isSelected = _selectedCategories.contains(cTitle);

                    return FilterChip(
                      avatar: Icon(
                        icon,
                        size: 16,
                        color: isSelected ? const Color(0xFF140F0E) : color,
                      ),
                      label: Text(
                        cTitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: isSelected ? const Color(0xFF140F0E) : Colors.white,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: accentColor,
                      backgroundColor: cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected ? accentColor : borderColor,
                        ),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategories.add(cTitle);
                          } else {
                            if (_selectedCategories.length > 1) {
                              _selectedCategories.remove(cTitle);
                            }
                          }
                        });
                      },
                    );
                  }),

                  // Dynamic custom categories
                  ..._customCategories.map((customTitle) {
                    final isSelected = _selectedCategories.contains(customTitle);

                    return FilterChip(
                      avatar: Icon(
                        Icons.bookmark_added_rounded,
                        size: 16,
                        color: isSelected ? const Color(0xFF140F0E) : const Color(0xFFEC4899),
                      ),
                      label: Text(
                        customTitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: isSelected ? const Color(0xFF140F0E) : Colors.white,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: const Color(0xFFEC4899),
                      backgroundColor: cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected ? const Color(0xFFEC4899) : const Color(0xFFEC4899).withValues(alpha: 0.3),
                        ),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCategories.add(customTitle);
                          } else {
                            if (_selectedCategories.length > 1) {
                              _selectedCategories.remove(customTitle);
                            }
                          }
                        });
                      },
                    );
                  }),

                  // Fifth button: + Custom
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 16, color: Color(0xFFEC4899)),
                    label: Text(
                      '+ Custom',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFFEC4899),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: const Color(0xFFEC4899).withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: const Color(0xFFEC4899).withValues(alpha: 0.35)),
                    ),
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      setState(() {
                        _isAddingCustom = !_isAddingCustom;
                      });
                    },
                  ),
                ],
              ),

              // Inline Custom Category Input Field
              if (_isAddingCustom) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEC4899).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customTitleController,
                          autofocus: true,
                          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. Assignment Sheet, Lab Manual',
                            hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF7E726B), fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _addCustomCategory(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEC4899),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: _addCustomCategory,
                        child: Text('Add', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),
              const Divider(color: Color(0xFF382A24), height: 1),
              const SizedBox(height: 14),

              // Step 2: Select Topics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '2. SELECT TOPICS (${_selectedTopics.length}/${_topics.length})',
                    style: GoogleFonts.plusJakartaSans(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        if (_selectedTopics.length == _topics.length) {
                          _selectedTopics.clear();
                        } else {
                          _selectedTopics.addAll(_topics);
                        }
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _selectedTopics.length == _topics.length ? 'Deselect All' : 'Select All',
                      style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Material(
                    color: Colors.transparent,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _topics.length,
                      separatorBuilder: (_, __) => const Divider(color: Color(0xFF382A24), height: 1),
                      itemBuilder: (context, idx) {
                        final topic = _topics[idx];
                        final isChecked = _selectedTopics.contains(topic);

                        return CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          activeColor: accentColor,
                          checkColor: const Color(0xFF140F0E),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: isChecked,
                          title: Text(
                            topic.title,
                            style: GoogleFonts.plusJakartaSans(
                              color: isChecked ? Colors.white : const Color(0xFFABA093),
                              fontSize: 12.5,
                              fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          subtitle: topic.children.isNotEmpty
                              ? Text(
                                  '${topic.children.length} sub-item(s) existing',
                                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF7E726B), fontSize: 10.5),
                                )
                              : null,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedTopics.add(topic);
                              } else {
                                _selectedTopics.remove(topic);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: const Color(0xFF140F0E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (_selectedTopics.isEmpty || _selectedCategories.isEmpty)
              ? null
              : _handleAttach,
          child: Text(
            totalToCreate > 0 ? 'Attach ($totalToCreate)' : 'Attach',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
