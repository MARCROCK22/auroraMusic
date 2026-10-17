import 'dart:async';
import 'dart:convert';

import '../core/models.dart';
import '../core/source_backend.dart';
import '../dj/ai_dj.dart';
import '../dj/reco_memory.dart';

/// Etiquetas de versión que penalizan si el candidato las trae y el original no.
const _versionTags = <String>[
  r'\b(live|en vivo|en directo|concert)\b',
  r'\b(cover|tribute|tributo)\b',
  r'\b(karaoke|karaoké|backing track)\b',
  r'\b(sped up|speed up|nightcore|8d)\b',
  r'\b(slowed|reverb)\b',
  r'\b(remix|mashup|bootleg)\b',
  r'\b(acoustic|acústic[ao])\b',
];

Set<String> _tokens(String normalized) =>
    normalized.split(' ').where((t) => t.isNotEmpty).toSet();

/// Igual o a una edición de distancia (solo palabras largas).
bool _close(String a, String b) {
  if (a == b) return true;
  if (a.length < 5 || b.length < 5 || (a.length - b.length).abs() > 1) {
    return false;
  }
  var i = 0, j = 0, diff = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      i++;
      j++;
    } else if (++diff > 1) {
      return false;
    } else if (a.length > b.length) {
      i++;
    } else if (b.length > a.length) {
      j++;
    } else {
      i++;
      j++;
    }
  }
  return true;
}

/// Dice de tokens (títulos normalizados) con tolerancia a una errata.
double titleSimilarity(String a, String b) {
  final ta = _tokens(recsNormalizeTitle(a)),
      tb = _tokens(recsNormalizeTitle(b));
  if (ta.isEmpty || tb.isEmpty) return ta.isEmpty && tb.isEmpty ? 1 : 0;
  final hits = ta.where((x) => tb.any((y) => _close(x, y))).length;
  return 2 * hits / (ta.length + tb.length);
}

String _plain(String s) => recsNormalizeTitle(s.replaceAll(' - Topic', ''));

double _artistScore(Track spotify, Track cand) {
  final want = djArtists(spotify.artist).map(_plain).toList();
  if (want.isEmpty) return 0.5;
  // El título del vídeo a veces trae el artista («Artista - Canción»).
  final haystack = '${_plain(cand.artist)} ${_plain(cand.title)}';
  final have = djArtists(cand.artist).map(_plain).toSet();
  bool found(String a) =>
      a.isNotEmpty &&
      (have.any((h) => h == a || _close(h, a)) ||
          RegExp('(^| )${RegExp.escape(a)}( |\$)').hasMatch(haystack));
  final primary = found(want.first) ? 1.0 : 0.0;
  if (want.length == 1) return primary;
  final rest = want.skip(1).where(found).length / (want.length - 1);
  return 0.7 * primary + 0.3 * rest;
}

/// 1 hasta ±3 s, baja a 0.5 en ±8 s y a 0 hacia ±30 s; sin dato = neutro.
double _durationScore(Duration a, Duration b) {
  if (a == Duration.zero || b == Duration.zero) return 0.5;
  final d = (a - b).inMilliseconds.abs() / 1000;
  if (d <= 3) return 1;
  if (d <= 8) return 1 - 0.5 * (d - 3) / 5;
  return (0.5 - (d - 8) / 44).clamp(0.0, 0.5);
}

/// Parecido en [0, 1] entre una pista de Spotify y un candidato de YouTube.
double scoreYoutubeMatch(Track spotify, Track cand) {
  final title = titleSimilarity(spotify.title, cand.title);
  final artist = _artistScore(spotify, cand);
  // Sin coincidencia de artista o de título no hay emparejamiento posible.
  if (title < 0.4 || artist == 0) return 0.3 * title * artist;
  var score =
      0.45 * title +
      0.30 * artist +
      0.20 * _durationScore(spotify.duration, cand.duration);
  final sa = spotify.album?.toLowerCase() ?? '';
  final ca = cand.album?.toLowerCase() ?? '';
  if (sa.isNotEmpty && ca.isNotEmpty) score += 0.05 * titleSimilarity(sa, ca);
  final orig = '${spotify.title} ${spotify.album ?? ''}'.toLowerCase();
  final text = cand.title.toLowerCase();
  var penalty = 0.0;
  for (final pattern in _versionTags) {
    final r = RegExp(pattern);
    if (r.hasMatch(text) && !r.hasMatch(orig)) penalty += 0.25;
  }
  score -= penalty.clamp(0.0, 0.6);
  // Más de 15 s de diferencia suele ser otra versión (extendida, en vivo...).
  if (spotify.duration > Duration.zero &&
      cand.duration > Duration.zero &&
      (spotify.duration - cand.duration).inSeconds.abs() > 15) {
    score -= 0.15;
  }
  final channel = cand.artist.toLowerCase();
  if (channel.endsWith('- topic') || channel.contains('vevo')) score += 0.04;
  if (RegExp(r'official audio|audio oficial').hasMatch(text)) score += 0.03;
  final lyrics = RegExp(r'\blyrics?\b|\bletra\b');
  if (lyrics.hasMatch(text) && !lyrics.hasMatch(orig)) score -= 0.03;
  return score.clamp(0.0, 1.0);
}

