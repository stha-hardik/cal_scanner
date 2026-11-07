import 'dart:convert';

import 'package:fpdart/fpdart.dart';

import '../../core/error/failure.dart';
import '../calories/domain/entities/food.dart';
import 'nepali_food_db.dart';

/// Sends the prompt (and photos, base64) to the vision model, returns its text.
typedef VisionCall = Future<Either<Failure, String>> Function(
    String prompt, List<String> base64Images);

/// Looks one food up on the web. Returns {kcal, protein, carbs, fat} per
/// 100 g, or null when nothing reliable was found.
typedef SearchCall = Future<Map<String, double>?> Function(String foodName);

class ScanItem {
  final String name;
  final double grams;
  final Nutrition nutrition;
  final String source; // table | web | AI estimate | note
  final double? count;
  const ScanItem(this.name, this.grams, this.nutrition, this.source, [this.count]);
}

/// The smart scan: AI looks at the photos and lists items with weights,
/// the built-in Nepali table gives trusted nutrition, the web fills gaps,
/// and the AI's own numbers are the last fallback.
class SmartScanner {
  SmartScanner(this.db);
  final NepaliFoodDb db;

  static String cleanNote(String? n) {
    final t = (n ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 300 ? t.substring(0, 300) : t;
  }

  String buildPrompt({
    required double plateCm,
    required double katoriMl,
    required int photoCount,
    required String note,
    Food? previous,
    required bool hasPhoto,
  }) {
    final names = db.foods.map((f) => f.name).join('; ');
    final hints = note.isEmpty
        ? ''
        : db
            .findInText(note)
            .map((n) => '${n.quantity == null ? '' : '${_fmt(n.quantity!)} x '}${n.food.name}')
            .join(', ');
    final b = StringBuffer()
      ..writeln('You are a careful nutrition analyst for Nepali and South Asian food.')
      ..writeln(hasPhoto
          ? 'Identify every separate food or drink item in the ${photoCount > 1 ? 'photos' : 'photo'}, '
              'estimate the weight in grams of what is actually served, and estimate its nutrition.'
          : 'No photo is available. From the description below, list every food or drink item, '
              'estimate the weight in grams of what was eaten, and estimate its nutrition.')
      ..writeln()
      ..writeln('SIZE REFERENCE: the user\'s usual plate is about ${_fmt(plateCm)} cm across and their katori '
          '(small bowl) holds about ${_fmt(katoriMl)} ml. Use plates, bowls, katori, spoons, glasses, hands '
          'and any other visible objects as rulers.');
    if (hasPhoto) {
      b
        ..writeln(photoCount > 1
            ? 'VOLUME: photo 1 is the main (top) view, photo 2 is a second angle. Use the top view for the '
                'area covered and the other view for the height of the pile, then weight = volume x density '
                '(cooked rice about 0.8 g/ml, dal 1.0, curry 0.9, fried snacks 0.4).'
            : 'VOLUME: from the one photo, estimate the area covered and the height of the pile, then '
                'weight = volume x density (cooked rice about 0.8 g/ml, dal 1.0, curry 0.9, fried snacks 0.4). '
                'Be conservative when the depth is unclear.')
        ..writeln('Count countable items (momo, roti, sel roti, gwaramari, eggs, pieces) and give the count.');
    }
    b
      ..writeln()
      ..writeln('KNOWN FOODS (use the exact name in "match" when an item is one of these, else null): $names')
      ..writeln('Nepali terms may be spelled many ways (gualamari = gwaramari, sael roti = sel roti).');
    if (note.isNotEmpty) {
      b
        ..writeln()
        ..writeln('USER NOTE (treat counts and details as true): "$note"');
      if (hints.isNotEmpty) b.writeln('Foods recognised in the note: $hints.');
    }
    if (previous != null) {
      b
        ..writeln()
        ..writeln('PREVIOUS ESTIMATE (the user is correcting it): "${previous.name}", '
            '${previous.calories.round()} kcal. Apply the user note to fix it.');
    }
    b
      ..writeln()
      ..writeln('Reply with JSON only, no markdown, exactly:')
      ..writeln('{"items":[{"name":"food name","match":"exact known name or null","grams":150,"count":null,'
          '"kcal":200,"protein":5,"carbs":30,"fat":6,"confidence":0.7}],"notes":"one short sentence"}')
      ..writeln('kcal/protein/carbs/fat are your own estimate for the WHOLE item portion (used as a fallback).');
    return b.toString();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  Future<Either<Failure, Food>> run({
    required VisionCall vision,
    SearchCall? search,
    required List<String> base64Images,
    String? note,
    Food? previous,
    required double plateCm,
    required double katoriMl,
  }) async {
    final n = cleanNote(note);
    final prompt = buildPrompt(
      plateCm: plateCm,
      katoriMl: katoriMl,
      photoCount: base64Images.length,
      note: n,
      previous: previous,
      hasPhoto: base64Images.isNotEmpty,
    );
    final reply = await vision(prompt, base64Images);
    final text = reply.fold((f) => null, (t) => t);
    if (text == null) return left(reply.fold((f) => f, (_) => const NetworkFailure('No reply')));

    final parsed = _parseJson(text);
    if (parsed == null) {
      return left(NetworkFailure('No JSON found in response', cause: text));
    }
    final raw = _rawItems(parsed);
    if (raw == null) {
      return left(NetworkFailure('Failed to parse API response', cause: text));
    }

    final noteItems = n.isEmpty ? <NoteItem>[] : db.findInText(n);
    final items = <ScanItem>[];
    final unknown = <int>[]; // indexes of items still needing numbers
    final rawUnknown = <Map<String, dynamic>>[];

    for (final r in raw) {
      final name = (r['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      double grams = _num(r['grams']) ?? 0;
      final count = _num(r['count']);
      if (r['_single'] == true) {
        // Old one-food reply: the numbers are for the whole meal, keep them as they are.
        items.add(ScanItem(name, 100,
            Nutrition(_num(r['kcal']) ?? 0, _num(r['protein']) ?? 0, _num(r['carbs']) ?? 0, _num(r['fat']) ?? 0),
            'AI estimate'));
        continue;
      }
      final matchName = (r['match'] ?? '').toString();
      var m = matchName.isNotEmpty && matchName.toLowerCase() != 'null' ? db.best(matchName, minScore: 0.8) : null;
      m ??= db.best(name);
      if (m != null) {
        final f = m.food;
        NoteItem? ni;
        for (final x in noteItems) {
          if (x.food.id == f.id) ni = x;
        }
        // Counting beats guessing weight: a typed quantity wins, then the AI's count.
        if (f.perPiece && ni?.quantity != null) {
          grams = ni!.quantity! * f.servingGrams;
        } else if (f.perPiece && count != null && count > 0) {
          grams = count * f.servingGrams;
        } else if (grams <= 0) {
          grams = f.servingGrams;
        }
        grams = grams.clamp(1, 3000).toDouble();
        items.add(ScanItem(f.name, grams, f.forGrams(grams), 'table', f.perPiece ? (ni?.quantity ?? count) : null));
        continue;
      }
      if (grams <= 0) grams = 100;
      grams = grams.clamp(1, 3000).toDouble();
      final ai = Nutrition(
        _num(r['kcal']) ?? 0,
        _num(r['protein']) ?? 0,
        _num(r['carbs']) ?? 0,
        _num(r['fat']) ?? 0,
      );
      items.add(ScanItem(name, grams, ai, 'AI estimate', count));
      unknown.add(items.length - 1);
      rawUnknown.add(r);
    }

    // Foods typed in the note that the AI did not list (a drink out of frame, for example).
    for (final ni in noteItems) {
      if (items.any((i) => i.name == ni.food.name)) continue;
      final f = ni.food;
      final grams = f.perPiece ? (ni.quantity ?? 1) * f.servingGrams : f.servingGrams * (ni.quantity ?? 1);
      items.add(ScanItem(f.name, grams, f.forGrams(grams), 'note', f.perPiece ? ni.quantity : null));
    }

    // Web lookup for the foods that are not in the table (max 3 to save tokens).
    if (search != null) {
      var looked = 0;
      for (final idx in unknown) {
        if (looked >= 3) break;
        final it = items[idx];
        looked++;
        Map<String, double>? per100;
        try {
          per100 = await search(it.name);
        } catch (_) {
          per100 = null;
        }
        if (per100 != null && _plausible(per100)) {
          final nutri = Nutrition(per100['kcal']!, per100['protein']!, per100['carbs']!, per100['fat']!)
              .scale(it.grams / 100);
          items[idx] = ScanItem(it.name, it.grams, nutri, 'web', it.count);
        }
      }
    }

    if (items.isEmpty) {
      return left(const NetworkFailure('Could not recognise any food in this meal.'));
    }
    var total = const Nutrition(0, 0, 0, 0);
    for (final i in items) {
      total = total + i.nutrition;
    }
    if (total.kcal <= 0 || total.kcal > 6000) {
      return left(NetworkFailure('Unrealistic result (${total.kcal.round()} kcal)', cause: text));
    }

    final sorted = [...items]..sort((a, b) => b.nutrition.kcal.compareTo(a.nutrition.kcal));
    final title = sorted.length <= 3
        ? sorted.map((i) => i.name).join(' + ')
        : '${sorted.take(2).map((i) => i.name).join(' + ')} + ${sorted.length - 2} more';
    final details = items.map((i) {
      final c = i.count == null ? '' : ' x${_fmt(i.count!)}';
      final tag = switch (i.source) {
        'table' => 'Nepali food table',
        'web' => 'web search',
        'note' => 'from your note',
        _ => 'AI estimate',
      };
      return '${i.name}$c: ${i.grams.round()} g, ${i.nutrition.kcal.round()} kcal ($tag)';
    }).join('\n');

    return right(Food(
      id: previous?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: title,
      calories: total.kcal.roundToDouble(),
      protein: double.parse(total.protein.toStringAsFixed(1)),
      carbs: double.parse(total.carbs.toStringAsFixed(1)),
      fat: double.parse(total.fat.toStringAsFixed(1)),
      quantity: 100,
      timestamp: previous?.timestamp ?? DateTime.now(),
      note: previous?.note,
      photoPath: previous?.photoPath,
      details: details,
    ));
  }

  static bool _plausible(Map<String, double> m) {
    final k = m['kcal'], p = m['protein'], c = m['carbs'], f = m['fat'];
    if (k == null || p == null || c == null || f == null) return false;
    if (k <= 0 || k > 900 || p < 0 || c < 0 || f < 0) return false;
    final macro = p * 4 + c * 4 + f * 9;
    return (k - macro).abs() <= 80 || (macro > 0 && (k / macro) > 0.6 && (k / macro) < 1.5);
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), ''));
    return null;
  }

  static Map<String, dynamic>? _parseJson(String text) {
    final cleaned = text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '');
    final m = RegExp(r'\{.*\}', dotAll: true).firstMatch(cleaned);
    if (m == null) return null;
    try {
      final d = jsonDecode(m.group(0)!);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// Accepts the new {"items":[...]} shape and the old single-food shape.
  static List<Map<String, dynamic>>? _rawItems(Map<String, dynamic> j) {
    final items = j['items'];
    if (items is List) {
      return items.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (j['name'] is String && j['calories'] is num) {
      return [
        {
          'name': j['name'],
          'grams': 100,
          'kcal': j['calories'],
          'protein': j['protein'],
          'carbs': j['carbs'],
          'fat': j['fat'],
          'match': null,
          '_single': true,
        }
      ];
    }
    return null;
  }
}
