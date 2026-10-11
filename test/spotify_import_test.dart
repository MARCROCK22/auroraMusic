import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/import/spotify_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('SpotifyImportParser', () {
    test('parses JSON playlists and reports episodes and local entries', () {
      final result = SpotifyImportParser.parse('''
        {"playlists":[{"name":"Road","items":[
          {"track":{"trackName":"Song","artistName":"Artist","albumName":"Album","trackUri":"spotify:track:abc123"}},
          {"track":{"trackName":"Episode","artistName":"Host","trackUri":"spotify:episode:xyz"}},
          {"track":{"trackName":"Local","artistName":"Artist","trackUri":"spotify:local:Artist:Song:0"}}
        ]}]}
      ''');

      expect(result.playlists.single.tracks, hasLength(1));
      expect(result.playlists.single.tracks.single.uri, 'spotify:track:abc123');
      expect(result.skipped, 2);
    });

    test('parses quoted CSV, preserves repeated rows and playlist order', () {
      final result = SpotifyImportParser.parse(
        'TrackName,ArtistName,AlbumName,PlaylistName,TrackUri\r\n'
        '"Song, Pt. 1","Artist ""A""",Album,First,spotify:track:a\r\n'
        '"Song, Pt. 1","Artist ""A""",Album,First,spotify:track:a\r\n'
        'Other,Second,Record,Later,spotify:track:b\r\n',
        extension: 'csv',
      );

      expect(result.playlists.map((playlist) => playlist.name), [
        'First',
        'Later',
      ]);
      expect(result.playlists.first.tracks, hasLength(2));
      expect(result.playlists.first.tracks.first.title, 'Song, Pt. 1');
      expect(result.playlists.first.tracks.first.artist, 'Artist "A"');
    });

    test('rejects malformed CSV and JSON', () {
      expect(
        () => SpotifyImportParser.parse('"unclosed', extension: 'csv'),
        throwsFormatException,
      );
      expect(
        () => SpotifyImportParser.parse('{bad json}', extension: 'json'),
        throwsFormatException,
      );
    });
  });

  test(
    'import persists selected playlists with order and duplicate tracks',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      const imported = [
        SpotifyImportPlaylist(
          name: 'Imported',
          tracks: [
            SpotifyImportTrack(
              title: 'Song',
              artist: 'Artist',
              album: 'Record',
              uri: 'spotify:track:abc',
            ),
            SpotifyImportTrack(
              title: 'Song',
              artist: 'Artist',
              album: 'Record',
              uri: 'spotify:track:abc',
            ),
            SpotifyImportTrack(
              title: 'Next',
              artist: 'Other',
              uri: 'spotify:track:def',
            ),
          ],
        ),
      ];

      await controller.importSpotifyPlaylists(imported);

      expect(controller.playlists.single.name, 'Imported');
      expect(controller.playlists.single.trackIds, hasLength(3));
      expect(controller.playlists.single.trackIds.toSet(), hasLength(3));
      final importedById = {
        for (final track in controller.tracks) track.id: track,
      };
      expect(
        controller.playlists.single.trackIds
            .map((id) => importedById[id]?.title)
            .toList(),
        ['Song', 'Song', 'Next'],
      );
      expect(controller.tracks.first.album, 'Record');
      expect(controller.tracks.first.isPendingSpotifyMatch, isTrue);
      final restored = await controller.database.readTracks();
      final restoredSong = restored.firstWhere(
        (track) => track.title == 'Song',
      );
      expect(restoredSong.spotifyUri, 'spotify:track:abc');
      expect(restoredSong.isPendingSpotifyMatch, isTrue);
    },
  );

  test(
    'Track JSON reads records created before Spotify import fields existed',
    () {
      final track = Track.fromJson({
        'id': 'old',
        'title': 'Old song',
        'artist': 'Old artist',
      });
      expect(track.album, isNull);
      expect(track.spotifyUri, isNull);
    },
  );
}
