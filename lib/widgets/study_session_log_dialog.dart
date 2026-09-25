import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/session_metadata.dart';
import '../models/study_session_model.dart';
import '../models/syllabus_node.dart';
import '../repositories/study_session_repository.dart';
import '../services/journal_service.dart';
import '../services/notification_service.dart';
import 'package:chondrobindu/utils/safe_haptics.dart';

export '../models/session_metadata.dart';

typedef SessionCompleteModal = StudySessionLogDialog;

/// Modal dialog shown immediately when a timer session finishes or is stopped.
/// Integrates syllabus topics (Sections -> Topics) with checkboxes,
/// master toggle to update syllabus progress in Firestore,
/// and logs study notes, reflections, and session duration to users/{uid}/journal.
class StudySessionLogDialog extends StatefulWidget {
  final String? subjectOrCourseName;
  final String? subjectOrCourseId;
  final int? durationMinutes;
  final String mode; // 'university' or 'admission'
  final VoidCallback? onSaved;
  final VoidCallback? onSkipped;
  final SessionMetadata? metadata;

  const StudySessionLogDialog({
    super.key,
    this.subjectOrCourseName,
    this.subjectOrCourseId,
    this.durationMinutes,
    this.mode = 'university',
    this.onSaved,
    this.onSkipped,
    this.metadata,
  });

  @override
  State<StudySessionLogDialog> createState() => _StudySessionLogDialogState();
}

class _StudySessionLogDialogState extends State<StudySessionLogDialog> {
  late final TextEditingController _reflectionsController;
  late final TextEditingController _customTopicsController;

  bool _isLoadingSyllabus = true;
  String? _courseDocId;
  List<SyllabusNode> _syllabusNodes = [];
  final Set<String> _selectedTopicIds = {};
  final Map<String, String> _selectedTopicTitles = {};
  bool _syncToMainSyllabus = true;

  String get effectiveCourseName =>
      widget.metadata?.courseTitle.isNotEmpty == true
          ? widget.metadata!.courseTitle
          : (widget.subjectOrCourseName ?? 'General Study');

  String get effectiveCourseCode =>
      widget.metadata?.courseCode ?? '';

  String get effectiveCourseId =>
      widget.metadata?.courseId.isNotEmpty == true
          ? widget.metadata!.courseId
          : (widget.subjectOrCourseId ?? '');

  int get effectiveDurationMinutes =>
      widget.metadata != null
          ? widget.metadata!.durationMinutes
          : ((widget.durationMinutes ?? 0) > 0 ? widget.durationMinutes! : 1);

  @override
  void initState() {
    super.initState();
    _reflectionsController = TextEditingController();
    _customTopicsController = TextEditingController();
    _fetchCourseSyllabus();
  }

  @override
  void dispose() {
    _reflectionsController.dispose();
    _customTopicsController.dispose();
    super.dispose();
  }

  Future<void> _fetchCourseSyllabus() async {
    try {
      String? uid;
      try {
        uid = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}

      if (uid == null || uid.isEmpty) {
        if (mounted) setState(() => _isLoadingSyllabus = false);
        return;
      }

      final coursesCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('courses');

      // 1. Try direct ID lookup strictly via effectiveCourseId
      if (effectiveCourseId.isNotEmpty) {
        final directDoc = await coursesCol.doc(effectiveCourseId).get();
        if (directDoc.exists && directDoc.data() != null) {
          _courseDocId = directDoc.id;
          final rawData = directDoc.data()!['syllabusData'];
          _parseNodes(rawData);
          if (mounted) setState(() => _isLoadingSyllabus = false);
          return;
        }
      }

      // 2. Query courses and match by metadata course code / title without relying on global notifiers
      final querySnap = await coursesCol.get();
      final targetCode = effectiveCourseCode.trim().toLowerCase();
      final targetTitle = effectiveCourseName.trim().toLowerCase();
      final targetId = effectiveCourseId.trim().toLowerCase();

      DocumentSnapshot<Map<String, dynamic>>? matchedDoc;
      for (final doc in querySnap.docs) {
        final data = doc.data();
        final docId = doc.id.toLowerCase();
        final cName = (data['courseName'] ?? data['title'] ?? '').toString().trim().toLowerCase();
        final cCode = (data['courseCode'] ?? '').toString().trim().toLowerCase();

        if (docId == targetId ||
            (targetCode.isNotEmpty && (cCode == targetCode || docId == targetCode)) ||
            (targetTitle.isNotEmpty && cName == targetTitle)) {
          matchedDoc = doc;
          break;
        }
      }

      if (matchedDoc != null && matchedDoc.data() != null) {
        _courseDocId = matchedDoc.id;
        final rawData = matchedDoc.data()!['syllabusData'];
        _parseNodes(rawData);
      }
    } catch (e) {
      debugPrint('Error fetching course syllabus in StudySessionLogDialog: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSyllabus = false);
      }
    }
  }

  void _parseNodes(dynamic rawData) {
    if (rawData == null) return;
    if (rawData is List) {
      _syllabusNodes = rawData
          .whereType<Map>()
          .map((c) => SyllabusNode.fromMap(Map<String, dynamic>.from(c)))
          .toList();
    }
  }

