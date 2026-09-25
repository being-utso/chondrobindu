import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/syllabus_node.dart';
import '../services/syllabus_parser_service.dart';
import 'app_preloader.dart';

/// Supported import modes for multi-modal ingestion
enum ImportSourceType { pdf, camera, gallery, text }

/// Type of data being imported
enum ImportTargetType { syllabus, routine }

/// Multi-Modal Intake Bottom Sheet supporting PDF, Camera/Gallery, and Raw Text Paste
class MultiModalImportSheet extends StatefulWidget {
  final ImportTargetType targetType;
  final String title;
  final String subtitle;
  final Function(String text) onProcessText;
  final Function(Uint8List imageBytes) onProcessImage;

  const MultiModalImportSheet({
    super.key,
    required this.targetType,
    required this.title,
    required this.subtitle,
    required this.onProcessText,
    required this.onProcessImage,
  });

  static Future<void> show({
    required BuildContext context,
    required ImportTargetType targetType,
    required String title,
    required String subtitle,
    required Function(String text) onProcessText,
    required Function(Uint8List imageBytes) onProcessImage,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MultiModalImportSheet(
        targetType: targetType,
        title: title,
        subtitle: subtitle,
        onProcessText: onProcessText,
        onProcessImage: onProcessImage,
      ),
    );
  }

  @override
  State<MultiModalImportSheet> createState() => _MultiModalImportSheetState();
}

