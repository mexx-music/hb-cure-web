import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'ui/main_shell.dart';
import 'ui/pages/start_page.dart';
import 'ui/theme/app_colors.dart';
import 'dart:async';
import 'services/app_memory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppMemory.instance.init();
  // In debug builds, automatically disable debug baseline painting (the yellow lines)
  assert(() {
    debugPaintBaselinesEnabled = false;
    return true;
  }());
  // Also ensure other debug paints are disabled at startup when running in debug mode.
  if (kDebugMode) {
    // Explicitly set these to false at startup to avoid Inspector/DevTools toggles showing overlays on app start.
    debugPaintBaselinesEnabled = false;
    debugPaintSizeEnabled = false;
    debugPaintPointersEnabled = false;
    debugPrint('DEBUG PAINT FLAGS at startup: baselines=\$debugPaintBaselinesEnabled, size=\$debugPaintSizeEnabled, pointers=\$debugPaintPointersEnabled');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // defensive: ensure debug paints are disabled during build in debug mode
    if (kDebugMode) {
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
    }
    final base = ThemeData.light();
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
      debugShowCheckedModeBanner: false,
      home: kDebugMode ? _DebugOverlayDisabler(child: const StartPage()) : const StartPage(),
    );
  }
}

// A tiny debug-only widget that disables debug paint overlays after the first frame.
class _DebugOverlayDisabler extends StatefulWidget {
  final Widget child;
  const _DebugOverlayDisabler({required this.child});

  @override
  State<_DebugOverlayDisabler> createState() => _DebugOverlayDisablerState();
}

class _DebugOverlayDisablerState extends State<_DebugOverlayDisabler> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // re-apply disabling of debug paints in case DevTools toggled them on later
      debugPaintBaselinesEnabled = false;
      debugPaintSizeEnabled = false;
      debugPaintPointersEnabled = false;
      debugPrint('DEBUG PAINT FLAGS after first frame: baselines=\$debugPaintBaselinesEnabled, size=\$debugPaintSizeEnabled, pointers=\$debugPaintPointersEnabled');
      // Defensive: periodically reset the debug paint flags for the first few seconds
      if (kDebugMode) {
        int ticks = 0;
        final timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
          debugPaintBaselinesEnabled = false;
          debugPaintSizeEnabled = false;
          debugPaintPointersEnabled = false;
          ticks++;
          if (ticks > 15) {
            t.cancel();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
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
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
