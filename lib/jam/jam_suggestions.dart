import '../core/models.dart';
import 'jam_models.dart';

/// Máximo de sugerencias que cada participante publica en la Jam.
const jamSuggestionsPerPerson = 5;

/// Intervalo mínimo entre publicaciones de un mismo participante.
const jamSuggestionsInterval = Duration(seconds: 60);

/// Lo único que sale del dispositivo: pista pública + razón corta. Nunca el
/// perfil de gustos, favoritos ni historial.
class JamSuggestion {
  const JamSuggestion(this.track, this.reason);
  final JamTrack track;
  final String reason;
  Map<String, Object?> toJson() => {'track': track.toJson(), 'reason': reason};
  factory JamSuggestion.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {'track', 'reason'});
    return JamSuggestion(
      JamTrack.fromJson(data['track']),
      jamText(data['reason'], max: 60),
    );
  }
}

/// Genera las sugerencias de ESTE dispositivo con SU propio perfil.
///
/// * [related]: radio de YouTube (InnerTube `next`) para una pista semilla.
/// * [rank]: reordena candidatos con el perfil local. En la integración se
///   conecta a `SuggestionsApi.getSuggestions(SessionContext)` del frente 4
///   con un único `ParticipantTaste` (el propio); por defecto no reordena.
/// * [local]: respaldo sin red (cola actual / biblioteca).
class JamSuggestionAdapter {
  JamSuggestionAdapter({
    required this.related,
    required this.seeds,
    required this.local,
    this.rank,
  });
  final Future<List<Track>> Function(Track seed) related;
  final List<Track> Function() seeds;
  final List<Track> Function() local;
  final Future<List<Track>> Function(List<Track> candidates, Track? current)?
  rank;

  Future<List<JamSuggestion>> build({Track? current}) async {
    final seen = <String>{};
    var candidates = <Track>[];
    var online = false;
    final starts = [?current, ...seeds().take(2)];
    for (final seed in starts) {
      try {
        for (final t in await related(seed)) {
          if (seen.add(t.id)) candidates.add(t);
        }
        online = true;
      } catch (_) {
        // YouTube falló o no hay red: se prueba la siguiente semilla o lo local.
      }
    }
    if (candidates.isEmpty) {
      online = false;
      candidates = [
        for (final t in local())
          if (seen.add(t.id)) t,
      ];
    }
    try {
      candidates = await rank?.call(candidates, current) ?? candidates;
    } catch (_) {}
    final out = <JamSuggestion>[];
    for (final t in candidates) {
      if (out.length >= jamSuggestionsPerPerson) break;
      try {
        out.add(
          JamSuggestion(
            JamTrack.fromTrack(t),
            online ? 'Radio de YouTube' : 'De tu biblioteca',
          ),
        );
      } on JamException {
        continue; // datos inválidos: no entran
      }
    }
    return out;
  }
}
