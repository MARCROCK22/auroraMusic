import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('Jam audio never advances or persists the personal queue', () async {
    final audio = FakeAudio();
    final app = await createTestController(audio: audio);
    addTearDown(() => closeTestController(app));
    const first = Track(
      id: 'first',
      title: 'First',
      artist: 'Artist',
      pageUrl: 'https://youtu.be/first',
    );
    const second = Track(
      id: 'second',
      title: 'Second',
      artist: 'Artist',
      pageUrl: 'https://youtu.be/second',
    );
    await app.playTrack(first, context: [first, second]);
    await app.seek(const Duration(seconds: 12));
    final savedPosition = app.preferences.getInt('position');
    await Future.wait([app.beginJamPlayback(), app.beginJamPlayback()]);
    expect(app.jamPlaybackActive, isTrue);
    await audio.seek(const Duration(seconds: 80));
    await audio.play();
    audio.position = audio.duration;
    audio.completions.add(null);
    await Future<void>.delayed(Duration.zero);
    await app.persistSession();
    await app.next();
    await app.previous();
    await app.playTrack(second);
    await app.togglePlayback();
    await app.pausePlayback();
    await app.stopPlayback();
    await app.seek(Duration.zero);
    expect(app.currentTrack?.id, first.id);
    expect(app.queue.map((track) => track.id), [first.id, second.id]);
    expect(app.preferences.getInt('position'), savedPosition);
    expect(audio.position, audio.duration);
    expect(audio.isPlaying, isTrue);
    await app.endJamPlayback();
    expect(app.jamPlaybackActive, isFalse);
    expect(audio.isPlaying, isFalse);
    await app.resumePlayback();
    expect(app.currentTrack?.id, first.id);
    expect(audio.position, const Duration(seconds: 12));
    expect(audio.isPlaying, isTrue);
  });
}
