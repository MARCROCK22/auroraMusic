import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:aurora_music/core/artwork_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'provider width hints distinguish known sizes and leave unknowns alone',
    () {
      expect(
        artworkWidthHint('https://lh3.googleusercontent.com/cover=w60-h60-l90'),
        60,
      );
      expect(
        artworkWidthHint('https://lh3.googleusercontent.com/cover=s512-rw'),
        512,
      );
      expect(artworkWidthHint('https://i.ytimg.com/cover.jpg?width=720'), 720);
      expect(
        artworkWidthHint('https://i.ytimg.com/vi/abc/maxresdefault.jpg'),
        1280,
      );
      expect(artworkWidthHint('https://i.ytimg.com/cover.jpg'), 0);
      expect(artworkWidthHint(null), 0);
    },
  );
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
