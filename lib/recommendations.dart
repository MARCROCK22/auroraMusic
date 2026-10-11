import 'core/models.dart';

class TrackRecommendation {
  const TrackRecommendation({required this.track, required this.reason});

  final Track track;
  final String reason;
}

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
}) {
  final byId = {for (final track in library) track.id: track};
  final playlistIds = playlists.expand((playlist) => playlist.trackIds).toSet();
  final artistAffinity = <String, double>{};
  final recency = <String, double>{};
  final exactHistory = history.map((track) => track.id).toSet();
  final likedArtists = <String>{};

  String artistKey(Track track) => track.artist.trim().toLowerCase();

  for (final id in favoriteIds) {
    final track = byId[id];
    if (track == null) continue;
    final artist = artistKey(track);
    if (artist.isNotEmpty) {
      likedArtists.add(artist);
      artistAffinity.update(artist, (score) => score + 4, ifAbsent: () => 4);
    }
  }
  for (final id in playlistIds) {
    final track = byId[id];
    if (track == null) continue;
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
    return track.id != currentTrackId &&
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
  for (final track in candidates) {
    if ((artistCounts[artistKey(track)] ?? 0) >= 2) continue;
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
            : 'Por tus listas y gustos',
      ),
  ];
}
