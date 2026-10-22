import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter/Inter-Variable.ttf',
      'Bagel Fat One': 'assets/fonts/bagel_fat_one/BagelFatOne-Regular.ttf',
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final kind in ['modern', 'brasa']) {
    for (final mode in ['light', 'dark']) {
      testWidgets('$kind $mode renders the main screens without errors', (
        tester,
      ) async {
        final controller = (await tester.runAsync(
          () => createTestController(
            preferences: {'themeKind': kind, 'themeMode': mode},
            tracks: [
              for (var i = 0; i < 40; i++)
                Track(
                  id: 'bulk$i',
                  title: 'Canción de relleno $i',
                  artist: 'Artista $i',
                  pageUrl: 'https://www.youtube.com/watch?v=bulk$i',
                  duration: const Duration(minutes: 3),
                ),

              Track(
                id: 'one',
                title: 'Una canción con un título muy largo',
                artist: 'Un artista',
                pageUrl: 'https://www.youtube.com/watch?v=test-one',
                duration: Duration(minutes: 4),
              ),
              Track(
                id: 'two',
                title: 'Otra canción',
                artist: 'Aurora',
                pageUrl: 'https://www.youtube.com/watch?v=test-two',
                duration: Duration(minutes: 3),
              ),
            ],
          ),
        ))!;
        addTearDown(() async {
          await tester.runAsync(() async {
            await controller.database.close();
            if (await controller.supportDirectory.exists()) {
              await controller.supportDirectory.delete(recursive: true);
            }
          });
        });
        final container = ProviderContainer(
          overrides: [controllerProvider.overrideWith((ref) => controller)],
        );
        addTearDown(container.dispose);
        for (final size in [const Size(1440, 900), const Size(390, 800)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const RepaintBoundary(
                key: ValueKey('shot'),
                child: AuroraApp(),
              ),
            ),
          );
          await settle(tester);
          expect(tester.takeException(), isNull);
          Future<void> shot(String name) => tester.runAsync(() async {
            final b = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('shot')),
            );
            final img = await b.toImage();
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/modern-review').create(recursive: true);
            await File(
              'build/modern-review/$kind-$name-$mode-${size.width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            img.dispose();
          });
          await shot('home');
          for (final label in [
            'Biblioteca',
            'Me gusta',
            'Artistas',
            'Ajustes',
            'Modo Vinilo',
            'Ecualizador',
          ]) {
            final f = find.text(label);
            if (f.evaluate().isEmpty) continue;
            await tester.tap(f.first);
            await settle(tester);
            expect(tester.takeException(), isNull);
            await shot(label.toLowerCase());
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}
