import 'dart:convert';

import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/reco_memory.dart';

/// Versión del cliente enviada como `submission_client_version`.
// shortcut: versión fija como en LyricsService; actualizar al subir de versión.
const kListenBrainzClientVersion = '1.2.4';

/// Tamaño máximo documentado por listen (bytes de su JSON).
const kMaxListenBytes = 10240;

/// Un listen: una pista escuchada que se publica en ListenBrainz.
/// Nunca contiene credenciales; se guarda tal cual en la cola de disco.
class Listen {
  const Listen({
    required this.artist,
    required this.title,
    required this.listenedAt,
    this.album,
    this.durationMs,
    this.originUrl,
    this.musicService,
  });

  final String artist, title;

  /// Inicio de la reproducción, Unix UTC en segundos.
  final int listenedAt;
  final String? album, originUrl, musicService;
  final int? durationMs;

  /// `playing_now` no lleva `listened_at`.
  Map<String, Object?> toPayload({bool playingNow = false}) => {
    if (!playingNow) 'listened_at': listenedAt,
    'track_metadata': {
      'artist_name': artist,
      'track_name': title,
      if (album != null) 'release_name': album,
      'additional_info': {
        'submission_client': 'Aurora',
        'submission_client_version': kListenBrainzClientVersion,
        if (musicService != null) 'music_service': musicService,
        if (originUrl != null) 'origin_url': originUrl,
        if (durationMs != null) 'duration_ms': durationMs,
      },
    },
  };

  Map<String, Object?> toJson() => {
    'artist': artist,
    'title': title,
    'at': listenedAt,
    if (album != null) 'album': album,
    if (durationMs != null) 'ms': durationMs,
    if (originUrl != null) 'url': originUrl,
    if (musicService != null) 'svc': musicService,
  };

  /// `null` si el registro del disco no es válido.
  static Listen? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artist = raw['artist'], title = raw['title'], at = raw['at'];
    if (artist is! String || title is! String || at is! int) return null;
    if (artist.trim().isEmpty || title.trim().isEmpty) return null;
    String? str(String key) => raw[key] is String ? raw[key] as String : null;
    return Listen(
      artist: artist,
      title: title,
      listenedAt: at,
      album: str('album'),
      durationMs: raw['ms'] is int ? raw['ms'] as int : null,
      originUrl: str('url'),
      musicService: str('svc'),
    );
  }

  int get payloadBytes => utf8.encode(jsonEncode(toPayload())).length;
}

final _topic = RegExp(r'\s+-\s+topic\s*$', caseSensitive: false);
final _noise = RegExp(
  r'\s*[(\[][^)\]]*\b(?:official|oficial|video|vídeo|audio|lyrics?|letra|visuali[sz]er|hd|hq|4k)\b[^)\]]*[)\]]',
  caseSensitive: false,
);
final _unknownArtist = RegExp(
  r'^(?:<unknown>|unknown(?: artist)?|artista desconocido|desconocido)$',
  caseSensitive: false,
);

/// Artista tal como se publica: sin « - Topic» de YouTube. `null` si no es fiable.
String? listenArtist(String raw) {
  final artist = raw.replaceAll(_topic, '').trim();
  if (artist.isEmpty || _unknownArtist.hasMatch(artist)) return null;
  // djArtists es la misma normalización que usa el DJ para separar colaboradores.
  return djArtists(artist).isEmpty ? null : artist;
}

/// Título sin «(Official Video)», «[Audio]»… `null` si no queda nada fiable.
String? listenTitle(String raw) {
  var title = raw.replaceAll(_noise, '').trim();
  if (title.isEmpty) title = raw.trim();
  return recsNormalizeTitle(title).isEmpty ? null : title;
}

/// Clave de identidad de «la misma canción» (para deduplicar).
String listenIdentity(Track track) => recsTrackKey(track);

/// Construye el listen de [track] o `null` si falta artista/título fiable o
/// se pasa del tamaño máximo. [duration] manda sobre `track.duration`.
Listen? buildListen(Track track, DateTime startedAt, {Duration? duration}) {
  final artist = listenArtist(track.artist), title = listenTitle(track.title);
  if (artist == null || title == null) return null;
  final length = (duration ?? Duration.zero) > Duration.zero
      ? duration!
      : track.duration;
  final page = track.pageUrl == null ? null : Uri.tryParse(track.pageUrl!);
  final web = page != null && page.hasScheme && page.scheme.startsWith('http');
  final youtube =
      web && (page.host.contains('youtube.') || page.host == 'youtu.be');
  final album = track.album?.trim();
  final listen = Listen(
    artist: artist,
    title: title,
    listenedAt: startedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    album: album == null || album.isEmpty ? null : album,
    durationMs: length > Duration.zero ? length.inMilliseconds : null,
    originUrl: web ? page.toString() : null,
    musicService: youtube ? 'youtube.com' : null,
  );
  return listen.payloadBytes > kMaxListenBytes ? null : listen;
}
