import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/notes_provider.dart';
import 'journal_screen.dart';

/// Unified wrapper redirecting to the main Journal & Notes screen with 'Exam Journal' filter active.
class ExamJournalScreen extends ConsumerStatefulWidget {
  const ExamJournalScreen({super.key});

  @override
  ConsumerState<ExamJournalScreen> createState() => _ExamJournalScreenState();
}

class _ExamJournalScreenState extends ConsumerState<ExamJournalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectedNoteTagProvider.notifier).state = 'Exam Journal';
    });
  }

  @override
  Widget build(BuildContext context) {
    return const JournalScreen();
  }
}
