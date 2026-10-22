import 'package:aurora_music/listenbrainz/lb_stats.dart';
import 'package:aurora_music/listenbrainz/listenbrainz_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parsea grabaciones, artistas y géneros', () {
    final rec = {
      'payload': {
        'recordings': [
          {
            'track_name': 'A',
            'artist_name': 'X',
            'listen_count': 10,
            'recording_mbid': 'm1',
          },
          {'track_name': 'B', 'artist_name': 'Y', 'listen_count': 4},
          {'bad': 1},
        ],
      },
    };
    final recs = LbStatsParser.recordings(rec);
    expect(recs.map((e) => e.name), ['A', 'B']);
    expect(recs.first.subtitle, 'X');
    final mbids = LbStatsParser.recordingMbids(rec);
    expect(mbids, ['m1', null]);
    final genres = LbStatsParser.genres(recs, mbids, {
      'm1': ['Rock', 'indie'],
    });
    expect(genres.first.name, 'rock');
    expect(genres.first.count, 10);
    expect(
      LbStatsParser.artists({
        'payload': {
          'artists': [
            {'artist_name': 'X', 'listen_count': 7},
          ],
        },
      }).single.count,
      7,
    );
  });

  test('actividad, hora favorita, racha y total', () {
    final day = {
      'payload': {
        'daily_activity': {
          'Monday': [
            {'hour': 3, 'listen_count': 2},
            {'hour': 21, 'listen_count': 5},
          ],
          'Tuesday': [
            {'hour': 21, 'listen_count': 1},
          ],
        },
      },
    };
    final stats = ListenStats(hourly: LbStatsParser.hourly(day));
    expect(stats.favoriteHour, 21);
    expect(LbStatsParser.streak([0, 2, 3, 1, 0]), 3);
    expect(LbStatsParser.streak([1, 0, 2]), 1);
    expect(
      LbStatsParser.listenCount({
        'payload': {'count': 42},
      }),
      42,
    );
    expect(LbStatsParser.recordings('basura'), isEmpty);
    expect(const ListenStats().favoriteHour, isNull);
  });

  test('JSON de caché ida y vuelta', () {
    final s = ListenStats(
      totalListens: 5,
      recordings: const [StatItem('A', 3, subtitle: 'X')],
      hourly: List.filled(24, 1),
      activity: const [1, 2],
    );
    final back = ListenStats.fromJson(s.toJson())!;
    expect(back.topTrack!.subtitle, 'X');
    expect(back.totalListens, 5);
    expect(ListenStats.fromJson({'t': 'x'}), isNull);
  });

  test('userStats pide los endpoints y el token va en la cabecera', () async {
    final paths = <String>[];
    final client = ListenBrainzClient(
      transport: (r) async {
        paths.add(r.uri.path);
        expect(r.uri.toString().contains('tok-secret'), isFalse);
        expect(r.headers['Authorization'], 'Token tok-secret');
        if (r.uri.path.endsWith('/recordings')) {
          return const LbResponse(
            200,
            '{"payload":{"recordings":[{"track_name":"A","artist_name":"X","listen_count":2}]}}',
          );
        }
        if (r.uri.path.endsWith('/listen-count')) {
          return const LbResponse(200, '{"payload":{"count":9}}');
        }
        return const LbResponse(204, '');
      },
    );
    final s = await client.userStats('juan', StatsRange.month, 'tok-secret');
    expect(s.totalListens, 9);
    expect(s.topTrack!.name, 'A');
    expect(s.topGenre, isNull);
    expect(paths.any((p) => p.endsWith('/daily-activity')), isTrue);
  });
}
