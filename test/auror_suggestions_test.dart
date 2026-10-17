import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/dj_modes.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/ui/artwork_cache.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, String artist, {List<String> genres = const []}) => Track(
  id: id,
  title: 'Song $id',
  artist: artist,
  genres: genres,
  pageUrl: 'https://music.youtube.com/watch?v=$id',
);

TasteProfile profileOf(List<Track> favs) => buildTasteProfile(
  favorites: favs,
  playlistTracks: const [],
  history: const [],
  events: const [],
  known: const {},
  now: DateTime(2026),
);

void main() {
  final noon = DateTime(2026, 1, 1, 14);
  final night = DateTime(2026, 1, 1, 23);

  test('modos: energía sube rock, relax sube ambient, hora cambia', () {
    final rock = t('r', 'A', genres: ['rock']);
    final calm = t('c', 'B', genres: ['ambient']);
    expect(
      djModeBonus(DjMode.energy, rock, now: noon) >
          djModeBonus(DjMode.energy, calm, now: noon),
      isTrue,
    );
    expect(
      djModeBonus(DjMode.relax, calm, now: noon) >
          djModeBonus(DjMode.relax, rock, now: noon),
      isTrue,
    );
    expect(
      djModeBonus(DjMode.mood, calm, now: night) >
          djModeBonus(DjMode.mood, rock, now: night),
      isTrue,
    );
    expect(
      djModeBonus(DjMode.mood, rock, now: noon) >
          djModeBonus(DjMode.mood, calm, now: noon),
      isTrue,
    );
  });

  test('mezcla favoritos/novedades sin artista seguido', () {
    final recs = [
      for (final x in [
        ('1', 'fav'),
        ('2', 'fav'),
        ('3', 'new1'),
        ('4', 'new2'),
      ])
        TrackRecommendation(track: t(x.$1, x.$2), reason: ''),
    ];
    final out = djMixFavoritesAndNovelty(recs, favoriteArtists: {'fav'});
    expect(out.length, 4);
    for (var i = 1; i < out.length; i++) {
      expect(out[i].track.artist, isNot(out[i - 1].track.artist));
    }
  });

  test(
    'getSuggestions: no repite artista, mezcla Jam, fallback offline',
    () async {
      final a = t('a', 'Rocker', genres: ['rock']);
      final b = t('b', 'Chiller', genres: ['ambient']);
      final library = [
        for (var i = 0; i < 4; i++) t('r$i', 'Rocker', genres: ['rock']),
        for (var i = 0; i < 4; i++) t('c$i', 'Chiller', genres: ['ambient']),
        for (var i = 0; i < 4; i++) t('o$i', 'Other$i'),
      ];
      final api = SuggestionsApi(fetchCandidates: (_) async => throw 'offline');
      final res = await api.getSuggestions(
        SessionContext(
          participants: [
            ParticipantTaste('u1', profileOf([a])),
            ParticipantTaste('u2', profileOf([b])),
          ],
          current: a,
          library: library,
          limit: 8,
          now: noon,
        ),
      );
      expect(res, isNotEmpty); // fallback offline
      expect(djPrimaryArtist(res.first.track), isNot('rocker'));
      for (var i = 1; i < res.length; i++) {
        expect(
          djPrimaryArtist(res[i].track),
          isNot(djPrimaryArtist(res[i - 1].track)),
        );
      }
      expect(res.every((s) => s.comment.isNotEmpty), isTrue);
      // Ambos gustos están representados en la Jam.
      final artists = res.map((s) => s.track.artist).toSet();
      expect(artists.containsAll({'Rocker', 'Chiller'}), isTrue);
    },
  );

  test('combineTasteProfiles es media ponderada', () {
    final pa = profileOf([
      t('a', 'Rocker', genres: ['rock']),
    ]);
    final pb = profileOf([
      t('b', 'Chiller', genres: ['ambient']),
    ]);
    final heavy = combineTasteProfiles([
      ParticipantTaste('a', pa, weight: 5),
      ParticipantTaste('b', pb),
    ]);
    expect(
      djCosine(heavy.vector, pa.vector) > djCosine(heavy.vector, pb.vector),
      isTrue,
    );
  });

  group('caché de portadas', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('art'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('acierta en disco y expulsa LRU', () async {
      var fetches = 0;
      final cache = ArtworkDiskCache(
        dir,
        maxBytes: 250,
        fetch: (_) async {
          fetches++;
          return Uint8List(100)..fillRange(0, 100, 1);
        },
      );
      Future<void> age(String u, int secs) => File(
        '${dir.path}/${ArtworkDiskCache.keyFor(u)}',
      ).setLastModified(DateTime.now().subtract(Duration(seconds: secs)));
      await cache.load('u1');
      await cache.load('u1');
      expect(fetches, 1);
      await age('u1', 30); // mtime de segundo en Windows: fijar el orden a mano
      await cache.load('u2');
      await age('u2', 20);
      await cache.load('u3');
      await cache.prune();
      expect(dir.listSync().whereType<File>().length, 2);
      expect(
        File('${dir.path}/${ArtworkDiskCache.keyFor('u1')}').existsSync(),
        isFalse,
      );
    });

    test('upgradeArtworkUrl sube resolución', () {
      expect(
        upgradeArtworkUrl(
          'https://lh3.googleusercontent.com/x=w60-h60-l90-rj',
          300,
        ),
        'https://lh3.googleusercontent.com/x=w544-h544-l90-rj',
      );
      expect(upgradeArtworkUrl('https://a.b/c.jpg', 300), 'https://a.b/c.jpg');
    });
  });
}
