import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class MemoryItem {
  final String id;
  String text;
  final String source; // 'you' or 'ai'
  final DateTime created;

  MemoryItem({
    required this.id,
    required this.text,
    required this.source,
    required this.created,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'source': source,
        'created': created.toIso8601String(),
      };

  factory MemoryItem.fromJson(Map<String, dynamic> j) => MemoryItem(
        id: j['id'] as String,
        text: j['text'] as String,
        source: j['source'] as String? ?? 'you',
        created: DateTime.parse(j['created'] as String),
      );
}

/// Health notes and memories. Saved on the phone and sent to the AI with
/// every chat message.
class MemoryStore {
  static const _kItems = 'ai_memory_items';
  static const _kHealth = 'ai_health_notes';
  static const maxItems = 100;
  static const maxTextLength = 300;
  static const maxHealthLength = 2000;

  static Future<List<MemoryItem>> items() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kItems);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => MemoryItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      list.sort((a, b) => b.created.compareTo(a.created));
      return list;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<MemoryItem> list) async {
    final prefs = await SharedPreferences.getInstance();
    list.sort((a, b) => b.created.compareTo(a.created));
    await prefs.setString(
      _kItems,
      jsonEncode(list.take(maxItems).map((m) => m.toJson()).toList()),
    );
  }

  /// Adds a memory. Returns null if it is empty or already saved.
  static Future<MemoryItem?> add(String text, {String source = 'you'}) async {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (t.length > maxTextLength) t = t.substring(0, maxTextLength);
    final list = await items();
    if (list.any((m) => m.text.toLowerCase() == t.toLowerCase())) return null;
    final item = MemoryItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: t,
      source: source,
      created: DateTime.now(),
    );
    list.add(item);
    await _write(list);
    return item;
  }

  static Future<void> update(String id, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final list = await items();
    for (final m in list) {
      if (m.id == id) {
        m.text = t.length > maxTextLength ? t.substring(0, maxTextLength) : t;
      }
    }
    await _write(list);
  }

  static Future<void> remove(String id) async {
    final list = await items();
    list.removeWhere((m) => m.id == id);
    await _write(list);
  }

  static Future<String> healthNotes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kHealth) ?? '';
  }

  static Future<void> setHealthNotes(String v) async {
    final prefs = await SharedPreferences.getInstance();
    final t = v.trim();
    if (t.isEmpty) {
      await prefs.remove(_kHealth);
    } else {
      await prefs.setString(
        _kHealth,
        t.length > maxHealthLength ? t.substring(0, maxHealthLength) : t,
      );
    }
  }

  /// Text added to the AI's instructions on every message.
  static Future<String> promptBlock() async {
    final health = (await healthNotes()).trim();
    final list = await items();
    final b = StringBuffer();
    b
      ..writeln()
      ..writeln('HEALTH NOTES FROM THE USER (always take these into account)');
    b.writeln(health.isEmpty ? '- none provided' : health);
    b
      ..writeln()
      ..writeln('MEMORY (things to remember about the user)');
    if (list.isEmpty) {
      b.writeln('- nothing saved yet');
    } else {
      var used = 0;
      for (final m in list) {
        if (used > 3000) break; // keep the prompt a sensible size
        final line = '- ${m.text}';
        b.writeln(line);
        used += line.length;
      }
    }
    return b.toString();
  }
}
