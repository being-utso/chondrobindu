import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/note_model.dart';
import '../providers/notes_provider.dart';
import '../widgets/app_preloader.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final NoteModel? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late TextEditingController _titleController;
  late QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  late bool _isPinned;
  late String _selectedTag;
  late DateTime _lastEditedDate;
  String? _currentNoteId;
  bool _isSaving = false;
  bool _hasChanges = false;

  static const List<String> availableTags = ['General', 'Brain Dump', 'Formula', 'Mistake'];

  @override
  void initState() {
    super.initState();
    _currentNoteId = widget.note?.id;
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _quillController = _initQuillController(widget.note?.content);

    _isPinned = widget.note?.isPinned ?? false;
    _selectedTag = (widget.note?.tags.isNotEmpty ?? false)
        ? widget.note!.tags.first
        : 'General';
    _lastEditedDate = widget.note?.updatedAt ?? DateTime.now();

    _titleController.addListener(_onTextChanged);
    _quillController.addListener(_onQuillChanged);
  }

  QuillController _initQuillController(String? rawContent) {
    if (rawContent == null || rawContent.trim().isEmpty) {
      return QuillController.basic();
    }

    try {
      final jsonData = jsonDecode(rawContent);
      if (jsonData is List) {
        final doc = Document.fromJson(jsonData);
        return QuillController(
          document: doc,
          selection: const TextSelection.collapsed(offset: 0),
        );
      }
    } catch (_) {
      // Fallback if legacy content is plain text/markdown
    }

    final doc = Document()..insert(0, rawContent);
    return QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _onTextChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  void _onQuillChanged() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _quillController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  String _formatAppleDate(DateTime dt) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final monthName = months[dt.month - 1];
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    return '$monthName ${dt.day}, ${dt.year} at $hour12:$minuteStr $period';
  }

  Future<void> _saveNote() async {
    if (!_hasChanges || _isSaving) return;

    final title = _titleController.text.trim();
    final plainTextContent = _quillController.document.toPlainText().trim();
    final deltaJson = jsonEncode(_quillController.document.toDelta().toJson());

    if (title.isEmpty && plainTextContent.isEmpty) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
      _hasChanges = false;
    });

    try {
      final noteService = ref.read(noteServiceProvider);
      final finalTitle = title.isNotEmpty
          ? title
          : (plainTextContent.length > 30
              ? '${plainTextContent.substring(0, 30)}...'
              : plainTextContent);

      final now = DateTime.now();
      _lastEditedDate = now;

      if (_currentNoteId == null || _currentNoteId!.isEmpty) {
        // Create new note
        final newNote = NoteModel(
          id: '',
          title: finalTitle,
          content: deltaJson,
          createdAt: now,
          updatedAt: now,
          isPinned: _isPinned,
          tags: [_selectedTag],
        );
        final createdId = await noteService.addNote(user.uid, newNote);
        _currentNoteId = createdId;
      } else {
        // Update existing note
        final updatedNote = NoteModel(
          id: _currentNoteId!,
          title: finalTitle,
          content: deltaJson,
          createdAt: widget.note?.createdAt ?? now,
          updatedAt: now,
          isPinned: _isPinned,
          tags: [_selectedTag],
        );
        await noteService.updateNote(user.uid, updatedNote);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasChanges = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to save note: $e', style: const TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _deleteNote() async {
    if (_currentNoteId == null || _currentNoteId!.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1412),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF382A24)),
        ),
        title: const Text('Delete Note?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'Are you sure you want to delete this note? This action cannot be undone.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && _currentNoteId != null) {
        await ref.read(noteServiceProvider).deleteNote(user.uid, _currentNoteId!);
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _copyNoteToClipboard() {
    final title = _titleController.text.trim();
    final content = _quillController.document.toPlainText().trim();
    final fullText = '${title.isNotEmpty ? '$title\n\n' : ''}$content';

    if (fullText.trim().isEmpty) return;

    Clipboard.setData(ClipboardData(text: fullText));
    SafeHaptics.lightImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFF2B78A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: const [
            Icon(Icons.content_copy_rounded, color: Color(0xFF110D0C), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Note copied to clipboard!',
                style: TextStyle(color: Color(0xFF110D0C), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Active Attribute Inspectors ---
  Style get _selectionStyle => _quillController.getSelectionStyle();

  bool _isBold() => _selectionStyle.containsKey(Attribute.bold.key);
  bool _isItalic() => _selectionStyle.containsKey(Attribute.italic.key);
  bool _isHeading() => _selectionStyle.containsKey(Attribute.h1.key) || _selectionStyle.containsKey(Attribute.h2.key) || _selectionStyle.containsKey(Attribute.header.key);
  bool _isChecklist() => _selectionStyle.containsKey(Attribute.unchecked.key) || _selectionStyle.containsKey(Attribute.checked.key);
  bool _isBullet() => _selectionStyle.containsKey(Attribute.ul.key);
  bool _isCode() => _selectionStyle.containsKey(Attribute.inlineCode.key);

  // --- Rich Text Toggles ---
  void _toggleBold() {
    _quillController.formatSelection(
      _isBold() ? Attribute.clone(Attribute.bold, null) : Attribute.bold,
    );
  }

  void _toggleItalic() {
    _quillController.formatSelection(
      _isItalic() ? Attribute.clone(Attribute.italic, null) : Attribute.italic,
    );
  }

  void _toggleHeading() {
    _quillController.formatSelection(
      _isHeading() ? Attribute.clone(Attribute.h1, null) : Attribute.h1,
    );
  }

  void _toggleChecklist() {
    _quillController.formatSelection(
      _isChecklist() ? Attribute.clone(Attribute.unchecked, null) : Attribute.unchecked,
    );
  }

  void _toggleBulletList() {
    _quillController.formatSelection(
      _isBullet() ? Attribute.clone(Attribute.ul, null) : Attribute.ul,
    );
  }

  void _toggleCode() {
    _quillController.formatSelection(
      _isCode() ? Attribute.clone(Attribute.inlineCode, null) : Attribute.inlineCode,
    );
  }

  Widget _buildAppleFormattingToolbar() {
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    final isBold = _isBold();
    final isItalic = _isItalic();
    final isHeading = _isHeading();
    final isChecklist = _isChecklist();
    final isBullet = _isBullet();
    final isCode = _isCode();

    Widget buildToolbarButton({
      required IconData icon,
      required String tooltip,
      required bool isActive,
      required VoidCallback onPressed,
    }) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive ? accentColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: IconButton(
          icon: Icon(
            icon,
            color: isActive ? accentColor : Colors.white,
            size: 20,
          ),
          tooltip: tooltip,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            buildToolbarButton(
              icon: Icons.format_bold_rounded,
              tooltip: 'Bold',
              isActive: isBold,
              onPressed: _toggleBold,
            ),
            buildToolbarButton(
              icon: Icons.format_italic_rounded,
              tooltip: 'Italic',
              isActive: isItalic,
              onPressed: _toggleItalic,
            ),
            buildToolbarButton(
              icon: Icons.title_rounded,
              tooltip: 'Heading 1',
              isActive: isHeading,
              onPressed: _toggleHeading,
            ),
            buildToolbarButton(
              icon: Icons.checklist_rounded,
              tooltip: 'Checklist Item',
              isActive: isChecklist,
              onPressed: _toggleChecklist,
            ),
            buildToolbarButton(
              icon: Icons.format_list_bulleted_rounded,
              tooltip: 'Bullet List',
              isActive: isBullet,
              onPressed: _toggleBulletList,
            ),
            buildToolbarButton(
              icon: Icons.code_rounded,
              tooltip: 'Code / Formula',
              isActive: isCode,
              onPressed: _toggleCode,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const accentColor = Color(0xFFF2B78A);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (_hasChanges) {
          await _saveNote();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: backgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: accentColor, size: 20),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          title: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTag,
              dropdownColor: const Color(0xFF1C1412),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: accentColor, size: 20),
              style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  SafeHaptics.lightImpact();
                  setState(() {
                    _selectedTag = newValue;
                    _hasChanges = true;
                  });
                }
              },
              items: availableTags.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                color: _isPinned ? accentColor : Colors.blueGrey.shade300,
                size: 20,
              ),
              tooltip: _isPinned ? 'Unpin Note' : 'Pin Note',
              onPressed: () {
                SafeHaptics.lightImpact();
                setState(() {
                  _isPinned = !_isPinned;
                  _hasChanges = true;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.content_copy_rounded, color: Colors.white, size: 19),
              tooltip: 'Copy to Clipboard',
              onPressed: _copyNoteToClipboard,
            ),
            if (_currentNoteId != null && _currentNoteId!.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 20),
                tooltip: 'Delete Note',
                onPressed: _deleteNote,
              ),
            TextButton(
              onPressed: () async {
                await _saveNote();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF10B981),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      content: const Text(
                        'Note saved',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  );
                }
              },
              child: _isSaving
                  ? const AppPreloader(
                      size: 16,
                      strokeWidth: 2,
                      color: accentColor,
                    )
                  : const Text(
                      'Done',
                      style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Apple Notes Style Centered Date Header
                      Center(
                        child: Text(
                          _formatAppleDate(_lastEditedDate),
                          style: TextStyle(
                            color: Colors.blueGrey.shade400,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Seamless Title Input
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Title',
                          hintStyle: TextStyle(color: Color(0xFF475569), fontSize: 24, fontWeight: FontWeight.bold),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Seamless Quill Rich Text Editor Body Canvas
                      Builder(
                        builder: (context) {
                          final interFontFamily = GoogleFonts.inter().fontFamily;

                          return Expanded(
                            child: QuillEditor(
                              controller: _quillController,
                              scrollController: _editorScrollController,
                              focusNode: _editorFocusNode,
                              config: QuillEditorConfig(
                                placeholder: 'Start writing your study note, formulas, or checklist...',
                                padding: EdgeInsets.zero,
                                autoFocus: false,
                                expands: false,
                                showCursor: true,
                                customStyles: DefaultStyles(
                                  bold: TextStyle(
                                    fontFamily: interFontFamily,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  italic: TextStyle(
                                    fontFamily: interFontFamily,
                                    fontStyle: FontStyle.italic,
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  paragraph: DefaultTextBlockStyle(
                                    TextStyle(
                                      fontFamily: interFontFamily,
                                      color: const Color(0xFFE2E8F0),
                                      fontSize: 16,
                                      height: 1.5,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    const HorizontalSpacing(0, 0),
                                    const VerticalSpacing(0, 0),
                                    const VerticalSpacing(0, 0),
                                    null,
                                  ),
                                  h1: DefaultTextBlockStyle(
                                    TextStyle(
                                      fontFamily: interFontFamily,
                                      color: const Color(0xFFF2B78A),
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                    const HorizontalSpacing(0, 0),
                                    const VerticalSpacing(6, 4),
                                    const VerticalSpacing(0, 0),
                                    null,
                                  ),
                                  h2: DefaultTextBlockStyle(
                                    TextStyle(
                                      fontFamily: interFontFamily,
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                    const HorizontalSpacing(0, 0),
                                    const VerticalSpacing(4, 2),
                                    const VerticalSpacing(0, 0),
                                    null,
                                  ),
                                  inlineCode: InlineCodeStyle(
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      backgroundColor: Color(0xFF241C1A),
                                      color: Color(0xFFF2B78A),
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Apple Notes Style Bottom Formatting Toolbar
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0, left: 16.0, right: 16.0),
                child: _buildAppleFormattingToolbar(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
