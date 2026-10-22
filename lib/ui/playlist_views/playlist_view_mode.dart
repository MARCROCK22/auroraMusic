import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_controller.dart';
import '../../core/models.dart';

enum PlaylistViewMode {
  normal('Normal'),
  cassettes('Casetes'),
  crate('Cajón de vinilos');

  const PlaylistViewMode(this.label);
  final String label;
}

const playlistViewModeKey = 'playlistViewMode';

/// Modo activo; el Ajuste lo cambia y las listas lo escuchan.
final ValueNotifier<PlaylistViewMode> playlistViewMode = ValueNotifier(
  PlaylistViewMode.normal,
);

/// Carga la preferencia guardada en [playlistViewMode].
void loadPlaylistViewMode(SharedPreferences prefs) {
  final saved = prefs.getString(playlistViewModeKey);
  playlistViewMode.value = PlaylistViewMode.values.firstWhere(
    (m) => m.name == saved,
    orElse: () => PlaylistViewMode.normal,
  );
}

Future<void> savePlaylistViewMode(
  SharedPreferences prefs,
  PlaylistViewMode mode,
) async {
  playlistViewMode.value = mode;
  await prefs.setString(playlistViewModeKey, mode.name);
}

/// Hasta 4 pistas de la playlist, para sus portadas.
List<Track> playlistCoverTracks(AppController c, MusicPlaylist p) =>
    c.tracks.where((t) => p.trackIds.contains(t.id)).take(4).toList();

const _palette = <Color>[
  Color(0xFFC8553D),
  Color(0xFF2E7D8C),
  Color(0xFFD99A2B),
  Color(0xFF5B7DB1),
  Color(0xFF8E5BA3),
  Color(0xFF4F8A5B),
  Color(0xFFD1647E),
  Color(0xFF3F4B8C),
  Color(0xFFB5651D),
  Color(0xFF2A9D8F),
];

/// Color estable por playlist, de una paleta cuidada (extraerlo de la imagen
/// sería asíncrono y caro; no hay helper de color dominante en el proyecto).
Color playlistColor(MusicPlaylist p, {double lightness = .45}) {
  var h = 0;
  for (final u in p.id.codeUnits) {
    h = (h * 31 + u) & 0xffff;
  }
  final c = HSLColor.fromColor(_palette[h % _palette.length]);
  return c.withLightness((c.lightness + lightness - .45).clamp(0, 1)).toColor();
}
