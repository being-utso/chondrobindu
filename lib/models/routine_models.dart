import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'assessment_model.dart';

/// Generates a lightweight unique ID for routine and attendance records
String generateRoutineId([String prefix = 'routine']) {
  final random = Random().nextInt(999999);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_${timestamp}_$random';
}

/// Status of an individual class attendance instance
enum AttendanceStatus {
  unmarked,
  attended,
  missed,
  canceled,
  extra;

  String get displayName {
    switch (this) {
      case AttendanceStatus.unmarked:
        return 'Unmarked';
      case AttendanceStatus.attended:
        return 'Attended';
      case AttendanceStatus.missed:
        return 'Missed';
      case AttendanceStatus.canceled:
        return 'Canceled';
      case AttendanceStatus.extra:
        return 'Extra';
    }
  }

  static AttendanceStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'attended':
        return AttendanceStatus.attended;
      case 'missed':
        return AttendanceStatus.missed;
      case 'canceled':
      case 'cancelled':
        return AttendanceStatus.canceled;
      case 'extra':
        return AttendanceStatus.extra;
      default:
        return AttendanceStatus.unmarked;
    }
  }
}

/// Academic / Calendar week helper for alternating/biweekly routine calculations
extension DateTimeWeekExtension on DateTime {
  /// Returns the academic / calendar week number of the year (1..53)
  int get weekOfYear {
    final firstDayOfYear = DateTime(year, 1, 1);
    final dayOfYear = difference(firstDayOfYear).inDays;
    return (dayOfYear / 7).floor() + 1;
  }
}

/// Model for a recurring weekly class in the university routine
class ClassRoutine {
  final String id;
  final String courseId;
  final String courseName;
  final int dayOfWeek; // 1 = Monday ... 7 = Sunday (Dart standard)
  final String startTime; // e.g., "09:00 AM" or "09:00"
  final String endTime; // e.g., "10:30 AM" or "10:30"
  final String classType; // e.g., "Theory", "Lab", "Sessional"
  final String? roomNumber;
  final String? teacherId; // Optional UUID of assigned instructor
  final bool isAlternating; // true if alternating weeks / bi-weekly lab
  final String recurrence; // 'weekly', 'biweekly_a' (Odd weeks), 'biweekly_b' (Even weeks)
  final String? pairedClassId; // ID of the alternating course slot (nullable)
  final DateTime? effectiveFrom; // lifecycle start boundary (inclusive)
  final DateTime? effectiveUntil; // lifecycle end boundary (inclusive)
  final List<String> swapWeeks; // e.g. ['2026-W37'] weeks where biweekly rotation is inverted

  ClassRoutine({
    String? id,
    required this.courseId,
    required this.courseName,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.classType = 'Theory',
    this.roomNumber,
    this.teacherId,
    bool isAlternating = false,
    String? recurrence,
    this.pairedClassId,
    this.effectiveFrom,
    this.effectiveUntil,
    this.swapWeeks = const [],
  })  : id = (id != null && id.isNotEmpty) ? id : generateRoutineId('class'),
        recurrence = (recurrence != null && recurrence.isNotEmpty)
            ? recurrence
            : (isAlternating ? 'biweekly_a' : 'weekly'),
        isAlternating = (recurrence == 'biweekly_a' || recurrence == 'biweekly_b') ||
            ((recurrence == null || recurrence.isEmpty) && isAlternating);

  String get dayName {
    switch (dayOfWeek) {
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      default:
        return 'Day $dayOfWeek';
    }
  }

  String get dayShortName {
    switch (dayOfWeek) {
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      default:
        return 'Day $dayOfWeek';
    }
  }

  /// Checks if this routine is active on the given calendar date respecting dayOfWeek, recurrence, and lifecycle boundaries
  bool isActiveOnDate(DateTime date) {
    if (date.weekday != dayOfWeek) return false;
    final d = DateTime(date.year, date.month, date.day);
    if (effectiveFrom != null) {
      final start = DateTime(effectiveFrom!.year, effectiveFrom!.month, effectiveFrom!.day);
      if (d.isBefore(start)) return false;
    }
    if (effectiveUntil != null) {
      final end = DateTime(effectiveUntil!.year, effectiveUntil!.month, effectiveUntil!.day);
      if (d.isAfter(end)) return false;
    }
    final weekKey = '${date.year}-W${date.weekOfYear}';
    final isSwapped = swapWeeks.contains(weekKey);
    if (recurrence == 'biweekly_a') {
      // Week A / Odd weeks: weekOfYear % 2 != 0 normally, inverted if swapped
      final isOdd = date.weekOfYear % 2 != 0;
      if (isSwapped ? isOdd : !isOdd) return false;
    } else if (recurrence == 'biweekly_b') {
      // Week B / Even weeks: weekOfYear % 2 == 0 normally, inverted if swapped
      final isEven = date.weekOfYear % 2 == 0;
      if (isSwapped ? isEven : !isEven) return false;
    }
    return true;
  }

  /// Whether this slot has a temporary biweekly turn swap active for the given date's academic week
  bool isSwappedForDate(DateTime date) {
    final weekKey = '${date.year}-W${date.weekOfYear}';
    return swapWeeks.contains(weekKey);
  }

  ClassRoutine copyWith({
    String? id,
    String? courseId,
    String? courseName,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    String? classType,
    String? roomNumber,
    String? teacherId,
    bool? isAlternating,
    String? recurrence,
    String? pairedClassId,
    DateTime? effectiveFrom,
    DateTime? effectiveUntil,
    List<String>? swapWeeks,
  }) {
    final effectiveRecurrence = recurrence ?? this.recurrence;
    final effectiveIsAlternating = isAlternating ??
        (recurrence != null
            ? (recurrence == 'biweekly_a' || recurrence == 'biweekly_b')
            : this.isAlternating);

    return ClassRoutine(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseName: courseName ?? this.courseName,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      classType: classType ?? this.classType,
      roomNumber: roomNumber ?? this.roomNumber,
      teacherId: teacherId ?? this.teacherId,
      isAlternating: effectiveIsAlternating,
      recurrence: effectiveRecurrence,
      pairedClassId: pairedClassId ?? this.pairedClassId,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      effectiveUntil: effectiveUntil ?? this.effectiveUntil,
      swapWeeks: swapWeeks ?? this.swapWeeks,
    );
  }

