import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/exam_model.dart';
import 'notification_service.dart';

/// Provider exposing the ExamService instance
final examServiceProvider = Provider<ExamService>((ref) {
  return ExamService();
});

/// StreamProvider providing real-time list of exams for the logged-in user
final examsStreamProvider = StreamProvider<List<ExamModel>>((ref) {
  final examService = ref.watch(examServiceProvider);
  return examService.getExamsStream();
});

class ExamService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final NotificationService _notificationService;

  ExamService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    NotificationService? notificationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _notificationService = notificationService ?? NotificationService();

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>>? get _examCollection {
    final uid = _uid;
    if (uid == null || uid.isEmpty) return null;
    return _firestore.collection('users').doc(uid).collection('exams');
  }

  /// Extracts the base series name by stripping trailing number (e.g. "Weekly Exam 5" -> "Weekly Exam")
  static String extractBaseName(String name) {
    final trimmed = name.trim();
    final regex = RegExp(r'^(.*?)(?:\s+\d+)?$');
    final match = regex.firstMatch(trimmed);
    if (match != null && match.group(1) != null && match.group(1)!.trim().isNotEmpty) {
      return match.group(1)!.trim();
    }
    return trimmed;
  }

  /// Extracts trailing number if name matches baseName + number (e.g. "Weekly Exam 5" with base "Weekly Exam" -> 5)
  static int? extractTrailingNumber(String name, String baseName) {
    final pattern = RegExp('^' + RegExp.escape(baseName.trim()) + r'\s+(\d+)$', caseSensitive: false);
    final match = pattern.firstMatch(name.trim());
    if (match != null && match.group(1) != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Queries Firestore for existing exams matching base name and extracts the highest trailing number
  Future<int> getHighestExamNumber(String baseName) async {
    final collection = _examCollection;
    if (collection == null) return 0;

    final cleanBase = extractBaseName(baseName).toLowerCase();
    int highest = 0;

    try {
      final snapshot = await collection.get();
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final examName = (data['examName'] as String?)?.trim() ?? '';
        final docBase = extractBaseName(examName).toLowerCase();

        if (docBase == cleanBase) {
          final trailingNum = extractTrailingNumber(examName, extractBaseName(examName));
          if (trailingNum != null && trailingNum > highest) {
            highest = trailingNum;
          } else if (examName.toLowerCase() == cleanBase && highest == 0) {
            highest = 1;
          }
        }
      }
      return highest;
    } catch (e) {
      debugPrint('Error getting highest exam number: $e');
      return 0;
    }
  }

  /// Stream of user exams from Firestore: users/{uid}/exams (strictly empty for new accounts)
  Stream<List<ExamModel>> getExamsStream() {
    final collection = _examCollection;
    if (collection == null) {
      return Stream.value(const <ExamModel>[]);
    }

    return collection
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return const <ExamModel>[];
      }
      return snapshot.docs
          .map((doc) => ExamModel.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  /// Add a single new exam to Firestore & schedule exam reminders and 10-day score nudges
  Future<void> addExam(ExamModel exam) async {
    final collection = _examCollection;
    if (collection == null) return;

    try {
      final docRef = collection.doc();
      final newExam = exam.copyWith(id: docRef.id);
      await docRef.set(newExam.toMap());

      await _notificationService.scheduleExamReminder(
        examId: newExam.id,
        subject: newExam.subject,
        examDate: newExam.date,
      );

      // Task 2: 10-Day Post-Exam "Score Log" Nudge
      await _notificationService.schedulePostExamScoreNudge(
        examId: newExam.id,
        subject: newExam.subject,
        examDate: newExam.date,
      );
    } catch (e) {
      debugPrint('Error adding exam to Firestore: $e');
    }
  }

  /// Batch-add multiple recurring exams using Firestore WriteBatch & schedule reminders + 10-day score nudges
  Future<List<ExamModel>> addExamsBatch(List<ExamModel> exams) async {
    final collection = _examCollection;
    if (collection == null || exams.isEmpty) return [];

    try {
      final batch = _firestore.batch();
      final List<ExamModel> addedExams = [];

      for (final exam in exams) {
        final docRef = collection.doc();
        final newExam = exam.copyWith(id: docRef.id);
        batch.set(docRef, newExam.toMap());
        addedExams.add(newExam);
      }

      await batch.commit();

      // Schedule pre-exam reminders and 10-day post-exam score nudges for all batch-added exams
      for (final newExam in addedExams) {
        unawaited(_notificationService.scheduleExamReminder(
          examId: newExam.id,
          subject: newExam.subject,
          examDate: newExam.date,
        ));
        unawaited(_notificationService.schedulePostExamScoreNudge(
          examId: newExam.id,
          subject: newExam.subject,
          examDate: newExam.date,
        ));
      }

      return addedExams;
    } catch (e) {
      debugPrint('Error adding exams batch to Firestore: $e');
      return [];
    }
  }

  /// Update an existing exam in Firestore and reschedule reminders
  Future<void> updateExam(ExamModel exam) async {
    final collection = _examCollection;
    if (collection == null || exam.id.isEmpty) return;

    try {
      await collection.doc(exam.id).update(exam.toMap());

      await _notificationService.scheduleExamReminder(
        examId: exam.id,
        subject: exam.subject,
        examDate: exam.date,
      );
      await _notificationService.schedulePostExamScoreNudge(
        examId: exam.id,
        subject: exam.subject,
        examDate: exam.date,
      );
    } catch (e) {
      debugPrint('Error updating exam in Firestore: $e');
    }
  }

  /// Shift all subsequent exams in a series by a Duration difference using WriteBatch
  Future<int> shiftSubsequentExamDates({
    required String baseSeriesName,
    required DateTime originalDate,
    required Duration shiftDuration,
    required String currentExamId,
  }) async {
    final collection = _examCollection;
    if (collection == null || shiftDuration.inSeconds == 0) return 0;

    try {
      final snapshot = await collection.get();
      final cleanBase = extractBaseName(baseSeriesName).toLowerCase();
      final batch = _firestore.batch();
      int countShifted = 0;

      for (final doc in snapshot.docs) {
        if (doc.id == currentExamId) continue;

        final data = doc.data();
        final examName = (data['examName'] as String?)?.trim() ?? '';
        final docBase = extractBaseName(examName).toLowerCase();

        if (docBase == cleanBase) {
          final isCompleted = (data['isCompleted'] as bool?) ?? false;
          final isAbsent = (data['isAbsent'] as bool?) ?? false;
          if (isCompleted || isAbsent) continue;

          final dynamic rawDate = data['date'];
          DateTime examDate;
          if (rawDate is Timestamp) {
            examDate = rawDate.toDate();
          } else if (rawDate is String) {
            examDate = DateTime.tryParse(rawDate) ?? DateTime.now();
          } else {
            continue;
          }

          // Shift exams that occur after the original date
          if (examDate.isAfter(originalDate)) {
            final newDate = examDate.add(shiftDuration);
            batch.update(doc.reference, {
              'date': Timestamp.fromDate(newDate),
              'targetDate': Timestamp.fromDate(newDate),
            });

            // Reschedule notification reminders for the shifted exam
            final subj = (data['subject'] as String?) ?? 'Exam';
            unawaited(_notificationService.scheduleExamReminder(
              examId: doc.id,
              subject: subj,
              examDate: newDate,
            ));
            unawaited(_notificationService.schedulePostExamScoreNudge(
              examId: doc.id,
              subject: subj,
              examDate: newDate,
            ));

            countShifted++;
          }
        }
      }

      if (countShifted > 0) {
        await batch.commit();
      }

      return countShifted;
    } catch (e) {
      debugPrint('Error shifting subsequent exam dates via WriteBatch: $e');
      return 0;
    }
  }

  /// Log score for an exam, optionally saving journal entries (mistakes & tips/tricks)
  Future<void> logScore({
    required String examId,
    required double marksObtained,
    required int meritPosition,
    List<JournalEntry>? journalEntries,
  }) async {
    final collection = _examCollection;
    if (collection == null || examId.isEmpty) return;

    try {
      final updateData = <String, dynamic>{
        'marksObtained': marksObtained,
        'meritPosition': meritPosition,
        'isCompleted': true,
        'isAbsent': false,
      };

      if (journalEntries != null) {
        updateData['journal_entries'] =
            journalEntries.where((e) => e.content.trim().isNotEmpty).map((e) => e.toMap()).toList();
      }

      await collection.doc(examId).update(updateData);
      await _notificationService.cancelExamReminder(examId);
      await _notificationService.cancelPostExamScoreNudge(examId);
    } catch (e) {
      debugPrint('Error logging score in Firestore: $e');
    }
  }

  /// Mark an exam as unattended / absent
  Future<void> markAbsent({
    required String examId,
    bool isAbsent = true,
  }) async {
    final collection = _examCollection;
    if (collection == null || examId.isEmpty) return;

    try {
      await collection.doc(examId).update({
        'isAbsent': isAbsent,
        'isCompleted': isAbsent,
      });
      await _notificationService.cancelExamReminder(examId);
      await _notificationService.cancelPostExamScoreNudge(examId);
    } catch (e) {
      debugPrint('Error marking exam absent in Firestore: $e');
    }
  }

  /// Delete an exam and cancel its scheduled reminders & score nudges
  Future<void> deleteExam(String examId) async {
    final collection = _examCollection;
    if (collection == null || examId.isEmpty) return;

    try {
      await collection.doc(examId).delete();
      await _notificationService.cancelExamReminder(examId);
      await _notificationService.cancelPostExamScoreNudge(examId);
    } catch (e) {
      debugPrint('Error deleting exam in Firestore: $e');
    }
  }
}
