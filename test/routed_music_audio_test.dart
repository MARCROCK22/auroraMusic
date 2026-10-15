import 'package:aurora_music/audio/routed_music_audio.dart';
import 'package:aurora_music/core/audio_backend.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _SessionAudio extends FakeAudio {
  final mirrors = <AudioBackend?>[];
  final metadata = <String>[];
  @override
  Future<void> mirrorExternalPlayback(AudioBackend? playback) async =>
      mirrors.add(playback);
  @override
  Future<void> updateTrackMetadata(Track track) async => metadata.add(track.id);
}

class _AdAudio extends FakeAudio {
  @override
  bool adPlaying = false;
  @override
  bool get supportsEqualizer => false;
}

const _web = ResolvedAudio(
  input: 'https://music.youtube.com/watch?v=6geljA2OZSY',
  engine: AudioEngine.web,
);

const _proxy = ResolvedAudio(input: 'http://127.0.0.1:41000/tok/a/id');

void main() {
  test(
    'web playback and local playback share controls without overlapping',
    () async {
      final native = FakeAudio();
      final web = FakeAudio();
      final audio = RoutedMusicAudio(native: native, web: web);
      addTearDown(audio.dispose);
      await audio.initialize();
      await audio.load(const ResolvedAudio(input: '/library/local.mp3'));
      await audio.play();
      expect(native.isPlaying, isTrue);
      expect(web.loadCount, 0);

      await audio.load(_web);
      await audio.play();
      expect(native.isPlaying, isFalse);
      expect(web.isPlaying, isTrue);
      expect(audio.usingWeb, isTrue);
      expect(native.loadCount, 1);
      await audio.seek(const Duration(seconds: 30));
      expect(web.position.inSeconds, 30);
      await audio.pause();
      expect(web.isPlaying, isFalse);

      await audio.load(const ResolvedAudio(input: '/library/local.flac'));
      await audio.play();
      expect(audio.usingWeb, isFalse);
      expect(web.isPlaying, isFalse);
      expect(native.isPlaying, isTrue);
    },
  );

  test('only active engine completion advances Aurora queue', () async {
    final native = FakeAudio();
    final web = FakeAudio();
    final audio = RoutedMusicAudio(native: native, web: web);
    addTearDown(audio.dispose);
    var completions = 0;
    final subscription = audio.completed.listen((_) => completions++);
    addTearDown(subscription.cancel);
    await audio.load(_web);
    native.completions.add(null);
    web.completions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completions, 1);
    await audio.load(const ResolvedAudio(input: '/library/local.mp3'));
    native.completions.add(null);
    web.completions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(completions, 2);
  });

  test(
    'native session mirrors web playback and always gets metadata',
    () async {
      final native = _SessionAudio();
      final web = _AdAudio();
      final audio = RoutedMusicAudio(native: native, web: web);
      addTearDown(audio.dispose);
      const track = Track(id: 'yt:6geljA2OZSY', title: 'Canción', artist: 'A');
      await audio.updateTrackMetadata(track);
      await audio.load(_web);
      await audio.play();
      expect(native.mirrors.last, same(web));
      await audio.updateTrackMetadata(track);
      expect(native.metadata, ['yt:6geljA2OZSY', 'yt:6geljA2OZSY']);
      expect(audio.supportsEqualizer, isFalse);
      web.adPlaying = true;
      expect(audio.adPlaying, isTrue);

      await audio.load(const ResolvedAudio(input: '/library/local.mp3'));
      expect(native.mirrors.last, isNull);
      expect(audio.adPlaying, isFalse);
      expect(audio.supportsEqualizer, isTrue);
    },
  );

  test(
    'engine decides routing and the guard blocks raw YouTube URLs',
    () async {
      final native = FakeAudio();
      final web = FakeAudio();
      final audio = RoutedMusicAudio(native: native, web: web);
      addTearDown(audio.dispose);
      // A music.youtube.com URL with the native engine is never sent to web.
      await expectLater(
        audio.load(
          const ResolvedAudio(input: 'https://music.youtube.com/watch?v=abc'),
        ),
        throwsStateError,
      );
      await expectLater(
        audio.load(
          const ResolvedAudio(
            input: 'https://rr1.googlevideo.com/videoplayback',
          ),
        ),
        throwsStateError,
      );
      expect(native.loadCount + web.loadCount, 0);
      await audio.load(_proxy);
      expect(native.loadCount, 1);
      expect(audio.usingWeb, isFalse);
      await audio.load(_web);
      expect(web.loadCount, 1);
    },
  );

  test('web initialization failure keeps local playback usable', () async {
    final native = FakeAudio();
    final web = _FailingAudio();
    final audio = RoutedMusicAudio(native: native, web: web);
    addTearDown(audio.dispose);
    await audio.initialize();
    expect(audio.webInitializationError, contains('WebView2'));
    await expectLater(audio.load(_web), throwsStateError);
    await audio.load(const ResolvedAudio(input: '/library/local.mp3'));
    expect(native.loadCount, 1);
  });
}

class _FailingAudio extends FakeAudio {
  @override
  Future<void> initialize() async => throw StateError('sin WebView');
}
