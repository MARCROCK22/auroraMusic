import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/metadata/spotify/spotify_auth.dart';
import 'package:aurora_music/metadata/spotify/spotify_browser_controller.dart';
import 'package:aurora_music/metadata/spotify/spotify_metadata_provider.dart';

const trackUri = 'spotify:track:0000000000000000000001';
const albumUri = 'spotify:album:0000000000000000000002';
const artistUri = 'spotify:artist:0000000000000000000003';
const playlistUri = 'spotify:playlist:0000000000000000000004';
Map<String, dynamic> trackData({
  String uri = trackUri,
  String name = 'Offline song',
}) => {
  '__typename': 'Track',
  'uri': uri,
  'name': name,
  'artists': {
    'items': [
      {
        'uri': artistUri,
        'profile': {'name': 'Offline artist'},
      },
    ],
  },
  'albumOfTrack': {
    'uri': albumUri,
    'name': 'Offline album',
    'coverArt': {
      'sources': [
        {'url': 'https://example.org/art.png'},
      ],
    },
  },
  'duration': {'totalMilliseconds': 123000},
};
Map<String, dynamic> searchData({int total = 1, List<Object?>? items}) => {
  'data': {
    'searchV2': {
      'tracksV2': {
        'totalCount': total,
        'items':
            items ??
            [
              {
                'item': {'data': trackData()},
              },
            ],
      },
    },
  },
};
SpotifyResponse response(Object data, {int status = 200}) =>
    SpotifyResponse(status, jsonEncode(data));

class OfflineSpotify {
  DateTime now = DateTime.utc(2026, 10, 12);
  int tokenCalls = 0;
  int secretCalls = 0;
  int queryCalls = 0;
  int activeQueries = 0;
  int maxQueries = 0;
  final List<Map<String, dynamic>> requests = [];
  final List<int> secretVersions = [];
  Future<SpotifyResponse> Function(Map<String, dynamic>)? onQuery;
  SpotifyResponse Function(Uri)? onToken;
  Future<SpotifyResponse> call(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    if (uri.host == 'raw.githubusercontent.com') {
      secretCalls++;
      return response({
        '2': [1, 2, 3, 4],
        '1': [5, 6, 7, 8],
      });
    }
    if (uri.path.endsWith('server-time')) {
      return response({'serverTime': now.millisecondsSinceEpoch ~/ 1000});
    }
    if (uri.path.endsWith('/token')) {
      tokenCalls++;
      secretVersions.add(int.parse(uri.queryParameters['totpVer']!));
      expect(uri.queryParameters['totp'], matches(RegExp(r'^\d{6}$')));
      expect(uri.queryParameters['totpServer'], matches(RegExp(r'^\d{6}$')));
      return onToken?.call(uri) ??
          response({
            'accessToken': 'offline-fixture-$tokenCalls',
            'accessTokenExpirationTimestampMs': now
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          });
    }
    expect(method, 'POST');
    expect(headers.containsKey('Authorization'), isTrue);
    final request = jsonDecode(body!) as Map<String, dynamic>;
    requests.add(request);
    queryCalls++;
    activeQueries++;
    if (activeQueries > maxQueries) maxQueries = activeQueries;
    try {
      return await (onQuery?.call(request) ??
          Future.value(response(searchData())));
    } finally {
      activeQueries--;
    }
  }

  SpotifyMetadataProvider provider() =>
      SpotifyMetadataProvider(transport: call, clock: () => now);
}

