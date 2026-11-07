import 'package:flutter/material.dart';

import '../../../core/settings/ai_settings.dart';

/// Plate and katori size (used as a ruler in photos) and the web lookup switch.
class PortionSection extends StatefulWidget {
  const PortionSection({super.key});

  @override
  State<PortionSection> createState() => _PortionSectionState();
}

class _PortionSectionState extends State<PortionSection> {
  double _plate = 26;
  double _katori = 150;
  bool _web = true;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plate = await AiSettings.plateCm();
    final katori = await AiSettings.katoriMl();
    final web = await AiSettings.webSearch();
    if (!mounted) return;
    setState(() {
      _plate = plate.clamp(18, 36).toDouble();
      _katori = katori.clamp(100, 300).toDouble();
      _web = web;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Food photos', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'The AI uses your plate and katori as a ruler to judge portion size. '
          'Measure your plate across (in cm) once.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text('My plate: ${_plate.round()} cm across'),
        Slider(
          value: _plate,
          min: 18,
          max: 36,
          divisions: 18,
          label: '${_plate.round()} cm',
          onChanged: (v) => setState(() => _plate = v),
          onChangeEnd: (v) => AiSettings.setPlateCm(v),
        ),
        Text('My katori (small bowl): ${_katori.round()} ml'),
        Slider(
          value: _katori,
          min: 100,
          max: 300,
          divisions: 8,
          label: '${_katori.round()} ml',
          onChanged: (v) => setState(() => _katori = v),
          onChangeEnd: (v) => AiSettings.setKatoriMl(v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Look up unknown foods on the web'),
          subtitle: const Text(
            'Foods not in the built-in Nepali table are searched online with a bigger model. Slower and uses more of your Groq limit.',
          ),
          value: _web,
          onChanged: (v) {
            setState(() => _web = v);
            AiSettings.setWebSearch(v);
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
