import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/performance_models.dart';
import '../services/exam_service.dart';

/// Provider for managing in-memory upcoming exam targets (fallback).
final upcomingExamsProvider = StateNotifierProvider<UpcomingExamsNotifier, List<UpcomingExam>>((ref) {
  return UpcomingExamsNotifier();
});

class UpcomingExamsNotifier extends StateNotifier<List<UpcomingExam>> {
  UpcomingExamsNotifier() : super(const []);

  void addExam(UpcomingExam exam) {
    state = [...state, exam];
  }

  void addRecurringExams({
    required String examName,
    required String subject,
    required double totalMarks,
    required DateTime startDate,
    required String recurringType,
    required int occurrences,
  }) {
    if (recurringType == 'None' || occurrences <= 1) {
      final singleExam = UpcomingExam(
        id: 'exam_${DateTime.now().millisecondsSinceEpoch}',
        examName: examName,
        subject: subject,
        totalMarks: totalMarks,
        targetDate: startDate,
        recurringType: 'None',
      );
      addExam(singleExam);
      return;
    }

    final groupId = 'rec_grp_${DateTime.now().millisecondsSinceEpoch}';
    final List<UpcomingExam> generated = [];

    for (int i = 0; i < occurrences; i++) {
      DateTime targetDate;
      if (recurringType == 'Weekly') {
        targetDate = startDate.add(Duration(days: 7 * i));
      } else {
        targetDate = DateTime(
          startDate.year,
          startDate.month + i,
          startDate.day,
        );
      }

      generated.add(
        UpcomingExam(
          id: 'exam_${groupId}_$i',
          examName: examName,
          subject: subject,
          totalMarks: totalMarks,
          targetDate: targetDate,
          recurringType: recurringType,
          recurringGroupId: groupId,
          occurrenceIndex: i + 1,
          totalOccurrences: occurrences,
        ),
      );
    }

    state = [...state, ...generated];
  }

  void updateSingleExam(UpcomingExam updatedExam) {
    state = state.map((e) => e.id == updatedExam.id ? updatedExam : e).toList();
  }

  void updateExamGroup({
    required String groupId,
    required String newName,
    required String newSubject,
    required double newTotalMarks,
  }) {
    state = state.map((e) {
      if (e.recurringGroupId == groupId) {
        return e.copyWith(
          examName: newName,
          subject: newSubject,
          totalMarks: newTotalMarks,
        );
      }
      return e;
    }).toList();
  }

  void deleteExam(String id) {
    state = state.where((e) => e.id != id).toList();
  }

  void deleteExamGroup(String groupId) {
    state = state.where((e) => e.recurringGroupId != groupId).toList();
  }
}

/// Global shared Provider deriving completed exam records from live Firestore `examsStreamProvider`
final allExamRecordsProvider = Provider<List<ExamRecord>>((ref) {
  final examsAsync = ref.watch(examsStreamProvider);
  final allExams = examsAsync.asData?.value ?? [];

  return allExams
      .where((e) => e.isCompleted && !e.isAbsent)
      .map((e) => ExamRecord(
            id: e.id,
            examName: e.examName,
            subject: e.subject,
            marks: e.marksObtained,
            totalMarks: e.totalMarks > 0 ? e.totalMarks : 100.0,
            meritPosition: e.meritPosition,
            date: e.date,
            isAbsent: e.isAbsent,
          ))
      .toList();
});

/// Total count of completed exams logged
final totalCompletedExamsCountProvider = Provider<int>((ref) {
  final records = ref.watch(allExamRecordsProvider);
  return records.length;
});

/// Global shared Provider for nearest upcoming exam derived from live Firestore `examsStreamProvider`
final nearestUpcomingExamProvider = Provider<UpcomingExam?>((ref) {
  final examsAsync = ref.watch(examsStreamProvider);
  final allExams = examsAsync.asData?.value ?? [];

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final upcomingList = allExams
      .where((e) => !e.isCompleted && !e.isAbsent && !e.date.isBefore(today.subtract(const Duration(hours: 12))))
      .toList();

  if (upcomingList.isEmpty) return null;

  upcomingList.sort((a, b) => a.date.compareTo(b.date));
  final nearest = upcomingList.first;

  return UpcomingExam(
    id: nearest.id,
    examName: nearest.examName,
    subject: nearest.subject,
    totalMarks: nearest.totalMarks,
    targetDate: nearest.date,
    recurringType: 'None',
    isAbsent: nearest.isAbsent,
  );
});

/// Provider for past exam records (synced with Firestore stream, with fallback to local notifier)
final examRecordsProvider = StateNotifierProvider<ExamRecordsNotifier, List<ExamRecord>>((ref) {
  final streamRecords = ref.watch(allExamRecordsProvider);
  final notifier = ExamRecordsNotifier();
  if (streamRecords.isNotEmpty) {
    notifier.setRecords(streamRecords);
  }
  return notifier;
});

class ExamRecordsNotifier extends StateNotifier<List<ExamRecord>> {
  ExamRecordsNotifier() : super(const []);

  void setRecords(List<ExamRecord> records) {
    state = records;
  }

  void addRecord(ExamRecord record) {
    state = [...state, record];
  }

  void updateRecord(ExamRecord updatedRecord) {
    state = state.map((r) => r.id == updatedRecord.id ? updatedRecord : r).toList();
  }

  void deleteRecord(String id) {
    state = state.where((r) => r.id != id).toList();
  }
}

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

/// Derived provider calculating improvement indicators comparing the latest 2 exams from live stream
final performanceImprovementProvider = Provider<PerformanceImprovement>((ref) {
  final records = ref.watch(allExamRecordsProvider);

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

  final marksDiff = latest.percentage - previous.percentage;
  final meritDiff = previous.meritPosition - latest.meritPosition;

  return PerformanceImprovement(
    marksDelta: marksDiff,
    meritDelta: meritDiff,
    isMarksImproved: marksDiff >= 0,
    isMeritImproved: meritDiff >= 0,
    hasEnoughData: true,
  );
});
