import 'package:cal_scanner/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../calories/presentation/cubit/food_log_cubit.dart';
import '../data/chat_actions.dart';
import '../data/chat_service.dart';
import '../data/chat_store.dart';
import '../../memory/data/memory_store.dart';
import '../../memory/presentation/memory_screen.dart';
import 'chat_list_screen.dart';
import 'rich_reply.dart';

class ChatScreen extends StatefulWidget {
  final ChatThread? thread;
  const ChatScreen({super.key, this.thread});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _starters = [
    'What should I eat next?',
    'Review my day so far',
    'Plan my meals for tomorrow',
    'Am I on track with my goal?',
  ];

  late ChatThread _thread;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread ?? ChatThread.fresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(jump: true));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(end);
    } else {
      _scroll.animateTo(end,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _error = null;
      _sending = true;
      _thread.messages
          .add(ChatMessage(role: 'user', content: text, time: DateTime.now()));
      if (_thread.messages.length == 1) {
        _thread.title = text.length > 40 ? '${text.substring(0, 40)}...' : text;
      }
      _thread.updated = DateTime.now();
    });
    await ChatStore.save(_thread);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    await _ask();
  }

  Future<void> _ask() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final reply = await ChatService.reply(_thread.messages);
      _thread.messages.add(
        ChatMessage(
          role: 'assistant',
          content: reply.text,
          time: DateTime.now(),
          actions: reply.actions,
        ),
      );
      _thread.updated = DateTime.now();
      await ChatStore.save(_thread);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  final _working = <String>{};

  Future<void> _confirm(ChatAction a) async {
    if (_working.contains(a.id)) return;
    final cubit = context.read<FoodLogCubit>();
    setState(() => _working.add(a.id));
    try {
      a.result = await ChatActions.apply(a, cubit);
      a.status = 'done';
    } catch (e) {
      a.result = 'Could not do that: ${e.toString().replaceFirst('Exception: ', '')}';
    }
    _thread.updated = DateTime.now();
    await ChatStore.save(_thread);
    if (mounted) setState(() => _working.remove(a.id));
  }

  Future<void> _dismiss(ChatAction a) async {
    setState(() {
      a.status = 'dismissed';
      a.result = null;
    });
    await ChatStore.save(_thread);
  }

  Future<void> _undoMemory(ChatAction a) async {
    final id = a.args['memoryId'] as String?;
    if (id != null) await MemoryStore.remove(id);
    setState(() => a.status = 'undone');
    await ChatStore.save(_thread);
  }

  Widget _memoryCard(ChatAction a) {
    final undone = a.status == 'undone';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.kPrimaryGrey.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology_outlined, size: 18, color: AppColors.kgrey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              undone
                  ? 'Removed from memory: ${a.args['text']}'
                  : 'Saved to memory: ${a.args['text']}',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.kBlack,
                decoration: undone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!undone)
            TextButton(onPressed: () => _undoMemory(a), child: const Text('Undo')),
        ],
      ),
    );
  }

  Widget _actionCard(ChatAction a) {
    if (a.name == 'save_memory') return _memoryCard(a);
    final busy = _working.contains(a.id);
    final failed = a.status == 'pending' && a.result != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.kPrimaryGrey.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChatActions.describe(a),
            style: TextStyle(fontSize: 14, color: AppColors.kBlack),
          ),
          const SizedBox(height: 6),
          if (a.status == 'done')
            Row(children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(a.result ?? 'Done',
                    style: TextStyle(fontSize: 13, color: AppColors.kBlack)),
              ),
            ])
          else if (a.status == 'dismissed')
            Text('Dismissed', style: TextStyle(fontSize: 13, color: AppColors.kgrey))
          else ...[
            if (failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(a.result!,
                    style: const TextStyle(fontSize: 13, color: Colors.red)),
              ),
            Row(children: [
              FilledButton(
                onPressed: busy ? null : () => _confirm(a),
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(failed ? 'Try again' : 'Confirm'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy ? null : () => _dismiss(a),
                child: const Text('Dismiss'),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _openHistory() async {
    final picked = await Navigator.of(context).push<ChatThread>(
      MaterialPageRoute(
        builder: (_) => ChatListScreen(currentId: _thread.id),
      ),
    );
    if (!mounted) return;
    final all = await ChatStore.all();
    setState(() {
      _error = null;
      if (picked != null) {
        _thread = picked;
      } else if (_thread.messages.isNotEmpty &&
          !all.any((t) => t.id == _thread.id)) {
        _thread = ChatThread.fresh(); // current chat was deleted
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(jump: true));
  }

  void _newChat() {
    if (_sending) return;
    setState(() {
      _thread = ChatThread.fresh();
      _error = null;
    });
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.role == 'user';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        decoration: BoxDecoration(
          color: mine ? AppColors.kPureBlack : AppColors.kCard,
          borderRadius: BorderRadius.circular(16),
          border: mine ? null : Border.all(color: AppColors.kPrimaryGrey),
        ),
        child: mine
            ? SelectableText(
                m.content,
                style: TextStyle(fontSize: 15, height: 1.4, color: AppColors.kWhite),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (m.content.isNotEmpty) RichReply(m.content),
                  for (final a in m.actions) _actionCard(a),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final empty = _thread.messages.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          empty ? 'AI chat' : _thread.title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Memory & health notes',
            icon: const Icon(Icons.psychology_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newChat,
          ),
          IconButton(
            tooltip: 'Chat history',
            icon: const Icon(Icons.history),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: empty
                  ? ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const SizedBox(height: 24),
                        Icon(Icons.chat_bubble_outline,
                            size: 40, color: AppColors.kgrey),
                        const SizedBox(height: 12),
                        Text(
                          'Ask me about your food, plans or goals.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: AppColors.kBlack),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'I can see your profile, targets and what you logged.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: AppColors.kgrey),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final s in _starters)
                              ActionChip(label: Text(s), onPressed: () => _send(s)),
                          ],
                        ),
                      ],
                    )
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      children: [
                        for (final m in _thread.messages) _bubble(m),
                        if (_sending)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text('Thinking...',
                                    style: TextStyle(color: AppColors.kgrey)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                color: Colors.red.withValues(alpha: .12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(fontSize: 13, color: AppColors.kBlack)),
                    ),
                    TextButton(
                      onPressed: _sending ? null : _ask,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        filled: true,
                        fillColor: AppColors.kCard,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: AppColors.kPrimaryGrey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
