import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global StateProvider for Admission Target Goal
/// Defaults to 'Engineering' and is shared across ProfileScreen and SyllabusScreen.
final admissionTargetProvider = StateProvider<String>((ref) => 'Engineering');
