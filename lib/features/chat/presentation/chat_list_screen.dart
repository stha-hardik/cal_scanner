import 'package:flutter/material.dart';

import '../data/chat_store.dart';

/// Saved chats. Tap one to continue it; pops with the chosen thread.
class ChatListScreen extends StatefulWidget {
  final String? currentId;
  const ChatListScreen({super.key, this.currentId});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatThread>? _threads;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await ChatStore.all();
    if (mounted) setState(() => _threads = all);
  }

  String _when(DateTime d) {
    final now = DateTime.now();
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    final hm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return sameDay ? 'Today $hm' : '${d.day}/${d.month}/${d.year}';
  }

  Future<void> _delete(ChatThread t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(t.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await ChatStore.delete(t.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat history')),
      body: threads == null
          ? const Center(child: CircularProgressIndicator())
          : threads.isEmpty
              ? const Center(child: Text('No saved chats yet.'))
              : ListView.separated(
                  itemCount: threads.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = threads[i];
                    final last = t.messages.isEmpty ? '' : t.messages.last.content;
                    return ListTile(
                      selected: t.id == widget.currentId,
                      title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${_when(t.updated)}  •  $last',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(t),
                      ),
                      onTap: () => Navigator.pop(context, t),
                    );
                  },
                ),
    );
  }
}
