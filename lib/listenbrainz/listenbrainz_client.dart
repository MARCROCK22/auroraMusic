import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'listen.dart';

const kListenBrainzBase = 'https://api.listenbrainz.org';
const kListenBrainzUserAgent =
    'Aurora/$kListenBrainzClientVersion (https://github.com/kaz-py/auroraMusic)';

final _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);

/// Quita [token] (y cualquier cosa con forma de token UUID) de [text].
/// Todo texto que salga hacia logs, errores o UI pasa por aquí.
String redactToken(String text, [String? token]) {
  var out = text;
  if (token != null && token.trim().isNotEmpty) {
    out = out.replaceAll(token.trim(), '[token]');
  }
  return out.replaceAll(_uuid, '[token]');
}

class LbRequestData {
  const LbRequestData(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class LbResponse {
  const LbResponse(this.status, this.body, [this.headers = const {}]);
  final int status;
  final String body;

  /// Nombres en minúsculas.
  final Map<String, String> headers;
}

typedef LbTransport = Future<LbResponse> Function(LbRequestData request);

/// Error con mensaje ya redactado.
class ListenBrainzException implements Exception {
  ListenBrainzException(String message, [String? token])
    : message = redactToken(message, token);
  final String message;
  @override
  String toString() => 'ListenBrainzException: $message';
}

enum LbSubmitStatus { ok, rateLimited, unauthorized, rejected, retry }

class LbSubmitResult {
  const LbSubmitResult(this.status, [this.retryAfter]);
  final LbSubmitStatus status;
  final Duration? retryAfter;
}

/// Novedad devuelta por `fresh_releases`.
class FreshRelease {
  const FreshRelease({
    required this.artist,
    required this.title,
    this.releaseDate,
    this.type,
    this.mbid,
  });
  final String artist, title;
  final String? releaseDate, type, mbid;
}

/// Cliente HTTPS mínimo de la API de ListenBrainz. El token solo viaja en la
/// cabecera `Authorization`, nunca en la URL.
class ListenBrainzClient {
  ListenBrainzClient({LbTransport? transport, Uri? base})
    : _base = base ?? Uri.parse(kListenBrainzBase),
      _transport = transport ?? _httpTransport {
    if (_base.scheme != 'https') {
      throw ArgumentError('ListenBrainz solo se usa por HTTPS.');
    }
  }

  final Uri _base;
  final LbTransport _transport;

  static const _timeout = Duration(seconds: 20);

  static Future<LbResponse> _httpTransport(LbRequestData r) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(r.method, r.uri).timeout(_timeout);
      r.headers.forEach(request.headers.set);
      if (r.body != null) request.add(utf8.encode(r.body!));
      final response = await request.close().timeout(_timeout);
      final body = await utf8.decodeStream(response).timeout(_timeout);
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(','),
      );
      return LbResponse(response.statusCode, body, headers);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, String> _headers(String? token, {bool json = false}) => {
    'User-Agent': kListenBrainzUserAgent,
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Token $token',
  };

  Future<LbResponse> _send(
    String method,
    String path,
    String? token, {
    String? body,
  }) async {
    try {
      return await _transport(
        LbRequestData(
          method,
          _base.resolve(path),
          _headers(token, json: body != null),
          body,
        ),
      );
    } on Object catch (error) {
      throw ListenBrainzException(
        'Sin conexión con ListenBrainz: $error',
        token,
      );
    }
  }

  Object? _json(LbResponse r) {
    try {
      return jsonDecode(r.body);
    } on FormatException {
      return null;
    }
  }

  /// Nombre de usuario si el token es válido, `null` si no lo es.
  /// Lanza [ListenBrainzException] si no se pudo comprobar.
  Future<String?> validateToken(String token) async {
    final r = await _send('GET', '/1/validate-token', token);
    if (r.status == 200) {
      final json = _json(r);
      if (json is Map && json['valid'] == true && json['user_name'] is String) {
        return json['user_name'] as String;
      }
      return null;
    }
    if (r.status == 401) return null;
    throw ListenBrainzException('ListenBrainz respondió ${r.status}.', token);
  }

  /// `type`: `single`, `playing_now` o `import`.
  Future<LbSubmitResult> submit(
    String token,
    String type,
    List<Listen> listens,
  ) async {
    final body = jsonEncode({
      'listen_type': type,
      'payload': [
        for (final l in listens) l.toPayload(playingNow: type == 'playing_now'),
      ],
    });
    final LbResponse r;
    try {
      r = await _send('POST', '/1/submit-listens', token, body: body);
    } on ListenBrainzException {
      return const LbSubmitResult(LbSubmitStatus.retry);
    }
    return switch (r.status) {
      200 => const LbSubmitResult(LbSubmitStatus.ok),
      429 => LbSubmitResult(LbSubmitStatus.rateLimited, _retryAfter(r)),
      401 => const LbSubmitResult(LbSubmitStatus.unauthorized),
      400 => const LbSubmitResult(LbSubmitStatus.rejected),
      _ => LbSubmitResult(LbSubmitStatus.retry, _retryAfter(r)),
    };
  }

  /// Respeta `X-RateLimit-Reset-In` (segundos); 5 s si no viene.
  Duration? _retryAfter(LbResponse r) {
    final seconds = int.tryParse(r.headers['x-ratelimit-reset-in'] ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds.clamp(1, 3600));
    }
    return r.status == 429 ? const Duration(seconds: 5) : null;
  }

