import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../onboarding/data/models/user_data_model.dart';
import '../../onboarding/domain/entities/user_data.dart';
import '../../onboarding/domain/usecases/calculate_goals.dart';

/// Changes the saved goal and recalculates the daily targets from the profile
/// saved during onboarding. Used by Settings and by the AI chat.
class GoalChanger {
  static const _key = 'userData';

  /// Names the AI uses -> names stored in the app.
  static const fromTool = {
    'lose_weight': 'Weight Loss',
    'maintain': 'Maintenance',
    'gain_weight': 'Muscle Gain',
    'body_recomposition': 'Body Recomposition',
  };

  static const labels = {
    'Weight Loss': 'Lose weight',
    'Maintenance': 'Maintain',
    'Muscle Gain': 'Gain weight',
    'Body Recomposition': 'Body recomposition',
  };

  static void _check(String what, int? v, int min, int max) {
    if (v != null && (v < min || v > max)) {
      throw Exception('$what of $v is outside the range $min to $max.');
    }
  }

  /// Saves [goal] and returns the new targets. Optional custom numbers
  /// replace the calculated ones.
  static Future<UserData> apply(
    String goal, {
    int? calories,
    int? protein,
    int? carbs,
    int? fat,
    String? activityLevel,
  }) async {
    _check('Calories', calories, 1000, 6000);
    _check('Protein', protein, 20, 400);
    _check('Carbs', carbs, 0, 800);
    _check('Fat', fat, 10, 300);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) throw Exception('Finish the setup first to choose a goal.');
    final p = Map<String, dynamic>.from(jsonDecode(raw) as Map);

    final result = await CalculateGoals()(
      weight: (p['weight'] as num).toDouble(),
      heightCm: (p['height'] as num).toDouble(),
      age: (p['age'] as num).toInt(),
      activityLevel: activityLevel ?? p['activityLevel'] as String,
      gender: p['gender'] as String,
      goal: goal,
    );
    final d = result.fold((f) => throw Exception(f.message), (d) => d);
    final data = UserData(
      weight: d.weight,
      heightCm: d.heightCm,
      age: d.age,
      activityLevel: d.activityLevel,
      gender: d.gender,
      goal: d.goal,
      estimatedCalories: calories ?? d.estimatedCalories,
      proteinGoal: protein ?? d.proteinGoal,
      fatGoal: fat ?? d.fatGoal,
      carbsGoal: carbs ?? d.carbsGoal,
    );
    await prefs.setString(_key, jsonEncode(UserDataModel.fromDomain(data).toJson()));
    return data;
  }
}
