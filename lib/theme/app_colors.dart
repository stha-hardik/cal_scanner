import 'package:flutter/material.dart';

/// App colors. They follow the current theme: [isDark] is set by the app
/// whenever the theme changes (see ThemeSettings), and the UI is rebuilt.
class AppColors {
  static bool isDark = false;

  static Color get kScaffold =>
      isDark ? const Color(0xFF121212) : const Color(0xfff9f6f1);
  static Color get kLightGrey => isDark
      ? const Color.fromARGB(40, 255, 255, 255)
      : const Color.fromARGB(15, 66, 66, 66);

  /// Main text / strong foreground colour.
  static Color get kBlack => isDark
      ? const Color.fromARGB(235, 255, 255, 255)
      : const Color.fromARGB(196, 0, 0, 0);
  static Color get kOrange => Colors.orange;

  static Color get kPureBlack => isDark ? Colors.white : Colors.black;

  /// Surface colour for cards and inputs (white in light mode).
  static Color get kWhite =>
      isDark ? const Color(0xFF1E1E1E) : const Color.fromARGB(255, 255, 255, 255);
  static Color get kCard => kWhite;
  static Color get kgrey => Colors.grey;
  static Color get kPrimaryGrey =>
      isDark ? const Color(0xFF3A3A3A) : const Color.fromARGB(255, 232, 232, 232);
}
