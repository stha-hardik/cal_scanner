import 'dart:convert';
import 'dart:io';

import 'package:cal_scanner/core/di/service_locator.dart';
import 'package:cal_scanner/core/privacy/photo_cleaner.dart';
import 'package:cal_scanner/core/settings/ai_settings.dart';
import 'package:cal_scanner/features/calories/data/models/food_model.dart';
import 'package:cal_scanner/features/calories/domain/entities/food.dart';
import 'package:cal_scanner/features/calories/domain/usecases/add_food.dart';
import 'package:cal_scanner/features/calories/data/datasources/food_remote_datasource.dart';
import 'package:cal_scanner/features/calories/domain/usecases/get_daily_food_log.dart';
import 'package:cal_scanner/features/calories/presentation/cubit/food_log_cubit.dart';
import 'package:cal_scanner/features/chat/data/chat_actions.dart';
import 'package:cal_scanner/features/chat/data/chat_service.dart';
import 'package:cal_scanner/features/chat/data/chat_store.dart';
import 'package:cal_scanner/features/memory/data/memory_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class FakeCubit extends Fake implements FoodLogCubit {
  int loads = 0;
  @override
  Future<void> loadDailyLog({preserveScannedMeal}) async => loads++;
}

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json'});

Map msg(String? content, [List<Map>? calls]) => {
      'choices': [
        {
          'message': {
            'role': 'assistant',
            'content': content,
            if (calls != null) 'tool_calls': calls,
          }
        }
      ]
    };

Map tool(String name, Map args, [String id = 'c1']) => {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(args)},
    };

