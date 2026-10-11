import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'audio/music_audio.dart';
import 'library_database.dart';
import 'sources/yt_dlp_source.dart';
import 'ui/aurora_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AuroraBootstrap());
}

class AuroraBootstrap extends StatefulWidget {
  const AuroraBootstrap({super.key});
  @override
  State<AuroraBootstrap> createState() => _AuroraBootstrapState();
}

class _AuroraBootstrapState extends State<AuroraBootstrap> {
  late Future<AppController> _startup = _createController();
  AppController? _controller;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onInactive: () {
      if (_controller != null) unawaited(_controller!.persistSession());
    },
  );

  Future<AppController> _createController() async {
    final preferences = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = await LibraryDatabase.open();
    final controller = AppController(
      audio: MusicAudio(),
      source: YtDlpSource(preferences),
      database: database,
      preferences: preferences,
      supportDirectory: directory,
    );
    await controller.initialize();
    _controller = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the listener alive without stopping background playback on Android.
    _lifecycle;
    return FutureBuilder<AppController>(
      future: _startup,
      builder: (context, snapshot) {
        final controller = snapshot.data;
        if (controller != null) {
          return ProviderScope(
            overrides: [controllerProvider.overrideWith((ref) => controller)],
            child: const AuroraApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: auroraTheme(Brightness.dark, const Color(0xffe86927)),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      snapshot.hasError
                          ? 'No se pudo iniciar Aurora'
                          : 'Preparando tu música',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.hasError) ...[
                      Text('${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _startup = _createController();
                        }),
                        child: const Text('Reintentar'),
                      ),
                    ] else
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      controllerProvider.select(
        (controller) => (
          controller.themeMode,
          controller.accentColor,
          controller.reducedMotion,
        ),
      ),
    );
    return MaterialApp(
      title: 'Aurora',
      debugShowCheckedModeBanner: false,
      themeMode: settings.$1,
      theme: auroraTheme(Brightness.light, settings.$2),
      darkTheme: auroraTheme(Brightness.dark, settings.$2),
      themeAnimationDuration: settings.$3
          ? Duration.zero
          : const Duration(milliseconds: 300),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            disableAnimations: media.disableAnimations || settings.$3,
          ),
          child: child!,
        );
      },
      home: const AuroraShell(),
    );
  }
}

ThemeData auroraTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  const ink = Color(0xff110f0e);
  const paper = Color(0xfff7f3ee);
  const ivory = Color(0xfff4eee7);
  const mutedIvory = Color(0xffd9cec1);
  const brown = Color(0xff38312c);
  final surface = dark ? ink : paper;
  final onPrimary = dark ? const Color(0xff151514) : Colors.white;
  var primary = dark
      ? accent
      : HSLColor.fromColor(accent).withLightness(0.32).toColor();
  double contrast(Color a, Color b) {
    final first = a.computeLuminance(), second = b.computeLuminance();
    return (math.max(first, second) + .05) / (math.min(first, second) + .05);
  }

  // Artwork can be any hue: preserve action labels and accent text contrast.
  for (
    var step = 0;
    step < 100 &&
        (contrast(primary, surface) < 4.7 ||
            contrast(primary, onPrimary) < 4.7);
    step++
  ) {
    final hsl = HSLColor.fromColor(primary);
    primary = hsl
        .withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0.0, 1.0))
        .toColor();
  }
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: onPrimary,
        secondary: dark ? const Color(0xffd9cec1) : brown,
        onSecondary: dark ? ink : paper,
        tertiary: dark ? const Color(0xffb9a99a) : const Color(0xff55483e),
        surface: surface,
        onSurface: dark ? ivory : const Color(0xff201a16),
        onSurfaceVariant: dark ? mutedIvory : const Color(0xff51463e),
        outline: dark ? const Color(0xff75685d) : const Color(0xff8b7d71),
        surfaceContainerLow: dark
            ? const Color(0xff191512)
            : const Color(0xfffffaf5),
        surfaceContainer: dark
            ? const Color(0xff211b17)
            : const Color(0xffeee6dd),
      );
  const bodyFont = 'Plus Jakarta Sans';
  const headlineFont = 'Newsreader';
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(
        fontFamily: bodyFont,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        headlineLarge: TextStyle(
          fontFamily: headlineFont,
          fontSize: 32,
          height: 1.15,
          color: scheme.onSurface,
        ),
        headlineMedium: TextStyle(
          fontFamily: headlineFont,
          fontSize: 28,
          height: 1.18,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontFamily: headlineFont,
          fontSize: 24,
          height: 1.2,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: headlineFont,
          fontSize: 22,
          height: 1.2,
          color: scheme.onSurface,
        ),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xff211b17) : const Color(0xfffffaf5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff211b17) : const Color(0xffeee6dd),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}
