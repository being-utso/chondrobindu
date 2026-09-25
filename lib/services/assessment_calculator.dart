import 'package:chondrobindu/models/assessment_model.dart';

/// Calculation result for a single assessment category
class CategoryCalculationResult {
  final double obtained;
  final double total;
  final double percentage;
  final double weightedScore;
  final double weightage;
  final bool useBestOf;
  final int bestCount;
  final int totalItems;
  final int countedItems;
  final List<AssessmentItem> activeItems;

  const CategoryCalculationResult({
    required this.obtained,
    required this.total,
    required this.percentage,
    required this.weightedScore,
    required this.weightage,
    required this.useBestOf,
    required this.bestCount,
    required this.totalItems,
    required this.countedItems,
    required this.activeItems,
  });

  /// Formatted score string (e.g., "16.5 / 20.0 (82.5%)")
  String get scoreSummary {
    if (total <= 0) return '0.0 / 0.0 (0.0%)';
    return '${obtained.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} (${percentage.toStringAsFixed(1)}%)';
  }

  /// Formatted weighted score string (e.g., "16.50 / 20.0 pts")
  String get weightedSummary {
    return '${weightedScore.toStringAsFixed(2)} / ${weightage.toStringAsFixed(1)} pts';
  }
}

/// Overall predicted course grade and CGPA conversion result
class PredictedGradeResult {
  final double totalWeightedScore;
  final double totalWeightage;
  final double normalizedPercentage;
  final String letterGrade;
  final double gradePoint;
  final String remarks;

  const PredictedGradeResult({
    required this.totalWeightedScore,
    required this.totalWeightage,
    required this.normalizedPercentage,
    required this.letterGrade,
    required this.gradePoint,
    required this.remarks,
  });

  bool get isFullWeightage => (totalWeightage - 100.0).abs() < 0.01;
}

/// Helper service for flexible percentage weightage & "Best of N" calculations
class AssessmentCalculationHelper {
  /// Computes category score, taking into account optional Best-of-N and weightage
  /// (ignoring future scheduled/pending assessments with no entered marks)
  static CategoryCalculationResult calculateCategoryScore({
    required List<AssessmentItem> items,
    required double weightagePercentage,
    bool useBestOf = false,
    int bestCount = 1,
  }) {
    final validWeightage = weightagePercentage.clamp(0.0, 100.0);

    if (items.isEmpty) {
      return CategoryCalculationResult(
        obtained: 0.0,
        total: 0.0,
        percentage: 0.0,
        weightedScore: 0.0,
        weightage: validWeightage,
        useBestOf: useBestOf,
        bestCount: bestCount,
        totalItems: 0,
        countedItems: 0,
        activeItems: const [],
      );
    }

    // Filter to only completed assessments with recorded marks
    final completedItems = items.where((item) => item.isRecorded).toList();

    if (completedItems.isEmpty) {
      return CategoryCalculationResult(
        obtained: 0.0,
        total: 0.0,
        percentage: 0.0,
        weightedScore: 0.0,
        weightage: validWeightage,
        useBestOf: useBestOf,
        bestCount: bestCount,
        totalItems: items.length,
        countedItems: 0,
        activeItems: const [],
      );
    }

    List<AssessmentItem> selectedItems;
    int counted;

    if (useBestOf && completedItems.isNotEmpty) {
      final effectiveN = bestCount.clamp(1, completedItems.length);
      final sorted = List<AssessmentItem>.from(completedItems)
        ..sort((a, b) => b.percentage.compareTo(a.percentage));
      selectedItems = sorted.take(effectiveN).toList();
      counted = effectiveN;
    } else {
      selectedItems = List.from(completedItems);
      counted = completedItems.length;
    }

    if (selectedItems.isEmpty) {
      return CategoryCalculationResult(
        obtained: 0.0,
        total: 0.0,
        percentage: 0.0,
        weightedScore: 0.0,
        weightage: validWeightage,
        useBestOf: useBestOf,
        bestCount: bestCount,
        totalItems: items.length,
        countedItems: 0,
        activeItems: const [],
      );
    }

    // Average percentage across the selected items
    double sumPercentages = 0.0;
    double sumObtained = 0.0;
    double sumTotal = 0.0;

    for (final item in selectedItems) {
      sumPercentages += item.percentage;
      sumObtained += item.obtained;
      sumTotal += item.total;
    }

    final double avgPercentage = sumPercentages / selectedItems.length;
    final double weightedScore = (avgPercentage / 100.0) * validWeightage;

    return CategoryCalculationResult(
      obtained: sumObtained,
      total: sumTotal,
      percentage: avgPercentage,
      weightedScore: weightedScore,
      weightage: validWeightage,
      useBestOf: useBestOf,
      bestCount: bestCount,
      totalItems: items.length,
      countedItems: counted,
      activeItems: selectedItems,
    );
  }

  /// Computes overall predicted grade and CGPA conversion from a list of category results
  /// Filters out 0-weight or inactive categories and dynamically re-normalizes active weights to 100%
  static PredictedGradeResult calculatePredictedGrade({
    required List<CategoryCalculationResult> categoryResults,
  }) {
    // Filter out categories where weightage <= 0
    final activeCategories = categoryResults.where((res) => res.weightage > 0.0).toList();

    double totalWeighted = 0.0;
    double totalWeight = 0.0;

    for (final res in activeCategories) {
      totalWeighted += res.weightedScore;
      totalWeight += res.weightage;
    }

    // If total weight is > 0, dynamically re-normalize score to 100% basis
    final double normalizedPct = totalWeight > 0
        ? ((totalWeighted / totalWeight) * 100.0).clamp(0.0, 100.0)
        : 0.0;

    final gradeInfo = percentageToGrade(normalizedPct);

    return PredictedGradeResult(
      totalWeightedScore: totalWeighted,
      totalWeightage: totalWeight,
      normalizedPercentage: normalizedPct,
      letterGrade: gradeInfo.letterGrade,
      gradePoint: gradeInfo.gradePoint,
      remarks: gradeInfo.remarks,
    );
  }

  /// Converts percentage score to standard UGC / BUET letter grade and grade point
  static ({String letterGrade, double gradePoint, String remarks}) percentageToGrade(double percentage) {
    final rounded = percentage.roundToDouble();

    if (rounded >= 80.0) {
      return (letterGrade: 'A+', gradePoint: 4.00, remarks: 'Outstanding');
    } else if (rounded >= 75.0) {
      return (letterGrade: 'A', gradePoint: 3.75, remarks: 'Excellent');
    } else if (rounded >= 70.0) {
      return (letterGrade: 'A-', gradePoint: 3.50, remarks: 'Very Good');
    } else if (rounded >= 65.0) {
      return (letterGrade: 'B+', gradePoint: 3.25, remarks: 'Good');
    } else if (rounded >= 60.0) {
      return (letterGrade: 'B', gradePoint: 3.00, remarks: 'Satisfactory');
    } else if (rounded >= 55.0) {
      return (letterGrade: 'B-', gradePoint: 2.75, remarks: 'Above Average');
    } else if (rounded >= 50.0) {
      return (letterGrade: 'C+', gradePoint: 2.50, remarks: 'Average');
    } else if (rounded >= 45.0) {
      return (letterGrade: 'C', gradePoint: 2.25, remarks: 'Below Average');
    } else if (rounded >= 40.0) {
      return (letterGrade: 'D', gradePoint: 2.00, remarks: 'Pass');
    } else {
      return (letterGrade: 'F', gradePoint: 0.00, remarks: 'Fail');
    }
  }
}
