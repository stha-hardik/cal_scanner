import 'dart:convert';
import 'dart:io';

import 'package:cal_scanner/core/di/service_locator.dart';
import 'package:cal_scanner/features/calories/domain/entities/food.dart';
import 'package:cal_scanner/features/calories/domain/usecases/add_food.dart';
import 'package:cal_scanner/features/calories/domain/usecases/get_daily_food_log.dart';
import 'package:cal_scanner/features/calories/presentation/cubit/food_log_cubit.dart';
import 'package:cal_scanner/features/calories/presentation/screens/meal_detail_screen.dart';
import 'package:cal_scanner/features/calories/presentation/screens/scan_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'helpers.dart';

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget wrap(Widget home) => ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, __) => MaterialApp(home: home),
    );

Future<List<Map>> useClient(String reply) async {
  final bodies = <Map>[];
  final c = MockClient((r) async {
    bodies.add(jsonDecode(r.body) as Map);
    return http.Response.bytes(
        utf8.encode(jsonEncode({
          'choices': [
            {'message': {'content': reply}}
          ]
        })),
        200);
  });
  await sl.unregister<http.Client>();
  sl.registerSingleton<http.Client>(c);
  return bodies;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late File img;
  setUp(() async {
    dotenv.loadFromString(envString: 'GROK_API_KEY=');
    await freshPrefs(withProfile(sampleProfile(), {'ai_api_key': 'gsk_test'}));
    img = File('${Directory.systemTemp.path}/ui_scan.jpg')..writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
  });
  tearDown(() => img.existsSync() ? img.deleteSync() : null);

  testWidgets('photo screen: nothing is sent until Analyze; the note goes with the photo', (t) async {
    tall(t);
    final bodies = await useClient('{"name":"Dal bhat","calories":600,"protein":20,"carbs":100,"fat":10}');
    final cubit = sl<FoodLogCubit>();
    await t.runAsync(() async {
      await t.pumpWidget(wrap(BlocProvider.value(value: cubit, child: ScanResultScreen(imageFile: img))));
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(bodies, isEmpty, reason: 'must wait for the user');
    expect(find.text('Analyze'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'extra ghee, large plate');
    await t.runAsync(() async {
      await t.tap(find.text('Analyze'));
      await Future.delayed(const Duration(seconds: 1));
    });
    await t.pump(const Duration(milliseconds: 500));
    expect(bodies.length, 1);
    expect(jsonEncode(bodies.single), contains('extra ghee, large plate'));
    await t.pump(const Duration(seconds: 1));
    final saved = await t.runAsync(() async => (await sl<GetDailyFoodLog>()(DateTime.now())).getOrElse((_) => []));
    expect(saved!.single.name, 'Dal bhat');
    expect(saved.single.note, 'extra ghee, large plate');
    expect(saved.single.photoPath, isNotNull);
    await t.runAsync(() async => File(saved.single.photoPath!).deleteSync());
  });

  testWidgets('meal screen: Edit sends note, shows new numbers, Save updates the meal', (t) async {
    tall(t);
    final bodies = await useClient('{"name":"Eggs","calories":200,"protein":14,"carbs":1,"fat":15}');
    final meal = Food(
        id: 'm1', name: 'Eggs', calories: 400, protein: 28, carbs: 2, fat: 30,
        quantity: 100, timestamp: DateTime.now());
    await t.runAsync(() => sl<AddFood>()(meal));
    final cubit = sl<FoodLogCubit>();
    await t.runAsync(() async {
      await t.pumpWidget(wrap(BlocProvider.value(value: cubit, child: MealDetailScreen(meal: meal))));
    });
    await t.pump();
    expect(find.text('400'), findsOneWidget);
    await t.tap(find.byTooltip('Edit'));
    await t.pumpAndSettle();
    expect(find.textContaining('photo is gone'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'only 2 eggs');
    await t.runAsync(() async {
      await t.tap(find.text('Re-analyze'));
      await Future.delayed(const Duration(seconds: 1));
    });
    await t.pumpAndSettle();
    expect(jsonEncode(bodies.single), contains('only 2 eggs'));
    expect(find.textContaining('200 kcal'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Save'));
      await Future.delayed(const Duration(milliseconds: 500));
    });
    await t.pumpAndSettle();
    expect(find.text('200'), findsOneWidget);
    expect(find.text('only 2 eggs'), findsOneWidget);
    final saved = await t.runAsync(() async => (await sl<GetDailyFoodLog>()(DateTime.now())).getOrElse((_) => []));
    expect(saved!.single.calories, 200);
    expect(saved.length, 1, reason: 'edited in place, not duplicated');
  });
}
