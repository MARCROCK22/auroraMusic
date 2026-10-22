import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  for (final kind in ['modern', 'brasa', 'atelier']) {
    testWidgets('$kind: la lista de Me gusta ocupa todo el alto disponible', (
      tester,
    ) async {
      final controller = (await tester.runAsync(() async {
        final c = await createTestController(
          preferences: {'themeKind': kind},
          tracks: [
            for (var i = 0; i < 40; i++)
              Track(
                id: 'bulk$i',
                title: 'Cancion $i',
                artist: 'Artista $i',
                pageUrl: 'https://www.youtube.com/watch?v=bulk$i',
                duration: const Duration(minutes: 3),
              ),
          ],
        );
        for (final t in c.tracks) {
          await c.toggleFavorite(t);
        }
        await c.playTrack(c.tracks.first, context: c.tracks);
        return c;
      }))!;
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
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AuroraApp(),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.text('Biblioteca').first);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.text('Me gusta').first);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      // La lista de la biblioteca es la vertical mas ancha (la barra lateral
      // de Brasa y la cola tambien son ListView estrechos).
      final list = find
          .byWidgetPredicate(
            (w) => w is ListView && w.scrollDirection == Axis.vertical,
          )
          .evaluate()
          .map((e) => e.renderObject! as RenderBox)
          .reduce((a, b) => a.size.width >= b.size.width ? a : b);
      // Regresion: un Flexible de cabecera repartia el alto 50/50 con la lista.
      expect(list.size.height, greaterThan(450));
      expect(
        list.localToGlobal(Offset(0, list.size.height)).dy,
        greaterThan(780),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
