import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/recommendations.dart';
import 'package:flutter_test/flutter_test.dart';

Track track(String id, String artist) =>
    Track(id: id, title: id, artist: artist, pageUrl: 'https://youtu.be/$id');

void main() {
  final library = [
    track('liked', 'North'),
    track('north-a', 'North'),
    track('north-b', 'North'),
    track('north-c', 'North'),
    track('south', 'South'),
  ];

  test('likes, playlists and recent artist history rank known tracks', () {
    expect(
      strongestTasteArtist(
        library: library,
        favoriteIds: {'liked'},
        playlists: const [],
        history: [track('played', 'South')],
      ),
      'North',
    );
    final result = recommendTracks(
      library: library,
      favoriteIds: {'liked'},
      playlists: const [MusicPlaylist(id: 'road', name: 'Road', trackIds: [])],
      history: [track('played', 'South')],
    );

    expect(result.first.track.artist, 'North');
    expect(result.first.reason, 'Porque te gusta North');
    expect(
      result.any((item) => item.reason == 'Porque te gusta North'),
      isTrue,
    );
  });

  test(
    'playlist inclusion and recency are explained; artist diversity holds',
    () {
      final result = recommendTracks(
        library: library,
        favoriteIds: {},
        playlists: const [
          MusicPlaylist(id: 'road', name: 'Road', trackIds: ['south']),
        ],
        history: [track('played', 'South')],
      );

      expect(result.first.reason, 'Está en tus listas');
      expect(
        result.where((item) => item.track.artist == 'North'),
        hasLength(2),
      );
      expect(result.map((item) => item.track.id).toSet().length, result.length);
    },
  );

  test('recent listening lifts an artist and names that signal', () {
    final result = recommendTracks(
      library: library,
      favoriteIds: {},
      playlists: const [],
      history: [track('played', 'South')],
    );

    expect(result.first.track.artist, 'South');
    expect(result.first.reason, 'Por tu escucha reciente de South');
  });

  test('cold start is stable and skips unplayable pending Spotify tracks', () {
    final pending = Track(
      id: 'pending',
      title: 'Pending',
      artist: 'North',
      spotifyMatchPending: true,
    );
    final args = (
      library: [...library, pending],
      favoriteIds: <String>{},
      playlists: <MusicPlaylist>[],
      history: <Track>[],
    );
    final first = recommendTracks(
      library: args.library,
      favoriteIds: args.favoriteIds,
      playlists: args.playlists,
      history: args.history,
    );
    final second = recommendTracks(
      library: args.library,
      favoriteIds: args.favoriteIds,
      playlists: args.playlists,
      history: args.history,
    );

    expect(
      first.map((item) => item.track.id),
      second.map((item) => item.track.id),
    );
    expect(first.every((item) => item.reason == 'De tu biblioteca'), isTrue);
    expect(first.any((item) => item.track.id == 'pending'), isFalse);
    expect(first.where((item) => item.track.artist == 'North'), hasLength(2));
  });
}
