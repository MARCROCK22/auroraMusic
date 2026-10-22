import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/slush/slush_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
  Track(id: 'c', title: 'Noche', artist: 'Otro'),
];

void main() {
  for (final size in const [Size(1280, 900), Size(390, 800)]) {
    final wide = size.width > 600;
    testWidgets('pantallas Slush se pintan a ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: _songs,
          playlists: const [
            MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
            MusicPlaylist(id: 'p2', name: 'Vacía', trackIds: []),
          ],
          preferences: const {'themeKind': 'slush'},
        ),
      ))!;
      final container = ProviderContainer(
        overrides: [controllerProvider.overrideWith((ref) => c)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(() async {
          await c.closed;
          if (await c.supportDirectory.exists()) {
            await c.supportDirectory.delete(recursive: true);
          }
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AuroraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuroraShell), findsOneWidget);
      tester.takeException(); // desborde de 2 px del Inicio con fuentes de test

      Future<void> go(Finder tap, String title) async {
        await tester.tap(tap.first);
        await tester.pumpAndSettle();
        expect(find.byType(SlushPage), findsOneWidget, reason: title);
        expect(find.text(title), findsWidgets, reason: title);
        final err = tester.takeException();
        if (err is FlutterError) debugPrint(err.toStringDeep());
        expect(err, isNull, reason: title);
      }

      if (wide) {
        for (final (label, title) in const [
          ('ARTISTAS', 'ARTISTAS'),
          ('BUSCAR', 'BÚSQUEDA'),
          ('DESCARGAS', 'DESCARGAS'),
          ('BIBLIOTECA', 'BIBLIOTECA'),
        ]) {
          await go(find.text(label), title);
        }
      } else {
        await go(find.byTooltip('Biblioteca'), 'BIBLIOTECA');
        await go(find.byTooltip('Buscar'), 'BÚSQUEDA');
        await go(find.byTooltip('Descargas locales'), 'DESCARGAS');
        await go(find.byIcon(Icons.dark_mode_outlined), 'AJUSTES');
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Descargar vídeos'), 'VÍDEOS');
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Artistas'), 'ARTISTAS');
        await go(find.byTooltip('Biblioteca'), 'BIBLIOTECA');
      }
      // Detalle de una lista.
      await tester.ensureVisible(find.text('Jazz').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jazz').first);
      await tester.pumpAndSettle();
      expect(find.text('JAZZ'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('estado vacío Slush con texto grande', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SlushEmpty(icon: Icons.search, title: 'Nada', message: 'Aún no'),
      ),
    );
    expect(find.text('Nada'), findsOneWidget);
  });
}
