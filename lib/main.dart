import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'ui/main_shell.dart';
import 'ui/pages/start_page.dart';
import 'ui/theme/app_colors.dart';
import 'dart:async';
import 'services/app_memory.dart';
import 'services/clients_store.dart';
import 'app_services.dart';
import 'i18n/program_name_localizer.dart';
import 'l10n/gen/app_localizations.dart';
import 'services/program_language_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Minimal-Fix (robust): Debug-Paint/Baselines/Pointers/etc. global abschalten (vor runApp)
  if (kDebugMode) {
    debugPaintSizeEnabled = false;
    debugPaintBaselinesEnabled = false;
    debugPaintPointersEnabled = false;
    debugPaintLayerBordersEnabled = false;
    debugRepaintRainbowEnabled = false;
  }

  await AppMemory.instance.init();

  // Ensure program name CSV is loaded early so localized program names are available
  // as soon as the UI is shown.
  try {
    await ProgramNameLocalizer.instance.ensureLoaded();
  } catch (_) {
    // non-fatal: proceed even if CSV load failed
  }

  // Load persisted program settings for the active client
  try {
    final activeId = await ClientsStore.instance.loadActiveClientId();
    await playerService.loadSettingsForClient(activeId ?? 'default');
  } catch (_) {
    // non-fatal
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final VoidCallback _langListener;

  @override
  void initState() {
    super.initState();
    _langListener = () {
      if (mounted) setState(() {});
    };
    ProgramLangController.instance.addListener(_langListener);
  }

  @override
  void dispose() {
    ProgramLangController.instance.removeListener(_langListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.light();
    // Derive Flutter locale from ProgramLangController so that
    // AppLocalizations.of(context) always matches the toggle state.
    final locale = ProgramLangController.instance.lang == ProgramLang.de
        ? const Locale('de')
        : const Locale('en');

    return MaterialApp(
      title: 'Cure App',
      theme: base.copyWith(
        scaffoldBackgroundColor: AppColors.background,
        textTheme: base.textTheme.copyWith(
          bodyMedium: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          titleLarge: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          displaySmall: const TextStyle(fontSize: 36, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
        ),
      ),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      home: const StartPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
