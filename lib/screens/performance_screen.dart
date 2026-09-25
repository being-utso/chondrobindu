import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/exam_model.dart';
import '../models/performance_models.dart';
import '../providers/performance_provider.dart';
import '../services/exam_service.dart';

/// Screen for tracking engineering admission exam performances & target countdowns.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearestExam = ref.watch(nearestUpcomingExamProvider);
    final examRecords = ref.watch(allExamRecordsProvider);
    final improvement = ref.watch(performanceImprovementProvider);

    const backgroundColor = Color(0xFF110D0C);
    const cardColor = Color(0xFF1C1412);
    const accentColor = Color(0xFFF2B78A);
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
                    child: Icon(Icons.analytics_rounded, color: accentColor, size: 22),
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

              const SizedBox(height: 24),

              // Bottom Quick Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _showAddExamDateDialog(context, ref),
                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
                      label: const Text('Add Exam Date'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: accentColor,
                        side: BorderSide(color: accentColor.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showLogResultDialog(context, ref),
                      icon: const Icon(Icons.add_task_rounded, size: 18),
                      label: const Text('Log New Result'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: const Color(0xFF110D0C),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  /// PART A: Countdown Banner Widget
  Widget _buildCountdownBanner(
    BuildContext context,
    WidgetRef ref,
    UpcomingExam? nearestExam,
    Color cardColor,
    Color accentColor,
  ) {
    if (nearestExam == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_outlined, color: accentColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'No Upcoming Exams Set',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap below to add your target admission exam date.',
                    style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _showAddExamDateDialog(context, ref),
              icon: Icon(Icons.add_circle_outline_rounded, color: accentColor),
            ),
          ],
        ),
      );
    }

    final days = nearestExam.daysRemaining;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardColor,
            const Color(0xFF1E3A8A).withOpacity(0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flag_rounded, color: accentColor, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'NEXT TARGET EXAM',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _showAddExamDateDialog(context, ref),
                icon: Icon(Icons.edit_calendar_rounded, color: Colors.blueGrey.shade400, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            nearestExam.examName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Target Date: ${_formatDate(nearestExam.targetDate)}',
            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Big Countdown Display
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF110D0C).withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$days',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      days == 1 ? 'DAY REMAINING' : 'DAYS REMAINING',
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                Icon(
                  days <= 10 ? Icons.alarm_on_rounded : Icons.hourglass_top_rounded,
                  color: days <= 10 ? const Color(0xFFF87171) : accentColor.withOpacity(0.8),
                  size: 32,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Improvement Indicator Card
  Widget _buildImprovementIndicatorCard(
    PerformanceImprovement improvement,
    Color cardColor,
    Color emeraldColor,
    Color accentColor,
  ) {
    if (!improvement.hasEnoughData) return const SizedBox.shrink();

    final isMarksUp = improvement.isMarksImproved;
    final isMeritUp = improvement.isMeritImproved;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.trending_up_rounded, color: Color(0xFF34D399), size: 18),
              SizedBox(width: 8),
              Text(
                'Improvement Indicator',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Spacer(),
              Text(
                'VS PREVIOUS EXAM',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isMarksUp ? emeraldColor : const Color(0xFFF87171)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isMarksUp ? emeraldColor : const Color(0xFFF87171)).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Marks Shift',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isMarksUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            color: isMarksUp ? emeraldColor : const Color(0xFFF87171),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isMarksUp ? '+' : ''}${improvement.marksDelta.toStringAsFixed(1)} pts',
                            style: TextStyle(
                              color: isMarksUp ? emeraldColor : const Color(0xFFF87171),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (isMeritUp ? emeraldColor : const Color(0xFFF87171)).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isMeritUp ? emeraldColor : const Color(0xFFF87171)).withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Merit Rank Shift',
                        style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isMeritUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                            color: isMeritUp ? emeraldColor : const Color(0xFFF87171),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${isMeritUp ? '+' : ''}${improvement.meritDelta} ranks',
                            style: TextStyle(
                              color: isMeritUp ? emeraldColor : const Color(0xFFF87171),
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// PART B: Marks Trend Line Chart Widget
  Widget _buildMarksTrendChart(List<ExamRecord> records, Color cardColor, Color accentColor) {
    final sorted = List<ExamRecord>.from(records)..sort((a, b) => a.date.compareTo(b.date));

    final spots = sorted.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.marks);
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Marks Trend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Score evolution across recent mock tests',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Latest: ${sorted.last.marks.toStringAsFixed(1)}',
                  style: TextStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < sorted.length) {
                          final nameParts = sorted[idx].examName.split(' ');
                          final shortName = nameParts.length > 2
                              ? '${nameParts[0]} ${nameParts.last}'
                              : sorted[idx].examName;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              shortName,
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: accentColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: accentColor,
                          strokeWidth: 2,
                          strokeColor: const Color(0xFF110D0C),
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withOpacity(0.35),
                          accentColor.withOpacity(0.01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1C1412),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final rec = sorted[idx];
                        return LineTooltipItem(
                          '${rec.examName}\n${rec.marks} Marks',
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// PART B: Merit Trend Line Chart Widget (CRITICAL: INVERTED Y-AXIS)
  Widget _buildMeritTrendChart(List<ExamRecord> records, Color cardColor, Color emeraldColor) {
    final sorted = List<ExamRecord>.from(records)..sort((a, b) => a.date.compareTo(b.date));

    final spots = sorted.asMap().entries.map((entry) {
      // INVERTED Y-AXIS: -meritPosition
      return FlSpot(entry.key.toDouble(), -entry.value.meritPosition.toDouble());
    }).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Merit Position Trend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Lower rank number = Higher graph progression',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: emeraldColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Current Merit: #${sorted.last.meritPosition}',
                  style: TextStyle(color: emeraldColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < sorted.length) {
                          final nameParts = sorted[idx].examName.split(' ');
                          final shortName = nameParts.length > 2
                              ? '${nameParts[0]} ${nameParts.last}'
                              : sorted[idx].examName;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              shortName,
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: emeraldColor,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: emeraldColor,
                          strokeWidth: 2,
                          strokeColor: const Color(0xFF110D0C),
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          emeraldColor.withOpacity(0.35),
                          emeraldColor.withOpacity(0.01),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1C1412),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final idx = spot.spotIndex;
                        final rec = sorted[idx];
                        return LineTooltipItem(
                          '${rec.examName}\nMerit Position: #${rec.meritPosition}',
                          const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// History List of Logged Past Exams
  Widget _buildExamHistoryList(
    BuildContext context,
    WidgetRef ref,
    List<ExamRecord> records,
    Color cardColor,
  ) {
    final sortedNewest = List<ExamRecord>.from(records)..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Exam Result History',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${records.length} logged',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedNewest.length,
            separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06), height: 16),
            itemBuilder: (context, index) {
              final rec = sortedNewest[index];
              return Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF110D0C),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Center(
                      child: Text(
                        '#${rec.meritPosition}',
                        style: const TextStyle(
                          color: Color(0xFFF2B78A),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec.examName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${rec.subject} • ${_formatDate(rec.date)}',
                          style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${rec.marks} pts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Marks',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 10),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// Empty State Card when no exam records are logged
  Widget _buildEmptyStateCard(BuildContext context, WidgetRef ref, Color cardColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.insert_chart_outlined_rounded, color: Colors.blueGrey.shade600, size: 48),
          const SizedBox(height: 14),
          const Text(
            'Log your first exam to see performance trends',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Record mock tests and paper finals to visualize your score evolution and merit rank trajectory.',
            style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _showLogResultDialog(context, ref),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log New Result'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF2B78A),
              foregroundColor: const Color(0xFF110D0C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog to add an upcoming exam date
  void _showAddExamDateDialog(BuildContext context, WidgetRef ref) {
    final nameController = TextEditingController(text: 'BUET Central Final');
    int daysOffset = 30;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1412),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Add Upcoming Exam', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Exam Name',
                  labelStyle: TextStyle(color: Colors.blueGrey.shade400),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFF2B78A)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Date: In $daysOffset days',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      Slider(
                        value: daysOffset.toDouble(),
                        min: 1,
                        max: 120,
                        divisions: 119,
                        activeColor: const Color(0xFFF2B78A),
                        onChanged: (val) {
                          setState(() {
                            daysOffset = val.toInt();
                          });
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF110D0C),
              ),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final now = DateTime.now();
                  final target = DateTime(now.year, now.month, now.day + daysOffset);
                  final newExam = ExamModel(
                    id: '',
                    examName: name,
                    subject: 'General',
                    date: target,
                    totalMarks: 100.0,
                    marksObtained: 0.0,
                    meritPosition: 0,
                    isCompleted: false,
                    isAbsent: false,
                  );

                  ref.read(examServiceProvider).addExam(newExam);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Target exam "$name" added!')),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Save Exam'),
            ),
          ],
        );
      },
    );
  }

  /// Dialog to log a new exam result
  void _showLogResultDialog(BuildContext context, WidgetRef ref) {
    final examController = TextEditingController(text: 'Paper Final Mock');
    final subjectController = TextEditingController(text: 'Physics & Chemistry');
    final marksController = TextEditingController(text: '82.0');
    final meritController = TextEditingController(text: '35');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1412),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Log Exam Result', style: TextStyle(color: Colors.white, fontSize: 18)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogField('Exam Name', examController),
                const SizedBox(height: 12),
                _buildDialogField('Subject', subjectController),
                const SizedBox(height: 12),
                _buildDialogField('Marks Scored', marksController, isNumber: true),
                const SizedBox(height: 12),
                _buildDialogField('Merit Position (Rank)', meritController, isNumber: true),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: Colors.blueGrey.shade400)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF2B78A),
                foregroundColor: const Color(0xFF110D0C),
              ),
              onPressed: () {
                final examName = examController.text.trim();
                final subject = subjectController.text.trim();
                final marks = double.tryParse(marksController.text.trim()) ?? 0.0;
                final merit = int.tryParse(meritController.text.trim()) ?? 0;

                if (examName.isNotEmpty) {
                  final newRecord = ExamModel(
                    id: '',
                    examName: examName,
                    subject: subject.isEmpty ? 'General' : subject,
                    marksObtained: marks,
                    totalMarks: 100.0,
                    meritPosition: merit,
                    date: DateTime.now(),
                    isCompleted: true,
                    isAbsent: false,
                  );

                  ref.read(examServiceProvider).addExam(newRecord);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Result for "$examName" recorded!')),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Log Result'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDialogField(String label, TextEditingController controller, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.blueGrey.shade400, fontSize: 13),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFFF2B78A)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
