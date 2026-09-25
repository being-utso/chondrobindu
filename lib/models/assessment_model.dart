import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

/// Generates a lightweight unique ID for assessments
String generateAssessmentId([String prefix = 'assess']) {
  final random = Random().nextInt(999999);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_${timestamp}_$random';
}

/// Canonical Theory assessment types
const List<String> kTheoryAssessmentTypes = [
  'Class Test (CT)',
  'Quiz',
  'Midterm Exam',
  'Term Final Exam',
  'Assignment / Presentation',
];

/// Canonical Sessional / Lab assessment types
const List<String> kSessionalAssessmentTypes = [
  'Continuous Evaluation / Lab Performance',
  'Lab Report / Assignment',
  'Lab Quiz',
  'Lab Final Exam',
  'Viva Voce',
  'Term Project / Presentation',
];

/// Canonical College assessment types (Higher Secondary / Intermediate)
const List<String> kCollegeAssessmentTypes = [
  'Class Test',
  'Monthly Assessment',
  'Term Exam',
  'Half-Yearly Exam',
  'Pre-Test Exam',
  'Test Exam',
  'Model Test',
  'Board Practical Exam',
];

/// Dynamic Assessment Model replacing rigid grading fields and unifying Course CTs & Planner Assessments
class Assessment {
  final String id;
  String courseId;
  String courseCode;
  String? userId;
  String name; // e.g. "CT 1", "CT 2", "Midterm Exam", "Lab Final"
  String type; // 'ct', 'quiz', 'midterm', 'final', 'assignment', 'other'
  DateTime? date; // Nullable: null for unscheduled / backfilled CTs
  double totalMarks;
  double? obtainedMarks; // Nullable: null means unrecorded / pending
  double weightage; // percentage e.g. 10.0 for 10%, 20.0 for 20%
  String status; // 'Pending', 'Attended', 'Missed', 'Postponed', 'Unrecorded'
  DateTime? postponedToDate;
  String? postponedFromId;
  String? postponedToId;
  String? syllabusSummary; // Topics / Syllabus Covered
  String? assignedTeacherId; // Optional UUID of assigned instructor

  Assessment({
    String? id,
    this.courseId = '',
    this.courseCode = '',
    this.userId,
    String name = '',
    String type = 'ct',
    DateTime? date,
    double totalMarks = 20.0,
    double? obtainedMarks,
    double weightage = 10.0,
    this.status = 'Pending',
    this.postponedToDate,
    this.postponedFromId,
    this.postponedToId,
    this.syllabusSummary,
    String? assignedTeacherId,
    double? obtained,
    double? total,
    String? title,
    String? assessmentType,
    double? weightPercentage,
    String? assignedTeacher,
    DateTime? dueDate,
  })  : id = (id != null && id.isNotEmpty) ? id : generateAssessmentId('assess'),
        name = (title != null && title.isNotEmpty) ? title : (name.isNotEmpty ? name : 'Assessment'),
        type = (assessmentType != null && assessmentType.isNotEmpty) ? assessmentType : type,
        weightage = weightPercentage ?? weightage,
        totalMarks = total ?? totalMarks,
        obtainedMarks = obtained ?? obtainedMarks,
        assignedTeacherId = assignedTeacher ?? assignedTeacherId,
        date = dueDate ?? date;

  String get assessmentType => type;
  set assessmentType(String val) => type = val;

  double get weightPercentage => weightage;
  set weightPercentage(double val) => weightage = val;

  String? get assignedTeacher => assignedTeacherId;
  set assignedTeacher(String? val) => assignedTeacherId = val;

  bool get isCompleted =>
      status.toLowerCase() == 'attended' ||
      status.toLowerCase() == 'completed' ||
      obtainedMarks != null;

  /// Helpful aliases matching user prompt
  DateTime? get dueDate => date;
  set dueDate(DateTime? val) => date = val;

  String? get topics => syllabusSummary;
  set topics(String? val) => syllabusSummary = val;

