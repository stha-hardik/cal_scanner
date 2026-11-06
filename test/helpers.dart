import 'dart:convert';

import 'package:cal_scanner/core/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A saved profile like the one onboarding creates.
Map<String, dynamic> sampleProfile({
  String goal = 'Maintenance',
  String activity = 'Moderate',
  double weight = 75,
}) =>
    {
      'weight': weight,
      'height': 175.0,
      'age': 24,
      'activityLevel': activity,
      'gender': 'Male',
      'goal': goal,
      'estimatedCalories': 2784,
      'proteinGoal': 175,
      'fatGoal': 77,
      'carbsGoal': 348,
    };

/// Fresh, empty-or-seeded SharedPreferences and a rebuilt service locator.
Future<SharedPreferences> freshPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.resetStatic();
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  await sl.reset();
  await configureDependencies(prefs: prefs, showOnboarding: false);
  return prefs;
}

Map<String, Object> withProfile(Map<String, dynamic> profile,
        [Map<String, Object> extra = const {}]) =>
    {'userData': jsonEncode(profile), 'onboarding_complete': true, ...extra};
