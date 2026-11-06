import 'package:flutter/material.dart';

import '../../../core/settings/ai_settings.dart';
import '../../../core/settings/model_chooser.dart';
import '../../../core/settings/theme_settings.dart';
import '../../memory/presentation/memory_screen.dart';
import 'activity_section.dart';
import 'goal_section.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _auto = true;
  bool _hideKey = true;
  bool _busy = false;
  String _status = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _keyCtrl.text = await AiSettings.apiKey();
    _modelCtrl.text = await AiSettings.model();
    _auto = await AiSettings.autoSwitch();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({bool quiet = false}) async {
    await AiSettings.setApiKey(_keyCtrl.text);
    await AiSettings.setModel(_modelCtrl.text);
    await AiSettings.setAutoSwitch(_auto);
    if (!quiet && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _status = '';
    });
    try {
      await job();
    } catch (e) {
      _status = 'Problem: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _test() => _run(() async {
        await _save(quiet: true);
        final ok = await ModelChooser.probe(
          _keyCtrl.text.trim(),
          _modelCtrl.text.trim(),
        );
        _status = ok
            ? 'Works: ${_modelCtrl.text.trim()} accepts images.'
            : 'This model did not work (wrong name, no image support, or bad key). Try "Auto-pick best model".';
      });

  Future<void> _autoPick() => _run(() async {
        await _save(quiet: true);
        final found = await ModelChooser.findWorkingModel(
          _keyCtrl.text.trim(),
          onTrying: (m) {
            if (mounted) setState(() => _status = 'Trying $m ...');
          },
        );
        if (found == null) {
          _status = 'No working image model found on this key right now.';
        } else {
          _modelCtrl.text = found;
          await AiSettings.setModel(found);
          _status = 'Picked and saved: $found';
        }
      });

  Future<void> _showModels() => _run(() async {
        final models = await ModelChooser.listModels(_keyCtrl.text.trim());
        models.sort();
        if (!mounted) return;
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (_) => SafeArea(
            child: ListView(
              children: [
                const ListTile(
                  title: Text('Models on your key'),
                  subtitle: Text('Tap one to use it. Some are text-only.'),
                ),
                for (final m in models)
                  ListTile(
                    title: Text(m),
                    onTap: () => Navigator.pop(context, m),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) {
          _modelCtrl.text = picked;
          await AiSettings.setModel(picked);
          _status = 'Selected $picked. Tap "Test model" to check it.';
        }
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeSettings.mode,
                  builder: (_, mode, _) => SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => ThemeSettings.set(s.first),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.psychology_outlined),
                  title: const Text('Memory & health notes'),
                  subtitle: const Text(
                    'Health conditions and facts the AI should know about you',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MemoryScreen()),
                  ),
                ),
                const SizedBox(height: 16),
                const ActivitySection(),
                const GoalSection(),
                Text(
                  'AI',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyCtrl,
                  obscureText: _hideKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Groq API key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _hideKey ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _hideKey = !_hideKey),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _modelCtrl,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Model (must accept images)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Switch model automatically'),
                  subtitle: const Text(
                    'If the model stops working, find a working one and keep using it.',
                  ),
                  value: _auto,
                  onChanged: (v) => setState(() => _auto = v),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : () => _save(),
                      child: const Text('Save'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _test,
                      child: const Text('Test model'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _autoPick,
                      child: const Text('Auto-pick best model'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _showModels,
                      child: const Text('Show available models'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_busy) const LinearProgressIndicator(),
                if (_status.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_status),
                  ),
              ],
            ),
    );
  }
}
