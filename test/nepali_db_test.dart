import 'dart:io';

import 'package:cal_scanner/features/nepali_food/nepali_food_db.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late NepaliFoodDb db;
  setUpAll(() => db = NepaliFoodDb.fromJsonString(File('assets/data/nepali_foods.json').readAsStringSync()));

  test('table is loaded and every row is sane', () {
    expect(db.foods.length, greaterThan(80));
    final ids = <String>{};
    for (final f in db.foods) {
      expect(ids.add(f.id), true, reason: 'duplicate id ${f.id}');
      expect(f.kcal100, inInclusiveRange(0, 900), reason: f.id);
      expect(f.servingGrams, greaterThan(0), reason: f.id);
      final macroKcal = f.protein100 * 4 + f.carbs100 * 4 + f.fat100 * 9;
      if (!['raksi', 'beer'].contains(f.id)) {
        expect((f.kcal100 - macroKcal).abs(), lessThan(50), reason: '${f.id} kcal vs macros');
      }
      expect(f.aliases, isNotEmpty);
    }
  });

  test('misspellings find the right food', () {
    String? name(String q) => db.best(q)?.food.id;
    expect(name('gualamari'), 'gwaramari');
    expect(name('gwaramari'), 'gwaramari');
    expect(name('gwarmari'), 'gwaramari');
    expect(name('sel roti'), 'sel_roti');
    expect(name('sael rotti'), 'sel_roti');
    expect(name('selroti'), 'sel_roti');
    expect(name('Sel Roti'), 'sel_roti');
    expect(name('dhido'), 'dhido');
    expect(name('dhindo'), 'dhido');
    expect(name('momo'), 'momo_chicken');
    expect(name('buff momo'), 'momo_buff');
    expect(name('chatamari'), 'chatamari');
    expect(name('yomari'), 'yomari');
    expect(name('juju dhau'), 'juju_dhau');
    expect(name('daal bhaat'), 'dal_bhat_set');
    expect(name('gundruk'), 'gundruk');
    expect(name('chiya'), 'chiya');
    expect(name('titaura'), 'titaura');
    expect(name('sekuwa'), 'sekuwa');
  });

  test('Nepali script names are searchable too? (aliases are Roman; unknown stays unknown)', () {
    expect(db.best('spaceship engine'), isNull);
    expect(db.best('xyz'), isNull);
    expect(db.best(''), isNull);
  });

  test('similar but different foods are not confused', () {
    expect(db.best('dal')?.food.id, 'dal');
    expect(db.best('bhat')?.food.id, 'bhat');
    expect(db.best('banana')?.food.id, 'banana');
    expect(db.best('roti')?.food.id, 'roti');
    expect(db.best('paratha')?.food.id, 'paratha');
    expect(db.best('puri')?.food.id, 'puri');
    expect(db.best('pizza')?.food.id, 'pizza');
  });

  test('finds foods and quantities inside a typed note', () {
    final r = db.findInText('2 sel roti and gualamari with chiya');
    final ids = r.map((e) => e.food.id).toList();
    expect(ids, containsAll(['sel_roti', 'gwaramari', 'chiya']));
    expect(r.firstWhere((e) => e.food.id == 'sel_roti').quantity, 2);
    expect(r.firstWhere((e) => e.food.id == 'gwaramari').quantity, isNull);
    final r2 = db.findInText('ek plate momo, dui ando');
    expect(r2.map((e) => e.food.id), containsAll(['momo_chicken', 'egg_boiled']));
    expect(db.findInText('had a very big lunch today'), isEmpty);
  });

  test('portion maths', () {
    final sel = db.best('sel roti')!.food;
    final n = sel.forGrams(160);
    expect(n.kcal.round(), 464);
    final prompt = db.promptTable();
    expect(prompt, contains('Gwaramari'));
    expect(prompt, contains('ग्वारामरी'));
  });
}
