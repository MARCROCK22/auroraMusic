// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from NuclearPlayer/nuclear-plugin-something; see third_party/nuclear_spotify/NOTICE.
import 'dart:convert';
import '../../core/models.dart';
import 'spotify_auth.dart';
import 'spotify_models.dart';
export 'spotify_models.dart';
export 'spotify_auth.dart' show SpotifyTransport, SpotifyResponse;

/// Metadata only. Returned tracks require an explicit match to Aurora's audio sources.
class SpotifyMetadataProvider {
  SpotifyMetadataProvider({
    SpotifyTransport? transport,
    DateTime Function()? clock,
  }) : _network = SpotifyNetwork(transport),
       _clock = clock ?? DateTime.now {
    _auth = SpotifyAuth(_network, _clock);
  }
  final SpotifyNetwork _network;
  final DateTime Function() _clock;
  late final SpotifyAuth _auth;
  final Map<String, ({DateTime fetched, Map<String, dynamic> data})> _cache =
      {};
  final Map<String, Future<Map<String, dynamic>>> _pending = {};
  bool _closed = false;
  static const _hashes = {
    'searchArtists':
        '0e6f9020a66fe15b93b3bb5c7e6484d1d8cb3775963996eaede72bac4d97e909',
    'searchAlbums':
        'a71d2c993fc98e1c880093738a55a38b57e69cc4ce5a8c113e6c5920f9513ee2',
    'searchTracks':
        'bc1ca2fcd0ba1013a0fc88e6cc4f190af501851e3dafd3e1ef85840297694428',
    'searchPlaylists':
        'fc3a690182167dbad20ac7a03f842b97be4e9737710600874cb903f30112ad58',
    'queryArtistOverview':
        '1ac33ddab5d39a3a9c27802774e6d78b9405cc188c6f75aed007df2a32737c72',
    'getAlbum':
        '97dd13a1f28c80d66115a13697a7ffd94fe3bebdb94da42159456e1d82bfee76',
    'fetchPlaylist':
        'e578eda4f77aae54294a48eac85e2a42ddb203faf6ea12b3fddaec5aa32918a3',
  };

  Future<SpotifyMetadataPage> search(
    String query, {
    SpotifyEntityType type = SpotifyEntityType.track,
    int limit = 20,
    int offset = 0,
  }) async {
    _validatePage(limit, offset);
    query = query.trim();
    if (query.isEmpty || query.length > 300) {
      throw const SpotifyMetadataException(
        'Escribe una búsqueda de entre 1 y 300 caracteres.',
      );
    }
    final operation = switch (type) {
      SpotifyEntityType.track => 'searchTracks',
      SpotifyEntityType.artist => 'searchArtists',
      SpotifyEntityType.album => 'searchAlbums',
      SpotifyEntityType.playlist => 'searchPlaylists',
    };
    final field = switch (type) {
      SpotifyEntityType.track => 'tracksV2',
      SpotifyEntityType.artist => 'artists',
      SpotifyEntityType.album => 'albumsV2',
      SpotifyEntityType.playlist => 'playlists',
    };
    final data = await _query(operation, {
      'searchTerm': query,
      'limit': limit,
      'offset': offset,
      'numberOfTopResults': limit,
      'includeAudiobooks': false,
      'includeArtistHasConcertsField': false,
      'includePreReleases': false,
    });
    final search = _requiredMap(data['searchV2']);
    final section = _requiredMap(search[field]);
    final raw = _requiredItems(section['items']);
    final total = _total(section['totalCount'], raw.length + offset);
    try {
      return SpotifyMetadataPage(
        items: raw
            .map((item) => mapSpotifyEntity(item, type))
            .whereType<SpotifyMetadataEntity>()
            .toList(),
        total: total,
        offset: offset,
        nextOffset: _next(offset, raw.length, total),
      );
    } catch (_) {
      throw const SpotifyMetadataException(
        'Spotify cambió el formato de sus metadatos.',
      );
    }
  }

