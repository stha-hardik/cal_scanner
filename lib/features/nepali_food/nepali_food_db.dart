import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Nutrition for one portion of a food.
class Nutrition {
  final double kcal, protein, carbs, fat;
  const Nutrition(this.kcal, this.protein, this.carbs, this.fat);

  Nutrition operator +(Nutrition o) =>
      Nutrition(kcal + o.kcal, protein + o.protein, carbs + o.carbs, fat + o.fat);
  Nutrition scale(double x) => Nutrition(kcal * x, protein * x, carbs * x, fat * x);
}

class NepaliFood {
  final String id, name, nep, category, servingLabel;

  /// True when the serving is one countable piece (1 sel roti, 1 momo, 1 egg).
  final bool perPiece;
  final List<String> aliases;
  final double kcal100, protein100, carbs100, fat100, servingGrams;

  const NepaliFood({
    required this.id,
    required this.name,
    required this.nep,
    required this.category,
    required this.servingLabel,
    required this.aliases,
    required this.kcal100,
    required this.protein100,
    required this.carbs100,
    required this.fat100,
    required this.servingGrams,
    this.perPiece = false,
  });

  factory NepaliFood.fromJson(Map<String, dynamic> j) {
    final p = j['per100'] as Map<String, dynamic>;
    final s = j['serving'] as Map<String, dynamic>;
    return NepaliFood(
      id: j['id'] as String,
      name: j['name'] as String,
      nep: (j['nep'] as String?) ?? '',
      category: (j['cat'] as String?) ?? '',
      servingLabel: s['label'] as String,
      aliases: List<String>.from(j['aliases'] as List),
      kcal100: (p['kcal'] as num).toDouble(),
      protein100: (p['p'] as num).toDouble(),
      carbs100: (p['c'] as num).toDouble(),
      fat100: (p['f'] as num).toDouble(),
      servingGrams: (s['g'] as num).toDouble(),
      perPiece: (j['piece'] as bool?) ?? false,
    );
  }

  Nutrition forGrams(double grams) =>
      Nutrition(kcal100, protein100, carbs100, fat100).scale(grams / 100);
}

class FoodMatch {
  final NepaliFood food;
  final double score; // 0..1
  const FoodMatch(this.food, this.score);
}

/// The built-in table of Nepali (and common South Asian / street) foods,
/// with forgiving name matching for Roman-Nepali spellings.
class NepaliFoodDb {
  NepaliFoodDb._(this.foods) {
    for (final f in foods) {
      final names = <String>{f.name, ...f.aliases};
      for (final n in names) {
        final k = phoneticKey(n);
        if (k.isNotEmpty) _keys.add(_Entry(k, f));
      }
    }
  }

  final List<NepaliFood> foods;
  final List<_Entry> _keys = [];

  static NepaliFoodDb? _instance;

  static Future<NepaliFoodDb> load() async {
    final cached = _instance;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString('assets/data/nepali_foods.json');
    return _instance = fromJsonString(raw);
  }

  static NepaliFoodDb fromJsonString(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final list = (data['foods'] as List)
        .map((e) => NepaliFood.fromJson(e as Map<String, dynamic>))
        .toList();
    return NepaliFoodDb._(list);
  }

