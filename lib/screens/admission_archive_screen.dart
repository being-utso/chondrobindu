import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exam_model.dart';
import '../providers/analytics_provider.dart';
import '../providers/performance_provider.dart';
import '../providers/syllabus_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/exam_service.dart';
import '../services/syllabus_factory.dart';
import '../widgets/app_preloader.dart';

/// Dedicated Archive Screen for University Students to view previous HSC & Admission data
class AdmissionArchiveScreen extends ConsumerStatefulWidget {
  const AdmissionArchiveScreen({super.key});

  @override
  ConsumerState<AdmissionArchiveScreen> createState() => _AdmissionArchiveScreenState();
}

class _AdmissionArchiveScreenState extends ConsumerState<AdmissionArchiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);

    final userProfile = ref.watch(userProfileProvider);
    final totalMinutes = ref.watch(totalFocusMinutesProvider);
    final currentStreak = ref.watch(currentStreakProvider);
    final totalExams = ref.watch(totalCompletedExamsCountProvider);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Admission Data Archive',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Previous HSC & Admission Records',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accentColor,
          labelColor: accentColor,
          unselectedLabelColor: Colors.blueGrey.shade400,
          tabs: const [
            Tab(icon: Icon(Icons.menu_book_rounded, size: 18), text: 'HSC Syllabus'),
            Tab(icon: Icon(Icons.assignment_outlined, size: 18), text: 'Past Exams'),
            Tab(icon: Icon(Icons.badge_outlined, size: 18), text: 'Target & Stats'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Archived HSC Syllabus
            _buildArchivedSyllabusTab(cardColor, accentColor),

            // Tab 2: Archived Past Exams
            _buildArchivedExamsTab(cardColor, accentColor),

            // Tab 3: Archived Target Goals & Study Stats
            _buildArchivedStatsTab(userProfile, cardColor, accentColor, totalMinutes, currentStreak, totalExams),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivedSyllabusTab(Color cardColor, Color accentColor) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Sign in to view syllabus', style: TextStyle(color: Colors.white)));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('syllabus_state')
          .doc('active_syllabus')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AppPreloader(size: 44));
        }

        List<Subject> subjects = [];
        if (snapshot.hasData && snapshot.data?.data() != null && snapshot.data!.data()!['subjects'] != null) {
          final rawSubjects = snapshot.data!.data()!['subjects'] as List<dynamic>;
          subjects = rawSubjects
              .map((s) => Subject.fromMap(Map<String, dynamic>.from(s)))
              .toList();
        }

        if (subjects.isEmpty) {
          // Fallback to factory engineering preset
          subjects = SyllabusFactory.generateInitialSyllabus('Engineering (BUET, CKRUET)');
        }

        int totalSections = 0;
        int completedSections = 0;
        for (var s in subjects) {
          for (var ch in s.chapters) {
            for (var sec in ch.sections) {
              totalSections++;
              if (sec.isCompleted) completedSections++;
            }
          }
        }

        final double progress = totalSections > 0 ? (completedSections / totalSections) : 0.0;

        return ListView(
          padding: const EdgeInsets.all(16),
          physics: const BouncingScrollPhysics(),
          children: [
            // Progress Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'HSC Syllabus Completion',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${(progress * 100).toStringAsFixed(1)}%',
                        style: TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF382A24),
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$completedSections of $totalSections study sections completed',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Subject Expansion Tiles
            ...subjects.map((subj) {
              final subjTotalSecs = subj.chapters.fold<int>(0, (sum, c) => sum + c.sections.length);
              final subjDoneSecs = subj.chapters.fold<int>(
                0,
                (sum, c) => sum + c.sections.where((s) => s.isCompleted).length,
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: ExpansionTile(
                  iconColor: accentColor,
                  collapsedIconColor: Colors.blueGrey,
                  title: Text(
                    subj.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Text(
                    '$subjDoneSecs / $subjTotalSecs completed • ${subj.chapters.length} chapters',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                  ),
                  children: subj.chapters.map((chap) {
                    final chapDone = chap.sections.where((s) => s.isCompleted).length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF241C1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF382A24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  chap.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                              Text(
                                '$chapDone/${chap.sections.length}',
                                style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...chap.sections.map((sec) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Icon(
                                      sec.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                      size: 16,
                                      color: sec.isCompleted ? const Color(0xFF10B981) : Colors.blueGrey.shade600,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        sec.title,
                                        style: TextStyle(
                                          color: sec.isCompleted ? Colors.blueGrey.shade300 : Colors.blueGrey.shade500,
                                          fontSize: 12,
                                          decoration: sec.isCompleted ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildArchivedExamsTab(Color cardColor, Color accentColor) {
    final examsAsync = ref.watch(examsStreamProvider);
    final allExams = examsAsync.asData?.value ?? [];

    if (allExams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_outlined, size: 56, color: Colors.blueGrey.shade600),
              const SizedBox(height: 16),
              const Text(
                'No Past Exams Found',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Past model tests and exam logs will appear here.',
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: allExams.length,
      itemBuilder: (context, index) {
        final exam = allExams[index];
        final percentage = exam.totalMarks > 0 ? (exam.marksObtained / exam.totalMarks * 100) : 0.0;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assignment_turned_in_rounded, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.examName,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${exam.subject} • ${exam.date.day}/${exam.date.month}/${exam.date.year}',
                      style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${exam.marksObtained.toStringAsFixed(1)} / ${exam.totalMarks.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: percentage >= 80 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  Widget _buildArchivedStatsTab(
    UserProfile profile,
    Color cardColor,
    Color accentColor,
    int totalMinutes,
    int currentStreak,
    int totalExams,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        // Admission Target Goals Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.stars_rounded, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Archived Admission Goals',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildInfoRow('Primary Target', profile.primaryTarget.isNotEmpty ? profile.primaryTarget : 'Engineering (BUET, CKRUET)'),
              const SizedBox(height: 8),
              _buildInfoRow('Secondary Target', profile.secondaryTarget ?? 'None'),
              const SizedBox(height: 8),
              _buildInfoRow('HSC Batch', 'HSC ${profile.hscBatch}'),
              const SizedBox(height: 8),
              _buildInfoRow('HSC Group', profile.hscGroup),
              const SizedBox(height: 8),
              _buildInfoRow('College / Institution', profile.college.isNotEmpty ? profile.college : 'Not specified'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Overall Stats Summary Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Historical Prep Stats',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildStatBadge('Total Focus Time', '${totalMinutes}m', Icons.timer_outlined, accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatBadge('Study Streak', '$currentStreak Days', Icons.local_fire_department_rounded, const Color(0xFFF97316)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatBadge('Completed Model Tests', '$totalExams Exams', Icons.assignment_turned_in_rounded, const Color(0xFF10B981)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13)),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _buildStatBadge(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF241C1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF382A24)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
