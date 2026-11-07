import 'dart:convert';

import 'package:cal_scanner/core/di/service_locator.dart';
import 'package:cal_scanner/core/settings/ai_settings.dart';
import 'package:cal_scanner/core/settings/theme_settings.dart';
import 'package:cal_scanner/features/calories/presentation/cubit/food_log_cubit.dart';
import 'package:cal_scanner/features/chat/presentation/rich_reply.dart';
import 'package:cal_scanner/features/memory/data/memory_store.dart';
import 'package:cal_scanner/features/memory/presentation/memory_screen.dart';
import 'package:cal_scanner/features/settings/presentation/settings_screen.dart';
import 'package:cal_scanner/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget app(Widget child, {FoodLogCubit? cubit}) {
  final home = cubit == null ? child : BlocProvider.value(value: cubit, child: child);
  return MaterialApp(home: home);
}

Future<Map<String, dynamic>> profile() async {
  final p = await SharedPreferences.getInstance();
  return jsonDecode(p.getString('userData')!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    dotenv.loadFromString(envString: 'GROK_API_KEY=');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('cal_ai/widget'), (_) async => null);
    await freshPrefs(withProfile(sampleProfile(), {'ai_api_key': 'gsk_abc'}));
  });

  testWidgets('RichReply shows bold, bullets and headings as text', (t) async {
    await t.pumpWidget(app(const Scaffold(
        body: RichReply('# Plan\nEat **more protein**\n- oats\n- eggs\n*Note* done'))));
    final all = t.widgetList<RichText>(find.byType(RichText)).map((r) => r.text.toPlainText()).join('|');
    expect(all, contains('more protein'));
    expect(all, contains('oats'));
    expect(all, contains('eggs'));
    expect(all, isNot(contains('**')));
    expect(all, isNot(contains('# Plan')));
  });

  testWidgets('Settings screen: loads values, saves new key and model', (t) async {
    tall(t);
    final cubit = sl<FoodLogCubit>();
    await t.pumpWidget(app(const SettingsScreen(), cubit: cubit));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsWidgets);
    expect(find.text('Body recomposition'), findsOneWidget);
    expect(find.text('Memory & health notes'), findsOneWidget);

    final fields = find.byType(TextField);
    expect(fields, findsWidgets);
    final key = find.widgetWithText(TextField, 'gsk_abc');
    expect(key, findsOneWidget, reason: 'saved key is shown');

    await t.enterText(key, 'gsk_new_key');
    await t.scrollUntilVisible(find.text('Save'), 300, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(await AiSettings.apiKey(), 'gsk_new_key');
  });

  testWidgets('Settings screen: changing the goal updates the saved targets', (t) async {
    tall(t);
    final cubit = sl<FoodLogCubit>();
    await t.pumpWidget(app(const SettingsScreen(), cubit: cubit));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Body recomposition'), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.text('Body recomposition'));
    await t.pumpAndSettle();
    final p = await profile();
    expect(p['goal'], 'Body Recomposition');
    expect(p['estimatedCalories'], 2506);
    await t.tap(find.text('Lose weight'));
    await t.pumpAndSettle();
    expect((await profile())['estimatedCalories'], 2227);
  });

  testWidgets('Settings screen: workout slider changes the calories', (t) async {
    tall(t);
    final cubit = sl<FoodLogCubit>();
    await t.pumpWidget(app(const SettingsScreen(), cubit: cubit));
    await t.pumpAndSettle();
    final slider = find.byType(Slider).first; // the workout slider (plate/katori sliders come after it)
    await t.scrollUntilVisible(slider, 200, scrollable: find.byType(Scrollable).first);
    expect(find.byType(Slider), findsNWidgets(3));
    // drag fully right = Very Active
    await t.drag(slider, const Offset(2000, 0));
    await t.pumpAndSettle();
    var p = await profile();
    expect(p['activityLevel'], 'Very Active');
    expect(p['estimatedCalories'], 3413);
    expect(p['goal'], 'Maintenance');
    await t.drag(slider, const Offset(-3000, 0));
    await t.pumpAndSettle();
    p = await profile();
    expect(p['activityLevel'], 'Sedentary');
    expect(p['estimatedCalories'], 2156);
  });

  testWidgets('Settings screen: theme choice is saved', (t) async {
    tall(t);
    final cubit = sl<FoodLogCubit>();
    await t.pumpWidget(app(const SettingsScreen(), cubit: cubit));
    await t.pumpAndSettle();
    await t.tap(find.text('Dark'));
    await t.pumpAndSettle();
    expect(ThemeSettings.mode.value, ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getString('theme_mode'), 'dark');
    await t.tap(find.text('Light'));
    await t.pumpAndSettle();
    expect(ThemeSettings.mode.value, ThemeMode.light);
    await ThemeSettings.set(ThemeMode.system);
  });

  testWidgets('Memory screen: health notes autosave, add / edit-free delete of memories', (t) async {
    await t.pumpWidget(app(const MemoryScreen()));
    await t.pumpAndSettle();
    expect(find.text('Nothing saved yet.'), findsOneWidget);

    final notes = find.byType(TextField).first;
    await t.enterText(notes, 'I have gastric problems');
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(await MemoryStore.healthNotes(), 'I have gastric problems');

    final add = find.widgetWithText(TextField, '').last;
    await t.enterText(find.byType(TextField).last, 'No dairy at night');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('No dairy at night'), findsOneWidget);
    expect(find.text('Added by you'), findsOneWidget);
    expect((await MemoryStore.items()).single.text, 'No dairy at night');
    expect(add, isNotNull);
  });

  testWidgets('Memory screen shows AI-saved memories and old notes', (t) async {
    await MemoryStore.setHealthNotes('Acid reflux');
    await MemoryStore.add('Vegetarian', source: 'ai');
    await t.pumpWidget(app(const MemoryScreen()));
    await t.pumpAndSettle();
    expect(find.text('Acid reflux'), findsOneWidget);
    expect(find.text('Vegetarian'), findsOneWidget);
    expect(find.text('Saved by AI'), findsOneWidget);
  });

  test('AppColors switch with dark mode', () {
    AppColors.isDark = false;
    final light = [AppColors.kCard, AppColors.kBlack];
    AppColors.isDark = true;
    final dark = [AppColors.kCard, AppColors.kBlack];
    AppColors.isDark = false;
    expect(light, isNot(equals(dark)));
  });
}
