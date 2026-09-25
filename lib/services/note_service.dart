import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note_model.dart';

class NoteService {
  final FirebaseFirestore _firestore;

  NoteService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _userNotesRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('notes');
  }

  /// Real-time stream of notes for a user, sorted by isPinned DESC and updatedAt DESC
  Stream<List<NoteModel>> getNotesStream(String uid) {
    if (uid.isEmpty) return Stream.value([]);
    
    return _userNotesRef(uid)
        .snapshots()
        .map((snapshot) {
      final Map<String, NoteModel> uniqueNotesMap = {};
      for (final doc in snapshot.docs) {
        uniqueNotesMap[doc.id] = NoteModel.fromMap(doc.data(), doc.id);
      }
      final notes = uniqueNotesMap.values.toList();

      // In-memory sort fallback to ensure pinned notes come first, followed by updated date
      notes.sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.updatedAt.compareTo(a.updatedAt);
      });

      return notes;
    });
  }

  /// Add a new note
  Future<String> addNote(String uid, NoteModel note) async {
    if (uid.isEmpty) throw Exception('User not authenticated');
    
    final docRef = _userNotesRef(uid).doc();
    final newNote = note.copyWith(
      id: docRef.id,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    
    await docRef.set(newNote.toMap());
    return docRef.id;
  }

  /// Update an existing note
  Future<void> updateNote(String uid, NoteModel note) async {
    if (uid.isEmpty || note.id.isEmpty) throw Exception('Invalid user or note ID');
    
    final updatedNote = note.copyWith(updatedAt: DateTime.now());
    await _userNotesRef(uid).doc(note.id).update(updatedNote.toMap());
  }

  /// Delete a note
  Future<void> deleteNote(String uid, String noteId) async {
    if (uid.isEmpty || noteId.isEmpty) return;
    await _userNotesRef(uid).doc(noteId).delete();
  }

  /// Toggle pin status for a note
  Future<void> togglePinNote(String uid, String noteId, bool currentPinState) async {
    if (uid.isEmpty || noteId.isEmpty) return;
    await _userNotesRef(uid).doc(noteId).update({
      'isPinned': !currentPinState,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Helper: Convert Brain Dump scratchpad text into a saved Note entry
  Future<String> convertBrainDumpToNote(
    String uid,
    String scratchpadContent, {
    String? customTitle,
    List<String>? tags,
  }) async {
    final cleanContent = scratchpadContent.trim();
    if (cleanContent.isEmpty) throw Exception('Scratchpad content is empty');

    // Auto-generate title from first non-empty line if no custom title is provided
    String generatedTitle = customTitle?.trim() ?? '';
    if (generatedTitle.isEmpty) {
      final lines = cleanContent.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty) {
        final firstLine = lines.first;
        generatedTitle = firstLine.length > 40 ? '${firstLine.substring(0, 40)}...' : firstLine;
      } else {
        generatedTitle = 'Brain Dump Note';
      }
    }

    final note = NoteModel(
      id: '',
      title: generatedTitle,
      content: cleanContent,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      tags: tags ?? const ['Brain Dump'],
    );

    return await addNote(uid, note);
  }
}
