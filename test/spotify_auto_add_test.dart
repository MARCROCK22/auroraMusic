import 'dart:async';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/metadata/spotify/spotify_browser_controller.dart';
import 'package:aurora_music/metadata/spotify/spotify_metadata_provider.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:aurora_music/ui/spotify_auto_add.dart';
import 'package:aurora_music/ui/spotify_browser_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Track sp(String title) => Track(
  id: 'spotify:track:$title',
  title: title,
  artist: 'Artista de prueba',
  spotifyUri: 'spotify:track:$title',
  spotifyMatchPending: true,
);

Track yt(String id, String title) => Track(
  id: 'yt:$id',
  title: title,
  artist: 'Artista de prueba',
  pageUrl: 'https://music.youtube.com/watch?v=$id',
);

class _Rig {
  _Rig(Map<String, List<Track>> results)
    : matcher = YoutubeMatcher(
        persist: false,
        search: (q, kind) async {
          searches++;
          await gate?.future;
          return kind == SearchKind.songs
              ? results[q.split(' ').first] ?? []
              : [];
        },
      ) {
    adder = SpotifyAutoAdder(
      matcher: matcher,
      save: (spotify, match, {next = false}) async {
        if (!queue.contains(match.id)) {
          next ? queue.insert(0, match.id) : queue.add(match.id);
        }
        return true;
      },
      playSeed: (spotify, match, {context, extras}) async {
        played.add(match.id);
        playedContext = context;
        return true;
      },
      queueLength: () => queue.length,
      unqueue: queue.remove,
      manual: (track, {replacing}) async {
        manualFor = track;
        manualReplacing = replacing;
      },
      messenger: () => messenger.currentState,
    );
  }
  static int searches = 0;
  static Completer<void>? gate;
  final YoutubeMatcher matcher;
  late final SpotifyAutoAdder adder;
  final queue = <String>[], played = <String>[];
  Stream<List<(Track, Track)>>? playedContext;
  final messenger = GlobalKey<ScaffoldMessengerState>();
  Track? manualFor, manualReplacing;

  Future<void> pump(WidgetTester tester, SpotifyBrowserController browser) =>
      tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          home: Scaffold(
            body: SpotifyBrowserPanel(browser: browser, adder: adder),
          ),
        ),
      );
}

class _Browser extends SpotifyBrowserController {
  void show(List<Track> tracks, {bool album = false}) {
    if (album) {
      detail = SpotifyMetadataDetails(
        entity: const SpotifyMetadataEntity(
          type: SpotifyEntityType.album,
          uri: 'spotify:album:a',
          name: 'Álbum',
        ),
        tracks: tracks,
        total: tracks.length,
        nextOffset: null,
      );
    } else {
      page = SpotifyMetadataPage(
        items: [
          for (final t in tracks)
            SpotifyMetadataEntity(
              type: SpotifyEntityType.track,
              uri: t.id,
              name: t.title,
              subtitle: t.artist,
              track: t,
            ),
        ],
        total: tracks.length,
        offset: 0,
        nextOffset: null,
      );
    }
    notifyListeners();
  }
}

