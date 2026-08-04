import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeController {
  AppThemeController._();

  static const String _preferenceKey = 'alpha_theme_mode';

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  static bool get isDarkMode => themeMode.value == ThemeMode.dark;

  static Future<void> initialize() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? storedMode = preferences.getString(_preferenceKey);

    themeMode.value = switch (storedMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static void setThemeMode(ThemeMode mode) {
    if (themeMode.value == mode) return;

    themeMode.value = mode;
    _persist(mode);
  }

  static void setDarkMode(bool enabled) {
    setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  static Future<void> _persist(ThemeMode mode) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final String value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    await preferences.setString(_preferenceKey, value);
  }
}
