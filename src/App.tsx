import React, { useState, useEffect } from 'react';
import {
  Home,
  BookOpen,
  Timer as TimerIcon,
  BarChart2,
  Flame,
  School,
  Play,
  Pause,
  Square as StopIcon,
  Coffee,
  PlusCircle,
  Award,
  FileText,
  Copy,
  Check,
  Smartphone,
  Code2,
  Bell,
  Quote,
  Sparkles,
  ChevronDown,
  ChevronUp,
  Plus,
  CheckSquare,
  Square,
  TrendingUp,
  PieChart as PieIcon,
  BarChart3,
  Calendar,
  Zap,
  Target,
  ArrowUpRight,
  ArrowDownRight,
  CalendarDays,
  Medal,
  Activity,
  RotateCcw,
  CheckCircle,
  HelpCircle,
  Settings2,
  ArrowLeft,
  User,
  Camera,
  Mail,
} from 'lucide-react';

// Dart File Source Code strings for the Inspector
const DART_FILES = {
  'lib/models/performance_models.dart': `class ExamRecord {
  final String id;
  final String examName;
  final String subject;
  final double marks;
  final int meritPosition;
  final DateTime date;

  const ExamRecord({
    required this.id,
    required this.examName,
    required this.subject,
    required this.marks,
    required this.meritPosition,
    required this.date,
  });

  ExamRecord copyWith({
    String? id,
    String? examName,
    String? subject,
    double? marks,
    int? meritPosition,
    DateTime? date,
  }) {
    return ExamRecord(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      subject: subject ?? this.subject,
      marks: marks ?? this.marks,
      meritPosition: meritPosition ?? this.meritPosition,
      date: date ?? this.date,
    );
  }
}

class UpcomingExam {
  final String id;
  final String examName;
  final DateTime targetDate;

  const UpcomingExam({
    required this.id,
    required this.examName,
    required this.targetDate,
  });

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final diff = target.difference(today).inDays;
    return diff < 0 ? 0 : diff;
  }

  UpcomingExam copyWith({
    String? id,
    String? examName,
    DateTime? targetDate,
  }) {
    return UpcomingExam(
      id: id ?? this.id,
      examName: examName ?? this.examName,
      targetDate: targetDate ?? this.targetDate,
    );
  }
}`,

  'lib/providers/performance_provider.dart': `import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/performance_models.dart';

/// Provider for managing upcoming exam targets.
final upcomingExamsProvider = StateProvider<List<UpcomingExam>>((ref) {
  final now = DateTime.now();

  return [
    UpcomingExam(
      id: 'exam_buet',
      examName: 'BUET Admission Test 2026',
      targetDate: DateTime(now.year, now.month, now.day + 42),
    ),
    UpcomingExam(
      id: 'exam_ckruet',
      examName: 'CKRUET Combined Exam',
      targetDate: DateTime(now.year, now.month, now.day + 58),
    ),
    UpcomingExam(
      id: 'exam_mist',
      examName: 'MIST Admission Test',
      targetDate: DateTime(now.year, now.month, now.day + 24),
    ),
  ];
});

/// Returns the nearest future upcoming exam.
final nearestUpcomingExamProvider = Provider<UpcomingExam?>((ref) {
  final exams = ref.watch(upcomingExamsProvider);
  if (exams.isEmpty) return null;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final futureExams = exams.where((e) {
    final t = DateTime(e.targetDate.year, e.targetDate.month, e.targetDate.day);
    return !t.isBefore(today);
  }).toList();

  if (futureExams.isEmpty) return null;

  futureExams.sort((a, b) => a.targetDate.compareTo(b.targetDate));
  return futureExams.first;
});

/// Provider for past exam records logged by the student.
final examRecordsProvider = StateProvider<List<ExamRecord>>((ref) {
  final now = DateTime.now();

  DateTime daysAgo(int days) {
    return DateTime(now.year, now.month, now.day - days);
  }

  return [
    ExamRecord(
      id: 'rec_1',
      examName: 'Udvash Paper Final 01',
      subject: 'Higher Mathematics',
      marks: 68.0,
      meritPosition: 185,
      date: daysAgo(28),
    ),
    ExamRecord(
      id: 'rec_2',
      examName: 'Udvash Paper Final 02',
      subject: 'Physics 1st & 2nd',
      marks: 74.5,
      meritPosition: 120,
      date: daysAgo(21),
    ),
    ExamRecord(
      id: 'rec_3',
      examName: 'Engineering Model Test 01',
      subject: 'Combined Science',
      marks: 79.0,
      meritPosition: 84,
      date: daysAgo(14),
    ),
    ExamRecord(
      id: 'rec_4',
      examName: 'BUET Central Mock Test 1',
      subject: 'Math & Physics',
      marks: 85.5,
      meritPosition: 42,
      date: daysAgo(7),
    ),
    ExamRecord(
      id: 'rec_5',
      examName: 'BUET Central Mock Test 2',
      subject: 'Combined Overall',
      marks: 89.0,
      meritPosition: 28,
      date: daysAgo(1),
    ),
  ];
});

class PerformanceImprovement {
  final double marksDelta;
  final int meritDelta;
  final bool isMarksImproved;
  final bool isMeritImproved;
  final bool hasEnoughData;

  const PerformanceImprovement({
    required this.marksDelta,
    required this.meritDelta,
    required this.isMarksImproved,
    required this.isMeritImproved,
    required this.hasEnoughData,
  });
}

/// Derived provider calculating improvement indicators comparing the latest 2 exams.
final performanceImprovementProvider = Provider<PerformanceImprovement>((ref) {
  final records = ref.watch(examRecordsProvider);

  if (records.length < 2) {
    return const PerformanceImprovement(
      marksDelta: 0,
      meritDelta: 0,
      isMarksImproved: false,
      isMeritImproved: false,
      hasEnoughData: false,
    );
  }

  final sorted = List<ExamRecord>.from(records)..sort((a, b) => a.date.compareTo(b.date));
  final latest = sorted[sorted.length - 1];
  final previous = sorted[sorted.length - 2];

  final marksDiff = latest.marks - previous.marks;
  final meritDiff = previous.meritPosition - latest.meritPosition;

  return PerformanceImprovement(
    marksDelta: marksDiff,
    meritDelta: meritDiff,
    isMarksImproved: marksDiff >= 0,
    isMeritImproved: meritDiff >= 0,
    hasEnoughData: true,
  );
});`,

  'lib/screens/performance_screen.dart': `import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/performance_models.dart';
import '../providers/performance_provider.dart';

/// Screen for tracking engineering admission exam performances & target countdowns.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearestExam = ref.watch(nearestUpcomingExamProvider);
    final examRecords = ref.watch(examRecordsProvider);
    final improvement = ref.watch(performanceImprovementProvider);

    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const accentColor = Color(0xFF38BDF8);
    const emeraldColor = Color(0xFF34D399);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Screen Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Performance Tracker',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Monitor exam marks, merit ranks & exam dates',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accentColor.withOpacity(0.25)),
                    ),
                    child: const Icon(Icons.analytics_rounded, color: accentColor, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // PART A: Countdown Banner Card
              _buildCountdownBanner(context, ref, nearestExam, cardColor, accentColor),
              const SizedBox(height: 24),

              // Improvement Indicator Summary Card
              if (examRecords.length >= 2) ...[
                _buildImprovementIndicatorCard(improvement, cardColor, emeraldColor, accentColor),
                const SizedBox(height: 24),
              ],

              // PART B: Performance Analytics Section
              if (examRecords.isEmpty)
                _buildEmptyStateCard(context, ref, cardColor)
              else ...[
                // Marks Trend Line Chart
                _buildMarksTrendChart(examRecords, cardColor, accentColor),
                const SizedBox(height: 24),

                // Merit Position Trend Line Chart (Inverted Y-axis)
                _buildMeritTrendChart(examRecords, cardColor, emeraldColor),
                const SizedBox(height: 24),

                // Past Exam History List
                _buildExamHistoryList(context, ref, examRecords, cardColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}`,

  'lib/screens/home_dashboard.dart': `import 'package:flutter/material.dart';
import 'help_screen.dart';
import 'profile_screen.dart';

/// Home Dashboard Screen for Chondrobindu engineering prep app.
class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const accentColor = Color(0xFF38BDF8);
    const orangeColor = Color(0xFFF97316);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: const [
            Text(
              'Chondrobindu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(width: 6),
            Text(
              '::',
              style: TextStyle(
                color: accentColor,
                fontSize: 18,
                fontWeight: FontWeight.extrabold,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: cardColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70, size: 20),
              onPressed: () {},
              tooltip: 'Notifications',
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
              child: CircleAvatar(
                radius: 18,
                backgroundColor: accentColor.withOpacity(0.2),
                child: const Text(
                  'R',
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Welcome Section
              _buildWelcomeHeader(),
              const SizedBox(height: 24),

              // 2. Summary Cards (Row with Expanded)
              _buildSummaryCards(cardColor, accentColor, orangeColor),
              const SizedBox(height: 20),

              // 3. Quote Card (Pelé Quote)
              _buildPeleQuoteCard(cardColor, accentColor),
              const SizedBox(height: 20),

              // 4. Upcoming Exam Card
              _buildUpcomingExamCard(cardColor, accentColor),
              const SizedBox(height: 20),

              // 5. Quick Access Buttons (Row with 2 Expanded buttons)
              _buildQuickAccessRow(cardColor, accentColor),
              const SizedBox(height: 40), // 6. Bottom Padding
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Welcome Section
  Widget _buildWelcomeHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Text(
                  'Good morning, Rafid',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  '👋',
                  style: TextStyle(fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ready for your engineering prep?',
              style: TextStyle(
                color: Colors.slate.shade400,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70),
            onPressed: () {},
            tooltip: 'Notifications',
          ),
        ),
      ],
    );
  }

  /// 2. Summary Cards (Inside a Row using Expanded)
  Widget _buildSummaryCards(Color cardColor, Color accentColor, Color orangeColor) {
    return Row(
      children: [
        // Card 1: Today's Focus
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: accentColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Today's Focus",
                      style: TextStyle(
                        color: Colors.slate.shade400,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '2h 15m',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Target: 4h 00m',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 14),

        // Card 2: Streak
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department_rounded, color: orangeColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Streak',
                      style: TextStyle(
                        color: Colors.slate.shade400,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '4 Days',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Personal Best: 12d',
                  style: TextStyle(
                    color: orangeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 3. Quote Card: Pelé quote
  Widget _buildPeleQuoteCard(Color cardColor, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: accentColor.withOpacity(0.25)),
        gradient: LinearGradient(
          colors: [
            cardColor,
            const Color(0xFF0F2B48).withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, color: accentColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '"Success is no accident. It is hard work, perseverance, learning, studying, sacrifice and most of all, love of what you are doing or learning to do."',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '— Pelé',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4. Upcoming Exam: BUET Admission
  Widget _buildUpcomingExamCard(Color cardColor, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        gradient: LinearGradient(
          colors: [
            cardColor,
            const Color(0xFF1E3A5F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.school_rounded, color: accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'BUET Admission',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withOpacity(0.4)),
                ),
                child: Text(
                  'Target #1',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '45',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 36,
                  fontWeight: FontWeight.extrabold,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Days Remaining',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: 0.65,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Syllabus Covered: 65%',
                style: TextStyle(color: Colors.slate.shade400, fontSize: 11.5),
              ),
              Text(
                'Exam Date: Target 2026',
                style: TextStyle(color: Colors.slate.shade400, fontSize: 11.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 5. Quick Access Row with 2 Expanded buttons
  Widget _buildQuickAccessRow(Color cardColor, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // Button 1: Resume Study
            Expanded(
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(16.0),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {},
                  splashColor: accentColor.withOpacity(0.15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: accentColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resume Study',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Physics',
                                style: TextStyle(
                                  color: Colors.slate.shade400,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Button 2: Log Score
            Expanded(
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(16.0),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {},
                  splashColor: const Color(0xFFA78BFA).withOpacity(0.15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA78BFA).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.insert_chart_outlined_rounded,
                            color: Color(0xFFA78BFA),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Log Score',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Mock Test',
                                style: TextStyle(
                                  color: Colors.slate.shade400,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
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
      ],
    );
  }
}
`,

  'lib/screens/profile_screen.dart': `import 'package:flutter/material.dart';
import 'help_screen.dart';

/// Profile Screen for Chondrobindu engineering prep app.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;

  String _primaryTarget = 'Engineering (BUET / CKRUET)';
  String _secondaryTarget = 'Versity A Unit (DU / JU)';

  final List<String> _primaryTargetOptions = [
    'Engineering (BUET / CKRUET)',
    'Medical (DMCH / Medical Colleges)',
    'Versity A Unit (DU Science)',
    'IUT / MIST Special'
  ];

  final List<String> _secondaryTargetOptions = [
    'Versity A Unit (DU / JU)',
    'CKRUET (CUET, KUET, RUET)',
    'Agricultural Universities',
    'General Public Universities'
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: 'Rafid Ahmed');
    _emailController = TextEditingController(text: 'rafid@example.com');
    _phoneController = TextEditingController(text: '+8801700000000');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF38BDF8),
          behavior: SnackBarBehavior.floating,
          content: const Text(
            'Profile updated successfully!',
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const accentColor = Color(0xFF38BDF8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar Section
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 46,
                      backgroundColor: accentColor.withOpacity(0.2),
                      child: const Text('R', style: TextStyle(color: accentColor, fontSize: 38, fontWeight: FontWeight.bold)),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: accentColor, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, size: 16, color: Color(0xFF0F172A)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text('Rafid Ahmed', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),

              // Fields & Save button
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.check_circle_rounded, size: 18),
                label: const Text('Save Changes'),
              ),
              const SizedBox(height: 20),

              // Help Tile
              ListTile(
                leading: const Icon(Icons.help_outline_rounded, color: accentColor),
                title: const Text('Help & Support', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const HelpScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
`,

  'lib/screens/syllabus_screen.dart': `import 'package:flutter/material.dart';

/// Syllabus Screen displaying interactive subjects, expanded chapters,
/// and section checkboxes with local StatefulWidget management.
class SyllabusScreen extends StatefulWidget {
  const SyllabusScreen({super.key});

  @override
  State<SyllabusScreen> createState() => _SyllabusScreenState();
}

class _SyllabusScreenState extends State<SyllabusScreen> {
  // 1. State Variables
  bool isMathExpanded = true;
  bool isPhysicsExpanded = false;
  bool isChemistryExpanded = false;

  // Map tracking individual study section checkbox states
  late Map<String, bool> checkboxStates;

  @override
  void initState() {
    super.initState();
    // Initialize default checkbox states for Higher Mathematics & Physics
    checkboxStates = {
      // Mathematics - Chapter 1: Matrices & Determinants
      'math_ch1_theory': true,
      'math_ch1_concept': true,
      'math_ch1_qb': true,
      'math_ch1_practice': false,

      // Mathematics - Chapter 2: Vector
      'math_ch2_theory': true,
      'math_ch2_concept': true,
      'math_ch2_qb': false,
      'math_ch2_practice': false,

      // Physics - Chapter 1: Vector Mechanics
      'phy_ch1_theory': true,
      'phy_ch1_qb': true,
      'phy_ch1_practice': false,

      // Chemistry - Chapter 1: Qualitative Chemistry
      'chem_ch1_theory': false,
      'chem_ch1_qb': false,
    };
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const accentColor = Color(0xFF38BDF8);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2. Header Section
            _buildHeader(accentColor),

            // Subject List inside Expanded -> ListView to prevent overflow errors
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                children: [
                  // 3. Subject Card: Higher Mathematics
                  _buildSubjectCard(
                    title: 'Higher Mathematics',
                    subtitle: '75% Completed',
                    icon: Icons.menu_book_rounded,
                    isExpanded: isMathExpanded,
                    onToggle: () {
                      setState(() {
                        isMathExpanded = !isMathExpanded;
                      });
                    },
                    cardColor: cardColor,
                    accentColor: accentColor,
                    chapters: [
                      _buildChapterItem(
                        chapterTitle: 'Chapter 1: Matrices & Determinants',
                        sections: [
                          _SectionData('math_ch1_theory', 'Main Book Theory (Ketab Uddin)'),
                          _SectionData('math_ch1_concept', 'Concept Book Formulas'),
                          _SectionData('math_ch1_qb', 'BUET Question Bank (2010-2023)'),
                          _SectionData('math_ch1_practice', 'Practice Problem Sheet'),
                        ],
                        accentColor: accentColor,
                      ),
                      _buildChapterItem(
                        chapterTitle: 'Chapter 2: Vector',
                        sections: [
                          _SectionData('math_ch2_theory', 'Main Book Theory'),
                          _SectionData('math_ch2_concept', 'Formula Summary Sheet'),
                          _SectionData('math_ch2_qb', 'Question Bank Solve'),
                          _SectionData('math_ch2_practice', 'Model Test Questions'),
                        ],
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subject Card: Physics 1st Paper
                  _buildSubjectCard(
                    title: 'Physics 1st Paper',
                    subtitle: '50% Completed',
                    icon: Icons.bolt_rounded,
                    isExpanded: isPhysicsExpanded,
                    onToggle: () {
                      setState(() {
                        isPhysicsExpanded = !isPhysicsExpanded;
                      });
                    },
                    cardColor: cardColor,
                    accentColor: accentColor,
                    chapters: [
                      _buildChapterItem(
                        chapterTitle: 'Chapter 1: Vector Mechanics',
                        sections: [
                          _SectionData('phy_ch1_theory', 'Main Book Theory (Shahjahan Tapan)'),
                          _SectionData('phy_ch1_qb', 'Engineering Question Bank'),
                          _SectionData('phy_ch1_practice', 'Practice MCQ & CQ'),
                        ],
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Subject Card: Chemistry 1st Paper
                  _buildSubjectCard(
                    title: 'Chemistry 1st Paper',
                    subtitle: '0% Completed',
                    icon: Icons.science_rounded,
                    isExpanded: isChemistryExpanded,
                    onToggle: () {
                      setState(() {
                        isChemistryExpanded = !isChemistryExpanded;
                      });
                    },
                    cardColor: cardColor,
                    accentColor: accentColor,
                    chapters: [
                      _buildChapterItem(
                        chapterTitle: 'Chapter 1: Qualitative Chemistry',
                        sections: [
                          _SectionData('chem_ch1_theory', 'Main Book Theory (Hazari Nag)'),
                          _SectionData('chem_ch1_qb', 'Question Bank Solve'),
                        ],
                        accentColor: accentColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 40), // Bottom padding for navigation clearance
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2. Header Widget
  Widget _buildHeader(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20.0, 16.0, 20.0, 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Syllabus Tracker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Main Books & Question Banks',
                style: TextStyle(
                  color: Colors.slate.shade400,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: Text(
              'Engineering Prep',
              style: TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. Subject Card Widget
  Widget _buildSubjectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Color cardColor,
    required Color accentColor,
    required List<Widget> chapters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isExpanded ? accentColor.withOpacity(0.4) : Colors.white.withOpacity(0.06),
          width: isExpanded ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header ListTile wrapped in InkWell to toggle expansion
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16.0),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                title: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.slate.shade400,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                trailing: Icon(
                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  color: Colors.slate.shade400,
                  size: 26,
                ),
              ),
            ),
          ),

          // 4. Expanded Content (Chapters & Sections)
          if (isExpanded) ...[
            Divider(height: 1, color: Colors.white.withOpacity(0.08)),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: chapters,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Chapter Container Item
  Widget _buildChapterItem({
    required String chapterTitle,
    required List<_SectionData> sections,
    required Color accentColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chapter Title
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0, top: 2.0),
            child: Text(
              chapterTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          // 5. Checkboxes (Study Sections)
          ...sections.map((section) {
            final isChecked = checkboxStates[section.key] ?? false;

            return Theme(
              data: ThemeData.dark().copyWith(
                unselectedWidgetColor: Colors.slate.shade500,
              ),
              child: CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                activeColor: accentColor,
                checkColor: const Color(0xFF0F172A),
                value: isChecked,
                onChanged: (bool? value) {
                  setState(() {
                    checkboxStates[section.key] = value ?? false;
                  });
                },
                title: Text(
                  section.label,
                  style: TextStyle(
                    color: isChecked ? Colors.slate.shade400 : Colors.white,
                    fontSize: 12.5,
                    decoration: isChecked ? TextDecoration.lineThrough : TextDecoration.none,
                    decorationColor: Colors.slate.shade400,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Helper model for study section keys and labels
class _SectionData {
  final String key;
  final String label;

  _SectionData(this.key, this.label);
}`,

  'lib/screens/main_nav.dart': `import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/nav_provider.dart';
import 'home_dashboard.dart';
import 'syllabus_screen.dart';
import 'timer_screen.dart';
import 'performance_screen.dart';
import 'insights_screen.dart';

class MainNavigationScreen extends ConsumerWidget {
  const MainNavigationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(navigationIndexProvider);

    final List<Widget> screens = [
      const HomeDashboardScreen(),
      const SyllabusScreen(),
      const TimerScreen(),
      const PerformanceScreen(),
      const InsightsScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(
        index: selectedIndex < screens.length ? selectedIndex : 0,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex < screens.length ? selectedIndex : 0,
        onDestinationSelected: (index) {
          ref.read(navigationIndexProvider.notifier).state = index;
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), label: 'Syllabus'),
          NavigationDestination(icon: Icon(Icons.timer_outlined), label: 'Timer'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'Exams'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), label: 'Insights'),
        ],
      ),
    );
  }
}`,

  'lib/models/analytics_models.dart': `class StudySessionLog {
  final String id;
  final DateTime date;
  final int durationInMinutes;
  final String subjectId;
  final String subjectName;

  const StudySessionLog({
    required this.id,
    required this.date,
    required this.durationInMinutes,
    required this.subjectId,
    this.subjectName = 'General Study',
  });
}`,

  'lib/providers/analytics_provider.dart': `import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/analytics_models.dart';

final studyLogsProvider = StateProvider<List<StudySessionLog>>((ref) => []);`,

  'lib/screens/insights_screen.dart': `import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      body: Center(child: Text('Insights Dashboard', style: TextStyle(color: Colors.white))),
    );
  }
}`,

  'lib/screens/help_screen.dart': `import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Help & Support Screen with Material 3 Contact Form and Quick AI Tutor links.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController(text: 'Rafid Ahmed');
  final _emailController = TextEditingController(text: 'rafid@example.com');
  final _messageController = TextEditingController();

  String _contactMethod = 'Email';
  String _reason = 'Syllabus Query';

  final List<String> _contactMethods = ['Email', 'WhatsApp', 'Phone'];
  final List<String> _reasons = [
    'Syllabus Query',
    'Technical Issue',
    'Feature Request',
    'General Feedback',
    'Other'
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Opening $urlString...')),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opening $urlString...')),
        );
      }
    }
  }

  void _sendMessage() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFF38BDF8),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Message sent successfully! Our team will get back to you shortly.',
            style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
          ),
        ),
      );
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFF0F172A);
    const cardColor = Color(0xFF1E293B);
    const accentColor = Color(0xFF38BDF8);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Help & Support',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Contact Support',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'We usually reply within 2 hours',
                      style: TextStyle(
                        color: Colors.slate.shade400,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Full Name',
                      style: TextStyle(
                        color: Colors.slate.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: 'Enter your name',
                        hintStyle: TextStyle(color: Colors.slate.shade500),
                        prefixIcon: const Icon(Icons.person_outline_rounded, color: accentColor, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Preferred Contact Method',
                      style: TextStyle(
                        color: Colors.slate.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _contactMethod,
                      dropdownColor: cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        prefixIcon: const Icon(Icons.contact_phone_outlined, color: accentColor, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      items: _contactMethods.map((method) {
                        return DropdownMenuItem<String>(
                          value: method,
                          child: Text(method),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _contactMethod = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Email Address',
                      style: TextStyle(
                        color: Colors.slate.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: 'Enter your email',
                        hintStyle: TextStyle(color: Colors.slate.shade500),
                        prefixIcon: const Icon(Icons.email_outlined, color: accentColor, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty || !value.contains('@')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Reason for Reaching Out',
                      style: TextStyle(
                        color: Colors.slate.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _reason,
                      dropdownColor: cardColor,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        prefixIcon: const Icon(Icons.help_outline_rounded, color: accentColor, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      items: _reasons.map((reason) {
                        return DropdownMenuItem<String>(
                          value: reason,
                          child: Text(reason),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _reason = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your Message',
                      style: TextStyle(
                        color: Colors.slate.shade300,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _messageController,
                      maxLines: 4,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        hintText: 'Describe your query or suggestion in detail...',
                        hintStyle: TextStyle(color: Colors.slate.shade500),
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: accentColor),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your message';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _sendMessage,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text(
                          'Send Message',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA78BFA).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFA78BFA), size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick AI Tutors',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Instant problem solving & concept explanation',
                      style: TextStyle(
                        color: Colors.slate.shade400,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.2,
              children: [
                _buildAITutorCard(
                  name: 'Gemini AI',
                  subtitle: 'Google Workspace',
                  icon: Icons.sparkles,
                  color: const Color(0xFF38BDF8),
                  url: 'https://gemini.google.com',
                ),
                _buildAITutorCard(
                  name: 'ChatGPT',
                  subtitle: 'OpenAI GPT-4o',
                  icon: Icons.chat_bubble_outline_rounded,
                  color: const Color(0xFF34D399),
                  url: 'https://chatgpt.com',
                ),
                _buildAITutorCard(
                  name: 'Claude AI',
                  subtitle: 'Anthropic Sonnet',
                  icon: Icons.psychology_outlined,
                  color: const Color(0xFFF97316),
                  url: 'https://claude.ai',
                ),
                _buildAITutorCard(
                  name: 'Perplexity',
                  subtitle: 'Realtime Research',
                  icon: Icons.search_rounded,
                  color: const Color(0xFFA78BFA),
                  url: 'https://perplexity.ai',
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAITutorCard({
    required String name,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String url,
  }) {
    return Material(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _launchUrl(url),
        splashColor: color.withOpacity(0.15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.slate.shade400,
                        fontSize: 10.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, color: Colors.slate.shade500, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}`,
  'pubspec.yaml': `name: chondrobindu
description: "Distraction-free study companion for admission candidates in Bangladesh."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  google_fonts: ^6.2.1
  fl_chart: ^0.68.0
  cupertino_icons: ^1.0.6`,
};