  Future<SpotifyMetadataDetails> details(
    SpotifyMetadataEntity entity, {
    int offset = 0,
    int limit = 50,
  }) async {
    if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
    _validatePage(limit, offset);
    final uri = normalizeSpotifyUri(entity.uri, entity.type);
    if (entity.type == SpotifyEntityType.track) {
      return SpotifyMetadataDetails(
        entity: entity,
        tracks: offset == 0 && entity.track != null ? [entity.track!] : [],
        total: entity.track == null ? 0 : 1,
      );
    }
    final operation = switch (entity.type) {
      SpotifyEntityType.artist => 'queryArtistOverview',
      SpotifyEntityType.album => 'getAlbum',
      SpotifyEntityType.playlist => 'fetchPlaylist',
      SpotifyEntityType.track => throw StateError('track'),
    };
    final data = await _query(operation, {
      'uri': uri,
      if (entity.type != SpotifyEntityType.playlist) 'locale': '',
      if (entity.type != SpotifyEntityType.artist) ...{
        'offset': offset,
        'limit': limit,
      },
    });
    try {
      final detail = _requiredMap(
        data[switch (entity.type) {
          SpotifyEntityType.artist => 'artistUnion',
          SpotifyEntityType.album => 'albumUnion',
          _ => 'playlistV2',
        }],
      );
      final mapped = mapSpotifyEntity(detail, entity.type) ?? entity;
      List<dynamic> raw;
      int total;
      if (entity.type == SpotifyEntityType.artist) {
        final top = _requiredItems(
          _requiredMap(
            _requiredMap(detail['discography'])['topTracks'],
          )['items'],
        );
        // topTracks son solo 10: el catálogo sale de sus álbumes y sencillos.
        final all = _artistCatalog[uri] ??= await _artistTracks(detail, top);
        final page = all.skip(offset).take(limit).toList();
        final bio = spotifyMap(
          spotifyMap(detail['profile'])['biography'],
        )['text'];
        return SpotifyMetadataDetails(
          entity: mapped,
          description: bio is String ? bio : '',
          tracks: page,
          total: all.length,
          nextOffset: _next(offset, page.length, all.length),
        );
      } else {
        final section = _requiredMap(
          detail[entity.type == SpotifyEntityType.album
              ? 'tracksV2'
              : 'content'],
        );
        raw = _requiredItems(section['items']);
        total = _total(section['totalCount'], raw.length + offset);
      }
      final tracks = <Track>[];
      final seen = <String>{};
      for (final item in raw) {
        var trackData = spotifyMap(item);
        if (trackData.containsKey('track')) {
          trackData = spotifyMap(trackData['track']);
        }
        if (entity.type == SpotifyEntityType.album &&
            !trackData.containsKey('albumOfTrack')) {
          trackData = {...trackData, 'albumOfTrack': detail};
        }
        final track = mapSpotifyEntity(
          trackData,
          SpotifyEntityType.track,
        )?.track;
        if (track != null && seen.add(track.id)) tracks.add(track);
      }
      final description = entity.type == SpotifyEntityType.artist
          ? spotifyMap(spotifyMap(detail['profile'])['biography'])['text']
          : detail['description'];
      return SpotifyMetadataDetails(
        entity: mapped,
        description: description is String ? description : '',
        tracks: tracks,
        total: total,
        nextOffset: _next(offset, raw.length, total),
      );
    } on SpotifyMetadataException {
      rethrow;
    } catch (_) {
      throw const SpotifyMetadataException(
        'Spotify cambió el formato de sus metadatos.',
      );
    }
  }

  final Map<String, List<Track>> _artistCatalog = {};
  static const _maxReleases = 30;