  String get courseCode => RoutineCourseSyncService.parseCourseCode(courseName.isNotEmpty ? courseName : courseId);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'courseId': courseId,
      'courseName': courseName,
      'courseCode': courseCode,
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
      'classType': classType,
      'roomNumber': roomNumber,
      if (teacherId != null) 'teacherId': teacherId,
      'isAlternating': isAlternating,
      'recurrence': recurrence,
      if (pairedClassId != null) 'pairedClassId': pairedClassId,
      if (effectiveFrom != null) 'effectiveFrom': Timestamp.fromDate(effectiveFrom!),
      if (effectiveUntil != null) 'effectiveUntil': Timestamp.fromDate(effectiveUntil!),
      if (swapWeeks.isNotEmpty) 'swapWeeks': swapWeeks,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory ClassRoutine.fromMap(Map<String, dynamic> map, {String? defaultId}) {
    DateTime? parseOptDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    final rawRecurrence = map['recurrence'] as String?;
    final legacyAlternating = map['isAlternating'] as bool? ?? false;
    final effectiveRecurrence = rawRecurrence ?? (legacyAlternating ? 'biweekly_a' : 'weekly');

    return ClassRoutine(
      id: map['id'] as String? ?? (defaultId ?? generateRoutineId('class')),
      courseId: map['courseId'] as String? ?? '',
      courseName: map['courseName'] as String? ?? (map['courseCode'] as String? ?? 'Untitled Course'),
      dayOfWeek: (map['dayOfWeek'] as num?)?.toInt() ?? DateTime.monday,
      startTime: map['startTime'] as String? ?? '09:00 AM',
      endTime: map['endTime'] as String? ?? '10:00 AM',
      classType: map['classType'] as String? ?? 'Theory',
      roomNumber: map['roomNumber'] as String?,
      teacherId: map['teacherId'] as String?,
      isAlternating: legacyAlternating || effectiveRecurrence != 'weekly',
      recurrence: effectiveRecurrence,
      pairedClassId: map['pairedClassId'] as String?,
      effectiveFrom: parseOptDate(map['effectiveFrom']),
      effectiveUntil: parseOptDate(map['effectiveUntil']),
      swapWeeks: (map['swapWeeks'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  /// Sorts a list of ClassRoutine objects strictly chronologically by time
  static List<ClassRoutine> sortRoutinesByTime(List<ClassRoutine> routines) =>
      RoutineCourseSyncService.sortRoutinesByTime(routines);
}

/// Type alias for ClassRoutine representing a single recurring timetable slot
typedef ClassRoutineSlot = ClassRoutine;

/// Model for one-off and permanent routine slot substitutions and swaps
class RoutineSlotOverride {
  final String overrideId;
  final String originalSlotId;
  final String targetDate; // ISO formatted YYYY-MM-DD
  final String replacementCourseId;
  final String? replacementCourseName;
  final String? replacementTeacherId;
  final bool isTemporarySwap;

  const RoutineSlotOverride({
    required this.overrideId,
    required this.originalSlotId,
    required this.targetDate,
    required this.replacementCourseId,
    this.replacementCourseName,
    this.replacementTeacherId,
    this.isTemporarySwap = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'overrideId': overrideId,
      'originalSlotId': originalSlotId,
      'targetDate': targetDate,
      'replacementCourseId': replacementCourseId,
      if (replacementCourseName != null) 'replacementCourseName': replacementCourseName,
      if (replacementTeacherId != null) 'replacementTeacherId': replacementTeacherId,
      'isTemporarySwap': isTemporarySwap,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory RoutineSlotOverride.fromMap(Map<String, dynamic> map, {String? defaultId}) {
    return RoutineSlotOverride(
      overrideId: map['overrideId'] as String? ?? (defaultId ?? generateRoutineId('ovr')),
      originalSlotId: map['originalSlotId'] as String? ?? '',
      targetDate: map['targetDate'] as String? ?? '',
      replacementCourseId: map['replacementCourseId'] as String? ?? '',
      replacementCourseName: map['replacementCourseName'] as String?,
      replacementTeacherId: map['replacementTeacherId'] as String?,
      isTemporarySwap: map['isTemporarySwap'] as bool? ?? true,
    );
  }
}

/// Model for a date-specific class attendance state
class AttendanceRecord {
  final String id;
  final String courseId;
  final String? courseCode;
  final DateTime date;
  final AttendanceStatus status;
  final String? routineId;
  final String? teacherId;
  final String? courseName;
  final String? classType;
  final String? time;
  final String? topic;

  AttendanceRecord({
    String? id,
    required this.courseId,
    this.courseCode,
    required this.date,
    this.status = AttendanceStatus.unmarked,
    this.routineId,
    this.teacherId,
    this.courseName,
    this.classType,
    this.time,
    this.topic,
  }) : id = (id != null && id.isNotEmpty) ? id : generateRoutineId('att');

  AttendanceRecord copyWith({
    String? id,
    String? courseId,
    String? courseCode,
    DateTime? date,
    AttendanceStatus? status,
    String? routineId,
    String? teacherId,
    String? courseName,
    String? classType,
    String? time,
    String? topic,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      courseId: courseId ?? this.courseId,
      courseCode: courseCode ?? this.courseCode,
      date: date ?? this.date,
      status: status ?? this.status,
      routineId: routineId ?? this.routineId,
      teacherId: teacherId ?? this.teacherId,
      courseName: courseName ?? this.courseName,
      classType: classType ?? this.classType,
      time: time ?? this.time,
      topic: topic ?? this.topic,
    );
  }

  Map<String, dynamic> toMap() {
    final effectiveCode = courseCode ??
        RoutineCourseSyncService.parseCourseCode(courseName ?? courseId);
    return {
      'id': id,
      'courseId': courseId,
      'courseCode': effectiveCode,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'status': status.name,
      'routineId': routineId,
      if (teacherId != null) 'teacherId': teacherId,
      'courseName': courseName,
      'classType': classType,
      'time': time,
      'topic': topic,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory AttendanceRecord.fromMap(Map<String, dynamic> map, {String? defaultId}) {
    DateTime parsedDate = DateTime.now();
    if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        parsedDate = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        parsedDate = DateTime.tryParse(map['date'] as String) ?? DateTime.now();
      }
    }

    final parsedCourseCode = map['courseCode'] as String? ??
        RoutineCourseSyncService.parseCourseCode(
            map['courseName'] as String? ?? map['courseId'] as String? ?? '');

    return AttendanceRecord(
      id: map['id'] as String? ?? (defaultId ?? generateRoutineId('att')),
      courseId: map['courseId'] as String? ?? '',
      courseCode: parsedCourseCode,
      date: parsedDate,
      status: AttendanceStatus.fromString(map['status'] as String?),
      routineId: map['routineId'] as String?,
      teacherId: map['teacherId'] as String?,
      courseName: map['courseName'] as String?,
      classType: map['classType'] as String?,
      time: map['time'] as String?,
      topic: map['topic'] as String? ?? map['notes'] as String?,
    );
  }
}

/// Helper calculations for attendance statistics
class AttendanceStats {
  final int attended;
  final int missed;
  final int canceled;
  final int extra;
  final bool isManualOverride;

  const AttendanceStats({
    this.attended = 0,
    this.missed = 0,
    this.canceled = 0,
    this.extra = 0,
    this.isManualOverride = false,
  });

  int get validClassesCount => attended + missed + extra;
  int get totalClasses => attended + missed + extra;

  double get percentage {
    if (validClassesCount == 0) return 100.0;
    return ((attended + extra) / validClassesCount) * 100.0;
  }

  static AttendanceStats fromRecords(
    List<AttendanceRecord> records, {
    bool useManualOverride = false,
    int? manualAttended,
    int? manualTotal,
  }) {
    if (useManualOverride && manualTotal != null && manualTotal > 0) {
      final safeAttended = (manualAttended ?? 0).clamp(0, manualTotal);
      final safeMissed = manualTotal - safeAttended;
      return AttendanceStats(
        attended: safeAttended,
        missed: safeMissed,
        canceled: 0,
        extra: 0,
        isManualOverride: true,
      );
    }

    int att = 0;
    int miss = 0;
    int canc = 0;
    int ext = 0;

    for (final r in records) {
      switch (r.status) {
        case AttendanceStatus.attended:
          att++;
          break;
        case AttendanceStatus.missed:
          miss++;
          break;
        case AttendanceStatus.canceled:
          canc++;
          break;
        case AttendanceStatus.extra:
          ext++;
          break;
        case AttendanceStatus.unmarked:
          break;
      }
    }

    return AttendanceStats(
      attended: att,
      missed: miss,
      canceled: canc,
      extra: ext,
      isManualOverride: false,
    );
  }
}

/// Override classification for academic scheduling (TASK 2)
enum OverrideType {
  holiday,
  termBreak,
  examPeriod;

  String get displayName {
    switch (this) {
      case OverrideType.holiday:
        return 'Holiday';
      case OverrideType.termBreak:
        return 'Term Break';
      case OverrideType.examPeriod:
        return 'Exam Period';
    }
  }

  static OverrideType fromString(String? str) {
    if (str == null) return OverrideType.termBreak;
    return OverrideType.values.firstWhere(
      (e) => e.name.toLowerCase() == str.toLowerCase(),
      orElse: () => OverrideType.termBreak,
    );
  }
}

/// Model for semester breaks, preparatory leaves, exam periods, and vacation spans (TASK 2)
class TermBreak {
  final String id;
  final String title; // e.g., "Mid Break", "PL", "Term Final Exams", "Eid Vacation"
  final DateTime startDate;
  final DateTime endDate;
  final OverrideType type;

  TermBreak({
    String? id,
    required this.title,
    required this.startDate,
    required this.endDate,
    this.type = OverrideType.termBreak,
  }) : id = (id != null && id.isNotEmpty) ? id : generateRoutineId('break');

  bool get isExamPeriod => type == OverrideType.examPeriod;
  bool get isHolidayOrBreak => type == OverrideType.holiday || type == OverrideType.termBreak;

  /// Checks if a given date falls within this break range (inclusive)
  bool containsDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final e = DateTime(endDate.year, endDate.month, endDate.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  TermBreak copyWith({
    String? id,
    String? title,
    DateTime? startDate,
    DateTime? endDate,
    OverrideType? type,
  }) {
    return TermBreak(
      id: id ?? this.id,
      title: title ?? this.title,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'startDate': Timestamp.fromDate(DateTime(startDate.year, startDate.month, startDate.day)),
      'endDate': Timestamp.fromDate(DateTime(endDate.year, endDate.month, endDate.day)),
      'type': type.name,
    };
  }

  factory TermBreak.fromMap(Map<String, dynamic> map, {String? defaultId}) {
    DateTime parseDate(dynamic d) {
      if (d is Timestamp) return d.toDate();
      if (d is String) return DateTime.tryParse(d) ?? DateTime.now();
      if (d is int) return DateTime.fromMillisecondsSinceEpoch(d);
      return DateTime.now();
    }

    return TermBreak(
      id: map['id'] as String? ?? (defaultId ?? generateRoutineId('break')),
      title: map['title'] as String? ?? 'Term Break',
      startDate: parseDate(map['startDate']),
      endDate: parseDate(map['endDate']),
      type: OverrideType.fromString(map['type'] as String?),
    );
  }
}

/// Model for weekly off-days, one-off specific holidays, range-based term breaks / exam periods, and semester boundaries
class HolidaySettings {
  final List<int> weeklyHolidays; // standard Dart weekday: 1 = Mon ... 5 = Fri, 6 = Sat, 7 = Sun
  final List<DateTime> specificHolidays; // specific calendar dates
  final List<TermBreak> termBreaks; // range breaks e.g. PL, Mid Break, Exam Period
  final DateTime? semesterStart; // start date of active semester
  final DateTime? semesterEnd; // end date of active semester

  const HolidaySettings({
    this.weeklyHolidays = const [DateTime.friday, DateTime.saturday],
    this.specificHolidays = const [],
    this.termBreaks = const [],
    this.semesterStart,
    this.semesterEnd,
  });

  static const HolidaySettings defaultSettings = HolidaySettings(
    weeklyHolidays: [DateTime.friday, DateTime.saturday],
    specificHolidays: [],
    termBreaks: [],
    semesterStart: null,
    semesterEnd: null,
  );

  /// TASK 4: Returns true if date falls between semesterStart and semesterEnd (inclusive).
  /// If no boundaries are set, returns true by default.
  bool isWithinSemester(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    if (semesterStart != null) {
      final start = DateTime(semesterStart!.year, semesterStart!.month, semesterStart!.day);
      if (d.isBefore(start)) return false;
    }
    if (semesterEnd != null) {
      final end = DateTime(semesterEnd!.year, semesterEnd!.month, semesterEnd!.day);
      if (d.isAfter(end)) return false;
    }
    return true;
  }

  /// Returns true if date is a weekly off-day, a single holiday, or falls in any TermBreak / Exam Period
  bool isHoliday(DateTime date) {
    if (weeklyHolidays.contains(date.weekday)) return true;
    if (specificHolidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day)) return true;
    return termBreaks.any((b) => b.containsDate(date));
  }

  /// Returns true if date falls into an Exam Period override
  bool isExamPeriod(DateTime date) {
    final b = getTermBreakForDate(date);
    return b != null && b.type == OverrideType.examPeriod;
  }

  /// Returns true if date is a non-exam holiday (weekly off-day, single holiday, or holiday/termBreak)
  bool isHolidayOrBreak(DateTime date) {
    if (weeklyHolidays.contains(date.weekday)) return true;
    if (specificHolidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day)) return true;
    final b = getTermBreakForDate(date);
    return b != null && b.type != OverrideType.examPeriod;
  }

  /// Returns the TermBreak covering this date, if any
  TermBreak? getTermBreakForDate(DateTime date) {
    for (final b in termBreaks) {
      if (b.containsDate(date)) return b;
    }
    return null;
  }

  /// Returns a human-friendly reason description for a holiday/break/exam period
  String? getHolidayReason(DateTime date) {
    final termBreak = getTermBreakForDate(date);
    if (termBreak != null) {
      if (termBreak.type == OverrideType.examPeriod) {
        return '${termBreak.title} (Exam Period)';
      }
      return '${termBreak.title} (${termBreak.type.displayName})';
    }
    if (specificHolidays.any((h) => h.year == date.year && h.month == date.month && h.day == date.day)) {
      return 'Public Holiday';
    }
    if (weeklyHolidays.contains(date.weekday)) {
      return 'Weekly Off-day';
    }
    return null;
  }

  HolidaySettings copyWith({
    List<int>? weeklyHolidays,
    List<DateTime>? specificHolidays,
    List<TermBreak>? termBreaks,
    DateTime? semesterStart,
    DateTime? semesterEnd,
  }) {
    return HolidaySettings(
      weeklyHolidays: weeklyHolidays ?? this.weeklyHolidays,
      specificHolidays: specificHolidays ?? this.specificHolidays,
      termBreaks: termBreaks ?? this.termBreaks,
      semesterStart: semesterStart ?? this.semesterStart,
      semesterEnd: semesterEnd ?? this.semesterEnd,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weeklyHolidays': weeklyHolidays,
      'specificHolidays': specificHolidays.map((d) => Timestamp.fromDate(DateTime(d.year, d.month, d.day))).toList(),
      'termBreaks': termBreaks.map((b) => b.toMap()).toList(),
      if (semesterStart != null) 'semesterStart': Timestamp.fromDate(DateTime(semesterStart!.year, semesterStart!.month, semesterStart!.day)),
      if (semesterEnd != null) 'semesterEnd': Timestamp.fromDate(DateTime(semesterEnd!.year, semesterEnd!.month, semesterEnd!.day)),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory HolidaySettings.fromMap(Map<String, dynamic> map) {
    final rawWeekly = map['weeklyHolidays'] as List<dynamic>? ?? [DateTime.friday, DateTime.saturday];
    final List<int> parsedWeekly = rawWeekly.map((e) => (e as num).toInt()).toList();

    final rawSpecific = map['specificHolidays'] as List<dynamic>? ?? [];
    final List<DateTime> parsedSpecific = [];
    for (final item in rawSpecific) {
      if (item is Timestamp) {
        parsedSpecific.add(item.toDate());
      } else if (item is String) {
        final parsed = DateTime.tryParse(item);
        if (parsed != null) parsedSpecific.add(parsed);
      }
    }

    final rawBreaks = map['termBreaks'] as List<dynamic>? ?? [];
    final List<TermBreak> parsedBreaks = [];
    for (final item in rawBreaks) {
      if (item is Map) {
        try {
          parsedBreaks.add(TermBreak.fromMap(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
    }

    DateTime? parseOptDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return HolidaySettings(
      weeklyHolidays: parsedWeekly,
      specificHolidays: parsedSpecific,
      termBreaks: parsedBreaks,
      semesterStart: parseOptDate(map['semesterStart']),
      semesterEnd: parseOptDate(map['semesterEnd']),
    );
  }
}

/// Service for parsing course codes and synchronizing routine courses with Firestore
class RoutineCourseSyncService {
  /// Extracts the standard course code from a raw course string.
  /// Examples:
  /// - "PHY 121 - Physics I" -> "PHY 121"
  /// - "MATH 157: Calculus" -> "MATH 157"
  /// - "CSE 110 (Sec A)" -> "CSE 110"
  /// - "EEE 101" -> "EEE 101"
  /// - "CSE-101" -> "CSE-101"
  static String parseCourseCode(String raw) {
    String text = raw.trim();
    if (text.isEmpty) return 'COURSE';

    // 1. Common delimiter split (Code - Name, Code: Name, etc.)
    for (final delimiter in [' - ', ': ', ' – ', ' — ', ' • ', '|']) {
      if (text.contains(delimiter)) {
        text = text.split(delimiter).first.trim();
        break;
      }
    }

    // 2. Strip trailing parenthesized sections, e.g. "CSE 110 (A)"
    if (text.contains('(')) {
      final beforeParen = text.split('(').first.trim();
      if (beforeParen.isNotEmpty) {
        text = beforeParen;
      }
    }

    // 3. Regex match for standard university course codes (e.g. CSE 101, MATH 157, PHY-121)
    final regex = RegExp(r'([A-Za-z]{2,6}\s*[-]?\s*\d{2,4}[A-Za-z]?)');
    final match = regex.firstMatch(text);
    if (match != null) {
      return match.group(1)!.trim().toUpperCase();
    }

    return text;
  }

  /// Normalizes a course code into a deterministic canonical document ID (e.g., "MATH 157" -> "MATH_157")
  static String sanitizeDocId(String code) {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    final collapsed = clean.replaceAll(RegExp(r'_+'), '_');
    return collapsed.replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Parses a time string (e.g. "10:00 AM", "01:50 PM", "9:30 AM", "11:00 AM - 01:50 PM") into minutes from midnight.
  /// Unassigned, missing, or unparseable times return 1440 (pushes to the bottom of the routine list).
  static int parseTimeToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return 1440;
    try {
      final trimmed = timeStr.trim();
      final firstPart = trimmed.split(RegExp(r'\s*[-–—]\s*')).first.trim();
      final cleaned = firstPart.toUpperCase();
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      final numbersOnly = cleaned.replaceAll(RegExp(r'[^\d:]'), '');
      final parts = numbersOnly.split(':');
      if (parts.isEmpty || parts[0].isEmpty) return 1440;
      int hour = int.parse(parts[0]);
      final minute = parts.length > 1 && parts[1].isNotEmpty ? int.parse(parts[1]) : 0;
      if (isPM && hour < 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return hour * 60 + minute;
    } catch (_) {
      return 1440;
    }
  }

  /// Strictly sorts a list of ClassRoutine objects chronologically by startTime, then endTime.
  static List<ClassRoutine> sortRoutinesByTime(List<ClassRoutine> routines) {
    final list = List<ClassRoutine>.from(routines);
    list.sort((a, b) {
      final startA = parseTimeToMinutes(a.startTime);
      final startB = parseTimeToMinutes(b.startTime);
      if (startA != startB) return startA.compareTo(startB);
      final endA = parseTimeToMinutes(a.endTime);
      final endB = parseTimeToMinutes(b.endTime);
      if (endA != endB) return endA.compareTo(endB);
      return a.courseName.compareTo(b.courseName);
    });
    return list;
  }

  /// Merges class routines and assessments for a selected date, and sorts them chronologically by time.
  static List<PlannerAgendaItem> mergeAndSortAgenda({
    required List<ClassRoutine> routines,
    required List<Assessment> assessments,
  }) {
    final items = <PlannerAgendaItem>[
      ...routines.map((r) => PlannerAgendaItem.routine(r)),
      ...assessments.map((a) => PlannerAgendaItem.assessment(a)),
    ];
    items.sort((a, b) {
      // 1. All Assessments/CTs/Quizzes are prioritized and always render at the top
      if (a.isAssessment && !b.isAssessment) return -1;
      if (!a.isAssessment && b.isAssessment) return 1;

      // 2. Both are assessments or both are routines: sort chronologically
      if (a.timeInMinutes != b.timeInMinutes) {
        return a.timeInMinutes.compareTo(b.timeInMinutes);
      }

      // 3. Fallback alphabetical sorting if start times are identical
      final nameA = a.routine?.courseName ?? a.assessment?.name ?? '';
      final nameB = b.routine?.courseName ?? b.assessment?.name ?? '';
      return nameA.compareTo(nameB);
    });
    return items;
  }

  /// Scans a list of ClassRoutines, finds all unique course codes across all 7 days,
  /// checks `users/{uid}/courses` for their presence, and auto-creates any missing course documents
  /// using the canonical sanitized course code as document ID (e.g. doc('MATH_157')).
  /// Returns the list of newly created course codes.
  static Future<List<String>> syncCoursesFromRoutines({
    required String uid,
    required List<ClassRoutine> routines,
  }) async {
    if (uid.isEmpty || routines.isEmpty) return [];

    final coursesCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('courses');

    // 1. Collect existing course codes in Firestore
    final existingSnap = await coursesCol.get();
    final existingCodes = <String>{};
    for (final doc in existingSnap.docs) {
      final data = doc.data();
      final code = (data['courseCode'] as String? ?? '').trim().toLowerCase();
      if (code.isNotEmpty) existingCodes.add(code);
      final docSanitized = sanitizeDocId(doc.id).toLowerCase();
      if (docSanitized.isNotEmpty) existingCodes.add(docSanitized);
    }

    // 2. Group routines by unique parsed course code
    final Map<String, List<ClassRoutine>> groupedByCode = {};
    for (final r in routines) {
      final raw = r.courseName.trim().isNotEmpty ? r.courseName : (r.courseId.isNotEmpty ? r.courseId : 'Course');
      final code = parseCourseCode(raw);
      groupedByCode.putIfAbsent(code, () => []).add(r);
    }

    final List<String> newlyCreatedCodes = [];

    // 3. Auto-populate missing courses with normalized document IDs (e.g. 'MATH_157')
    for (final entry in groupedByCode.entries) {
      final code = entry.key;
      final classList = entry.value;
      final docId = sanitizeDocId(code);

      if (existingCodes.contains(code.toLowerCase()) || (docId.isNotEmpty && existingCodes.contains(docId.toLowerCase()))) {
        continue; // Course already exists
      }

      final isLab = classList.any((r) {
        final t = r.classType.toLowerCase();
        return t.contains('lab') || t.contains('sessional');
      });

      final newDoc = docId.isNotEmpty ? coursesCol.doc(docId) : coursesCol.doc();
      final effectiveId = newDoc.id;
      final newCourseData = {
        'id': effectiveId,
        'courseCode': code,
        'courseName': code, // Parsed course code (user can edit title later)
        'creditHours': isLab ? 1.5 : 3.0,
        'courseType': isLab ? 'Sessional/Lab' : 'Theory',
        'syllabus': [],
        'syllabusData': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      try {
        await newDoc.set(newCourseData, SetOptions(merge: true));
        existingCodes.add(code.toLowerCase());
        if (docId.isNotEmpty) existingCodes.add(docId.toLowerCase());
        newlyCreatedCodes.add(code);
      } catch (e) {
        debugPrint('Error auto-creating course for code "$code": $e');
      }
    }

    return newlyCreatedCodes;
  }

  /// Scans the user's active routine in Firestore (`users/{uid}/routine`) across all 7 days
  /// and ensures all unique course entries exist in `users/{uid}/courses`.
  static Future<List<String>> syncCoursesFromFirestoreRoutine(String uid) async {
    if (uid.isEmpty) return [];

    try {
      final routineSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('routine')
          .get();

      final List<ClassRoutine> routines = routineSnap.docs
          .map((doc) => ClassRoutine.fromMap(doc.data(), defaultId: doc.id))
          .toList();
      return await syncCoursesFromRoutines(uid: uid, routines: routines);
    } catch (e) {
      debugPrint('Error syncing courses from Firestore routine: $e');
      return [];
    }
  }

  /// Ensures a single course document exists for a given routine code/name,
  /// standardizing on canonical document ID (e.g. 'MATH_157')
  static Future<String> ensureCourseExists({
    required String uid,
    required String courseId,
    required String rawName,
    required String classType,
  }) async {
    final coursesCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('courses');
    final code = parseCourseCode(rawName);
    final canonicalId = sanitizeDocId(code);

    if (courseId.isNotEmpty) {
      final docSnap = await coursesCol.doc(courseId).get();
      if (docSnap.exists) return courseId;
    }

    if (canonicalId.isNotEmpty) {
      final canonicalSnap = await coursesCol.doc(canonicalId).get();
      if (canonicalSnap.exists) return canonicalId;
    }

    final existingSnap = await coursesCol.get();
    for (final doc in existingSnap.docs) {
      final existingCode = (doc.data()['courseCode'] as String? ?? '').toLowerCase().trim();
      if (code.isNotEmpty && (existingCode == code.toLowerCase() || sanitizeDocId(existingCode) == canonicalId)) {
        return doc.id;
      }
    }

    final isLab = classType.toLowerCase().contains('lab') || classType.toLowerCase().contains('sessional');
    final targetId = canonicalId.isNotEmpty ? canonicalId : (courseId.isNotEmpty ? courseId : coursesCol.doc().id);
    final targetDoc = coursesCol.doc(targetId);

    await targetDoc.set({
      'id': targetId,
      'courseCode': code,
      'courseName': code,
      'creditHours': isLab ? 1.5 : 3.0,
      'courseType': isLab ? 'Sessional/Lab' : 'Theory',
      'syllabus': [],
      'syllabusData': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return targetId;
  }

  /// Resolves the canonical Course document ID for a courseId and rawName/code
  static Future<String> resolveCanonicalCourseId({
    required String uid,
    required String courseId,
    required String rawName,
  }) async {
    if (uid.isEmpty) return courseId;
    final coursesCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('courses');
    final code = parseCourseCode(rawName.isNotEmpty ? rawName : courseId);
    final canonicalId = sanitizeDocId(code);

    // 1. Direct docId check if provided and exists
    if (courseId.isNotEmpty) {
      try {
        final docSnap = await coursesCol.doc(courseId).get();
        if (docSnap.exists) return courseId;
      } catch (_) {}
    }

    // 2. Canonical docId check (e.g. 'MATH_157')
    if (canonicalId.isNotEmpty) {
      try {
        final snap = await coursesCol.doc(canonicalId).get();
        if (snap.exists) return canonicalId;
      } catch (_) {}
    }

    // 3. Scan existing courses for matching courseCode
    try {
      final allCourses = await coursesCol.get();
      for (final doc in allCourses.docs) {
        final cCode = (doc.data()['courseCode'] as String? ?? '').trim();
        if (cCode.isNotEmpty && (cCode.toUpperCase() == code.toUpperCase() || sanitizeDocId(cCode) == canonicalId)) {
          return doc.id;
        }
      }
    } catch (_) {}

    return canonicalId.isNotEmpty ? canonicalId : (courseId.isNotEmpty ? courseId : 'COURSE');
  }

  /// Resilient check to see if an AttendanceRecord belongs to a Course by matching
  /// docId, courseCode, sanitized code, or parsed courseName
  static bool recordMatchesCourse({
    required AttendanceRecord record,
    required String courseId,
    required String courseCode,
    String? courseName,
  }) {
    final cleanDocId = courseId.trim().toLowerCase();
    final cleanCourseCode = courseCode.trim().toLowerCase();
    final cleanSanitized = sanitizeDocId(courseCode).toLowerCase();

    final recCourseId = record.courseId.trim().toLowerCase();
    final recSanitizedId = sanitizeDocId(record.courseId).toLowerCase();

    // 1. Direct ID match
    if (recCourseId.isNotEmpty && (recCourseId == cleanDocId || recCourseId == cleanSanitized)) return true;

    // 2. record.courseId matches courseCode or docId
    if (cleanCourseCode.isNotEmpty && (recCourseId == cleanCourseCode || recSanitizedId == cleanSanitized)) return true;

    // 3. record.courseCode matches courseCode or docId
    if (record.courseCode != null && record.courseCode!.trim().isNotEmpty) {
      final recCode = record.courseCode!.trim().toLowerCase();
      final recSanitizedCode = sanitizeDocId(record.courseCode!).toLowerCase();
      if (recCode == cleanCourseCode || recCode == cleanDocId || recSanitizedCode == cleanSanitized) {
        return true;
      }
    }

    // 4. record.courseName parse match
    if (record.courseName != null && record.courseName!.trim().isNotEmpty) {
      final parsedFromRecordName = parseCourseCode(record.courseName!).toLowerCase();
      final parsedSanitized = sanitizeDocId(parsedFromRecordName).toLowerCase();
      if (parsedFromRecordName == cleanCourseCode || parsedSanitized == cleanSanitized || parsedFromRecordName == cleanDocId) {
        return true;
      }
    }

    return false;
  }

  /// Resilient check to see if a ClassRoutine belongs to a Course by matching
  /// routine.courseId, routine.courseName, or base course codes
  static bool routineMatchesCourse({
    required ClassRoutine routine,
    required String courseId,
    required String courseCode,
    String? courseName,
  }) {
    final cleanDocId = courseId.trim().toLowerCase();
    final cleanCourseCode = courseCode.trim().toLowerCase();
    final cleanSanitized = sanitizeDocId(courseCode).toLowerCase();

    final rCourseId = routine.courseId.trim().toLowerCase();
    final rSanitizedId = sanitizeDocId(routine.courseId).toLowerCase();

    // 1. Direct courseId or sanitized match
    if (rCourseId.isNotEmpty && (rCourseId == cleanDocId || rCourseId == cleanSanitized || rCourseId == cleanCourseCode || rSanitizedId == cleanSanitized)) {
      return true;
    }

    // 2. Parse course code from routine.courseName
    final parsedFromRoutineName = parseCourseCode(routine.courseName.isNotEmpty ? routine.courseName : routine.courseId).toLowerCase();
    final parsedSanitized = sanitizeDocId(parsedFromRoutineName).toLowerCase();
    if (parsedFromRoutineName == cleanCourseCode || parsedSanitized == cleanSanitized || parsedFromRoutineName == cleanDocId) {
      return true;
    }

    // 3. Base course code match
    final routineBase = extractBaseCourseCode(routine.courseName.isNotEmpty ? routine.courseName : routine.courseId).toLowerCase();
    final targetBase = extractBaseCourseCode(courseCode.isNotEmpty ? courseCode : (courseName ?? '')).toLowerCase();
    if (routineBase.isNotEmpty && targetBase.isNotEmpty && routineBase == targetBase) {
      return true;
    }

    return false;
  }

  /// TASK 1: Extracts canonical base course code (e.g. "EEE 102" from "EEE 102 (H)" or "EEE 102 (S)")
  static String extractBaseCourseCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    // 1. Regex pattern for standard department course codes: e.g. EEE 102, CSE 109, MATH 157
    final match = RegExp(r'([A-Za-z]{2,5}\s*\d{3,4}[A-Za-z]?)', caseSensitive: false).firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    }

    // 2. Strip parentheses, brackets, and braces like (H), (S), [Lab]
    final stripped = trimmed.replaceAll(RegExp(r'\s*[\(\[\{].*?[\)\]\}]'), '').trim().toUpperCase();
    return stripped.isNotEmpty ? stripped : trimmed.toUpperCase();
  }

  /// Finds the alternating partner class for a biweekly routine slot (if any)
  static ClassRoutine? findPartnerClass({
    required ClassRoutine routine,
    required List<ClassRoutine> allRoutines,
  }) {
    for (final r in allRoutines) {
      if (r.id == routine.id) continue;
      // 1. Explicit pairedClassId link
      if (routine.pairedClassId != null &&
          (r.id == routine.pairedClassId || r.courseId == routine.pairedClassId)) {
        return r;
      }
      if (r.pairedClassId != null &&
          (r.pairedClassId == routine.id || r.pairedClassId == routine.courseId)) {
        return r;
      }
      // 2. Same weekday, same start time, alternating
      if (r.dayOfWeek == routine.dayOfWeek &&
          r.startTime == routine.startTime &&
          r.isAlternating &&
          routine.isAlternating) {
        return r;
      }
    }
    return null;
  }

  /// Returns the canonical Saturday-to-Friday academic week boundary for a given date
  static ({DateTime start, DateTime end}) getAcademicWeekRange(DateTime date) {
    final int daysSinceSat = (date.weekday - DateTime.saturday + 7) % 7;
    final start = DateTime(date.year, date.month, date.day).subtract(Duration(days: daysSinceSat));
    final end = start.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
    return (start: start, end: end);
  }

  /// Checks if an alternating counterpart of the given routine already had an
  /// 'Attended' or 'Missed' session in the same Saturday-to-Friday academic week.
  ///
  /// SCOPED STRICTLY:
  /// - Only runs if slot recurrence is strictly biweekly ('biweekly_a' or 'biweekly_b')
  /// - Only runs if slot is a Lab / Sessional class
  /// - Only runs if slot has an explicit alternating pair (pairedClassId != null and non-empty)
  /// Standard Theory classes or weekly recurring slots NEVER return true.
  static bool isAlternatingCounterpartBlocked({
    required ClassRoutine routine,
    required List<AttendanceRecord> records,
    required DateTime selectedDate,
  }) {
    // 1. Recurrence must strictly be biweekly
    final recurrence = routine.recurrence.toLowerCase().trim();
    final bool isBiweeklySlot = recurrence == 'biweekly_a' || recurrence == 'biweekly_b';
    if (!isBiweeklySlot) {
      return false;
    }

    // 2. Must be a lab or sessional class
    final classType = routine.classType.toLowerCase().trim();
    final bool isLabOrSessional = classType == 'sessional' ||
        classType == 'lab' ||
        classType.contains('sessional') ||
        classType.contains('lab');
    if (!isLabOrSessional) {
      return false;
    }

    // 3. Must have an explicit paired alternating counterpart
    final pairedId = routine.pairedClassId?.trim();
    if (pairedId == null || pairedId.isEmpty) {
      return false;
    }

    final week = getAcademicWeekRange(selectedDate);
    final sanitizedPairedId = sanitizeDocId(pairedId);

    for (final rec in records) {
      // Must be within the same academic week
      if (rec.date.isBefore(week.start) || rec.date.isAfter(week.end)) {
        continue;
      }

      // Ignore the routine's own direct attendance record on the current date
      final isSelf = (rec.date.year == selectedDate.year &&
              rec.date.month == selectedDate.month &&
              rec.date.day == selectedDate.day) &&
          (rec.routineId == routine.id);
      if (isSelf) continue;

      // Only Attended or Missed statuses indicate an alternating session was recorded
      final isActioned = rec.status == AttendanceStatus.attended ||
          rec.status == AttendanceStatus.extra ||
          rec.status == AttendanceStatus.missed;
      if (!isActioned) continue;

      // Match against the paired routine ID or paired course ID
      final bool isPairedMatch = rec.routineId == pairedId ||
          rec.courseId == pairedId ||
          (rec.courseCode != null && rec.courseCode == pairedId) ||
          (rec.courseCode != null && sanitizeDocId(rec.courseCode!) == sanitizedPairedId) ||
          (sanitizeDocId(rec.courseId) == sanitizedPairedId);

      if (isPairedMatch) {
        return true;
      }
    }

    return false;
  }

  /// Global Course Attendance calculation taking into account manual bulk override
  static AttendanceStats computeCourseAttendance({
    required List<AttendanceRecord> courseRecords,
    bool useManualAttendanceOverride = false,
    int? manualAttendedClasses,
    int? manualTotalClasses,
  }) {
    if (useManualAttendanceOverride && manualTotalClasses != null && manualTotalClasses > 0) {
      final safeAtt = (manualAttendedClasses ?? 0).clamp(0, manualTotalClasses);
      return AttendanceStats(
        attended: safeAtt,
        missed: manualTotalClasses - safeAtt,
        canceled: 0,
        extra: 0,
        isManualOverride: true,
      );
    }
    return AttendanceStats.fromRecords(courseRecords);
  }

  /// Global Attendance Percentage calculation (0.0 to 100.0)
  static double calculateAttendanceRate({
    required List<AttendanceRecord> courseRecords,
    bool useManualAttendanceOverride = false,
    int? manualAttendedClasses,
    int? manualTotalClasses,
  }) {
    if (useManualAttendanceOverride && manualTotalClasses != null && manualTotalClasses > 0) {
      final safeAtt = (manualAttendedClasses ?? 0).clamp(0, manualTotalClasses);
      return (safeAtt / manualTotalClasses) * 100.0;
    }
    final stats = AttendanceStats.fromRecords(courseRecords);
    return stats.percentage;
  }

  /// Preserves historical attendance by retiring active routines up to yesterday,
  /// and optionally activates a new set of routines starting from today forward.
  static Future<void> preserveHistoricalRoutineAndApplyNew({
    required String uid,
    List<ClassRoutine>? newRoutines,
  }) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final endTimestamp = Timestamp.fromDate(yesterday);
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);

    final routineCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('routine');
    final routineSnap = await routineCol.get();

    final batch = FirebaseFirestore.instance.batch();

    // 1. Retire all currently active routine slots by setting effectiveUntil to yesterday
    for (final doc in routineSnap.docs) {
      final r = ClassRoutine.fromMap(doc.data(), defaultId: doc.id);
      final bool isCurrentlyActive = r.effectiveUntil == null || r.effectiveUntil!.isAfter(yesterday);
      if (isCurrentlyActive) {
        batch.update(doc.reference, {
          'effectiveUntil': endTimestamp,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // 2. If new routines are supplied, activate them starting from today forward
    if (newRoutines != null && newRoutines.isNotEmpty) {
      await syncCoursesFromRoutines(uid: uid, routines: newRoutines);

      for (final nr in newRoutines) {
        final effectiveCourseId = await ensureCourseExists(
          uid: uid,
          courseId: nr.courseId,
          rawName: nr.courseName,
          classType: nr.classType,
        );
        final activatedRoutine = nr.copyWith(
          courseId: effectiveCourseId,
          effectiveFrom: todayDateOnly,
          effectiveUntil: null,
        );
        final ref = routineCol.doc(activatedRoutine.id);
        batch.set(ref, activatedRoutine.toMap(), SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  /// Clears all existing routine slots and past routine attendance logs, starting completely fresh.
  static Future<void> resetFreshRoutineAndAttendance({
    required String uid,
    List<ClassRoutine>? newRoutines,
  }) async {
    final routineCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('routine');
    final attCol = FirebaseFirestore.instance.collection('users').doc(uid).collection('attendance_records');

    final routineSnap = await routineCol.get();
    final attSnap = await attCol.get();

    // Delete all existing routine docs
    for (final doc in routineSnap.docs) {
      await doc.reference.delete();
    }

    // Delete attendance records linked to routines or past logs
    for (final doc in attSnap.docs) {
      await doc.reference.delete();
    }

    // If new routines are supplied, add them clean
    if (newRoutines != null && newRoutines.isNotEmpty) {
      await syncCoursesFromRoutines(uid: uid, routines: newRoutines);

      final batch = FirebaseFirestore.instance.batch();
      for (final nr in newRoutines) {
        final effectiveCourseId = await ensureCourseExists(
          uid: uid,
          courseId: nr.courseId,
          rawName: nr.courseName,
          classType: nr.classType,
        );
        final cleanRoutine = nr.copyWith(
          courseId: effectiveCourseId,
          effectiveFrom: null,
          effectiveUntil: null,
        );
        final ref = routineCol.doc(cleanRoutine.id);
        batch.set(ref, cleanRoutine.toMap(), SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}

/// Unified agenda item wrapping either a ClassRoutine or an Assessment,
/// sorted chronologically by time for the daily agenda view.
class PlannerAgendaItem {
  final ClassRoutine? routine;
  final Assessment? assessment;
  final int timeInMinutes;

  PlannerAgendaItem.routine(ClassRoutine r)
      : routine = r,
        assessment = null,
        timeInMinutes = RoutineCourseSyncService.parseTimeToMinutes(r.startTime);

  PlannerAgendaItem.assessment(Assessment a)
      : assessment = a,
        routine = null,
        timeInMinutes = (a.date ?? a.dueDate) != null
            ? ((a.date ?? a.dueDate)!.hour * 60 + (a.date ?? a.dueDate)!.minute)
            : 1440;

  bool get isAssessment => assessment != null;
  bool get isRoutine => routine != null;
}
