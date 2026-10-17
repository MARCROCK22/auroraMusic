import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:flutter_test/flutter_test.dart';

Track sp(String title, String artist, int secs, {String? album}) => Track(
  id: 'spotify:track:${title.hashCode.abs().toString().padLeft(22, '0')}',
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: secs),
  spotifyUri:
      'spotify:track:${title.hashCode.abs().toString().padLeft(22, '0')}',
  spotifyMatchPending: true,
);

Track yt(String id, String title, String artist, int secs, {String? album}) =>
    Track(
      id: 'yt:$id',
      title: title,
      artist: artist,
      album: album,
      duration: Duration(seconds: secs),
      pageUrl: 'https://music.youtube.com/watch?v=$id',
    );

void main() {
  final blinding = sp(
    'Blinding Lights',
    'The Weeknd',
    200,
    album: 'After Hours',
  );

  test('prefiere la versión de estudio frente a live, sped up y cover', () {
    final cands = [
      yt('aaaaaaaaaa1', 'Blinding Lights (Live)', 'The Weeknd', 262),
      yt('aaaaaaaaaa2', 'Blinding Lights (Sped Up)', 'The Weeknd', 160),
      yt('aaaaaaaaaa3', 'Blinding Lights cover', 'Some Band', 201),
      yt(
        'aaaaaaaaaa4',
        'Blinding Lights',
        'The Weeknd',
        201,
        album: 'After Hours',
      ),
    ];
    cands.sort(
      (a, b) => scoreYoutubeMatch(
        blinding,
        b,
      ).compareTo(scoreYoutubeMatch(blinding, a)),
    );
    expect(cands.first.id, 'yt:aaaaaaaaaa4');
    expect(scoreYoutubeMatch(blinding, cands.first), greaterThan(0.9));
    expect(scoreYoutubeMatch(blinding, cands[1]), lessThan(0.62));
  });

  test('ignora feat y paréntesis del título de Spotify', () {
    final s = sp(
      'Despacito (feat. Daddy Yankee)',
      'Luis Fonsi, Daddy Yankee',
      229,
    );
    final c = yt('bbbbbbbbbb1', 'Despacito', 'Luis Fonsi, Daddy Yankee', 229);
    expect(scoreYoutubeMatch(s, c), greaterThan(0.9));
  });

  test('remaster en el título no penaliza', () {
    final s = sp('Bohemian Rhapsody - Remastered 2011', 'Queen', 355);
    final c = yt('cccccccccc1', 'Bohemian Rhapsody', 'Queen', 354);
    expect(scoreYoutubeMatch(s, c), greaterThan(0.9));
  });

  test('live solo vale si el original también lo es', () {
    final s = sp('Hotel California - Live', 'Eagles', 400);
    final c = yt('dddddddddd1', 'Hotel California (Live)', 'Eagles', 398);
    expect(scoreYoutubeMatch(s, c), greaterThan(0.9));
  });

  test('duración muy distinta baja bajo el umbral; ±3 s no cuesta nada', () {
    final s = sp('Song X', 'Artist Y', 180);
    final far = yt('eeeeeeeeee1', 'Song X', 'Artist Y', 230);
    final near = yt('eeeeeeeeee2', 'Song X', 'Artist Y', 182);
    expect(scoreYoutubeMatch(s, far), lessThan(0.62));
    expect(scoreYoutubeMatch(s, near), greaterThan(0.9));
  });

  test('mismo título con otro artista se rechaza', () {
    final c = yt('ffffffffff1', 'Blinding Lights', 'Karaoke Hits', 200);
    expect(scoreYoutubeMatch(blinding, c), lessThan(0.4));
  });

  test('Topic y artista dentro del título cuentan', () {
    final s = sp('Creep', 'Radiohead', 238);
    final topic = yt('gggggggggg1', 'Creep', 'Radiohead - Topic', 239);
    final inTitle = yt('gggggggggg2', 'Radiohead - Creep', 'Canal X', 238);
    expect(scoreYoutubeMatch(s, topic), greaterThan(0.9));
    expect(scoreYoutubeMatch(s, inTitle), greaterThan(0.62));
  });

  group('YoutubeMatcher', () {
    test('elige el mejor, cachea aciertos y fallos, cae a vídeos', () async {
      var calls = 0;
      final kinds = <SearchKind>[];
      final matcher = YoutubeMatcher(
        persist: false,
        search: (q, kind) async {
          calls++;
          kinds.add(kind);
          return kind == SearchKind.songs
              ? [yt('hhhhhhhhhh1', 'Blinding Lights (Live)', 'The Weeknd', 262)]
              : [yt('hhhhhhhhhh2', 'Blinding Lights', 'The Weeknd', 200)];
        },
      );
      final m = await matcher.match(blinding);
      expect(m!.track.id, 'yt:hhhhhhhhhh2');
      expect(m.confidence, greaterThan(0.62));
      expect(kinds, [SearchKind.songs, SearchKind.videos]);
      await matcher.match(blinding);
      expect(calls, 2, reason: 'la segunda vez sale de la caché');

      final miss = YoutubeMatcher(
        persist: false,
        search: (q, k) async {
          calls++;
          return [yt('iiiiiiiiii1', 'Otra cosa', 'Nadie', 10)];
        },
      );
      expect(await miss.match(blinding), isNull);
      final before = calls;
      expect(await miss.match(blinding), isNull);
      expect(calls, before, reason: 'el fallo también se cachea');
    });

    test('sin red devuelve null', () async {
      final m = YoutubeMatcher(
        persist: false,
        search: (q, k) async => throw Exception('sin red'),
      );
      expect(await m.match(blinding), isNull);
    });
  });
}
