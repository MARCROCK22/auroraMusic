import 'package:aurora_music/youtube_music/youtube_music_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('allows only exact official HTTPS origins', () {
    for (final value in [
      'https://music.youtube.com/',
      'https://music.youtube.com:443/watch?v=example',
      'https://consent.youtube.com/m?continue=https%3A%2F%2Fmusic.youtube.com',
      'https://consent.google.com/',
    ]) {
      expect(
        classifyYouTubeMusicNavigation(Uri.parse(value)),
        YouTubeMusicNavigation.allow,
        reason: value,
      );
    }
  });

  test('Google accounts uses external browser without embedded login', () {
    expect(
      classifyYouTubeMusicNavigation(
        Uri.parse('https://accounts.google.com/ServiceLogin'),
      ),
      YouTubeMusicNavigation.signInInBrowser,
    );
  });

  test(
    'blocks non-HTTPS, spoofed hosts, credentials and nonstandard ports',
    () {
      expect(
        classifyYouTubeMusicNavigation(null),
        YouTubeMusicNavigation.block,
      );
      for (final value in [
        'http://music.youtube.com/',
        'https://music.youtube.com.evil.example/',
        'https://evilmusic.youtube.com/',
        'https://music.youtube.com@evil.example/',
        'https://user:password@music.youtube.com/',
        'https://music.youtube.com:444/',
        'https://music.youtube.com./',
        'https://accounts.google.com.evil.example/',
        'http://accounts.google.com/',
        'https://www.youtube.com/',
        'https://youtube.com/',
        'https://google.com/',
        'javascript:alert(1)',
        'data:text/html,example',
        'file:///example',
        'intent://music.youtube.com/',
        'about:blank',
        '//music.youtube.com/',
        '/watch?v=example',
      ]) {
        expect(
          classifyYouTubeMusicNavigation(Uri.parse(value)),
          YouTubeMusicNavigation.block,
          reason: value,
        );
      }
    },
  );
}
