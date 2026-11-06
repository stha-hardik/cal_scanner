import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../calories/presentation/cubit/food_log_cubit.dart';
import '../data/goal_changer.dart';

/// Lets the user change their goal later. Targets are recalculated from the
/// profile saved during onboarding (weight, height, age, activity, gender).
class GoalSection extends StatefulWidget {
  const GoalSection({super.key});

  @override
  State<GoalSection> createState() => _GoalSectionState();
}

class _GoalSectionState extends State<GoalSection> {
  static const _goals = <(String, String, String)>[
    ('Weight Loss', 'Lose weight', '20% below maintenance'),
    ('Maintenance', 'Maintain', 'Eat at maintenance'),
    ('Muscle Gain', 'Gain weight', '15% above maintenance'),
    (
      'Body Recomposition',
      'Body recomposition',
      'Build muscle and lose fat together',
    ),
  ];

  static const _key = 'userData';
  Map<String, dynamic>? _profile;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) _profile = Map<String, dynamic>.from(decoded);
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _choose(String goal) async {
    final p = _profile;
    if (p == null || _busy || p['goal'] == goal) return;
    setState(() => _busy = true);
    final cubit = context.read<FoodLogCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await GoalChanger.apply(goal);
      final prefs = await SharedPreferences.getInstance();
      _profile = Map<String, dynamic>.from(jsonDecode(prefs.getString(_key)!));
      await cubit.loadDailyLog(); // refreshes home screen and widgets
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Goal updated: ${data.estimatedCalories} kcal, '
            '${data.proteinGoal}g protein',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not change goal: ${e.toString().replaceFirst('Exception: ', '')}')),
      );
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (!_loaded) return const SizedBox.shrink();
    final p = _profile;
    if (p == null) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 24),
        child: Text('Finish the setup first to choose a goal.'),
      );
    }
    final current = p['goal'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Goal', style: textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Daily target: ${p['estimatedCalories']} kcal  •  '
          'P ${p['proteinGoal']}g  C ${p['carbsGoal']}g  F ${p['fatGoal']}g',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        RadioGroup<String>(
          groupValue: current,
          onChanged: (v) {
            if (v != null) _choose(v);
          },
          child: Column(
            children: [
              for (final g in _goals)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: g.$1,
                  enabled: !_busy,
                  title: Text(g.$2),
                  subtitle: Text(g.$3),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
