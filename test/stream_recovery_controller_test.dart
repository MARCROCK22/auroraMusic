import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _first = Track(
  id: 'one',
  title: 'Uno',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/abcdefghijk',
);
const _second = Track(
  id: 'two',
  title: 'Dos',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/lmnopqrstuv',
);

class _FailingAudio extends FakeAudio {
  int failedLoadsRemaining = 0;

  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    if (failedLoadsRemaining > 0) {
      failedLoadsRemaining--;
      throw Exception('socket timeout');
    }
    await super.load(source, ffmpegExecutable: ffmpegExecutable, start: start);
  }
}

class _PendingAudio extends FakeAudio {
  final loadStarted = Completer<void>();
  final loadGate = Completer<void>();

  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    if (!loadStarted.isCompleted) loadStarted.complete();
    await loadGate.future;
    await super.load(source, ffmpegExecutable: ffmpegExecutable, start: start);
  }
}

Future<void> _settle(AppController controller) async {
  while (controller.busy) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

void main() {
  test(
    'premature EOF refreshes the same queue occurrence twice at position',
    () async {
      final source = FakeSource();
      final audio = FakeAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
        tracks: [_first, _second],
        preferences: {
          'queue': ['one', 'one', 'two'],
          'queueIndex': 1,
        },
      );
      addTearDown(() => closeTestController(controller));
      await controller.playQueueAt(1);
      audio.position = const Duration(seconds: 37);
      audio.lastError = 'El audio terminó antes de completar la reproducción.';
      audio.notifyListeners();
      await _settle(controller);

      expect(controller.queueIndex, 1);
      expect(controller.currentTrack?.id, 'one');
      expect(source.resolved, ['one', 'one']);
      expect(audio.position, const Duration(seconds: 37));
      expect(controller.error, isNull);
      audio.lastError = 'El audio terminó antes de completar la reproducción.';
      audio.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _settle(controller);
      expect(source.resolved, ['one', 'one', 'one']);
      expect(controller.error, isNull);
    },
  );

  test(
    'failed refresh retries automatically and later outage recovers',
    () async {
      final source = FakeSource();
      final audio = _FailingAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(_first);
      audio.position = const Duration(seconds: 24);
      audio.failedLoadsRemaining = 1;
      audio.lastError = 'SocketException: connection timed out';
      audio.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _settle(controller);
      expect(source.resolved, ['one', 'one', 'one']);
      expect(audio.position, const Duration(seconds: 24));
      expect(controller.error, isNull);

      // No retry is scheduled after exhausting the bounded incident budget.
      audio.lastError = 'SocketException: connection timed out';
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one', 'one']);
      expect(controller.error, 'SocketException: connection timed out');

      // A real 30 second advance resets the budget for a later outage.
      audio.position = const Duration(seconds: 54);
      audio.notifyListeners();
      audio.lastError = 'SocketException: connection timed out';
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one', 'one', 'one']);
      expect(controller.error, isNull);
    },
  );

  test('queue change while URL refresh is pending wins', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 18);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await controller.playQueueAt(1);
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await _settle(controller);

    expect(controller.queueIndex, 1);
    expect(controller.currentTrack?.id, 'two');
    expect(audio.loaded?.input, 'https://example.test/two');
  });

  test('stop cancels in-flight refresh', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 12);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await controller.stopPlayback();
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await _settle(controller);
    expect(audio.isPlaying, isFalse);
    expect(audio.position, Duration.zero);
    expect(source.resolved, ['one', 'one']);
  });

  test('pause cancels a refresh while source resolution is pending', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 12);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    while (source.resolved.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    await controller.togglePlayback();
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(audio.isPlaying, isFalse);
    expect(source.resolved, ['one', 'one']);
  });

  test('toggle pauses an initial load that is still busy', () async {
    final audio = _PendingAudio();
    final controller = await createTestController(audio: audio);
    addTearDown(() => closeTestController(controller));
    final starting = controller.playTrack(_first);
    await audio.loadStarted.future;

    await controller.togglePlayback();
    audio.loadGate.complete();
    await starting;

    expect(audio.isPlaying, isFalse);
    expect(audio.loadCount, 1);
  });

  test('pause cancels the bounded retry backoff', () async {
    final source = FakeSource();
    final audio = _FailingAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    audio.failedLoadsRemaining = 1;
    audio.lastError = 'SocketException: connection timed out';
    audio.notifyListeners();
    await _settle(controller);

    audio.lastError = 'SocketException: connection timed out';
    audio.notifyListeners();
    await controller.togglePlayback();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(source.resolved, ['one', 'one']);
    expect(audio.isPlaying, isFalse);
  });
}
