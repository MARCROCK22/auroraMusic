// ignore_for_file: avoid_print
// Prueba manual por red (omitida salvo LIVE_YT=1): empareja pistas tipo Spotify
// con YouTube Music y muestra el candidato elegido y su confianza.
// Uso: $env:LIVE_YT='1'; flutter test --no-pub test/live_youtube_match_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:aurora_music/sources/innertube_source.dart';

class _NoDelegate implements SourceBackend {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Track sp(String title, String artist, int secs, [String? album]) => Track(
  id: 'spotify:track:$title',
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: secs),
  spotifyUri:
      'spotify:track:${title.hashCode.abs().toString().padLeft(22, '0')}',
  spotifyMatchPending: true,
);

void main() {
  test(
    'emparejamiento real contra YouTube Music',
    () async {
      HttpOverrides.global = null; // flutter_test bloquea la red por defecto
      final source = InnerTubeSource(_NoDelegate());
      final matcher = YoutubeMatcher(
        persist: false,
        search: (q, kind) async => (await source.searchPage(q, kind)).tracks,
      );
      final cases = [
        sp('Blinding Lights', 'The Weeknd', 200, 'After Hours'),
        sp('Despacito - Remix', 'Luis Fonsi, Daddy Yankee, Justin Bieber', 232),
        sp('Bohemian Rhapsody - Remastered 2011', 'Queen', 355),
        sp('Creep', 'Radiohead', 238, 'Pablo Honey'),
        sp('Hotel California - 2013 Remaster', 'Eagles', 391),
        sp('La Bachata', 'Manuel Turizo', 162),
        sp('Cancion que no existe zzqx', 'Nadie Absoluto', 100),
      ];
      for (final c in cases) {
        final m = await matcher.match(c);
        print(
          '${c.title} / ${c.artist} (${c.duration.inSeconds}s) -> '
          '${m == null ? 'SIN COINCIDENCIA' : '${m.track.title} / ${m.track.artist} '
                    '(${m.track.duration.inSeconds}s) ${m.track.id} conf=${m.confidence.toStringAsFixed(2)}'}',
        );
      }
    },
    skip: Platform.environment['LIVE_YT'] != '1',
  );
}
