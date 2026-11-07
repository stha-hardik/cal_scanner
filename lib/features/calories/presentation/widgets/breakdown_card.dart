import 'package:flutter/material.dart';

/// Per-item breakdown of a meal: what was recognised, how many grams, and
/// where each number came from.
class BreakdownCard extends StatelessWidget {
  final String details;
  const BreakdownCard({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final lines = details.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What the AI saw', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $l', style: TextStyle(fontSize: 13, color: cs.onSurface)),
            ),
          const SizedBox(height: 4),
          Text(
            'Portion sizes from photos are estimates (about 20-30% off). Typing the count in the note is the most accurate.',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
