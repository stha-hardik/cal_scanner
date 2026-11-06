import 'dart:convert';

import 'package:cal_scanner/features/settings/data/goal_changer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<Map<String, dynamic>> saved() async {
  final p = await SharedPreferences.getInstance();
  return jsonDecode(p.getString('userData')!) as Map<String, dynamic>;
}

void main() {
  test('every goal recalculates targets from the saved profile', () async {
    await freshPrefs(withProfile(sampleProfile()));
    final expected = {
      'Maintenance': 2784,
      'Weight Loss': 2227,
      'Muscle Gain': 3202,
      'Body Recomposition': 2506,
    };
    for (final e in expected.entries) {
      final d = await GoalChanger.apply(e.key);
      expect(d.estimatedCalories, e.value, reason: e.key);
      expect(d.goal, e.key);
      final s = await saved();
      expect(s['goal'], e.key);
      expect(s['estimatedCalories'], e.value);
      expect(s['weight'], 75, reason: 'profile is kept');
    }
  });

  test('custom numbers override the calculated ones', () async {
    await freshPrefs(withProfile(sampleProfile()));
    final d = await GoalChanger.apply('Weight Loss',
        calories: 2000, protein: 160, carbs: 180, fat: 60);
    expect([d.estimatedCalories, d.proteinGoal, d.carbsGoal, d.fatGoal], [2000, 160, 180, 60]);
    final s = await saved();
    expect(s['estimatedCalories'], 2000);
    expect(s['proteinGoal'], 160);
  });

  test('out-of-range numbers are rejected and nothing is saved', () async {
    await freshPrefs(withProfile(sampleProfile()));
    for (final f in <Future Function()>[
      () => GoalChanger.apply('Maintenance', calories: 500),
      () => GoalChanger.apply('Maintenance', calories: 9000),
      () => GoalChanger.apply('Maintenance', protein: 5),
      () => GoalChanger.apply('Maintenance', carbs: 2000),
      () => GoalChanger.apply('Maintenance', fat: 1),
    ]) {
      await expectLater(f(), throwsException);
    }
    expect((await saved())['goal'], 'Maintenance');
    expect((await saved())['estimatedCalories'], 2784);
  });

  test('changing the workout level changes calories and keeps the goal', () async {
    await freshPrefs(withProfile(sampleProfile(goal: 'Weight Loss')));
    final low = await GoalChanger.apply('Weight Loss', activityLevel: 'Sedentary');
    final high = await GoalChanger.apply('Weight Loss', activityLevel: 'Very Active');
    expect(high.estimatedCalories > low.estimatedCalories, true);
    expect(low.estimatedCalories, (2156 * 0.8).round());
    final s = await saved();
    expect(s['activityLevel'], 'Very Active');
    expect(s['goal'], 'Weight Loss');
  });

  test('without a saved profile it explains what to do', () async {
    await freshPrefs();
    await expectLater(
        GoalChanger.apply('Maintenance'),
        throwsA(predicate((e) => e.toString().contains('Finish the setup'))));
  });

  test('AI goal names map to app goals', () {
    expect(GoalChanger.fromTool['body_recomposition'], 'Body Recomposition');
    expect(GoalChanger.fromTool.length, 4);
    for (final g in GoalChanger.fromTool.values) {
      expect(GoalChanger.labels.containsKey(g), true);
    }
  });
}
