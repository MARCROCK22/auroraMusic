import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/reco_memory.dart';

/// Versión del cliente (User-Agent).
// shortcut: versión fija como en LyricsService; actualizar al subir de versión.
const kLastfmClientVersion = '1.4.0';

/// Una escucha que se publica en Last.fm. Nunca contiene credenciales; se
/// guarda tal cual en la cola de disco.
class Listen {
  const Listen({
    required this.artist,
    required this.title,
    required this.listenedAt,
    this.album,
    this.durationMs,
  });

  final String artist, title;

  /// Inicio de la reproducción, Unix UTC en segundos.
  final int listenedAt;
  final String? album;
  final int? durationMs;

  /// Parámetros de `track.scrobble` (con sufijo `[index]`) o de
  /// `track.updateNowPlaying` (sin índice ni marca de tiempo).
  Map<String, String> toParams({int? index, bool playingNow = false}) {
    String k(String n) => index == null ? n : '$n[$index]';
    return {
      k('artist'): artist,
      k('track'): title,
      if (!playingNow) k('timestamp'): '$listenedAt',
      k('album'): ?album,
      if (durationMs != null) k('duration'): '${durationMs! ~/ 1000}',
    };
  }

  Map<String, Object?> toJson() => {
    'artist': artist,
    'title': title,
    'at': listenedAt,
    if (album != null) 'album': album,
    if (durationMs != null) 'ms': durationMs,
  };

  /// `null` si el registro del disco no es válido.
  static Listen? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final artist = raw['artist'], title = raw['title'], at = raw['at'];
    if (artist is! String || title is! String || at is! int) return null;
    if (artist.trim().isEmpty || title.trim().isEmpty) return null;
    return Listen(
      artist: artist,
      title: title,
      listenedAt: at,
      album: raw['album'] is String ? raw['album'] as String : null,
      durationMs: raw['ms'] is int ? raw['ms'] as int : null,
    );
  }
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

/// Construye la escucha de [track] o `null` si falta artista/título fiable.
/// [duration] manda sobre `track.duration`.
Listen? buildListen(Track track, DateTime startedAt, {Duration? duration}) {
  final artist = listenArtist(track.artist), title = listenTitle(track.title);
  if (artist == null || title == null) return null;
  final length = (duration ?? Duration.zero) > Duration.zero
      ? duration!
      : track.duration;
  final album = track.album?.trim();
  return Listen(
    artist: artist,
    title: title,
    listenedAt: startedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    album: album == null || album.isEmpty ? null : album,
    durationMs: length > Duration.zero ? length.inMilliseconds : null,
  );
}
