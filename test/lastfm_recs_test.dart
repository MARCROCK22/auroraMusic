import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/lastfm/lastfm_client.dart';
import 'package:aurora_music/lastfm/lastfm_recs.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:flutter_test/flutter_test.dart';

const _similar =
    '{"similartracks":{"track":[{"name":"Canción Uno","artist":{"name":"Banda Uno"}},{"name":"Canción Dos","artist":{"name":"Banda Dos"}}]}}';

Track _yt(String title, String artist, int seconds) => Track(
  id: 'yt:${title.hashCode.toRadixString(36).padRight(11, 'x').substring(0, 11)}',
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
  pageUrl: 'https://music.youtube.com/watch?v=x',
);

const _now = Track(id: 'n', title: 'Actual', artist: 'Banda Cero');
SessionContext get _ctx =>
    const SessionContext(participants: [], seed: 1, current: _now);

void main() {
  late List<Uri> calls;
  late Map<String, LfmResponse> routes;
  late LastfmRecsSource src;
  var on = true;

  setUp(() {
    calls = [];
    routes = {'track.getSimilar': const LfmResponse(200, _similar)};
    on = true;
    src = LastfmRecsSource(
      client: LastfmClient(
        apiKey: 'k',
        secret: 's',
        transport: (r) async {
          calls.add(r.uri);
          final m = r.uri.queryParameters['method'];
          return routes[m] ?? const LfmResponse(404, '');
        },
      ),
      matcher: YoutubeMatcher(
        search: (q, k) async => [
          _yt('Canción Uno', 'Banda Uno', 200),
          _yt('Canción Dos', 'Banda Dos', 180),
        ],
        persist: false,
      ),
      enabled: () => on,
    );
  });

  test(
    'similares → candidatos de YouTube con prior bajo y cubo lastfm',
    () async {
      final out = await src.fetch(_ctx, 6);
      expect(out, isNotEmpty);
      for (final c in out) {
        expect(c.bucket, RecBucket.lastfm);
        expect(c.reason, 'Recomendado por Last.fm');
        expect(c.prior, inInclusiveRange(0.01, 0.4));
      }
      expect(src.source.bucket, RecBucket.lastfm);
      expect(defaultRecMix[RecBucket.lastfm]!, lessThan(0.15));
    },
  );

  test('sin similares de pista usa artistas similares y sus top', () async {
    routes['track.getSimilar'] = const LfmResponse(200, '{"similartracks":{}}');
    routes['artist.getSimilar'] = const LfmResponse(
      200,
      '{"similarartists":{"artist":[{"name":"Banda Uno"}]}}',
    );
    routes['artist.getTopTracks'] = const LfmResponse(
      200,
      '{"toptracks":{"track":[{"name":"Canción Uno","playcount":"5"}]}}',
    );
    expect(await src.fetch(_ctx, 6), isNotEmpty);
  });

  test('apagado: ninguna petición; fallos y 29: vacío y bloqueo', () async {
    on = false;
    expect(await src.fetch(_ctx, 6), isEmpty);
    expect(calls, isEmpty);
    on = true;
    routes['track.getSimilar'] = const LfmResponse(
      429,
      '{"error":29,"message":"limit"}',
    );
    expect(await src.fetch(_ctx, 6), isEmpty);
    final n = calls.length;
    expect(await src.fetch(_ctx, 6), isEmpty);
    expect(calls.length, n);
  });

  test('artistas saltados no se ofrecen', () async {
    final out = await src.fetch(
      const SessionContext(
        participants: [],
        seed: 1,
        current: _now,
        skippedArtists: {'banda uno', 'banda dos'},
      ),
      6,
    );
    expect(out, isEmpty);
  });
}
