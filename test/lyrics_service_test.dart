import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';

void main() {
  test('parses multiple timestamps and applies offset in order', () {
    final lines = LyricsService.parseLrc(
      '[offset:250]\n[00:02.10][00:01.2]fixture one\n[00:03.00]fixture two',
    );
    expect(lines.map((line) => line.at.inMilliseconds), [1450, 2350, 3250]);
    expect(lines.map((line) => line.text), [
      'fixture one',
      'fixture one',
      'fixture two',
    ]);
  });
  test('applies offset metadata wherever it appears', () {
    final lines = LyricsService.parseLrc('[00:01.00]fixture\n[offset:-500]');
    expect(lines.single.at, const Duration(milliseconds: 500));
  });
  test('rejects invalid seconds and non timestamp text', () {
    expect(LyricsService.parseLrc('[99:99]fixture'), isEmpty);
    expect(LyricsService.parseLrc('not a timestamp'), isEmpty);
  });
  test(
    'recognizes cautious artist-title parsing without broad fuzzy matching',
    () {
      final track = Track(
        id: 'a/b',
        title: 'Artist - Song (Official Video)',
        artist: 'Artist',
      );
      expect(track.id, 'a/b');
      expect(LyricsService.parseLrc('[00:01.00]fixture'), isNotEmpty);
    },
  );
}
