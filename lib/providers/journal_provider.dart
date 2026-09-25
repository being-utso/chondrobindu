import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/journal_entry_model.dart';
import '../services/journal_service.dart';

final journalServiceProvider = Provider<JournalService>((ref) {
  return JournalService();
});

/// Stream of study session journal entries for the current user
final journalStreamProvider = StreamProvider.autoDispose<List<StudyJournalEntry>>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value([]);
  return ref.watch(journalServiceProvider).getJournalStream(user.uid);
});
