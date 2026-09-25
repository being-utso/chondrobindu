import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_quill/flutter_quill.dart';

class NoteModel {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPinned;
  final List<String> tags;

  const NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.tags = const ['General'],
  });

  /// Safe Plain Text extractor for note previews and search matching.
  String get plainTextContent {
    if (content.trim().isEmpty) return '';
    try {
      final jsonData = jsonDecode(content);
      if (jsonData is List) {
        final doc = Document.fromJson(jsonData);
        return doc.toPlainText().trim();
      }
    } catch (_) {
      // Fallback for legacy plain text or markdown notes
    }
    return content;
  }

  NoteModel copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    List<String>? tags,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isPinned': isPinned,
      'tags': tags,
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map, [String? docId]) {
    DateTime parseDate(dynamic dateVal) {
      if (dateVal is Timestamp) {
        return dateVal.toDate();
      } else if (dateVal is String) {
        return DateTime.tryParse(dateVal) ?? DateTime.now();
      } else if (dateVal is int) {
        return DateTime.fromMillisecondsSinceEpoch(dateVal);
      }
      return DateTime.now();
    }

    final rawTags = map['tags'];
    List<String> parsedTags = ['General'];
    if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    }

    return NoteModel(
      id: docId ?? map['id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      isPinned: map['isPinned'] ?? false,
      tags: parsedTags.isEmpty ? ['General'] : parsedTags,
    );
  }
}
