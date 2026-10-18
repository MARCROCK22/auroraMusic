import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/queue_policy.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:aurora_music/ui/spotify_auto_add.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_jam_backend.dart';
import 'support/fakes.dart';

Track yt(String name, {String? artist}) => Track(
  id: 'yt:play$name',
  title: 'Song $name',
  artist: artist ?? 'Artist $name',
  pageUrl: 'https://music.youtube.com/watch?v=play$name',
  duration: const Duration(minutes: 3),
);

Track spotify(String name) => Track(
  id: 'spotify:track:$name',
  title: 'Song $name',
  artist: 'Artist $name',
  duration: const Duration(minutes: 3),
  spotifyUri: 'spotify:track:$name',
  spotifyMatchPending: true,
);

class _Engine extends SuggestionsApi {
  _Engine(this.pick);
  final List<Track> Function(SessionContext) pick;
  Track? lastSeed;
  @override
  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async {
    lastSeed = ctx.current;
    return [
      for (final t in pick(ctx)) Suggestion(t, 'Radio de la semilla', ''),
    ];
  }
}

Future<void> eventually(bool Function() ok) async {
  for (var i = 0; i < 300; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('timeout');
}

List<String> ahead(AppController a) => [
  for (final t in a.queue.skip(a.queueIndex + 1)) t.title,
];

void main() {
  final radio = [
    for (var i = 0; i < 20; i++) yt('R${i.toString().padLeft(2, '0')}'),
  ];
  late FakeAudio audio;

  Future<AppController> make({
    List<Track> library = const [],
    Map<String, Object> prefs = const {},
    List<Track> Function(SessionContext)? engine,
  }) async {
    audio = FakeAudio();
    final app = await createTestController(
      tracks: library,
      audio: audio,
      preferences: {'autoRefill': true, ...prefs},
    );
    addTearDown(() => closeTestController(app));
    app.refillEngineTimeout = const Duration(milliseconds: 200);
    app.suggestionsApi = _Engine(engine ?? (_) => radio);
    return app;
  }

  test('tocar reproduce y la cola se rehace desde la semilla', () async {
    final app = await make();
    final seed = spotify('Seed');
    final ok = await app.playSpotifySeed(seed, yt('Seed'));
    expect(ok, isTrue);
    expect(app.currentTrack?.title, 'Song Seed');
    expect(app.currentTrack?.spotifyUri, 'spotify:track:Seed');
    expect(audio.loaded, isNotNull);
    await eventually(
      () => app.queue.length - app.queueIndex - 1 >= kQueueLookahead,
    );
    expect(
      (app.suggestionsApi as _Engine).lastSeed?.id,
      yt('Seed').id,
      reason: 'el motor recibe la pista tocada como semilla',
    );
    expect(app.autoAddedIds, isNotEmpty);
  });

  test('conserva historial y pistas manuales; reemplaza lo sugerido', () async {
    final app = await make();
    final h1 = yt('H1'), h2 = yt('H2'), manual = yt('Manual');
    final old = [for (var i = 0; i < 4; i++) yt('Old$i')];
    await app.playTrack(h1, context: [h1, h2, ...old]);
    await app.playQueueAt(1); // h2 suena; h1 ya sonó
    await app.addToQueue(manual);
    await eventually(() => app.queue.length > 6);
    final oldIds = {for (final t in old) t.id};
    expect(app.queue.any((t) => oldIds.contains(t.id)), isTrue);

    await app.playSpotifySeed(spotify('Seed'), yt('Seed'));
    await eventually(
      () => app.queue.length - app.queueIndex - 1 >= kQueueLookahead,
    );
    expect(app.queue.take(3).map((t) => t.title), [
      'Song H1',
      'Song H2',
      'Song Seed',
    ]);
    expect(app.queueIndex, 2);
    // Lo puesto a mano va primero; el contexto anterior ya no está.
    expect(ahead(app).first, 'Song Manual');
    expect(app.queue.any((t) => oldIds.contains(t.id)), isFalse);
    expect(app.manualQueuedIds, contains(manual.id));
    expect(ahead(app).skip(1).first, startsWith('Song R'));
  });

  test(
    'sin red: el motor falla y la cola cae al respaldo, nunca vacía',
    () async {
      final library = [for (var i = 0; i < 14; i++) yt('L$i')];
      final app = await make(
        library: library,
        engine: (_) => throw StateError('sin red'),
      );
      await app.playSpotifySeed(spotify('Seed'), yt('Seed'));
      await eventually(
        () => app.queue.length - app.queueIndex - 1 >= kQueueLookahead,
      );
      expect(ahead(app), everyElement(startsWith('Song L')));
      expect(audio.isPlaying, isTrue);
    },
  );

  test(
    '«Rellenar la cola» apagado: solo entra lo que ofrece la semilla',
    () async {
      final library = [for (var i = 0; i < 14; i++) yt('L$i')];
      final app = await make(
        library: library,
        prefs: {'autoRefill': false},
        engine: (_) => radio.take(3).toList(),
      );
      await app.playSpotifySeed(spotify('Seed'), yt('Seed'));
      await eventually(() => app.queue.length > 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(ahead(app), ['Song R00', 'Song R01', 'Song R02']);
    },
  );

  test('repeat-uno: no se reemplaza lo que viene', () async {
    final app = await make();
    final a = yt('A'), b = yt('B'), c = yt('C');
    await app.playTrack(a, context: [a, b, c]);
    app.cycleRepeat();
    app.cycleRepeat();
    expect(app.repeat, RepeatMode.one);
    await app.playSpotifySeed(spotify('Seed'), yt('Seed'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(app.queue.map((t) => t.title), [
      'Song A',
      'Song Seed',
      'Song B',
      'Song C',
    ]);
    expect(app.currentTrack?.title, 'Song Seed');
  });

  test(
    'álbum: la primera pista suena antes de terminar el lote y sigue en orden',
    () async {
      final app = await make();
      final gate = Completer<void>();
      Stream<List<(Track, Track)>> chunks() async* {
        yield [(spotify('B'), yt('B')), (spotify('C'), yt('C'))];
        await gate.future; // el lote no termina hasta que se libere
        yield [(spotify('D'), yt('D'))];
      }

      await app.playSpotifySeed(spotify('A'), yt('A'), context: chunks());
      expect(app.currentTrack?.title, 'Song A');
      expect(audio.isPlaying, isTrue);
      await eventually(() => ahead(app).length >= 2);
      expect(ahead(app), ['Song B', 'Song C']);
      gate.complete();
      await eventually(
        () => app.queue.length - app.queueIndex - 1 >= kQueueLookahead,
      );
      // Contexto en orden y después la radio de respaldo.
      expect(ahead(app).take(3), ['Song B', 'Song C', 'Song D']);
      expect(ahead(app)[3], startsWith('Song R'));
    },
  );

  test(
    'tras consumir pistas la cola vuelve a $kQueueLookahead por delante',
    () async {
      final library = [for (var i = 0; i < 40; i++) yt('Lib$i')];
      final app = await make(library: library, engine: (_) => const []);
      await app.playTrack(library[0], context: [library[0]]);
      int pending() => app.queue.length - app.queueIndex - 1;
      await eventually(() => pending() >= kQueueLookahead);
      for (var i = 0; i < 6; i++) {
        audio.position = audio.duration;
        audio.completions.add(null);
        final before = app.queueIndex;
        await eventually(() => app.queueIndex > before);
        await eventually(() => pending() >= kQueueLookahead);
      }
      expect(pending(), greaterThanOrEqualTo(kQueueLookahead));
    },
  );

  group('con Jam', () {
    Future<(AppController, JamController)> host(FakeJamBackend backend) async {
      final app = await make();
      final jam = JamController(app: app, transport: backend.transport());
      addTearDown(jam.dispose);
      await jam.hostOnline('Ana');
      return (app, jam);
    }

    SpotifyAutoAdder adderFor(
      JamController jam,
      List<String> played,
      AppController app,
    ) => SpotifyAutoAdder(
      matcher: YoutubeMatcher(
        persist: false,
        search: (q, kind) async => kind == SearchKind.songs ? [yt('Jam')] : [],
      ),
      save: (s, m, {next = false}) =>
          app.importSpotifyMetadataMatch(s, m, next: next),
      playSeed: (s, m, {context, extras}) async {
        played.add(m.id);
        return true;
      },
      queueLength: () => app.queue.length,
      unqueue: (_) {},
      manual: (t, {replacing}) async {},
      messenger: () => null,
      jam: () => jam,
    );

    test(
      'anfitrión: tocar añade al final de la Jam sin tocar la cola local',
      () async {
        final backend = FakeJamBackend();
        final (app, jam) = await host(backend);
        final played = <String>[];
        final local = app.queue.length;
        await adderFor(jam, played, app).play(
          Track(
            id: 'spotify:track:Jam',
            title: 'Song Jam',
            artist: 'Artist Jam',
            spotifyUri: 'spotify:track:Jam',
            spotifyMatchPending: true,
          ),
        );
        await eventually(
          () => jam.service.queue.any((e) => e.track.title == 'Song Jam'),
        );
        expect(played, isEmpty);
        expect(app.queue.length, local);
      },
    );

    test('invitado: tocar la deja al final de la cola compartida', () async {
      final backend = FakeJamBackend();
      final (_, hostJam) = await host(backend);
      final app = await make();
      final guest = JamController(app: app, transport: backend.transport());
      addTearDown(guest.dispose);
      await guest.join(hostJam.service.invite!.code, 'Beto');
      final played = <String>[];
      await adderFor(guest, played, app).play(
        Track(
          id: 'spotify:track:Jam',
          title: 'Song Jam',
          artist: 'Artist Jam',
          spotifyUri: 'spotify:track:Jam',
          spotifyMatchPending: true,
        ),
      );
      await eventually(
        () => hostJam.service.queue.any((e) => e.track.title == 'Song Jam'),
      );
      expect(played, isEmpty);
    });
  });

  test('la constante es la única fuente del objetivo', () {
    expect(kQueueLookahead, 10);
    expect(JamController.minAhead, kQueueLookahead);
    expect(djUpcomingTarget, greaterThanOrEqualTo(kQueueLookahead));
  });
}
