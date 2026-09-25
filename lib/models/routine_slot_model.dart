import 'package:cloud_firestore/cloud_firestore.dart';
import 'course_model.dart';

/// Routine Slot Model inside `/users/{uid}/routine_slots/{slotId}`
class RoutineSlot {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseTitle;
  final int dayOfWeek;        // 1 = Monday ... 7 = Sunday
  final String startTime;     // "10:00 AM"
  final String endTime;       // "11:30 AM"
  final String room;          // "LT-1, Room 302"
  final String? teacherBadge; // "MSR"
  final CourseType slotType;  // theory vs sessional/practical
  final DateTime? effectiveFrom;
  final DateTime? effectiveUntil;

  const RoutineSlot({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseTitle,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.room = '',
    this.teacherBadge,
    this.slotType = CourseType.theory,
    this.effectiveFrom,
    this.effectiveUntil,
  });

  /// Convenience getter for time range string (e.g. "10:00 AM - 11:30 AM")
  String get timeRange => '$startTime - $endTime';
  String get courseName => courseTitle;
  String get roomNumber => room;

  factory RoutineSlot.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return RoutineSlot.fromMap(data, doc.id);
  }

  factory RoutineSlot.fromMap(Map<String, dynamic> map, [String? docId]) {
    final id = docId ?? map['id'] as String? ?? '';
    final courseId = map['courseId'] as String? ?? '';
    final courseCode = map['courseCode'] as String? ?? '';
    final courseTitle = map['courseTitle'] as String? ?? map['courseName'] as String? ?? '';
    final day = (map['dayOfWeek'] as num?)?.toInt() ?? 1;
    final start = map['startTime'] as String? ?? '08:00 AM';
    final end = map['endTime'] as String? ?? '09:00 AM';
    final room = map['room'] as String? ?? '';
    final teacher = map['teacherBadge'] as String? ?? map['teacher'] as String?;
    final sType = CourseType.fromString(map['slotType'] as String? ?? map['courseType'] as String?);

    DateTime? effFrom;
    if (map['effectiveFrom'] != null) {
      if (map['effectiveFrom'] is Timestamp) {
        effFrom = (map['effectiveFrom'] as Timestamp).toDate();
      } else if (map['effectiveFrom'] is String) {
        effFrom = DateTime.tryParse(map['effectiveFrom'] as String);
      }
    }

    DateTime? effUntil;
    if (map['effectiveUntil'] != null) {
      if (map['effectiveUntil'] is Timestamp) {
        effUntil = (map['effectiveUntil'] as Timestamp).toDate();
      } else if (map['effectiveUntil'] is String) {
        effUntil = DateTime.tryParse(map['effectiveUntil'] as String);
      }
    }

    return RoutineSlot(
      id: id,
      courseId: courseId,
      courseCode: courseCode,
      courseTitle: courseTitle,
      dayOfWeek: day,
      startTime: start,
      endTime: end,
      room: room,
      teacherBadge: teacher,
      slotType: sType,
      effectiveFrom: effFrom,
      effectiveUntil: effUntil,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'courseId': courseId,
      'courseCode': courseCode,
      'courseTitle': courseTitle,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'room': room,
      'teacherBadge': teacherBadge,
      'slotType': slotType.name,
      'effectiveFrom': effectiveFrom != null ? Timestamp.fromDate(effectiveFrom!) : null,
      'effectiveUntil': effectiveUntil != null ? Timestamp.fromDate(effectiveUntil!) : null,
    };
  }

  RoutineSlot copyWith({
    String? id,
    String? courseId,
    String? courseCode,
    String? courseTitle,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    String? room,
    String? teacherBadge,
    CourseType? slotType,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
  }) {
    return RoutineSlot(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseCode: courseCode ?? this.courseCode,
      courseTitle: courseTitle ?? this.courseTitle,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      room: room ?? this.room,
      teacherBadge: teacherBadge ?? this.teacherBadge,
      slotType: slotType ?? this.slotType,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveUntil: effectiveUntil ?? this.effectiveUntil,
    );
  }
}
