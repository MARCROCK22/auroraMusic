import '../core/models.dart';

/// Empty inclusions accept every value. Exclusions take precedence.
class DjFilters {
  const DjFilters({
    this.artists = const [],
    this.trackIds = const [],
    this.genres = const [],
    this.excludedArtists = const [],
    this.excludedTrackIds = const [],
    this.excludedGenres = const [],
  });
  final List<String> artists, trackIds, genres;
  final List<String> excludedArtists, excludedTrackIds, excludedGenres;
  static String normalize(String value) => value.trim().toLowerCase();
  bool permits(Track track) {
    final artist = normalize(track.artist);
    final tags = track.genres.map(normalize).toSet();
    bool contains(List<String> values, String value) =>
        values.map(normalize).contains(value);
    bool intersects(List<String> values) =>
        values.map(normalize).any(tags.contains);
    return !contains(excludedArtists, artist) &&
        !excludedTrackIds.contains(track.id) &&
        !intersects(excludedGenres) &&
        (artists.isEmpty || contains(artists, artist)) &&
        (trackIds.isEmpty || trackIds.contains(track.id)) &&
        (genres.isEmpty || intersects(genres));
  }

  Map<String, Object> toJson() => {
    'artists': artists,
    'trackIds': trackIds,
    'genres': genres,
    'excludedArtists': excludedArtists,
    'excludedTrackIds': excludedTrackIds,
    'excludedGenres': excludedGenres,
  };
  factory DjFilters.fromJson(Map<String, dynamic> json) {
    List<String> values(String key) => List<String>.unmodifiable(
      (json[key] as List?)?.whereType<String>() ?? const <String>[],
    );
    return DjFilters(
      artists: values('artists'),
      trackIds: values('trackIds'),
      genres: values('genres'),
      excludedArtists: values('excludedArtists'),
      excludedTrackIds: values('excludedTrackIds'),
      excludedGenres: values('excludedGenres'),
    );
  }
}

class TrackRecommendation {
  const TrackRecommendation({required this.track, required this.reason});

  final Track track;
  final String reason;
}

Set<String> recommendationTrackKeys(Track track) {
  final keys = {'id:${track.id}'};
  final spotify = track.spotifyUri;
  if (spotify != null && spotify.startsWith('spotify:track:')) {
    keys.add(spotify);
  }
  final uri = Uri.tryParse(track.pageUrl ?? '');
  if (uri == null || uri.host.isEmpty) return keys;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final videoId = host == 'youtu.be'
      ? uri.pathSegments.firstOrNull
      : (host == 'youtube.com' || host == 'music.youtube.com') &&
            uri.path == '/watch'
      ? uri.queryParameters['v']
      : (host == 'youtube.com' || host == 'music.youtube.com') &&
            uri.pathSegments.length >= 2 &&
            const {'shorts', 'embed', 'live'}.contains(uri.pathSegments.first)
      ? uri.pathSegments[1]
      : null;
  if (videoId != null && videoId.isNotEmpty) {
    keys.add('youtube:$videoId');
  } else if (host == 'open.spotify.com' || host == 'spotify.com') {
    final path = uri.path.replaceFirst(RegExp(r'/$'), '');
    keys.add('page:$host$path');
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final trackIndex = segments.indexOf('track');
    if (trackIndex >= 0 && segments.length > trackIndex + 1) {
      keys.add('spotify:track:${segments[trackIndex + 1]}');
    }
  } else {
    final query =
        {
          for (final entry in uri.queryParametersAll.entries)
            entry.key: List<String>.from(entry.value),
        }..removeWhere((key, _) {
          final lower = key.toLowerCase();
          return lower == 'si' ||
              lower == 'feature' ||
              lower == 'ref' ||
              lower == 'fbclid' ||
              lower == 'gclid' ||
              lower.startsWith('utm_');
        });
    final path = uri.path.replaceFirst(RegExp(r'/$'), '');
    final queryString = (query.keys.toList()..sort())
        .map((key) {
          final values = query[key]!..sort();
          return values.map((value) => '$key=$value').join('&');
        })
        .join('&');
    keys.add(
      'page:${uri.scheme.toLowerCase()}://$host$path'
      '${queryString.isEmpty ? '' : '?$queryString'}',
    );
  }
  return keys;
}

bool recommendationTracksMatch(Track a, Track b) => recommendationTrackKeys(
  a,
).intersection(recommendationTrackKeys(b)).isNotEmpty;

String? strongestTasteArtist({
  required List<Track> library,
  required Set<String> favoriteIds,
  required List<MusicPlaylist> playlists,
  required List<Track> history,
}) {
  final byId = {for (final track in library) track.id: track};
  final scores = <String, double>{};
  final names = <String, String>{};
  String key(Track track) => track.artist.trim().toLowerCase();
  void add(Track track, double weight) {
    final artist = key(track);
    if (artist.isEmpty) return;
    names[artist] = track.artist.trim();
    scores.update(artist, (score) => score + weight, ifAbsent: () => weight);
  }

  for (final id in favoriteIds) {
    final track = byId[id];
    if (track != null) add(track, 4);
  }
  for (final id in playlists.expand((playlist) => playlist.trackIds).toSet()) {
    final track = byId[id];
    if (track != null) add(track, 1.5);
  }
  for (var i = 0; i < history.length; i++) {
    add(byId[history[i].id] ?? history[i], 2.5 / (1 + i / 4));
  }

  if (scores.isEmpty) return null;
  final strongest = scores.keys.toList()
    ..sort((a, b) {
      final scoreOrder = scores[b]!.compareTo(scores[a]!);
      return scoreOrder != 0 ? scoreOrder : a.compareTo(b);
    });
  return names[strongest.first];
}