ChatMessage user(String t) => ChatMessage(role: 'user', content: t, time: DateTime.now());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  notesTests();
  setUp(() {
    dotenv.loadFromString(envString: 'GROK_API_KEY=');
    return freshPrefs(withProfile(sampleProfile(), {'ai_api_key': 'gsk_test'}));
  });

  group('ChatService', () {
    test('plain reply, and the request carries profile, health notes and memories', () async {
      await MemoryStore.setHealthNotes('Chronic gastritis, avoid spicy food');
      await MemoryStore.add('Vegetarian');
      final bodies = <Map>[];
      final client = MockClient((r) async {
        bodies.add(jsonDecode(r.body) as Map);
        expect(r.headers['Authorization'], 'Bearer gsk_test');
        return json(msg('Try oats with banana.'));
      });
      final reply = await http.runWithClient(
          () => ChatService.reply([user('What should I eat for breakfast?')]), () => client);
      expect(reply.text, 'Try oats with banana.');
      expect(reply.actions, isEmpty);
      expect(bodies.length, 1);
      final system = (bodies.single['messages'] as List).first['content'] as String;
      expect(system, contains('Chronic gastritis'));
      expect(system, contains('Vegetarian'));
      expect(system, contains('Daily targets: 2784 kcal'));
      expect(bodies.single['model'], AiSettings.defaultModel);
      expect((bodies.single['tools'] as List).length, 3);
    });

    test('thinking text is stripped from replies', () async {
      final client = MockClient((_) async => json(msg('<think>hmm</think>\nHello!')));
      final r = await http.runWithClient(() => ChatService.reply([user('hi')]), () => client);
      expect(r.text, 'Hello!');
    });

    test('log_meal and set_goal become proposals; nothing changes until confirmed', () async {
      final client = MockClient((_) async => json(msg('Shall I log it?', [
            tool('log_meal', {'name': 'Dal bhat', 'calories': 650, 'protein': 20, 'carbs': 110, 'fat': 12}),
            tool('set_goal', {'goal': 'body_recomposition'}, 'c2'),
          ])));
      final r = await http.runWithClient(() => ChatService.reply([user('log dal bhat')]), () => client);
      expect(r.actions.map((a) => a.name), ['log_meal', 'set_goal']);
      expect(r.actions.every((a) => a.status == 'pending'), true);
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('userData')!)['goal'], 'Maintenance');
    });

    test('save_memory saves immediately, then the AI is asked to carry on and answer', () async {
      var calls = 0;
      List? secondMessages;
      final client = MockClient((r) async {
        calls++;
        if (calls == 1) {
          return json(msg(null, [tool('save_memory', {'text': 'Has gastric problems'})]));
        }
        secondMessages = (jsonDecode(r.body) as Map)['messages'] as List;
        return json(msg('Since you have gastric problems, go for plain rice and curd.'));
      });
      final r = await http.runWithClient(
          () => ChatService.reply([user('I have gastric issues, what should I eat?')]), () => client);
      expect(calls, 2);
      expect(r.text, contains('plain rice'));
      expect(r.actions.single.name, 'save_memory');
      expect(r.actions.single.status, 'done');
      expect((await MemoryStore.items()).single.text, 'Has gastric problems');
      expect(secondMessages!.last['role'], 'tool');
      expect(secondMessages!.last['tool_call_id'], 'c1');
    });

    test('a failed follow-up still keeps the saved memory and gives a result', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return calls == 1
            ? json(msg('Noted.', [tool('save_memory', {'text': 'Allergic to peanuts'})]))
            : json({'error': {'message': 'boom'}}, 500);
      });
      final r = await http.runWithClient(() => ChatService.reply([user('peanut allergy')]), () => client);
      expect(r.text, 'Noted.');
      expect((await MemoryStore.items()).length, 1);
    });

    test('duplicate memory is not saved twice', () async {
      await MemoryStore.add('Vegetarian');
      final client = MockClient((_) async => json(msg('ok', [tool('save_memory', {'text': 'vegetarian'})])));
      final r = await http.runWithClient(() => ChatService.reply([user('I am vegetarian')]), () => client);
      expect(r.actions, isEmpty);
      expect((await MemoryStore.items()).length, 1);
    });

    test('unknown tools and garbage arguments are ignored safely', () async {
      final client = MockClient((_) async => json(msg('Hi', [
            tool('delete_everything', {}),
            {'id': 'x', 'function': {'name': 'log_meal', 'arguments': 'not json'}},
          ])));
      final r = await http.runWithClient(() => ChatService.reply([user('hi')]), () => client);
      expect(r.text, 'Hi');
      expect(r.actions, isEmpty);
    });

    test('retired model: picks another model and retries', () async {
      final seen = <String>[];
      final client = MockClient((r) async {
        if (r.url.path.endsWith('/models')) {
          return json({'data': [{'id': 'meta/new-vision-model'}]});
        }
        final model = (jsonDecode(r.body) as Map)['model'] as String;
        seen.add(model);
        if (model == AiSettings.defaultModel) {
          return json({'error': {'message': 'The model has been decommissioned'}}, 404);
        }
        return json(msg('Works now'));
      });
      final r = await http.runWithClient(() => ChatService.reply([user('hi')]), () => client);
      expect(r.text, 'Works now');
      expect(seen.first, AiSettings.defaultModel);
      expect(await AiSettings.model(), 'meta/new-vision-model', reason: 'new choice is remembered');
    });

    test('auto switch off: the error is shown, model unchanged', () async {
      await AiSettings.setAutoSwitch(false);
      final client = MockClient((_) async => json({'error': {'message': 'model gone'}}, 404));
      await expectLater(
          http.runWithClient(() => ChatService.reply([user('hi')]), () => client),
          throwsA(predicate((e) => e.toString().contains('model gone'))));
      expect(await AiSettings.model(), AiSettings.defaultModel);
    });

    test('server errors surface a readable message', () async {
      final client = MockClient((_) async => json({'error': {'message': 'Rate limit reached'}}, 429));
      await expectLater(http.runWithClient(() => ChatService.reply([user('hi')]), () => client),
          throwsA(predicate((e) => e.toString().contains('Rate limit reached'))));
      final plain = MockClient((_) async => http.Response('oops', 502));
      await expectLater(http.runWithClient(() => ChatService.reply([user('hi')]), () => plain),
          throwsA(predicate((e) => e.toString().contains('502'))));
    });

    test('empty reply is an error; missing key is an error', () async {
      final client = MockClient((_) async => json(msg('')));
      await expectLater(http.runWithClient(() => ChatService.reply([user('hi')]), () => client), throwsException);
      await freshPrefs({'ai_api_key': ''});
      // dotenv is not loaded in tests, so no fallback key exists
      await expectLater(http.runWithClient(() => ChatService.reply([user('hi')]), () => client), throwsException);
    });

    test('only the last 20 messages are sent, and proposal status is described', () async {
      Map? body;
      final client = MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        return json(msg('ok'));
      });
      final history = <ChatMessage>[
        for (var i = 0; i < 30; i++) user('message $i'),
      ];
      history.add(ChatMessage(
        role: 'assistant',
        content: 'Log it?',
        time: DateTime.now(),
        actions: [
          ChatAction(id: '1', name: 'log_meal', args: {'name': 'Egg', 'calories': 80, 'protein': 6, 'carbs': 1, 'fat': 5}, status: 'dismissed'),
        ],
      ));
      history.add(user('thanks'));
      await http.runWithClient(() => ChatService.reply(history), () => client);
      final sent = body!['messages'] as List;
      expect(sent.length, 21); // system + 20
      final asString = jsonEncode(sent);
      expect(asString, contains('declined by the user'));
      expect(asString, isNot(contains('message 0"')));
    });
  });

  group('ChatActions', () {
    String today() {
      final n = DateTime.now();
      return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    }

    ChatAction meal(Map<String, dynamic> a) => ChatAction(id: '1', name: 'log_meal', args: a);

    test('describe reads clearly', () {
      expect(ChatActions.describe(meal({'name': 'Egg', 'calories': 78.4, 'protein': 6, 'carbs': 0.6, 'fat': 5})),
          allOf(contains('Egg'), contains('78 kcal'), contains(today())));
      expect(ChatActions.describe(ChatAction(id: '2', name: 'set_goal', args: {'goal': 'body_recomposition'})),
          contains('Body recomposition'));
      expect(ChatActions.describe(ChatAction(id: '3', name: 'set_goal', args: {'goal': 'maintain', 'calories': 2200})),
          contains('2200 kcal'));
      expect(ChatActions.describe(ChatAction(id: '4', name: 'save_memory', args: {'text': 'x'})), contains('x'));
    });

    test('log_meal really adds to today\'s log and refreshes the screen', () async {
      final cubit = FakeCubit();
      final msgText = await ChatActions.apply(
          meal({'name': 'Dal bhat', 'calories': '650', 'protein': 20, 'carbs': 110, 'fat': 12}), cubit);
      expect(msgText, contains('Dal bhat'));
      expect(cubit.loads, 1);
      final log = await sl<GetDailyFoodLog>()(DateTime.now());
      final foods = log.getOrElse((_) => []);
      expect(foods.single.name, 'Dal bhat');
      expect(foods.single.calories, 650);
    });

    test('log_meal on an earlier date goes to that day', () async {
      final d = DateTime.now().subtract(const Duration(days: 2));
      final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await ChatActions.apply(
          meal({'name': 'Pizza', 'calories': 800, 'protein': 30, 'carbs': 90, 'fat': 30, 'date': ds}), FakeCubit());
      final then = (await sl<GetDailyFoodLog>()(d)).getOrElse((_) => []);
      expect(then.single.name, 'Pizza');
      expect((await sl<GetDailyFoodLog>()(DateTime.now())).getOrElse((_) => []), isEmpty);
    });

    test('bad meals are refused', () async {
      Future<void> bad(Map<String, dynamic> a) =>
          expectLater(ChatActions.apply(meal(a), FakeCubit()), throwsException);
      await bad({'name': '', 'calories': 100, 'protein': 1, 'carbs': 1, 'fat': 1});
      await bad({'name': 'x', 'calories': 100, 'protein': 1, 'carbs': 1});
      await bad({'name': 'x', 'calories': 99999, 'protein': 1, 'carbs': 1, 'fat': 1});
      await bad({'name': 'x', 'calories': -5, 'protein': 1, 'carbs': 1, 'fat': 1});
      await bad({'name': 'x', 'calories': 100, 'protein': 1, 'carbs': 1, 'fat': 1, 'date': 'yesterday'});
      final future = DateTime.now().add(const Duration(days: 3));
      await bad({
        'name': 'x', 'calories': 100, 'protein': 1, 'carbs': 1, 'fat': 1,
        'date': '${future.year}-${future.month.toString().padLeft(2, '0')}-${future.day.toString().padLeft(2, '0')}'
      });
    });

    test('set_goal changes the saved goal and refreshes', () async {
      final cubit = FakeCubit();
      final res = await ChatActions.apply(
          ChatAction(id: '1', name: 'set_goal', args: {'goal': 'body_recomposition'}), cubit);
      expect(res, contains('Body recomposition'));
      expect(res, contains('2506'));
      expect(cubit.loads, 1);
      await expectLater(
          ChatActions.apply(ChatAction(id: '2', name: 'set_goal', args: {'goal': 'bulk_up_insane'}), cubit),
          throwsException);
    });
  });

  group('Photo scan (FoodRemoteDataSource)', () {
    late File img;
    setUp(() {
      img = File('${Directory.systemTemp.path}/scan_test.jpg')..writeAsBytesSync([1, 2, 3, 4]);
    });
    tearDown(() => img.existsSync() ? img.deleteSync() : null);

    Future<dynamic> scan(MockClient c) async {
      await sl.unregister<http.Client>();
      sl.registerSingleton<http.Client>(c);
      return http.runWithClient(
          () => sl<FoodRemoteDataSource>().detectFoodAndCalories(img), () => c);
    }

    test('parses plain and markdown-fenced JSON', () async {
      for (final content in [
        '{"name":"Banana","calories":105,"protein":1.3,"carbs":27,"fat":0.4}',
        'Here you go:\n```json\n{"name":"Banana","calories":105,"protein":1.3,"carbs":27,"fat":0.4}\n```',
      ]) {
        await freshPrefs(withProfile(sampleProfile(), {'ai_api_key': 'gsk_test'}));
        final r = await scan(MockClient((req) async {
          final body = jsonDecode(req.body) as Map;
          final part = (body['messages'][0]['content'] as List).first;
          expect(part['image_url']['url'], startsWith('data:image/jpeg;base64,'));
          return json(msg(content));
        }));
        final food = r.getOrElse((_) => throw Exception('failed: $r'));
        expect(food.name, 'Banana');
        expect(food.calories, 105);
      }
    });

    test('garbage reply gives a failure, not a crash', () async {
      final r = await scan(MockClient((_) async => json(msg('I cannot tell what that is'))));
      expect(r.isLeft(), true);
      final r2 = await scan(MockClient((_) async => json(msg('{"name":"x"}'))));
      expect(r2.isLeft(), true);
    });

    test('retired model during a scan: switches model and succeeds', () async {
      final r = await scan(MockClient((req) async {
        if (req.url.path.endsWith('/models')) {
          return json({'data': [{'id': 'meta/vision-two'}]});
        }
        final model = (jsonDecode(req.body) as Map)['model'];
        if (model == AiSettings.defaultModel) {
          return json({'error': {'message': 'model decommissioned'}}, 400);
        }
        return json(msg('{"name":"Rice","calories":200,"protein":4,"carbs":44,"fat":0.5}'));
      }));
      expect(r.isRight(), true);
      expect(await AiSettings.model(), 'meta/vision-two');
    });

    test('missing image file and missing key are handled', () async {
      img.deleteSync();
      final r = await scan(MockClient((_) async => json(msg('x'))));
      expect(r.isLeft(), true);
    });
  });
}

