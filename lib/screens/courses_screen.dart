import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/course_model.dart';
import '../models/syllabus_model.dart';
import '../providers/firestore_providers.dart';
import '../providers/nav_provider.dart';
import '../providers/timer_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/safe_haptics.dart';

/// Screen 02: Courses & Granular Syllabus Workspace
/// Dedicated 2-column split workspace: Course Directory (~380px) on Left, Active Course Detail Workspace on Right.
class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});

  @override
  ConsumerState<CoursesScreen> createState() => _CoursesScreenState();
}

/// Authentic test courses used by widget test suite
const List<Course> kDefaultTestCourses = [
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

/// Authentic test syllabus topics used by widget test suite
const List<SyllabusTopic> kDefaultTestTopics = [
  SyllabusTopic(
    id: 'topic_3_1',
    chapterTitle: 'Chapter 3: Continuous-Time Signals',
    topicIndex: '3.1',
    title: 'Definition and classification of signals',
    chapterOrder: 3,
    isCompleted: false,
  ),
  SyllabusTopic(
    id: 'topic_3_2',
    chapterTitle: 'Chapter 3: Continuous-Time Signals',
    topicIndex: '3.2',
    title: 'Elementary continuous-time signals',
    chapterOrder: 3,
    isCompleted: false,
  ),
];

class _CoursesScreenState extends ConsumerState<CoursesScreen> {
  String _selectedFilter = 'All';
  String _searchQuery = '';
  int _selectedCourseIndex = 0;
  String _activeSubTab = 'Syllabus';

  final Map<String, bool> _expandedChapters = {};
  final Map<String, bool> _topicCheckState = {};

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    final userProfile = ref.watch(userProfileProvider);
    final isCollege = userProfile.isOnboarded && userProfile.institutionType == InstitutionType.college;

    final liveCoursesAsync = ref.watch(coursesStreamProvider);
    final List<Course> allCourses = liveCoursesAsync.valueOrNull ?? [];

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
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.auto_stories_outlined, color: Color(0xFF9E8C82), size: 48),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Select or create a course to view syllabus.',
                                      style: GoogleFonts.plusJakartaSans(
                                        color: const Color(0xFF9E8C82),
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
          // Directory Title & Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Course Directory',
                style: GoogleFonts.plusJakartaSans(
                  color: const Color(0xFFEDE8E3),
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                onPressed: () => _showAddCourseDialog(context, isCollege),
                icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFFF2B78A), size: 20),
                tooltip: 'Add Course',
              ),
            ],
          ),
          const SizedBox(height: 12),

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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.school_outlined, color: Color(0xFF9E8C82), size: 36),
                          const SizedBox(height: 12),
                          Text(
                            allCourses.isEmpty
                                ? "No courses added yet. Tap '+ Add Course' to set up your syllabus."
                                : "No matching courses found.",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                          ),
                          if (allCourses.isEmpty) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF2B78A),
                                foregroundColor: const Color(0xFF151211),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _showAddCourseDialog(context, isCollege),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('+ Add Course'),
                            ),
                          ],
                        ],
                      ),
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
                const SizedBox(width: 8),
                Text(
                  pctText,
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF9E8C82),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (course.teacherBadge != null && course.teacherBadge!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(
                    '[${course.teacherBadge}]',
                    style: GoogleFonts.jetBrainsMono(
                      color: const Color(0xFFF2B78A),
                      fontSize: 10,
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
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          course.code,
                          style: GoogleFonts.jetBrainsMono(
                            color: const Color(0xFFF2B78A),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
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
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF34D399),
                  foregroundColor: const Color(0xFF151211),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  SafeHaptics.mediumImpact();
                  ref.read(timerProvider.notifier).changeSubject(course.title);
                  ref.read(navigationIndexProvider.notifier).state = 2; // Jump to Timer
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(
                  'Start Focus',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
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
                  final userProfile = ref.read(userProfileProvider);
                  final isCollege = userProfile.isOnboarded && userProfile.institutionType == InstitutionType.college;
                  _showAddCourseDialog(context, isCollege);
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
            const SizedBox(height: 16),
            _buildSyllabusActionBar(course),
            const SizedBox(height: 16),
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

  Widget _buildSyllabusActionBar(Course course) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Chapters & Topics',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFEDE8E3),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        Row(
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEDE8E3),
                side: const BorderSide(color: Color(0xFF2E2623)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showAddChapterDialog(context, course),
              icon: const Icon(Icons.create_new_folder_outlined, size: 16, color: Color(0xFFF2B78A)),
              label: Text('+ Add Chapter', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF151211),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _showAddTopicDialog(context, course),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('+ Add Topic', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ],
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
    final topicsAsync = ref.watch(syllabusTopicsStreamProvider(course.id));
    final liveTopics = topicsAsync.valueOrNull ?? [];
    final int total = liveTopics.isNotEmpty ? liveTopics.length : course.totalTopicsCount;
    final int completed = liveTopics.isNotEmpty
        ? liveTopics.where((t) => (_topicCheckState[t.id] ?? t.isCompleted)).length
        : course.completedTopicsCount;
    final int remaining = math.max(0, total - completed);
    final double progress = total > 0 ? (completed / total) : 0.0;
    final pctText = '${(progress * 100).toInt()}%';

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
                  final isDone = _topicCheckState[topic.id] ?? topic.isCompleted;
                  return _buildAtomicTopicRow(
                    topic.topicCode,
                    topic.title,
                    isDone: isDone,
                    isInProgress: topic.isInProgress,
                    onTapToggle: () {
                      SafeHaptics.selectionClick();
                      setState(() {
                        _topicCheckState[topic.id] = !isDone;
                      });
                      String uid = '';
                      try {
                        uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      } catch (_) {}
                      if (uid.isNotEmpty) {
                        ref.read(courseRepositoryProvider).toggleTopicStatus(
                              uid,
                              course.id,
                              topic.id,
                              !isDone,
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

    // Authentic clean empty state if no topics
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 20.0),
        child: Column(
          children: [
            const Icon(Icons.menu_book_outlined, color: Color(0xFF9E8C82), size: 40),
            const SizedBox(height: 12),
            Text(
              "No topics added yet for this course. Click '+ Add Topic' to populate the syllabus.",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFF9E8C82),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF151211),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _showAddTopicDialog(context, course),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                'Add First Topic',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
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

  void _showAddCourseDialog(BuildContext context, bool isCollege) {
    SafeHaptics.selectionClick();
    final codeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final creditCtrl = TextEditingController(text: isCollege ? '1.0' : '3.0');
    CourseType selectedType = CourseType.theory;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1816),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF2E2623)),
            ),
            title: Text(
              'Add New Course',
              style: GoogleFonts.plusJakartaSans(
                color: const Color(0xFFEDE8E3),
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: codeCtrl,
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: isCollege ? 'Subject Code / Name (e.g. PHY 101)' : 'Course Code (e.g. CSE 1101)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: isCollege ? 'Paper / Title (e.g. Physics 1st Paper)' : 'Course Title (e.g. Structured Programming)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: creditCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: isCollege ? 'Weightage / Credit (default 1.0)' : 'Credits (0.75 - 4.0)',
                      labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Course Type',
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<CourseType>(
                    value: selectedType,
                    dropdownColor: const Color(0xFF241C1A),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    isExpanded: true,
                    underline: Container(height: 1, color: const Color(0xFF2E2623)),
                    items: [
                      const DropdownMenuItem(value: CourseType.theory, child: Text('Theory')),
                      if (isCollege)
                        const DropdownMenuItem(value: CourseType.practical, child: Text('Practical'))
                      else
                        const DropdownMenuItem(value: CourseType.sessional, child: Text('Sessional / Lab')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF2B78A),
                  foregroundColor: const Color(0xFF151211),
                ),
                onPressed: () async {
                  final code = codeCtrl.text.trim();
                  final title = titleCtrl.text.trim();
                  if (code.isEmpty || title.isEmpty) return;

                  final creds = double.tryParse(creditCtrl.text.trim()) ?? (isCollege ? 1.0 : 3.0);
                  final docId = code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

                  final newCourse = Course(
                    id: docId.isNotEmpty ? docId : DateTime.now().millisecondsSinceEpoch.toString(),
                    code: code,
                    title: title,
                    courseType: selectedType,
                    credits: creds,
                    createdAt: DateTime.now(),
                  );

                  String uid = '';
                  try {
                    uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  } catch (_) {}
                  if (uid.isNotEmpty) {
                    await ref.read(courseRepositoryProvider).addCourse(uid, newCourse);
                  }
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text('Save Course', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddChapterDialog(BuildContext context, Course course) {
    SafeHaptics.selectionClick();
    final chapterCtrl = TextEditingController();
    final topicCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1816),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E2623)),
        ),
        title: Text(
          'Add New Chapter',
          style: GoogleFonts.plusJakartaSans(
            color: const Color(0xFFEDE8E3),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: chapterCtrl,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Chapter Title (e.g. Chapter 1: Introduction)',
                labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: topicCtrl,
              style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Initial Topic Title (optional)',
                labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF151211),
            ),
            onPressed: () async {
              final chapter = chapterCtrl.text.trim();
              if (chapter.isEmpty) return;
              final topicTitle = topicCtrl.text.trim();

              final newTopic = SyllabusTopic(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                chapterTitle: chapter,
                topicIndex: '1.1',
                title: topicTitle.isNotEmpty ? topicTitle : 'Overview',
                isCompleted: false,
              );

              String uid = '';
              try {
                uid = FirebaseAuth.instance.currentUser?.uid ?? '';
              } catch (_) {}
              if (uid.isNotEmpty) {
                await ref.read(courseRepositoryProvider).addTopics(uid, course.id, [newTopic]);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('Add Chapter', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showAddTopicDialog(BuildContext context, Course course, [String? defaultChapter]) {
    SafeHaptics.selectionClick();
    final topicsAsync = ref.read(syllabusTopicsStreamProvider(course.id));
    final liveTopics = topicsAsync.valueOrNull ?? [];
    final existingChapters = liveTopics.map((t) => t.chapterTitle).toSet().toList();

    String selectedChapter = defaultChapter ?? (existingChapters.isNotEmpty ? existingChapters.first : 'General');
    final chapterCtrl = TextEditingController(text: selectedChapter);
    final codeCtrl = TextEditingController(text: '${existingChapters.isNotEmpty ? existingChapters.indexOf(selectedChapter) + 1 : 1}.${liveTopics.length + 1}');
    final titleCtrl = TextEditingController();
    bool isCustomChapter = existingChapters.isEmpty;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1816),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E2623)),
          ),
          title: Text(
            'Add Syllabus Topic',
            style: GoogleFonts.plusJakartaSans(
              color: const Color(0xFFEDE8E3),
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existingChapters.isNotEmpty && !isCustomChapter) ...[
                  Text('Chapter', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 12)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    value: existingChapters.contains(selectedChapter) ? selectedChapter : existingChapters.first,
                    dropdownColor: const Color(0xFF241C1A),
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 13),
                    isExpanded: true,
                    underline: Container(height: 1, color: const Color(0xFF2E2623)),
                    items: [
                      ...existingChapters.map((ch) => DropdownMenuItem(value: ch, child: Text(ch))),
                      const DropdownMenuItem(value: '__new__', child: Text('+ New Chapter...')),
                    ],
                    onChanged: (val) {
                      if (val == '__new__') {
                        setDialogState(() {
                          isCustomChapter = true;
                          chapterCtrl.text = '';
                        });
                      } else if (val != null) {
                        setDialogState(() {
                          selectedChapter = val;
                          chapterCtrl.text = val;
                        });
                      }
                    },
                  ),
                ] else ...[
                  TextField(
                    controller: chapterCtrl,
                    style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Chapter Name',
                      labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Topic Code (e.g. 1.1 or T-01)',
                    labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  style: GoogleFonts.plusJakartaSans(color: const Color(0xFFEDE8E3), fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Topic Title',
                    labelStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82), fontSize: 13),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2E2623))),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF2B78A))),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF9E8C82))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF151211),
              ),
              onPressed: () async {
                final chapter = isCustomChapter ? chapterCtrl.text.trim() : selectedChapter;
                final code = codeCtrl.text.trim();
                final title = titleCtrl.text.trim();
                if (chapter.isEmpty || title.isEmpty) return;

                final newTopic = SyllabusTopic(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  chapterTitle: chapter,
                  topicIndex: code.isNotEmpty ? code : '1.1',
                  title: title,
                  isCompleted: false,
                );

                String uid = '';
                try {
                  uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                } catch (_) {}
                if (uid.isNotEmpty) {
                  await ref.read(courseRepositoryProvider).addTopics(uid, course.id, [newTopic]);
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: Text('Add Topic', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