  String get title => name;
  set title(String val) => name = val;

  String? get topicsSummary => syllabusSummary;
  set topicsSummary(String? val) => syllabusSummary = val;

  /// In-place mutation helpers for UI table cells
  double get obtained => obtainedMarks ?? 0.0;
  set obtained(double val) {
    obtainedMarks = val;
    if (status == 'Pending' || status == 'Unrecorded') {
      status = 'Attended';
    }
  }

  double get total => totalMarks;
  set total(double val) {
    totalMarks = val;
  }

  /// Whether marks have been recorded for this assessment
  bool get isRecorded => obtainedMarks != null;

  /// Whether this assessment has a scheduled date
  bool get isScheduled => date != null;

  double get percentage =>
      (totalMarks > 0 && obtainedMarks != null) ? (obtainedMarks! / totalMarks) * 100.0 : 0.0;

  double get weightedScore =>
      (totalMarks > 0 && obtainedMarks != null) ? (obtainedMarks! / totalMarks) * weightage : 0.0;

  String? get attendanceStatus {
    final s = status.toLowerCase();
    if (s == 'attended') return 'attended';
    if (s == 'missed') return 'missed';
    if (s == 'postponed') return 'postponed';
    return null; // null indicates unmarked/scheduled
  }
  set attendanceStatus(String? val) {
    if (val == null || val.isEmpty || val == 'unmarked') {
      status = 'Pending';
    } else if (val.toLowerCase() == 'attended') {
      status = 'Attended';
    } else if (val.toLowerCase() == 'missed') {
      status = 'Missed';
    } else {
      status = val;
    }
  }

  bool get isPostponed => status.toLowerCase() == 'postponed';
  bool get isAttended => status.toLowerCase() == 'attended';
  bool get isMissed => status.toLowerCase() == 'missed';
  bool get isPending =>
      status.toLowerCase() == 'pending' ||
      status.toLowerCase() == 'unmarked' ||
      status.toLowerCase() == 'unrecorded';

  Assessment copyWith({
    String? id,
    String? courseId,
    String? userId,
    String? name,
    String? type,
    DateTime? date,
    DateTime? dueDate,
    double? totalMarks,
    double? obtainedMarks,
    double? weightage,
    String? status,
    DateTime? postponedToDate,
    String? postponedFromId,
    String? postponedToId,
    String? syllabusSummary,
    String? assignedTeacherId,
  }) {
    return Assessment(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseCode: courseCode ?? courseCode,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      date: dueDate ?? date ?? this.date,
      totalMarks: totalMarks ?? this.totalMarks,
      obtainedMarks: obtainedMarks ?? this.obtainedMarks,
      weightage: weightage ?? this.weightage,
      status: status ?? this.status,
      postponedToDate: postponedToDate ?? this.postponedToDate,
      postponedFromId: postponedFromId ?? this.postponedFromId,
      postponedToId: postponedToId ?? this.postponedToId,
      syllabusSummary: syllabusSummary ?? this.syllabusSummary,
      assignedTeacherId: assignedTeacherId ?? this.assignedTeacherId,
    );
  }

