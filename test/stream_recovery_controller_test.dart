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
  bool failNextLoad = false;

  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    if (failNextLoad) {
      failNextLoad = false;
      throw Exception('socket timeout');
    }
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
    'premature EOF refreshes URL once at position on same queue occurrence',
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
      audio.lastError = 'El audio terminó antes de completar la reproducción.';
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one']);
    },
  );

  test(
    'network read timeout recovery is bounded and manual retry reloads position',
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
      audio.failNextLoad = true;
      audio.lastError = 'SocketException: connection timed out';
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one']);

      audio.lastError = 'SocketException: connection timed out';
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one']);

      audio.position = Duration.zero;
      await controller.resumePlayback();
      expect(source.resolved, ['one', 'one', 'one']);
      expect(audio.position, const Duration(seconds: 24));
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
}
