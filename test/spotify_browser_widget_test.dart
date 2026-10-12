import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/metadata/spotify/spotify_browser_controller.dart';
import 'package:aurora_music/metadata/spotify/spotify_metadata_provider.dart';
import 'package:aurora_music/ui/spotify_browser_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const track = Track(
    id: 'spotify:track:fixture',
    title: 'Canción de prueba',
    artist: 'Artista de prueba',
    spotifyMatchPending: true,
  );
  const item = SpotifyMetadataEntity(
    type: SpotifyEntityType.track,
    uri: 'spotify:track:fixture',
    name: 'Canción de prueba',
    subtitle: 'Artista de prueba',
    track: track,
  );

  testWidgets(
    'metadata states and queue action remain usable with enlarged narrow layout',
    (tester) async {
      final browser = _FixtureBrowser();
      addTearDown(browser.dispose);
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Track? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SpotifyBrowserPanel(
                browser: browser,
                onQueue: (value) async => selected = value,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Explora canciones, artistas y colecciones'),
        findsOneWidget,
      );
      browser.loading = true;
      browser.publish();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      browser.loading = false;
      browser.error = 'A safe metadata error';
      browser.publish();
      await tester.pump();
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      expect(browser.searchCalls, 1);
      browser.error = null;
      browser.query = 'consulta';
      browser.page = SpotifyMetadataPage(
        items: [item],
        total: 2,
        offset: 0,
        nextOffset: 1,
      );
      browser.publish();
      await tester.pump();
      await tester.ensureVisible(
        find.byTooltip('Elegir audio para Canción de prueba'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Elegir audio para Canción de prueba'));
      expect(selected, track);
      await tester.ensureVisible(find.text('Ver más resultados'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver más resultados'));
      expect(browser.moreCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collection details expose tracks and pagination without playback URLs',
    (tester) async {
      final browser = _FixtureBrowser();
      addTearDown(browser.dispose);
      const album = SpotifyMetadataEntity(
        type: SpotifyEntityType.album,
        uri: 'spotify:album:fixture',
        name: 'Álbum de prueba',
      );
      browser.detail = SpotifyMetadataDetails(
        entity: album,
        tracks: [track],
        total: 2,
        nextOffset: 1,
      );
      Track? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SpotifyBrowserPanel(
              browser: browser,
              onQueue: (value) async => selected = value,
            ),
          ),
        ),
      );
      await tester.ensureVisible(
        find.byTooltip('Elegir audio para Canción de prueba'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Elegir audio para Canción de prueba'));
      expect(selected?.pageUrl, isNull);
      expect(selected?.isPendingSpotifyMatch, isTrue);
      await tester.ensureVisible(find.text('Ver más canciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver más canciones'));
      expect(browser.moreDetailsCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _FixtureBrowser extends SpotifyBrowserController {
  int searchCalls = 0;
  int moreCalls = 0;
  int moreDetailsCalls = 0;
  void publish() => notifyListeners();
  @override
  Future<void> search(String value, {SpotifyEntityType? type}) async {
    searchCalls++;
  }

  @override
  Future<void> loadMore() async {
    moreCalls++;
  }

  @override
  Future<void> loadMoreDetails() async {
    moreDetailsCalls++;
  }
}
