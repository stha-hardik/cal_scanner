import 'package:cal_scanner/core/utils/calorie_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int maintenance(String activity) => CalorieCalculator.fallbackEstimateCalories(
        weight: 75, height: 175, age: 24, activityLevel: activity, gender: 'Male');

  test('maintenance calories scale with the workout level', () {
    expect(maintenance('Sedentary'), 2156);
    expect(maintenance('Light'), 2470);
    expect(maintenance('Moderate'), 2784);
    expect(maintenance('Active'), 3099);
    expect(maintenance('Very Active'), 3413);
    final all = ['Sedentary', 'Light', 'Moderate', 'Active', 'Very Active']
        .map(maintenance)
        .toList();
    expect([...all]..sort(), all, reason: 'higher level must never lower calories');
  });

  test('goal adjustments', () {
    int adj(String g) => CalorieCalculator.calculateCaloriesBasedOnGoal(
        maintenanceCalories: 2784, goal: g);
    expect(adj('Maintenance'), 2784);
    expect(adj('Weight Loss'), 2227); // -20%
    expect(adj('Muscle Gain'), 3202); // +15%
    expect(adj('Body Recomposition'), 2506); // -10%
    expect(adj('Something else'), 2784);
  });

  test('recomposition deficit is capped at 300 kcal and never negative', () {
    int adj(int m) => CalorieCalculator.calculateCaloriesBasedOnGoal(
        maintenanceCalories: m, goal: 'Body Recomposition');
    expect(adj(2000), 1800); // 10%
    expect(adj(3500), 3200); // capped at 300
    expect(adj(5000), 4700);
    expect(adj(0), 0);
  });

  test('recomposition macros: 2.2 g/kg protein, fat 25%, carbs fill the rest', () {
    final m = CalorieCalculator.calculateMacroGoals(
        calories: 2506, goal: 'Body Recomposition', weight: 75);
    expect(m['proteinGoal'], 165);
    expect(m['fatGoal'], (2506 * 0.25 / 9).round());
    final kcal = m['proteinGoal']! * 4 + m['fatGoal']! * 9 + m['carbsGoal']! * 4;
    expect((kcal - 2506).abs(), lessThan(8), reason: 'macros must add up to the calories');
  });

  test('recomposition without weight falls back to percentages, carbs never negative', () {
    final m = CalorieCalculator.calculateMacroGoals(
        calories: 2000, goal: 'Body Recomposition');
    expect(m['proteinGoal']! > 0, true);
    final tiny = CalorieCalculator.calculateMacroGoals(
        calories: 600, goal: 'Body Recomposition', weight: 150);
    expect(tiny['carbsGoal']! >= 0, true);
  });

  test('other goals keep their original percentage macros', () {
    final m = CalorieCalculator.calculateMacroGoals(calories: 2000, goal: 'Weight Loss');
    expect(m['proteinGoal'], 150); // 30%
    expect(m['fatGoal'], 56); // 25%
    expect(m['carbsGoal'], 225); // 45%
  });
}
