import 'dart:io';

import 'package:cal_scanner/features/nepali_food/nepali_food_db.dart';
import 'package:cal_scanner/features/nepali_food/smart_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';

void main() {
  late SmartScanner s;
  setUpAll(() => s = SmartScanner(NepaliFoodDb.fromJsonString(File('assets/data/nepali_foods.json').readAsStringSync())));

  Future<dynamic> go(String reply, {String? note, int photos = 1, Future<Map<String, double>?> Function(String)? search, List<String>? prompts}) {
    return s.run(
      vision: (p, imgs) async {
        prompts?.add(p);
        return right(reply);
      },
      search: search,
      base64Images: List.filled(photos, 'x'),
      note: note,
      plateCm: 26,
      katoriMl: 150,
    );
  }

  test('prompt carries plate/katori ruler and photo count', () {
    final p = s.buildPrompt(plateCm: 26, katoriMl: 150, photoCount: 2, note: '', previous: null, hasPhoto: true);
    expect(p, contains('26'));
    expect(p, contains('150'));
    expect(p.toLowerCase(), contains('katori'));
  });

  test('table numbers beat AI numbers; note quantity overrides', () async {
    const reply = '{"items":[{"name":"sel roti","match":"sel roti","grams":80,"count":1,"kcal":50,"confidence":0.8}]}';
    final r = await go(reply, note: '2 sel roti');
    final food = r.getOrElse((_) => throw 'fail');
    expect(food.calories, closeTo(464, 15)); // 2 x 80 g x 2.9
  });

  test('misspelled item in the reply is recognised', () async {
    const reply = '{"items":[{"name":"gualamari","grams":100,"kcal":1,"confidence":0.7}]}';
    final food = (await go(reply)).getOrElse((_) => throw 'fail');
    expect(food.calories, closeTo(330, 20));
  });

  test('unknown food uses web lookup, falls back to AI when it fails', () async {
    const reply = '{"items":[{"name":"zzqx special","grams":200,"kcal":300,"protein":10,"carbs":30,"fat":10,"confidence":0.5}]}';
    var asked = '';
    final web = (await go(reply, search: (n) async {
      asked = n;
      return {'kcal': 150.0, 'protein': 5.0, 'carbs': 20.0, 'fat': 4.0};
    })).getOrElse((_) => throw 'fail');
    expect(asked, contains('zzqx'));
    expect(web.calories, closeTo(300, 5)); // 200 g x 1.5
    final ai = (await go(reply, search: (n) async => null)).getOrElse((_) => throw 'fail');
    expect(ai.calories, closeTo(300, 5));
  });

  test('two photos are passed through', () async {
    var count = 0;
    await s.run(
      vision: (p, imgs) async {
        count = imgs.length;
        return right('{"items":[{"name":"dhido","grams":200,"kcal":1}]}');
      },
      base64Images: ['a', 'b'],
      plateCm: 26,
      katoriMl: 150,
    );
    expect(count, 2);
  });
}
