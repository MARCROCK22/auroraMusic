import 'package:flutter/material.dart';

import '../core/models.dart';
import '../jam/jam_controller.dart';
import '../metadata/youtube_match.dart';

typedef SpotifyManualMatch =
    Future<void> Function(Track spotify, {Track? replacing});

class SpotifyBatchProgress {
  const SpotifyBatchProgress(this.label, this.done, this.total);
  final String label;
  final int done, total;
}

/// Spotify aporta los metadatos; esta clase encuentra sola la versión de
/// YouTube (YoutubeMatcher), la añade a la cola/Jam y avisa con «Deshacer».
/// Sin [matcher] (fuente que no es InnerTube) delega en el diálogo manual.
class SpotifyAutoAdder extends ChangeNotifier {
  SpotifyAutoAdder({
    this.matcher,
    required this.save,
    required this.queueLength,
    required this.unqueue,
    required this.manual,
    required this.messenger,
    this.jam,
  });

  final YoutubeMatcher? matcher;

  /// Guarda/encola (o reproduce) la coincidencia: `importSpotifyMetadataMatch`.
  final Future<bool> Function(Track spotify, Track match, {bool play}) save;
  final int Function() queueLength;
  final void Function(String id) unqueue;
  final SpotifyManualMatch manual;
  final ScaffoldMessengerState? Function() messenger;
  final JamController? Function()? jam;

  /// Tope de pistas por lote (límite de red; la Jam aplica además los suyos).
  static const maxBatch = 100;

  final _busy = <String>{};
  SpotifyBatchProgress? batch;
  bool _cancel = false, _disposed = false;

  bool isBusy(String trackId) => _busy.contains(trackId);
  bool get jamAvailable => jam?.call()?.active == true;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _say(String text, {String? label, VoidCallback? onTap, int secs = 4}) {
    final m = messenger();
    m?.hideCurrentSnackBar();
    m?.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: Duration(seconds: secs),
        action: label == null
            ? null
            : SnackBarAction(label: label, onPressed: onTap ?? () {}),
      ),
    );
  }

  static String _what(Track t) => '${t.title} · ${t.artist}';

  /// Un toque: empareja, añade a la cola (o a la Jam / reproduce) y confirma.
  Future<void> add(Track t, {bool play = false, bool toJam = false}) async {
    final m = matcher;
    if (m == null) return manual(t);
    if (!_busy.add(t.id)) return;
    _notify();
    try {
      final match = await m.match(t, lenient: true);
      if (match == null) {
        _say(
          'Sin coincidencia en YouTube para «${t.title}».',
          label: 'Buscar a mano',
          onTap: () => manual(t),
          secs: 6,
        );
        return;
      }
      final doubtful = match.confidence < m.threshold;
      final y = match.track;
      if (toJam) {
        final ok = jam?.call()?.addTracks([y]) ?? false;
        _say(
          ok
              ? 'Añadida a la Jam: ${_what(y)}'
              : (jam?.call()?.error ?? 'No se pudo añadir a la Jam.'),
        );
        return;
      }
      final before = queueLength();
      if (!await save(t, y, play: play)) {
        _say('No se pudo añadir «${t.title}».');
        return;
      }
      final added = queueLength() > before;
      if (doubtful) {
        _say(
          'Coincidencia dudosa: ${_what(y)}',
          label: 'Cambiar',
          onTap: () => manual(t, replacing: play ? null : y),
          secs: 8,
        );
      } else if (!play) {
        _say(
          added ? 'Añadida: ${_what(y)}' : 'Ya estaba en la cola: ${_what(y)}',
          label: added ? 'Deshacer' : null,
          onTap: () => unqueue(y.id),
        );
      }
    } catch (_) {
      _say(
        'No se pudo buscar en YouTube. Revisa la conexión.',
        label: 'Buscar a mano',
        onTap: () => manual(t),
      );
    } finally {
      _busy.remove(t.id);
      _notify();
    }
  }

  void cancelBatch() {
    _cancel = true;
  }

  /// Álbum/playlist/artista completo. Solo entran coincidencias fiables; el
  /// resto se omite y se cuenta al final. Cancelar descarta el lote (lo ya
  /// emparejado queda en caché, así que repetirlo es rápido).
  Future<void> addAll(
    String label,
    List<Track> tracks, {
    bool toJam = false,
  }) async {
    final m = matcher;
    if (m == null || tracks.isEmpty) return;
    if (batch != null) {
      _say('Ya hay un lote en curso.');
      return;
    }
    final target = toJam ? jam?.call() : null;
    if (toJam && (target == null || !target.canAdd)) {
      _say('No puedes añadir canciones a la Jam.');
      return;
    }
    final list = tracks.take(maxBatch).toList();
    _cancel = false;
    batch = SpotifyBatchProgress(label, 0, list.length);
    _notify();
    try {
      final found = await m.matchMany(
        list,
        cancelled: () => _cancel,
        onProgress: (done, total) {
          batch = SpotifyBatchProgress(label, done, total);
          _notify();
        },
      );
      if (_cancel) {
        _say('Lote cancelado. No se añadió nada.');
        return;
      }
      final pairs = [
        for (var i = 0; i < list.length; i++)
          if (found[i] != null) (list[i], found[i]!.track),
      ];
      final skipped = list.length - pairs.length;
      final tail = skipped == 0 ? '' : ' · $skipped sin coincidencia';
      if (target != null) {
        final ok =
            pairs.isNotEmpty && target.addTracks([for (final p in pairs) p.$2]);
        _say(
          pairs.isEmpty
              ? 'Ninguna canción tuvo coincidencia en YouTube.'
              : ok
              ? 'Enviando ${pairs.length} canciones a la Jam$tail'
              : (target.error ?? 'No se pudo añadir a la Jam.'),
          secs: 6,
        );
        return;
      }
      final before = queueLength();
      for (final p in pairs) {
        await save(p.$1, p.$2, play: false);
      }
      final n = queueLength() - before;
      _say(
        pairs.isEmpty
            ? 'Ninguna canción tuvo coincidencia en YouTube.'
            : n == 0
            ? 'Ya estaban en la cola$tail'
            : 'Añadidas $n de ${tracks.length} a la cola$tail',
        secs: 6,
      );
    } catch (_) {
      _say('No se pudo completar el lote. Revisa la conexión.');
    } finally {
      batch = null;
      _notify();
    }
  }
}
