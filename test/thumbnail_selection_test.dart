import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'highest width wins regardless of input order or thumbnail fallback',
    () {
      final result = YtDlpSource.selectArtworkUrl({
        'thumbnail': 'https://i.ytimg.com/vi/example/hqdefault.jpg',
        'thumbnails': [
          {
            'url': 'https://i.ytimg.com/vi/example/maxresdefault.jpg',
            'width': 1280,
          },
          {'url': 'https://i.ytimg.com/vi/example/sddefault.jpg', 'width': 640},
          {'url': 'https://i.ytimg.com/vi/example/mqdefault.jpg', 'width': 320},
        ],
      });
      expect(result, endsWith('maxresdefault.jpg'));
    },
  );

  test(
    'known high-resolution filenames are preferred when width is missing',
    () {
      expect(
        YtDlpSource.selectArtworkUrl({
          'thumbnails': [
            {'url': 'https://i.ytimg.com/vi/example/hqdefault.jpg'},
            {'url': 'https://i.ytimg.com/vi/example/maxresdefault.jpg'},
          ],
        }),
        endsWith('maxresdefault.jpg'),
      );
    },
  );

  test('malformed entries and credential-bearing images are ignored', () {
    expect(
      YtDlpSource.selectArtworkUrl({
        'thumbnails': [
          null,
          false,
          {},
          {'url': 'https://secret@i.ytimg.com/private.jpg', 'width': 2000},
          {'url': 'https://i.ytimg.com/cover.jpg', 'width': 750},
        ],
      }),
      'https://i.ytimg.com/cover.jpg',
    );
    expect(YtDlpSource.selectArtworkUrl({}), isNull);
    expect(
      YtDlpSource.selectArtworkUrl({
        'thumbnails': 'invalid',
        'thumbnail': 'https://i.ytimg.com/cover.jpg',
      }),
      'https://i.ytimg.com/cover.jpg',
    );
  });
}
