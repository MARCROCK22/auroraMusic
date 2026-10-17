import 'dart:typed_data';

import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/dj_modes.dart';
import '../dj/suggestions_api.dart';
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
/// * [api] (opcional): motor de sugerencias con el perfil de ESTE dispositivo
///   ([taste]); mezcla radio de YouTube + fuentes de `api.sources` (p. ej.
///   Spotify emparejado), con memoria anti-repetición, diversidad y
///   exploración, y devuelve razones en español. Sin [api] se conserva el
///   comportamiento anterior ([rank] opcional).
class JamSuggestionAdapter {
  JamSuggestionAdapter({
    required this.related,
    required this.seeds,
    required this.local,
    this.rank,
    this.api,
    this.taste,
    this.mode = DjMode.discover,
    this.count = jamSuggestionsPerPerson,
  });
  final SuggestionsApi? api;
  final ParticipantTaste Function()? taste;
  final DjMode mode;
  final int count;
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
    final engine = api;
    if (engine != null) {
      try {
        final picks = await engine.getSuggestions(
          SessionContext(
            participants: [
              taste?.call() ??
                  ParticipantTaste(
                    'self',
                    TasteProfile(Float32List(djVectorDims), const {}),
                  ),
            ],
            mode: mode,
            current: current,
            library: local(),
            extraCandidates: [
              for (var i = 0; i < candidates.length; i++)
                DjCandidate(
                  candidates[i],
                  online ? 'Radio de YouTube' : 'De tu biblioteca',
                  prior: 0.5 / (1 + i / 5),
                  bucket: online ? RecBucket.radio : RecBucket.similar,
                ),
            ],
            limit: count * 2, // margen por si algún dato no es válido
          ),
        );
        final out = <JamSuggestion>[];
        for (final s in picks) {
          if (out.length >= count) break;
          try {
            out.add(JamSuggestion(JamTrack.fromTrack(s.track), s.reason));
          } on JamException {
            continue;
          }
        }
        if (out.isNotEmpty) return out;
      } catch (_) {
        // El motor falló: se cae al camino sencillo de abajo.
      }
    }
    try {
      candidates = await rank?.call(candidates, current) ?? candidates;
    } catch (_) {}
    final out = <JamSuggestion>[];
    for (final t in candidates) {
      if (out.length >= count) break;
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
