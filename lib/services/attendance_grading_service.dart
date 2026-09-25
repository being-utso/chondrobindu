import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Represents a single attendance tier / slab (e.g. >= 80% awards 100% of weightage)
class AttendanceMarkSlab {
  final double minPercentage; // e.g. 80.0
  final double maxPercentage; // e.g. 100.0
  final double awardRatio; // e.g. 1.0 for 100%, 0.9 for 90%, 0.0 for discollegiate
  final String label;

  const AttendanceMarkSlab({
    required this.minPercentage,
    required this.maxPercentage,
    required this.awardRatio,
    required this.label,
  });

  Map<String, dynamic> toMap() {
    return {
      'minPercentage': minPercentage,
      'maxPercentage': maxPercentage,
      'awardRatio': awardRatio,
      'label': label,
    };
  }

  factory AttendanceMarkSlab.fromMap(Map<String, dynamic> map) {
    return AttendanceMarkSlab(
      minPercentage: (map['minPercentage'] as num?)?.toDouble() ?? 0.0,
      maxPercentage: (map['maxPercentage'] as num?)?.toDouble() ?? 100.0,
      awardRatio: (map['awardRatio'] as num?)?.toDouble() ?? 0.0,
      label: map['label'] as String? ?? '',
    );
  }

  AttendanceMarkSlab copyWith({
    double? minPercentage,
    double? maxPercentage,
    double? awardRatio,
    String? label,
  }) {
    return AttendanceMarkSlab(
      minPercentage: minPercentage ?? this.minPercentage,
      maxPercentage: maxPercentage ?? this.maxPercentage,
      awardRatio: awardRatio ?? this.awardRatio,
      label: label ?? this.label,
    );
  }
}

/// Service managing step-based attendance marks calculation (BUET/UGC style)
class AttendanceGradingService {
  /// Default university tiers for standard attendance distribution
  /// * Attendance >= 80%: 100% of weightage
  /// * 75% <= Attendance < 80%: 90%
  /// * 70% <= Attendance < 75%: 80%
  /// * 65% <= Attendance < 70%: 70%
  /// * 60% <= Attendance < 65%: 60%
  /// * Attendance < 60%: 0% (Discollegiate)
  static const List<AttendanceMarkSlab> defaultSlabs = [
    AttendanceMarkSlab(
      minPercentage: 80.0,
      maxPercentage: 100.0,
      awardRatio: 1.0,
      label: '≥ 80% (100% - Full Marks)',
    ),
    AttendanceMarkSlab(
      minPercentage: 75.0,
      maxPercentage: 80.0,
      awardRatio: 0.9,
      label: '75% to < 80% (90%)',
    ),
    AttendanceMarkSlab(
      minPercentage: 70.0,
      maxPercentage: 75.0,
      awardRatio: 0.8,
      label: '70% to < 75% (80%)',
    ),
    AttendanceMarkSlab(
      minPercentage: 65.0,
      maxPercentage: 70.0,
      awardRatio: 0.7,
      label: '65% to < 70% (70%)',
    ),
    AttendanceMarkSlab(
      minPercentage: 60.0,
      maxPercentage: 65.0,
      awardRatio: 0.6,
      label: '60% to < 65% (60%)',
    ),
    AttendanceMarkSlab(
      minPercentage: 0.0,
      maxPercentage: 60.0,
      awardRatio: 0.0,
      label: '< 60% (0% - Discollegiate)',
    ),
  ];

  /// Finds the matching slab for a given attendance rate (0% - 100%)
  static AttendanceMarkSlab getMatchingSlab({
    required double attendanceRate,
    List<AttendanceMarkSlab>? customSlabs,
  }) {
    final slabs = (customSlabs != null && customSlabs.isNotEmpty) ? customSlabs : defaultSlabs;
    final clampedRate = attendanceRate.clamp(0.0, 100.0);

    for (final slab in slabs) {
      if (clampedRate >= slab.minPercentage &&
          (clampedRate < slab.maxPercentage || (slab.maxPercentage >= 100.0 && clampedRate <= 100.0))) {
        return slab;
      }
    }

    // Fallback: return highest if above max, or lowest if below min
    if (clampedRate >= 80.0) return slabs.first;
    return slabs.last;
  }

  /// Calculates earned marks dynamically based on attendance percentage and weightage
  /// (e.g. 7/8 = 87.5% with 10% weight awards 10.0 pts; with 8% weight awards 8.0 pts)
  static double calculateAttendanceMarks({
    required double attendanceRate,
    required double attendanceWeightage,
    List<AttendanceMarkSlab>? customSlabs,
  }) {
    if (attendanceWeightage <= 0) return 0.0;
    final slab = getMatchingSlab(attendanceRate: attendanceRate, customSlabs: customSlabs);
    return double.parse((slab.awardRatio * attendanceWeightage).toStringAsFixed(2));
  }

  /// Helper to parse custom slabs from a Firestore course document map or list
  static List<AttendanceMarkSlab> parseSlabs(dynamic raw) {
    if (raw == null) return List.from(defaultSlabs);
    if (raw is List) {
      try {
        final parsed = raw
            .whereType<Map>()
            .map((m) => AttendanceMarkSlab.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        if (parsed.isNotEmpty) return parsed;
      } catch (e) {
        debugPrint('Error parsing attendance slabs: $e');
      }
    }
    return List.from(defaultSlabs);
  }

  /// Saves custom slabs for a specific course in Firestore
  static Future<void> saveCourseSlabs({
    required String uid,
    required String courseId,
    required List<AttendanceMarkSlab> slabs,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('courses')
          .doc(courseId)
          .set({
        'assessments': {
          'attendanceSlabs': slabs.map((s) => s.toMap()).toList(),
        }
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving course attendance slabs: $e');
    }
  }
}
