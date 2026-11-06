import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/home_widget_sync.dart';

/// Light / Dark / System choice, saved on the phone.
class ThemeSettings {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static const _key = 'theme_mode';

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    mode.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  static Future<void> set(ThemeMode m) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m.name);
    mode.value = m;
    HomeWidgetSync.pushTheme(m.name);
  }

  static bool effectiveDark(ThemeMode m) =>
      m == ThemeMode.dark ||
      (m == ThemeMode.system &&
          PlatformDispatcher.instance.platformBrightness == Brightness.dark);
}
