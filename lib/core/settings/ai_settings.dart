import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-editable AI settings. Stored on the phone, so a model or key change
/// never needs a new APK. Falls back to the key bundled in `.env`.
class AiSettings {
  static const String endpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String modelsEndpoint = 'https://api.groq.com/openai/v1/models';
  static const String defaultModel = 'qwen/qwen3.8-27b';

  static const _kKey = 'ai_api_key';
  static const _kModel = 'ai_model';
  static const _kAuto = 'ai_auto_switch';

  static Future<String> apiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kKey)?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return (dotenv.env['GROK_API_KEY'] ?? '').trim();
  }

  static Future<String> model() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kModel)?.trim();
    return (saved == null || saved.isEmpty) ? defaultModel : saved;
  }

  static Future<bool> autoSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAuto) ?? true;
  }

  static Future<void> setApiKey(String v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v.trim().isEmpty) {
      await prefs.remove(_kKey);
    } else {
      await prefs.setString(_kKey, v.trim());
    }
  }

  static Future<void> setModel(String v) async {
    final prefs = await SharedPreferences.getInstance();
    if (v.trim().isEmpty) {
      await prefs.remove(_kModel);
    } else {
      await prefs.setString(_kModel, v.trim());
    }
  }

  static Future<void> setAutoSwitch(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuto, v);
  }
}