void main() {
  test('genre mapping retains explicit values and invents none', () {
    expect(
      mapSpotifyEntity(trackData(), SpotifyEntityType.track)!.track!.genres,
      isEmpty,
    );
    expect(
      mapSpotifyEntity({
        ...trackData(),
        'genres': [' Rock ', 'Jazz', 'Jazz', 3],
      }, SpotifyEntityType.track)!.track!.genres,
      ['Rock', 'Jazz'],
    );
  });

  test('response cache evicts oldest entries at 128 queries', () async {
    final fixture = OfflineSpotify();
    final provider = fixture.provider();
    addTearDown(provider.close);
    for (var i = 0; i < 129; i++) {
      await provider.search('query$i');
    }
    await provider.search('query128');
    expect(fixture.queryCalls, 129);
    await provider.search('query0');
    expect(fixture.queryCalls, 130);
  });

  test('malformed anonymous token response exposes only safe error', () async {
    final fixture = OfflineSpotify()
      ..onToken = (_) => response({
        'accessToken': 123,
        'accessTokenExpirationTimestampMs': 'invalid',
      });
    final provider = fixture.provider();
    addTearDown(provider.close);
    await expectLater(
      provider.search('x'),
      throwsA(isA<SpotifyMetadataException>()),
    );
    expect(fixture.queryCalls, 0);
  });

  test('browser detail state handles failure separately from search', () async {
    final fixture = OfflineSpotify();
    fixture.onQuery = (request) async => request['operationName'] == 'getAlbum'
        ? response({}, status: 503)
        : response(searchData());
    final browser = SpotifyBrowserController(provider: fixture.provider());
    addTearDown(browser.dispose);
    await browser.search('x');
    final opening = browser.openDetails(
      const SpotifyMetadataEntity(
        type: SpotifyEntityType.album,
        uri: albumUri,
        name: 'Album',
      ),
    );
    expect(browser.detailLoading, isTrue);
    await opening;
    expect(browser.detailLoading, isFalse);
    expect(browser.detailError, isNotNull);
    expect(browser.error, isNull);
    expect(browser.items, hasLength(1));
    browser.closeDetails();
    expect(browser.detailError, isNull);
  });

  test('TOTP matches public RFC6238 vector with six digit truncation', () {
    expect(spotifyTotp(utf8.encode('12345678901234567890'), 59, 30), '287082');
  });

  test('maps metadata without Spotify audio or account credentials', () async {
    final fixture = OfflineSpotify();
    final provider = fixture.provider();
    addTearDown(provider.close);
    final page = await provider.search(' song ');
    final track = page.items.single.track!;
    expect(track.title, 'Offline song');
    expect(track.artist, 'Offline artist');
    expect(track.album, 'Offline album');
    expect(track.duration.inSeconds, 123);
    expect(track.artworkUrl, 'https://example.org/art.png');
    expect(track.spotifyUri, trackUri);
    expect(track.spotifyMatchPending, isTrue);
    expect(track.pageUrl, isNull);
    expect(track.localPath, isNull);
    expect(fixture.requests.single['operationName'], 'searchTracks');
    expect((fixture.requests.single['variables'] as Map)['searchTerm'], 'song');
  });

  test('maps artists albums playlists using Nuclear wrapper shapes', () async {
    final fixture = OfflineSpotify();
    fixture.onQuery = (query) async {
      final operation = query['operationName'];
      final field = operation == 'searchArtists'
          ? 'artists'
          : operation == 'searchAlbums'
          ? 'albumsV2'
          : 'playlists';
      final uri = operation == 'searchArtists'
          ? artistUri
          : operation == 'searchAlbums'
          ? albumUri
          : playlistUri;
      return response({
        'data': {
          'searchV2': {
            field: {
              'totalCount': 1,
              'items': [
                {
                  'data': {
                    'uri': uri,
                    'name': 'Entity',
                    'profile': {'name': 'Artist'},
                    'images': {
                      'items': [
                        {
                          'sources': [
                            {'url': 'https://example.org/playlist.png'},
                          ],
                        },
                      ],
                    },
                  },
                },
              ],
            },
          },
        },
      });
    };
    final provider = fixture.provider();
    addTearDown(provider.close);
    expect(
      (await provider.search(
        'x',
        type: SpotifyEntityType.artist,
      )).items.single.name,
      'Artist',
    );
    expect(
      (await provider.search(
        'x',
        type: SpotifyEntityType.album,
      )).items.single.uri,
      albumUri,
    );
    expect(
      (await provider.search(
        'x',
        type: SpotifyEntityType.playlist,
      )).items.single.artworkUrl,
      'https://example.org/playlist.png',
    );
  });

  test(
    'deduplicates identical in-flight requests and caches results',
    () async {
      final fixture = OfflineSpotify();
      fixture.onQuery = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return response(searchData());
      };
      final provider = fixture.provider();
      addTearDown(provider.close);
      await Future.wait(List.generate(8, (_) => provider.search('same')));
      await provider.search('same');
      expect(fixture.tokenCalls, 1);
      expect(fixture.queryCalls, 1);
      fixture.now = fixture.now.add(const Duration(minutes: 6));
      await provider.search('same');
      expect(fixture.queryCalls, 2);
      expect(fixture.tokenCalls, 1);
    },
  );

  test('limits parallel requests to three while sharing auth', () async {
    final fixture = OfflineSpotify();
    fixture.onQuery = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      return response(searchData());
    };
    final provider = fixture.provider();
    addTearDown(provider.close);
    await Future.wait(List.generate(12, (i) => provider.search('query$i')));
    expect(fixture.queryCalls, 12);
    expect(fixture.maxQueries, lessThanOrEqualTo(3));
    expect(fixture.tokenCalls, 1);
  });

  test(
    'renews expired token and refreshes remote rotation dictionary',
    () async {
      final fixture = OfflineSpotify();
      final provider = fixture.provider();
      addTearDown(provider.close);
      await provider.search('first');
      fixture.now = fixture.now.add(const Duration(hours: 2));
      await provider.search('second');
      expect(fixture.tokenCalls, 2);
      expect(fixture.secretCalls, 2);
    },
  );

  test('401 renews once and concurrent rejections share renewal', () async {
    final fixture = OfflineSpotify();
    fixture.onQuery = (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      return fixture.tokenCalls == 1
          ? response({}, status: 401)
          : response(searchData());
    };
    final provider = fixture.provider();
    addTearDown(provider.close);
    await Future.wait([provider.search('first'), provider.search('second')]);
    expect(fixture.tokenCalls, 2);
    expect(fixture.queryCalls, 4);
  });

  test('persistent 401 stops after one retry', () async {
    final fixture = OfflineSpotify()
      ..onQuery = (_) async => response({}, status: 401);
    final provider = fixture.provider();
    addTearDown(provider.close);
    await expectLater(
      provider.search('x'),
      throwsA(isA<SpotifyMetadataException>()),
    );
    expect(fixture.tokenCalls, 2);
    expect(fixture.queryCalls, 2);
  });

  test('token rejection rotates to next remote dictionary version', () async {
    final fixture = OfflineSpotify();
    fixture.onToken = (uri) => uri.queryParameters['totpVer'] == '2'
        ? response({}, status: 403)
        : response({
            'accessToken': 'offline-rotation',
            'accessTokenExpirationTimestampMs': fixture.now
                .add(const Duration(hours: 1))
                .millisecondsSinceEpoch,
          });
    final provider = fixture.provider();
    addTearDown(provider.close);
    await provider.search('x');
    expect(fixture.secretVersions, [2, 1]);
  });

  test('authentication retries are bounded when all versions fail', () async {
    final fixture = OfflineSpotify()
      ..onToken = (_) => response({}, status: 403);
    final provider = fixture.provider();
    addTearDown(provider.close);
    await expectLater(
      provider.search('x'),
      throwsA(isA<SpotifyMetadataException>()),
    );
    expect(fixture.secretCalls, 2);
    expect(fixture.tokenCalls, 4);
    expect(fixture.queryCalls, 0);
  });

  test(
    'failed queries are not cached and errors omit upstream payload',
    () async {
      final fixture = OfflineSpotify();
      fixture.onQuery = (_) async => fixture.queryCalls == 1
          ? response({'message': 'upstream-payload-marker'}, status: 500)
          : response(searchData());
      final provider = fixture.provider();
      addTearDown(provider.close);
      await expectLater(
        provider.search('x'),
        throwsA(
          isA<SpotifyMetadataException>().having(
            (failure) => failure.toString(),
            'sanitized',
            isNot(contains('upstream-payload-marker')),
          ),
        ),
      );
      expect((await provider.search('x')).items, hasLength(1));
      expect(fixture.queryCalls, 2);
    },
  );

  for (final invalid in [
    const SpotifyResponse(200, 'not json'),
    response({
      'errors': [
        {'message': 'private-upstream-marker'},
      ],
    }),
    response({
      'data': {
        'searchV2': {
          'tracksV2': {'items': 123},
        },
      },
    }),
    response({}, status: 429),
  ]) {
    test(
      'malformed schema, GraphQL and rate errors are sanitized ${invalid.statusCode}/${invalid.body.length}',
      () async {
        final fixture = OfflineSpotify()..onQuery = (_) async => invalid;
        final provider = fixture.provider();
        addTearDown(provider.close);
        await expectLater(
          provider.search('x'),
          throwsA(isA<SpotifyMetadataException>()),
        );
      },
    );
  }

  test(
    'pagination uses raw count even if unavailable tracks are removed',
    () async {
      final fixture = OfflineSpotify();
      fixture.onQuery = (query) async {
        final offset = (query['variables'] as Map)['offset'];
        return response(
          offset == 0
              ? searchData(
                  total: 3,
                  items: [
                    {
                      'item': {'data': trackData()},
                    },
                    {
                      'item': {
                        'data': {'__typename': 'NotFound'},
                      },
                    },
                  ],
                )
              : searchData(total: 3, items: []),
        );
      };
      final provider = fixture.provider();
      addTearDown(provider.close);
      final first = await provider.search('x', limit: 2);
      expect(first.items, hasLength(1));
      expect(first.nextOffset, 2);
      expect(
        (await provider.search(
          'x',
          limit: 2,
          offset: first.nextOffset!,
        )).hasMore,
        isFalse,
      );
    },
  );

  test(
    'playlist details map trackDuration, skip episodes and retain next page',
    () async {
      final fixture = OfflineSpotify();
      fixture.onQuery = (query) async => response({
        'data': {
          'playlistV2': {
            'uri': playlistUri,
            'name': 'Playlist',
            'description': 'Real description',
            'content': {
              'totalCount': 3,
              'items': [
                {
                  'item': {
                    'data': {
                      ...trackData(),
                      'duration': null,
                      'trackDuration': {'totalMilliseconds': 456000},
                    },
                  },
                },
                {
                  'item': {
                    'data': {
                      '__typename': 'Episode',
                      'uri': 'spotify:episode:0000000000000000000005',
                      'name': 'Episode',
                    },
                  },
                },
              ],
            },
          },
        },
      });
      final provider = fixture.provider();
      addTearDown(provider.close);
      final result = await provider.details(
        const SpotifyMetadataEntity(
          type: SpotifyEntityType.playlist,
          uri: playlistUri,
          name: 'Original',
        ),
        limit: 2,
      );
      expect(result.title, 'Playlist');
      expect(result.description, 'Real description');
      expect(result.tracks, hasLength(1));
      expect(result.tracks.single.duration.inSeconds, 456);
      expect(result.nextOffset, 2);
    },
  );

  test('album details inject album metadata for simplified tracks', () async {
    final fixture = OfflineSpotify();
    final simplified = trackData()..remove('albumOfTrack');
    fixture.onQuery = (_) async => response({
      'data': {
        'albumUnion': {
          'uri': albumUri,
          'name': 'Album details',
          'coverArt': {
            'sources': [
              {'url': 'https://example.org/album.png'},
            ],
          },
          'tracksV2': {
            'totalCount': 1,
            'items': [
              {'track': simplified},
            ],
          },
        },
      },
    });
    final provider = fixture.provider();
    addTearDown(provider.close);
    final result = await provider.details(
      const SpotifyMetadataEntity(
        type: SpotifyEntityType.album,
        uri: albumUri,
        name: 'Original',
      ),
    );
    expect(result.tracks.single.album, 'Album details');
    expect(result.tracks.single.artworkUrl, 'https://example.org/album.png');
  });

  test('artist biography and top tracks support local paging', () async {
    final fixture = OfflineSpotify();
    fixture.onQuery = (_) async => response({
      'data': {
        'artistUnion': {
          'uri': artistUri,
          'profile': {
            'name': 'Artist',
            'biography': {'text': 'Biography'},
          },
          'discography': {
            'topTracks': {
              'items': [
                {'track': trackData()},
                {
                  'track': trackData(
                    uri: 'spotify:track:0000000000000000000006',
                  ),
                },
              ],
            },
          },
        },
      },
    });
    final provider = fixture.provider();
    addTearDown(provider.close);
    const entity = SpotifyMetadataEntity(
      type: SpotifyEntityType.artist,
      uri: artistUri,
      name: 'Original',
    );
    final first = await provider.details(entity, limit: 1);
    final second = await provider.details(
      entity,
      limit: 1,
      offset: first.nextOffset!,
    );
    expect(first.description, 'Biography');
    expect(first.nextOffset, 1);
    expect(second.tracks.single.id, 'spotify:track:0000000000000000000006');
    expect(second.hasMore, isFalse);
    expect(fixture.queryCalls, 1);
  });

  test('validates user input and references before HTTP', () async {
    final fixture = OfflineSpotify();
    final provider = fixture.provider();
    addTearDown(provider.close);
    await expectLater(
      provider.search(''),
      throwsA(isA<SpotifyMetadataException>()),
    );
    await expectLater(
      provider.search('x', limit: 101),
      throwsA(isA<SpotifyMetadataException>()),
    );
    for (final uri in [
      'https://evil.example/playlist/0000000000000000000004',
      'spotify:playlist:short',
      'https://user@open.spotify.com/playlist/0000000000000000000004',
    ]) {
      await expectLater(
        provider.details(
          SpotifyMetadataEntity(
            type: SpotifyEntityType.playlist,
            uri: uri,
            name: 'Invalid',
          ),
        ),
        throwsA(isA<SpotifyMetadataException>()),
      );
    }
    expect(
      normalizeSpotifyUri(
        'https://open.spotify.com/playlist/0000000000000000000004?si=public',
        SpotifyEntityType.playlist,
      ),
      playlistUri,
    );
    expect(fixture.secretCalls, 0);
  });

  test(
    'network rejects oversized response and hides transport exceptions',
    () async {
      final network = SpotifyNetwork(
        (uri, {required method, required headers, body}) async =>
            SpotifyResponse(200, 'x' * (SpotifyNetwork.maxResponseBytes + 1)),
      );
      addTearDown(network.close);
      await expectLater(
        network.request(Uri.https('example.org')),
        throwsA(isA<SpotifyMetadataException>()),
      );
      final broken = SpotifyNetwork(
        (uri, {required method, required headers, body}) async =>
            throw Exception('transport-payload-marker'),
      );
      addTearDown(broken.close);
      await expectLater(
        broken.request(Uri.https('example.org')),
        throwsA(
          isA<SpotifyMetadataException>().having(
            (error) => error.toString(),
            'sanitized',
            isNot(contains('transport-payload-marker')),
          ),
        ),
      );
    },
  );

  test('closing network rejects queued requests promptly', () async {
    final gate = Completer<SpotifyResponse>();
    final network = SpotifyNetwork(
      (uri, {required method, required headers, body}) => gate.future,
    );
    final active = List.generate(
      3,
      (_) => network.request(Uri.https('example.org')),
    );
    final queued = List.generate(
      2,
      (_) => network.request(Uri.https('example.org')),
    );
    final checks = queued
        .map(
          (future) =>
              expectLater(future, throwsA(isA<SpotifyMetadataException>())),
        )
        .toList();
    final activeChecks = active
        .map(
          (future) =>
              expectLater(future, throwsA(isA<SpotifyMetadataException>())),
        )
        .toList();
    network.close();
    await Future.wait(checks);
    gate.complete(response({}));
    await Future.wait(activeChecks);
    await expectLater(
      network.request(Uri.https('example.org')),
      throwsA(isA<SpotifyMetadataException>()),
    );
  });

  test(
    'browser ignores late old searches and deduplicates page items',
    () async {
      final fixture = OfflineSpotify();
      final old = Completer<SpotifyResponse>();
      final oldStarted = Completer<void>();
      fixture.onQuery = (request) async {
        final vars = request['variables'] as Map;
        if (vars['searchTerm'] == 'old') {
          oldStarted.complete();
          return old.future;
        }
        return response(searchData(total: vars['offset'] == 0 ? 2 : 1));
      };
      final browser = SpotifyBrowserController(provider: fixture.provider());
      addTearDown(browser.dispose);
      final first = browser.search('old');
      await oldStarted.future;
      await browser.search('new');
      old.complete(
        response(
          searchData(
            items: [
              {
                'item': {'data': trackData(name: 'Old stale')},
              },
            ],
          ),
        ),
      );
      await first;
      expect(browser.query, 'new');
      expect(browser.items.single.name, 'Offline song');
      await browser.loadMore();
      expect(browser.items, hasLength(1));
      expect(browser.loading, isFalse);
      expect(browser.page!.hasMore, isFalse);
    },
  );

  test(
    'browser presents sanitized loading/error and clears empty searches',
    () async {
      final fixture = OfflineSpotify()
        ..onQuery = (_) async => response({}, status: 500);
      final browser = SpotifyBrowserController(provider: fixture.provider());
      addTearDown(browser.dispose);
      final search = browser.search('x');
      expect(browser.loading, isTrue);
      await search;
      expect(browser.loading, isFalse);
      expect(browser.error, isNotNull);
      await browser.search('');
      expect(browser.items, isEmpty);
      expect(browser.error, isNull);
    },
  );
}
