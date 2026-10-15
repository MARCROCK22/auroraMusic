import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Map<String, Object?> _run(String text, [String? pageType]) => {
  'text': text,
  if (pageType != null)
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': pageType},
        },
      },
    },
};

Map<String, Object?> _row(String id, String title, List<Object?> details) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {
              'url': 'https://lh3.googleusercontent.com/a=w60-h60-l90-rj',
              'width': 60,
            },
            {
              'url': 'https://lh3.googleusercontent.com/a=w120-h120-l90-rj',
              'width': 120,
            },
            {'url': 'http://insecure.test/big.jpg', 'width': 999},
          ],
        },
      },
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {'text': title},
            ],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {'runs': details},
        },
      },
    ],
  },
};

// Hand-trimmed from a real WEB_REMIX songs search response.
final _searchFixture = <String, dynamic>{
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {
                      'contents': [
                        _row('19y35jAcG6k', '120', [
                          _run('Bad Bunny', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' • '),
                          _run('EL ÚLTIMO TOUR', 'MUSIC_PAGE_TYPE_ALBUM'),
                          _run(' • '),
                          _run('2:32'),
                        ]),
                        _row('abcdefghijk', 'Dúo', [
                          _run('A', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' & '),
                          _run('B', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' • '),
                          _run('1:02:03'),
                        ]),
                        _row('bad', 'Invalid id', [_run('X')]),
                        _row('19y35jAcG6k', 'Duplicate', [_run('X')]),
                        _row('zyxwvutsrqp', 'Plain', [
                          _run('Uploader'),
                          _run(' • '),
                          _run('3:00'),
                        ]),
                      ],
                    },
                  },
                ],
              },
            },
          },
        },
      ],
    },
  },
};

const _song = Track(
  id: 'yt:19y35jAcG6k',
  title: '120',
  artist: 'Bad Bunny',
  duration: Duration(seconds: 152),
  pageUrl: 'https://music.youtube.com/watch?v=19y35jAcG6k',
);

void main() {
  test('search parses songs rows into canonical YouTube tracks', () async {
    final requests = <(String, Map<String, Object?>)>[];
    final source = InnerTubeSource(
      FakeSource(),
      post: (endpoint, body) async {
        requests.add((endpoint, body));
        return _searchFixture;
      },
    );
    final tracks = await source.search('  bad bunny ');
    expect(requests.single.$1, 'search');
    expect(requests.single.$2['query'], 'bad bunny');
    expect(requests.single.$2.containsKey('key'), isFalse);
    expect(tracks.map((t) => t.id), [
      'yt:19y35jAcG6k',
      'yt:abcdefghijk',
      'yt:zyxwvutsrqp',
    ]);
    final first = tracks.first;
    expect(first.title, '120');
    expect(first.artist, 'Bad Bunny');
    expect(first.album, 'EL ÚLTIMO TOUR');
    expect(first.duration, const Duration(minutes: 2, seconds: 32));
    expect(
      first.artworkUrl,
      'https://lh3.googleusercontent.com/a=w544-h544-l90-rj',
    );
    expect(first.pageUrl, 'https://music.youtube.com/watch?v=19y35jAcG6k');
    expect(recommendationTrackKeys(first), contains('youtube:19y35jAcG6k'));
    expect(tracks[1].artist, 'A, B');
    expect(
      tracks[1].duration,
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(tracks[2].artist, 'Uploader');
    expect(await source.search('bad bunny', limit: 1), hasLength(1));
  });

  test('search sends links to the delegate and rejects long input', () async {
    final delegate = FakeSource()..searchMatches = [_song];
    var posts = 0;
    final source = InnerTubeSource(
      delegate,
      post: (_, _) async {
        posts++;
        return {};
      },
    );
    expect(await source.search('https://youtu.be/19y35jAcG6k'), [_song]);
    expect(await source.search('   '), isEmpty);
    expect(() => source.search('x' * 501), throwsArgumentError);
    expect(posts, 0);
  });

  test('video ids use the 11-character pattern', () {
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6k'), isTrue);
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6'), isFalse);
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6k/'), isFalse);
    expect(InnerTubeSource.isValidVideoId('../etc/pass'), isFalse);
  });

  test('resolve hands YouTube tracks to the official watch page', () async {
    final delegate = FakeSource();
    final source = InnerTubeSource(delegate);
    final audio = await source.resolve(_song);
    expect(audio.input, 'https://music.youtube.com/watch?v=19y35jAcG6k');
    expect(audio.headers, isEmpty);
    expect(audio.duration, _song.duration);
    expect(source.isExpiredStream(_song), isFalse);
    // No extraction, no yt-dlp fallback.
    expect(delegate.resolved, isEmpty);
    await expectLater(
      source.resolve(
        const Track(
          id: 'web:1',
          title: 'Otra',
          artist: 'Sitio',
          pageUrl: 'https://example.test/song',
        ),
      ),
      throwsStateError,
    );
    expect(delegate.resolved, isEmpty);
  });
}
