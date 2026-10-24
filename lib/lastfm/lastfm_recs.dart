import 'dart:math' as math;

import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/suggestions_api.dart';
import '../metadata/youtube_match.dart';
import 'lastfm_client.dart';
import 'lastfm_stats.dart';

/// Fuente de candidatos del DJ con las canciones similares de Last.fm a la que
/// suena (`track.getSimilar`); si no hay, artistas similares y sus pistas top.
/// Cada pista se empareja con YouTube vía [matcher]. El prior es bajo
/// (0,4 × confianza): el perfil local manda. Todo fallo devuelve lista vacía y
/// el DJ sigue con lo local; el filtro de coherencia y la memoria
/// anti-repetición los aplica el SuggestionsApi.
class LastfmRecsSource {
  LastfmRecsSource({
    required this.client,
    required this.matcher,
    required this.enabled,
    DateTime Function()? clock,
    this.maxMatches = 6,
  }) : _now = clock ?? DateTime.now;

  final LastfmClient client;
  final YoutubeMatcher matcher;

  /// Interruptor del usuario y sesión presente.
  final bool Function() enabled;
  final int maxMatches;
  final DateTime Function() _now;
  DateTime? _blockedUntil;

  RecSource get source => RecSource(RecBucket.lastfm, fetch);

  Track _track(LfmTrack t) =>
      Track(id: 'lfm:${t.artist}|${t.title}', title: t.title, artist: t.artist);

  Future<List<LfmTrack>> _pool(SessionContext ctx) async {
    final cur = ctx.current;
    if (cur == null) return const [];
    final similar = await client.similarTracks(cur.artist, cur.title);
    if (similar.isNotEmpty) return similar;
    final out = <LfmTrack>[];
    for (final a in (await client.similarArtists(cur.artist)).take(4)) {
      out.addAll(await client.artistTopTracks(a));
    }
    return out;
  }

  Future<List<DjCandidate>> fetch(SessionContext ctx, int want) async {
    try {
      if (!enabled()) return const [];
      final blocked = _blockedUntil;
      if (blocked != null && _now().isBefore(blocked)) return const [];
      final pool = [...await _pool(ctx)]
        ..removeWhere(
          (t) => ctx.skippedArtists.contains(djPrimaryArtist(_track(t))),
        )
        ..shuffle(math.Random(ctx.seed));
      final limit = math.min(want, maxMatches);
      final out = <DjCandidate>[];
      // De tres en tres para no saturar la búsqueda de YouTube Music.
      for (var i = 0; i < pool.length && out.length < limit; i += 3) {
        final batch = pool.skip(i).take(3).toList();
        final matches = await Future.wait([
          for (final t in batch)
            matcher.match(_track(t)).catchError((_) => null),
        ]);
        for (final m in matches) {
          if (m == null) continue; // sin coincidencia fiable en YouTube
          out.add(
            DjCandidate(
              m.track,
              'Recomendado por Last.fm',
              prior: 0.4 * m.confidence,
              bucket: RecBucket.lastfm,
            ),
          );
        }
      }
      return out.take(limit).toList();
    } on LastfmException catch (e) {
      if (e.rateLimited) {
        _blockedUntil = _now().add(e.retryAfter ?? const Duration(minutes: 1));
      }
      return const [];
    } on Object {
      return const []; // el mensaje podría llevar datos de red; no se propaga
    }
  }
}
