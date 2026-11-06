import 'package:device_preview/device_preview.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/di/service_locator.dart';
import 'core/privacy/photo_cleaner.dart';
import 'core/settings/theme_settings.dart';
import 'theme/app_colors.dart';
import 'features/calories/presentation/cubit/food_log_cubit.dart';
import 'features/onboarding/presentation/cubit/onboarding_cubit.dart';
import 'theme/app_typography.dart';
import 'theme/theme.dart';

Future<void> _loadEnvironmentFile() async {
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Error loading .env file: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _loadEnvironmentFile();
  await ThemeSettings.load();
  PhotoCleaner.purge(); // delete temporary meal photos older than 24 hours
  AppColors.isDark = ThemeSettings.effectiveDark(ThemeSettings.mode.value);

  final prefs = await SharedPreferences.getInstance();
  final showOnboarding = !(prefs.getBool('onboarding_complete') ?? false);

  await configureDependencies(prefs: prefs, showOnboarding: showOnboarding);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    DevicePreview(
      enabled: false,
      builder: (context) => MyApp(router: sl<GoRouter>()),
    ),
  );
}

class MyApp extends StatefulWidget {
  final GoRouter router;

  const MyApp({super.key, required this.router});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemeSettings.mode.addListener(_applyTheme);
  }

  @override
  void dispose() {
    ThemeSettings.mode.removeListener(_applyTheme);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _applyTheme();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) PhotoCleaner.purge();
  }

  /// Update the shared colours, then rebuild every widget so they pick them up.
  void _applyTheme() {
    final dark = ThemeSettings.effectiveDark(ThemeSettings.mode.value);
    final changed = dark != AppColors.isDark;
    AppColors.isDark = dark;
    setState(() {});
    if (changed) {
      void visit(Element e) {
        e.markNeedsBuild();
        e.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => sl<FoodLogCubit>()),
            BlocProvider(create: (_) => sl<OnboardingCubit>()),
          ],

          child: MaterialApp.router(
            routerConfig: widget.router,
            theme: buildLightTheme().copyWith(
              textTheme: AppTypography.textTheme,
            ),
            darkTheme: buildDarkTheme().copyWith(
              textTheme: AppTypography.textTheme,
            ),
            themeMode: ThemeSettings.mode.value,

            debugShowCheckedModeBanner: false,
            title: 'AI Calorie Tracker',
          ),
        );
      },
    );
  }
}