  Future<void> _handleSave() async {
    SafeHaptics.mediumImpact();

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final effectiveMins = effectiveDurationMinutes;

    // TASK: Instant Dialog Dismissal on Submit
    Navigator.of(context, rootNavigator: true).pop();
    widget.onSaved?.call();

    // Cancel timer status bar notification and pause nudge
    try {
      NotificationService().cancelTimerNotification();
      NotificationService().cancelAbandonedPauseNudge();
    } catch (e) {
      debugPrint('Error canceling timer notification: $e');
    }

    // TASK: Floating 3-second SnackBar with 'View' action & hideCurrentSnackBar
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Session notes saved to Journal (${effectiveMins}m)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            nav.pushNamed('/journal');
          },
        ),
      ),
    );

    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {}

    if (uid == null || uid.isEmpty) return;

    // Collect topics: selected syllabus topics + any manual custom topics
    final selectedTitles = _selectedTopicTitles.values.toList();
    final customTopics = _customTopicsController.text.trim();
    final reflections = _reflectionsController.text.trim();

    final List<String> allTopicsList = [];
    allTopicsList.addAll(selectedTitles);
    if (customTopics.isNotEmpty) {
      allTopicsList.add(customTopics);
    }
    final combinedTopics = allTopicsList.join(', ');

    // 1. Save to Journal in background
    try {
      final service = JournalService();
      await service.saveStudySessionJournal(
        uid: uid,
        subjectOrCourse: effectiveCourseName,
        subjectOrCourseId: effectiveCourseId,
        durationMinutes: effectiveMins,
        topicsCovered: combinedTopics.isNotEmpty ? combinedTopics : 'General Study',
        reflections: reflections.isNotEmpty ? reflections : null,
        mode: widget.mode,
      );
    } catch (e) {
      debugPrint('Error saving study session journal: $e');
    }

    // 1b. Save to StudySessionRepository for dual-track metrics and streak
    try {
      final now = DateTime.now();
      final session = StudySession(
        id: now.millisecondsSinceEpoch.toString(),
        courseId: _courseDocId ?? effectiveCourseId,
        courseCode: effectiveCourseCode.isNotEmpty ? effectiveCourseCode : effectiveCourseName,
        topicIds: _selectedTopicIds.toList(),
        topicTitles: selectedTitles,
        durationSeconds: effectiveMins * 60,
        startedAt: now.subtract(Duration(minutes: effectiveMins)),
        endedAt: now,
        focusNotes: reflections.isNotEmpty ? reflections : null,
        focusRating: 5,
      );
      await StudySessionRepository().logCompletedSession(uid, session);
    } catch (e) {
      debugPrint('Error logging study session: $e');
    }

    // 2. If sync toggle is ON and syllabus nodes were selected, update syllabus in Firestore
    if (_syncToMainSyllabus && _selectedTopicIds.isNotEmpty && _courseDocId != null && _syllabusNodes.isNotEmpty) {
      try {
        void markCompleted(List<SyllabusNode> nodes) {
          for (final node in nodes) {
            if (_selectedTopicIds.contains(node.id)) {
              node.isCompleted = true;
              node.setCompletedCascading(true);
            }
            markCompleted(node.children);
          }
        }

        markCompleted(_syllabusNodes);

        // Run bottom-up hierarchical update so parent sections update accurately
        for (final root in _syllabusNodes) {
          root.updateHierarchicalCompletion();
        }

        final serialized = _syllabusNodes.map((n) => n.toMap()).toList();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('courses')
            .doc(_courseDocId)
            .update({
          'syllabusData': serialized,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        debugPrint('Successfully marked ${_selectedTopicIds.length} syllabus topic(s) as completed in course $_courseDocId');
      } catch (e) {
        debugPrint('Error syncing syllabus completion to Firestore: $e');
      }
    }
  }

  Widget _buildNodeTile(SyllabusNode node, {int depth = 0}) {
    const accentColor = Color(0xFFF2B78A);
    const emeraldColor = Color(0xFF10B981);

    final isSelected = _selectedTopicIds.contains(node.id);

    // If node has children (Section with topics, or Topic with subtopics / materials), render expandable tile with cascading checkbox
    if (node.children.isNotEmpty) {
      void selectCascading(SyllabusNode n, bool select) {
        if (select) {
          _selectedTopicIds.add(n.id);
          _selectedTopicTitles[n.id] = n.title;
        } else {
          _selectedTopicIds.remove(n.id);
          _selectedTopicTitles.remove(n.id);
        }
        for (final child in n.children) {
          selectCascading(child, select);
        }
      }

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.only(left: (depth * 10.0).clamp(0, 32), right: 6),
          childrenPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isSelected,
              activeColor: emeraldColor,
              checkColor: Colors.black,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (val) {
                setState(() {
                  selectCascading(node, val == true);
                });
              },
            ),
          ),
          title: Row(
            children: [
              Icon(
                depth == 0 ? Icons.folder_open_rounded : Icons.library_books_rounded,
                color: accentColor.withOpacity(0.85),
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.title,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: depth == 0 ? 13.5 : 13.0,
                    fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w600,
                    decoration: node.isCompleted && !isSelected ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white38,
                  ),
                ),
              ),
              if (node.isCompleted)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: emeraldColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.plusJakartaSans(color: emeraldColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          children: node.children.map((child) => _buildNodeTile(child, depth: depth + 1)).toList(),
        ),
      );
    }

    // Otherwise render as a checkable leaf topic / material tile ("Class Note", "Lecture Sheet", etc.)
    return Padding(
      padding: EdgeInsets.only(left: (depth * 14.0).clamp(0, 48)),
      child: Material(
        color: Colors.transparent,
        child: CheckboxListTile(
          value: isSelected,
          activeColor: emeraldColor,
          checkColor: Colors.black,
          dense: true,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          title: Text(
            node.title,
            style: GoogleFonts.plusJakartaSans(
              color: isSelected ? Colors.white : Colors.white70,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              decoration: node.isCompleted && !isSelected ? TextDecoration.lineThrough : null,
              decorationColor: Colors.white38,
            ),
          ),
          subtitle: node.isCompleted
              ? Text(
                  'Already completed in syllabus',
                  style: GoogleFonts.plusJakartaSans(color: emeraldColor.withOpacity(0.8), fontSize: 10.5),
                )
              : null,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedTopicIds.add(node.id);
                _selectedTopicTitles[node.id] = node.title;
              } else {
                _selectedTopicIds.remove(node.id);
                _selectedTopicTitles.remove(node.id);
              }
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const cardColor = Color(0xFF1C1412);
    const fieldFill = Color(0xFF241C1A);
    const borderColor = Color(0xFF382A24);
    const accentColor = Color(0xFFF2B78A);
    const emeraldColor = Color(0xFF10B981);

    return Dialog(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: borderColor, width: 0.8),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: emeraldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle_rounded, color: emeraldColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Session Completed! 🎉',
                        style: GoogleFonts.plusJakartaSans(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Log what you learned to your Journal',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Summary Row: Course & Duration Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fieldFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.menu_book_rounded, color: accentColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            effectiveCourseCode.isNotEmpty && effectiveCourseCode != effectiveCourseName
                                ? '$effectiveCourseCode: $effectiveCourseName'
                                : effectiveCourseName,
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: emeraldColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, color: emeraldColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$effectiveDurationMinutes mins',
                          style: GoogleFonts.jetBrainsMono(
                            color: emeraldColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Section: Syllabus Topics Multi-Select
            Text(
              'SELECT SYLLABUS TOPICS READ',
              style: GoogleFonts.plusJakartaSans(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),

            if (_isLoadingSyllabus)
              Container(
                height: 52,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, color: accentColor, size: 18),
                    SizedBox(width: 10),
                    Text('Loading course syllabus topics...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              )
            else if (_syllabusNodes.isNotEmpty) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: _syllabusNodes.map((node) => _buildNodeTile(node)).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Master Toggle Switch: Mark selected topics as completed in main syllabus
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _syncToMainSyllabus ? emeraldColor.withOpacity(0.4) : borderColor),
                ),
                child: SwitchListTile(
                  value: _syncToMainSyllabus,
                  activeThumbColor: emeraldColor,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Mark selected topics as completed in main syllabus',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Syncs status to Course Dashboard & Syllabus',
                    style: GoogleFonts.plusJakartaSans(
                      color: const Color(0xFFABA093),
                      fontSize: 11,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _syncToMainSyllabus = val);
                  },
                ),
              ),
            ] else ...[
              // Fallback / No syllabus found notice
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: fieldFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFABA093), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No syllabus structure found for this course. You can enter topics manually below.',
                        style: GoogleFonts.plusJakartaSans(color: const Color(0xFFABA093), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Additional / Custom Topics TextField
            Text(
              _syllabusNodes.isNotEmpty ? 'ADDITIONAL TOPICS / KEYWORDS (OPTIONAL)' : 'KEYWORDS / TOPICS READ',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFABA093),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _customTopicsController,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'e.g., Problem set 3, Formula derivations',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF7E726B), fontSize: 12.5),
                filled: true,
                fillColor: fieldFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Quick Reflection TextField
            Text(
              'QUICK REFLECTION / NOTES (OPTIONAL)',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFABA093),
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reflectionsController,
              maxLines: 2,
              style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 13.5),
              decoration: InputDecoration(
                hintText: 'e.g., Felt confident on derivations; need to practice numericals.',
                hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF7E726B), fontSize: 12.5),
                filled: true,
                fillColor: fieldFill,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: accentColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFABA093),
                      side: const BorderSide(color: borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      SafeHaptics.lightImpact();
                      Navigator.of(context, rootNavigator: true).pop();
                      try {
                        NotificationService().cancelTimerNotification();
                        NotificationService().cancelAbandonedPauseNudge();
                      } catch (_) {}
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      widget.onSkipped?.call();
                    },
                    child: Text('Skip', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: const Color(0xFF140F0E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _handleSave,
                    icon: const Icon(Icons.bookmark_added_rounded, size: 18),
                    label: Text(
                      'Save to Journal',
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
  }
}
