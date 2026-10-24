import 'package:aurora_music/lastfm/lastfm_client.dart';
import 'package:aurora_music/lastfm/lastfm_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea top, recientes y total (números como texto)', () {
    final tracks = LfmParser.topTracks({
      'toptracks': {
        'track': [
          {
            'name': 'A',
            'playcount': '10',
            'artist': {'name': 'X'},
          },
          {
            'name': 'B',
            'playcount': '4',
            'artist': {'name': 'Y'},
          },
          {'bad': 1},
        ],
      },
    });
    expect(tracks.map((t) => t.name), ['A', 'B']);
    expect(tracks.first.count, 10);
    expect(tracks.first.subtitle, 'X');
    // una sola entrada llega como objeto
    expect(
      LfmParser.topArtists({
        'topartists': {
          'artist': {'name': 'Solo', 'playcount': '3'},
        },
      }).single.name,
      'Solo',
    );
    final recent = LfmParser.recent({
      'recenttracks': {
        'track': [
          {
            'name': 'Ahora',
            'artist': {'#text': 'X'},
            '@attr': {'nowplaying': 'true'},
          },
          {
            'name': 'Antes',
            'artist': {'#text': 'Y'},
            'date': {'uts': '1700000000'},
          },
        ],
      },
    });
    expect(recent.first.at, isNull);
    expect(recent.last.at, 1700000000);
    expect(
      LfmParser.playcount({
        'user': {'playcount': '1234'},
      }),
      1234,
    );
    expect(LfmParser.topTracks('basura'), isEmpty);
    expect(
      LfmParser.similarTracks({
        'similartracks': {
          'track': [
            {
              'name': 'S',
              'artist': {'name': 'Z'},
            },
          ],
        },
      }).single.artist,
      'Z',
    );
  });

  test('ListenStats se serializa y rechaza datos corruptos', () {
    const s = ListenStats(
      totalListens: 5,
      recordings: [StatItem('A', 3, subtitle: 'X')],
      artists: [StatItem('X', 3)],
      recent: [RecentItem('A', 'X', at: 1)],
    );
    final back = ListenStats.fromJson(s.toJson())!;
    expect(back.totalListens, 5);
    expect(back.recent.single.at, 1);
    expect(ListenStats.fromJson({'t': 'x'}), isNull);
  });

  test('userStats pide user.* con el periodo, por GET y sin firma', () async {
    final methods = <String>[];
    final client = LastfmClient(
      apiKey: 'k',
      secret: 'sec',
      transport: (r) async {
        final q = r.uri.queryParameters;
        methods.add('${q['method']}:${q['period']}');
        expect(r.method, 'GET');
        expect(q['user'], 'juan');
        expect(q.containsKey('api_sig'), isFalse);
        expect(r.uri.toString(), isNot(contains('sec')));
        return switch (q['method']) {
          'user.getTopTracks' => const LfmResponse(
            200,
            '{"toptracks":{"track":[{"name":"A","playcount":"2","artist":{"name":"X"}}]}}',
          ),
          'user.getInfo' => const LfmResponse(
            200,
            '{"user":{"playcount":"9"}}',
          ),
          _ => const LfmResponse(404, '{"error":6,"message":"x"}'),
        };
      },
    );
    final s = await client.userStats('juan', StatsRange.quarter);
    expect(s.totalListens, 9);
    expect(s.topTrack!.name, 'A');
    expect(s.artists, isEmpty);
    expect(methods, contains('user.getTopTracks:3month'));
  });
}
