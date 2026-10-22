import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/playlist_shelf.dart';
import 'package:aurora_music/ui/playlist_views/playlist_view_mode.dart';
import 'package:aurora_music/ui/playlist_views/playlist_view_mode_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late AppController controller;
  MusicPlaylist? opened;
  setUp(() async {
    opened = null;
    controller = await createTestController(
      tracks: const [Track(id: 'one', title: 'Uno', artist: 'A')],
    );
    controller.playlists
      ..add(const MusicPlaylist(id: 'b', name: 'Beta', trackIds: ['one']))
      ..add(const MusicPlaylist(id: 'a', name: 'Alfa', trackIds: ['one']));
  });
  tearDown(() async {
    playlistViewMode.value = PlaylistViewMode.normal;
    await closeTestController(controller);
  });

  Future<void> pump(WidgetTester tester, PlaylistViewMode mode) async {
    playlistViewMode.value = mode;
    await controller.preferences.setString(playlistViewModeKey, mode.name);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PlaylistShelf(
              controller: controller,
              onOpen: (p) => opened = p,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('normal: busca y ordena', (tester) async {
    await pump(tester, PlaylistViewMode.normal);
    expect(find.text('Alfa'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'bet');
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsNothing);
    await tester.tap(find.text('Beta'));
    expect(opened?.id, 'b');
  });

  testWidgets('casetes: muestra y abre', (tester) async {
    await pump(tester, PlaylistViewMode.cassettes);
    expect(find.text('Alfa'), findsOneWidget);
    await tester.tap(find.text('Beta'));
    expect(opened?.id, 'b');
  });

  testWidgets('cajón: hojea y abre la del centro', (tester) async {
    await pump(tester, PlaylistViewMode.crate);
    expect(tester.takeException(), isNull);
    // Orden «recientes»: Alfa (última añadida) queda al centro.
    await tester.tapAt(
      tester.getCenter(find.byType(PageView)) + const Offset(0, 20),
    );
    await tester.pumpAndSettle();
    expect(opened?.id, 'a');
  });

  testWidgets('tile guarda el modo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaylistViewModeTile(controller: controller)),
      ),
    );
    await tester.tap(find.text('Casetes'));
    await tester.pumpAndSettle();
    expect(playlistViewMode.value, PlaylistViewMode.cassettes);
    expect(controller.preferences.getString(playlistViewModeKey), 'cassettes');
  });
}
