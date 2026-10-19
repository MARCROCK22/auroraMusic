import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/studio/equalizer_panel.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(
  id: 'song',
  title: 'Canción base',
  artist: 'Artista',
  duration: Duration(minutes: 3),
);

void main() {
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  late AppController app;
  late ProviderContainer container;

  setUp(() async {
    app = await createTestController(tracks: [_song], audio: FakeAudio());
    await app.playTrack(_song);
    await app.pausePlayback();
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => app)],
    );
  });

  tearDown(() async {
    container.dispose();
    await app.closed;
    if (await app.supportDirectory.exists()) {
      await app.supportDirectory.delete(recursive: true);
    }
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuroraApp()),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Las pantallas con animación continua (vinilo) no "se asientan".
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the button is on home, vinyl, queue, lyrics and Jam', (
    tester,
  ) async {
    await mount(tester, const Size(1400, 900));
    for (final (key, shift) in [
      (LogicalKeyboardKey.digit1, false), // inicio
      (LogicalKeyboardKey.keyI, false), // vinilo
      (LogicalKeyboardKey.keyQ, true), // cola
      (LogicalKeyboardKey.keyL, false), // letras (página)
      (LogicalKeyboardKey.keyJ, false), // Jam
    ]) {
      await chord(tester, key, shift: shift);
      expect(
        find.byType(TransportEqualizerButton),
        findsWidgets,
        reason: 'section for $key',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl+E opens the EQ sheet over the current screen', (
    tester,
  ) async {
    await mount(tester, const Size(1400, 900));
    await chord(tester, LogicalKeyboardKey.keyQ, shift: true);
    await chord(tester, LogicalKeyboardKey.keyE);
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.byType(StudioTransport), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the "now playing" sheet reuses the same button', (tester) async {
    await mount(tester, const Size(500, 900));
    await tester.tap(find.text(_song.title).last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('AHORA SUENA'), findsOneWidget);
    expect(find.byType(TransportEqualizerButton), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
