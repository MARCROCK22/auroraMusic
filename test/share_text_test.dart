import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/track_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shareText añade enlace solo a pistas no locales', () {
    const t = Track(id: 'abc123', title: 'Canción', artist: 'Ana');
    expect(
      shareText(t),
      'Canción — Ana\nhttps://music.youtube.com/watch?v=abc123',
    );
    expect(
      shareText(
        const Track(id: 'x', title: 'A', artist: 'B', localPath: '/a.mp3'),
      ),
      'A — B',
    );
  });
}
