import 'dart:async';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

Track song(
  String id, {
  String artist = 'North',
  List<String> genres = const [],
}) => Track(
  id: id,
  title: id,
  artist: artist,
  genres: genres,
  pageUrl: 'https://youtu.be/$id',
);

Future<void> settleUntil(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

void main() {
  test('genre JSON supports old tracks and survives copy', () {
    final old = Track.fromJson({
      'id': 'old',
      'title': 'Old',
      'artist': 'North',
    });
    expect(old.genres, isEmpty);
    final enriched = old.copyWith(genres: ['Jazz']);
    expect(Track.fromJson(enriched.toJson()).genres, ['Jazz']);
    expect(enriched.copyWith(pageUrl: 'https://youtu.be/old').genres, ['Jazz']);
  });

  test('filters AND dimensions and let exclusions win', () {
    const filters = DjFilters(
      artists: [' north '],
      trackIds: ['jazz'],
      genres: [' JAZZ '],
      excludedGenres: ['rock'],
    );
    expect(filters.permits(song('jazz', genres: ['jazz'])), isTrue);
    expect(filters.permits(song('other', genres: ['jazz'])), isFalse);
    expect(
      filters.permits(song('jazz', artist: 'South', genres: ['jazz'])),
      isFalse,
    );
    expect(filters.permits(song('jazz', genres: ['jazz', 'Rock'])), isFalse);
    expect(filters.permits(song('jazz')), isFalse);
    expect(
      const DjFilters(excludedArtists: ['NORTH']).permits(song('jazz')),
      isFalse,
    );
    expect(
      const DjFilters(excludedTrackIds: ['jazz']).permits(song('jazz')),
      isFalse,
    );
  });

  test(
    'favorite genres rank and explain another artist without invented tags',
    () {
      final result = recommendTracks(
        library: [
          song('liked', genres: ['Jazz']),
          song('jazzy', artist: 'South', genres: ['jazz']),
          song('untagged', artist: 'West'),
        ],
        favoriteIds: {'liked'},
        playlists: [],
        history: [],
      );
      expect(result.first.track.id, 'jazzy');
      expect(
        result.first.reason,
        'Porque coincide con tus g\u00e9neros favoritos',
      );
      expect(result.last.reason, 'De tu biblioteca');
    },
  );

  test('Spotify identity survives different matched audio URLs', () {
    final a = song('a').copyWith(spotifyUri: 'spotify:track:abc');
    final b = song('b').copyWith(spotifyUri: 'spotify:track:abc');
    const c = Track(
      id: 'c',
      title: 'c',
      artist: 'South',
      pageUrl: 'https://open.spotify.com/intl-es/track/abc?si=ignored',
    );
    expect(recommendationTracksMatch(a, b), isTrue);
    expect(recommendationTracksMatch(a, c), isTrue);
    expect(
      recommendTracks(
        library: [a, b],
        favoriteIds: {},
        playlists: [],
        history: [],
      ),
      hasLength(1),
    );
  });

  test('filters persist across restart and invalid JSON falls back', () async {
    final controller = await createTestController(
      tracks: [
        song('one'),
        song('two', artist: 'South'),
      ],
    );
    await controller.setDjFilters(
      const DjFilters(artists: ['North'], excludedTrackIds: ['one']),
    );
    final saved = controller.preferences.getString('djFilters')!;
    await closeTestController(controller);
    final restored = await createTestController(
      tracks: [
        song('one'),
        song('two', artist: 'South'),
      ],
      preferences: {'djFilters': saved},
    );
    expect(restored.djFilters.artists, ['North']);
    expect(restored.recommendations, isEmpty);
    await closeTestController(restored);
    final malformed = await createTestController(
      preferences: {'djFilters': '{broken'},
    );
    addTearDown(() => closeTestController(malformed));
    expect(malformed.djFilters.artists, isEmpty);
  });

  test(
    'discovery filters results and invalidates pending results on change',
    () async {
      final source = FakeSource()
        ..searchMatches = [song('allowed'), song('blocked', artist: 'South')];
      final controller = await createTestController(
        tracks: [song('liked')],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(song('liked'));
      await controller.setDjFilters(const DjFilters(artists: ['North']));
      await controller.discoverRecommendations();
      expect(controller.discoveredRecommendations.map((t) => t.id), [
        'allowed',
      ]);
      source.pendingSearch = Completer<List<Track>>();
      final discovery = controller.refreshRecommendations();
      await controller.setDjFilters(
        const DjFilters(excludedArtists: ['North']),
      );
      source.pendingSearch!.complete([song('late')]);
      await discovery;
      expect(controller.discoveredRecommendations, isEmpty);
      expect(controller.discoveringRecommendations, isFalse);
    },
  );

  test('local DJ start and refill honor song filters', () async {
    final tracks = [
      for (var i = 0; i < 12; i++) song('t$i', artist: 'Artist $i'),
    ];
    final controller = await createTestController(tracks: tracks);
    addTearDown(() => closeTestController(controller));
    await controller.setDjFilters(
      const DjFilters(excludedTrackIds: ['t0', 't7']),
    );
    await controller.startPersonalDj();
    final initialLength = controller.queue.length;
    for (var i = 0; i < 3; i++) {
      await controller.next();
    }
    await settleUntil(() => controller.queue.length > initialLength);
    expect(controller.queue.any((t) => ['t0', 't7'].contains(t.id)), isFalse);
    expect(
      controller.queue.map((t) => t.id).toSet(),
      hasLength(controller.queue.length),
    );
  });

  test('DJ rejects pending refill after filter changes', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(
      tracks: [song('liked'), song('one'), song('two')],
      source: source,
    );
    addTearDown(() => closeTestController(controller));
    await controller.toggleFavorite(song('liked'));
    await controller.startPersonalDj(includeDiscovery: true);
    await settleUntil(() => source.searchQueries.isNotEmpty);
    await controller.setDjFilters(const DjFilters(excludedArtists: ['North']));
    source.pendingSearch!.complete([song('late')]);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(controller.queue.any((t) => t.id == 'late'), isFalse);
  });

  test(
    'DJ discovery respects filters and queue cap after manual additions',
    () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final controller = await createTestController(
        tracks: [song('liked'), song('one'), song('two')],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(song('liked'));
      await controller.setDjFilters(
        const DjFilters(excludedTrackIds: ['blocked']),
      );
      await controller.startPersonalDj(includeDiscovery: true);
      await settleUntil(() => source.searchQueries.isNotEmpty);
      source.pendingSearch!.complete([song('blocked'), song('allowed')]);
      await settleUntil(() => controller.queue.any((t) => t.id == 'allowed'));
      expect(controller.queue.any((t) => t.id == 'blocked'), isFalse);
    },
  );

  test('refill cannot exceed 24 after concurrent manual enqueue', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(
      tracks: [song('liked'), song('one'), song('two')],
      source: source,
    );
    addTearDown(() => closeTestController(controller));
    await controller.toggleFavorite(song('liked'));
    await controller.startPersonalDj(includeDiscovery: true);
    await settleUntil(() => source.searchQueries.isNotEmpty);
    while (controller.queue.length < 24) {
      await controller.addToQueue(song('manual-${controller.queue.length}'));
    }
    source.pendingSearch!.complete([song('late')]);
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(controller.queue, hasLength(24));
  });

  test('manual enqueue deduplicates canonical YouTube pages', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    await controller.addToQueue(song('audio'));
    await controller.addToQueue(
      song(
        'alias',
      ).copyWith(pageUrl: 'https://www.youtube.com/watch?v=audio&si=share'),
    );
    expect(controller.queue, hasLength(1));
  });

  test('concurrent enqueue deduplicates Spotify aliases and IDs', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    final a = song('a').copyWith(spotifyUri: 'spotify:track:abc');
    final b = song('b').copyWith(spotifyUri: 'spotify:track:abc');
    await Future.wait([
      controller.addToQueue(a),
      controller.addToQueue(b),
      controller.addToQueue(a),
    ]);
    expect(controller.queue, hasLength(1));
  });

  test(
    'Spotify enqueue preserves metadata and only uses matched audio',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      const metadata = Track(
        id: 'spotify',
        title: 'Description',
        artist: 'Creator',
        album: 'Album',
        genres: ['Jazz'],
        spotifyUri: 'spotify:track:abc',
        artworkUrl: 'https://image.test/a',
        pageUrl: 'https://open.spotify.com/track/abc',
        spotifyMatchPending: true,
      );
      expect(
        await controller.importSpotifyMetadataMatch(metadata, song('audio')),
        isTrue,
      );
      final queued = controller.queue.single;
      expect(queued.id, 'audio');
      expect(queued.title, metadata.title);
      expect(queued.artist, metadata.artist);
      expect(queued.album, metadata.album);
      expect(queued.artworkUrl, metadata.artworkUrl);
      expect(queued.pageUrl, 'https://youtu.be/audio');
      expect(queued.spotifyUri, metadata.spotifyUri);
      expect(queued.genres, ['Jazz']);
      expect(queued.isPendingSpotifyMatch, isFalse);
      expect(
        await controller.importSpotifyMetadataMatch(metadata, song('other')),
        isTrue,
      );
      expect(controller.queue, hasLength(1));
      expect(
        await controller.importSpotifyMetadataMatch(metadata, metadata),
        isFalse,
      );
      expect(
        await controller.importSpotifyMetadataMatch(
          metadata,
          song(
            'evil',
          ).copyWith(pageUrl: 'https://youtube.com.evil.test/watch?v=abc'),
        ),
        isFalse,
      );
    },
  );
}
