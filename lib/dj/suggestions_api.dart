// API estable de sugerencias de Auror (consumida por JAM y por el DJ).
//
//   final api = SuggestionsApi(fetchCandidates: ...);   // fetch opcional
//   Future<List<Suggestion>> api.getSuggestions(SessionContext ctx)
//
// SessionContext:
//   participants   List<ParticipantTaste>  perfiles (1 = sesión personal, N = Jam);
//                                          se combinan con media ponderada por `weight`
//   mode           DjMode                  discover | energy | relax | mood
//   current        Track?                  pista sonando (continuidad)
//   queueTail      List<Track>             últimas pistas de la cola (no repetir artista)
//   recentKeys / skippedArtists            señales de repeticiones y saltos
//   favoriteArtists Set<String>            artistas (djPrimaryArtist) para mezclar favoritos/novedades
//   library        List<Track>             candidatos locales (fallback offline)
//   filters, limit, now
//
// Candidatos: `fetchCandidates(ctx)` (red, opcional) -> si falla o viene vacío se
// usa la última lista cacheada de la misma sesión y, si no, `library` (offline).
// Solo usa datos locales: no consulta recomendaciones de YouTube.
import 'dart:typed_data';

import '../core/models.dart';
import 'ai_dj.dart';
import 'dj_modes.dart';
import 'recommendations.dart';

class ParticipantTaste {
  const ParticipantTaste(this.id, this.profile, {this.weight = 1});
  final String id;
  final TasteProfile profile;
  final double weight;
}

class SessionContext {
  const SessionContext({
    required this.participants,
    this.mode = DjMode.discover,
    this.current,
    this.queueTail = const [],
    this.recentKeys = const {},
    this.skippedArtists = const {},
    this.favoriteArtists = const {},
    this.library = const [],
    this.filters = const DjFilters(),
    this.limit = 10,
    this.now,
  });
  final List<ParticipantTaste> participants;
  final DjMode mode;
  final Track? current;
  final List<Track> queueTail;
  final Set<String> recentKeys, skippedArtists, favoriteArtists;
  final List<Track> library;
  final DjFilters filters;
  final int limit;
  final DateTime? now;
}

class Suggestion {
  const Suggestion(this.track, this.reason, this.comment);
  final Track track;
  final String reason;

  /// Frase breve de transición (plantillas locales).
  final String comment;
}

/// Media ponderada de perfiles (cada vector ya está normalizado, así que nadie
/// domina por tener más historial); ignora perfiles vacíos o de peso <= 0.
TasteProfile combineTasteProfiles(List<ParticipantTaste> parts) {
  final vector = Float32List(djVectorDims);
  final features = <String, double>{};
  for (final p in parts) {
    if (p.weight <= 0 || p.profile.isEmpty) continue;
    for (var i = 0; i < djVectorDims; i++) {
      vector[i] += p.weight * p.profile.vector[i];
    }
    final total = p.profile.features.values.fold<double>(
      0,
      (s, v) => s + v.abs(),
    );
    if (total == 0) continue;
    p.profile.features.forEach(
      (k, v) => features.update(
        k,
        (s) => s + p.weight * v / total,
        ifAbsent: () => p.weight * v / total,
      ),
    );
  }
  return TasteProfile(djNormalize(vector), features);
}

class SuggestionsApi {
  SuggestionsApi({this.fetchCandidates});
  final Future<List<DjCandidate>> Function(SessionContext ctx)? fetchCandidates;
  final _cache = <String, List<DjCandidate>>{};

  static String _key(SessionContext c) =>
      '${c.mode.name}|${(c.participants.map((p) => p.id).toList()..sort()).join(',')}';

  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async {
    final key = _key(ctx);
    var candidates = <DjCandidate>[];
    try {
      candidates = await fetchCandidates?.call(ctx) ?? const [];
    } catch (_) {
      // Sin red o fallo de fuente: se cae a caché/biblioteca.
    }
    if (candidates.isNotEmpty) {
      if (_cache.length >= 16) _cache.remove(_cache.keys.first);
      _cache[key] = candidates;
    } else {
      candidates =
          _cache[key] ??
          [
            for (final t in ctx.library)
              DjCandidate(t, 'De tu biblioteca', prior: 0.3),
          ];
    }
    final now = ctx.now ?? DateTime.now();
    final ranked = rankDjCandidates(
      candidates: candidates,
      profile: combineTasteProfiles(ctx.participants).vector,
      limit: ctx.limit,
      current: ctx.current,
      recentKeys: ctx.recentKeys,
      skippedArtists: ctx.skippedArtists,
      queueTail: ctx.queueTail,
      filters: ctx.filters,
      adjust: (t) =>
          djModeBonus(ctx.mode, t, now: now, knownArtists: ctx.favoriteArtists),
    );
    final last = ctx.queueTail.isNotEmpty ? ctx.queueTail.last : ctx.current;
    final mixed = djMixFavoritesAndNovelty(
      ranked,
      favoriteArtists: ctx.favoriteArtists,
      previousArtist: last == null ? null : djPrimaryArtist(last),
    );
    Track? prev = last;
    final out = <Suggestion>[];
    for (var i = 0; i < mixed.length; i++) {
      final r = mixed[i];
      out.add(
        Suggestion(
          r.track,
          r.reason,
          djTransitionComment(prev, r.track, ctx.mode, seed: i, now: now),
        ),
      );
      prev = r.track;
    }
    return out;
  }
}
