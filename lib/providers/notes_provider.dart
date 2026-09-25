import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/note_model.dart';
import '../services/note_service.dart';

final noteServiceProvider = Provider<NoteService>((ref) {
  return NoteService();
});

/// Stream of all notes for the authenticated user
final notesStreamProvider = StreamProvider.autoDispose<List<NoteModel>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  
  final service = ref.watch(noteServiceProvider);
  return service.getNotesStream(user.uid);
});

/// Selected category/tag filter chip ('All', 'Pinned', 'Brain Dump', 'Formula', 'Mistake', 'General')
final selectedNoteTagProvider = StateProvider.autoDispose<String>((ref) => 'All');

/// Active search query in Journal screen
final noteSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Computed filtered notes based on search query and selected tag chip
final filteredNotesProvider = Provider.autoDispose<List<NoteModel>>((ref) {
  final notesAsync = ref.watch(notesStreamProvider);
  final tagFilter = ref.watch(selectedNoteTagProvider);
  final searchQuery = ref.watch(noteSearchQueryProvider).trim().toLowerCase();

  final rawNotes = notesAsync.value ?? [];
  final seenIds = <String>{};
  final notes = rawNotes.where((n) => n.id.isNotEmpty ? seenIds.add(n.id) : true).toList();

  return notes.where((note) {
    // 1. Tag filter matching
    bool matchesTag = true;
    if (tagFilter == 'Pinned') {
      matchesTag = note.isPinned;
    } else if (tagFilter == 'Notes') {
      matchesTag = !note.tags.contains('Exam Journal') && !note.tags.contains('Brain Dump') && !note.tags.contains('Study Session');
    } else if (tagFilter != 'All') {
      matchesTag = note.tags.contains(tagFilter);
    }

    // 2. Search query matching
    bool matchesSearch = true;
    if (searchQuery.isNotEmpty) {
      final titleMatch = note.title.toLowerCase().contains(searchQuery);
      final contentMatch = note.plainTextContent.toLowerCase().contains(searchQuery);
      final tagMatch = note.tags.any((t) => t.toLowerCase().contains(searchQuery));
      matchesSearch = titleMatch || contentMatch || tagMatch;
    }

    return matchesTag && matchesSearch;
  }).toList();
});
