import 'dart:convert';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/listenbrainz/lb_recs.dart';
import 'package:aurora_music/listenbrainz/listenbrainz_client.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:flutter_test/flutter_test.dart';

const secret = '11111111-2222-3333-4444-555555555555';
const mbidA = 'aaaaaaaa-0000-0000-0000-000000000001';
const mbidB = 'bbbbbbbb-0000-0000-0000-000000000002';
const listMbid = 'cccccccc-0000-0000-0000-000000000003';

const _created =
    '{"playlists":[{"playlist":{"identifier":"https://listenbrainz.org/playlist/$listMbid","title":"Daily Jams"}}]}';
final _jspf = jsonEncode({
  'playlist': {
    'track': [
      {
        'identifier': ['https://musicbrainz.org/recording/$mbidA'],
        'title': 'Canción Uno',
        'creator': 'Banda Uno',
        'album': 'Disco',
        'duration': 200000,
      },
      {
        'identifier': ['https://musicbrainz.org/recording/$mbidB'],
        'title': 'Canción Dos',
        'creator': 'Banda Dos',
        'duration': 180000,
      },
    ],
  },
});

class Net {
  final requests = <LbRequestData>[];
  final routes = <String, LbResponse Function()>{};
  Future<LbResponse> call(LbRequestData r) async {
    requests.add(r);
    for (final e in routes.entries) {
      if (r.uri.path.contains(e.key)) return e.value();
    }
    return const LbResponse(404, '');
  }
}

Track _yt(String title, String artist, int seconds) => Track(
  id: 'yt:${title.hashCode.toRadixString(36).padRight(11, 'x').substring(0, 11)}',
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
  pageUrl: 'https://music.youtube.com/watch?v=x',
);

SessionContext get _ctx => const SessionContext(participants: [], seed: 1);

void main() {
  late Net net;
  late LbRecsSource build;
  var on = true;
  var searches = 0;
  List<Track> Function(String) found = (_) => const [];

  setUp(() {
    net = Net()
      ..routes['/playlists/createdfor'] = (() =>
          const LbResponse(200, _created))
      ..routes['/1/playlist/'] = (() => LbResponse(200, _jspf));
    on = true;
    searches = 0;
    found = (q) => [
      _yt('Canción Uno', 'Banda Uno', 200),
      _yt('Canción Dos', 'Banda Dos', 180),
    ];
    build = LbRecsSource(
      client: ListenBrainzClient(transport: net.call),
      matcher: YoutubeMatcher(
        search: (q, k) async {
          searches++;
          return found(q);
        },
        persist: false,
      ),
      readToken: () async => secret,
      userName: () => 'ana',
      enabled: () => on,
      pause: Duration.zero,
    );
  });

  test(
    'listas Created for You → candidatos de YouTube con prior bajo',
    () async {
      final out = await build.fetch(_ctx, 6);
      expect(out, isNotEmpty);
      for (final c in out) {
        expect(c.bucket, RecBucket.listenbrainz);
        expect(c.prior, lessThanOrEqualTo(0.4));
        expect(c.prior, greaterThan(0));
        expect(c.track.pageUrl, isNotNull);
      }
      for (final r in net.requests) {
        expect(r.uri.toString(), isNot(contains(secret)));
        expect(r.headers['Authorization'], 'Token $secret');
      }
    },
  );

  test('la fuente se registra en su cubo con cuota pequeña', () {
    expect(build.source.bucket, RecBucket.listenbrainz);
    expect(defaultRecMix[RecBucket.listenbrainz]!, lessThan(0.15));
  });

  test('apagado o sin token: ninguna petición', () async {
    on = false;
    expect(await build.fetch(_ctx, 6), isEmpty);
    expect(net.requests, isEmpty);
    on = true;
    final noToken = LbRecsSource(
      client: ListenBrainzClient(transport: net.call),
      matcher: YoutubeMatcher(search: (q, k) async => const [], persist: false),
      readToken: () async => null,
      userName: () => 'ana',
      enabled: () => true,
      pause: Duration.zero,
    );
    expect(await noToken.fetch(_ctx, 6), isEmpty);
    expect(net.requests, isEmpty);
  });

  test('204 en listas y en CF: lista vacía sin fallar', () async {
    net.routes['/playlists/createdfor'] = () => const LbResponse(204, '');
    net.routes['/cf/recommendation'] = () => const LbResponse(204, '');
    expect(await build.fetch(_ctx, 6), isEmpty);
  });

  test('sin listas, el CF experimental se resuelve por MBID', () async {
    net.routes['/playlists/createdfor'] = () =>
        const LbResponse(200, '{"playlists":[]}');
    net.routes['/cf/recommendation'] = () => const LbResponse(
      200,
      '{"payload":{"mbids":[{"recording_mbid":"$mbidA","score":0.9}]}}',
    );
    net.routes['/metadata/recording'] = () => const LbResponse(
      200,
      '{"$mbidA":{"recording":{"name":"Canción Uno","length":200000},"artist":{"name":"Banda Uno"},"tag":{"artist":[{"tag":"rock","count":3}]}}}',
    );
    final out = await build.fetch(_ctx, 6);
    expect(out.single.bucket, RecBucket.listenbrainz);
    expect(out.single.track.genres, contains('rock'));
    expect(net.requests.last.uri.query, contains('inc=artist+tag'));
  });

  test('429: vacío y no vuelve a llamar hasta pasar el tiempo', () async {
    net.routes['/playlists/createdfor'] = () =>
        const LbResponse(429, '{}', {'x-ratelimit-reset-in': '30'});
    expect(await build.fetch(_ctx, 6), isEmpty);
    final calls = net.requests.length;
    expect(await build.fetch(_ctx, 6), isEmpty);
    expect(net.requests.length, calls);
  });

  test('5xx y fallos de red: vacío', () async {
    net.routes['/playlists/createdfor'] = () => const LbResponse(503, '');
    net.routes['/cf/recommendation'] = () => const LbResponse(500, '');
    expect(await build.fetch(_ctx, 6), isEmpty);
    net.routes.clear();
    expect(await build.fetch(_ctx, 6), isEmpty); // 404
  });

  test('MBID sin coincidencia en YouTube: se descarta', () async {
    found = (_) => [_yt('Otra cosa distinta', 'Nadie', 90)];
    expect(await build.fetch(_ctx, 6), isEmpty);
  });

  test('caché: la segunda vez no repite peticiones ni búsquedas', () async {
    final first = await build.fetch(_ctx, 6);
    expect(first, isNotEmpty);
    final calls = net.requests.length, s = searches;
    final second = await build.fetch(_ctx, 6);
    expect(second, hasLength(first.length));
    expect(net.requests.length, calls);
    expect(searches, s);
  });

  test('artistas saltados no se ofrecen', () async {
    final out = await build.fetch(
      const SessionContext(
        participants: [],
        seed: 1,
        skippedArtists: {'banda uno', 'banda dos'},
      ),
      6,
    );
    expect(out, isEmpty);
  });
}
