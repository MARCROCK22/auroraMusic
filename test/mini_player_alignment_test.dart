import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';

import 'support/fakes.dart';

void main() {
  testWidgets(
    'mini-player centers desktop transport and fits mobile metadata',
    (tester) async {
      const track = Track(
        id: 'alignment',
        title: 'Una pista larga para comprobar el recorte del mini reproductor',
        artist: 'Aurora',
        pageUrl: 'https://www.youtube.com/watch?v=alignment',
        duration: Duration(minutes: 3),
      );
      final controller = (await tester.runAsync(
        () => createTestController(tracks: const [track], audio: FakeAudio()),
      ))!;
      final container = ProviderContainer(
        overrides: [controllerProvider.overrideWith((ref) => controller)],
      );
      addTearDown(() async {
        container.dispose();
        await tester.runAsync(() async {
          await controller.closed;
          if (await controller.supportDirectory.exists()) {
            await controller.supportDirectory.delete(recursive: true);
          }
        });
      });
      await tester.runAsync(() => controller.playTrack(track));
      await controller.audio.pause();

      for (final (size, scale) in [
        (const Size(1440, 900), 1.0),
        (const Size(900, 900), 1.0),
        (const Size(320, 800), 2.0),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: const AuroraApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final playButton = find.byTooltip('Reproducir').last;
        expect(playButton, findsOneWidget);
        if (size.width >= 900) {
          expect(tester.getCenter(playButton).dx, closeTo(size.width / 2, 1));
        } else {
          final metadata = find.text(track.title);
          expect(metadata, findsOneWidget);
          final metadataRect = tester.getRect(metadata);
          final playRect = tester.getRect(playButton);
          expect(metadataRect.right, lessThanOrEqualTo(playRect.left - 12));
        }
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout $size at scale $scale',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    },
  );
}