class YoutubeMatch {
  const YoutubeMatch(this.track, this.confidence);
  final Track track;
  final double confidence;
}

/// Busca en YouTube Music la pista MÁS PARECIDA a una de Spotify.
/// [search] hace la búsqueda real (InnerTube `searchPage`); el resultado se
/// guarda en caché (SharedPreferences, como el resto de la memoria del DJ).
/// ISRC: YouTube Music no permite buscar por ISRC y Track no lo guarda, así
/// que el emparejamiento es por título/artistas/duración/álbum.
class YoutubeMatcher {
  YoutubeMatcher({
    required this.search,
    this.threshold = 0.62,
    this.persist = true,
    this.cacheKey = 'ytMatchCache',
    this.maxCache = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<List<Track>> Function(String query, SearchKind kind) search;
  final double threshold;
  final bool persist;
  final String cacheKey;
  final int maxCache;
  final DateTime Function() _clock;
  final _cache = <String, Map<String, Object?>>{};
  Future<void>? _loading;
  static const _missTtl = Duration(days: 1);

  static String keyOf(Track s) =>
      s.spotifyUri ?? '${recsTrackKey(s)}|${s.duration.inSeconds ~/ 5}';

  Future<void> _load() async {
    if (!persist) return;
    final raw = (await recsPrefs())?.getString(cacheKey);
    if (raw == null) return;
    try {
      (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
        if (v is Map<String, dynamic>) _cache.putIfAbsent(k, () => v);
      });
    } catch (_) {}
  }

  /// Mejor candidato aceptado, o null si ninguno llega a [threshold].
  Future<YoutubeMatch?> match(Track spotify) async {
    await (_loading ??= _load());
    final key = keyOf(spotify), now = _clock();
    final hit = _cache[key];
    if (hit != null) {
      final track = hit['track'];
      if (track is Map<String, dynamic>) {
        return YoutubeMatch(
          Track.fromJson(track),
          (hit['confidence'] as num).toDouble(),
        );
      }
      final at = DateTime.fromMillisecondsSinceEpoch(hit['at'] as int? ?? 0);
      if (now.difference(at) < _missTtl) return null; // fallo reciente
    }
    final best = await _best(spotify);
    _cache.remove(key);
    _cache[key] = {
      'at': now.millisecondsSinceEpoch,
      if (best != null) ...{
        'track': best.track.toJson(),
        'confidence': best.confidence,
      },
    };
    while (_cache.length > maxCache) {
      _cache.remove(_cache.keys.first);
    }
    if (persist) {
      final prefs = await recsPrefs();
      await prefs?.setString(cacheKey, jsonEncode(_cache));
    }
    return best;
  }

  Future<YoutubeMatch?> _best(Track spotify) async {
    final query =
        '${spotify.title} ${djArtists(spotify.artist).take(2).join(' ')}';
    YoutubeMatch? best;
    // Canciones primero; vídeos solo si ninguna canción llega al umbral.
    for (final kind in [SearchKind.songs, SearchKind.videos]) {
      List<Track> found;
      try {
        found = await search(query, kind);
      } catch (_) {
        continue;
      }
      for (final c in found.take(10)) {
        if (!c.id.startsWith('yt:')) continue;
        final s = scoreYoutubeMatch(spotify, c);
        if (best == null || s > best.confidence) best = YoutubeMatch(c, s);
      }
      if (best != null && best.confidence >= threshold) return best;
    }
    return null;
  }
}
