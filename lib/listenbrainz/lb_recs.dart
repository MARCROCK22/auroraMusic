import 'dart:math' as math;

import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/suggestions_api.dart';
import '../metadata/youtube_match.dart';
import 'listenbrainz_client.dart';

/// Fuente de candidatos del DJ con las recomendaciones de ListenBrainz del
/// propio usuario (su token): primero las listas «Created for You»; si no hay,
/// el filtrado colaborativo (experimental, solo MBID → se resuelven por
/// metadatos). Cada pista se empareja con YouTube vía [matcher]. El prior es
/// bajo (0,4 × confianza): el perfil local manda. Todo fallo (204, 429, 5xx,
/// timeout, sin token) devuelve lista vacía y el DJ sigue con lo local; el
/// coherence filter y la memoria anti-repetición los aplica el SuggestionsApi.
class LbRecsSource {
  LbRecsSource({
    required this.client,
    required this.matcher,
    required this.readToken,
    required this.userName,
    required this.enabled,
    DateTime Function()? clock,
    this.pause = const Duration(seconds: 1),
    this.maxMatches = 6,
    this.maxCache = 300,
  }) : _now = clock ?? DateTime.now;

  final ListenBrainzClient client;
  final YoutubeMatcher matcher;
  final Future<String?> Function() readToken;
  final String? Function() userName;

  /// Interruptor del usuario y token presente.
  final bool Function() enabled;

  /// Espera entre peticiones seguidas (la API pide ~1 req/s).
  final Duration pause;
  final int maxMatches, maxCache;
  final DateTime Function() _now;

  static const _poolTtl = Duration(minutes: 30);
  static const _playlistTtl = Duration(hours: 6);

  final _playlists = <String, (DateTime, List<Track>)>{};
  final _byMbid = <String, Track>{}; // caché MBID → metadatos (CF)
  (DateTime, List<Track>)? _pool;
  DateTime? _blockedUntil;

  RecSource get source => RecSource(RecBucket.listenbrainz, fetch);

  Track _track(LbTrack t) => Track(
    id: 'lb:${t.mbid ?? '${t.artist}|${t.title}'}',
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: t.duration,
    genres: t.tags,
  );

  void _put<V>(Map<String, V> map, String key, V value) {
    map.remove(key);
    map[key] = value;
    while (map.length > maxCache) {
      map.remove(map.keys.first);
    }
  }

  Future<List<Track>> _loadPool(String user, String token) async {
    final cached = _pool;
    if (cached != null && _now().difference(cached.$1) < _poolTtl) {
      return cached.$2;
    }
    final tracks = <Track>[];
    final lists = await client.createdForYou(user, token);
    for (final list in lists.take(2)) {
      final hit = _playlists[list.mbid];
      if (hit != null && _now().difference(hit.$1) < _playlistTtl) {
        tracks.addAll(hit.$2);
        continue;
      }
      await Future<void>.delayed(pause);
      try {
        final got = [
          for (final t in await client.playlistTracks(list.mbid, token))
            _track(t),
        ];
        _put(_playlists, list.mbid, (_now(), got));
        tracks.addAll(got);
      } on ListenBrainzRateLimited {
        rethrow;
      } on Object {
        continue; // una lista que falla no tumba las demás
      }
    }
    if (tracks.isEmpty) {
      await Future<void>.delayed(pause);
      final mbids = await client.cfRecordingMbids(user, token);
      final missing = [
        for (final m in mbids)
          if (!_byMbid.containsKey(m)) m,
      ];
      if (missing.isNotEmpty) {
        await Future<void>.delayed(pause);
        for (final t in await client.recordingMetadata(missing, token)) {
          _put(_byMbid, t.mbid!, _track(t));
        }
      }
      tracks.addAll([
        for (final m in mbids)
          if (_byMbid[m] != null) _byMbid[m]!,
      ]);
    }
    if (tracks.isNotEmpty) _pool = (_now(), tracks);
    return tracks;
  }

  Future<List<DjCandidate>> fetch(SessionContext ctx, int want) async {
    try {
      if (!enabled()) return const [];
      final blocked = _blockedUntil;
      if (blocked != null && _now().isBefore(blocked)) return const [];
      final user = userName(), token = await readToken();
      if (user == null || token == null) return const [];
      final pool = [...await _loadPool(user, token)]
        ..removeWhere((t) => ctx.skippedArtists.contains(djPrimaryArtist(t)))
        ..shuffle(math.Random(ctx.seed));
      final limit = math.min(want, maxMatches);
      final out = <DjCandidate>[];
      // De tres en tres para no saturar la búsqueda de YouTube Music.
      for (var i = 0; i < pool.length && out.length < limit; i += 3) {
        final batch = pool.skip(i).take(3).toList();
        final matches = await Future.wait([
          for (final t in batch) matcher.match(t).catchError((_) => null),
        ]);
        for (var k = 0; k < matches.length; k++) {
          final m = matches[k];
          if (m == null) continue; // sin coincidencia fiable en YouTube
          final lb = batch[k];
          out.add(
            DjCandidate(
              m.track.genres.isEmpty && lb.genres.isNotEmpty
                  ? m.track.copyWith(genres: lb.genres)
                  : m.track,
              'Recomendado por ListenBrainz',
              prior: 0.4 * m.confidence,
              bucket: RecBucket.listenbrainz,
            ),
          );
        }
      }
      return out.take(limit).toList();
    } on ListenBrainzRateLimited catch (e) {
      _blockedUntil = _now().add(e.retryAfter);
      return const [];
    } on Object {
      return const []; // el mensaje podría llevar datos de red; no se propaga
    }
  }
}