class _MultiModalImportSheetState extends State<MultiModalImportSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _textController = TextEditingController();
  bool _isExtractingPdf = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickAndExtractPdf() async {
    try {
      final List<PlatformFile> selectedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (selectedFiles.isEmpty) return;

      final platformFile = selectedFiles.first;
      final String? filePath = platformFile.path;

      setState(() => _isExtractingPdf = true);

      if (filePath == null || filePath.isEmpty) {
        throw Exception('Could not access selected PDF file path.');
      }

      final List<int> bytes = await File(filePath).readAsBytes();

      final PdfDocument pdfDoc = PdfDocument(inputBytes: bytes);
      final int totalPages = pdfDoc.pages.count;
      final int endPage = totalPages > 15 ? 15 : totalPages;
      final PdfTextExtractor extractor = PdfTextExtractor(pdfDoc);
      final String extractedText = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: endPage - 1,
      );
      pdfDoc.dispose();

      setState(() => _isExtractingPdf = false);

      if (extractedText.trim().isEmpty) {
        throw Exception('No readable text content found in selected PDF. If it is a scanned document, please use the Camera / Photo tab.');
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onProcessText(extractedText);
      }
    } catch (e) {
      setState(() => _isExtractingPdf = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to read PDF: $e'),
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      if (mounted) {
        Navigator.pop(context);
        widget.onProcessImage(bytes);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to capture photo: $e'),
          ),
        );
      }
    }
  }

  void _submitPastedText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please paste some text first.'),
        ),
      );
      return;
    }
    Navigator.pop(context);
    widget.onProcessText(text);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _textController.text = data.text!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF1C1412);
    const borderColor = Color(0xFF4A3830);
    const accentColor = Color(0xFFF2B78A);
    const secondaryText = Color(0xFFABA093);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          color: secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: secondaryText, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Bar for 3 Modalities
            Container(
              height: 42,
              padding: const EdgeInsets.all(3.5),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: 0.8),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                labelColor: const Color(0xFF140F0E),
                unselectedLabelColor: secondaryText,
                labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.picture_as_pdf_rounded, size: 16),
                    text: 'PDF Document',
                  ),
                  Tab(
                    icon: Icon(Icons.camera_alt_rounded, size: 16),
                    text: 'Photo / Camera',
                  ),
                  Tab(
                    icon: Icon(Icons.content_paste_rounded, size: 16),
                    text: 'Paste Text',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tab Views
            SizedBox(
              height: 220,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: PDF Document
                  _buildPdfTab(accentColor, surfaceColor, borderColor, secondaryText),

                  // Tab 2: Photo / Camera
                  _buildCameraTab(accentColor, surfaceColor, borderColor, secondaryText),

                  // Tab 3: Paste Text
                  _buildPasteTextTab(accentColor, surfaceColor, borderColor, secondaryText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfTab(Color accentColor, Color surfaceColor, Color borderColor, Color secondaryText) {
    if (_isExtractingPdf) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppPreloader(size: 28, strokeWidth: 2.5),
            const SizedBox(height: 14),
            Text(
              'Extracting text from PDF...',
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickAndExtractPdf,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.upload_file_rounded, color: accentColor, size: 32),
              ),
              const SizedBox(height: 12),
              Text(
                'Select Syllabus / Timetable PDF',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Extracts chapter hierarchy or timetable slots locally',
                style: GoogleFonts.plusJakartaSans(
                  color: secondaryText,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraTab(Color accentColor, Color surfaceColor, Color borderColor, Color secondaryText) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _pickImage(ImageSource.camera),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.photo_camera_rounded, color: accentColor, size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Take a Photo',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Capture printed outline or routine sheet',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(color: secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => _pickImage(ImageSource.gallery),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor, width: 1.0),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_rounded, color: Color(0xFF10B981), size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'From Gallery',
                    style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select screenshot or saved timetable image',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(color: secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPasteTextTab(Color accentColor, Color surfaceColor, Color borderColor, Color secondaryText) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Paste syllabus outline, course chapters, or routine text from portal/email...',
                  hintStyle: GoogleFonts.plusJakartaSans(color: secondaryText.withValues(alpha: 0.8), fontSize: 12),
                  filled: true,
                  fillColor: surfaceColor,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: borderColor, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: accentColor, width: 1.2),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: InkWell(
                  onTap: _pasteFromClipboard,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E221E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.paste_rounded, color: accentColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Paste',
                          style: GoogleFonts.plusJakartaSans(color: accentColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 42,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: const Color(0xFF140F0E),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _submitPastedText,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: Text(
              'Process with AI',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}

/// Editable Staging and Confirmation Sheet for extracted Syllabus Chapters & Topics
class SyllabusStagingConfirmationSheet extends StatefulWidget {
  final List<SyllabusNode> extractedNodes;
  final Function(List<SyllabusNode> approvedNodes) onConfirm;

  const SyllabusStagingConfirmationSheet({
    super.key,
    required this.extractedNodes,
    required this.onConfirm,
  });

  static Future<void> show({
    required BuildContext context,
    required List<SyllabusNode> extractedNodes,
    required Function(List<SyllabusNode> approvedNodes) onConfirm,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SyllabusStagingConfirmationSheet(
        extractedNodes: extractedNodes,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  State<SyllabusStagingConfirmationSheet> createState() => _SyllabusStagingConfirmationSheetState();
}

class _StagingChapter {
  String title;
  bool isSelected;
  List<_StagingTopic> topics;

  _StagingChapter({
    required this.title,
    this.isSelected = true,
    required this.topics,
  });
}

class _StagingTopic {
  String title;
  bool isSelected;
  List<SyllabusNode> materials;

  _StagingTopic({
    required this.title,
    this.isSelected = true,
    required this.materials,
  });
}

class _SyllabusStagingConfirmationSheetState extends State<SyllabusStagingConfirmationSheet> {
  late List<_StagingChapter> _chapters;

  @override
  void initState() {
    super.initState();
    final sanitizedNodes = SyllabusParserService.sanitizeChapterNodes(widget.extractedNodes);
    _chapters = sanitizedNodes.map((ch) {
      final topicList = ch.children.map((t) {
        return _StagingTopic(
          title: t.title,
          isSelected: true,
          materials: List<SyllabusNode>.from(t.children),
        );
      }).toList();

      return _StagingChapter(
        title: ch.title,
        isSelected: true,
        topics: topicList,
      );
    }).toList();
  }

  void _editTitle(String currentTitle, Function(String newTitle) onSaved) {
    final controller = TextEditingController(text: currentTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF4A3830), width: 0.8),
        ),
        title: Text(
          'Edit Title',
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1C1412),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
            ),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                onSaved(text);
              }
              Navigator.pop(ctx);
            },
            child: Text('Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmAndImport() {
    final List<SyllabusNode> approvedNodes = [];

    for (final ch in _chapters) {
      if (!ch.isSelected) continue;

      final List<SyllabusNode> approvedTopics = [];
      for (final t in ch.topics) {
        if (!t.isSelected) continue;
        final decomposed = SyllabusParserService.decomposeTopicTitle(t.title);
        for (final title in decomposed) {
          approvedTopics.add(
            SyllabusNode(
              id: generateUniqueNodeId('topic'),
              title: title,
              isLeaf: true,
              isCompleted: false,
              children: t.materials.map((m) => m.copyWith(id: generateUniqueNodeId('item'))).toList(),
            ),
          );
        }
      }

      if (approvedTopics.isNotEmpty || ch.title.isNotEmpty) {
        approvedNodes.add(
          SyllabusNode(
            title: ch.title,
            isLeaf: false,
            children: approvedTopics,
          ),
        );
      }
    }

    if (approvedNodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please select at least one module or topic to import.'),
        ),
      );
      return;
    }

    Navigator.pop(context);
    widget.onConfirm(approvedNodes);
  }

  @override
  Widget build(BuildContext context) {
    const surfaceColor = Color(0xFF140F0E);
    const borderColor = Color(0xFF4A3830);
    const accentColor = Color(0xFFF2B78A);
    const secondaryText = Color(0xFFABA093);

    final selectedCount = _chapters.where((c) => c.isSelected).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.checklist_rounded, color: accentColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Review Syllabus Structure',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_chapters.length} chapter(s) parsed • Uncheck or edit before importing',
                    style: GoogleFonts.plusJakartaSans(color: secondaryText, fontSize: 12),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: secondaryText),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Staged Chapters List
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: chapter.isSelected ? accentColor.withValues(alpha: 0.6) : borderColor,
                      width: chapter.isSelected ? 1.0 : 0.8,
                    ),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: index == 0,
                      leading: Checkbox(
                        value: chapter.isSelected,
                        activeColor: accentColor,
                        checkColor: const Color(0xFF140F0E),
                        onChanged: (val) {
                          setState(() {
                            chapter.isSelected = val ?? false;
                            for (final t in chapter.topics) {
                              t.isSelected = chapter.isSelected;
                            }
                          });
                        },
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              chapter.title,
                              style: GoogleFonts.plusJakartaSans(
                                color: chapter.isSelected ? Colors.white : secondaryText,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, color: secondaryText, size: 16),
                            onPressed: () {
                              _editTitle(chapter.title, (newTitle) {
                                setState(() => chapter.title = newTitle);
                              });
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            onPressed: () {
                              setState(() => _chapters.removeAt(index));
                            },
                          ),
                        ],
                      ),
                      subtitle: Text(
                        '${chapter.topics.length} topics',
                        style: GoogleFonts.plusJakartaSans(color: secondaryText, fontSize: 11.5),
                      ),
                      children: [
                        const Divider(color: Color(0xFF382A24), height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Column(
                            children: chapter.topics.asMap().entries.map((entry) {
                              final tIndex = entry.key;
                              final topic = entry.value;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 8),
                                    Checkbox(
                                      value: topic.isSelected,
                                      activeColor: accentColor,
                                      checkColor: const Color(0xFF140F0E),
                                      visualDensity: VisualDensity.compact,
                                      onChanged: chapter.isSelected
                                          ? (val) {
                                              setState(() => topic.isSelected = val ?? false);
                                            }
                                          : null,
                                    ),
                                    Expanded(
                                      child: Text(
                                        topic.title,
                                        style: GoogleFonts.plusJakartaSans(
                                          color: topic.isSelected ? Colors.white70 : secondaryText.withValues(alpha: 0.5),
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded, color: secondaryText, size: 14),
                                      onPressed: () {
                                        _editTitle(topic.title, (newTitle) {
                                          setState(() => topic.title = newTitle);
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 14),
                                      onPressed: () {
                                        setState(() => chapter.topics.removeAt(tIndex));
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Confirm & Import Action
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: const Color(0xFF140F0E),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: selectedCount > 0 ? _confirmAndImport : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                'Confirm & Import ($selectedCount Chapters)',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
