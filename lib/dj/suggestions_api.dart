// API estable de sugerencias de Aurora (consumida por la JAM y por el DJ).
//
//   final api = SuggestionsApi(sources: [...]);          // todo opcional
//   Future<List<Suggestion>> api.getSuggestions(SessionContext ctx)
//
// SessionContext:
//   participants   List<ParticipantTaste>  perfiles (1 = personal, N = Jam);
//                                          el perfil NUNCA sale del dispositivo
//   mode / current / queueTail / recentKeys / skippedArtists / favoriteArtists
//   library        candidatos locales (relleno y respaldo sin red)
//   extraCandidates  candidatos ya traídos por el llamador (p. ej. radio de
//                  YouTube de la pista actual); entran en la mezcla
//   seed           semilla de exploración (null = distinta en cada sesión)
//   remember       false = vista previa que no consume la memoria
//   filters, limit (se admiten lotes grandes, p. ej. 30), now
//
// Candidatos: `sources` (por cubo: similar 50 %, adjacent 30 %, discovery 15 %,
// classics 5 %, configurables en `mix`) + `fetchCandidates` (compat.) +
// `extraCandidates`. Si todo falla se usa la última lista de la misma sesión y
// después `library`; nunca se devuelve vacío mientras quede algo que ofrecer.
//
// Ranking: relevancia con el perfil + novedad (memoria anti-repetición de 300
// pistas / 7 días persistida) + diversidad (MMR, tope por artista, género y
// década) + exploración (ε-greedy con muestreo ponderado). Si el pool se agota
// la ventana de repetición se relaja por tramos en vez de quedarse vacío.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/models.dart';
import 'ai_dj.dart';
import 'coherence.dart';
import 'dj_modes.dart';
import 'recommendations.dart';
import 'reco_memory.dart';

/// Peso de la coherencia de artista en la relevancia.
const djCoherenceWeight = 0.8;

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
    this.extraCandidates = const [],
    this.filters = const DjFilters(),
    this.limit = 10,
    this.now,
    this.seed,
    this.remember = true,
  });
  final List<ParticipantTaste> participants;
  final DjMode mode;
  final Track? current;
  final List<Track> queueTail;
  final Set<String> recentKeys, skippedArtists, favoriteArtists;
  final List<Track> library;
  final List<DjCandidate> extraCandidates;
  final DjFilters filters;
  final int limit;
  final DateTime? now;
  final int? seed;
  final bool remember;
}

class Suggestion {
  const Suggestion(
    this.track,
    this.reason,
    this.comment, {
    this.forParticipant,
    this.bucket = RecBucket.similar,
    this.coherence = 0.5,
    this.coherenceReason = '',
  });
  final Track track;

  /// Coherencia de artista con la semilla/gustos (0..1, 0,5 = sin datos).
  final double coherence;
  final String coherenceReason;

  /// Razón legible en español («Porque escuchas X», «Descubrimiento»…).
  final String reason;

  /// Frase breve de transición (plantillas locales).
  final String comment;

  /// Participante al que va dirigida (turno round-robin en una Jam).
  final String? forParticipant;
  final RecBucket bucket;
}

/// Fuente de candidatos de un cubo. Debe ser tolerante a fallos: si lanza o
/// tarda más de [SuggestionsApi.sourceTimeout] se ignora.
class RecSource {
  const RecSource(this.bucket, this.fetch);
  final RecBucket bucket;
  final Future<List<DjCandidate>> Function(SessionContext ctx, int want) fetch;
}

const defaultRecMix = <RecBucket, double>{
  RecBucket.similar: 0.50,
  RecBucket.adjacent: 0.30,
  RecBucket.discovery: 0.15,
  RecBucket.classics: 0.05,
  RecBucket.listenbrainz: 0.08, // cuota pequeña: el perfil local manda
};

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

/// Claves de característica más fuertes del perfil con el prefijo dado
/// (`a:` artistas, `g:` géneros), de mayor a menor peso.
List<String> tasteTop(TasteProfile profile, String prefix, int count) {
  final entries =
      profile.features.entries
          .where((e) => e.key.startsWith(prefix) && e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entries.take(count)) e.key.substring(prefix.length)];
}