List<TrackRecommendation> recommendTracks({
  required List<Track> library,
  required Set<String> favoriteIds,
  required List<MusicPlaylist> playlists,
  required List<Track> history,
  String? currentTrackId,
  int limit = 6,
  DjFilters filters = const DjFilters(),
}) {
  final byId = {for (final track in library) track.id: track};
  final playlistIds = playlists.expand((playlist) => playlist.trackIds).toSet();
  final artistAffinity = <String, double>{};
  final recency = <String, double>{};
  final exactHistory = history.map((track) => track.id).toSet();
  final likedArtists = <String>{};
  final genreAffinity = <String, double>{};
  void addGenres(Track track, double weight) {
    for (final genre in track.genres.map(DjFilters.normalize).toSet()) {
      if (genre.isNotEmpty) {
        genreAffinity.update(
          genre,
          (score) => score + weight,
          ifAbsent: () => weight,
        );
      }
    }
  }

  String artistKey(Track track) => track.artist.trim().toLowerCase();

  for (final id in favoriteIds) {
    final track = byId[id];
    if (track == null) continue;
    addGenres(track, 4);
    final artist = artistKey(track);
    if (artist.isNotEmpty) {
      likedArtists.add(artist);
      artistAffinity.update(artist, (score) => score + 4, ifAbsent: () => 4);
    }
  }
  for (final id in playlistIds) {
    final track = byId[id];
    if (track == null) continue;
    addGenres(track, 1.5);
    final artist = artistKey(track);
    if (artist.isNotEmpty) {
      artistAffinity.update(
        artist,
        (score) => score + 1.5,
        ifAbsent: () => 1.5,
      );
    }
  }
  for (var i = 0; i < history.length; i++) {
    final track = byId[history[i].id] ?? history[i];
    addGenres(track, 2.5 / (1 + i / 4));
    final artist = artistKey(track);
    if (artist.isEmpty) continue;
    final weight = 2.5 / (1 + i / 4);
    recency[artist] = (recency[artist] ?? 0) + weight;
    artistAffinity.update(
      artist,
      (score) => score + weight,
      ifAbsent: () => weight,
    );
  }

  final hasSignals =
      favoriteIds.any(byId.containsKey) ||
      playlistIds.any(byId.containsKey) ||
      history.isNotEmpty;
  if (limit <= 0) return const [];
  final candidates = library.where((track) {
    return filters.permits(track) &&
        track.id != currentTrackId &&
        !favoriteIds.contains(track.id) &&
        !track.isPendingSpotifyMatch &&
        (track.isLocal || track.pageUrl != null);
  }).toList();
  if (!hasSignals) {
    candidates.sort((a, b) {
      final artistOrder = artistKey(a).compareTo(artistKey(b));
      return artistOrder != 0 ? artistOrder : a.title.compareTo(b.title);
    });
  } else {
    double score(Track track) =>
        (playlistIds.contains(track.id) ? 1.5 : 0) +
        (artistAffinity[artistKey(track)] ?? 0) +
        track.genres
            .map(DjFilters.normalize)
            .toSet()
            .fold<double>(
              0,
              (total, genre) => total + (genreAffinity[genre] ?? 0),
            ) +
        (exactHistory.contains(track.id) ? -2.0 : 0);
    candidates.sort((a, b) {
      final order = score(b).compareTo(score(a));
      if (order != 0) return order;
      final artistOrder = artistKey(a).compareTo(artistKey(b));
      return artistOrder != 0 ? artistOrder : a.title.compareTo(b.title);
    });
  }

  final selected = <Track>[];
  final artistCounts = <String, int>{};
  final selectedKeys = <String>{};
  for (final track in candidates) {
    final keys = recommendationTrackKeys(track);
    if (keys.any(selectedKeys.contains) ||
        (artistCounts[artistKey(track)] ?? 0) >= 2) {
      continue;
    }
    selectedKeys.addAll(keys);
    selected.add(track);
    artistCounts.update(
      artistKey(track),
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    if (selected.length >= limit) break;
  }
  return [
    for (final track in selected)
      TrackRecommendation(
        track: track,
        reason: !hasSignals
            ? 'De tu biblioteca'
            : likedArtists.contains(artistKey(track))
            ? 'Porque te gusta ${track.artist}'
            : playlistIds.contains(track.id)
            ? 'Está en tus listas'
            : recency.containsKey(artistKey(track))
            ? 'Por tu escucha reciente de ${track.artist}'
            : track.genres
                  .map(DjFilters.normalize)
                  .any(genreAffinity.containsKey)
            ? 'Porque coincide con tus g\u00e9neros favoritos'
            : (artistAffinity[artistKey(track)] ?? 0) > 0
            ? 'Por afinidad con tus gustos'
            : 'De tu biblioteca',
      ),
  ];
}
