import 'dart:math' as math;

import '../core/models.dart';
import 'ai_dj.dart';
import 'recommendations.dart';

/// Modos de Auror (el DJ). Solo sesgan el ranking local; no usan servicios.
enum DjMode {
  discover('Descubrir'),
  energy('Energía'),
  relax('Relax'),
  mood('Por hora y ánimo');

  const DjMode(this.label);
  final String label;
}

const _energyWords = [
  'rock',
  'metal',
  'punk',
  'dance',
  'edm',
  'electro',
  'house',
  'techno',
  'hip hop',
  'hip-hop',
  'rap',
  'trap',
  'reggaeton',
  'pop',
  'remix',
  'workout',
  'salsa',
  'latin',
  'dubstep',
  'drill',
  'party',
];
const _calmWords = [
  'acoustic',
  'acústic',
  'ambient',
  'chill',
  'lofi',
  'lo-fi',
  'jazz',
  'piano',
  'classical',
  'clásic',
  'sleep',
  'instrumental',
  'bossa',
  'relax',
  'calm',
  'folk',
  'unplugged',
  'soft',
];

/// Energía estimada en [-1, 1] por palabras clave de género/título (heurística
/// local; sin audio-features). 0 = neutro/desconocido.
double djEnergyEstimate(Track track) {
  final text = [
    ...track.genres,
    track.title,
    track.album ?? '',
  ].join(' ').toLowerCase();
  final up = _energyWords.where(text.contains).length;
  final down = _calmWords.where(text.contains).length;
  if (up == down) return 0;
  return ((up - down) / math.max(1, up + down)).clamp(-1.0, 1.0).toDouble();
}

/// Cuota de pistas YA oídas (biblioteca: historial, favoritos, listas) en cada
/// tanda del DJ; el resto son pistas nuevas. Descubrir apuesta por lo nuevo,
/// Relax por lo conocido.
double djHeardShare(DjMode mode) => switch (mode) {
  DjMode.discover => 0.30,
  DjMode.energy => 0.35,
  DjMode.mood => 0.35,
  DjMode.relax => 0.40,
};

/// Una pista ya oída puede volver pasado este tiempo desde que sonó (además
/// de la memoria de las últimas 20 reproducciones); las nuevas siguen con la
/// ventana larga de la memoria anti-repetición (7 días).
const djHeardCooldown = Duration(hours: 3);

/// Energía objetivo según la hora local: noche calma, tarde alta.
double djTargetEnergyForHour(int hour) {
  if (hour >= 22 || hour < 6) return -0.7;
  if (hour < 12) return 0.1;
  if (hour < 18) return 0.5;
  return 0.0;
}

/// Ajuste aditivo de relevancia (≈ ±0.3) que el modo aplica a una pista.
/// [knownArtists] son artistas ya escuchados/favoritos (para «descubrir»).
double djModeBonus(
  DjMode mode,
  Track track, {
  required DateTime now,
  Set<String> knownArtists = const {},
}) {
  final energy = djEnergyEstimate(track);
  switch (mode) {
    case DjMode.energy:
      return 0.3 * energy;
    case DjMode.relax:
      return -0.3 * energy;
    case DjMode.mood:
      return 0.3 * (0.5 - (energy - djTargetEnergyForHour(now.hour)).abs() / 2);
    case DjMode.discover:
      return knownArtists.contains(djPrimaryArtist(track)) ? -0.2 : 0.15;
  }
}

/// Mezcla favoritos/novedades según [favoriteRatio] manteniendo el orden de
/// relevancia dentro de cada grupo y evitando el mismo artista seguido.
List<TrackRecommendation> djMixFavoritesAndNovelty(
  List<TrackRecommendation> ranked, {
  required Set<String> favoriteArtists,
  double favoriteRatio = 0.4,
  String? previousArtist,
}) {
  final fav = <TrackRecommendation>[], fresh = <TrackRecommendation>[];
  for (final r in ranked) {
    (favoriteArtists.contains(djPrimaryArtist(r.track)) ? fav : fresh).add(r);
  }
  final out = <TrackRecommendation>[];
  var last = previousArtist ?? '';
  var favTaken = 0;
  while (fav.isNotEmpty || fresh.isNotEmpty) {
    final wantFav =
        fav.isNotEmpty &&
        (fresh.isEmpty || favTaken < (out.length + 1) * favoriteRatio);
    var pool = wantFav ? fav : fresh;
    var i = pool.indexWhere((r) => djPrimaryArtist(r.track) != last);
    if (i < 0) {
      // Todo el grupo preferido repite artista: probar el otro grupo.
      final other = wantFav ? fresh : fav;
      final j = other.indexWhere((r) => djPrimaryArtist(r.track) != last);
      if (j >= 0) {
        pool = other;
        i = j;
      } else {
        i = 0;
      }
    }
    final pick = pool.removeAt(i);
    if (identical(pool, fav)) favTaken++;
    out.add(pick);
    last = djPrimaryArtist(pick.track);
  }
  return out;
}

/// Comentario breve de transición generado por plantillas (determinista por
/// [seed] para poder probarlo).
String djTransitionComment(
  Track? from,
  Track to,
  DjMode mode, {
  int seed = 0,
  DateTime? now,
}) {
  final hour = (now ?? DateTime.now()).hour;
  final moment = hour >= 22 || hour < 6
      ? 'de noche'
      : hour < 12
      ? 'por la mañana'
      : hour < 18
      ? 'por la tarde'
      : 'al caer el día';
  final all = [
    ...switch (mode) {
      DjMode.discover => [
        'Algo nuevo para ti: ${to.title}.',
        'Salimos del camino con ${to.artist}.',
      ],
      DjMode.energy => [
        'Subimos el ritmo con ${to.title}.',
        'Más energía: ${to.artist}.',
      ],
      DjMode.relax => [
        'Bajamos revoluciones con ${to.title}.',
        'Respira un poco: ${to.artist}.',
      ],
      DjMode.mood => [
        'Para sonar bien $moment: ${to.title}.',
        '${to.artist}, justo para ir $moment.',
      ],
    },
    if (from != null && from.title.isNotEmpty)
      'Tras ${from.title}, sigue ${to.title} de ${to.artist}.',
  ];
  return all[math.Random(seed).nextInt(all.length)];
}