// ---- notes and meal editing ----
void notesTests() {
  group('Photo note + meal editing', () {
    late File img;
    setUp(() async {
      dotenv.loadFromString(envString: 'GROK_API_KEY=');
      await freshPrefs(withProfile(sampleProfile(), {'ai_api_key': 'gsk_test'}));
      img = File('${Directory.systemTemp.path}/note_test.jpg')..writeAsBytesSync([1, 2, 3]);
    });
    tearDown(() => img.existsSync() ? img.deleteSync() : null);

    Future<dynamic> run(MockClient c, Future<dynamic> Function() f) async {
      await sl.unregister<http.Client>();
      sl.registerSingleton<http.Client>(c);
      return http.runWithClient(f, () => c);
    }

    test('the note is sent to the AI together with the photo', () async {
      Map? body;
      await run(MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        return json(msg('{"name":"Roti dal","calories":450,"protein":18,"carbs":70,"fat":10}'));
      }), () => sl<FoodRemoteDataSource>().detectFoodAndCalories(img, note: '2 rotis with dal, little oil'));
      final parts = body!['messages'][0]['content'] as List;
      expect(parts.first['type'], 'image_url');
      expect(parts.last['text'], contains('2 rotis with dal, little oil'));
    });

    test('no note: prompt has no note text', () async {
      Map? body;
      await run(MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        return json(msg('{"name":"x","calories":1,"protein":1,"carbs":1,"fat":1}'));
      }), () => sl<FoodRemoteDataSource>().detectFoodAndCalories(img));
      expect((body!['messages'][0]['content'] as List).last['text'], isNot(contains('USER NOTE')));
    });

    final base = Food(
        id: '1', name: 'Eggs', calories: 400, protein: 28, carbs: 2, fat: 30,
        quantity: 100, timestamp: DateTime.now(), note: null, photoPath: null);

    test('edit with photo: photo + old numbers + note are sent, result keeps id and time', () async {
      Map? body;
      final r = await run(MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return json(msg('{"name":"Eggs","calories":200,"protein":14,"carbs":1,"fat":15}'));
      }), () => sl<FoodRemoteDataSource>().reestimate(base, 'It was 2 eggs, not 4', image: img));
      final parts = body!['messages'][0]['content'] as List;
      expect(parts.first['type'], 'image_url');
      expect(parts.last['text'], allOf(contains('2 eggs, not 4'), contains('400 kcal')));
      final f = (r as dynamic).getOrElse((_) => throw Exception('failed'));
      expect(f.calories, 200);
      expect(f.id, '1');
      expect(f.timestamp, base.timestamp);
      expect(f.note, 'It was 2 eggs, not 4');
    });

    test('edit without photo: text-only request', () async {
      Map? body;
      final r = await run(MockClient((req) async {
        body = jsonDecode(req.body) as Map;
        return json(msg('{"name":"Eggs","calories":210,"protein":14,"carbs":1,"fat":16}'));
      }), () => sl<FoodRemoteDataSource>().reestimate(base, 'only 2 eggs'));
      expect(body!['messages'][0]['content'], isA<String>());
      expect(body!['messages'][0]['content'], contains('No photo'));
      expect((r as dynamic).isRight(), true);
    });

    test('edit failure is a readable failure', () async {
      final r = await run(MockClient((_) async => json({'error': {'message': 'x'}}, 500)),
          () => sl<FoodRemoteDataSource>().reestimate(base, 'fix'));
      expect((r as dynamic).isLeft(), true);
    });

    test('note and photo path survive saving; old saved meals still load', () async {
      final f = base.copyWith(note: 'my note', photoPath: '/tmp/x.jpg');
      await sl<AddFood>()(f);
      final back = (await sl<GetDailyFoodLog>()(DateTime.now())).getOrElse((_) => []).single;
      expect(back.note, 'my note');
      expect(back.photoPath, '/tmp/x.jpg');
      final old = FoodModel.fromJson({
        'id': 'o', 'name': 'Old', 'calories': 1, 'protein': 1, 'carbs': 1, 'fat': 1,
        'quantity': 100, 'timestamp': DateTime.now().toIso8601String()
      });
      expect(old.note, isNull);
    });

    test('kept photos: usable for 24h, then gone; deleting works', () async {
      final path = await PhotoCleaner.keepCopy(img, 'unit_test_photo');
      expect(path, isNotNull);
      expect(PhotoCleaner.freshPhoto(path), isNotNull);
      File(path!).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 25)));
      expect(PhotoCleaner.freshPhoto(path), isNull, reason: 'older than a day is not used');
      await PhotoCleaner.purge();
      expect(File(path).existsSync(), false);
      final p2 = await PhotoCleaner.keepCopy(img, 'unit_test_photo2');
      await PhotoCleaner.deleteKept(p2);
      expect(File(p2!).existsSync(), false);
      expect(PhotoCleaner.freshPhoto(null), isNull);
    });
  });
}
