import 'package:cal_scanner/theme/app_colors.dart';
import 'package:cal_scanner/app_widgets/buttons/back_button.dart';
import 'package:cal_scanner/core/extensions/capital_first_extension.dart';
import 'package:cal_scanner/core/privacy/photo_cleaner.dart';
import 'package:cal_scanner/features/calories/presentation/widgets/breakdown_card.dart';
import 'package:cal_scanner/core/extensions/context_extension.dart';
import 'package:cal_scanner/core/extensions/widget_extension.dart';
import 'package:cal_scanner/features/calories/presentation/cubit/food_log_cubit.dart';
import 'package:cal_scanner/features/calories/presentation/widgets/macros_card.dart';
import 'package:cal_scanner/theme/app_typography.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' hide VerticalDivider;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/food.dart';
import 'package:timeago/timeago.dart' as timeago;

class MealDetailScreen extends StatefulWidget {
  final Food meal;

  const MealDetailScreen({super.key, required this.meal});

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  late Food meal = widget.meal;
  bool _busy = false;

  Future<void> _edit() async {
    final photo = PhotoCleaner.freshPhoto(meal.photoPath);
    final ctrl = TextEditingController(text: meal.note ?? '');
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit meal', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              photo != null
                  ? 'Tell the AI what to fix. Your note and the photo are sent again to re-estimate this meal.'
                  : 'The photo is gone (photos are deleted after 24 hours), so the AI will re-estimate from the meal name, its numbers and your note.',
              style: TextStyle(color: ctx.colors.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'e.g. It was 2 eggs and 1 roti, not 4 eggs',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.kOrange),
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: const Text('Re-analyze'),
              ),
            ),
          ],
        ),
      ),
    );
    if (note == null || !mounted) return;
    if (note.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Write a note first.')));
      return;
    }
    final cubit = context.read<FoodLogCubit>();
    setState(() => _busy = true);
    final result = await cubit.reestimateMeal(meal, note);
    if (!mounted) return;
    setState(() => _busy = false);
    await result.fold(
      (f) async => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not update: ${f.message}'))),
      (updated) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(updated.name.capitalizeFirst()),
            content: Text(
              'New estimate:\n${updated.calories.round()} kcal\n'
              'Protein ${updated.protein.round()}g  Carbs ${updated.carbs.round()}g  Fat ${updated.fat.round()}g\n\n'
              'Before: ${meal.calories.round()} kcal',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep old')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
            ],
          ),
        );
        if (ok == true && mounted) {
          await cubit.updateMeal(updated);
          if (mounted) setState(() => meal = updated);
        }
      },
    );
  }

  void _deleteMeal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Meal'),
        content: Text('Are you sure you want to delete this meal?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppColors.kPureBlack)),
          ),
          TextButton(
            onPressed: () {
              context.read<FoodLogCubit>().deleteMeal(meal);
              Navigator.pop(context); // Close the dialog
              Navigator.pop(context);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = PhotoCleaner.freshPhoto(meal.photoPath);
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: context.colors.surface,
        iconTheme: IconThemeData(color: context.colors.onSurface),
        leading: AppBackButton(),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(CupertinoIcons.pencil, color: context.colors.onSurface),
            onPressed: _busy ? null : _edit,
          ),
          IconButton(
            icon: Icon(CupertinoIcons.delete, color: Colors.red),
            onPressed: () => _deleteMeal(context),
          ).paddingOnly(right: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.file(
                  photo,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (photo != null) SizedBox(height: 24),
            if (meal.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Image.network(
                  meal.imageUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            if (meal.imageUrl != null) SizedBox(height: 24),

            // Large calorie display
            Text(
              meal.name.capitalizeFirst(),
              style: AppTypography.headlineMedium,
            ),
            SizedBox(height: 30),

            Text(
              meal.calories.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 80,
                fontWeight: FontWeight.bold,
                color: Colors.orange,
                height: 1.0,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'calories',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[500],
                fontWeight: FontWeight.w400,
              ),
            ),

            SizedBox(height: 32),

            // Macros card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.kCard,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  MacroItem(
                    value: '${meal.protein.toStringAsFixed(0)}g',
                    label: 'Protein',
                    color: Colors.blue,
                  ),
                  VerticalDivider(),

                  MacroItem(
                    value: '${meal.carbs.toStringAsFixed(0)}g',
                    label: 'Carbs',
                    color: Colors.orange,
                  ),
                  VerticalDivider(),
                  MacroItem(
                    value: '${meal.fat.toStringAsFixed(0)}g',
                    label: 'Fat',
                    color: Colors.redAccent,
                  ),
                ],
              ),
              ),
            ),

            SizedBox(height: 32),

            // Additional details
            _DetailRow(
              icon: Icons.access_time,
              label: 'Logged',
              value: timeago.format(meal.timestamp),
            ),
            if ((meal.details ?? '').isNotEmpty) ...[
              SizedBox(height: 24),
              BreakdownCard(details: meal.details!),
              SizedBox(height: 8),
            ],
            if ((meal.note ?? '').isNotEmpty)
              _DetailRow(
                icon: Icons.notes,
                label: 'Note',
                value: meal.note!,
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.colors.primary),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.colors.onSurface,
              ),
            ),
          ),
          SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: context.colors.onSurfaceVariant,
            ),
          ),
          ),
        ],
      ),
    );
  }
}
