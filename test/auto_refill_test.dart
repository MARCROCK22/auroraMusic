import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/queue_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

Track song(int n) => Track(
  id: 'yt:refill${n.toString().padLeft(6, '0')}',
  title: 'Song $n',
  artist: 'Artist $n',
  pageUrl:
      'https://music.youtube.com/watch?v=refill${n.toString().padLeft(6, '0')}',
  duration: const Duration(minutes: 3),
);

Future<void> eventually(bool Function() ok) async {
  for (var i = 0; i < 200; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure('timeout');
}

void main() {
  final library = [for (var i = 0; i < 12; i++) song(i)];
  late FakeAudio audio;

  Future<AppController> make({Map<String, Object> prefs = const {}}) async {
    audio = FakeAudio();
    final app = await createTestController(
      tracks: library,
      audio: audio,
      preferences: {'autoRefill': true, ...prefs},
    );
    addTearDown(() => closeTestController(app));
    return app;
  }

  test('cola que se agota: se rellena y la siguiente suena sola', () async {
    final app = await make();
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    expect(
      app.queue.length - app.queueIndex - 1,
      greaterThanOrEqualTo(kQueueLookahead),
    );
    expect(app.autoAddedIds, isNotEmpty);
    expect(app.autoAddedIds.contains(library[0].id), isFalse);
    final first = app.queue[1];
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(() => app.currentTrack?.id == first.id);
  });

  test('sin red: usa la biblioteca, sin repetir artista seguido', () async {
    final app = await make();
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    for (var i = 1; i < app.queue.length; i++) {
      expect(app.queue[i].artist, isNot(app.queue[i - 1].artist));
    }
  });

  test('repeat-one no rellena', () async {
    final app = await make();
    app.cycleRepeat();
    app.cycleRepeat();
    expect(app.repeat, RepeatMode.one);
    await app.playTrack(library[0], context: [library[0]]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, 1);
  });

  test('shuffle no rellena', () async {
    final app = await make();
    app.setShuffle(true);
    await app.playTrack(library[0], context: [library[0]]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, 1);
  });

  test('ajuste apagado no rellena', () async {
    final app = await make(prefs: {'autoRefill': false});
    expect(app.autoRefill, isFalse);
    await app.playTrack(library[0], context: [library[0]]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, 1);
    expect(app.autoAddedIds, isEmpty);
  });

  test('una cola larga armada a mano no se toca', () async {
    final app = await make();
    await app.playTrack(library[0], context: library);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, library.length);
    expect(app.autoAddedIds, isEmpty);
  });
}
