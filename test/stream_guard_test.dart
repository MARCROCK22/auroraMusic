import 'package:aurora_music/audio/audio_math.dart';
import 'package:aurora_music/audio/stream_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guard rejects raw YouTube hosts and allows loopback and files', () {
    for (final bad in [
      'https://music.youtube.com/watch?v=abcdefghijk',
      'https://youtube.com/watch?v=abcdefghijk',
      'https://youtu.be/abcdefghijk',
      'https://rr3---sn-x.googlevideo.com/videoplayback?id=1',
      'https://i.ytimg.com/vi/x/a.jpg',
      'https://yt3.ggpht.com/a',
      'https://YouTube.com/x',
    ]) {
      expect(() => assertNotRawYouTube(bad), throwsStateError, reason: bad);
    }
    for (final ok in [
      'http://127.0.0.1:4000/0123456789abcdef0123456789abcdef/a/0123456789abcdef',
      'http://127.0.0.1:4000/aurora-progressive/token',
      r'C:\Music\a.mp3',
      '/storage/emulated/0/a.mp3',
      'file:///a.mp3',
      'https://example.test/notyoutube.com',
      'https://evilyoutube.com/x',
    ]) {
      assertNotRawYouTube(ok);
    }
  });

  test('FFmpeg options: loopback http gets timeout/reconnect, no TLS flag', () {
    final loop = ffmpegHttpsOptions('http://127.0.0.1:4000/t/a/i');
    expect(loop, containsAllInOrder(['-rw_timeout', '15000000', '-reconnect']));
    expect(loop, isNot(contains('-tls_verify')));
    expect(
      ffmpegHttpsOptions('https://example.test/a'),
      contains('-tls_verify'),
    );
    expect(ffmpegHttpsOptions('http://example.test/a'), isEmpty);
    expect(ffmpegHttpsOptions('http://localhost:4000/a'), isEmpty);
    expect(ffmpegHttpsOptions('/music/a.mp3'), isEmpty);
  });
}
