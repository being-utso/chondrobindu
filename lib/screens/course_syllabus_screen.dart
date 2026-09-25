import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/routine_models.dart';
import '../models/assessment_model.dart';
import '../models/syllabus_node.dart';
import '../widgets/batch_add_materials_dialog.dart';
import '../theme/app_theme.dart';
import 'course_assessment_screen.dart';
import 'course_attendance_screen.dart';
import 'journal_screen.dart';
import '../widgets/app_preloader.dart';
import '../widgets/compact_loading_dialog.dart';
import '../widgets/multi_modal_import_sheet.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/tour_service.dart';
import '../widgets/tour_coach_mark.dart';
import '../services/syllabus_parser_service.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

export '../widgets/batch_add_materials_dialog.dart';
export 'course_attendance_screen.dart';

/// Type alias for CourseDashboardScreen and CourseDetailsScreen
typedef CourseDashboardScreen = CourseSyllabusScreen;
typedef CourseDetailsScreen = CourseSyllabusScreen;

/// Actions available when confirming section deletion
enum DeleteSectionAction {
  cancel,
  deleteAll,
  unwrapOnly,
}

/// Gemini API Key Placeholder
const String YOUR_GEMINI_API_KEY = 'GEMINI_API_KEY'; // This will be injected at runtime via environment variables in AI Studio.

/// Interactive Syllabus Screen for a University Course with n-level nested SyllabusNode hierarchy
class CourseSyllabusScreen extends ConsumerStatefulWidget {
  final String courseId;

  const CourseSyllabusScreen({super.key, required this.courseId});

  @override
  ConsumerState<CourseSyllabusScreen> createState() => _CourseSyllabusScreenState();
}

class _CourseSyllabusScreenState extends ConsumerState<CourseSyllabusScreen> {
  List<SyllabusNode>? _localNodes;
  String? _currentCourseCode;
  String? _currentCourseName;
  String? _currentCourseType;
  bool _currentUseManualAttendanceOverride = false;
  int? _currentManualAttendedClasses;
  int? _currentManualTotalClasses;
  bool _isMultiSelectMode = false;
  final Set<String> _selectedNodeIds = <String>{};
  final GlobalKey _keyPdfImport = GlobalKey();
  final GlobalKey _keyProgressTally = GlobalKey();
  final GlobalKey _keyFirstChapterMenu = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  bool _hasTriggeredTour = false;

