import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_settings.dart';

/// Finds a Groq model that currently accepts images, by asking Groq which
/// models exist and sending a tiny test picture to the likely candidates.
class ModelChooser {
  // 64x64 solid-colour PNG used only to check that a model accepts images.
  static const String _probeImage =
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfMYEY0liH8OITBAtzm7PV1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYBhT7BWl2NbrcAAAAASUVORK5CYII=';

  static const _notChat = [
    'whisper', 'orpheus', 'guard', 'safeguard', 'tts', 'embed', 'allam',
  ];

  static Map<String, String> _headers(String key) => {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      };

  /// All model ids Groq currently offers (throws on network/auth errors).
  static Future<List<String>> listModels(String key) async {
    final r = await http
        .get(Uri.parse(AiSettings.modelsEndpoint), headers: _headers(key))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Groq returned ${r.statusCode}');
    }
    final data = jsonDecode(r.body)['data'] as List;
    return data.map((m) => m['id'].toString()).toList();
  }

  /// True if [model] answers a small image request successfully.
  static Future<bool> probe(String key, String model) async {
    try {
      final r = await http
          .post(
            Uri.parse(AiSettings.endpoint),
            headers: _headers(key),
            body: jsonEncode({
              'model': model,
              'max_tokens': 8,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/png;base64,$_probeImage',
                      },
                    },
                    {'type': 'text', 'text': 'Reply with the word ok.'},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 40));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static int _rank(String id) {
    final s = id.toLowerCase();
    if (s.contains('vision')) return 0;
    if (s.contains('llama-4') || s.contains('scout') || s.contains('maverick')) {
      return 1;
    }
    if (s.contains('qwen')) return 2;
    if (s.contains('gemma') || s.contains('pixtral') || s.contains('llava')) {
      return 3;
    }
    return 4;
  }

  /// Returns the first model that accepts images, or null. [skip] is tried last.
  static Future<String?> findWorkingModel(
    String key, {
    String? skip,
    void Function(String model)? onTrying,
  }) async {
    final all = await listModels(key);
    final candidates = all
        .where((id) => !_notChat.any((bad) => id.toLowerCase().contains(bad)))
        .where((id) => id != skip)
        .toList()
      ..sort((a, b) => _rank(a).compareTo(_rank(b)));
    for (final id in candidates.take(10)) {
      onTrying?.call(id);
      if (await probe(key, id)) return id;
    }
    return null;
  }
}
