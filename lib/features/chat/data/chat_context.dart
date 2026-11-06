import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/di/service_locator.dart';
import '../../calories/data/datasources/food_local_datasource.dart';
import '../../memory/data/memory_store.dart';

/// Builds the instructions and personal data sent to the AI with every chat.
/// Rebuilt on each message so it always reflects the latest log.
class ChatContext {
  static const _goalNames = {
    'Weight Loss': 'lose weight',
    'Maintenance': 'maintain weight',
    'Muscle Gain': 'gain weight',
    'Body Recomposition': 'body recomposition (build muscle and lose fat together)',
  };

  static String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    final ds = sl<FoodLocalDataSource>();
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln(
        'You are the friendly nutrition coach inside the Cal AI calorie tracker app. '
        'Talk with the user about their eating, plans and goals using the data below.',
      )
      ..writeln('Guidelines:')
      ..writeln('- Be practical and concise (under about 200 words unless asked for more).')
      ..writeln('- When suggesting foods, give specific options with approximate calories and macros that fit the calories and macros they still have left today and their goal. Ask about cuisine, allergies or preferences if it would help.')
      ..writeln('- Only state facts about their log that appear in the data. If something is missing, say so.')
      ..writeln('- Calories and macros in the log are AI estimates from photos, so they are approximate.')
      ..writeln('- You can propose changes in the app with tools. Use log_meal when the user says they ate or drank something they want logged (estimate calories and macros if they did not give them, and say they are estimates). Use set_goal when they want a different goal (lose_weight, maintain, gain_weight, body_recomposition), optionally with custom daily calories, protein, carbs or fat. The app shows the user a Confirm button for every proposal, so say briefly what you are proposing and never claim it is already done. Only propose when the user asks or clearly agrees. Never log the same meal twice: check the log and earlier proposals first.')
      ..writeln('- Always respect the HEALTH NOTES and MEMORY below in every food suggestion. For example, with gastric problems or acid reflux prefer gentle, low-acid, low-fat, non-spicy foods and mention likely trigger foods. Never diagnose; for severe or persistent symptoms suggest seeing a doctor.')
      ..writeln('- When the user shares a lasting fact worth remembering (a health condition, allergy, food preference, routine or constraint), call save_memory with one short sentence. Do not save one-off or trivial things, and do not save what is already in memory. Tell the user briefly that you saved it.')
      ..writeln('- You are not a doctor. For medical conditions, pregnancy, eating disorders or very low calorie plans, suggest talking to a doctor or dietitian.')
      ..writeln()
      ..writeln('Today is ${_d(now)}.');

    final raw = prefs.getString('userData');
    int calGoal = 0, pGoal = 0, cGoal = 0, fGoal = 0;
    if (raw != null) {
      try {
        final p = jsonDecode(raw) as Map;
        calGoal = (p['estimatedCalories'] as num).toInt();
        pGoal = (p['proteinGoal'] as num).toInt();
        cGoal = (p['carbsGoal'] as num).toInt();
        fGoal = (p['fatGoal'] as num).toInt();
        b
          ..writeln()
          ..writeln('USER PROFILE')
          ..writeln('- Gender: ${p['gender']}, age: ${p['age']}, weight: ${p['weight']} kg, height: ${p['height']} cm')
          ..writeln('- Activity level: ${p['activityLevel']}')
          ..writeln('- Goal: ${_goalNames[p['goal']] ?? p['goal']}')
          ..writeln('- Daily targets: $calGoal kcal, protein ${pGoal}g, carbs ${cGoal}g, fat ${fGoal}g');
      } catch (_) {}
    } else {
      b
        ..writeln()
        ..writeln('USER PROFILE: not set up yet.');
    }

    // Today in detail, then the previous 13 days in short form.
    b
      ..writeln()
      ..writeln('TODAY\'S MEALS (${_d(now)})');
    final today = await ds.getDailyFoodLog(now);
    double tc = 0, tp = 0, tcb = 0, tf = 0;
    if (today.isEmpty) {
      b.writeln('- nothing logged yet');
    }
    for (final m in today) {
      tc += m.calories;
      tp += m.protein;
      tcb += m.carbs;
      tf += m.fat;
      final t = '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}';
      b.writeln('- $t ${m.name}: ${m.calories.round()} kcal, P ${m.protein.round()}g, C ${m.carbs.round()}g, F ${m.fat.round()}g');
    }
    b.writeln('Totals today: ${tc.round()} kcal, protein ${tp.round()}g, carbs ${tcb.round()}g, fat ${tf.round()}g.');
    if (calGoal > 0) {
      b.writeln('Left today: ${(calGoal - tc).round()} kcal, protein ${(pGoal - tp).round()}g, carbs ${(cGoal - tcb).round()}g, fat ${(fGoal - tf).round()}g (negative means over).');
    }

    b
      ..writeln()
      ..writeln('PREVIOUS 13 DAYS');
    var any = false;
    for (var i = 1; i <= 13; i++) {
      final day = now.subtract(Duration(days: i));
      final meals = await ds.getDailyFoodLog(day);
      if (meals.isEmpty) continue;
      any = true;
      final kcal = meals.fold<double>(0, (s, m) => s + m.calories).round();
      final p = meals.fold<double>(0, (s, m) => s + m.protein).round();
      final c = meals.fold<double>(0, (s, m) => s + m.carbs).round();
      final f = meals.fold<double>(0, (s, m) => s + m.fat).round();
      final names = meals.map((m) => m.name).take(8).join(', ');
      b.writeln('- ${_d(day)}: $kcal kcal, P ${p}g, C ${c}g, F ${f}g. Meals: $names');
    }
    if (!any) b.writeln('- no earlier days logged');
    b.write(await MemoryStore.promptBlock());
    return b.toString();
  }
}
