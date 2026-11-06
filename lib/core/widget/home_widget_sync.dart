import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pushes today's totals to the Android home screen widgets.
/// Safe to call on any platform: failures are swallowed.
class HomeWidgetSync {
  static const MethodChannel _channel = MethodChannel('cal_ai/widget');

  /// Tell the home screen widgets which look to use: system, light or dark.
  static Future<void> pushTheme(String mode) async {
    try {
      await _channel.invokeMethod('theme', {'theme': mode});
    } catch (_) {}
  }

  static Future<void> update({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required int meals,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      num calorieGoal = 2000, proteinGoal = 120, carbsGoal = 250, fatGoal = 65;
      final raw = prefs.getString('userData');
      if (raw != null) {
        final m = jsonDecode(raw);
        if (m is Map) {
          calorieGoal = (m['estimatedCalories'] as num?) ?? calorieGoal;
          proteinGoal = (m['proteinGoal'] as num?) ?? proteinGoal;
          carbsGoal = (m['carbsGoal'] as num?) ?? carbsGoal;
          fatGoal = (m['fatGoal'] as num?) ?? fatGoal;
        }
      }
      await _channel.invokeMethod('update', {
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'meals': meals,
        'calorieGoal': calorieGoal,
        'proteinGoal': proteinGoal,
        'carbsGoal': carbsGoal,
        'fatGoal': fatGoal,
        'theme': prefs.getString('theme_mode') ?? 'system',
      });
    } catch (_) {
      // Not on Android, or widget channel unavailable. Ignore.
    }
  }
}