String _title(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Década de la pista si se puede deducir (género «80s», año en álbum/título).
int? djDecade(Track t) {
  final text = '${t.genres.join(' ')} ${t.album ?? ''} ${t.title}'
      .toLowerCase();
  final year = RegExp(r'\b(19[5-9]\d|20[0-2]\d)\b').firstMatch(text);
  if (year != null) return int.parse(year.group(1)!) ~/ 10 * 10;
  final short = RegExp(r'\b(?:19|20)?([5-9]0|[0-2]0)s\b').firstMatch(text);
  if (short == null) return null;
  final d = int.parse(short.group(1)!);
  return d >= 50 ? 1900 + d : 2000 + d;
}

String? _genre(Track t) {
  for (final g in t.genres) {
    final v = g.trim().toLowerCase();
    if (v.isNotEmpty && !RegExp(r'^(19|20)?\d0s$').hasMatch(v)) return v;
  }
  return null;
}

class _Item {
  _Item(this.candidate, this.vector)
    : artist = djPrimaryArtist(candidate.track),
      genre = _genre(candidate.track),
      decade = djDecade(candidate.track);
  final DjCandidate candidate;
  final Float32List vector;
  final String artist;
  final String? genre;
  final int? decade;
  List<double> rel = const [];
  double mean = 0;
  double group = 0;
  Track get track => candidate.track;
}

class SuggestionsApi {
  SuggestionsApi({
    this.fetchCandidates,
    this.sources = const [],
    this.mix = defaultRecMix,
    RecsMemory? memory,
    this.exploration = 0.2,
    this.sourceTimeout = const Duration(seconds: 10),
    math.Random? random,
  }) : memory = memory ?? RecsMemory.shared,
       _random = random ?? math.Random();

  /// Compatibilidad: una sola fuente que cuenta como cubo `similar`.
  final Future<List<DjCandidate>> Function(SessionContext ctx)? fetchCandidates;
  final List<RecSource> sources;
  final Map<RecBucket, double> mix;
  final RecsMemory memory;

  /// Probabilidad ε de elegir por muestreo ponderado en vez de la mejor.
  final double exploration;
  final Duration sourceTimeout;
  final math.Random _random;
  final _cache = <String, List<DjCandidate>>{};

  static String _key(SessionContext c) =>
      '${c.mode.name}|${(c.participants.map((p) => p.id).toList()..sort()).join(',')}';

  Future<List<DjCandidate>> _gather(SessionContext ctx) async {
    final want = math.max(ctx.limit, 10);
    Future<List<DjCandidate>> run(
      RecBucket bucket,
      Future<List<DjCandidate>> Function() call,
    ) async {
      try {
        final out = await call().timeout(sourceTimeout);
        return [
          for (final c in out)
            DjCandidate(c.track, c.reason, prior: c.prior, bucket: bucket),
        ];
      } catch (_) {
        return const []; // sin red o fuente caída: las demás siguen
      }
    }

    final lists = await Future.wait([
      for (final s in sources)
        run(
          s.bucket,
          () => s.fetch(
            ctx,
            math.max(4, ((mix[s.bucket] ?? 0.2) * want * 2).ceil()),
          ),
        ),
      if (fetchCandidates != null)
        run(RecBucket.similar, () => fetchCandidates!(ctx)),
    ]);
    return [...ctx.extraCandidates, for (final l in lists) ...l];
  }

  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async {
    final key = _key(ctx);
    final now = ctx.now ?? DateTime.now();
    final rnd = math.Random(ctx.seed ?? _random.nextInt(1 << 30));
    await memory.ensureLoaded();
    var candidates = await _gather(ctx);
    if (candidates.isNotEmpty) {
      if (_cache.length >= 16) _cache.remove(_cache.keys.first);
      _cache[key] = candidates;
    } else {
      candidates = _cache[key] ?? const [];
    }
    if (candidates.length < ctx.limit * 2) {
      // Poca oferta: la biblioteca completa el pool (y es el único respaldo).
      final inKnown = {for (final c in candidates) c.track.id};
      candidates = [
        ...candidates,
        for (final t in ctx.library)
          if (!inKnown.contains(t.id))
            DjCandidate(
              t,
              'De tu biblioteca',
              prior: 0.3,
              bucket: ctx.favoriteArtists.contains(djPrimaryArtist(t))
                  ? RecBucket.similar
                  : RecBucket.adjacent,
            ),
      ];
    }
    final picks = _rank(ctx, candidates, now, rnd);
    if (ctx.remember) unawaited(memory.record(picks.map((p) => p.track), now));
    Track? prev = ctx.queueTail.isNotEmpty ? ctx.queueTail.last : ctx.current;
    return [
      for (var i = 0; i < picks.length; i++)
        () {
          final s = Suggestion(
            picks[i].track,
            picks[i].reason,
            djTransitionComment(
              prev,
              picks[i].track,
              ctx.mode,
              seed: i,
              now: now,
            ),
            forParticipant: picks[i].forParticipant,
            bucket: picks[i].bucket,
            coherence: picks[i].coherence,
            coherenceReason: picks[i].coherenceReason,
          );
          prev = picks[i].track;
          return s;
        }(),
    ];
  }

  List<
    ({
      Track track,
      String reason,
      String? forParticipant,
      RecBucket bucket,
      double coherence,
      String coherenceReason,
    })
  >
  _rank(
    SessionContext ctx,
    List<DjCandidate> candidates,
    DateTime now,
    math.Random rnd,
  ) {
    if (ctx.limit <= 0) return const [];
    final parts = [
      for (final p in ctx.participants)
        if (p.weight > 0 && !p.profile.isEmpty) p,
    ];
    final vecs = parts.isEmpty
        ? [Float32List(djVectorDims)]
        : [for (final p in parts) p.profile.vector];
    final combined = combineTasteProfiles(ctx.participants);
    final topArtist = tasteTop(combined, 'a:', 1).firstOrNull;
    final currentVector = ctx.current == null
        ? null
        : embedDjTrack(ctx.current!);

    // Lo que ya está en la cola o suena no se vuelve a ofrecer.
    final inQueue = <String>{
      for (final t in [?ctx.current, ...ctx.queueTail])
        ...recommendationTrackKeys(t),
    };
    final inQueueNames = {
      for (final t in [?ctx.current, ...ctx.queueTail]) recsTrackKey(t),
    };
    final seen = <String>{...inQueue};
    final seenNames = <String>{...inQueueNames};
    final items = <_Item>[];
    final ordered = [...candidates]..sort((a, b) => b.prior.compareTo(a.prior));
    for (final c in ordered) {
      final t = c.track;
      final keys = recommendationTrackKeys(t);
      final name = recsTrackKey(t);
      if (keys.any(seen.contains) ||
          seenNames.contains(name) ||
          !ctx.filters.permits(t) ||
          t.isPendingSpotifyMatch ||
          !(t.isLocal || t.pageUrl != null)) {
        continue;
      }
      seen.addAll(keys);
      seenNames.add(name);
      items.add(_Item(c, embedDjTrack(t)));
    }

    // Coherencia de ARTISTA con la semilla (nunca por título): baja la
    // puntuación; el rechazo duro solo si quedan suficientes alternativas.
    final seedArtists = <String>{
      ...ctx.favoriteArtists,
      ...tasteTop(combined, 'a:', 12),
      for (final t in [?ctx.current, ...ctx.queueTail.take(3)])
        ...coherenceArtists(t),
    };
    final coh = CoherenceContext(
      artists: seedArtists,
      genres: {...tasteTop(combined, 'g:', 6), ...?ctx.current?.genres},
      decade: ctx.current == null ? null : djDecade(ctx.current!),
    );
    final cohOf = <_Item, CoherenceResult>{
      for (final i in items) i: scoreCoherence(i.track, coh, decade: i.decade),
    };
    final soft = [
      for (final i in items)
        if (!cohOf[i]!.hardReject) i,
    ];
    if (soft.length >= ctx.limit) items.retainWhere(soft.contains);

    // Tramos de relajación del filtro de repetición: ventana completa,
    // mitad, cuarto y sin filtro (entonces solo pesa la penalización).
    List<_Item> eligible(double tier) => [
      for (final i in items)
        if (() {
          final age = memory.ageOf(i.track, now);
          if (age != null && age < memory.window * tier) return false;
          return !(tier >= 0.5 &&
              recommendationTrackKeys(i.track).any(ctx.recentKeys.contains));
        }())
          i,
    ];
    var pool = const <_Item>[];
    for (final tier in const [1.0, 0.5, 0.25, 0.0]) {
      pool = eligible(tier);
      if (pool.length >= ctx.limit) break;
    }

    for (final i in pool) {
      final age = memory.ageOf(i.track, now);
      final novelty = age == null
          ? 0.0
          : 0.4 * math.exp(-age.inMinutes / memory.window.inMinutes);
      final bonus =
          djModeBonus(
            ctx.mode,
            i.track,
            now: now,
            knownArtists: ctx.favoriteArtists,
          ) -
          novelty -
          (recommendationTrackKeys(i.track).any(ctx.recentKeys.contains)
              ? djRecentPenalty
              : 0) -
          (ctx.skippedArtists.contains(i.artist) ? djSkippedArtistPenalty : 0) +
          djCoherenceWeight * (cohOf[i]!.score - 0.5) +
          djPriorWeight * i.candidate.prior +
          (currentVector == null
              ? 0
              : djContinuityWeight * djCosine(currentVector, i.vector));
      final cos = [for (final v in vecs) djCosine(v, i.vector)];
      i.rel = [for (final c in cos) djTasteWeight * c + bonus];
      i.mean = i.rel.reduce((a, b) => a + b) / i.rel.length;
      // Afinidad de grupo: gusta a al menos dos personas.
      i.group = cos.where((c) => c > 0.15).length >= 2 ? 0.08 : 0;
    }

    final limit = ctx.limit;
    final artistCap = math.max(1, (limit / 5).ceil());
    final genreCap = math.max(2, (limit * 0.4).ceil());
    final decadeCap = math.max(2, (limit * 0.5).ceil());
    final artistsSoFar = [
      if (ctx.current != null && ctx.queueTail.isEmpty)
        djPrimaryArtist(ctx.current!),
      ...ctx.queueTail.map(djPrimaryArtist),
    ];
    final tailWindow = artistsSoFar.length > 9
        ? artistsSoFar.sublist(artistsSoFar.length - 9)
        : [...artistsSoFar];
    final chosen = <_Item>[];
    final turns = <String?>[];
    final byArtist = <String, int>{}, byGenre = <String, int>{};
    final byDecade = <int, int>{};
    final byBucket = <RecBucket, int>{};

    bool cooled(_Item i) =>
        i.artist.isEmpty ||
        ((artistsSoFar.isEmpty || artistsSoFar.last != i.artist) &&
            tailWindow.where((a) => a == i.artist).length < 2);
    bool capped(_Item i) =>
        (byArtist[i.artist] ?? 0) >= artistCap && i.artist.isNotEmpty ||
        (i.genre != null && (byGenre[i.genre] ?? 0) >= genreCap) ||
        (i.decade != null && (byDecade[i.decade] ?? 0) >= decadeCap);

    final remaining = [...pool];
    while (chosen.length < limit && remaining.isNotEmpty) {
      final turn = chosen.length % vecs.length;
      var options = [
        for (final i in remaining)
          if (cooled(i) && !capped(i)) i,
      ];
      if (options.isEmpty) {
        options = [
          for (final i in remaining)
            if (cooled(i)) i,
        ];
      }
      if (options.isEmpty) options = remaining; // nunca vacío
      final scores = <double>[];
      for (final i in options) {
        var redundancy = 0.0;
        for (final c in chosen) {
          redundancy = math.max(redundancy, djCosine(i.vector, c.vector));
        }
        final target = mix[i.candidate.bucket] ?? 0;
        final share = chosen.isEmpty
            ? 0.0
            : (byBucket[i.candidate.bucket] ?? 0) / chosen.length;
        final relevance = vecs.length > 1
            ? 0.6 * i.rel[turn] + 0.4 * i.mean + i.group
            : i.mean;
        scores.add(
          djMmrLambda * relevance -
              (1 - djMmrLambda) * redundancy +
              0.25 * (target - share) +
              0.03 * rnd.nextDouble(),
        );
      }
      var best = 0;
      if (options.length > 1 && rnd.nextDouble() < exploration) {
        // Muestreo ponderado (softmax): puede salir cualquiera de las buenas.
        final top = scores.reduce(math.max);
        final w = [for (final s in scores) math.exp((s - top) / 0.12)];
        var r = rnd.nextDouble() * w.reduce((a, b) => a + b);
        for (var k = 0; k < w.length; k++) {
          r -= w[k];
          if (r <= 0) {
            best = k;
            break;
          }
        }
      } else {
        for (var k = 1; k < scores.length; k++) {
          if (scores[k] > scores[best]) best = k;
        }
      }
      final pick = options[best];
      remaining.remove(pick);
      chosen.add(pick);
      turns.add(parts.isEmpty ? null : parts[turn].id);
      artistsSoFar.add(pick.artist);
      tailWindow.add(pick.artist);
      if (tailWindow.length > 9) tailWindow.removeAt(0);
      byArtist.update(pick.artist, (n) => n + 1, ifAbsent: () => 1);
      if (pick.genre != null) {
        byGenre.update(pick.genre!, (n) => n + 1, ifAbsent: () => 1);
      }
      if (pick.decade != null) {
        byDecade.update(pick.decade!, (n) => n + 1, ifAbsent: () => 1);
      }
      byBucket.update(pick.candidate.bucket, (n) => n + 1, ifAbsent: () => 1);
    }

    String reasonOf(_Item i) {
      if (i.candidate.reason.isNotEmpty) return i.candidate.reason;
      return switch (i.candidate.bucket) {
        RecBucket.similar =>
          topArtist == null
              ? 'Más de lo que te gusta'
              : 'Porque escuchas ${_title(topArtist)}',
        RecBucket.adjacent =>
          topArtist == null
              ? 'Artistas parecidos a tus gustos'
              : 'Artistas parecidos a ${_title(topArtist)}',
        RecBucket.discovery => 'Descubrimiento',
        RecBucket.classics => 'Un clásico imprescindible',
        RecBucket.radio => 'Radio de YouTube',
        RecBucket.listenbrainz => 'Recomendado por ListenBrainz',
      };
    }

    return [
      for (var k = 0; k < chosen.length; k++)
        (
          track: chosen[k].track,
          reason: reasonOf(chosen[k]),
          forParticipant: turns[k],
          bucket: chosen[k].candidate.bucket,
          coherence: cohOf[chosen[k]]!.score,
          coherenceReason: cohOf[chosen[k]]!.reason,
        ),
    ];
  }
}
