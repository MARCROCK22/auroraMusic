import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/playlist_shelf.dart';
import 'package:aurora_music/ui/dj_filters_panel.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppController controller;
  setUp(() async {
    controller = await createTestController(
      tracks: const [
        Track(
          id: 'one',
          title: 'Una canción de mi biblioteca',
          artist: 'Artista de la biblioteca',
          localPath: '/music/one.mp3',
        ),
      ],
    );
  });
  tearDown(() => closeTestController(controller));
  testWidgets('DJ artist selection works at 320 dp and preserves exclusions', (
    tester,
  ) async {
    await controller.setDjFilters(const DjFilters(excludedTrackIds: ['other']));
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: DjFiltersPanel(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Personalizar el DJ'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Tu biblioteca todavía no tiene géneros. Solo usamos los metadatos disponibles.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Artistas'));
    await tester.tap(find.text('Artistas'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Artista de la biblioteca'));
    await tester.ensureVisible(find.text('Aplicar filtros'));
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(controller.djFilters.artists, ['Artista de la biblioteca']);
    expect(controller.djFilters.excludedTrackIds, ['other']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'playlist artwork fallback and selection work at 320 dp with enlarged text',
    (tester) async {
      controller.playlists.add(
        const MusicPlaylist(
          id: 'list',
          name: 'Mis canciones favoritas para escuchar',
          trackIds: ['one'],
        ),
      );
      MusicPlaylist? selected;
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: PlaylistShelf(
                  controller: controller,
                  onOpen: (playlist) => selected = playlist,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(find.text('1 canciones'), findsOneWidget);
      await tester.tap(find.text(controller.playlists.single.name));
      expect(selected?.id, 'list');
    },
  );
}
