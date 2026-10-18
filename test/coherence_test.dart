import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/coherence.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 17, 12);
String vid(String s) => s.padRight(11, '_').substring(0, 11);
Track tr(
  String id,
  String title,
  String artist, {
  List<String> genres = const [],
}) => Track(
  id: 'yt:${vid(id)}',
  title: title,
  artist: artist,
  genres: genres,
  pageUrl: 'https://music.youtube.com/watch?v=${vid(id)}',
);

Future<List<Suggestion>> run(
  List<Track> pool,
  Track current, {
  int limit = 3,
  Set<String> favs = const {},
}) {
  final api = SuggestionsApi(
    memory: RecsMemory(persist: false),
    exploration: 0,
  );
  return api.getSuggestions(
    SessionContext(
      participants: [
        ParticipantTaste(
          'yo',
          buildTasteProfile(
            favorites: [current],
            playlistTracks: const [],
            history: const [],
            events: const [],
            known: const {},
            now: now,
          ),
        ),
      ],
      current: current,
      favoriteArtists: favs,
      extraCandidates: [
        for (final t in pool) DjCandidate(t, 'Radio', bucket: RecBucket.radio),
      ],
      limit: limit,
      now: now,
      seed: 1,
      remember: false,
    ),
  );
}

void main() {
  final cur = tr('cur', 'Usseewa', 'Ado');
  final bad = tr(
    'bad',
    'Ado (Teledrama Theme Song)',
    'Anushka Weerakkody & Neluka Deemantha',
  );

  test(
    'título con nombre de artista pero otro artista: baja y queda detrás',
    () async {
      final good = tr('g1', 'Show', 'Ado');
      final feat = tr('g2', 'Otra', 'Vocaloid X feat. Ado');
      final r = await run([bad, good, feat], cur);
      expect(r.last.track.id, bad.id);
      expect(r.last.coherence, lessThan(0.2));
      expect(r.first.coherence, greaterThan(0.8));
    },
  );

  test('feat. del artista correcto sube', () {
    final ctx = CoherenceContext(artists: ['Ado']);
    expect(
      scoreCoherence(tr('a', 'Cancion (feat. Ado)', 'Otro'), ctx).score,
      greaterThan(0.8),
    );
  });

  test('todo dudoso: nunca vacío', () async {
    final r = await run([bad, tr('b2', 'Ado Ado', 'Nadie')], cur, limit: 2);
    expect(r, hasLength(2));
    final ranked = CoherenceFilter.rank([
      DjCandidate(bad, 'x'),
    ], CoherenceContext(artists: ['Ado']));
    expect(ranked, hasLength(1));
  });

  test(
    'palabra común en el título sin género: rechazo duro; con género solo baja',
    () {
      final ctx = CoherenceContext(artists: ['Love'], genres: ['pop']);
      final hard = scoreCoherence(tr('a', 'Love me', 'Otro'), ctx);
      expect(hard.hardReject, isTrue);
      final soft = scoreCoherence(
        tr('b', 'Love me', 'Otro', genres: ['pop']),
        ctx,
      );
      expect(soft.hardReject, isFalse);
      expect(soft.score, lessThan(0.5));
    },
  );

  test('acentos y japonés', () {
    final ctx = CoherenceContext(artists: ['Beyoncé', '米津玄師']);
    expect(
      scoreCoherence(tr('a', 'x', 'BEYONCE'), ctx).score,
      greaterThan(0.9),
    );
    expect(
      scoreCoherence(tr('b', 'x', '米津玄師 - Topic'), ctx).score,
      greaterThan(0.9),
    );
    expect(scoreCoherence(tr('c', 'x', 'Otro'), ctx).score, lessThan(0.5));
  });

  test('sin referencia ni Spotify: neutro', () {
    expect(scoreCoherence(tr('a', 'x', 'Y'), CoherenceContext()).score, 0.5);
  });
}
