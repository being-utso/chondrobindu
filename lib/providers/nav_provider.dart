import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider to manage the selected index of the bottom NavigationBar
final navigationIndexProvider = StateProvider<int>((ref) => 0);