void main() {
  setUp(() {
    _Rig.searches = 0;
    _Rig.gate = null;
  });

  testWidgets('un toque REPRODUCE (no añade) y muestra la ayuda nueva', (
    tester,
  ) async {
    final rig = _Rig({
      'Uno': [yt('aaaaaaaaaa1', 'Uno')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Uno')]);
    await rig.pump(tester, browser);
    expect(find.textContaining('Toca una canción para reproducirla'), findsOne);
    await tester.tap(find.text('Uno'));
    await tester.pumpAndSettle();
    expect(rig.played, ['yt:aaaaaaaaaa1']);
    expect(rig.queue, isEmpty);
  });

  testWidgets('empareja y reproduce mientras muestra «Buscando versión…»', (
    tester,
  ) async {
    final rig = _Rig({
      'Uno': [yt('aaaaaaaaaa1', 'Uno')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Uno')]);
    await rig.pump(tester, browser);
    _Rig.gate = Completer<void>();
    final done = rig.adder.play(sp('Uno'));
    await tester.pump();
    expect(find.textContaining('Buscando versión…'), findsOneWidget);
    _Rig.gate!.complete();
    await done;
    await tester.pumpAndSettle();
    expect(find.textContaining('Buscando versión…'), findsNothing);
  });

  testWidgets('menú ⋯: a continuación y «+» solo encolan, no reproducen', (
    tester,
  ) async {
    final rig = _Rig({
      'Uno': [yt('aaaaaaaaaa1', 'Uno')],
      'Dos': [yt('aaaaaaaaaa2', 'Dos')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Uno'), sp('Dos')]);
    await rig.pump(tester, browser);
    await tester.tap(find.byTooltip('Más opciones de Dos'));
    await tester.pumpAndSettle();
    expect(find.text('Reproducir a continuación'), findsOneWidget);
    await tester.tap(find.text('Reproducir a continuación'));
    await tester.pumpAndSettle();
    expect(rig.queue, ['yt:aaaaaaaaaa2']);
    expect(find.textContaining('Sonará a continuación'), findsOneWidget);
    await tester.tap(find.byTooltip('Añadir a la cola: Uno'));
    await tester.pumpAndSettle();
    expect(rig.queue, ['yt:aaaaaaaaaa2', 'yt:aaaaaaaaaa1']);
    expect(rig.played, isEmpty);
  });

  testWidgets('álbum: tocar una pista pasa el resto en orden como contexto', (
    tester,
  ) async {
    final rig = _Rig({
      for (final n in ['A', 'B', 'C', 'D', 'E', 'F'])
        n: [yt('eeeeeeeeee$n', n)],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([for (final n in 'ABCDEF'.split('')) sp(n)], album: true);
    await rig.pump(tester, browser);
    await tester.ensureVisible(find.text('B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(rig.played, ['yt:eeeeeeeeeeB']);
    final chunks = await rig.playedContext!.toList();
    // Tandas de 4 (C D E F) en el orden del álbum.
    expect(chunks.first.map((p) => p.$1.title), ['C', 'D', 'E', 'F']);
    expect(chunks.expand((c) => c).map((p) => p.$2.id).toList(), [
      for (final n in 'CDEF'.split('')) 'yt:eeeeeeeeee$n',
    ]);
  });

  testWidgets('un toque empareja solo, confirma y permite deshacer', (
    tester,
  ) async {
    final rig = _Rig({
      'Uno': [yt('aaaaaaaaaa1', 'Uno')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Uno')]);
    await rig.pump(tester, browser);
    expect(
      find.textContaining('Toca una canción para reproducirla'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Añadir a la cola: Uno'));
    await tester.pumpAndSettle();
    expect(rig.queue, ['yt:aaaaaaaaaa1']);
    expect(find.text('Añadida: Uno · Artista de prueba'), findsOneWidget);
    await tester.tap(find.text('Deshacer'));
    await tester.pumpAndSettle();
    expect(rig.queue, isEmpty);
    // La segunda vez sale de la caché: ninguna búsqueda nueva.
    final before = _Rig.searches;
    await tester.tap(find.byTooltip('Añadir a la cola: Uno'));
    await tester.pumpAndSettle();
    expect(_Rig.searches, before);
    expect(rig.queue, hasLength(1));
  });

  testWidgets('confianza baja: añade igual, avisa y «Cambiar» abre el manual', (
    tester,
  ) async {
    final rig = _Rig({
      'Dos': [yt('bbbbbbbbbb1', 'Dos (Live)')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Dos')]);
    await rig.pump(tester, browser);
    await tester.tap(find.text('Dos'));
    await tester.pumpAndSettle();
    expect(rig.played, ['yt:bbbbbbbbbb1']);
    expect(find.textContaining('Coincidencia dudosa'), findsOneWidget);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(rig.manualFor?.title, 'Dos');
    await tester.tap(find.byTooltip('Añadir a la cola: Dos'));
    await tester.pumpAndSettle();
    expect(rig.queue, ['yt:bbbbbbbbbb1']);
    await tester.tap(find.text('Cambiar'));
    await tester.pumpAndSettle();
    expect(rig.manualReplacing?.id, 'yt:bbbbbbbbbb1');
  });

  testWidgets('sin coincidencia: mensaje claro y búsqueda a mano', (
    tester,
  ) async {
    final rig = _Rig({});
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('Tres')]);
    await rig.pump(tester, browser);
    await tester.tap(find.text('Tres'));
    await tester.pumpAndSettle();
    expect(rig.queue, isEmpty);
    expect(rig.played, isEmpty);
    expect(find.textContaining('Sin coincidencia en YouTube'), findsOneWidget);
    await tester.tap(find.text('Buscar a mano'));
    expect(rig.manualFor?.title, 'Tres');
  });

  testWidgets('álbum: añadir todo omite sin coincidencia y resume', (
    tester,
  ) async {
    final rig = _Rig({
      'A': [yt('cccccccccc1', 'A')],
      'B': [yt('cccccccccc2', 'B')],
    });
    final browser = _Browser();
    addTearDown(browser.dispose);
    browser.show([sp('A'), sp('B'), sp('Z')], album: true);
    await rig.pump(tester, browser);
    await tester.tap(find.text('Añadir todo a la cola'));
    await tester.pumpAndSettle();
    expect(rig.queue, ['yt:cccccccccc1', 'yt:cccccccccc2']);
    expect(
      find.text('Añadidas 2 de 3 a la cola · 1 sin coincidencia'),
      findsOneWidget,
    );
    expect(rig.adder.batch, isNull);
  });

  test('lote: progreso visible y cancelación no añade nada', () async {
    final rig = _Rig({
      for (final n in ['A', 'B', 'C', 'D']) n: [yt('dddddddddd$n', n)],
    });
    final seen = <int>[];
    rig.adder.addListener(() {
      final b = rig.adder.batch;
      if (b != null) {
        seen.add(b.done);
        if (b.done >= 1) rig.adder.cancelBatch();
      }
    });
    await rig.adder.addAll('Lista', [for (final n in 'ABCD'.split('')) sp(n)]);
    expect(seen, isNotEmpty);
    expect(rig.queue, isEmpty);
    expect(rig.adder.batch, isNull);
  });

  test('sin matcher delega en el diálogo manual', () async {
    Track? manual;
    final adder = SpotifyAutoAdder(
      save: (_, _, {next = false}) async => true,
      playSeed: (_, _, {context, extras}) async => true,
      queueLength: () => 0,
      unqueue: (_) {},
      manual: (t, {replacing}) async => manual = t,
      messenger: () => null,
    );
    await adder.add(sp('X'));
    expect(manual?.title, 'X');
  });
}