  factory Assessment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Assessment.fromMap(data, defaultId: doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'courseId': courseId,
      'courseCode': courseCode,
      if (userId != null && userId!.isNotEmpty) 'userId': userId,
      'name': name,
      'title': name,
      'type': type,
      'assessmentType': type,
      'date': date != null ? Timestamp.fromDate(date!) : null,
      'dueDate': date != null ? Timestamp.fromDate(date!) : null,
      'totalMarks': totalMarks,
      'obtainedMarks': obtainedMarks,
      'total': totalMarks,
      'obtained': obtainedMarks,
      'weightage': weightage,
      'weightPercentage': weightage,
      'status': status,
      'isCompleted': isCompleted,
      'postponedToDate': postponedToDate != null ? Timestamp.fromDate(postponedToDate!) : null,
      'postponedFromId': postponedFromId,
      'postponedToId': postponedToId,
      'syllabusSummary': syllabusSummary,
      'topics': syllabusSummary,
      if (assignedTeacherId != null && assignedTeacherId!.isNotEmpty) ...{
        'assignedTeacherId': assignedTeacherId,
        'assignedTeacher': assignedTeacherId,
      },
    };
  }

  factory Assessment.fromMap(Map<String, dynamic> map, {String? defaultCourseId, String? defaultId}) {
    DateTime? parsedDate;
    final rawDate = map['date'] ??
        map['dueDate'] ??
        map['due_date'] ??
        map['targetDate'] ??
        map['scheduledDate'] ??
        map['deadline'];
    if (rawDate != null) {
      if (rawDate is Timestamp) {
        parsedDate = rawDate.toDate();
      } else if (rawDate is String) {
        parsedDate = DateTime.tryParse(rawDate);
      } else if (rawDate is int) {
        parsedDate = DateTime.fromMillisecondsSinceEpoch(rawDate);
      } else if (rawDate is DateTime) {
        parsedDate = rawDate;
      }
    }

    DateTime? parsedPostponedDate;
    if (map['postponedToDate'] != null) {
      if (map['postponedToDate'] is Timestamp) {
        parsedPostponedDate = (map['postponedToDate'] as Timestamp).toDate();
      } else if (map['postponedToDate'] is String) {
        parsedPostponedDate = DateTime.tryParse(map['postponedToDate'] as String);
      }
    }

    final rawObtained = (map['obtainedMarks'] as num?)?.toDouble() ??
        ((map['obtained'] as num?)?.toDouble());

    String parsedStatus = map['status'] as String? ??
        (map['attendanceStatus'] as String? ?? 'Pending');
    if (map['status'] == null && map['attendanceStatus'] == null) {
      if (rawObtained != null && rawObtained > 0) {
        parsedStatus = 'Attended';
      } else {
        parsedStatus = 'Pending';
      }
    }

    final summary = map['syllabusSummary'] as String? ?? (map['topics'] as String?);

    // Auto-detect type from name if not explicit
    String detectedType = map['type'] as String? ?? 'ct';
    final nameLower = (map['name'] as String? ?? '').toLowerCase();
    if (nameLower.contains('midterm') || nameLower.contains('mid')) {
      detectedType = 'midterm';
    } else if (nameLower.contains('final')) {
      detectedType = 'final';
    } else if (nameLower.contains('quiz') || nameLower.contains('viva')) {
      detectedType = 'quiz';
    } else if (nameLower.contains('report') || nameLower.contains('assignment')) {
      detectedType = 'assignment';
    }

    return Assessment(
      id: map['id'] as String? ?? (defaultId ?? generateAssessmentId('assess')),
      courseId: map['courseId'] as String? ?? (defaultCourseId ?? ''),
      courseCode: map['courseCode'] as String? ?? '',
      userId: map['userId'] as String?,
      name: map['name'] as String? ?? (map['examName'] as String? ?? 'Assessment'),
      type: detectedType,
      date: parsedDate,
      totalMarks: (map['totalMarks'] as num?)?.toDouble() ??
          ((map['total'] as num?)?.toDouble() ?? 20.0),
      obtainedMarks: rawObtained,
      weightage: (map['weightage'] as num?)?.toDouble() ?? 10.0,
      status: parsedStatus,
      postponedToDate: parsedPostponedDate,
      postponedFromId: map['postponedFromId'] as String?,
      postponedToId: map['postponedToId'] as String?,
      syllabusSummary: summary,
      assignedTeacherId: map['assignedTeacherId'] as String?,
    );
  }

  /// Safely extracts and parses a list of Assessment objects from any raw Firestore
  /// assessments field or map. Handles:
  /// - Direct List<dynamic> of assessment maps
  /// - Category maps with lists: 'classTests', 'quizzesViva', 'quizzes', 'labReportsAssignments',
  ///   'continuousAssessment', 'labFinalPractical', 'assignments', 'items', etc.
  /// - Map of assessment IDs to assessment maps: {'assess_1': {...}, 'assess_2': {...}}
  /// - Single assessment map
  static List<Assessment> fromRawListOrMap(dynamic rawData, {String? defaultCourseId}) {
    if (rawData == null) return [];

    final List<Assessment> results = [];

    void extractFrom(dynamic obj) {
      if (obj == null) return;
      if (obj is List) {
        for (final item in obj) {
          extractFrom(item);
        }
      } else if (obj is Map) {
        final map = Map<String, dynamic>.from(obj);
        final bool hasName = map.containsKey('name') ||
            map.containsKey('title') ||
            map.containsKey('examName');
        final bool hasDates = map.containsKey('date') ||
            map.containsKey('dueDate') ||
            map.containsKey('due_date') ||
            map.containsKey('targetDate') ||
            map.containsKey('scheduledDate');
        final bool hasMarks = map.containsKey('totalMarks') ||
            map.containsKey('obtainedMarks') ||
            map.containsKey('total') ||
            map.containsKey('obtained');

        if (hasName && (hasDates || hasMarks || map.containsKey('id') || map.containsKey('type'))) {
          try {
            results.add(Assessment.fromMap(map, defaultCourseId: defaultCourseId));
          } catch (_) {}
          return;
        }

        const knownCategoryKeys = [
          'classTests',
          'quizzesViva',
          'quizzes',
          'labReportsAssignments',
          'labReports',
          'continuousAssessment',
          'labFinalPractical',
          'assignments',
          'items',
        ];

        for (final key in knownCategoryKeys) {
          if (map.containsKey(key) && map[key] != null) {
            extractFrom(map[key]);
          }
        }

        map.forEach((k, v) {
          if (!knownCategoryKeys.contains(k)) {
            if (v is List || v is Map) {
              extractFrom(v);
            }
          }
        });
      }
    }

    extractFrom(rawData);

    // Deduplicate results by ID if present
    final seenIds = <String>{};
    final uniqueResults = <Assessment>[];
    for (final a in results) {
      if (a.id.isNotEmpty && seenIds.contains(a.id)) {
        continue;
      }
      if (a.id.isNotEmpty) {
        seenIds.add(a.id);
      }
      uniqueResults.add(a);
    }

    return uniqueResults;
  }

  /// Parses all assessments contained in a Course document data map.
  /// Inspects data['assessments'] as well as top-level assessment arrays like
  /// data['classTests'], data['quizzes'], data['assignments'].
  static List<Assessment> fromCourseData(Map<String, dynamic> data, {required String courseId}) {
    final List<Assessment> all = [];

    // 1. Check data['assessments']
    if (data.containsKey('assessments') && data['assessments'] != null) {
      all.addAll(fromRawListOrMap(data['assessments'], defaultCourseId: courseId));
    }

    // 2. Check top-level arrays if present
    const topLevelKeys = [
      'classTests',
      'quizzesViva',
      'quizzes',
      'labReportsAssignments',
      'labReports',
      'continuousAssessment',
      'labFinalPractical',
      'assignments',
    ];
    for (final key in topLevelKeys) {
      if (data.containsKey(key) && data[key] != null) {
        all.addAll(fromRawListOrMap(data[key], defaultCourseId: courseId));
      }
    }

    // Deduplicate by ID and ensure courseId is set
    final seenIds = <String>{};
    final unique = <Assessment>[];
    for (final a in all) {
      if (a.courseId.isEmpty) {
        a.courseId = courseId;
      }
      if (a.id.isNotEmpty && seenIds.contains(a.id)) {
        continue;
      }
      if (a.id.isNotEmpty) {
        seenIds.add(a.id);
      }
      unique.add(a);
    }
    return unique;
  }
}

/// Aliases matching user prompt specifications and backward compatibility
typedef AssessmentModel = Assessment;
typedef AssessmentItem = Assessment;