export default function App() {
  const [activeTab, setActiveTab] = useState<number>(3); // Default to Tab 3 (Exams / Performance) to highlight Phase 5!
  const [activeViewMode, setActiveViewMode] = useState<'preview' | 'code'>('preview');
  const [selectedFile, setSelectedFile] = useState<keyof typeof DART_FILES>('lib/screens/performance_screen.dart');
  const [copied, setCopied] = useState<boolean>(false);
  const [emptyDataMode, setEmptyDataMode] = useState<boolean>(false);

  // Syllabus local state
  const [subjects, setSubjects] = useState([
    {
      id: 'subj_math',
      title: 'Higher Mathematics',
      isExpanded: true,
      chapters: [
        {
          id: 'math_ch1',
          title: 'Matrices & Determinants',
          sections: [
            { id: 'm1_s1', title: 'Main Book Theory (Ketab Uddin)', isCompleted: true },
            { id: 'm1_s2', title: 'Concept Book Formulas', isCompleted: true },
            { id: 'm1_s3', title: 'BUET Question Bank (2010-2023)', isCompleted: true },
            { id: 'm1_s4', title: 'Practice Problem Sheet', isCompleted: false },
          ],
        },
      ],
    },
  ]);

  const handleCopyCode = () => {
    navigator.clipboard.writeText(DART_FILES[selectedFile]);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <div className="min-h-screen bg-[#090D16] text-slate-100 flex flex-col font-sans selection:bg-[#38BDF8] selection:text-slate-900">
      {/* Top Header Bar */}
      <header className="border-b border-slate-800/80 bg-[#0F172A]/90 backdrop-blur px-6 py-3.5 flex items-center justify-between sticky top-0 z-50">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#38BDF8] to-blue-600 flex items-center justify-center text-slate-950 font-bold text-lg shadow-lg shadow-sky-500/20">
            চ
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="font-bold text-[#38BDF8] text-lg tracking-tight">Chondrobindu</h1>
              <span className="bg-sky-500/10 text-[#38BDF8] border border-sky-500/20 text-[10px] px-2 py-0.5 rounded-full font-semibold uppercase tracking-wider">
                Flutter Phase 5 (Performance Tracker & Exams)
              </span>
            </div>
            <p className="text-xs text-slate-400">Admission Companion • Material 3 Dark Theme</p>
          </div>
        </div>

        {/* View Mode Toggle: Interactive Phone Preview vs Dart Code Inspector */}
        <div className="flex items-center gap-2 bg-slate-900/90 border border-slate-800 p-1 rounded-xl">
          <button
            onClick={() => setActiveViewMode('preview')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
              activeViewMode === 'preview'
                ? 'bg-[#38BDF8] text-slate-950 shadow-md shadow-sky-500/20 font-semibold'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Smartphone className="w-3.5 h-3.5" />
            Live Flutter Simulator
          </button>
          <button
            onClick={() => setActiveViewMode('code')}
            className={`flex items-center gap-2 px-3.5 py-1.5 rounded-lg text-xs font-medium transition-all ${
              activeViewMode === 'code'
                ? 'bg-[#38BDF8] text-slate-950 shadow-md shadow-sky-500/20 font-semibold'
                : 'text-slate-400 hover:text-slate-200'
            }`}
          >
            <Code2 className="w-3.5 h-3.5" />
            Dart Code Files (.dart)
          </button>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col md:flex-row max-w-7xl w-full mx-auto p-4 md:p-6 gap-6">
        {activeViewMode === 'preview' ? (
          <div className="flex-1 flex flex-col lg:flex-row items-center justify-center gap-8 py-4">
            {/* Phone Device Mockup Frame */}
            <div className="w-[380px] h-[780px] bg-[#000000] rounded-[48px] p-3 shadow-2xl shadow-sky-500/10 border-4 border-slate-800 relative flex flex-col overflow-hidden ring-1 ring-slate-700/50">
              {/* Device Notch / Island */}
              <div className="absolute top-0 left-1/2 -translate-x-1/2 w-32 h-5 bg-black rounded-b-2xl z-40 flex items-center justify-center">
                <div className="w-12 h-1 bg-slate-800 rounded-full" />
              </div>

              {/* Status Bar */}
              <div className="pt-2 px-6 pb-1 text-[11px] text-slate-400 font-medium flex items-center justify-between z-30 select-none">
                <span>09:41</span>
                <div className="flex items-center gap-1.5">
                  <span className="text-[10px]">5G</span>
                  <div className="w-4 h-2 border border-slate-400 rounded-sm p-0.5 flex items-center">
                    <div className="w-full h-full bg-slate-300 rounded-2xs" />
                  </div>
                </div>
              </div>

              {/* Screen Canvas (Material 3 Dark Container #0F172A) */}
              <div className="flex-1 bg-[#0F172A] rounded-[36px] overflow-hidden flex flex-col relative">
                {/* Active Tab Screen */}
                <div className="flex-1 overflow-y-auto overflow-x-hidden scrollbar-thin scrollbar-thumb-slate-700 flex flex-col">
                  {activeTab === 0 && <FlutterHomeScreen />}
                  {activeTab === 1 && <FlutterSyllabusScreen subjects={subjects} />}
                  {activeTab === 2 && <FlutterTimerInteractiveScreen />}
                  {activeTab === 3 && <FlutterPerformanceInteractiveScreen emptyDataMode={emptyDataMode} />}
                  {activeTab === 4 && <FlutterInsightsInteractiveScreen emptyDataMode={emptyDataMode} />}
                </div>

                {/* Flutter Material 3 NavigationBar at Bottom (#1E293B) */}
                <div className="bg-[#1E293B] border-t border-slate-800/80 px-2 py-1.5 flex items-center justify-around z-30 select-none">
                  <NavTabItem
                    icon={<Home className="w-4 h-4" />}
                    label="Home"
                    active={activeTab === 0}
                    onClick={() => setActiveTab(0)}
                  />
                  <NavTabItem
                    icon={<BookOpen className="w-4 h-4" />}
                    label="Syllabus"
                    active={activeTab === 1}
                    onClick={() => setActiveTab(1)}
                  />
                  <NavTabItem
                    icon={<TimerIcon className="w-4 h-4" />}
                    label="Timer"
                    active={activeTab === 2}
                    onClick={() => setActiveTab(2)}
                  />
                  <NavTabItem
                    icon={<Activity className="w-4 h-4" />}
                    label="Exams"
                    active={activeTab === 3}
                    onClick={() => setActiveTab(3)}
                  />
                  <NavTabItem
                    icon={<BarChart2 className="w-4 h-4" />}
                    label="Insights"
                    active={activeTab === 4}
                    onClick={() => setActiveTab(4)}
                  />
                </div>
              </div>
            </div>

            {/* Right Information & Architecture Box */}
            <div className="flex-1 max-w-xl space-y-5">
              <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-5 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2 text-[#38BDF8] font-semibold text-sm">
                    <Sparkles className="w-4 h-4" />
                    <span>Phase 5 Performance Engine Overview</span>
                  </div>
                  {/* Empty state test button */}
                  <button
                    onClick={() => setEmptyDataMode(!emptyDataMode)}
                    className={`text-[11px] px-2.5 py-1 rounded-lg border font-medium transition-all ${
                      emptyDataMode
                        ? 'bg-amber-500/20 border-amber-500/40 text-amber-400'
                        : 'bg-slate-800 border-slate-700 text-slate-300 hover:text-white'
                    }`}
                  >
                    {emptyDataMode ? 'Show Sample Data' : 'Test Empty State'}
                  </button>
                </div>

                <p className="text-xs text-slate-300 leading-relaxed">
                  Phase 5 introduces <strong>Performance Tracker & Exams</strong> with Riverpod providers tracking upcoming admission test countdowns, score evolution line charts, merit rank trajectory (inverted Y-axis where better ranks climb higher), and improvement indicators comparing recent mock tests.
                </p>

                <div className="grid grid-cols-2 gap-3 text-xs">
                  <div className="bg-[#0F172A] p-3 rounded-xl border border-slate-800">
                    <p className="text-slate-400 font-medium">Target Countdown</p>
                    <p className="text-sky-400 font-bold mt-1">Nearest Exam Banner</p>
                  </div>
                  <div className="bg-[#0F172A] p-3 rounded-xl border border-slate-800">
                    <p className="text-slate-400 font-medium">Merit Rank Trend</p>
                    <p className="text-emerald-400 font-bold mt-1">Inverted fl_chart Line</p>
                  </div>
                </div>
              </div>

              {/* Screen Descriptions */}
              <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-5 space-y-3">
                <h3 className="text-sm font-semibold text-slate-200">Generated Phase 5 Files</h3>
                <div className="space-y-2 text-xs text-slate-300">
                  <div className="flex items-start gap-2.5 p-2 rounded-lg bg-[#0F172A]/60">
                    <FileText className="w-4 h-4 text-[#38BDF8] shrink-0 mt-0.5" />
                    <div>
                      <p className="font-mono text-sky-300 font-medium">lib/models/performance_models.dart</p>
                      <p className="text-slate-400 text-[11px] mt-0.5">ExamRecord and UpcomingExam data classes with daysRemaining getters.</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-2.5 p-2 rounded-lg bg-[#0F172A]/60">
                    <FileText className="w-4 h-4 text-[#38BDF8] shrink-0 mt-0.5" />
                    <div>
                      <p className="font-mono text-sky-300 font-medium">lib/providers/performance_provider.dart</p>
                      <p className="text-slate-400 text-[11px] mt-0.5">Riverpod state providers for upcoming exams, past records, and derived performance improvement indicators.</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-2.5 p-2 rounded-lg bg-[#0F172A]/60">
                    <FileText className="w-4 h-4 text-[#38BDF8] shrink-0 mt-0.5" />
                    <div>
                      <p className="font-mono text-sky-300 font-medium">lib/screens/performance_screen.dart</p>
                      <p className="text-slate-400 text-[11px] mt-0.5">Material 3 performance dashboard with countdown banner, LineChart trends, rank shift indicators, and dialog forms.</p>
                    </div>
                  </div>
                </div>

                <button
                  onClick={() => setActiveViewMode('code')}
                  className="w-full mt-2 py-2 px-3 bg-[#38BDF8]/10 hover:bg-[#38BDF8]/20 border border-[#38BDF8]/30 rounded-xl text-xs font-medium text-[#38BDF8] transition-colors flex items-center justify-center gap-2"
                >
                  <Code2 className="w-4 h-4" />
                  View & Copy All Phase 5 .dart Code
                </button>
              </div>
            </div>
          </div>
        ) : (
          /* Dart Code Inspector View */
          <div className="flex-1 flex flex-col md:flex-row gap-6">
            {/* Sidebar File Selector */}
            <div className="w-full md:w-64 bg-[#1E293B] border border-slate-800 rounded-2xl p-4 flex flex-col gap-2 shrink-0">
              <h2 className="text-xs font-bold text-slate-400 uppercase tracking-wider px-2 mb-1">
                Flutter Code Files
              </h2>
              {(Object.keys(DART_FILES) as Array<keyof typeof DART_FILES>).map((filePath) => (
                <button
                  key={filePath}
                  onClick={() => setSelectedFile(filePath)}
                  className={`flex items-center gap-2.5 px-3 py-2 rounded-xl text-xs font-mono transition-all text-left ${
                    selectedFile === filePath
                      ? 'bg-[#38BDF8]/15 text-[#38BDF8] font-bold border border-[#38BDF8]/30'
                      : 'text-slate-300 hover:bg-slate-800/80'
                  }`}
                >
                  <FileText className="w-4 h-4 shrink-0" />
                  <span className="truncate">{filePath}</span>
                </button>
              ))}
            </div>

            {/* Code View Canvas */}
            <div className="flex-1 bg-[#1E293B] border border-slate-800 rounded-2xl flex flex-col overflow-hidden">
              <div className="bg-[#0F172A] px-4 py-3 border-b border-slate-800 flex items-center justify-between">
                <span className="font-mono text-xs text-[#38BDF8] font-semibold">{selectedFile}</span>
                <button
                  onClick={handleCopyCode}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium transition-colors border border-slate-700"
                >
                  {copied ? (
                    <>
                      <Check className="w-3.5 h-3.5 text-emerald-400" />
                      <span className="text-emerald-400 font-semibold">Copied!</span>
                    </>
                  ) : (
                    <>
                      <Copy className="w-3.5 h-3.5 text-slate-400" />
                      <span>Copy Code</span>
                    </>
                  )}
                </button>
              </div>
              <pre className="p-4 text-xs font-mono text-slate-200 overflow-auto flex-1 leading-relaxed whitespace-pre font-normal selection:bg-sky-500/30">
                {DART_FILES[selectedFile]}
              </pre>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

// Mobile Bottom Nav Tab Item
function NavTabItem({
  icon,
  label,
  active,
  onClick
}: {
  icon: React.ReactNode;
  label: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex flex-col items-center gap-0.5 py-1 px-2 rounded-xl transition-all"
    >
      <div
        className={`p-1 rounded-full transition-all ${
          active ? 'bg-[#38BDF8]/20 text-[#38BDF8]' : 'text-slate-400 hover:text-slate-200'
        }`}
      >
        {icon}
      </div>
      <span
        className={`text-[10px] font-medium transition-colors ${
          active ? 'text-[#38BDF8] font-semibold' : 'text-slate-400'
        }`}
      >
        {label}
      </span>
    </button>
  );
}

// 5. Interactive Performance Screen Component for Web Simulator
function FlutterPerformanceInteractiveScreen({ emptyDataMode }: { emptyDataMode: boolean }) {
  const [selectedDay, setSelectedDay] = useState(14);
  const [showScheduleModal, setShowScheduleModal] = useState(false);
  const [showLogModal, setShowLogModal] = useState(false);
  const [selectedExamOptions, setSelectedExamOptions] = useState<any>(null);

  // Scheduled exams state
  const [upcomingExams, setUpcomingExams] = useState([
    { id: 'ex_1', name: 'BUET Weekly Model Test', subject: 'Higher Math', day: 14, recurring: 'Weekly 1/4', groupId: 'grp_buet' },
    { id: 'ex_2', name: 'BUET Weekly Model Test', subject: 'Higher Math', day: 21, recurring: 'Weekly 2/4', groupId: 'grp_buet' },
    { id: 'ex_3', name: 'BUET Weekly Model Test', subject: 'Higher Math', day: 28, recurring: 'Weekly 3/4', groupId: 'grp_buet' },
    { id: 'ex_4', name: 'CKRUET Combined Grand Test', subject: 'Physics & Chem', day: 18, recurring: null, groupId: null },
  ]);

  const [records, setRecords] = useState(
    emptyDataMode
      ? []
      : [
          { id: 'rec_1', name: 'Paper Final 01', marks: 68.0, merit: 185, date: '28 days ago' },
          { id: 'rec_2', name: 'Paper Final 02', marks: 74.5, merit: 120, date: '21 days ago' },
          { id: 'rec_3', name: 'Model Test 01', marks: 79.0, merit: 84, date: '14 days ago' },
          { id: 'rec_4', name: 'Mock Test 1', marks: 85.5, merit: 42, date: '7 days ago' },
          { id: 'rec_5', name: 'Mock Test 2', marks: 89.0, merit: 28, date: 'Yesterday' },
        ]
  );

  // Form states
  const [schedName, setSchedName] = useState('Central Engineering Test');
  const [schedSubj, setSchedSubj] = useState('Higher Mathematics');
  const [schedRecurring, setSchedRecurring] = useState('Weekly');
  const [schedCount, setSchedCount] = useState('4');

  const [logName, setLogName] = useState('BUET Model Test');
  const [logMarks, setLogMarks] = useState('88.5');
  const [logMerit, setLogMerit] = useState('32');

  const selectedDayExams = upcomingExams.filter((e) => e.day === selectedDay);

  const handleSaveSchedule = () => {
    if (!schedName) return;
    const count = parseInt(schedCount) || 1;
    const newExams = [];
    const grp = schedRecurring !== 'None' ? `grp_${Date.now()}` : null;

    for (let i = 0; i < count; i++) {
      const targetDay = (selectedDay + (schedRecurring === 'Weekly' ? i * 7 : i * 30)) % 31 + 1;
      newExams.push({
        id: `ex_${Date.now()}_${i}`,
        name: schedName,
        subject: schedSubj,
        day: targetDay,
        recurring: schedRecurring !== 'None' ? `${schedRecurring} ${i + 1}/${count}` : null,
        groupId: grp,
      });
    }

    setUpcomingExams([...upcomingExams, ...newExams]);
    setShowScheduleModal(false);
  };

  const handleAddResult = () => {
    if (!logName) return;
    const item = {
      id: `rec_${Date.now()}`,
      name: logName,
      marks: parseFloat(logMarks) || 80,
      merit: parseInt(logMerit) || 50,
      date: 'Just now',
    };
    setRecords([item, ...records]);
    setShowLogModal(false);
  };

  const handleDeleteGroup = (groupId: string) => {
    setUpcomingExams(upcomingExams.filter((e) => e.groupId !== groupId));
    setSelectedExamOptions(null);
  };

  const handleDeleteSingle = (id: string) => {
    setUpcomingExams(upcomingExams.filter((e) => e.id !== id));
    setSelectedExamOptions(null);
  };

  return (
    <div className="p-4 space-y-4">
      {/* Header with Schedule Button */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight">Exam Calendar & Tracker</h2>
          <p className="text-xs text-slate-400 mt-0.5">Visual calendar, recurring tests & scores</p>
        </div>
        <button
          onClick={() => setShowScheduleModal(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-[#38BDF8] text-slate-950 font-bold rounded-xl text-xs hover:bg-sky-300 transition-colors shadow-md shadow-sky-500/20"
        >
          <Plus className="w-3.5 h-3.5" />
          Schedule
        </button>
      </div>

      {/* Visual Table Calendar Component */}
      <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-3">
        <div className="flex items-center justify-between text-xs text-white font-bold">
          <div className="flex items-center gap-2">
            <Calendar className="w-4 h-4 text-[#38BDF8]" />
            <span>August 2026</span>
          </div>
          <span className="text-[10px] text-slate-400 font-normal">Tap day to filter</span>
        </div>

        {/* Days Grid */}
        <div className="grid grid-cols-7 gap-1 text-center">
          {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d, i) => (
            <span key={i} className="text-[10px] font-bold text-slate-500 py-1">
              {d}
            </span>
          ))}
          {Array.from({ length: 31 }, (_, i) => i + 1).map((dayNum) => {
            const isSelected = selectedDay === dayNum;
            const hasExam = upcomingExams.some((e) => e.day === dayNum);

            return (
              <button
                key={dayNum}
                onClick={() => setSelectedDay(dayNum)}
                className={`h-7 rounded-lg text-xs font-medium relative flex items-center justify-center transition-all ${
                  isSelected
                    ? 'bg-[#38BDF8] text-slate-950 font-bold shadow-sm'
                    : 'bg-slate-900/60 text-slate-300 hover:bg-slate-800'
                }`}
              >
                <span>{dayNum}</span>
                {hasExam && (
                  <span
                    className={`absolute bottom-0.5 w-1 h-1 rounded-full ${
                      isSelected ? 'bg-slate-950' : 'bg-amber-400'
                    }`}
                  />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Selected Day Schedule Banner */}
      <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3 space-y-2">
        <div className="flex items-center justify-between text-xs font-bold text-white">
          <span className="text-[#38BDF8]">Schedule for August {selectedDay}, 2026</span>
          <span className="text-[10px] text-slate-400">{selectedDayExams.length} Exams</span>
        </div>
        {selectedDayExams.length > 0 ? (
          <div className="space-y-1.5 pt-1">
            {selectedDayExams.map((ex) => (
              <div key={ex.id} className="flex items-center justify-between text-xs bg-[#0F172A] p-2 rounded-xl border border-slate-800">
                <div className="flex items-center gap-2">
                  <div className="w-1.5 h-1.5 rounded-full bg-[#38BDF8]" />
                  <span className="text-white font-medium">{ex.name}</span>
                </div>
                <span className="text-[10px] text-slate-400">{ex.subject}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-xs text-slate-500 italic pt-1">No exams scheduled for this date.</p>
        )}
      </div>

      {/* Upcoming Exam Cards List with Recurring Badges */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-xs font-bold text-white">Upcoming Target Tests</span>
          <span className="text-[10px] text-slate-400">{upcomingExams.length} total</span>
        </div>
        {upcomingExams.map((ex) => (
          <div key={ex.id} className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3 flex items-center justify-between">
            <div>
              <div className="flex items-center gap-2">
                <h4 className="text-xs font-bold text-white">{ex.name}</h4>
                {ex.recurring && (
                  <span className="bg-amber-500/15 border border-amber-500/30 text-amber-400 text-[9px] px-1.5 py-0.5 rounded-md font-bold">
                    {ex.recurring}
                  </span>
                )}
              </div>
              <p className="text-[10px] text-slate-400 mt-0.5">
                {ex.subject} • Target: Aug {ex.day}, 2026
              </p>
            </div>
            <button
              onClick={() => setSelectedExamOptions(ex)}
              className="p-1.5 text-slate-400 hover:text-white"
            >
              <Settings2 className="w-4 h-4" />
            </button>
          </div>
        ))}
      </div>

      {/* Improvement Indicator */}
      {!emptyDataMode && records.length >= 2 && (
        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-2">
          <div className="flex items-center justify-between text-xs font-bold text-white">
            <div className="flex items-center gap-1.5">
              <TrendingUp className="w-4 h-4 text-emerald-400" />
              <span>Improvement Indicator</span>
            </div>
            <span className="text-[10px] text-slate-500 uppercase">vs last test</span>
          </div>
          <div className="grid grid-cols-2 gap-2 pt-1">
            <div className="bg-emerald-500/10 border border-emerald-500/20 p-2.5 rounded-xl">
              <span className="text-[10px] text-slate-400 block">Marks Shift</span>
              <div className="flex items-center gap-1 text-emerald-400 font-bold text-sm mt-0.5">
                <ArrowUpRight className="w-4 h-4" />
                <span>+3.5 pts</span>
              </div>
            </div>
            <div className="bg-emerald-500/10 border border-emerald-500/20 p-2.5 rounded-xl">
              <span className="text-[10px] text-slate-400 block">Merit Shift</span>
              <div className="flex items-center gap-1 text-emerald-400 font-bold text-sm mt-0.5">
                <ArrowUpRight className="w-4 h-4" />
                <span>+14 ranks</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Log Score Floating Button / Action */}
      <button
        onClick={() => setShowLogModal(true)}
        className="w-full py-2.5 bg-gradient-to-r from-sky-500 to-blue-600 text-slate-950 font-bold rounded-xl text-xs flex items-center justify-center gap-2 shadow-lg shadow-sky-500/20"
      >
        <CheckCircle className="w-4 h-4" />
        Log Exam Result Score
      </button>

      {/* Schedule Modal */}
      {showScheduleModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-xs z-50 flex items-center justify-center p-4">
          <div className="bg-[#1E293B] border border-slate-700 rounded-2xl p-5 w-full max-w-xs space-y-3">
            <h3 className="text-sm font-bold text-white">Schedule New Exam</h3>
            <input
              type="text"
              value={schedName}
              onChange={(e) => setSchedName(e.target.value)}
              placeholder="Exam Name"
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
            />
            <input
              type="text"
              value={schedSubj}
              onChange={(e) => setSchedSubj(e.target.value)}
              placeholder="Subject"
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
            />
            <div>
              <label className="text-[10px] text-slate-400 font-bold block mb-1">RECURRING TYPE</label>
              <div className="grid grid-cols-3 gap-1">
                {['None', 'Weekly', 'Monthly'].map((type) => (
                  <button
                    key={type}
                    onClick={() => setSchedRecurring(type)}
                    className={`py-1.5 rounded-lg text-xs font-bold transition-all ${
                      schedRecurring === type ? 'bg-[#38BDF8] text-slate-950' : 'bg-[#0F172A] text-slate-400'
                    }`}
                  >
                    {type}
                  </button>
                ))}
              </div>
            </div>
            {schedRecurring !== 'None' && (
              <input
                type="text"
                value={schedCount}
                onChange={(e) => setSchedCount(e.target.value)}
                placeholder="Number of Occurrences (e.g. 4)"
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
              />
            )}
            <div className="flex items-center justify-end gap-2 pt-2">
              <button onClick={() => setShowScheduleModal(false)} className="px-3 py-1.5 text-xs text-slate-400 hover:text-white">
                Cancel
              </button>
              <button onClick={handleSaveSchedule} className="px-3 py-1.5 bg-[#38BDF8] text-slate-950 font-bold rounded-xl text-xs">
                Save Exams
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Options BottomSheet Modal */}
      {selectedExamOptions && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-xs z-50 flex items-end justify-center">
          <div className="bg-[#1E293B] border-t border-slate-700 rounded-t-2xl p-5 w-full space-y-3 animate-in slide-in-from-bottom">
            <h3 className="text-sm font-bold text-white">{selectedExamOptions.name}</h3>
            <p className="text-xs text-slate-400">Manage scheduled target exam instance</p>
            <div className="space-y-2 pt-2">
              <button
                onClick={() => handleDeleteSingle(selectedExamOptions.id)}
                className="w-full py-2 bg-rose-500/10 border border-rose-500/20 text-rose-400 font-bold rounded-xl text-xs text-left px-3"
              >
                Delete This Instance Only
              </button>
              {selectedExamOptions.groupId && (
                <button
                  onClick={() => handleDeleteGroup(selectedExamOptions.groupId)}
                  className="w-full py-2 bg-rose-500/20 border border-rose-500/40 text-rose-300 font-bold rounded-xl text-xs text-left px-3"
                >
                  Delete Entire Recurring Series ({selectedExamOptions.recurring})
                </button>
              )}
              <button onClick={() => setSelectedExamOptions(null)} className="w-full py-2 bg-slate-800 text-slate-300 font-bold rounded-xl text-xs">
                Close
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Log Modal */}
      {showLogModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-xs z-50 flex items-center justify-center p-4">
          <div className="bg-[#1E293B] border border-slate-700 rounded-2xl p-5 w-full max-w-xs space-y-3">
            <h3 className="text-sm font-bold text-white">Log Exam Result</h3>
            <input
              type="text"
              value={logName}
              onChange={(e) => setLogName(e.target.value)}
              placeholder="Exam Name"
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
            />
            <div className="grid grid-cols-2 gap-2">
              <input
                type="text"
                value={logMarks}
                onChange={(e) => setLogMarks(e.target.value)}
                placeholder="Marks"
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
              />
              <input
                type="text"
                value={logMerit}
                onChange={(e) => setLogMerit(e.target.value)}
                placeholder="Merit Rank"
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white"
              />
            </div>
            <div className="flex items-center justify-end gap-2 pt-2">
              <button onClick={() => setShowLogModal(false)} className="px-3 py-1.5 text-xs text-slate-400 hover:text-white">
                Cancel
              </button>
              <button onClick={handleAddResult} className="px-3 py-1.5 bg-[#38BDF8] text-slate-950 font-bold rounded-xl text-xs">
                Save Result
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// 4. Interactive Insights Screen Component for Web Simulator
function FlutterInsightsInteractiveScreen({ emptyDataMode }: { emptyDataMode: boolean }) {
  const weeklyData = emptyDataMode
    ? [
        { day: 'Mon', mins: 0 },
        { day: 'Tue', mins: 0 },
        { day: 'Wed', mins: 0 },
        { day: 'Thu', mins: 0 },
        { day: 'Fri', mins: 0 },
        { day: 'Sat', mins: 0 },
        { day: 'Sun', mins: 0 },
      ]
    : [
        { day: 'Mon', mins: 45 },
        { day: 'Tue', mins: 75 },
        { day: 'Wed', mins: 50 },
        { day: 'Thu', mins: 90 },
        { day: 'Fri', mins: 0 },
        { day: 'Sat', mins: 60 },
        { day: 'Sun', mins: 75 },
      ];

  const subjectDist = emptyDataMode
    ? []
    : [
        { name: 'Higher Math', percent: 42, color: '#38BDF8' },
        { name: 'Physics', percent: 31, color: '#34D399' },
        { name: 'Chemistry', percent: 18, color: '#F59E0B' },
        { name: 'English & BUA', percent: 9, color: '#A855F7' },
      ];

  const hasWeekly = weeklyData.some(d => d.mins > 0);
  const maxMins = Math.max(100, ...weeklyData.map(d => d.mins));

  return (
    <div className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight">Performance Insights</h2>
          <p className="text-xs text-slate-400 mt-0.5">Study consistency & subject focus</p>
        </div>
        <div className="p-2 bg-[#38BDF8]/15 border border-[#38BDF8]/30 rounded-xl text-[#38BDF8]">
          <BarChart3 className="w-5 h-5" />
        </div>
      </div>

      {/* Top Cards */}
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-xs text-slate-400 font-medium">Current Streak</span>
            <Flame className="w-4 h-4 text-amber-500" />
          </div>
          <div className="text-xl font-bold text-white tracking-tight">
            {emptyDataMode ? '0 Days' : '4 Days'}
          </div>
          <p className="text-[10px] text-amber-500">
            {emptyDataMode ? 'Start your streak today' : 'Keep the momentum going!'}
          </p>
        </div>

        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-2">
          <div className="flex items-center justify-between">
            <span className="text-xs text-slate-400 font-medium">Avg Focus</span>
            <TimerIcon className="w-4 h-4 text-[#38BDF8]" />
          </div>
          <div className="text-xl font-bold text-white tracking-tight">
            {emptyDataMode ? '0 Mins' : '56 Mins'}
          </div>
          <p className="text-[10px] text-sky-400">Last 7 days average</p>
        </div>
      </div>

      {/* Weekly Trend Bar Chart */}
      <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-4 space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-bold text-white">Weekly Study Trend</span>
          <span className="text-[11px] text-slate-400">Last 7 Days</span>
        </div>

        {!hasWeekly ? (
          <div className="py-8 flex flex-col items-center justify-center text-slate-500 space-y-2">
            <BarChart2 className="w-8 h-8 opacity-40" />
            <p className="text-xs text-slate-400">No study data logged for this week yet.</p>
          </div>
        ) : (
          <div className="pt-2">
            <div className="h-32 flex items-end justify-between gap-2 px-1">
              {weeklyData.map((d, i) => {
                const heightPct = Math.max(8, (d.mins / maxMins) * 100);
                return (
                  <div key={i} className="flex-1 flex flex-col items-center gap-1.5 h-full justify-end">
                    <div className="w-full bg-slate-800/80 rounded-t-lg h-full flex items-end overflow-hidden">
                      <div
                        style={{ height: `${heightPct}%` }}
                        className="w-full bg-[#38BDF8] rounded-t-lg transition-all duration-500 hover:brightness-110"
                        title={`${d.day}: ${d.mins} min`}
                      />
                    </div>
                    <span className="text-[10px] text-slate-400 font-medium">{d.day}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* Subject Distribution Pie Chart Section */}
      <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-4 space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-xs font-bold text-white">Subject Focus Breakdown</span>
          <span className="text-[11px] text-slate-400">Last 30 Days</span>
        </div>

        {subjectDist.length === 0 ? (
          <div className="py-8 flex flex-col items-center justify-center text-slate-500 space-y-2">
            <PieIcon className="w-8 h-8 opacity-40" />
            <p className="text-xs text-slate-400">No subject focus records available yet.</p>
          </div>
        ) : (
          <div className="flex items-center gap-4 pt-1">
            {/* Doughnut SVG representation */}
            <div className="relative w-28 h-28 shrink-0 flex items-center justify-center">
              <svg className="w-full h-full transform -rotate-90" viewBox="0 0 36 36">
                <path
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  fill="none"
                  stroke="#38BDF8"
                  strokeWidth="4"
                  strokeDasharray="42, 100"
                />
                <path
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  fill="none"
                  stroke="#34D399"
                  strokeWidth="4"
                  strokeDasharray="31, 100"
                  strokeDashoffset="-42"
                />
                <path
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  fill="none"
                  stroke="#F59E0B"
                  strokeWidth="4"
                  strokeDasharray="18, 100"
                  strokeDashoffset="-73"
                />
                <path
                  d="M18 2.0845 a 15.9155 15.9155 0 0 1 0 31.831 a 15.9155 15.9155 0 0 1 0 -31.831"
                  fill="none"
                  stroke="#A855F7"
                  strokeWidth="4"
                  strokeDasharray="9, 100"
                  strokeDashoffset="-91"
                />
              </svg>
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-[10px] font-bold text-slate-300">30 Days</span>
              </div>
            </div>

            {/* Legend */}
            <div className="flex-1 space-y-1.5">
              {subjectDist.map((item, idx) => (
                <div key={idx} className="flex items-center justify-between text-xs">
                  <div className="flex items-center gap-2">
                    <span className="w-2 h-2 rounded-full" style={{ backgroundColor: item.color }} />
                    <span className="text-slate-200 text-[11px]">{item.name}</span>
                  </div>
                  <span className="text-slate-400 font-bold text-[11px]">{item.percent}%</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// 3. Interactive Timer Screen for Web Simulator
function FlutterTimerInteractiveScreen() {
  const [targetMins, setTargetMins] = useState<number>(25);
  const [elapsedSecs, setElapsedSecs] = useState<number>(0);
  const [isRunning, setIsRunning] = useState<boolean>(false);
  const [mode, setMode] = useState<'focus' | 'break' | 'overtime'>('focus');
  const [accumulatedBreak, setAccumulatedBreak] = useState<number>(0);

  useEffect(() => {
    let timer: any = null;
    if (isRunning) {
      timer = setInterval(() => {
        setElapsedSecs(prev => {
          const next = prev + 1;
          const targetSecs = targetMins * 60;
          if (mode === 'focus' && next >= targetSecs) {
            setMode('overtime');
          }
          if (mode === 'break' && next >= targetSecs) {
            setIsRunning(false);
          }
          return next;
        });
      }, 1000);
    } else {
      clearInterval(timer);
    }
    return () => clearInterval(timer);
  }, [isRunning, targetMins, mode]);

  const targetSecs = targetMins * 60;
  const remainingOrOvertime =
    mode === 'overtime' ? elapsedSecs - targetSecs : Math.max(0, targetSecs - elapsedSecs);

  const displayMinutes = String(Math.floor(remainingOrOvertime / 60)).padStart(2, '0');
  const displaySeconds = String(remainingOrOvertime % 60).padStart(2, '0');
  const formattedDisplay = mode === 'overtime' ? `+${displayMinutes}:${displaySeconds}` : `${displayMinutes}:${displaySeconds}`;

  const progressRatio = targetSecs > 0 ? Math.min(1, elapsedSecs / targetSecs) : 0;
  const currentColor =
    mode === 'overtime' ? '#F97316' : mode === 'break' ? '#34D399' : '#38BDF8';

  // Continuous break calculation: 5 mins break for every 25 mins focus
  const earnedBreakSeconds = mode === 'break' ? accumulatedBreak : Math.floor(elapsedSecs / 5);
  const earnedMins = Math.floor(earnedBreakSeconds / 60);
  const earnedSecs = String(earnedBreakSeconds % 60).padStart(2, '0');

  const handleStartPause = () => setIsRunning(!isRunning);

  const handleReset = () => {
    setIsRunning(false);
    setElapsedSecs(0);
    setMode('focus');
  };

  const handleFinishSession = () => {
    setIsRunning(false);
    const breakTarget = earnedBreakSeconds > 0 ? earnedBreakSeconds : 300;
    setAccumulatedBreak(breakTarget);
    setTargetMins(Math.max(1, Math.round(breakTarget / 60)));
    setElapsedSecs(0);
    setMode('break');
    setIsRunning(true);
  };

  const adjustTarget = (delta: number) => {
    setTargetMins(prev => Math.max(5, Math.min(180, prev + delta)));
  };

  return (
    <div className="flex-1 flex flex-col justify-between p-4 text-center">
      <div className="flex items-center justify-between text-left">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight">
            {mode === 'break' ? 'Short Break' : mode === 'overtime' ? 'Overtime Focus' : 'Focus Study Timer'}
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            {mode === 'overtime'
              ? 'Target reached! Counting overtime...'
              : mode === 'break'
              ? 'Rest your eyes & refresh'
              : 'Distraction-free study session'}
          </p>
        </div>
        <span
          className="px-2.5 py-1 rounded-xl text-[10px] font-bold tracking-wider"
          style={{
            backgroundColor: `${currentColor}20`,
            color: currentColor,
            border: `1px solid ${currentColor}40`
          }}
        >
          {mode.toUpperCase()}
        </span>
      </div>

      {/* Main Timer with +/- Adjust Buttons */}
      <div className="my-auto py-4 flex items-center justify-center gap-3">
        {mode !== 'break' && (
          <button
            onClick={() => adjustTarget(-5)}
            className="w-10 h-10 rounded-full bg-[#1E293B] border border-slate-700 hover:border-[#38BDF8] text-slate-200 flex items-center justify-center font-bold text-lg transition-all"
            title="Decrease 5 minutes"
          >
            -
          </button>
        )}

        <div className="relative w-48 h-48 flex items-center justify-center">
          <svg className="w-full h-full transform -rotate-90">
            <circle cx="96" cy="96" r="80" stroke="#1E293B" strokeWidth="8" fill="transparent" />
            <circle
              cx="96"
              cy="96"
              r="80"
              stroke={currentColor}
              strokeWidth="8"
              strokeDasharray={502}
              strokeDashoffset={502 * (1 - (mode === 'overtime' ? 1 : progressRatio))}
              strokeLinecap="round"
              fill="transparent"
              className="transition-all duration-300"
            />
          </svg>
          <div className="absolute inset-0 flex flex-col items-center justify-center">
            <span className="text-3xl font-extrabold text-white tracking-tight font-mono">
              {formattedDisplay}
            </span>
            <span className="text-xs text-slate-400 font-medium mt-1">
              {mode === 'overtime' ? 'Extra Focus Time' : mode === 'break' ? 'Break Remaining' : `Target: ${targetMins} min`}
            </span>
          </div>
        </div>

        {mode !== 'break' && (
          <button
            onClick={() => adjustTarget(5)}
            className="w-10 h-10 rounded-full bg-[#1E293B] border border-slate-700 hover:border-[#38BDF8] text-slate-200 flex items-center justify-center font-bold text-lg transition-all"
            title="Increase 5 minutes"
          >
            +
          </button>
        )}
      </div>

      {/* Earned Break Banner */}
      <div className="bg-[#1E293B]/80 border border-[#34D399]/30 rounded-xl py-2 px-3 flex items-center justify-center gap-2 text-xs mb-3">
        <Coffee className="w-4 h-4 text-[#34D399]" />
        <span className="text-slate-400">Earned Break:</span>
        <span className="font-bold text-[#34D399]">{earnedMins}m {earnedSecs}s</span>
      </div>

      {/* Action Buttons: Start/Pause + Finish Session */}
      <div className="flex items-center justify-center gap-2">
        {elapsedSecs > 0 && (
          <button
            onClick={handleReset}
            className="p-3 rounded-xl bg-[#1E293B] border border-slate-800 text-slate-400 hover:text-white transition-all"
            title="Reset"
          >
            <RotateCcw className="w-4 h-4" />
          </button>
        )}

        <button
          onClick={handleStartPause}
          style={{ backgroundColor: currentColor }}
          className="flex-1 py-2.5 px-4 rounded-xl text-slate-950 font-bold text-xs flex items-center justify-center gap-2 shadow-lg shadow-sky-500/20 transition-all"
        >
          {isRunning ? <Pause className="w-4 h-4 fill-current" /> : <Play className="w-4 h-4 fill-current" />}
          <span>{isRunning ? 'Pause' : elapsedSecs === 0 ? 'Start Session' : 'Resume'}</span>
        </button>

        {mode !== 'break' && elapsedSecs > 0 && (
          <button
            onClick={handleFinishSession}
            className="flex-1 py-2.5 px-4 rounded-xl border border-[#34D399]/60 text-[#34D399] font-bold text-xs flex items-center justify-center gap-1.5 hover:bg-[#34D399]/10 transition-all"
          >
            <CheckCircle className="w-4 h-4" />
            <span>Finish Session</span>
          </button>
        )}
      </div>
    </div>
  );
}

// 5. Help & Support Screen Component for Web Simulator
function FlutterHelpScreen({ onBack }: { onBack?: () => void }) {
  const userProfile = {
    fullName: 'Rafid Ahmed',
    email: 'rafid@example.com',
    phone: '+8801700000000',
    linkedIn: 'https://linkedin.com/in/rafidahmed',
    instagram: 'https://instagram.com/rafid_ahmed',
    facebook: 'https://facebook.com/rafid.ahmed',
  };

  const [name, setName] = useState(userProfile.fullName);
  const [contactMethod, setContactMethod] = useState('Mail');
  const [contactDetail, setContactDetail] = useState(userProfile.email);
  const [reason, setReason] = useState('Syllabus Query');
  const [message, setMessage] = useState('');
  const [submitted, setSubmitted] = useState(false);

  const getDynamicLabel = (method: string) => {
    if (method === 'Mail') return 'EMAIL ADDRESS';
    if (method === 'Phone' || method === 'WhatsApp') return 'PHONE NUMBER';
    return 'PROFILE LINK';
  };

  const getDynamicInputType = (method: string) => {
    if (method === 'Mail') return 'email';
    if (method === 'Phone' || method === 'WhatsApp') return 'tel';
    return 'url';
  };

  const getDefaultValue = (method: string) => {
    switch (method) {
      case 'Mail':
        return userProfile.email;
      case 'Phone':
      case 'WhatsApp':
        return userProfile.phone;
      case 'LinkedIn':
        return userProfile.linkedIn;
      case 'Instagram':
        return userProfile.instagram;
      case 'Facebook':
        return userProfile.facebook;
      default:
        return userProfile.email;
    }
  };

  const handleMethodChange = (method: string) => {
    setContactMethod(method);
    setContactDetail(getDefaultValue(method));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!name || !contactDetail || !message) return;
    setSubmitted(true);
    setTimeout(() => {
      setMessage('');
      setSubmitted(false);
    }, 4000);
  };

  const aiTutors = [
    { name: 'Gemini AI', subtitle: 'Google Workspace', icon: Sparkles, color: 'text-sky-400', bg: 'bg-sky-500/15', url: 'https://gemini.google.com' },
    { name: 'ChatGPT', subtitle: 'OpenAI GPT-4o', icon: Code2, color: 'text-emerald-400', bg: 'bg-emerald-500/15', url: 'https://chatgpt.com' },
    { name: 'Claude AI', subtitle: 'Anthropic Sonnet', icon: Zap, color: 'text-orange-400', bg: 'bg-orange-500/15', url: 'https://claude.ai' },
    { name: 'Perplexity', subtitle: 'Realtime Research', icon: BarChart3, color: 'text-purple-400', bg: 'bg-purple-500/15', url: 'https://perplexity.ai' },
  ];

  return (
    <div className="p-4 space-y-4 pb-12">
      {/* Top Header */}
      <div className="flex items-center gap-3">
        {onBack && (
          <button
            onClick={onBack}
            className="p-1.5 rounded-xl bg-[#1E293B] border border-slate-700 text-slate-300 hover:text-white transition-all"
          >
            <ChevronUp className="w-4 h-4 transform -rotate-90" />
          </button>
        )}
        <div>
          <h2 className="text-lg font-bold text-white tracking-tight">Help & Support</h2>
          <p className="text-[11px] text-slate-400">Reach out or access Quick AI Tutors</p>
        </div>
      </div>

      {/* Form Card */}
      <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-4 space-y-3">
        <h3 className="text-xs font-bold text-white flex items-center gap-1.5">
          <HelpCircle className="w-4 h-4 text-[#38BDF8]" />
          <span>Contact Support Form</span>
        </h3>

        {submitted && (
          <div className="p-2.5 rounded-xl bg-sky-500/15 border border-sky-500/30 text-[#38BDF8] text-xs font-semibold animate-pulse">
            Message sent successfully via {contactMethod}! Our team will get back to you shortly.
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-2.5">
          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">FULL NAME</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            />
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">PREFERRED CONTACT METHOD</label>
            <select
              value={contactMethod}
              onChange={(e) => handleMethodChange(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            >
              <option value="Mail">Mail</option>
              <option value="Phone">Phone</option>
              <option value="WhatsApp">WhatsApp</option>
              <option value="LinkedIn">LinkedIn</option>
              <option value="Instagram">Instagram</option>
              <option value="Facebook">Facebook</option>
            </select>
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-[10px] font-semibold text-slate-400 block">
                {getDynamicLabel(contactMethod)}
              </label>
              <span className="text-[9px] text-[#38BDF8]">Auto-filled</span>
            </div>
            <input
              type={getDynamicInputType(contactMethod)}
              value={contactDetail}
              onChange={(e) => setContactDetail(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            />
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">REASON FOR REACHING OUT</label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            >
              <option value="Syllabus Query">Syllabus Query</option>
              <option value="Technical Issue">Technical Issue</option>
              <option value="Feature Request">Feature Request</option>
              <option value="General Feedback">General Feedback</option>
              <option value="Other">Other</option>
            </select>
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">YOUR MESSAGE</label>
            <textarea
              rows={3}
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Describe your question or feedback..."
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl p-2.5 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            />
          </div>

          <button
            type="submit"
            className="w-full py-2.5 rounded-xl bg-[#38BDF8] text-slate-950 font-bold text-xs hover:bg-sky-400 transition-all shadow-md shadow-sky-500/20"
          >
            Send Message
          </button>
        </form>
      </div>

      {/* Quick AI Tutors */}
      <div className="space-y-2">
        <h3 className="text-xs font-bold text-white flex items-center gap-1.5">
          <Sparkles className="w-3.5 h-3.5 text-purple-400" />
          <span>Quick AI Tutors</span>
        </h3>
        <div className="grid grid-cols-2 gap-2">
          {aiTutors.map((t) => {
            const IconComp = t.icon;
            return (
              <a
                key={t.name}
                href={t.url}
                target="_blank"
                rel="noreferrer"
                className="p-2.5 bg-[#1E293B] hover:bg-slate-800 border border-slate-800 rounded-2xl flex items-center justify-between transition-all group"
              >
                <div className="flex items-center gap-2">
                  <div className={`p-1.5 rounded-xl ${t.bg} ${t.color}`}>
                    <IconComp className="w-3.5 h-3.5" />
                  </div>
                  <div>
                    <p className="text-xs font-bold text-white leading-tight">{t.name}</p>
                    <p className="text-[9px] text-slate-400">{t.subtitle}</p>
                  </div>
                </div>
                <ArrowUpRight className="w-3 h-3 text-slate-500 group-hover:text-sky-400" />
              </a>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// 2. Syllabus Screen Interactive Component
function FlutterSyllabusScreen({ subjects: initialSubjects }: { subjects?: any[] }) {
  const [isEditMode, setIsEditMode] = useState(false);
  const [subjectsList, setSubjectsList] = useState([
    {
      id: 'math',
      title: 'Higher Mathematics',
      subtitle: '75% Completed',
      isExpanded: true,
      chapters: [
        {
          id: 'math_ch1',
          title: 'Chapter 1: Matrices & Determinants',
          sections: [
            { id: 'math_ch1_theory', label: 'Main Book Theory (Ketab Uddin)', isChecked: true },
            { id: 'math_ch1_concept', label: 'Concept Book Formulas', isChecked: true },
            { id: 'math_ch1_qb', label: 'BUET Question Bank (2010-2023)', isChecked: true },
            { id: 'math_ch1_practice', label: 'Practice Problem Sheet', isChecked: false },
          ],
        },
        {
          id: 'math_ch2',
          title: 'Chapter 2: Vector',
          sections: [
            { id: 'math_ch2_theory', label: 'Main Book Theory', isChecked: true },
            { id: 'math_ch2_concept', label: 'Formula Summary Sheet', isChecked: true },
            { id: 'math_ch2_qb', label: 'Question Bank Solve', isChecked: false },
            { id: 'math_ch2_practice', label: 'Model Test Questions', isChecked: false },
          ],
        },
      ],
    },
    {
      id: 'physics',
      title: 'Physics 1st Paper',
      subtitle: '50% Completed',
      isExpanded: false,
      chapters: [
        {
          id: 'phy_ch1',
          title: 'Chapter 1: Vector Mechanics',
          sections: [
            { id: 'phy_ch1_theory', label: 'Main Book Theory (Shahjahan Tapan)', isChecked: true },
            { id: 'phy_ch1_qb', label: 'Engineering Question Bank', isChecked: true },
            { id: 'phy_ch1_practice', label: 'Practice MCQ & CQ', isChecked: false },
          ],
        },
      ],
    },
  ]);

  // BottomSheet modal state
  const [activeModal, setActiveModal] = useState<{
    type: 'subject' | 'chapter' | 'section';
    mode: 'add' | 'edit';
    subjectId?: string;
    chapterId?: string;
    sectionId?: string;
    initialTitle?: string;
  } | null>(null);

  const [modalInput, setModalInput] = useState('');
  const [sectionInputs, setSectionInputs] = useState<string[]>(['Main Book Theory', 'Question Bank Solve']);

  const toggleSection = (subjId: string, chapId: string, secId: string) => {
    setSubjectsList((prev) =>
      prev.map((s) => {
        if (s.id !== subjId) return s;
        return {
          ...s,
          chapters: s.chapters.map((c) => {
            if (c.id !== chapId) return c;
            return {
              ...c,
              sections: c.sections.map((sec) =>
                sec.id === secId ? { ...sec, isChecked: !sec.isChecked } : sec
              ),
            };
          }),
        };
      })
    );
  };

  const toggleExpand = (subjId: string) => {
    setSubjectsList((prev) =>
      prev.map((s) => (s.id === subjId ? { ...s, isExpanded: !s.isExpanded } : s))
    );
  };

  const handleOpenModal = (
    type: 'subject' | 'chapter' | 'section',
    mode: 'add' | 'edit',
    params?: { subjectId?: string; chapterId?: string; sectionId?: string; initialTitle?: string }
  ) => {
    setModalInput(params?.initialTitle || '');
    if (type === 'chapter') {
      if (mode === 'add') {
        setSectionInputs(['Main Book Theory', 'Question Bank Solve']);
      } else if (mode === 'edit' && params?.subjectId && params?.chapterId) {
        const targetSub = subjectsList.find((s) => s.id === params.subjectId);
        const targetChap = targetSub?.chapters.find((c) => c.id === params.chapterId);
        setSectionInputs(targetChap?.sections.map((sec) => sec.label) || ['']);
      }
    }
    setActiveModal({
      type,
      mode,
      ...params,
    });
  };

  const handleSaveModal = () => {
    if (!activeModal || !modalInput.trim()) return;

    const now = Date.now();

    if (activeModal.type === 'subject') {
      if (activeModal.mode === 'add') {
        setSubjectsList((prev) => [
          ...prev,
          {
            id: `subj_${now}_${Math.floor(Math.random() * 10000)}`,
            title: modalInput.trim(),
            subtitle: '0% Completed',
            isExpanded: true,
            chapters: [],
          },
        ]);
      } else if (activeModal.mode === 'edit' && activeModal.subjectId) {
        setSubjectsList((prev) =>
          prev.map((s) => (s.id === activeModal.subjectId ? { ...s, title: modalInput.trim() } : s))
        );
      }
    } else if (activeModal.type === 'chapter' && activeModal.subjectId) {
      const validSections = sectionInputs
        .map((s) => s.trim())
        .filter((s) => s.length > 0)
        .map((label, idx) => ({
          id: `sec_${now}_${idx}_${Math.floor(Math.random() * 10000)}`,
          label,
          isChecked: false,
        }));

      if (activeModal.mode === 'add') {
        const newChapId = `chap_${now}_${Math.floor(Math.random() * 10000)}`;
        setSubjectsList((prev) =>
          prev.map((s) => {
            if (s.id !== activeModal.subjectId) return s;
            return {
              ...s,
              chapters: [
                ...s.chapters,
                {
                  id: newChapId,
                  title: modalInput.trim(),
                  sections: validSections,
                },
              ],
            };
          })
        );
      } else if (activeModal.mode === 'edit' && activeModal.chapterId) {
        setSubjectsList((prev) =>
          prev.map((s) => {
            if (s.id !== activeModal.subjectId) return s;
            return {
              ...s,
              chapters: s.chapters.map((c) =>
                c.id === activeModal.chapterId
                  ? { ...c, title: modalInput.trim(), sections: validSections }
                  : c
              ),
            };
          })
        );
      }
    } else if (activeModal.type === 'section' && activeModal.subjectId && activeModal.chapterId) {
      if (activeModal.mode === 'add') {
        setSubjectsList((prev) =>
          prev.map((s) => {
            if (s.id !== activeModal.subjectId) return s;
            return {
              ...s,
              chapters: s.chapters.map((c) => {
                if (c.id !== activeModal.chapterId) return c;
                return {
                  ...c,
                  sections: [
                    ...c.sections,
                    {
                      id: `sec_${now}_${Math.floor(Math.random() * 10000)}`,
                      label: modalInput.trim(),
                      isChecked: false,
                    },
                  ],
                };
              }),
            };
          })
        );
      } else if (activeModal.mode === 'edit' && activeModal.sectionId) {
        setSubjectsList((prev) =>
          prev.map((s) => {
            if (s.id !== activeModal.subjectId) return s;
            return {
              ...s,
              chapters: s.chapters.map((c) => {
                if (c.id !== activeModal.chapterId) return c;
                return {
                  ...c,
                  sections: c.sections.map((sec) =>
                    sec.id === activeModal.sectionId ? { ...sec, label: modalInput.trim() } : sec
                  ),
                };
              }),
            };
          })
        );
      }
    }

    setActiveModal(null);
  };

  const handleDeleteItem = () => {
    if (!activeModal) return;

    if (activeModal.type === 'subject' && activeModal.subjectId) {
      setSubjectsList((prev) => prev.filter((s) => s.id !== activeModal.subjectId));
    } else if (activeModal.type === 'chapter' && activeModal.subjectId && activeModal.chapterId) {
      setSubjectsList((prev) =>
        prev.map((s) => {
          if (s.id !== activeModal.subjectId) return s;
          return {
            ...s,
            chapters: s.chapters.filter((c) => c.id !== activeModal.chapterId),
          };
        })
      );
    } else if (
      activeModal.type === 'section' &&
      activeModal.subjectId &&
      activeModal.chapterId &&
      activeModal.sectionId
    ) {
      setSubjectsList((prev) =>
        prev.map((s) => {
          if (s.id !== activeModal.subjectId) return s;
          return {
            ...s,
            chapters: s.chapters.map((c) => {
              if (c.id !== activeModal.chapterId) return c;
              return {
                ...c,
                sections: c.sections.filter((sec) => sec.id !== activeModal.sectionId),
              };
            }),
          };
        })
      );
    }

    setActiveModal(null);
  };

  return (
    <div className="p-4 space-y-4 pb-12">
      {/* Header with Edit Toggle */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight">Syllabus Tracker</h2>
          <p className="text-xs text-slate-400 mt-0.5">Main Books & Question Banks</p>
        </div>

        <div className="flex items-center gap-2">
          {/* Edit Mode Toggle FilterChip */}
          <button
            onClick={() => setIsEditMode(!isEditMode)}
            className={`px-2.5 py-1 rounded-xl text-xs font-semibold flex items-center gap-1.5 transition-all ${
              isEditMode
                ? 'bg-amber-500/20 text-amber-400 border border-amber-500/40 shadow-sm'
                : 'bg-slate-800 text-slate-300 hover:text-white border border-slate-700'
            }`}
          >
            <Settings2 className="w-3.5 h-3.5" />
            <span>{isEditMode ? 'Editing On' : 'Edit Mode'}</span>
          </button>

          {isEditMode && (
            <button
              onClick={() => handleOpenModal('subject', 'add')}
              className="p-1.5 rounded-xl bg-[#38BDF8] text-slate-950 hover:bg-sky-400 transition-all shadow-md shadow-sky-500/20"
              title="Add New Subject"
            >
              <Plus className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {/* Subjects List */}
      <div className="space-y-3">
        {subjectsList.map((subject) => (
          <div
            key={subject.id}
            className={`bg-[#1E293B] rounded-2xl border transition-all ${
              subject.isExpanded ? 'border-[#38BDF8]/40 shadow-lg shadow-sky-500/5' : 'border-slate-800'
            }`}
          >
            <div className="p-3.5 flex items-center justify-between">
              <div
                onClick={() => toggleExpand(subject.id)}
                className="flex items-center gap-3 cursor-pointer flex-1"
              >
                <div className="p-2 bg-[#38BDF8]/15 rounded-xl text-[#38BDF8]">
                  <BookOpen className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="font-bold text-white text-sm">{subject.title}</h3>
                  <p className="text-[11px] text-slate-400">{subject.subtitle}</p>
                </div>
              </div>

              <div className="flex items-center gap-1.5">
                {isEditMode && (
                  <>
                    <button
                      onClick={() =>
                        handleOpenModal('subject', 'edit', {
                          subjectId: subject.id,
                          initialTitle: subject.title,
                        })
                      }
                      className="p-1.5 text-slate-400 hover:text-[#38BDF8]"
                    >
                      <Settings2 className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={() =>
                        handleOpenModal('chapter', 'add', { subjectId: subject.id })
                      }
                      className="p-1 rounded-lg bg-sky-500/10 text-sky-400 text-[10px] px-2 font-bold flex items-center gap-1 border border-sky-500/20"
                    >
                      <Plus className="w-3 h-3" />
                      Chap
                    </button>
                  </>
                )}
                <button onClick={() => toggleExpand(subject.id)}>
                  {subject.isExpanded ? (
                    <ChevronUp className="w-5 h-5 text-slate-400" />
                  ) : (
                    <ChevronDown className="w-5 h-5 text-slate-400" />
                  )}
                </button>
              </div>
            </div>

            {subject.isExpanded && (
              <div className="px-3.5 pb-3.5 pt-1 border-t border-slate-800/60 space-y-3">
                {subject.chapters.length === 0 ? (
                  <p className="text-xs text-slate-500 italic text-center py-2">
                    No chapters added yet. Tap + Chap above to create one.
                  </p>
                ) : (
                  subject.chapters.map((chapter) => (
                    <div
                      key={chapter.id}
                      className="bg-[#0F172A]/60 rounded-xl p-3 border border-slate-800/50 space-y-2"
                    >
                      <div className="flex items-center justify-between">
                        <h4 className="text-xs font-semibold text-slate-200">{chapter.title}</h4>
                        {isEditMode && (
                          <div className="flex items-center gap-1">
                            <button
                              onClick={() =>
                                handleOpenModal('chapter', 'edit', {
                                  subjectId: subject.id,
                                  chapterId: chapter.id,
                                  initialTitle: chapter.title,
                                })
                              }
                              className="p-1 text-slate-400 hover:text-sky-400"
                            >
                              <Settings2 className="w-3 h-3" />
                            </button>
                            <button
                              onClick={() =>
                                handleOpenModal('section', 'add', {
                                  subjectId: subject.id,
                                  chapterId: chapter.id,
                                })
                              }
                              className="p-1 text-sky-400 hover:bg-sky-500/10 rounded"
                            >
                              <Plus className="w-3.5 h-3.5" />
                            </button>
                          </div>
                        )}
                      </div>

                      <div className="space-y-1.5 pl-1">
                        {chapter.sections.length === 0 ? (
                          <p className="text-[11px] text-slate-500 italic">No section items.</p>
                        ) : (
                          chapter.sections.map((section) => (
                            <div key={section.id} className="flex items-center justify-between group">
                              <label className="flex items-center gap-2.5 cursor-pointer text-xs flex-1">
                                <input
                                  type="checkbox"
                                  checked={section.isChecked}
                                  onChange={() =>
                                    toggleSection(subject.id, chapter.id, section.id)
                                  }
                                  className="rounded border-slate-700 text-[#38BDF8] focus:ring-0 bg-slate-800 accent-[#38BDF8] w-4 h-4 cursor-pointer"
                                />
                                <span
                                  className={
                                    section.isChecked
                                      ? 'line-through text-slate-400'
                                      : 'text-slate-200'
                                  }
                                >
                                  {section.label}
                                </span>
                              </label>
                              {isEditMode && (
                                <button
                                  onClick={() =>
                                    handleOpenModal('section', 'edit', {
                                      subjectId: subject.id,
                                      chapterId: chapter.id,
                                      sectionId: section.id,
                                      initialTitle: section.label,
                                    })
                                  }
                                  className="p-1 text-slate-400 hover:text-amber-400 opacity-80"
                                >
                                  <Settings2 className="w-3 h-3" />
                                </button>
                              )}
                            </div>
                          ))
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      {/* Material 3 BottomSheet Style Dialog Modal */}
      {activeModal && (
        <div className="fixed inset-0 bg-black/70 backdrop-blur-xs z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
          <div className="bg-[#1E293B] border-t sm:border border-slate-700 rounded-t-3xl sm:rounded-2xl p-5 w-full max-w-sm space-y-4 animate-in slide-in-from-bottom">
            <div className="w-12 h-1 bg-slate-700 rounded-full mx-auto sm:hidden mb-2" />
            <h3 className="text-sm font-bold text-white capitalize">
              {activeModal.mode} {activeModal.type}
            </h3>

            <div className="space-y-1">
              <label className="text-[10px] font-bold text-[#38BDF8] tracking-wider block">
                {activeModal.type.toUpperCase()} NAME
              </label>
              <input
                type="text"
                autoFocus
                value={modalInput}
                onChange={(e) => setModalInput(e.target.value)}
                placeholder={`e.g. ${activeModal.type === 'chapter' ? 'Chapter 3: Integration' : 'Matrices & Determinants'}`}
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3.5 py-2.5 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
              />
            </div>

            {activeModal.type === 'chapter' && (
              <div className="space-y-2 pt-1">
                <div className="flex items-center justify-between">
                  <label className="text-[10px] font-bold text-[#38BDF8] tracking-wider">
                    STUDY SECTIONS / TOPICS
                  </label>
                  <span className="text-[10px] text-slate-400">{sectionInputs.length} Section(s)</span>
                </div>
                <div className="space-y-2 max-h-44 overflow-y-auto pr-1">
                  {sectionInputs.map((secVal, idx) => (
                    <div key={idx} className="flex items-center gap-2">
                      <input
                        type="text"
                        value={secVal}
                        onChange={(e) => {
                          const next = [...sectionInputs];
                          next[idx] = e.target.value;
                          setSectionInputs(next);
                        }}
                        placeholder={`Section ${idx + 1} (e.g. Concept Book / Practice)`}
                        className="flex-1 bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-1.5 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
                      />
                      {sectionInputs.length > 1 && (
                        <button
                          type="button"
                          onClick={() => setSectionInputs(sectionInputs.filter((_, i) => i !== idx))}
                          className="p-1 text-rose-400 hover:bg-rose-500/10 rounded-lg text-xs font-bold"
                          title="Remove section"
                        >
                          ✕
                        </button>
                      )}
                    </div>
                  ))}
                </div>
                <button
                  type="button"
                  onClick={() => setSectionInputs([...sectionInputs, ''])}
                  className="text-xs font-bold text-[#38BDF8] flex items-center gap-1 hover:underline pt-1"
                >
                  <Plus className="w-3.5 h-3.5" />
                  + Add Section
                </button>
              </div>
            )}

            <div className="flex items-center justify-between pt-2">
              {activeModal.mode === 'edit' ? (
                <button
                  onClick={handleDeleteItem}
                  className="px-3 py-1.5 bg-rose-500/15 border border-rose-500/30 text-rose-400 font-bold rounded-xl text-xs hover:bg-rose-500/20"
                >
                  Delete
                </button>
              ) : <div />}

              <div className="flex items-center gap-2">
                <button
                  onClick={() => setActiveModal(null)}
                  className="px-3 py-1.5 text-xs text-slate-400 hover:text-white"
                >
                  Cancel
                </button>
                <button
                  onClick={handleSaveModal}
                  className="px-4 py-2 bg-[#38BDF8] text-slate-950 font-bold rounded-xl text-xs hover:bg-sky-400 shadow-md shadow-sky-500/20"
                >
                  Save
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// 6. Profile Screen Component for Web Simulator
function FlutterProfileScreen({ onBack, onOpenHelp }: { onBack?: () => void; onOpenHelp: () => void }) {
  // Dynamic Signup Method State ('email' | 'phone')
  const [signUpMethod, setSignUpMethod] = useState<'email' | 'phone'>('email');

  // Mock Data Initialization
  const [fullName, setFullName] = useState('Shahriyer Sayem');
  const [nickname, setNickname] = useState('Sayem');
  const [username, setUsername] = useState('sayem_25');
  const [email, setEmail] = useState('s.sayemx@gmail.com');
  const [phone, setPhone] = useState('+8801700000000');
  const [college, setCollege] = useState('Notre Dame College, Dhaka');
  const [hscBatch, setHscBatch] = useState('2025');
  const [hscGroup, setHscGroup] = useState('Science');
  const [district, setDistrict] = useState('Dhaka');

  const [primaryTarget, setPrimaryTarget] = useState('Engineering (BUET, CKRUET)');
  const [secondaryTarget, setSecondaryTarget] = useState('None');
  
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saved, setSaved] = useState(false);

  const allTargets = [
    'Engineering (BUET, CKRUET)',
    'Medical (MBBS & BDS)',
    'Versity "A" Unit',
    'Versity "B" Unit',
    'Versity "C" Unit',
    'IBA/BBA Admission',
  ];

  // Dynamic filtering for 2nd Target: "None" + exclude whichever option is selected as Primary Target
  const secondaryTargetOptions = ['None', ...allTargets.filter((t) => t !== primaryTarget)];

  const handlePrimaryChange = (newTarget: string) => {
    setPrimaryTarget(newTarget);
    // If secondary target equals new primary target, automatically switch secondary target to 'None'
    if (secondaryTarget !== 'None' && secondaryTarget === newTarget) {
      setSecondaryTarget('None');
    }
  };

  const handleSave = (e: React.FormEvent) => {
    e.preventDefault();
    const newErrors: Record<string, string> = {};

    if (!nickname.trim()) newErrors.nickname = 'Nickname is required';
    if (!username.trim()) newErrors.username = 'Username is required';
    if (!college.trim()) newErrors.college = 'College is required';

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      setSaved(false);
      return;
    }

    setErrors({});
    setSaved(true);
    setTimeout(() => setSaved(false), 3500);
  };

  const isEmailReadOnly = signUpMethod === 'email';
  const isPhoneReadOnly = signUpMethod === 'phone';

  return (
    <div className="p-4 space-y-4 pb-10">
      {/* Header */}
      <div className="flex items-center justify-between pb-2 border-b border-slate-800">
        <div className="flex items-center gap-2">
          {onBack && (
            <button
              onClick={onBack}
              className="p-1.5 rounded-xl bg-slate-800 text-slate-300 hover:text-white"
            >
              <ArrowLeft className="w-4 h-4" />
            </button>
          )}
          <h2 className="text-sm font-bold text-white">My Profile</h2>
        </div>
        <span className="text-[10px] text-[#38BDF8] bg-sky-500/10 px-2 py-0.5 rounded-full font-semibold border border-sky-500/20">
          HSC {hscBatch} Batch
        </span>
      </div>

      {/* Profile Picture Section */}
      <div className="flex flex-col items-center justify-center py-2">
        <div className="relative">
          <div className="w-20 h-20 rounded-full ring-4 ring-sky-400/30 shadow-xl shadow-sky-500/10 overflow-hidden bg-slate-800 flex items-center justify-center">
            <img
              src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=300"
              alt="Profile Avatar"
              className="w-full h-full object-cover"
              onError={(e) => {
                // Fallback icon if image fails
                (e.target as HTMLElement).style.display = 'none';
              }}
            />
            <span className="font-bold text-2xl text-[#38BDF8]">S</span>
          </div>
          <button
            type="button"
            onClick={() => alert('Image picker triggered')}
            className="absolute bottom-0 right-0 p-1.5 rounded-full bg-[#38BDF8] text-slate-950 border-2 border-[#0F172A] shadow-md hover:scale-110 transition-transform"
            title="Edit Profile Photo"
          >
            <Camera className="w-3.5 h-3.5" />
          </button>
        </div>
        <h3 className="text-base font-bold text-white mt-2">{fullName || 'Shahriyer Sayem'}</h3>
        <p className="text-xs text-slate-400">@{username || 'sayem_25'} • {college || 'College'}</p>
      </div>

      {saved && (
        <div className="p-3 rounded-xl bg-sky-500/15 border border-sky-500/30 text-[#38BDF8] text-xs font-semibold text-center flex items-center justify-center gap-2 animate-in fade-in">
          <span className="w-2 h-2 rounded-full bg-[#38BDF8] animate-ping" />
          ✓ Profile updated successfully!
        </div>
      )}

      {/* Form Section */}
      <form onSubmit={handleSave} className="space-y-4">
        {/* Personal Details Card */}
        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-4 space-y-3">
          <div className="flex items-center gap-2 pb-1 border-b border-slate-800/60">
            <User className="w-4 h-4 text-[#38BDF8]" />
            <h4 className="text-xs font-bold text-white">Personal Information</h4>
          </div>

          {/* Signup Method Switcher */}
          <div className="p-1 bg-[#0F172A] rounded-xl border border-slate-800 flex items-center text-xs">
            <button
              type="button"
              onClick={() => setSignUpMethod('email')}
              className={`flex-1 py-1.5 rounded-lg font-medium transition-all flex items-center justify-center gap-1.5 ${
                signUpMethod === 'email'
                  ? 'bg-[#1E293B] text-white border border-[#38BDF8]/40 shadow'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Mail className="w-3.5 h-3.5 text-[#38BDF8]" />
              Email Signup
            </button>
            <button
              type="button"
              onClick={() => setSignUpMethod('phone')}
              className={`flex-1 py-1.5 rounded-lg font-medium transition-all flex items-center justify-center gap-1.5 ${
                signUpMethod === 'phone'
                  ? 'bg-[#1E293B] text-white border border-[#38BDF8]/40 shadow'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              <Smartphone className="w-3.5 h-3.5 text-[#38BDF8]" />
              Phone Signup
            </button>
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">
              FULL NAME
            </label>
            <input
              type="text"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="e.g. Shahriyer Sayem"
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            />
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-[10px] font-semibold text-slate-400 block mb-1">
                NICKNAME <span className="text-[#38BDF8] font-bold">*</span>
              </label>
              <input
                type="text"
                value={nickname}
                onChange={(e) => {
                  setNickname(e.target.value);
                  if (errors.nickname) setErrors({ ...errors, nickname: '' });
                }}
                placeholder="e.g. Sayem"
                className={`w-full bg-[#0F172A] border rounded-xl px-3 py-2 text-xs text-white focus:outline-none ${
                  errors.nickname ? 'border-rose-500' : 'border-slate-700 focus:border-[#38BDF8]'
                }`}
              />
              {errors.nickname && <p className="text-[10px] text-rose-400 mt-0.5">{errors.nickname}</p>}
            </div>

            <div>
              <label className="text-[10px] font-semibold text-slate-400 block mb-1">
                USERNAME <span className="text-[#38BDF8] font-bold">*</span>
              </label>
              <input
                type="text"
                value={username}
                onChange={(e) => {
                  setUsername(e.target.value);
                  if (errors.username) setErrors({ ...errors, username: '' });
                }}
                placeholder="e.g. sayem_25"
                className={`w-full bg-[#0F172A] border rounded-xl px-3 py-2 text-xs text-white focus:outline-none ${
                  errors.username ? 'border-rose-500' : 'border-slate-700 focus:border-[#38BDF8]'
                }`}
              />
              {errors.username && <p className="text-[10px] text-rose-400 mt-0.5">{errors.username}</p>}
            </div>
          </div>

          {/* Email Address Field with Dynamic ReadOnly Locking */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-[10px] font-semibold text-slate-400">
                EMAIL ADDRESS <span className="text-[#38BDF8] font-bold">*</span>
              </label>
              {isEmailReadOnly && (
                <span className="text-[9px] text-slate-400 bg-slate-800 px-1.5 py-0.5 rounded flex items-center gap-1 border border-slate-700">
                  🔒 Primary Signup (Locked)
                </span>
              )}
            </div>
            <input
              type="email"
              value={email}
              readOnly={isEmailReadOnly}
              onChange={(e) => setEmail(e.target.value)}
              className={`w-full border rounded-xl px-3 py-2 text-xs transition-all ${
                isEmailReadOnly
                  ? 'bg-[#0F172A]/60 border-slate-800 text-slate-400 cursor-not-allowed'
                  : 'bg-[#0F172A] border-slate-700 text-white focus:outline-none focus:border-[#38BDF8]'
              }`}
            />
          </div>

          {/* Phone Number Field with Dynamic ReadOnly Locking */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-[10px] font-semibold text-slate-400">
                PHONE NUMBER
              </label>
              {isPhoneReadOnly && (
                <span className="text-[9px] text-slate-400 bg-slate-800 px-1.5 py-0.5 rounded flex items-center gap-1 border border-slate-700">
                  🔒 Primary Signup (Locked)
                </span>
              )}
            </div>
            <input
              type="tel"
              value={phone}
              readOnly={isPhoneReadOnly}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+8801XXXXXXXXX"
              className={`w-full border rounded-xl px-3 py-2 text-xs transition-all ${
                isPhoneReadOnly
                  ? 'bg-[#0F172A]/60 border-slate-800 text-slate-400 cursor-not-allowed'
                  : 'bg-[#0F172A] border-slate-700 text-white focus:outline-none focus:border-[#38BDF8]'
              }`}
            />
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">
              COLLEGE <span className="text-[#38BDF8] font-bold">*</span>
            </label>
            <input
              type="text"
              value={college}
              onChange={(e) => {
                setCollege(e.target.value);
                if (errors.college) setErrors({ ...errors, college: '' });
              }}
              placeholder="e.g. Notre Dame College, Dhaka"
              className={`w-full bg-[#0F172A] border rounded-xl px-3 py-2 text-xs text-white focus:outline-none ${
                errors.college ? 'border-rose-500' : 'border-slate-700 focus:border-[#38BDF8]'
              }`}
            />
            {errors.college && <p className="text-[10px] text-rose-400 mt-0.5">{errors.college}</p>}
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="text-[10px] font-semibold text-slate-400 block mb-1">
                HSC BATCH <span className="text-[#38BDF8] font-bold">*</span>
              </label>
              <select
                value={hscBatch}
                onChange={(e) => setHscBatch(e.target.value)}
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
              >
                {['2024', '2025', '2026', '2027', '2028', '2029'].map((b) => (
                  <option key={b} value={b}>HSC {b}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="text-[10px] font-semibold text-slate-400 block mb-1">
                HSC GROUP <span className="text-[#38BDF8] font-bold">*</span>
              </label>
              <select
                value={hscGroup}
                onChange={(e) => setHscGroup(e.target.value)}
                className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
              >
                {['Science', 'Arts', 'Commerce'].map((g) => (
                  <option key={g} value={g}>{g}</option>
                ))}
              </select>
            </div>
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">
              HOME DISTRICT
            </label>
            <input
              type="text"
              value={district}
              onChange={(e) => setDistrict(e.target.value)}
              placeholder="e.g. Dhaka, Chittagong"
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            />
          </div>
        </div>

        {/* Admission Target Section with Dynamic Filtering & None Option */}
        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-4 space-y-3">
          <div className="flex items-center gap-2 pb-1 border-b border-slate-800/60">
            <School className="w-4 h-4 text-[#38BDF8]" />
            <h4 className="text-xs font-bold text-white">Admission Target Goals</h4>
          </div>

          <div>
            <label className="text-[10px] font-semibold text-slate-400 block mb-1">
              ADMISSION TARGET GOAL <span className="text-[#38BDF8] font-bold">*</span>
            </label>
            <select
              value={primaryTarget}
              onChange={(e) => handlePrimaryChange(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            >
              {allTargets.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          </div>

          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-[10px] font-semibold text-slate-400">
                2ND ADMISSION TARGET GOAL
              </label>
              <span className="text-[9px] text-[#38BDF8] font-semibold">
                Includes "None" & Excludes 1st Target
              </span>
            </div>
            <select
              value={secondaryTarget}
              onChange={(e) => setSecondaryTarget(e.target.value)}
              className="w-full bg-[#0F172A] border border-slate-700 rounded-xl px-3 py-2 text-xs text-white focus:outline-none focus:border-[#38BDF8]"
            >
              {secondaryTargetOptions.map((t) => (
                <option key={t} value={t}>{t}</option>
              ))}
            </select>
          </div>
        </div>

        <button
          type="submit"
          className="w-full py-3 rounded-xl bg-[#38BDF8] text-slate-950 font-bold text-xs hover:bg-sky-400 transition-all shadow-md shadow-sky-500/20 active:scale-[0.99]"
        >
          Save Profile
        </button>
      </form>

      {/* Help & Support Tile */}
      <button
        onClick={onOpenHelp}
        className="w-full bg-[#1E293B] hover:bg-slate-800 border border-slate-800 rounded-2xl p-3.5 flex items-center justify-between text-left transition-all"
      >
        <div className="flex items-center gap-3">
          <div className="p-2 bg-[#38BDF8]/15 text-[#38BDF8] rounded-xl">
            <HelpCircle className="w-4 h-4" />
          </div>
          <div>
            <p className="text-xs font-bold text-white">Help & Support</p>
            <p className="text-[10px] text-slate-400">Contact support & launch AI tutors</p>
          </div>
        </div>
        <ArrowUpRight className="w-4 h-4 text-slate-500" />
      </button>
    </div>
  );
}

function FlutterHomeScreen() {
  const [screenMode, setScreenMode] = useState<'home' | 'profile' | 'help'>('home');

  if (screenMode === 'help') {
    return <FlutterHelpScreen onBack={() => setScreenMode('home')} />;
  }

  if (screenMode === 'profile') {
    return (
      <FlutterProfileScreen
        onBack={() => setScreenMode('home')}
        onOpenHelp={() => setScreenMode('help')}
      />
    );
  }

  return (
    <div className="p-4 space-y-4 pb-10">
      {/* Sleek Top Transparent AppBar with Circular Profile Avatar */}
      <div className="flex items-center justify-between pt-1">
        <div className="flex items-center gap-2">
          <div className="w-6 h-6 rounded-lg bg-[#38BDF8] text-slate-950 font-black text-xs flex items-center justify-center">
            চ
          </div>
          <span className="font-bold text-white text-base tracking-tight">Chondrobindu</span>
        </div>

        <div className="flex items-center gap-2">
          <button className="w-8 h-8 rounded-full bg-[#1E293B] border border-slate-700/60 flex items-center justify-center text-slate-300 hover:text-white transition-colors">
            <Bell className="w-4 h-4" />
          </button>

          {/* Profile Avatar button -> opens ProfileScreen */}
          <button
            onClick={() => setScreenMode('profile')}
            className="w-9 h-9 rounded-full bg-gradient-to-tr from-[#38BDF8] to-indigo-500 text-slate-950 font-bold text-xs flex items-center justify-center shadow-md shadow-sky-500/20 ring-2 ring-sky-400/30 hover:scale-105 transition-transform"
            title="My Profile"
          >
            R
          </button>
        </div>
      </div>

      {/* 1. Welcome Section */}
      <div className="flex items-start justify-between">
        <div>
          <h2 className="text-xl font-bold text-white tracking-tight flex items-center gap-2">
            Good morning, Rafid 👋
          </h2>
          <p className="text-xs text-slate-400 mt-1">Ready for your engineering prep?</p>
        </div>
      </div>

      {/* 2. Summary Cards */}
      <div className="grid grid-cols-2 gap-3">
        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-2 shadow-sm">
          <div className="flex items-center gap-1.5 text-xs text-slate-400 font-medium">
            <TimerIcon className="w-4 h-4 text-[#38BDF8]" />
            <span>Today's Focus</span>
          </div>
          <div className="text-2xl font-bold text-white tracking-tight">2h 15m</div>
          <p className="text-[11px] text-[#38BDF8] font-semibold">Target: 4h 00m</p>
        </div>

        <div className="bg-[#1E293B] border border-slate-800 rounded-2xl p-3.5 space-y-2 shadow-sm">
          <div className="flex items-center gap-1.5 text-xs text-slate-400 font-medium">
            <Flame className="w-4 h-4 text-amber-500" />
            <span>Streak</span>
          </div>
          <div className="text-2xl font-bold text-white tracking-tight">4 Days</div>
          <p className="text-[11px] text-amber-500 font-semibold">Personal Best: 12d</p>
        </div>
      </div>

      {/* 3. Quote Card */}
      <div className="bg-gradient-to-br from-[#1E293B] to-[#0F2B48] border border-[#38BDF8]/30 rounded-2xl p-4 space-y-2">
        <div className="flex items-start gap-2.5">
          <Quote className="w-5 h-5 text-[#38BDF8] shrink-0 mt-0.5" />
          <div className="space-y-1.5">
            <p className="text-xs text-slate-200 italic leading-relaxed">
              "Success is no accident. It is hard work, perseverance, learning, studying, sacrifice and most of all, love of what you are doing or learning to do."
            </p>
            <p className="text-[11px] font-bold text-[#38BDF8]">— Pelé</p>
          </div>
        </div>
      </div>

      {/* 4. Upcoming Exam Card */}
      <div className="bg-gradient-to-br from-[#1E293B] to-[#1E3A5F] border border-[#38BDF8]/30 rounded-2xl p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <div className="p-1.5 bg-[#38BDF8]/15 rounded-lg text-[#38BDF8]">
              <School className="w-4 h-4" />
            </div>
            <span className="font-bold text-white text-sm">BUET Admission</span>
          </div>
          <span className="bg-[#38BDF8]/20 border border-[#38BDF8]/40 text-[#38BDF8] text-[10px] px-2 py-0.5 rounded-full font-semibold">
            Target #1
          </span>
        </div>
        <div className="flex items-baseline gap-2">
          <span className="text-3xl font-black text-[#38BDF8] tracking-tight">45</span>
          <span className="text-xs text-slate-300 font-medium">Days Remaining</span>
        </div>
        <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
          <div className="bg-[#38BDF8] h-full w-[65%]" />
        </div>
        <div className="flex justify-between text-[11px] text-slate-400">
          <span>Syllabus Covered: 65%</span>
          <span>Exam Date: Target 2026</span>
        </div>
      </div>

      {/* 5. Quick Access Row */}
      <div className="space-y-2">
        <h3 className="text-xs font-semibold text-slate-300">Quick Actions</h3>
        <div className="grid grid-cols-2 gap-3">
          <button
            onClick={() => setScreenMode('profile')}
            className="flex items-center gap-3 p-3 bg-[#1E293B] hover:bg-slate-800 border border-slate-800 rounded-2xl text-left transition-all"
          >
            <div className="p-2 bg-[#38BDF8]/15 text-[#38BDF8] rounded-xl">
              <User className="w-4 h-4" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">My Profile</p>
              <p className="text-[10px] text-slate-400">Targets & Details</p>
            </div>
          </button>
          <button
            onClick={() => setScreenMode('help')}
            className="flex items-center gap-3 p-3 bg-[#1E293B] hover:bg-slate-800 border border-slate-800 rounded-2xl text-left transition-all"
          >
            <div className="p-2 bg-purple-500/15 text-purple-400 rounded-xl">
              <HelpCircle className="w-4 h-4" />
            </div>
            <div>
              <p className="text-xs font-bold text-white">Help & Support</p>
              <p className="text-[10px] text-slate-400">AI Tutors & Form</p>
            </div>
          </button>
        </div>
      </div>
    </div>
  );
}

