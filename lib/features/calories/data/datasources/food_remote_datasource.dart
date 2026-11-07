import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/settings/ai_settings.dart';
import '../../../../core/settings/model_chooser.dart';
import '../../../nepali_food/nepali_food_db.dart';
import '../../../nepali_food/smart_scanner.dart';
import '../../domain/entities/food.dart';

class FoodRemoteDataSource {
  final ApiService _api;
  FoodRemoteDataSource(this._api);

  /// Photo(s) + optional note -> one meal made of recognised items.
  /// [moreImages] is an optional second angle (side view).
  Future<Either<Failure, Food>> detectFoodAndCalories(
    File imageFile, {
    String? note,
    List<File> moreImages = const [],
  }) async {
    try {
      if (!imageFile.existsSync()) {
        return left(CacheFailure('File not found', cause: imageFile.path));
      }
      final images = <String>[
        base64Encode(await imageFile.readAsBytes()),
        for (final f in moreImages.take(1))
          if (f.existsSync()) base64Encode(await f.readAsBytes()),
      ];
      return await _run(images: images, note: note);
    } catch (e) {
      return left(NetworkFailure('Failed to detect food', cause: e));
    }
  }

  /// Corrects an earlier estimate using the user's note, with the photo when
  /// it still exists, otherwise from the text alone.
  Future<Either<Failure, Food>> reestimate(Food current, String note, {File? image}) async {
    try {
      final hasPhoto = image != null && image.existsSync();
      final images = hasPhoto ? [base64Encode(await image.readAsBytes())] : <String>[];
      final fullNote = [
        if (SmartScanner.cleanNote(note).isNotEmpty) SmartScanner.cleanNote(note),
        if (!hasPhoto) 'Meal logged earlier: ${current.name}. Details: ${(current.details ?? '').replaceAll('\n', '; ')}',
      ].join(' | ');
      final r = await _run(images: images, note: fullNote, previous: current);
      return r.map((f) => f.copyWith(note: SmartScanner.cleanNote(note)));
    } catch (e) {
      return left(NetworkFailure('Failed to update the estimate', cause: e));
    }
  }

  Future<Either<Failure, Food>> _run({
    required List<String> images,
    String? note,
    Food? previous,
  }) async {
    final apiKey = await AiSettings.apiKey();
    if (apiKey.isEmpty) {
      return left(const NetworkFailure('Missing API key. Add it in AI settings.'));
    }
    final db = await NepaliFoodDb.load();
    final web = await AiSettings.webSearch();
    return await SmartScanner(db).run(
      vision: (prompt, imgs) => _vision(apiKey, prompt, imgs),
      search: web ? (name) => _webLookup(apiKey, name) : null,
      base64Images: images,
      note: note,
      previous: previous,
      plateCm: await AiSettings.plateCm(),
      katoriMl: await AiSettings.katoriMl(),
    );
  }

  /// One vision/text call, switching to another model if the saved one was retired.
  Future<Either<Failure, String>> _vision(String apiKey, String prompt, List<String> images) async {
    final model = await AiSettings.model();
    var response = await _request(apiKey, model, prompt, images);
    if (response.isLeft() && _looksLikeModelProblem(response) && await AiSettings.autoSwitch()) {
      final replacement = await ModelChooser.findWorkingModel(apiKey, skip: model);
      if (replacement != null) {
        await AiSettings.setModel(replacement);
        response = await _request(apiKey, replacement, prompt, images);
      }
    }
    return response.flatMap((data) {
      final output = data['choices']?[0]?['message']?['content'];
      if (output is! String || output.trim().isEmpty) {
        return left(NetworkFailure('Invalid API response', cause: data));
      }
      return right(output);
    });
  }

  Future<Either<Failure, Map<String, dynamic>>> _request(
    String apiKey,
    String model,
    String prompt,
    List<String> images,
  ) {
    return _api.postJson(
      Uri.parse(AiSettings.endpoint),
      headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
      body: {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': images.isEmpty
                ? prompt
                : [
                    for (final b in images)
                      {
                        'type': 'image_url',
                        'image_url': {'url': 'data:image/jpeg;base64,$b'},
                      },
                    {'type': 'text', 'text': prompt},
                  ],
          },
        ],
        'max_tokens': 1500,
      },
    );
  }

  /// Web lookup with Groq's built-in browser search on the bigger gpt-oss model.
  /// Returns per-100 g values, or null if it fails (the AI estimate is used then).
  Future<Map<String, double>?> _webLookup(String apiKey, String foodName) async {
    try {
      final model = await AiSettings.searchModel();
      final prompt =
          'Find reliable nutrition facts per 100 g for this food, as eaten in Nepal or South Asia if relevant: '
          '"$foodName". Reply with JSON only: '
          '{"kcal": 250, "protein": 5, "carbs": 40, "fat": 8}';
      final r = await _api
          .postJson(
            Uri.parse(AiSettings.endpoint),
            headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'},
            body: {
              'model': model,
              'reasoning_effort': 'low',
              'tool_choice': 'required',
              'tools': [
                {'type': 'browser_search'}
              ],
              'max_completion_tokens': 1500,
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            },
          )
          .timeout(const Duration(seconds: 45));
      return r.fold((_) => null, (data) {
        final out = data['choices']?[0]?['message']?['content'];
        if (out is! String) return null;
        final m = RegExp(r'\{[^{}]*\}', dotAll: true).firstMatch(out);
        if (m == null) return null;
        final j = jsonDecode(m.group(0)!);
        if (j is! Map) return null;
        double? n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');
        final k = n(j['kcal'] ?? j['calories']);
        final p = n(j['protein']);
        final c = n(j['carbs']);
        final f = n(j['fat']);
        if (k == null || p == null || c == null || f == null) return null;
        return {'kcal': k, 'protein': p, 'carbs': c, 'fat': f};
      });
    } catch (_) {
      return null;
    }
  }

  /// 400/404 errors that mention the model (retired, unknown, no image support).
  bool _looksLikeModelProblem(Either<Failure, Map<String, dynamic>> r) {
    return r.fold((f) {
      final msg = f.message;
      final cause = (f.cause ?? '').toString().toLowerCase();
      final badStatus = msg.contains('400') || msg.contains('404');
      return badStatus &&
          (cause.contains('model') || cause.contains('decommission') || cause.contains('image'));
    }, (_) => false);
  }
}