  /// Novedades personalizadas por historial (`/1/user/<user>/fresh_releases`).
  Future<List<FreshRelease>> freshReleases(String user) async {
    final r = await _send(
      'GET',
      '/1/user/${Uri.encodeComponent(user)}/fresh_releases',
      null,
    );
    if (r.status != 200) {
      throw ListenBrainzException('ListenBrainz respondió ${r.status}.');
    }
    final json = _json(r);
    final releases = json is Map && json['payload'] is Map
        ? (json['payload'] as Map)['releases']
        : null;
    if (releases is! List) return const [];
    return [
      for (final item in releases)
        if (item is Map &&
            item['artist_credit_name'] is String &&
            item['release_name'] is String)
          FreshRelease(
            artist: item['artist_credit_name'] as String,
            title: item['release_name'] as String,
            releaseDate: _str(item['release_date']),
            type: _str(item['release_group_primary_type']),
            mbid: _str(item['release_mbid']),
          ),
    ];
  }

  static String? _str(Object? v) => v is String ? v : null;

  Future<Object?> _get(String path, String token) async {
    final r = await _send('GET', path, token);
    if (r.status == 204) return null; // aún sin datos para este usuario
    if (r.status == 429) {
      throw ListenBrainzRateLimited(
        _retryAfter(r) ?? const Duration(seconds: 5),
      );
    }
    if (r.status != 200) {
      throw ListenBrainzException('ListenBrainz respondió ${r.status}.', token);
    }
    return _json(r);
  }

  static String? _mbidOf(Object? identifier) {
    final id = identifier is String ? identifier.split('/').last : null;
    return id != null && RegExp(r'^[0-9a-f-]{36}$').hasMatch(id) ? id : null;
  }

  /// MBID y título de las listas «Created for You» (Daily/Weekly Jams…).
  Future<List<({String mbid, String title})>> createdForYou(
    String user,
    String token,
  ) async {
    final json = await _get(
      '/1/user/${Uri.encodeComponent(user)}/playlists/createdfor',
      token,
    );
    final items = json is Map ? json['playlists'] : null;
    if (items is! List) return const [];
    return [
      for (final item in items)
        if (item is Map && item['playlist'] is Map)
          if (_mbidOf((item['playlist'] as Map)['identifier']) case final id?)
            (mbid: id, title: _str((item['playlist'] as Map)['title']) ?? ''),
    ];
  }

