import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kThemeModeKey = 'chondrobindu_theme_mode';

/// Manages dynamic theme switching between Light Mode (Lime Wash & Indigo Dye)
/// and Dark Mode (Indigo Slate & Luminous Rust).
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_kThemeModeKey);
      if (savedMode == 'light') {
        state = ThemeMode.light;
      } else if (savedMode == 'dark') {
        state = ThemeMode.dark;
      } else if (savedMode == 'system') {
        state = ThemeMode.system;
      }
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(newMode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.light
          ? 'light'
          : (mode == ThemeMode.dark ? 'dark' : 'system');
      await prefs.setString(_kThemeModeKey, modeStr);
    } catch (_) {}
  }
}

/// Global provider for the active ThemeMode
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
