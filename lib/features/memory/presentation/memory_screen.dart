import 'dart:async';

import 'package:cal_scanner/theme/app_colors.dart';
import 'package:flutter/material.dart';

import '../../../core/privacy/photo_cleaner.dart';
import '../data/memory_store.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final _health = TextEditingController();
  final _add = TextEditingController();
  Timer? _debounce;
  List<MemoryItem> _items = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _health.text = await MemoryStore.healthNotes();
    _items = await MemoryStore.items();
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    MemoryStore.setHealthNotes(_health.text); // save whatever is typed
    _health.dispose();
    _add.dispose();
    super.dispose();
  }

  void _healthChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 600),
      () => MemoryStore.setHealthNotes(v),
    );
  }

  Future<void> _addMemory() async {
    final text = _add.text;
    if (text.trim().isEmpty) return;
    final item = await MemoryStore.add(text);
    _add.clear();
    if (item == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Already in memory.')),
      );
    }
    _items = await MemoryStore.items();
    if (mounted) setState(() {});
  }

  Future<void> _edit(MemoryItem m) async {
    final c = TextEditingController(text: m.text);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit memory'),
        content: TextField(controller: c, maxLines: null, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (saved != null) {
      await MemoryStore.update(m.id, saved);
      _items = await MemoryStore.items();
      if (mounted) setState(() {});
    }
  }

  Future<void> _delete(MemoryItem m) async {
    await MemoryStore.remove(m.id);
    _items = await MemoryStore.items();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Memory & health')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Health & dietary notes', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Always sent to the AI so its advice fits you.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _health,
                  onChanged: _healthChanged,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: MemoryStore.maxHealthLength,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. I have gastric problems and acid reflux, lactose intolerant, no spicy food',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Memory', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Facts the AI remembers across chats. The AI can add to this '
                  'during a conversation (you can undo it there). Everything '
                  'here is sent to the AI with each message.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _add,
                        maxLength: MemoryStore.maxTextLength,
                        onSubmitted: (_) => _addMemory(),
                        decoration: const InputDecoration(
                          hintText: 'Add something to remember',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addMemory,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nothing saved yet.', style: t.bodyMedium),
                  ),
                for (final m in _items)
                  Card(
                    margin: const EdgeInsets.only(top: 8),
                    color: AppColors.kCard,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.kPrimaryGrey),
                    ),
                    child: ListTile(
                      title: Text(m.text),
                      subtitle: Text(m.source == 'ai' ? 'Saved by AI' : 'Added by you'),
                      onTap: () => _edit(m),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(m),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                Text('Privacy', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Meal photos are one-time shots. They are sent for analysis and '
                  'only the text (name, calories, macros) is saved. The temporary '
                  'photo copy on your phone is deleted after 24 hours.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () async {
                      final n = await PhotoCleaner.purge(all: true);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(n == 0 ? 'No temporary photos found.' : 'Deleted temporary photos.')),
                      );
                    },
                    child: const Text('Delete temporary photos now'),
                  ),
                ),
              ],
            ),
    );
  }
}