  /// Pistas de una lista (JSPF con `fetch_metadata`).
  Future<List<LbTrack>> playlistTracks(String mbid, String token) async {
    final json = await _get(
      '/1/playlist/${Uri.encodeComponent(mbid)}?fetch_metadata=true',
      token,
    );
    final tracks = json is Map && json['playlist'] is Map
        ? (json['playlist'] as Map)['track']
        : null;
    if (tracks is! List) return const [];
    return [
      for (final t in tracks)
        if (t is Map &&
            _str(t['title'])?.trim().isNotEmpty == true &&
            _str(t['creator'])?.trim().isNotEmpty == true)
          LbTrack(
            title: t['title'] as String,
            artist: t['creator'] as String,
            album: _str(t['album']),
            duration: Duration(
              milliseconds: t['duration'] is int ? t['duration'] as int : 0,
            ),
            mbid: _mbidOf(
              t['identifier'] is List && (t['identifier'] as List).isNotEmpty
                  ? (t['identifier'] as List).first
                  : t['identifier'],
            ),
          ),
    ];
  }

  /// Filtrado colaborativo (experimental): solo MBID de grabaciones.
  Future<List<String>> cfRecordingMbids(
    String user,
    String token, {
    int count = 25,
  }) async {
    final json = await _get(
      '/1/cf/recommendation/user/${Uri.encodeComponent(user)}/recording?count=$count',
      token,
    );
    final payload = json is Map ? json['payload'] : null;
    final mbids = payload is Map ? payload['mbids'] : null;
    if (mbids is! List) return const [];
    return [
      for (final m in mbids)
        if (m is Map && m['recording_mbid'] is String)
          m['recording_mbid'] as String,
    ];
  }

  /// Título, artista y etiquetas de grabaciones por MBID.
  Future<List<LbTrack>> recordingMetadata(
    List<String> mbids,
    String token,
  ) async {
    final valid = mbids.where((m) => _mbidOf(m) != null).toList();
    if (valid.isEmpty) return const [];
    final json = await _get(
      '/1/metadata/recording/?recording_mbids=${valid.join(',')}&inc=artist+tag',
      token,
    );
    if (json is! Map) return const [];
    final out = <LbTrack>[];
    for (final mbid in valid) {
      final m = json[mbid];
      if (m is! Map) continue;
      final recording = m['recording'], artist = m['artist'];
      final title = recording is Map ? _str(recording['name']) : null;
      final name = artist is Map ? _str(artist['name']) : null;
      if (title == null || name == null) continue;
      final tags = <String>[];
      final tag = m['tag'];
      if (tag is Map) {
        for (final key in const ['recording', 'artist']) {
          final list = tag[key];
          if (list is List) {
            for (final t in list) {
              final v = t is Map ? _str(t['tag']) : null;
              if (v != null) tags.add(v);
            }
          }
        }
      }
      out.add(
        LbTrack(
          title: title,
          artist: name,
          duration: Duration(
            milliseconds: recording is Map && recording['length'] is int
                ? recording['length'] as int
                : 0,
          ),
          mbid: mbid,
          tags: tags.take(3).toList(),
        ),
      );
    }
    return out;
  }
}

/// 429: [retryAfter] sale de `X-RateLimit-Reset-In`.
class ListenBrainzRateLimited extends ListenBrainzException {
  ListenBrainzRateLimited(this.retryAfter) : super('Límite de peticiones.');
  final Duration retryAfter;
}

/// Pista de una lista o recomendación, con lo que ListenBrainz sabe de ella.
class LbTrack {
  const LbTrack({
    required this.title,
    required this.artist,
    this.album,
    this.duration = Duration.zero,
    this.mbid,
    this.tags = const [],
  });
  final String title, artist;
  final String? album, mbid;
  final Duration duration;
  final List<String> tags;
}
