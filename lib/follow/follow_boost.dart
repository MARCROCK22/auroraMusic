import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/coherence.dart';

/// Refuerzo suave para pistas de artistas seguidos. Es un sesgo de ranking
/// (misma escala que `djModeBonus`, ±0.3): no sustituye al perfil local, ni
/// salta el filtro de coherencia, el tope por artista ni la memoria anti-repetición.
const followedArtistBoost = 0.12;

/// [followedKeys] viene de `FollowService.followedArtistKeys`.
double followedArtistBonus(Track track, Set<String> followedKeys) {
  if (followedKeys.isEmpty) return 0;
  final primary = djArtists(track.artist).firstOrNull;
  if (primary == null) return 0;
  return followedKeys.contains(primary) ||
          followedKeys.contains(coherenceNorm(primary))
      ? followedArtistBoost
      : 0;
}
