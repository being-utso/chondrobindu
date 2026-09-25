import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/add_course_screen.dart' show Teacher, WeightageDistribution, CourseModel;
export '../screens/add_course_screen.dart' show Teacher, WeightageDistribution, CourseModel, CourseDashboardScreen, CourseSyllabusScreen, CourseAttendanceScreen, CourseAttendanceAuditScreen;
export '../services/course_service.dart';

enum CourseType {
  theory,
  sessional,
  practical;

  String get displayName {
    switch (this) {
      case CourseType.theory:
        return 'Theory';
      case CourseType.sessional:
        return 'Sessional/Lab';
      case CourseType.practical:
        return 'Practical';
    }
  }

  static CourseType fromString(String? val) {
    if (val == null) return CourseType.theory;
    final v = val.toLowerCase().trim();
    if (v.contains('sessional') || v.contains('lab')) return CourseType.sessional;
    if (v.contains('practical')) return CourseType.practical;
    return CourseType.theory;
  }
}

class Course {
  final String id;
  final String code;          // e.g., "EEE 2105" or "PHY 101"
  final String title;         // e.g., "Signals & Systems" or "Physics 1st Paper"
  final CourseType courseType;// theory vs sessional vs practical
  final double credits;       // Uni credits (e.g., 3.0), or 1.0 for college subjects
  final String? colorHex;     // Accent card color
  final List<String> teacherInitials; // e.g. ["MSR", "ARH"]
  final int totalTopicsCount;
  final int completedTopicsCount;
  final bool isArchived;
  final String semester;
  final DateTime createdAt;

  const Course({
    required this.id,
    required this.code,
    required this.title,
    this.courseType = CourseType.theory,
    this.credits = 3.0,
    this.colorHex,
    this.teacherInitials = const [],
    this.totalTopicsCount = 0,
    this.completedTopicsCount = 0,
    this.isArchived = false,
    this.semester = 'Active',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? const _DefaultDateTime();

  double get progressPercentage => totalTopicsCount > 0
      ? (completedTopicsCount / totalTopicsCount) * 100
      : 0.0;

  // Compatibility aliases
  String get courseCode => code;
  String get courseName => title;
  String? get teacherBadge => teacherInitials.isNotEmpty ? teacherInitials.first : null;
  double get progressFraction => totalTopicsCount > 0
      ? (completedTopicsCount / totalTopicsCount).clamp(0.0, 1.0)
      : 0.0;
  double get creditHours => credits;
  CourseType get courseTypeEnum => courseType;
  bool get isTheory => courseType == CourseType.theory;
  bool get isSessional => courseType == CourseType.sessional || courseType == CourseType.practical;

  factory Course.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Course.fromMap(data, doc.id);
  }

  factory Course.fromMap(Map<String, dynamic> map, [String? docId]) {
    final id = docId ?? map['id'] as String? ?? '';
    final code = map['code'] as String? ?? map['courseCode'] as String? ?? '';
    final title = map['title'] as String? ?? map['courseName'] as String? ?? '';
    final cTypeStr = map['courseType'] as String?;
    final cType = CourseType.fromString(cTypeStr);
    final credits = (map['credits'] as num?)?.toDouble() ??
        (map['creditHours'] as num?)?.toDouble() ??
        1.0;
    final colorHex = map['colorHex'] as String?;
    final teachers = (map['teacherInitials'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        (map['teachers'] as List<dynamic>?)
            ?.map((e) => e is Map ? (e['initials'] ?? '').toString() : e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [];

    final total = (map['totalTopicsCount'] as num?)?.toInt() ?? 0;
    final completed = (map['completedTopicsCount'] as num?)?.toInt() ?? 0;
    final isArchived = map['isArchived'] as bool? ?? false;
    final semester = map['semester'] as String? ?? 'Active';

    DateTime? created;
    if (map['createdAt'] != null) {
      if (map['createdAt'] is Timestamp) {
        created = (map['createdAt'] as Timestamp).toDate();
      } else if (map['createdAt'] is String) {
        created = DateTime.tryParse(map['createdAt'] as String);
      }
    }

    return Course(
      id: id,
      code: code,
      title: title,
      courseType: cType,
      credits: credits,
      colorHex: colorHex,
      teacherInitials: teachers,
      totalTopicsCount: total,
      completedTopicsCount: completed,
      isArchived: isArchived,
      semester: semester,
      createdAt: created ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'title': title,
      'courseType': courseType.name,
      'credits': credits,
      'colorHex': colorHex,
      'teacherInitials': teacherInitials,
      'totalTopicsCount': totalTopicsCount,
      'completedTopicsCount': completedTopicsCount,
      'isArchived': isArchived,
      'semester': semester,
      'createdAt': Timestamp.fromDate(createdAt),
      // Legacy compatibility
      'courseCode': code,
      'courseName': title,
      'creditHours': credits,
    };
  }

  Course copyWith({
    String? id,
    String? code,
    String? title,
    CourseType? courseType,
    double? credits,
    String? colorHex,
    List<String>? teacherInitials,
    int? totalTopicsCount,
    int? completedTopicsCount,
    bool? isArchived,
    String? semester,
    DateTime? createdAt,
  }) {
    return Course(
      id: id ?? this.id,
      code: code ?? this.code,
      title: title ?? this.title,
      courseType: courseType ?? this.courseType,
      credits: credits ?? this.credits,
      colorHex: colorHex ?? this.colorHex,
      teacherInitials: teacherInitials ?? this.teacherInitials,
      totalTopicsCount: totalTopicsCount ?? this.totalTopicsCount,
      completedTopicsCount: completedTopicsCount ?? this.completedTopicsCount,
      isArchived: isArchived ?? this.isArchived,
      semester: semester ?? this.semester,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class _DefaultDateTime implements DateTime {
  const _DefaultDateTime();
  @override
  dynamic noSuchMethod(Invocation invocation) => DateTime(2026, 1, 1);
}
