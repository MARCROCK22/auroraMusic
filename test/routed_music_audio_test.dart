import 'package:aurora_music/audio/routed_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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

      await audio.load(
        const ResolvedAudio(
          input: 'https://music.youtube.com/watch?v=6geljA2OZSY',
        ),
      );
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
    await audio.load(
      const ResolvedAudio(
        input: 'https://music.youtube.com/watch?v=6geljA2OZSY',
      ),
    );
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
}
