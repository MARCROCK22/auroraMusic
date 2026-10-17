import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'ai_dj.dart';

/// Clave estable de «la misma canción» aunque cambie el vídeo: título
/// normalizado + artista principal.
String recsTrackKey(Track track) =>
    '${recsNormalizeTitle(track.title)}|${djPrimaryArtist(track)}';

final _paren = RegExp(r'[(\[][^)\]]*[)\]]');
final _suffix = RegExp(
  r'\s-\s.*(remaster|version|mix|edit|live|mono|stereo|radio|single|\d{4}).*$',
);

/// Título sin acentos, paréntesis, «feat», «remastered» ni puntuación.
String recsNormalizeTitle(String title) {
  var s = title.toLowerCase().replaceAll(_paren, ' ').replaceAll(_suffix, ' ');
  s = s.replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), ' ');
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .replaceAll(
        RegExp(r'\b(remastered|remaster|official|audio|video)\b'),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Future<SharedPreferences?> recsPrefs() async {
  try {
    return await SharedPreferences.getInstance();
  } catch (_) {
    return null; // sin plugin (tests): la memoria vive solo en RAM
  }
}

/// Memoria anti-repetición: las últimas [max] pistas recomendadas o
/// reproducidas con su marca de tiempo, persistida en SharedPreferences.
class RecsMemory {
  RecsMemory({
    this.max = 300,
    this.window = const Duration(days: 7),
    this.persist = true,
    this.prefsKey = 'recsMemory',
  });

  /// Instancia compartida por la app (la usa `SuggestionsApi` por defecto).
  static final RecsMemory shared = RecsMemory();

  final int max;
  final Duration window;
  final bool persist;
  final String prefsKey;
  final _entries = <String, int>{}; // clave -> ms (orden de inserción)
  Future<void>? _loading;

  int get length => _entries.length;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!persist) return;
    final raw = (await recsPrefs())?.getString(prefsKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = [
        for (final e in data.entries)
          if (e.value is int) MapEntry(e.key, e.value as int),
      ]..sort((a, b) => a.value.compareTo(b.value));
      for (final e in loaded) {
        _entries.putIfAbsent(e.key, () => e.value); // lo grabado antes gana
      }
      _trim();
    } catch (_) {}
  }

  void _trim() {
    while (_entries.length > max) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Antigüedad de la pista en memoria, o null si no está.
  Duration? ageOf(Track track, DateTime now) {
    final at = _entries[recsTrackKey(track)];
    return at == null
        ? null
        : now.difference(DateTime.fromMillisecondsSinceEpoch(at));
  }

  Future<void> record(Iterable<Track> tracks, DateTime now) {
    for (final t in tracks) {
      final k = recsTrackKey(t);
      _entries.remove(k); // reinsertar = más reciente
      _entries[k] = now.millisecondsSinceEpoch;
    }
    _trim();
    return persist ? _save() : Future.value();
  }

  Future<void> _save() async {
    final prefs = await recsPrefs();
    await prefs?.setString(prefsKey, jsonEncode(_entries));
  }

  Future<void> clear() async {
    _entries.clear();
    await _save();
  }
}
