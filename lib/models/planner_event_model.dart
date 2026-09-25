import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

String generateEventId([String prefix = 'event']) {
  final random = Random().nextInt(999999);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_${timestamp}_$random';
}

/// Model for Non-Academic Calendar Events in the Planner
class PlannerEvent {
  final String id;
  final String title;
  final String category; // e.g. 'Club', 'Workshop', 'Seminar', 'Competition', 'Meeting', 'Personal', 'Other'
  final DateTime date;
  final String timeSlot; // e.g. '14:00 - 15:30'
  final String remarks;
  final String status; // 'Pending', 'Completed', 'Missed', 'Postponed'
  final DateTime? postponedToDate;
  final String? postponedToSlot;

  PlannerEvent({
    String? id,
    required this.title,
    this.category = 'Personal',
    required this.date,
    this.timeSlot = '10:00 - 11:00',
    this.remarks = '',
    this.status = 'Pending',
    this.postponedToDate,
    this.postponedToSlot,
  }) : id = (id != null && id.isNotEmpty) ? id : generateEventId('event');

  bool get isCompleted => status.toLowerCase() == 'completed' || status.toLowerCase() == 'attended';
  bool get isMissed => status.toLowerCase() == 'missed';
  bool get isPostponed => status.toLowerCase() == 'postponed';

  PlannerEvent copyWith({
    String? id,
    String? title,
    String? category,
    DateTime? date,
    String? timeSlot,
    String? remarks,
    String? status,
    DateTime? postponedToDate,
    String? postponedToSlot,
  }) {
    return PlannerEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      date: date ?? this.date,
      timeSlot: timeSlot ?? this.timeSlot,
      remarks: remarks ?? this.remarks,
      status: status ?? this.status,
      postponedToDate: postponedToDate ?? this.postponedToDate,
      postponedToSlot: postponedToSlot ?? this.postponedToSlot,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'date': Timestamp.fromDate(date),
      'timeSlot': timeSlot,
      'remarks': remarks,
      'status': status,
      'postponedToDate': postponedToDate != null ? Timestamp.fromDate(postponedToDate!) : null,
      'postponedToSlot': postponedToSlot,
    };
  }

  factory PlannerEvent.fromMap(Map<String, dynamic> map, [String? fallbackId]) {
    DateTime parsedDate = DateTime.now();
    if (map['date'] != null) {
      if (map['date'] is Timestamp) {
        parsedDate = (map['date'] as Timestamp).toDate();
      } else if (map['date'] is String) {
        parsedDate = DateTime.tryParse(map['date'] as String) ?? DateTime.now();
      } else if (map['date'] is int) {
        parsedDate = DateTime.fromMillisecondsSinceEpoch(map['date'] as int);
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

    return PlannerEvent(
      id: map['id'] as String? ?? (fallbackId ?? generateEventId('event')),
      title: map['title'] as String? ?? 'Event',
      category: map['category'] as String? ?? 'Personal',
      date: parsedDate,
      timeSlot: map['timeSlot'] as String? ?? '10:00 - 11:00',
      remarks: map['remarks'] as String? ?? '',
      status: map['status'] as String? ?? 'Pending',
      postponedToDate: parsedPostponedDate,
      postponedToSlot: map['postponedToSlot'] as String?,
    );
  }
}
