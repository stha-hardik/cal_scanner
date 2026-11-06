import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A change the AI proposed (log a meal, change the goal). Applied only after
/// the user taps Confirm.
class ChatAction {
  final String id;
  final String name; // 'log_meal' or 'set_goal'
  final Map<String, dynamic> args;
  String status; // pending, done, dismissed
  String? result;

  ChatAction({
    required this.id,
    required this.name,
    required this.args,
    this.status = 'pending',
    this.result,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'args': args,
        'status': status,
        'result': result,
      };

  factory ChatAction.fromJson(Map<String, dynamic> j) => ChatAction(
        id: j['id'] as String,
        name: j['name'] as String,
        args: Map<String, dynamic>.from(j['args'] as Map),
        status: j['status'] as String? ?? 'pending',
        result: j['result'] as String?,
      );
}

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime time;
  final List<ChatAction> actions;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.time,
    this.actions = const [],
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'time': time.toIso8601String(),
        'actions': actions.map((a) => a.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: j['role'] as String,
        content: j['content'] as String,
        time: DateTime.parse(j['time'] as String),
        actions: ((j['actions'] as List?) ?? const [])
            .map((a) => ChatAction.fromJson(Map<String, dynamic>.from(a)))
            .toList(),
      );
}

class ChatThread {
  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updated;

  ChatThread({
    required this.id,
    required this.title,
    required this.messages,
    required this.updated,
  });

  factory ChatThread.fresh() => ChatThread(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'New chat',
        messages: [],
        updated: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory ChatThread.fromJson(Map<String, dynamic> j) => ChatThread(
        id: j['id'] as String,
        title: j['title'] as String,
        updated: DateTime.parse(j['updated'] as String),
        messages: (j['messages'] as List)
            .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// Chat history, saved on the phone.
class ChatStore {
  static const _key = 'ai_chats';
  static const _maxThreads = 100;

  static Future<List<ChatThread>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => ChatThread.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => b.updated.compareTo(a.updated));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<ChatThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    threads.sort((a, b) => b.updated.compareTo(a.updated));
    final kept = threads.take(_maxThreads).toList();
    await prefs.setString(_key, jsonEncode(kept.map((t) => t.toJson()).toList()));
  }

  static Future<void> save(ChatThread thread) async {
    final threads = await all();
    threads.removeWhere((t) => t.id == thread.id);
    threads.add(thread);
    await _write(threads);
  }

  static Future<void> delete(String id) async {
    final threads = await all();
    threads.removeWhere((t) => t.id == id);
    await _write(threads);
  }
}
