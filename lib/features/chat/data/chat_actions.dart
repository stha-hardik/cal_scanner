import '../../../core/di/service_locator.dart';
import '../../calories/domain/entities/food.dart';
import '../../calories/domain/usecases/add_food.dart';
import '../../calories/presentation/cubit/food_log_cubit.dart';
import '../../settings/data/goal_changer.dart';
import 'chat_store.dart';

/// Describes and carries out the changes the AI proposes.
class ChatActions {
  static const toolNames = {'log_meal', 'set_goal', 'save_memory'};

  static num? _num(Object? v) => v is num ? v : num.tryParse('$v');

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// One-line summary shown on the confirm card.
  static String describe(ChatAction a) {
    final g = a.args;
    if (a.name == 'save_memory') return 'Save to memory: ${g['text']}';
    if (a.name == 'log_meal') {
      final date = (g['date'] as String?) ?? _today();
      return 'Log meal: ${g['name']}  •  ${_num(g['calories'])?.round()} kcal  •  '
          'P ${_num(g['protein'])?.round()}g  C ${_num(g['carbs'])?.round()}g  '
          'F ${_num(g['fat'])?.round()}g  •  $date';
    }
    final goal = GoalChanger.fromTool[g['goal']] ?? '${g['goal']}';
    final custom = <String>[
      if (_num(g['calories']) != null) '${_num(g['calories'])!.round()} kcal',
      if (_num(g['protein']) != null) 'protein ${_num(g['protein'])!.round()}g',
      if (_num(g['carbs']) != null) 'carbs ${_num(g['carbs'])!.round()}g',
      if (_num(g['fat']) != null) 'fat ${_num(g['fat'])!.round()}g',
    ];
    return 'Change goal to ${GoalChanger.labels[goal] ?? goal}'
        '${custom.isEmpty ? ' (targets recalculated from your profile)' : ' with ${custom.join(', ')}'}';
  }

  /// Applies the action and returns a short result message. Throws on failure.
  static Future<String> apply(ChatAction a, FoodLogCubit cubit) async {
    final g = a.args;
    if (a.name == 'log_meal') {
      final name = '${g['name'] ?? ''}'.trim();
      final cal = _num(g['calories']);
      final p = _num(g['protein']);
      final c = _num(g['carbs']);
      final f = _num(g['fat']);
      if (name.isEmpty || cal == null || p == null || c == null || f == null) {
        throw Exception('The meal details are incomplete.');
      }
      if (cal < 0 || cal > 5000 || p < 0 || p > 500 || c < 0 || c > 1000 || f < 0 || f > 500) {
        throw Exception('Those numbers look unrealistic for one meal.');
      }
      final now = DateTime.now();
      var when = now;
      final dateStr = g['date'] as String?;
      if (dateStr != null && dateStr != _today()) {
        final d = DateTime.tryParse(dateStr);
        if (d == null) throw Exception('Could not understand the date "$dateStr".');
        if (d.isAfter(now)) throw Exception('That date is in the future.');
        when = DateTime(d.year, d.month, d.day, 12);
      }
      final food = Food(
        id: now.microsecondsSinceEpoch.toString(),
        name: name,
        calories: cal.toDouble(),
        protein: p.toDouble(),
        carbs: c.toDouble(),
        fat: f.toDouble(),
        quantity: 100.0,
        timestamp: when,
      );
      final res = await sl<AddFood>()(food);
      res.fold((l) => throw Exception(l.message), (_) {});
      await cubit.loadDailyLog();
      return 'Logged "$name" (${cal.round()} kcal).';
    }

    if (a.name == 'set_goal') {
      final goal = GoalChanger.fromTool[g['goal']];
      if (goal == null) throw Exception('Unknown goal "${g['goal']}".');
      final data = await GoalChanger.apply(
        goal,
        calories: _num(g['calories'])?.round(),
        protein: _num(g['protein'])?.round(),
        carbs: _num(g['carbs'])?.round(),
        fat: _num(g['fat'])?.round(),
      );
      await cubit.loadDailyLog();
      return 'Goal set to ${GoalChanger.labels[goal]}: ${data.estimatedCalories} kcal, '
          'P ${data.proteinGoal}g, C ${data.carbsGoal}g, F ${data.fatGoal}g.';
    }
    throw Exception('Unknown action.');
  }
}