  /// Destacadas + pistas de álbumes, sencillos y populares (sin recopilatorios).
  Future<List<Track>> _artistTracks(
    Map<String, dynamic> detail,
    List<dynamic> top,
  ) async {
    if (_artistCatalog.length > 20) _artistCatalog.clear();
    final out = <Track>[];
    final seen = <String>{};
    void add(Track? t) {
      if (t != null && seen.add(t.id)) out.add(t);
    }

    for (final item in top) {
      var data = spotifyMap(item);
      if (data.containsKey('track')) data = spotifyMap(data['track']);
      add(mapSpotifyEntity(data, SpotifyEntityType.track)?.track);
    }
    final discography = spotifyMap(detail['discography']);
    final releases = <SpotifyMetadataEntity>[];
    final uris = <String>{};
    for (final key in const ['albums', 'singles', 'popularReleasesAlbums']) {
      for (final group in spotifyItems(spotifyMap(discography[key])['items'])) {
        final nested = spotifyMap(spotifyMap(group)['releases'])['items'];
        for (final release in nested == null ? [group] : spotifyItems(nested)) {
          final album = mapSpotifyEntity(release, SpotifyEntityType.album);
          if (album != null && uris.add(album.uri)) releases.add(album);
        }
      }
    }
    final wanted = releases.take(_maxReleases).toList();
    for (var i = 0; i < wanted.length && !_closed; i += 4) {
      final batch = await Future.wait(
        wanted
            .skip(i)
            .take(4)
            .map(
              (album) => details(album, limit: 50).then<List<Track>>(
                (d) => d.tracks,
                onError: (Object _) => const <Track>[],
              ),
            ),
      );
      for (final tracks in batch) {
        tracks.forEach(add);
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> _query(
    String operation,
    Map<String, Object> variables,
  ) {
    if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
    final body = jsonEncode({
      'operationName': operation,
      'variables': variables,
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': _hashes[operation]},
      },
    });
    final cached = _cache[body];
    if (cached != null &&
        _clock().difference(cached.fetched) < const Duration(minutes: 5)) {
      return Future.value(cached.data);
    }
    if (_pending.containsKey(body)) return _pending[body]!;
    if (_pending.length >= 100) {
      throw const SpotifyMetadataException(
        'Hay demasiadas consultas pendientes. Intenta nuevamente.',
      );
    }
    return _pending[body] = _fetch(body)
        .then((data) {
          if (!_closed) {
            _cache.remove(body);
            if (_cache.length >= 128) _cache.remove(_cache.keys.first);
            _cache[body] = (fetched: _clock(), data: data);
          }
          return data;
        })
        .whenComplete(() {
          _pending.remove(body);
        });
  }

  Future<Map<String, dynamic>> _fetch(String body) async {
    var token = await _auth.token();
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _network.request(
        Uri.parse('https://api-partner.spotify.com/pathfinder/v2/query'),
        method: 'POST',
        body: body,
        headers: {
          ...spotifyBrowserHeaders,
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 401 && attempt == 0) {
        token = await _auth.token(rejectedToken: token);
        continue;
      }
      final data = _network.decode(response);
      if (data.containsKey('errors')) {
        throw const SpotifyMetadataException(
          'Spotify rechazó la consulta. Su interfaz privada puede haber cambiado.',
        );
      }
      return _requiredMap(data['data']);
    }
    throw const SpotifyMetadataException(
      'No se pudo renovar la autorización de Spotify.',
    );
  }

  void close() {
    _closed = true;
    _cache.clear();
    _auth.close();
    _network.close();
  }
}

Map<String, dynamic> _requiredMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const SpotifyMetadataException(
      'Spotify cambió el formato de sus metadatos.',
    );
  }
  return value;
}

List<dynamic> _requiredItems(Object? value) {
  if (value is! List) {
    throw const SpotifyMetadataException(
      'Spotify cambió el formato de sus metadatos.',
    );
  }
  return value;
}

int _total(Object? value, int fallback) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : fallback;
int? _next(int offset, int count, int total) =>
    count > 0 && offset + count < total ? offset + count : null;
void _validatePage(int limit, int offset) {
  if (limit < 1 || limit > 100 || offset < 0 || offset > 100000) {
    throw const SpotifyMetadataException('Página de Spotify inválida.');
  }
}
