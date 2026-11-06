import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calories/presentation/cubit/food_log_cubit.dart';
import '../data/goal_changer.dart';

/// Weekly workout level. Moving the slider recalculates the daily calories
/// and macros for the current goal.
class ActivitySection extends StatefulWidget {
  const ActivitySection({super.key});

  @override
  State<ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<ActivitySection> {
  static const _levels = <(String, String)>[
    ('Sedentary', 'Little or no exercise'),
    ('Light', 'Exercise 1-3 days a week'),
    ('Moderate', 'Exercise 3-5 days a week'),
    ('Active', 'Exercise 6-7 days a week'),
    ('Very Active', 'Hard exercise every day'),
  ];

  Map<String, dynamic>? _profile;
  double _value = 0;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('userData');
    if (raw != null) {
      _profile = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final i = _levels.indexWhere((l) => l.$1 == _profile!['activityLevel']);
      _value = (i < 0 ? 0 : i).toDouble();
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _apply(double v) async {
    final p = _profile;
    final level = _levels[v.round()].$1;
    if (p == null || _busy || p['activityLevel'] == level) return;
    setState(() => _busy = true);
    final cubit = context.read<FoodLogCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await GoalChanger.apply(
        p['goal'] as String,
        activityLevel: level,
      );
      final prefs = await SharedPreferences.getInstance();
      _profile = Map<String, dynamic>.from(jsonDecode(prefs.getString('userData')!));
      await cubit.loadDailyLog(); // refreshes home screen and widgets
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Workout level $level: ${data.estimatedCalories} kcal, '
            '${data.proteinGoal}g protein',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not change it: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _profile == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final current = _levels[_value.round()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Workout this week', style: t.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Set this at the start of each week. Your daily calories change to match.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 4),
        Text('${current.$1}: ${current.$2}', style: t.bodyMedium),
        Slider(
          value: _value,
          min: 0,
          max: 4,
          divisions: 4,
          label: current.$1,
          onChanged: _busy ? null : (v) => setState(() => _value = v),
          onChangeEnd: _apply,
        ),
        Text(
          'Daily target: ${_profile!['estimatedCalories']} kcal  •  '
          'P ${_profile!['proteinGoal']}g  C ${_profile!['carbsGoal']}g  F ${_profile!['fatGoal']}g',
          style: t.bodySmall,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
