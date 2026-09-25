import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/user_profile_provider.dart';
import '../utils/safe_haptics.dart';

/// Screen 02: Courses & Granular Syllabus Workspace
/// Dedicated 2-column split workspace: Course Directory (~380px) on Left, Active Course Detail Workspace on Right.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _selectedFilter = 'All';
  String _searchQuery = '';
  int _selectedCourseIndex = 0;
  String _activeSubTab = 'Syllabus';

  // Fallback Courses with authentic academic data
  static const List<Course> _defaultCourses = [
    Course(
      id: 'eee_2105',
      code: 'EEE 2105',
      title: 'Signals & Systems',
      courseType: CourseType.theory,
      credits: 3.0,
      totalTopicsCount: 42,
      completedTopicsCount: 28,
      teacherInitials: ['MSR'],
    ),
    Course(
      id: 'eee_2106',
      code: 'EEE 2106',
      title: 'Signals & Simulation Lab',
      courseType: CourseType.sessional,
      credits: 1.5,
      totalTopicsCount: 20,
      completedTopicsCount: 10,
      teacherInitials: ['MSR'],
    ),
    Course(
      id: 'eee_2101',
      code: 'EEE 2101',
      title: 'Electronic Circuits I',
      courseType: CourseType.theory,
      credits: 3.0,
      totalTopicsCount: 36,
      completedTopicsCount: 30,
      teacherInitials: ['ARH'],
    ),
    Course(
      id: 'eee_2102',
      code: 'EEE 2102',
      title: 'Electronics Circuit Lab',
      courseType: CourseType.sessional,
      credits: 1.5,
      totalTopicsCount: 16,
      completedTopicsCount: 12,
      teacherInitials: ['ARH'],
    ),
    Course(
      id: 'math_2103',
      code: 'MATH 2103',
      title: 'Complex Variables & Laplace',
      courseType: CourseType.theory,
      credits: 3.0,
      totalTopicsCount: 40,
      completedTopicsCount: 18,
      teacherInitials: [],
    ),
    Course(
      id: 'cse_2110',
      code: 'CSE 2110',
      title: 'Data Structures Lab',
      courseType: CourseType.sessional,
      credits: 1.5,
      totalTopicsCount: 25,
      completedTopicsCount: 15,
      teacherInitials: ['NA'],
    ),
    Course(
      id: 'hum_2107',
      code: 'HUM 2107',
      title: 'Engineering Economics',
      courseType: CourseType.theory,
      credits: 2.0,
      totalTopicsCount: 20,
      completedTopicsCount: 7,
      teacherInitials: [],
    ),
    Course(
      id: 'eee_1202',
      code: 'EEE 1202',
      title: 'Basic Electrical Engineering Lab',
      courseType: CourseType.sessional,
      credits: 1.5,
      totalTopicsCount: 20,
      completedTopicsCount: 15,
      isArchived: false,
      teacherInitials: ['FK'],
    ),
  ];

  // Fallback atomic topic items state for granular syllabus tree
  final Map<String, bool> _topicCheckState = {
    '3.1': true,
    '3.2': true,
    '3.3': false,
    '3.4': false,
    '3.5': false,
    '3.6': false,
    '3.7': false,
    '4.1': true,
    '4.2': false,
  };

  final Map<String, bool> _expandedChapters = {
    'Chapter 3: Continuous-Time Signals': true,
    'Chapter 4: Fourier Series Representation': false,
  };

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    final userProfile = ref.watch(userProfileProvider);
    final isCollege = userProfile.isOnboarded && userProfile.institutionType == InstitutionType.college;

    final liveCoursesAsync = ref.watch(coursesStreamProvider);
    final liveCourses = liveCoursesAsync.valueOrNull;
    final List<Course> allCourses = (liveCourses != null && liveCourses.isNotEmpty)
        ? liveCourses
        : _defaultCourses;

    final filteredCourses = allCourses.where((c) {
      if (_selectedFilter == 'Theory' && c.courseType != CourseType.theory) return false;
      if (_selectedFilter == 'Sessional' && c.courseType != CourseType.sessional) return false;
      if (_selectedFilter == 'Practical' && c.courseType != CourseType.practical) return false;
      if (_selectedFilter == 'Archived' && !c.isArchived) return false;
      if (_selectedFilter != 'Archived' && c.isArchived) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final code = c.code.toLowerCase();
        final title = c.title.toLowerCase();
        return code.contains(q) || title.contains(q);
      }
      return true;
    }).toList();

    final Course? selectedCourse = filteredCourses.isNotEmpty
        ? filteredCourses[math.min(_selectedCourseIndex, filteredCourses.length - 1)]
        : (allCourses.isNotEmpty ? allCourses.first : null);

    return Scaffold(
      backgroundColor: const Color(0xFF151211),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: isWide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Course Directory (~380px)
                    SizedBox(
                      width: 380,
                      child: _buildCourseDirectory(allCourses, filteredCourses, isCollege),
                    ),

                    // Subtle Vertical Divider
                    Container(width: 1, color: const Color(0xFF2E2623)),

                    // Right Column: Active Course Workspace
                    Expanded(
                      child: selectedCourse != null
                          ? _buildCourseDetailWorkspace(selectedCourse)
                          : const Center(
                              child: Text('No courses found', style: TextStyle(color: Color(0xFF9E8C82))),
                            ),
                    ),
                  ],
                )
              : _buildMobileCourseView(allCourses, filteredCourses, selectedCourse, isCollege),
        ),
      ),
    );
  }

  // --- SECTION A: Left Column — Course Directory ---
  Widget _buildCourseDirectory(List<Course> allCourses, List<Course> filteredCourses, bool isCollege) {
    final int allCount = allCourses.length;
    final int theoryCount = allCourses.where((c) => c.courseType == CourseType.theory).length;
    final int sessionalCount = allCourses.where((c) => c.courseType == CourseType.sessional).length;
    final int practicalCount = allCourses.where((c) => c.courseType == CourseType.practical).length;
    final int archivedCount = allCourses.where((c) => c.isArchived).length;

    return Container(
      color: const Color(0xFF151211),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Chips Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', '$allCount'),
                const SizedBox(width: 8),
                _filterChip('Theory', '$theoryCount'),
                const SizedBox(width: 8),
                if (isCollege)
                  _filterChip('Practical', '$practicalCount')
                else
                  _filterChip('Sessional', '$sessionalCount'),
                const SizedBox(width: 8),
                _filterChip('Archived', '$archivedCount'),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Search Bar
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1816),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E2623), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: Color(0xFF9E8C82), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search course code or title...',
                      hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Course Card List
          Expanded(
            child: filteredCourses.isEmpty
                ? Center(
                    child: Text(
                      'No matching courses',
                      style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredCourses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final course = filteredCourses[index];
                      final isSelected = index == _selectedCourseIndex;
                      return _buildCourseCard(course, index, isSelected);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String count) {
    final active = _selectedFilter == label;
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() {
          _selectedFilter = label;
          _selectedCourseIndex = 0;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF2B78A).withValues(alpha: 0.15) : const Color(0xFF1E1816),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? const Color(0xFFF2B78A) : const Color(0xFF2E2623),
            width: 1,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: GoogleFonts.plusJakartaSans(
            color: active ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course, int index, bool isSelected) {
    final double progress = course.progressFraction;
    final pctText = '${(progress * 100).toInt()}%';

    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _selectedCourseIndex = index);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1816),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? const Color(0xFFF2B78A) : const Color(0xFF2E2623),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  course.code,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFFF2B78A),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${course.credits} cr • ${course.courseType == CourseType.sessional ? "Sessional" : (course.courseType == CourseType.practical ? "Practical" : "Theory")}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFF9E8C82),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              course.title,
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFEDE8E3),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Progress row
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF2E2623),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                      minHeight: 5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  pctText,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (course.teacherBadge != null && course.teacherBadge!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '[${course.teacherBadge}]',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- SECTION B: Right Column — Active Course Detail Workspace ---
  Widget _buildCourseDetailWorkspace(Course course) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Course Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          course.code,
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFFF2B78A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1816),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF2E2623), width: 1),
                          ),
                          child: Text(
                            '${course.credits} Credits • ${course.courseType.displayName}',
                            style: GoogleFonts.jetBrainsMono(
                              color: const Color(0xFF9E8C82),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      course.title,
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFFEDE8E3),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course.teacherBadge != null && course.teacherBadge!.isNotEmpty
                          ? 'Instructor Initials: [${course.teacherBadge}]'
                          : 'Standard Academic Track',
                      style: GoogleFonts.plusJakartaSans(
                        color: const Color(0xFF9E8C82),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),

              // Action Buttons
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEDE8E3),
                  side: const BorderSide(color: Color(0xFF2E2623)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  SafeHaptics.selectionClick();
                },
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2B78A),
                  foregroundColor: const Color(0xFF151211),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  SafeHaptics.mediumImpact();
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  '+ Add Course',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Horizontal Sub-Tabs: [Syllabus], [Assessments], [Resources], [Progress]
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF2E2623), width: 1)),
            ),
            child: Row(
              children: [
                _subTabItem('Syllabus', Icons.menu_book_outlined),
                _subTabItem('Assessments', Icons.assignment_outlined),
                _subTabItem('Resources', Icons.folder_outlined),
                _subTabItem('Progress', Icons.insights_outlined),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Syllabus Tab Content
          if (_activeSubTab == 'Syllabus') ...[
            _buildSyllabusTabHeader(course),
            const SizedBox(height: 24),
            _buildGranularTopicTree(course),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48.0),
                child: Text(
                  '$_activeSubTab Workspace Loaded',
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subTabItem(String label, IconData icon) {
    final active = _activeSubTab == label;
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        setState(() => _activeSubTab = label);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? const Color(0xFFF2B78A) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: active ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
              size: 17,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: active ? const Color(0xFFF2B78A) : const Color(0xFF9E8C82),
                fontSize: 13.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SECTION B1: Syllabus Tab Header ---
  Widget _buildSyllabusTabHeader(Course course) {
    final double progress = course.progressFraction;
    final pctText = '${(progress * 100).toInt()}%';
    final int total = course.totalTopicsCount > 0 ? course.totalTopicsCount : 42;
    final int completed = course.completedTopicsCount;
    final int remaining = math.max(0, total - completed);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1816),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2623), width: 1),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Radial Completion Chart
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 7,
                      backgroundColor: const Color(0xFF2E2623),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                    ),
                    Text(
                      pctText,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFFEDE8E3),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 20),

              // Stat Counts
              _statBox('$total', 'Total Topics', const Color(0xFFEDE8E3)),
              const SizedBox(width: 16),
              _statBox('$completed', 'Completed', const Color(0xFF34D399)),
              const SizedBox(width: 16),
              _statBox('$remaining', 'Remaining', const Color(0xFFF2B78A)),
            ],
          ),

          // "Mark All" action button
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFF2B78A),
              side: const BorderSide(color: Color(0xFF382A24)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              SafeHaptics.selectionClick();
              setState(() {
                _topicCheckState.updateAll((key, value) => true);
              });
            },
            child: Text(
              'Mark All Complete',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            color: valueColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFF9E8C82),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // --- SECTION B2: Granular Topic Tree ---
  Widget _buildGranularTopicTree(Course course) {
    final topicsAsync = ref.watch(syllabusTopicsStreamProvider(course.id));
    final liveTopics = topicsAsync.valueOrNull;

    if (liveTopics != null && liveTopics.isNotEmpty) {
      // Group topics by chapter
      final Map<String, List<SyllabusTopic>> byChapter = {};
      for (final topic in liveTopics) {
        byChapter.putIfAbsent(topic.chapter, () => []).add(topic);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: byChapter.entries.map((entry) {
          final chapterName = entry.key;
          final chapterTopics = entry.value;
          final completedCount = chapterTopics.where((t) => t.isCompleted).length;
          final isExpanded = _expandedChapters[chapterName] ?? true;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildChapterHeader(
                chapterTitle: chapterName,
                topicsCount: '${chapterTopics.length} Topics • $completedCount Completed',
                isExpanded: isExpanded,
                onToggle: () => setState(() {
                  _expandedChapters[chapterName] = !isExpanded;
                }),
              ),
              if (isExpanded) ...[
                const SizedBox(height: 8),
                ...chapterTopics.map((topic) {
                  return _buildAtomicTopicRow(
                    topic.topicCode,
                    topic.title,
                    isDone: topic.isCompleted,
                    isInProgress: topic.isInProgress,
                    onTapToggle: () {
                      SafeHaptics.selectionClick();
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      if (uid.isNotEmpty) {
                        ref.read(courseRepositoryProvider).toggleTopicStatus(
                              uid,
                              course.id,
                              topic.id,
                              !topic.isCompleted,
                            );
                      }
                    },
                  );
                }),
                const SizedBox(height: 16),
              ],
            ],
          );
        }).toList(),
      );
    }

    // Fallback static topics if no Firestore topics yet
    final ch3Expanded = _expandedChapters['Chapter 3: Continuous-Time Signals'] ?? true;
    final ch4Expanded = _expandedChapters['Chapter 4: Fourier Series Representation'] ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapsible Chapter 3 Header
        _buildChapterHeader(
          chapterTitle: 'Chapter 3: Continuous-Time Signals',
          topicsCount: '7 Topics • 2 Completed',
          isExpanded: ch3Expanded,
          onToggle: () => setState(() {
            _expandedChapters['Chapter 3: Continuous-Time Signals'] = !ch3Expanded;
          }),
        ),

        if (ch3Expanded) ...[
          const SizedBox(height: 8),
          _buildAtomicTopicRow('3.1', 'Definition and classification of signals', isDone: _topicCheckState['3.1'] ?? false, onTapToggle: () => _toggleLocalTopic('3.1')),
          _buildAtomicTopicRow('3.2', 'Elementary continuous-time signals', isDone: _topicCheckState['3.2'] ?? false, onTapToggle: () => _toggleLocalTopic('3.2')),
          _buildAtomicTopicRow('3.3', 'Time shifting and scaling', isInProgress: true, isDone: _topicCheckState['3.3'] ?? false, onTapToggle: () => _toggleLocalTopic('3.3')),
          _buildAtomicTopicRow('3.4', 'Signal addition and multiplication', isDone: _topicCheckState['3.4'] ?? false, onTapToggle: () => _toggleLocalTopic('3.4')),
          _buildAtomicTopicRow('3.5', 'Even and odd signals', isDone: _topicCheckState['3.5'] ?? false, onTapToggle: () => _toggleLocalTopic('3.5')),
          _buildAtomicTopicRow('3.6', 'Periodic signals and fundamental period', isDone: _topicCheckState['3.6'] ?? false, onTapToggle: () => _toggleLocalTopic('3.6')),
          _buildAtomicTopicRow('3.7', 'Energy and power signals', isDone: _topicCheckState['3.7'] ?? false, onTapToggle: () => _toggleLocalTopic('3.7')),
        ],

        const SizedBox(height: 16),

        // Collapsible Chapter 4 Header
        _buildChapterHeader(
          chapterTitle: 'Chapter 4: Fourier Series Representation',
          topicsCount: '5 Topics • 1 Completed',
          isExpanded: ch4Expanded,
          onToggle: () => setState(() {
            _expandedChapters['Chapter 4: Fourier Series Representation'] = !ch4Expanded;
          }),
        ),

        if (ch4Expanded) ...[
          const SizedBox(height: 8),
          _buildAtomicTopicRow('4.1', 'Trigonometric Fourier Series formulation', isDone: _topicCheckState['4.1'] ?? false, onTapToggle: () => _toggleLocalTopic('4.1')),
          _buildAtomicTopicRow('4.2', 'Exponential Fourier Series & Dirichlet conditions', isDone: _topicCheckState['4.2'] ?? false, onTapToggle: () => _toggleLocalTopic('4.2')),
        ],
      ],
    );
  }

  void _toggleLocalTopic(String id) {
    SafeHaptics.selectionClick();
    setState(() {
      _topicCheckState[id] = !(_topicCheckState[id] ?? false);
    });
  }

  Widget _buildChapterHeader({
    required String chapterTitle,
    required String topicsCount,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return InkWell(
      onTap: () {
        SafeHaptics.selectionClick();
        onToggle();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1816),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2E2623), width: 1),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded,
              color: const Color(0xFFF2B78A),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapterTitle,
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              topicsCount,
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF9E8C82),
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAtomicTopicRow(
    String id,
    String title, {
    bool isDone = false,
    bool isInProgress = false,
    VoidCallback? onTapToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isInProgress ? const Color(0xFFF2B78A).withValues(alpha: 0.5) : const Color(0xFF2E2623),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: isDone,
            activeColor: const Color(0xFF34D399),
            checkColor: const Color(0xFF151211),
            side: const BorderSide(color: Color(0xFF4A3830), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: (val) {
              onTapToggle?.call();
            },
          ),
          const SizedBox(width: 8),
          Text(
            id,
            style: GoogleFonts.jetBrainsMono(
              color: const Color(0xFF9E8C82),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                color: isDone ? const Color(0xFF9E8C82) : const Color(0xFFEDE8E3),
                decoration: isDone ? TextDecoration.lineThrough : null,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isInProgress)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF2B78A).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFF2B78A), width: 0.8),
              ),
              child: Text(
                'In Progress',
                style: GoogleFonts.jetBrainsMono(
                  color: const Color(0xFFF2B78A),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Mobile fallback for small screens ---
  Widget _buildMobileCourseView(
    List<Course> allCourses,
    List<Course> filteredCourses,
    Course? selectedCourse,
    bool isCollege,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', '${allCourses.length}'),
                const SizedBox(width: 8),
                _filterChip('Theory', '${allCourses.where((c) => c.courseType == CourseType.theory).length}'),
                const SizedBox(width: 8),
                if (isCollege)
                  _filterChip('Practical', '${allCourses.where((c) => c.courseType == CourseType.practical).length}')
                else
                  _filterChip('Sessional', '${allCourses.where((c) => c.courseType == CourseType.sessional).length}'),
                const SizedBox(width: 8),
                _filterChip('Archived', '${allCourses.where((c) => c.isArchived).length}'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (selectedCourse != null) _buildCourseDetailWorkspace(selectedCourse),
        ],
      ),
    );
  }
}
