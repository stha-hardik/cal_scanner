import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/network/api_service.dart';
import '../../../../core/settings/ai_settings.dart';
import '../../../../core/settings/model_chooser.dart';
import '../../domain/entities/food.dart';

class FoodRemoteDataSource {
  final ApiService _api;
  FoodRemoteDataSource(this._api);


  static String _cleanNote(String? n) {
    final t = (n ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 300 ? t.substring(0, 300) : t;
  }

  static const _format =
      'Return JSON only, no markdown, no explanation, in this exact format: '
      '{"name": "food name", "calories": 100, "protein": 10, "carbs": 20, "fat": 5}';

  Future<Either<Failure, Food>> detectFoodAndCalories(File imageFile, {String? note}) async {
    try {
      if (!imageFile.existsSync()) {
        return left(CacheFailure('File not found', cause: imageFile.path));
      }
      final apiKey = await AiSettings.apiKey();
      if (apiKey.isEmpty) {
        return left(
          const NetworkFailure('Missing API key. Add it in AI settings.'),
        );
      }

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final model = await AiSettings.model();
      final prompt = _scanPrompt(note);
      var response = await _request(apiKey, model, prompt, base64Image);

      // If the model was retired or does not accept images, find another one.
      if (response.isLeft() &&
          _looksLikeModelProblem(response) &&
          await AiSettings.autoSwitch()) {
        final replacement = await ModelChooser.findWorkingModel(
          apiKey,
          skip: model,
        );
        if (replacement != null) {
          await AiSettings.setModel(replacement);
          response = await _request(apiKey, replacement, prompt, base64Image);
        }
      }

      return response.flatMap(_parseFood);
    } catch (e) {
      return left(NetworkFailure('Failed to detect food', cause: e));
    }
  }

  Either<Failure, Food> _parseFood(Map<String, dynamic> data) {

      try {
        final output = data['choices']?[0]?['message']?['content'];
        if (output is! String) {
          return left(NetworkFailure('Invalid API response', cause: data));
        }

        final match = RegExp(r'\{.*\}', dotAll: true).firstMatch(output);
        if (match == null) {
          return left(NetworkFailure('No JSON found in response', cause: output));
        }

        final foodData = jsonDecode(match.group(0)!);
        if (foodData is! Map) {
          return left(NetworkFailure('Invalid JSON in response', cause: output));
        }

        return right(
          Food(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: foodData['name'] as String,
            calories: (foodData['calories'] as num).toDouble(),
            protein: (foodData['protein'] as num).toDouble(),
            carbs: (foodData['carbs'] as num).toDouble(),
            fat: (foodData['fat'] as num).toDouble(),
            quantity: 100.0,
            timestamp: DateTime.now(),
          ),
        );
      } catch (e) {
        return left(NetworkFailure('Failed to parse API response', cause: e));
      }
    
  }

  String _scanPrompt(String? note) {
    final n = _cleanNote(note);
    return 'Analyze this image and identify the food. '
        'Estimate its calories, protein, carbs, and fat. '
        '${n.isEmpty ? '' : 'The user added this note about the meal; use it (portion size, ingredients, cooking method): "$n". '}'
        '$_format';
  }

  /// Corrects an earlier estimate using the user's note, with the photo when
  /// it still exists, otherwise from the text alone.
  Future<Either<Failure, Food>> reestimate(Food current, String note, {File? image}) async {
    try {
      final apiKey = await AiSettings.apiKey();
      if (apiKey.isEmpty) {
        return left(const NetworkFailure('Missing API key. Add it in AI settings.'));
      }
      final n = _cleanNote(note);
      final prev = 'Previous estimate: "${current.name}", ${current.calories.round()} kcal, '
          'protein ${current.protein.round()} g, carbs ${current.carbs.round()} g, fat ${current.fat.round()} g.';
      final hasPhoto = image != null && image.existsSync();
      final prompt = hasPhoto
          ? 'Look at this food photo again. $prev The user corrected or added: "$n". '
              'Re-estimate calories, protein, carbs and fat for the whole meal, taking the note into account. $_format'
          : 'A meal was logged earlier (no photo available now). $prev The user corrected or added: "$n". '
              'Re-estimate calories, protein, carbs and fat for the whole meal, taking the note into account. $_format';
      final b64 = hasPhoto ? base64Encode(await image.readAsBytes()) : null;

      final model = await AiSettings.model();
      var response = await _request(apiKey, model, prompt, b64);
      if (response.isLeft() && _looksLikeModelProblem(response) && await AiSettings.autoSwitch()) {
        final replacement = await ModelChooser.findWorkingModel(apiKey, skip: model);
        if (replacement != null) {
          await AiSettings.setModel(replacement);
          response = await _request(apiKey, replacement, prompt, b64);
        }
      }
      return response.flatMap(_parseFood).map((f) => current.copyWith(
            name: f.name,
            calories: f.calories,
            protein: f.protein,
            carbs: f.carbs,
            fat: f.fat,
            note: n,
          ));
    } catch (e) {
      return left(NetworkFailure('Failed to update the estimate', cause: e));
    }
  }

  Future<Either<Failure, Map<String, dynamic>>> _request(
    String apiKey,
    String model,
    String prompt,
    String? base64Image,
  ) {
    return _api.postJson(
      Uri.parse(AiSettings.endpoint),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': base64Image == null
                ? prompt
                : [
                    {
                      'type': 'image_url',
                      'image_url': {'url': 'data:image/jpeg;base64,$base64Image'},
                    },
                    {'type': 'text', 'text': prompt},
                  ],
          },
        ],
        'max_tokens': 600,
      },
    );
  }

  /// 400/404 errors that mention the model (retired, unknown, no image support).
  bool _looksLikeModelProblem(Either<Failure, Map<String, dynamic>> r) {
    return r.fold((f) {
      final msg = f.message;
      final cause = (f.cause ?? '').toString().toLowerCase();
      final badStatus = msg.contains('400') || msg.contains('404');
      return badStatus &&
          (cause.contains('model') ||
              cause.contains('decommission') ||
              cause.contains('image'));
    }, (_) => false);
  }
}