  void _triggerSyllabusTourIfNeeded(BuildContext showcaseContext, List<SyllabusNode> allNodes) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true) || _hasTriggeredTour) return;

    triggerTourSafely(
      context: showcaseContext,
      section: TourSection.syllabus,
      keys: allNodes.isNotEmpty
          ? [_keyPdfImport, _keyProgressTally, _keyFirstChapterMenu]
          : [_keyPdfImport],
      onStarted: () => _hasTriggeredTour = true,
      onSkippedOrEmpty: () => _hasTriggeredTour = false,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleNodeSelection(String id) {
    SafeHaptics.selectionClick();
    setState(() {
      if (_selectedNodeIds.contains(id)) {
        _selectedNodeIds.remove(id);
        if (_selectedNodeIds.isEmpty) {
          _isMultiSelectMode = false;
        }
      } else {
        _selectedNodeIds.add(id);
      }
    });
  }

  void _enterMultiSelectMode(String initialId) {
    SafeHaptics.mediumImpact();
    setState(() {
      _isMultiSelectMode = true;
      _selectedNodeIds.add(initialId);
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedNodeIds.clear();
    });
  }

  void _selectAllTopics(List<SyllabusNode> allNodes) {
    final Set<String> allIds = {};
    void collectIds(List<SyllabusNode> list) {
      for (final n in list) {
        allIds.add(n.id);
        collectIds(n.children);
      }
    }
    collectIds(allNodes);
    setState(() {
      if (_selectedNodeIds.length == allIds.length) {
        _selectedNodeIds.clear();
        _isMultiSelectMode = false;
      } else {
        _selectedNodeIds.addAll(allIds);
      }
    });
  }

  void _showGroupIntoSectionDialog(BuildContext context, List<SyllabusNode> allNodes) {
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Color(0xFFF2B78A), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Group into Section / Folder',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group ${_selectedNodeIds.length} selected item(s) into a new Section / Folder:',
              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Vector Calculus, Modern Physics',
                hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final sectionTitle = titleController.text.trim();
              if (sectionTitle.isEmpty) return;
              Navigator.pop(ctx);

              final targetIds = Set<String>.from(_selectedNodeIds);
              final createdSection = SyllabusNode.groupNodesIntoSection(
                nodes: allNodes,
                targetIds: targetIds,
                sectionTitle: sectionTitle,
              );

              if (createdSection != null) {
                setState(() {
                  _selectedNodeIds.clear();
                  _isMultiSelectMode = false;
                });
                await _saveSyllabusToFirestore(allNodes);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF1E293B),
                      behavior: SnackBarBehavior.floating,
                      content: Text('Grouped ${targetIds.length} topic(s) into "$sectionTitle".'),
                    ),
                  );
                }
              }
            },
            child: const Text('Group Topics', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// TASK 2: Dialog to Edit Course Code and Course Name, persisting both to Firestore
  void _showEditCourseDialog(BuildContext context, String currentCode, String currentName) {
    final codeController = TextEditingController(text: currentCode);
    final nameController = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.edit_rounded, color: Color(0xFFF2B78A), size: 20),
            SizedBox(width: 8),
            Text('Edit Course Info', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: codeController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Course Code',
                labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                hintText: 'e.g. EEE 101',
                hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Course Name',
                labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
                hintText: 'e.g. Electric Circuits',
                hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newCode = codeController.text.trim();
              final newName = nameController.text.trim();
              if (newCode.isEmpty && newName.isEmpty) return;

              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .collection('courses')
                      .doc(widget.courseId)
                      .update({
                    'courseCode': newCode.isNotEmpty ? newCode : 'COURSE',
                    'courseName': newName.isNotEmpty ? newName : 'Tap to edit name',
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  setState(() {
                    if (newCode.isNotEmpty) _currentCourseCode = newCode;
                    if (newName.isNotEmpty) _currentCourseName = newName;
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text('Course updated: $newCode${newName.isNotEmpty ? ' • $newName' : ''}'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFFEF4444),
                        content: Text('Failed to update course: $e'),
                      ),
                    );
                  }
                }
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Helper parser converting dynamic Firestore syllabusData to List<SyllabusNode>
  List<SyllabusNode> _parseSyllabusData(dynamic rawData) {
    if (rawData == null) return [];
    List<dynamic> rawList = [];

    if (rawData is List) {
      rawList = rawData;
    } else if (rawData is Map) {
      if (rawData['nodes'] is List) {
        rawList = rawData['nodes'] as List;
      } else if (rawData['chapters'] is List) {
        rawList = rawData['chapters'] as List;
      }
    }

    final parsed = rawList
        .whereType<Map>()
        .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
        .toList();

    // If an existing syllabus was previously wrapped in an artificial root container "Section 1",
    // flatten it so top-level cards directly represent the actual chapters/modules.
    if (parsed.length == 1 &&
        (parsed.first.title.toLowerCase() == 'section 1' ||
            parsed.first.title.toLowerCase() == 'section 1:' ||
            parsed.first.title.toLowerCase().startsWith('section 1')) &&
        !parsed.first.isLeaf &&
        parsed.first.children.isNotEmpty &&
        parsed.first.children.any((child) => !child.isLeaf)) {
      return parsed.first.children;
    }

    return parsed;
  }

  /// Saves the complete SyllabusNode tree to Firestore
  Future<void> _saveSyllabusToFirestore(List<SyllabusNode> nodes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    setState(() {
      _localNodes = nodes;
    });

    final serializedData = nodes.map((n) => n.toMap()).toList();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(widget.courseId)
          .update({
        'syllabusData': serializedData,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Failed to sync syllabus: $e'),
          ),
        );
      }
    }
  }

  /// Generates syllabus JSON with dynamic failover across [kGeminiModelPriorityPool]
  Future<String> _generateSyllabusWithRetryAndFallback({
    String? fullPrompt,
    Uint8List? imageBytes,
  }) async {
    return SyllabusParserService.extractSyllabusWithFailover(
      promptText: fullPrompt,
      imageBytes: imageBytes,
      apiKey: YOUR_GEMINI_API_KEY,
    );
  }

  List<SyllabusNode> _parseSyllabusJsonResponse(String rawResponseText) {
    return SyllabusParserService.parseSyllabusJsonResponse(rawResponseText);
  }

  /// Multi-Modal AI Smart Import Entrypoint
  Future<void> _startSmartImportFlow(List<SyllabusNode> existingNodes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Please sign in to import syllabus.'),
        ),
      );
      return;
    }

    MultiModalImportSheet.show(
      context: context,
      targetType: ImportTargetType.syllabus,
      title: 'Import Course Syllabus (AI)',
      subtitle: 'Upload PDF outline, capture syllabus photo, or paste text',
      onProcessText: (text) => _processSyllabusText(text, existingNodes),
      onProcessImage: (bytes) => _processSyllabusImage(bytes, existingNodes),
    );
  }

  Future<void> _processSyllabusText(String rawText, List<SyllabusNode> existingNodes) async {
    final cleanedText = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');

    if (cleanedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Provided text is empty.')),
      );
      return;
    }

    final safeCleanedText = cleanedText.length > 50000
        ? cleanedText.substring(0, 50000)
        : cleanedText;

    final promptText = SyllabusParserService.buildExtractionPrompt(safeCleanedText);

    await _executeSyllabusExtraction(existingNodes, promptText: promptText);
  }

  Future<void> _processSyllabusImage(Uint8List imageBytes, List<SyllabusNode> existingNodes) async {
    await _executeSyllabusExtraction(existingNodes, imageBytes: imageBytes);
  }

  Future<void> _executeSyllabusExtraction(
    List<SyllabusNode> existingNodes, {
    String? promptText,
    Uint8List? imageBytes,
  }) async {
    if (!mounted) return;

    CompactLoadingDialog.showProgressive(
      context: context,
    );

    try {
      final rawResponseText = await _generateSyllabusWithRetryAndFallback(
        fullPrompt: promptText,
        imageBytes: imageBytes,
      );

      if (rawResponseText.trim().isEmpty) {
        throw Exception('Empty response from AI model.');
      }

      final chapterNodes = _parseSyllabusJsonResponse(rawResponseText);

      if (chapterNodes.isEmpty) {
        throw Exception('No sections or topics could be parsed from the response.');
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss preloader

        // Present editable Staging & Confirmation Preview Sheet
        SyllabusStagingConfirmationSheet.show(
          context: context,
          extractedNodes: chapterNodes,
          onConfirm: (approvedNodes) async {
            final importResult = SyllabusNode.appendImportedNodes(
              existingNodes: existingNodes,
              importedNodes: approvedNodes,
            );

            await _saveSyllabusToFirestore(importResult.nodes);

            if (mounted) {
              setState(() {
                _localNodes = importResult.nodes;
              });
              final successMsg = approvedNodes.length == 1
                  ? 'Successfully imported "${approvedNodes.first.title}"!'
                  : 'Successfully imported ${approvedNodes.length} chapters into syllabus!';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  content: Text(
                    successMsg,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            }
          },
        );
      }
    } catch (e, s) {
      debugPrint('CRITICAL AI ERROR: $e');
      debugPrint('STACK TRACE: $s');
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss preloader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Text(
              'Smart Import failed: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  /// TASK 2: Add Sub-section (Folder) Dialog
  void _showAddSectionDialog(BuildContext context, {SyllabusNode? parentNode, required List<SyllabusNode> allNodes}) {
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          parentNode != null ? 'Add Sub-section to "${parentNode.title}"' : 'Add New Chapter / Section',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: TextField(
          controller: titleController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: parentNode != null ? 'e.g. Sub-module A, Part 1' : 'e.g. Ordinary Differential Equations, Complex Variable',
            hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
            filled: true,
            fillColor: const Color(0xFF170F0D),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF2B78A)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;

              final newNode = SyllabusNode(
                title: text,
                isLeaf: false,
                children: [],
                parentId: parentNode?.id,
              );

              setState(() {
                if (parentNode != null) {
                  parentNode.children.add(newNode);
                } else {
                  allNodes.add(newNode);
                }
              });

              await _saveSyllabusToFirestore(allNodes);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Create Section', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// TASK 2: Normalizes a user-entered URL, automatically prepending https:// if HTTP protocol is missing
  String? _normalizeUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  /// TASK 2: Add Topic (Checkable Leaf) Dialog
  void _showAddTopicDialog(BuildContext context, {required SyllabusNode parentNode, required List<SyllabusNode> allNodes}) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Topic to "${parentNode.title}"',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. Karnaugh Map Minimization',
                hintStyle: TextStyle(color: Colors.blueGrey.shade500, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Resource URL (e.g. Google Drive link - optional)',
                hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFF2B78A), size: 18),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;
              final normalizedUrl = _normalizeUrl(urlController.text);

              final leafNode = SyllabusNode(
                title: text,
                isLeaf: true,
                isCompleted: false,
                resourceUrl: normalizedUrl,
                parentId: parentNode.id,
              );

              setState(() {
                parentNode.children.add(leafNode);
                for (final r in allNodes) {
                  r.updateHierarchicalCompletion();
                }
              });
              await _saveSyllabusToFirestore(allNodes);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Add Topic', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// TASK 1 & 2: Add Material / Study Sub-section Modal for Topic Nodes with URL Linking
  void _showAddMaterialModal(BuildContext context, SyllabusNode parentNode, List<SyllabusNode> allNodes) {
    const categories = [
      {'title': 'Class Note', 'icon': Icons.edit_note_rounded, 'color': Color(0xFFABA093)},
      {'title': 'Lecture Sheet', 'icon': Icons.description_outlined, 'color': Color(0xFF10B981)},
      {'title': 'Ref Book', 'icon': Icons.menu_book_rounded, 'color': Color(0xFFF59E0B)},
      {'title': 'Term Final Question', 'icon': Icons.quiz_outlined, 'color': Color(0xFFA855F7)},
      {'title': 'Custom', 'icon': Icons.add_circle_outline_rounded, 'color': Colors.white70},
    ];

    String selectedCategory = 'Lecture Sheet';
    final titleController = TextEditingController(text: 'Lecture Sheet');
    final urlController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF241C1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.post_add_rounded, color: Color(0xFFF2B78A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add Material / Sub-section',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'For: "${parentNode.title}"',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 14),

                  // Category Selector Chips
                  const Text('SELECT CATEGORY', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((cat) {
                      final cTitle = cat['title'] as String;
                      final icon = cat['icon'] as IconData;
                      final isSelected = selectedCategory == cTitle;

                      return ChoiceChip(
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        avatar: Icon(
                          icon,
                          size: 16,
                          color: isSelected ? const Color(0xFF140F0E) : Colors.white70,
                        ),
                        label: Text(
                          cTitle,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF140F0E) : Colors.white,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: const Color(0xFFF2B78A),
                        backgroundColor: const Color(0xFF170F0D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF4A3830),
                          ),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setModalState(() {
                              selectedCategory = cTitle;
                              if (cTitle != 'Custom') {
                                titleController.text = cTitle;
                              } else {
                                titleController.text = '';
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Material Title Field
                  const Text('MATERIAL TITLE', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. Lecture Sheet 3, Ref Book (Sedra Smith)',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Resource URL Field (TASK 2)
                  Row(
                    children: [
                      const Text('RESOURCE URL / DRIVE LINK', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text('(Optional)', style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: urlController,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                    decoration: InputDecoration(
                      hintText: 'https://drive.google.com/... or web doc',
                      hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                      prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFF2B78A), size: 18),
                      filled: true,
                      fillColor: const Color(0xFF170F0D),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Attach Google Drive or external resources to save cloud database storage.',
                    style: TextStyle(color: Colors.blueGrey.shade500, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 20),

                  // Add Action Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: const Color(0xFF140F0E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        final title = titleController.text.trim();
                        if (title.isEmpty) return;
                        final normalizedUrl = _normalizeUrl(urlController.text);

                        final newNode = SyllabusNode(
                          title: title,
                          isLeaf: true,
                          isCompleted: false,
                          resourceUrl: normalizedUrl,
                          parentId: parentNode.id,
                        );

                        setState(() {
                          parentNode.children.add(newNode);
                          for (final r in allNodes) {
                            r.updateHierarchicalCompletion();
                          }
                        });
                        await _saveSyllabusToFirestore(allNodes);
                        if (context.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Add Material Sub-section', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// TASK 1 & TASK 2: Multi-select dialog allowing the user to select multiple topic items within a section
  /// and choose one or more categories ("Class Note", "Lecture Sheet", "Ref Book", "Term Final Question", or "+ Custom")
  /// to attach to all selected topics at once.
  void _showBatchAddMaterialsDialog(
    BuildContext context,
    SyllabusNode sectionNode,
    List<SyllabusNode> allNodes,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => BatchAddMaterialsDialog(
        sectionNode: sectionNode,
        allNodes: allNodes,
        onSave: (updated) => _saveSyllabusToFirestore(updated),
      ),
    );
  }

  /// Rename Node & Resource Link Dialog
  void _showRenameDialog(BuildContext context, SyllabusNode node, List<SyllabusNode> allNodes) {
    final titleController = TextEditingController(text: node.title);
    final urlController = TextEditingController(text: node.resourceUrl ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Node Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Title', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Resource URL (Drive/Web link)', style: TextStyle(color: Color(0xFFF2B78A), fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://drive.google.com/...',
                hintStyle: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFFF2B78A), size: 18),
                filled: true,
                fillColor: const Color(0xFF170F0D),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF140F0E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final text = titleController.text.trim();
              if (text.isEmpty) return;
              final normalizedUrl = _normalizeUrl(urlController.text);

              setState(() {
                node.title = text;
                node.resourceUrl = normalizedUrl;
              });
              await _saveSyllabusToFirestore(allNodes);
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// TASK 3: Launches an external resource URL safely with error handling and canLaunchUrl check
  Future<void> _launchResourceUrl(BuildContext context, String urlString) async {
    final normalized = _normalizeUrl(urlString);
    if (normalized == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Invalid or empty URL link.'),
          ),
        );
      }
      return;
    }

    final Uri? uri = Uri.tryParse(normalized);
    if (uri == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFEF4444),
            content: Text('Invalid URL format.'),
          ),
        );
      }
      return;
    }

    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!await launchUrl(uri, mode: LaunchMode.platformDefault)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFEF4444),
                content: Text('Could not open link: $normalized'),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Error launching link: $e'),
          ),
        );
      }
    }
  }

  void _deleteNode(SyllabusNode node, List<SyllabusNode> allNodes) async {
    if (node.isLeaf && node.children.isEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF241C1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Delete Topic?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to delete "${node.title}"?',
            style: const TextStyle(color: Colors.blueGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() {
          SyllabusNode.removeNode(nodes: allNodes, targetId: node.id);
          for (final r in allNodes) {
            r.updateHierarchicalCompletion();
          }
        });
        await _saveSyllabusToFirestore(allNodes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E293B),
              behavior: SnackBarBehavior.floating,
              content: Text('Deleted "${node.title}".'),
            ),
          );
        }
      }
      return;
    }

    // Section deletion with Unwrapping / Promoting choices
    final action = await showDialog<DeleteSectionAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241C1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Delete Section',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'How would you like to delete "${node.title}"?',
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            if (node.children.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'This section contains ${node.children.length} nested item(s).',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 18),
            // Choice 1: Remove Section Only (Keep Topics)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFF2B78A), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => Navigator.pop(ctx, DeleteSectionAction.unwrapOnly),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Remove Section Only (Keep Topics)',
                    style: TextStyle(
                      color: Color(0xFFF2B78A),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Promotes nested topics up one level',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Choice 2: Delete Section & All Contents
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.centerLeft,
              ),
              onPressed: () => Navigator.pop(ctx, DeleteSectionAction.deleteAll),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delete Section & All Contents',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Destroys section and all topics underneath it',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, DeleteSectionAction.cancel),
            child: const Text('Cancel', style: TextStyle(color: Colors.blueGrey)),
          ),
        ],
      ),
    );

    if (action == DeleteSectionAction.unwrapOnly) {
      setState(() {
        SyllabusNode.unwrapNode(nodes: allNodes, targetId: node.id);
        for (final r in allNodes) {
          r.updateHierarchicalCompletion();
        }
      });
      await _saveSyllabusToFirestore(allNodes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            content: Text('Removed "${node.title}" and promoted nested topics.'),
          ),
        );
      }
    } else if (action == DeleteSectionAction.deleteAll) {
      setState(() {
        SyllabusNode.removeNode(nodes: allNodes, targetId: node.id);
        for (final r in allNodes) {
          r.updateHierarchicalCompletion();
        }
      });
      await _saveSyllabusToFirestore(allNodes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
            content: Text('Deleted "${node.title}" and all its contents.'),
          ),
        );
      }
    }
  }

  void _navigateToAssessment() {
    if (_currentCourseType == null || _currentCourseType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF64748B),
          behavior: SnackBarBehavior.floating,
          content: Text('Still loading course data...'),
        ),
      );
      return;
    }

    SafeHaptics.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CourseAssessmentScreen(
          courseId: widget.courseId,
          courseCode: _currentCourseCode ?? '',
          courseType: _currentCourseType!,
        ),
      ),
    );
  }

  /// Recursive Widget Renderer for SyllabusNode Tree with Dynamic Auto-Conversion
  Widget _buildNodeTree(SyllabusNode node, int depth, List<SyllabusNode> allNodes, {GlobalKey? optionsMenuKey}) {
    final bool isFolder = node.children.isNotEmpty;

    if (isFolder) {
      return _SyllabusFolderTile(
        key: ValueKey(node.id),
        node: node,
        depth: depth,
        allNodes: allNodes,
        optionsMenuKey: optionsMenuKey,
        isMultiSelectMode: _isMultiSelectMode,
        isSelected: _selectedNodeIds.contains(node.id),
        onToggleSelection: () => _toggleNodeSelection(node.id),
        onLongPress: () => _enterMultiSelectMode(node.id),
        onAddMaterial: () => _showAddMaterialModal(context, node, allNodes),
        onAddTopic: () => _showAddTopicDialog(context, parentNode: node, allNodes: allNodes),
        onAddSection: () => _showAddSectionDialog(context, parentNode: node, allNodes: allNodes),
        onBatchAdd: () => _showBatchAddMaterialsDialog(context, node, allNodes),
        onRename: () => _showRenameDialog(context, node, allNodes),
        onDelete: () => _deleteNode(node, allNodes),
        onOpenUrl: (url) => _launchResourceUrl(context, url),
        buildChild: (child, childDepth) => _buildNodeTree(child, childDepth, allNodes),
      );
    }

    return _buildCheckableTopicRow(node, depth, allNodes, optionsMenuKey: optionsMenuKey);
  }

  /// Standard Checkable Topic Row with a regular checkbox
  Widget _buildCheckableTopicRow(SyllabusNode node, int depth, List<SyllabusNode> allNodes, {GlobalKey? optionsMenuKey}) {
    const accentColor = Color(0xFFF2B78A);
    final isSelected = _selectedNodeIds.contains(node.id);
    final hasUrl = node.resourceUrl != null && node.resourceUrl!.trim().isNotEmpty;

    return GestureDetector(
      onLongPress: () => _enterMultiSelectMode(node.id),
      child: Container(
        margin: EdgeInsets.only(
          left: (depth * 12.0).clamp(0.0, 36.0),
          bottom: 4,
          right: 4,
        ),
        decoration: BoxDecoration(
          color: _isMultiSelectMode && isSelected
              ? accentColor.withValues(alpha: 0.12)
              : (depth == 0 ? const Color(0xFF241C1A) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
          border: _isMultiSelectMode && isSelected
              ? Border.all(color: accentColor, width: 1.5)
              : (depth == 0 ? Border.all(color: const Color(0xFF4A3830)) : null),
        ),
        child: CheckboxListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          activeColor: accentColor,
          checkColor: const Color(0xFF140F0E),
          controlAffinity: ListTileControlAffinity.leading,
          value: _isMultiSelectMode ? isSelected : node.isCompleted,
          onChanged: (bool? val) {
            if (_isMultiSelectMode) {
              _toggleNodeSelection(node.id);
            } else if (val != null) {
              setState(() {
                node.isCompleted = val;
                for (final root in allNodes) {
                  root.updateHierarchicalCompletion();
                }
              });
              _saveSyllabusToFirestore(allNodes);
            }
          },
          title: Text(
            node.title,
            style: TextStyle(
              color: node.isCompleted ? Colors.blueGrey.shade400 : Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              decoration: node.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
              decorationColor: Colors.blueGrey.shade500,
            ),
          ),
          subtitle: hasUrl
              ? InkWell(
                  onTap: () => _launchResourceUrl(context, node.resourceUrl!),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_rounded, size: 13, color: Color(0xFFF2B78A)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          node.resourceUrl!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF2B78A),
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          secondary: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasUrl)
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFFF2B78A), size: 18),
                  tooltip: 'Open Attached Link in Browser',
                  onPressed: () => _launchResourceUrl(context, node.resourceUrl!),
                ),
              IconButton(
                icon: const Icon(Icons.post_add_rounded, color: accentColor, size: 20),
                tooltip: 'Add Material / Sub-section',
                onPressed: () => _showAddMaterialModal(context, node, allNodes),
              ),
              () {
                final popup = PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: Colors.blueGrey.shade400, size: 18),
                  color: const Color(0xFF241C1A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) async {
                    if (val == 'add_material') {
                      _showAddMaterialModal(context, node, allNodes);
                    } else if (val == 'convert_to_folder') {
                      _showAddMaterialModal(context, node, allNodes);
                    } else if (val == 'rename') {
                      _showRenameDialog(context, node, allNodes);
                    } else if (val == 'delete') {
                      _deleteNode(node, allNodes);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'add_material',
                      child: Row(
                        children: [
                          Icon(Icons.post_add_rounded, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Add Material Sub-section', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'convert_to_folder',
                      child: Row(
                        children: [
                          Icon(Icons.folder_outlined, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Convert to Folder / Section', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Edit / Rename', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                );

                if (optionsMenuKey != null) {
                  return TourShowcaseItem(
                    step: TourStep(
                      key: optionsMenuKey,
                      title: 'Batch Materials & Grouping',
                      description: 'Attach lecture sheets across multiple topics at once, or long-press any item to group topics into sections.',
                    ),
                    stepIndex: 3,
                    totalSteps: 3,
                    section: TourSection.syllabus,
                    child: popup,
                  );
                }
                return popup;
              }(),
            ],
          ),
        ),
      ),
    );
  }

  /// TASK 4: Real-time stream of logged classes for this course
  Widget _buildCourseAttendanceBanner(String uid, Color cardColor, Color accentColor) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance_records')
          .snapshots(),
      builder: (context, attSnap) {
        final attDocs = attSnap.data?.docs ?? [];
        final allRecords = attDocs.map((d) => AttendanceRecord.fromMap(d.data(), defaultId: d.id)).toList();
        final records = allRecords.where((rec) => RoutineCourseSyncService.recordMatchesCourse(
          record: rec,
          courseId: widget.courseId,
          courseCode: _currentCourseCode ?? '',
          courseName: _currentCourseName,
        )).toList();
        final rawCalendarStats = AttendanceStats.fromRecords(records);
        final attStats = RoutineCourseSyncService.computeCourseAttendance(
          courseRecords: records,
          useManualAttendanceOverride: _currentUseManualAttendanceOverride,
          manualAttendedClasses: _currentManualAttendedClasses,
          manualTotalClasses: _currentManualTotalClasses,
        );
        final totalLogged = attStats.totalClasses;
        final totalAttended = attStats.attended;
        final double pct = attStats.percentage;
        final isSafe = pct >= 75.0;
        final statusColor = totalLogged == 0
            ? const Color(0xFF94A3B8)
            : (isSafe ? const Color(0xFF10B981) : const Color(0xFFEF4444));

        return buildGlassCard(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    SafeHaptics.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CourseAttendanceScreen(
                          courseId: widget.courseId,
                          courseCode: _currentCourseCode ?? '',
                          courseName: _currentCourseName,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.event_available_rounded, color: statusColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$totalLogged Classes ${_currentUseManualAttendanceOverride ? '(Manual Tally)' : 'Recorded'}',
                              style: AppTypography.cardTitle.copyWith(fontSize: 13.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _currentUseManualAttendanceOverride
                                  ? 'Attended: $totalAttended | Missed: ${attStats.missed}'
                                  : 'Attended: $totalAttended | Missed: ${rawCalendarStats.missed}${rawCalendarStats.canceled > 0 ? ' | Canceled: ${rawCalendarStats.canceled}' : ''}',
                              style: AppTypography.subtext,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      SafeHaptics.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CourseAttendanceScreen(
                            courseId: widget.courseId,
                            courseCode: _currentCourseCode ?? '',
                            courseName: _currentCourseName,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Attendance',
                            style: AppTypography.geist(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      totalLogged == 0 ? 'No Data' : '${pct.toStringAsFixed(1)}%',
                      style: AppTypography.attendanceCount.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
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

  Widget _buildCourseAssessmentsPreviewBanner(
    String uid,
    Map<String, dynamic>? courseData,
    Color cardColor,
    Color accentColor,
  ) {
    final rawAss = courseData?['assessments'];
    final assessments = Assessment.fromRawListOrMap(rawAss, defaultCourseId: widget.courseId);

    if (assessments.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF10B981), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Assessments & Topics',
                    style: TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              InkWell(
                onTap: _navigateToAssessment,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        'Details (${assessments.length})',
                        style: const TextStyle(color: Color(0xFFF2B78A), fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFF2B78A), size: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...assessments.take(3).map((ass) {
            final hasTopic = ass.syllabusSummary != null && ass.syllabusSummary!.trim().isNotEmpty;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF170F0D),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4A3830)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        ass.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${ass.obtainedMarks?.toStringAsFixed(1) ?? "--"} / ${ass.totalMarks.toStringAsFixed(1)} (${ass.weightage.toStringAsFixed(0)}%)',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                      ),
                    ],
                  ),
                  if (hasTopic) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFF2B78A).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book_rounded, color: Color(0xFFF2B78A), size: 11),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Topic: ${ass.syllabusSummary!.trim()}',
                              style: const TextStyle(
                                color: Color(0xFFF2B78A),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF241C1A);
    const accentColor = Color(0xFFF2B78A);

    final uid = FirebaseAuth.instance.currentUser?.uid;

    return ShowCaseWidget(
      enableAutoScroll: true,
      scrollDuration: const Duration(milliseconds: 300),
      blurValue: 2.0,
      onFinish: () {
        TourService().markTourSeen(TourSection.syllabus);
      },
      onComplete: (index, key) {
        SafeHaptics.selectionClick();
      },
      onStart: (index, key) {
        final ctx = key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: 0.5,
          );
        }
      },
      builder: (showcaseContext) {
        return Scaffold(
            backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: _isMultiSelectMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                onPressed: _exitMultiSelectMode,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
        title: _isMultiSelectMode
            ? Text(
                '${_selectedNodeIds.length} Selected',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentCourseCode != null && _currentCourseCode!.trim().isNotEmpty
                        ? _currentCourseCode!.trim()
                        : 'Course',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  if (_currentCourseName != null &&
                      _currentCourseName!.trim().isNotEmpty &&
                      _currentCourseName != _currentCourseCode)
                    Text(
                      _currentCourseName!.trim(),
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, fontWeight: FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
        actions: [
          if (_isMultiSelectMode)
            TextButton(
              onPressed: () => _selectAllTopics(_localNodes ?? []),
              child: Text(
                _selectedNodeIds.isNotEmpty && _selectedNodeIds.length == (_localNodes?.length ?? 0)
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rounded, color: accentColor, size: 22),
              tooltip: 'Select Topics',
              onPressed: () => setState(() => _isMultiSelectMode = true),
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
              tooltip: 'Edit Course Info',
              onPressed: () => _showEditCourseDialog(
                context,
                _currentCourseCode ?? '',
                _currentCourseName ?? '',
              ),
            ),
            IconButton(
              icon: const Icon(Icons.analytics_outlined, color: accentColor, size: 22),
              tooltip: 'Marks & Assessment',
              onPressed: _navigateToAssessment,
            ),
            IconButton(
              icon: const Icon(Icons.auto_stories_rounded, color: accentColor, size: 21),
              tooltip: 'Course Journal & Notes',
              onPressed: () {
                SafeHaptics.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => JournalScreen(
                      initialCourseFilter: _currentCourseCode,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
      bottomNavigationBar: _isMultiSelectMode && _selectedNodeIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_selectedNodeIds.length} selected',
                        style: const TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: const Color(0xFF140F0E),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                      label: const Text(
                        'Group into Section / Folder',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: () => _showGroupIntoSectionDialog(context, _localNodes ?? []),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: uid == null || uid.isEmpty
            ? const Center(
                child: Text('User authentication required.', style: TextStyle(color: Colors.white)),
              )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('courses')
                    .doc(widget.courseId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && _localNodes == null) {
                    return const Center(child: AppPreloader(size: 44));
                  }

                  final data = snapshot.data?.data();
                  if (data != null) {
                    _currentCourseCode = data['courseCode'] as String?;
                    _currentCourseName = data['courseName'] as String?;
                    _currentCourseType = data['courseType'] as String? ?? 'Theory';
                    _currentUseManualAttendanceOverride = data['useManualAttendanceOverride'] as bool? ?? false;
                    _currentManualAttendedClasses = (data['manualAttendedClasses'] as num?)?.toInt();
                    _currentManualTotalClasses = (data['manualTotalClasses'] as num?)?.toInt();
                  }

                  final allNodes = _localNodes ?? _parseSyllabusData(data?['syllabusData']);
                  _localNodes ??= allNodes;

                  int totalTopics = 0;
                  int completedTopics = 0;
                  for (final node in allNodes) {
                    totalTopics += node.totalLeafCount;
                    completedTopics += node.completedLeafCount;
                  }

                  final double completionRatio = totalTopics > 0 ? (completedTopics / totalTopics) : 0.0;
                  final int completionPercentage = (completionRatio * 100).round();

                  _triggerSyllabusTourIfNeeded(showcaseContext, allNodes);

                  if (allNodes.isEmpty) {
                    return CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCourseAttendanceBanner(uid, cardColor, accentColor),
                              _buildCourseAssessmentsPreviewBanner(uid, data, cardColor, accentColor),
                              Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 20),
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: cardColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                                      ),
                                      child: const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 56,
                                        color: accentColor,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    const Text(
                                      'No Syllabus Data Found',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Import your syllabus via PDF using AI or create sections and topics manually.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.blueGrey.shade300,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 28),
                                    TourShowcaseItem(
                                      step: TourStep(
                                        key: _keyPdfImport,
                                        title: 'Smart Syllabus Ingestion',
                                        description: 'Upload a course outline or syllabus PDF to automatically extract chapters and topics with Gemini AI.',
                                      ),
                                      stepIndex: 1,
                                      totalSteps: 1,
                                      section: TourSection.syllabus,
                                      child: SizedBox(
                                        width: double.infinity,
                                        height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: accentColor,
                                            foregroundColor: const Color(0xFF140F0E),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                          ),
                                          onPressed: () => _startSmartImportFlow(allNodes),
                                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                                          label: const Text(
                                            'Smart Import via PDF',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 46,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: accentColor,
                                          side: BorderSide(color: accentColor.withValues(alpha: 0.5)),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: () => _showAddSectionDialog(context, allNodes: allNodes),
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        label: const Text(
                                          '+ New Section',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 40),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TASK 4: Real-time Total Logged Classes Counter at top of Course Dashboard
                            _buildCourseAttendanceBanner(uid, cardColor, accentColor),

                            // TASK 2: Course Details Assessments & Topics Preview
                            _buildCourseAssessmentsPreviewBanner(uid, data, cardColor, accentColor),

                            // Header Progress & Action Bar
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TourShowcaseItem(
                                    step: TourStep(
                                      key: _keyProgressTally,
                                      title: 'Live Progress Tally',
                                      description: 'Tracks completed topics and sub-materials across all nested chapters in real time.',
                                    ),
                                    stepIndex: 2,
                                    totalSteps: 3,
                                    section: TourSection.syllabus,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Course Progress',
                                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              '$completionPercentage%',
                                              style: const TextStyle(color: accentColor, fontSize: 18, fontWeight: FontWeight.w900),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: LinearProgressIndicator(
                                            value: completionRatio,
                                            minHeight: 8,
                                            backgroundColor: const Color(0xFF4A3830),
                                            valueColor: const AlwaysStoppedAnimation<Color>(accentColor),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '$completedTopics of $totalTopics Topics Completed',
                                              style: TextStyle(color: Colors.blueGrey.shade300, fontSize: 12, fontWeight: FontWeight.w500),
                                            ),
                                            Text(
                                              '${allNodes.length} Sections',
                                              style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TourShowcaseItem(
                                          step: TourStep(
                                            key: _keyPdfImport,
                                            title: 'Smart Syllabus Ingestion',
                                            description: 'Upload a course outline or syllabus PDF to automatically extract chapters and topics with Gemini AI.',
                                          ),
                                          stepIndex: 1,
                                          totalSteps: 3,
                                          section: TourSection.syllabus,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: accentColor,
                                              side: const BorderSide(color: Color(0xFFF2B78A)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                            ),
                                            onPressed: () => _startSmartImportFlow(allNodes),
                                            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                                            label: const Text('Import PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFF2B78A),
                                            foregroundColor: const Color(0xFF140F0E),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                          ),
                                          onPressed: () => _showAddSectionDialog(context, allNodes: allNodes),
                                          icon: const Icon(Icons.add_rounded, size: 18),
                                          label: const Text('+ New Section', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Tree SliverList
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == allNodes.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: accentColor,
                                        side: BorderSide(color: accentColor.withValues(alpha: 0.5), width: 1.2),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      ),
                                      onPressed: () => _showAddSectionDialog(context, allNodes: allNodes),
                                      icon: const Icon(Icons.add_rounded, size: 18),
                                      label: const Text(
                                        '+ New Section',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return _buildNodeTree(
                                allNodes[index],
                                0,
                                allNodes,
                                optionsMenuKey: index == 0 ? _keyFirstChapterMenu : null,
                              );
                            },
                            childCount: allNodes.length + 1,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  },
);
  }
}

/// Expandable folder/group container widget for nodes with nested children
class _SyllabusFolderTile extends StatefulWidget {
  final SyllabusNode node;
  final int depth;
  final List<SyllabusNode> allNodes;
  final bool isMultiSelectMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onLongPress;
  final VoidCallback onAddMaterial;
  final VoidCallback onAddTopic;
  final VoidCallback onAddSection;
  final VoidCallback onBatchAdd;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final void Function(String url) onOpenUrl;
  final Widget Function(SyllabusNode child, int depth) buildChild;
  final GlobalKey? optionsMenuKey;

  const _SyllabusFolderTile({
    super.key,
    required this.node,
    required this.depth,
    required this.allNodes,
    this.optionsMenuKey,
    required this.isMultiSelectMode,
    required this.isSelected,
    required this.onToggleSelection,
    required this.onLongPress,
    required this.onAddMaterial,
    required this.onAddTopic,
    required this.onAddSection,
    required this.onBatchAdd,
    required this.onRename,
    required this.onDelete,
    required this.onOpenUrl,
    required this.buildChild,
  });

  @override
  State<_SyllabusFolderTile> createState() => _SyllabusFolderTileState();
}

class _SyllabusFolderTileState extends State<_SyllabusFolderTile> {
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFFF2B78A);
    const cardColor = Color(0xFF241C1A);
    final node = widget.node;
    final depth = widget.depth;
    final isSelected = widget.isSelected;
    final hasUrl = node.resourceUrl != null && node.resourceUrl!.trim().isNotEmpty;

    final completed = node.children.fold<int>(0, (acc, c) => acc + c.completedLeafCount);
    final total = node.children.fold<int>(0, (acc, c) => acc + c.totalLeafCount);

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
        margin: EdgeInsets.only(
          left: (depth * 12.0).clamp(0.0, 36.0),
          bottom: depth == 0 ? 8 : 6,
          right: 4,
        ),
        decoration: BoxDecoration(
          color: widget.isMultiSelectMode && isSelected
              ? accentColor.withValues(alpha: 0.12)
              : (depth == 0 ? cardColor : const Color(0xFF1C1412)),
          borderRadius: BorderRadius.circular(depth == 0 ? 14 : 12),
          border: Border.all(
            color: widget.isMultiSelectMode && isSelected
                ? accentColor
                : (depth == 0 ? const Color(0xFF4A3830) : const Color(0xFF382A24)),
            width: widget.isMultiSelectMode && isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            onExpansionChanged: (expanded) {
              setState(() {
                _isExpanded = expanded;
              });
            },
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: widget.isMultiSelectMode
                ? Checkbox(
                    value: isSelected,
                    activeColor: accentColor,
                    checkColor: const Color(0xFF140F0E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    onChanged: (_) => widget.onToggleSelection(),
                  )
                : Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.folder_outlined, color: accentColor, size: 20),
                  ),
            title: Text(
              node.title,
              style: TextStyle(
                color: Colors.white,
                fontSize: depth == 0 ? 15 : 13.5,
                fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  '$completed / $total completed',
                  style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11.5),
                ),
                if (hasUrl) ...[
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => widget.onOpenUrl(node.resourceUrl!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded, size: 12, color: Color(0xFFF2B78A)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            node.resourceUrl!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF2B78A),
                              fontSize: 10.5,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUrl)
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFFF2B78A), size: 18),
                    tooltip: 'Open Attached Link in Browser',
                    onPressed: () => widget.onOpenUrl(node.resourceUrl!),
                  ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.add_circle_outline_rounded, color: accentColor, size: 20),
                  tooltip: 'Add sub-items',
                  color: const Color(0xFF241C1A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (val) {
                    if (val == 'add_section') {
                      widget.onAddSection();
                    } else if (val == 'add_topic') {
                      widget.onAddTopic();
                    } else if (val == 'add_material') {
                      widget.onAddMaterial();
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'add_material',
                      child: Row(
                        children: [
                          Icon(Icons.post_add_rounded, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Add Material Sub-section', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_topic',
                      child: Row(
                        children: [
                          Icon(Icons.check_box_outlined, size: 16, color: Color(0xFF10B981)),
                          SizedBox(width: 8),
                          Text('Add Topic', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_section',
                      child: Row(
                        children: [
                          Icon(Icons.create_new_folder_rounded, size: 16, color: Color(0xFFF2B78A)),
                          SizedBox(width: 8),
                          Text('Add Sub-section', style: TextStyle(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final popup = PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: Colors.blueGrey.shade400, size: 18),
                      color: const Color(0xFF241C1A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == 'batch_add_materials') {
                          widget.onBatchAdd();
                        } else if (val == 'rename') {
                          widget.onRename();
                        } else if (val == 'delete') {
                          widget.onDelete();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'batch_add_materials',
                          child: Row(
                            children: [
                              Icon(Icons.library_add_rounded, size: 16, color: Color(0xFFF2B78A)),
                              SizedBox(width: 8),
                              Text('Batch Add Materials', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'rename',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 16, color: Color(0xFFF2B78A)),
                              SizedBox(width: 8),
                              Text('Edit / Rename', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                              SizedBox(width: 8),
                              Text('Delete Section', style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    );

                    if (widget.optionsMenuKey != null) {
                      return TourShowcaseItem(
                        step: TourStep(
                          key: widget.optionsMenuKey!,
                          title: 'Batch Materials & Grouping',
                          description: 'Attach lecture sheets across multiple topics at once, or long-press any item to group topics into sections.',
                        ),
                        stepIndex: 3,
                        totalSteps: 3,
                        section: TourSection.syllabus,
                        child: popup,
                      );
                    }
                    return popup;
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4.0, right: 2.0),
                  child: Icon(
                    _isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
                    color: accentColor,
                    size: 22,
                  ),
                ),
              ],
            ),
            children: [
              ...node.children.map((child) => widget.buildChild(child, depth + 1)),
            ],
          ),
        ),
      ),
    );
  }
}
