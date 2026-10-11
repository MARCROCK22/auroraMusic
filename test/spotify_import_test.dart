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

    test('accepts Spotify CSV export aliases without playlist column', () {
      final result = SpotifyImportParser.parse(
        'Track Name,Artist Name(s),Album Name,Track URI\n'
        'Song,Artist One; Artist Two,Record,spotify:track:abc\n',
        extension: 'csv',
        fallbackPlaylistName: 'Liked Songs',
      );
      expect(result.playlists.single.name, 'Liked Songs');
      expect(result.playlists.single.tracks.single.title, 'Song');
      expect(
        result.playlists.single.tracks.single.artist,
        'Artist One; Artist Two',
      );
      expect(result.playlists.single.tracks.single.uri, 'spotify:track:abc');
    });

    test('accepts Artist(s) header spelling', () {
      final result = SpotifyImportParser.parse(
        'Track Name,Artist(s),Playlist Name\nSong,Artist,Playlist\n',
        extension: 'csv',
      );
      expect(result.playlists.single.tracks.single.artist, 'Artist');
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
    'manual match preserves Spotify identity in tracks and restored queue',
    () async {
      const pending = Track(
        id: 'spotify-stable-id',
        title: 'Original title',
        artist: 'Original artist',
        album: 'Original album',
        spotifyUri: 'spotify:track:abc',
        spotifyMatchPending: true,
      );
      const match = Track(
        id: 'youtube-result',
        title: 'Different YouTube title',
        artist: 'Different YouTube artist',
        duration: Duration(minutes: 3),
        artworkUrl: 'https://img.test/art.jpg',
        pageUrl: 'https://youtu.be/abcdefghijk',
      );
      final source = FakeSource()..searchMatches = [match];
      final controller = await createTestController(
        tracks: const [pending],
        source: source,
        preferences: const {
          'queue': ['spotify-stable-id'],
          'queueIndex': 0,
        },
      );
      addTearDown(() => closeTestController(controller));

      final matches = await controller.findSpotifyMatches(pending);
      expect(matches, [match]);
      expect(source.searchQueries, ['Original title Original artist']);
      expect(source.searchLimits, [3]);
      expect(await controller.matchSpotifyTrack(pending.id, match), isTrue);

      final saved = (await controller.database.readTracks()).single;
      expect(saved.id, pending.id);
      expect(saved.title, pending.title);
      expect(saved.artist, pending.artist);
      expect(saved.album, pending.album);
      expect(saved.spotifyUri, pending.spotifyUri);
      expect(saved.isPendingSpotifyMatch, isFalse);
      expect(saved.pageUrl, match.pageUrl);
      expect(saved.artworkUrl, match.artworkUrl);
      expect(saved.duration, match.duration);
      expect(controller.currentTrack?.id, pending.id);
      expect(controller.currentTrack?.pageUrl, match.pageUrl);
      expect((controller.audio as FakeAudio).loadCount, 0);
      expect(source.resolved, isEmpty);
    },
  );

  test('manual match plays only when the user requests it', () async {
    const pending = Track(
      id: 'spotify-stable-id',
      title: 'Song',
      artist: 'Artist',
      spotifyUri: 'spotify:track:abc',
      spotifyMatchPending: true,
    );
    const match = Track(
      id: 'youtube-result',
      title: 'Video title',
      artist: 'Video artist',
      pageUrl: 'https://youtu.be/abcdefghijk',
    );
    final controller = await createTestController(tracks: const [pending]);
    addTearDown(() => closeTestController(controller));

    expect(
      await controller.matchSpotifyTrack(pending.id, match, play: true),
      isTrue,
    );
    expect(controller.currentTrack?.id, pending.id);
    expect((controller.audio as FakeAudio).loaded?.input, contains(pending.id));
  });

  test(
    'pending restored queue playback stops with actionable guidance',
    () async {
      const pending = Track(
        id: 'spotify-pending',
        title: 'Song',
        artist: 'Artist',
        spotifyMatchPending: true,
      );
      final controller = await createTestController(
        tracks: const [pending],
        preferences: const {
          'queue': ['spotify-pending'],
          'queueIndex': 0,
        },
      );
      addTearDown(() => closeTestController(controller));
      await controller.playQueueAt(0);

      expect((controller.audio as FakeAudio).isPlaying, isFalse);
      expect(controller.error, contains('elige su video de YouTube'));
      expect((controller.audio as FakeAudio).loadCount, 0);
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
