import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track song(int n) => Track(
  id: 'yt:never${n.toString().padLeft(6, '0')}',
  title: 'Song $n',
  artist: 'Artist $n',
  pageUrl:
      'https://music.youtube.com/watch?v=never${n.toString().padLeft(6, '0')}',
  duration: const Duration(minutes: 3),
);

class _Engine extends SuggestionsApi {
  _Engine(this.behavior);
  final Future<List<Suggestion>> Function() behavior;
  int calls = 0;
  @override
  Future<List<Suggestion>> getSuggestions(SessionContext ctx) {
    calls++;
    return behavior();
  }
}

Future<void> eventually(bool Function() ok) async {
  for (var i = 0; i < 300; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('timeout');
}

void main() {
  late FakeAudio audio;

  Future<AppController> make(
    int size, {
    Future<List<Suggestion>> Function()? engine,
    Map<String, Object> prefs = const {},
  }) async {
    audio = FakeAudio();
    final app = await createTestController(
      tracks: [for (var i = 0; i < size; i++) song(i)],
      audio: audio,
      preferences: {'autoRefill': true, ...prefs},
    );
    addTearDown(() => closeTestController(app));
    if (engine != null) app.suggestionsApi = _Engine(engine);
    app.refillEngineTimeout = const Duration(milliseconds: 80);
    return app;
  }

  Future<void> finishTrack(AppController app) async {
    final before = app.currentTrack?.id;
    final queued = app.queueIndex;
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(
      () => app.queueIndex != queued || app.currentTrack?.id != before,
    );
  }

  Future<void> runWithDj(AppController app, {int songs = 10}) async {
    await app.toggleFavorite(app.tracks.first);
    await app.startPersonalDj();
    expect(app.personalDjActive, isTrue);
    for (var i = 0; i < songs; i++) {
      await finishTrack(app);
      expect(app.personalDjActive, isTrue, reason: 'DJ apagado en pista $i');
      expect(app.currentTrack, isNotNull);
      expect(audio.isPlaying, isTrue, reason: 'silencio en pista $i');
    }
  }

  test('DJ + biblioteca pequeña agotada: la cola no termina', () async {
    final app = await make(4);
    await runWithDj(app, songs: 10);
  });

  test('DJ + el motor lanza error: sigue y avisa sin apagar', () async {
    final app = await make(
      12,
      engine: () async => throw Exception('motor caído'),
    );
    await runWithDj(app);
  });

  test('DJ + el motor devuelve vacío', () async {
    final app = await make(6, engine: () async => const []);
    await runWithDj(app);
  });

  test('DJ + el motor se cuelga (timeout)', () async {
    final app = await make(
      6,
      engine: () => Completer<List<Suggestion>>().future,
    );
    await runWithDj(app, songs: 6);
    expect(app.personalDjActive, isTrue);
  });

  test('tocar un elemento de la cola no apaga el DJ', () async {
    final app = await make(12);
    await app.toggleFavorite(app.tracks.first);
    await app.startPersonalDj();
    await app.playQueueAt(1);
    expect(app.personalDjActive, isTrue);
  });

  test('cambios rápidos de pista con el DJ activo', () async {
    final app = await make(8);
    await app.toggleFavorite(app.tracks.first);
    await app.startPersonalDj();
    for (var i = 0; i < 12; i++) {
      await app.next();
    }
    expect(app.personalDjActive, isTrue);
    expect(app.currentTrack, isNotNull);
    expect(audio.isPlaying, isTrue);
  });

  test(
    'cola larga: rellena con menos de 5 por delante, no solo al final',
    () async {
      final app = await make(30);
      await app.playTrack(app.tracks[0], context: app.tracks.take(8).toList());
      await app.playQueueAt(5);
      await eventually(() => app.queue.length > 8);
      expect(app.queue.length - app.queueIndex - 1, greaterThanOrEqualTo(5));
    },
  );

  test('una sola pista en la biblioteca: se repite antes que callar', () async {
    final app = await make(1);
    await app.playTrack(app.tracks.first, context: [app.tracks.first]);
    await eventually(() => app.queue.length > 1);
    await finishTrack(app);
    expect(app.currentTrack, isNotNull);
    expect(audio.isPlaying, isTrue);
  });

  test('repeat-one y ajuste apagado siguen sin rellenar', () async {
    final app = await make(6, prefs: {'autoRefill': false});
    await app.playTrack(app.tracks.first, context: [app.tracks.first]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(app.queue.length, 1);
  });
}
