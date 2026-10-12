// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from NuclearPlayer/nuclear-plugin-something; see third_party/nuclear_spotify/NOTICE.
import '../../core/models.dart';

enum SpotifyEntityType { track, artist, album, playlist }

class SpotifyMetadataEntity {
  const SpotifyMetadataEntity({
    required this.type,
    required this.uri,
    required this.name,
    this.subtitle = '',
    this.artworkUrl,
    this.track,
  });
  final SpotifyEntityType type;
  final String uri;
  final String name;
  final String subtitle;
  final String? artworkUrl;
  final Track? track;
}

class SpotifyMetadataPage {
  SpotifyMetadataPage({
    required List<SpotifyMetadataEntity> items,
    required this.total,
    required this.offset,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final List<SpotifyMetadataEntity> items;
  final int total;
  final int offset;
  final int? nextOffset;
  bool get hasMore => nextOffset != null;
}

class SpotifyMetadataDetails {
  SpotifyMetadataDetails({
    required this.entity,
    this.description = '',
    required List<Track> tracks,
    required this.total,
    this.nextOffset,
  }) : tracks = List.unmodifiable(tracks);
  final SpotifyMetadataEntity entity;
  String get title => entity.name;
  final String description;
  final List<Track> tracks;
  final int total;
  final int? nextOffset;
  bool get hasMore => nextOffset != null;
}

class SpotifyMetadataException implements Exception {
  const SpotifyMetadataException(this.message);
  final String message;
  @override
  String toString() => message;
}

Map<String, dynamic> spotifyMap(Object? value) =>
    value is Map<String, dynamic> ? value : {};
List<dynamic> spotifyItems(Object? value) => value is List ? value : const [];

String normalizeSpotifyUri(String value, SpotifyEntityType type) {
  final pattern = RegExp('^spotify:${type.name}:([a-zA-Z0-9]{22})\$');
  if (pattern.hasMatch(value)) return value;
  final url = Uri.tryParse(value);
  if (url != null &&
      url.scheme == 'https' &&
      url.host == 'open.spotify.com' &&
      url.userInfo.isEmpty &&
      !url.hasPort &&
      RegExp('^/${type.name}/[a-zA-Z0-9]{22}\$').hasMatch(url.path)) {
    return 'spotify:${type.name}:${url.pathSegments[1]}';
  }
  throw const SpotifyMetadataException('Referencia de Spotify inválida.');
}

String? spotifyArtwork(Map<String, dynamic> data) {
  final sources = spotifyItems(spotifyMap(data['coverArt'])['sources']);

  return _artworkFrom(
    sources.isNotEmpty
        ? sources
        : [
            ...spotifyItems(
              spotifyMap(spotifyMap(data['visuals'])['avatarImage'])['sources'],
            ),
            ...spotifyItems(
              spotifyMap(data['images'])['items'],
            ).expand((image) => spotifyItems(spotifyMap(image)['sources'])),
          ],
  );
}

String? _artworkFrom(List<dynamic> sources) {
  for (final source in sources) {
    final value = spotifyMap(source)['url'];
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      return value as String;
    }
  }
  return null;
}

String spotifyArtists(Map<String, dynamic> data) =>
    spotifyItems(spotifyMap(data['artists'])['items'])
        .map((artist) {
          final raw = spotifyMap(artist);
          return spotifyMap(raw['profile'])['name'] ??
              spotifyMap(spotifyMap(raw['data'])['profile'])['name'];
        })
        .whereType<String>()
        .join(', ');

SpotifyMetadataEntity? mapSpotifyEntity(Object? raw, SpotifyEntityType type) {
  var data = spotifyMap(raw);
  if (data.containsKey('item')) data = spotifyMap(data['item']);
  if (data.containsKey('data')) data = spotifyMap(data['data']);
  if (data['__typename'] == 'NotFound' || data['__typename'] == 'PreRelease') {
    return null;
  }
  final uriValue = data['uri'];
  final name = type == SpotifyEntityType.artist
      ? spotifyMap(data['profile'])['name']
      : data['name'];
  if (uriValue is! String || name is! String || name.trim().isEmpty) {
    return null;
  }
  String uri;
  try {
    uri = normalizeSpotifyUri(uriValue, type);
  } on SpotifyMetadataException {
    return null;
  }
  final album = spotifyMap(data['albumOfTrack']);
  final artwork = spotifyArtwork(
    type == SpotifyEntityType.track ? album : data,
  );
  final artist = spotifyArtists(data);
  final duration = spotifyMap(
    data['duration'] ?? data['trackDuration'],
  )['totalMilliseconds'];
  return SpotifyMetadataEntity(
    type: type,
    uri: uri,
    name: name,
    subtitle: type == SpotifyEntityType.playlist
        ? (spotifyMap(spotifyMap(data['ownerV2'])['data'])['name'] as String? ??
              '')
        : artist,
    artworkUrl: artwork,
    track: type == SpotifyEntityType.track
        ? Track(
            id: uri,
            title: name,
            artist: artist.isEmpty ? 'Artista desconocido' : artist,
            album: album['name'] as String?,
            genres: spotifyItems(data['genres'])
                .whereType<String>()
                .map((genre) => genre.trim())
                .where((genre) => genre.isNotEmpty)
                .toSet()
                .toList(),
            artworkUrl: artwork,
            duration: Duration(
              milliseconds: duration is num && duration >= 0
                  ? duration.toInt()
                  : 0,
            ),
            spotifyUri: uri,
            spotifyMatchPending: true,
          )
        : null,
  );
}