  /// Collapses the many ways Nepali words are typed in English letters
  /// (gwaramari / gualamari, sel roti / sael rotti, dhido / dido) to one key.
  static String phoneticKey(String input) {
    var s = input.toLowerCase();
    s = s.replaceAll(RegExp(r'[^a-z]'), '');
    if (s.isEmpty) return '';
    const subs = <String, String>{
      'ua': 'wa', 'ue': 'we', 'ui': 'wi',
      'ph': 'f', 'sh': 's', 'ch': 'c', 'kh': 'k', 'gh': 'g', 'bh': 'b',
      'dh': 'd', 'jh': 'j', 'th': 't',
      'oo': 'u', 'ou': 'u', 'ee': 'i', 'ii': 'i', 'aa': 'a',
      'ae': 'e', 'ai': 'e', 'ei': 'e', 'ey': 'e', 'ay': 'e',
      'w': 'v', 'z': 'j', 'q': 'k', 'x': 'ks', 'c': 'k', 'l': 'r', 'y': 'i',
    };
    // multi-letter first
    for (final e in subs.entries.where((e) => e.key.length == 2)) {
      s = s.replaceAll(e.key, e.value);
    }
    for (final e in subs.entries.where((e) => e.key.length == 1)) {
      s = s.replaceAll(e.key, e.value);
    }
    s = s.replaceAll('h', '');
    s = s.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
    return s;
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static double _similarity(String a, String b) {
    final m = a.length > b.length ? a.length : b.length;
    if (m == 0) return 0;
    return 1 - _lev(a, b) / m;
  }

  /// Best matches for one food name, best first.
  List<FoodMatch> search(String query, {int limit = 3, double minScore = 0.78}) {
    final k = phoneticKey(query);
    if (k.isEmpty) return const [];
    final best = <String, FoodMatch>{};
    for (final e in _keys) {
      var score = _similarity(k, e.key);
      // short keys are risky for fuzzy matching: require exact
      if (e.key.length <= 3 && k != e.key) score = 0;
      if (score >= minScore) {
        final prev = best[e.food.id];
        if (prev == null || score > prev.score) best[e.food.id] = FoodMatch(e.food, score);
      }
    }
    final list = best.values.toList()..sort((a, b) => b.score.compareTo(a.score));
    return list.take(limit).toList();
  }

  FoodMatch? best(String query, {double minScore = 0.78}) {
    final r = search(query, limit: 1, minScore: minScore);
    return r.isEmpty ? null : r.first;
  }

  /// Finds known foods inside a free-text note like
  /// "2 sel roti and gualamari with chiya". Returns each food once, with the
  /// quantity written just before it when there is one.
  List<NoteItem> findInText(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9ऀ-ॿ\s]"), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final found = <String, NoteItem>{};
    var i = 0;
    while (i < words.length) {
      if (_qty(words[i]) != null && i + 1 < words.length) {
        i++; // a count like "2" belongs to the food that follows it
        continue;
      }
      FoodMatch? hit;
      var used = 1;
      for (final n in [3, 2, 1]) {
        if (i + n > words.length) continue;
        final phrase = words.sublist(i, i + n).join(' ');
        if (n == 1 && RegExp(r'^\d+$').hasMatch(phrase)) continue;
        final m = best(phrase, minScore: n == 1 ? 0.84 : 0.82);
        if (m != null) {
          hit = m;
          used = n;
          break;
        }
      }
      if (hit != null) {
        double? qty;
        if (i > 0) qty = _qty(words[i - 1]);
        found.putIfAbsent(hit.food.id, () => NoteItem(hit!.food, qty));
        i += used;
      } else {
        i++;
      }
    }
    return found.values.toList();
  }

  static double? _qty(String w) {
    final n = double.tryParse(w);
    if (n != null && n > 0 && n <= 50) return n;
    const words = {
      'one': 1, 'ek': 1, 'a': 1, 'two': 2, 'dui': 2, 'three': 3, 'tin': 3,
      'four': 4, 'char': 4, 'five': 5, 'panch': 5, 'six': 6,
      'half': 0.5, 'aadha': 0.5,
    };
    return words[w]?.toDouble();
  }

  /// Short reference list for the AI: name, Nepali, per-100 g and a serving.
  String promptTable() {
    final b = StringBuffer();
    for (final f in foods) {
      final serv = (f.kcal100 * f.servingGrams / 100).round();
      b.writeln('${f.name}'
          '${f.nep.isEmpty ? '' : ' (${f.nep})'}'
          ': ${f.kcal100.round()} kcal/100g, P${f.protein100.round()} C${f.carbs100.round()} F${f.fat100.round()};'
          ' typical ${f.servingLabel} = ${f.servingGrams.round()} g = $serv kcal');
    }
    return b.toString();
  }
}

class NoteItem {
  final NepaliFood food;
  final double? quantity;
  const NoteItem(this.food, this.quantity);
}

class _Entry {
  final String key;
  final NepaliFood food;
  _Entry(this.key, this.food);
}
