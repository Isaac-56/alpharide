import 'package:flutter/material.dart';

class AppThemeController {
  AppThemeController._();

  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  static bool get isDarkMode => themeMode.value == ThemeMode.dark;

  static void setDarkMode(bool enabled) {
    themeMode.value = enabled ? ThemeMode.dark : ThemeMode.light;
  }
}
