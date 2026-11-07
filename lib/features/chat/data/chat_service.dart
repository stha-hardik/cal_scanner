import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/settings/ai_settings.dart';
import '../../../core/settings/model_chooser.dart';
import '../../memory/data/memory_store.dart';
import 'chat_actions.dart';
import 'chat_context.dart';
import 'chat_store.dart';

/// The AI's answer: text plus any changes it proposes (confirmed by the user).
class ChatReply {
  final String text;
  final List<ChatAction> actions;
  const ChatReply(this.text, this.actions);
}

class ChatService {
  static const _historyLimit = 20;

  static const _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'log_meal',
        'description':
            "Propose adding a meal to the user's food log. The user confirms in the app.",
        'parameters': {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
            'calories': {'type': 'number'},
            'protein': {'type': 'number', 'description': 'grams'},
            'carbs': {'type': 'number', 'description': 'grams'},
            'fat': {'type': 'number', 'description': 'grams'},
            'date': {
              'type': 'string',
              'description': 'YYYY-MM-DD. Leave out for today.',
            },
          },
          'required': ['name', 'calories', 'protein', 'carbs', 'fat'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_goal',
        'description':
            "Propose changing the user's goal, optionally with custom daily targets. The user confirms in the app.",
        'parameters': {
          'type': 'object',
          'properties': {
            'goal': {
              'type': 'string',
              'enum': ['lose_weight', 'maintain', 'gain_weight', 'body_recomposition'],
            },
            'calories': {'type': 'number'},
            'protein': {'type': 'number', 'description': 'grams'},
            'carbs': {'type': 'number', 'description': 'grams'},
            'fat': {'type': 'number', 'description': 'grams'},
          },
          'required': ['goal'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'save_memory',
        'description':
            'Save a lasting fact about the user to memory (a health condition, allergy, food preference, routine or constraint). One short sentence. Not for one-off things or things already in memory.',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string'},
          },
          'required': ['text'],
        },
      },
    },
  ];

  /// What the AI sees for an earlier message, including what happened to its proposals.
  static String _contentFor(ChatMessage m) {
    if (m.role != 'assistant' || m.actions.isEmpty) return m.content;
    final notes = m.actions.map((a) {
      final state = switch (a.status) {
        'done' => a.name == 'save_memory' ? 'saved to memory' : 'confirmed and applied',
        'undone' => 'removed from memory by the user',
        'dismissed' => 'declined by the user',
        _ => 'waiting for the user to confirm',
      };
      return '[Proposed: ${ChatActions.describe(a)} - $state]';
    }).join('\n');
    return m.content.isEmpty ? notes : '${m.content}\n$notes';
  }

  /// Sends the conversation to the AI and returns its reply text.
  static Future<ChatReply> reply(List<ChatMessage> history) async {
    final key = await AiSettings.apiKey();
    if (key.isEmpty) {
      throw Exception('Missing API key. Add it in Settings.');
    }
    final recentUser = history.where((m) => m.role == 'user').toList();
    final recentText = recentUser.length > 3
        ? recentUser.sublist(recentUser.length - 3).map((m) => m.content).join(' . ')
        : recentUser.map((m) => m.content).join(' . ');
    final system = await ChatContext.build(recentUserText: recentText);
    final recent = history.length > _historyLimit
        ? history.sublist(history.length - _historyLimit)
        : history;
    final messages = [
      {'role': 'system', 'content': system},
      for (final m in recent) {'role': m.role, 'content': _contentFor(m)},
    ];

    Future<http.Response> call(String model, [List? msgs]) => http
        .post(
          Uri.parse(AiSettings.endpoint),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': msgs ?? messages,
            'tools': _tools,
            'max_tokens': 1200,
            'temperature': 0.6,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final model = await AiSettings.model();
    var usedModel = model;
    var res = await call(model);

    // Model retired or unavailable: pick another working one and retry once.
    if ((res.statusCode == 400 || res.statusCode == 404) &&
        await AiSettings.autoSwitch()) {
      final replacement = await ModelChooser.findWorkingModel(key, skip: model);
      if (replacement != null) {
        await AiSettings.setModel(replacement);
        usedModel = replacement;
        res = await call(replacement);
      }
    }

    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      String detail = 'HTTP ${res.statusCode}';
      try {
        detail = jsonDecode(body)['error']['message'].toString();
      } catch (_) {}
      throw Exception(detail);
    }
    final first = jsonDecode(body)['choices'][0]['message'] as Map;
    final actions = <ChatAction>[];
    var text = _clean(first['content']);
    final results = await _process(first, actions);

    // The AI saved a memory instead of answering. Let it carry on, so the
    // user's actual question still gets an answer.
    final savedMemory = ((first['tool_calls'] as List?) ?? const [])
        .any((tc) => (tc['function'] as Map?)?['name'] == 'save_memory');
    if (savedMemory && results.isNotEmpty) {
      try {
        final follow = await call(usedModel, [
          ...messages,
          {
            'role': 'assistant',
            'content': first['content'] ?? '',
            'tool_calls': first['tool_calls'],
          },
          ...results,
        ]);
        if (follow.statusCode == 200) {
          final second =
              jsonDecode(utf8.decode(follow.bodyBytes))['choices'][0]['message'] as Map;
          final more = _clean(second['content']);
          await _process(second, actions);
          text = [text, more].where((t) => t.isNotEmpty).join('\n\n');
        }
      } catch (_) {
        // Keep the first answer if the follow-up fails.
      }
    }

    if (text.isEmpty && actions.isEmpty) {
      throw Exception('The AI sent an empty reply. Try again.');
    }
    return ChatReply(text, actions);
  }

  static String _clean(Object? content) => (content ?? '')
      .toString()
      .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
      .trim();

  /// Handles the tool calls in an AI message: memories are saved right away,
  /// meals and goal changes become proposals the user confirms. Returns the
  /// tool results to send back to the AI.
  static Future<List<Map<String, dynamic>>> _process(
    Map msg,
    List<ChatAction> actions,
  ) async {
    final results = <Map<String, dynamic>>[];
    for (final tc in (msg['tool_calls'] as List?) ?? const []) {
      final callId = '${tc['id'] ?? ''}';
      String outcome = 'Could not read this request.';
      try {
        final fn = tc['function'] as Map;
        final name = fn['name'] as String;
        if (!ChatActions.toolNames.contains(name)) {
          results.add({'role': 'tool', 'tool_call_id': callId, 'content': 'Unknown tool.'});
          continue;
        }
        final raw = fn['arguments'];
        final args = raw is String
            ? Map<String, dynamic>.from(jsonDecode(raw) as Map)
            : Map<String, dynamic>.from(raw as Map);
        final id = '${DateTime.now().microsecondsSinceEpoch}_${actions.length}';
        if (name == 'save_memory') {
          // Memories are saved right away; the user can undo in the chat.
          final item = await MemoryStore.add('${args['text'] ?? ''}', source: 'ai');
          if (item == null) {
            outcome = 'Not saved: empty or already in memory.';
          } else {
            actions.add(ChatAction(
              id: id,
              name: name,
              args: {'text': item.text, 'memoryId': item.id},
              status: 'done',
            ));
            outcome = 'Saved to memory.';
          }
        } else if (actions.length < 5) {
          actions.add(ChatAction(id: id, name: name, args: args));
          outcome = 'Shown to the user as a proposal. Waiting for their confirmation.';
        }
      } catch (_) {
        // Ignore a malformed request.
      }
      results.add({'role': 'tool', 'tool_call_id': callId, 'content': outcome});
    }
    return results;
  }
}
