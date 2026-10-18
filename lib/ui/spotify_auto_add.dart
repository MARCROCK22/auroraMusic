import 'package:flutter/material.dart';

import '../core/models.dart';
import '../jam/jam_controller.dart';
import '../jam/jam_models.dart';
import '../metadata/youtube_match.dart';
import 'jam/jam_widgets.dart';
import 'undo_snackbar.dart';

typedef SpotifyManualMatch =
    Future<void> Function(Track spotify, {Track? replacing});

class SpotifyBatchProgress {
  const SpotifyBatchProgress(this.label, this.done, this.total);
  final String label;
  final int done, total;
}

/// Spotify aporta los metadatos; esta clase encuentra sola la versión de
/// YouTube (YoutubeMatcher). Un toque REPRODUCE (y la cola se rehace desde esa
/// pista); «+» y ⋯ añaden a la cola/Jam con «Deshacer». En una Jam el toque
/// pone la canción al final de la cola compartida.
/// Sin [matcher] (fuente que no es InnerTube) delega en el diálogo manual.
class SpotifyAutoAdder extends ChangeNotifier {
  SpotifyAutoAdder({
    this.matcher,
    required this.save,
    required this.playSeed,
    required this.queueLength,
    required this.unqueue,
    required this.manual,
    required this.messenger,
    this.jam,
    this.moreFromArtist,
  });

  final YoutubeMatcher? matcher;

  /// Encola la coincidencia (al final o, con [next], a continuación).
  final Future<bool> Function(Track spotify, Track match, {bool next}) save;

  /// Reproduce la coincidencia y rehace la cola desde ella
  /// (`AppController.playSpotifySeed`).
  final Future<bool> Function(
    Track spotify,
    Track match, {
    Stream<List<(Track, Track)>>? context,
    Future<List<Track>> Function()? extras,
  })
  playSeed;

  /// Más canciones del artista de la semilla (metadatos de Spotify).
  final Future<List<Track>> Function(Track seed)? moreFromArtist;
  final int Function() queueLength;
  final void Function(String id) unqueue;
  final SpotifyManualMatch manual;
  final ScaffoldMessengerState? Function() messenger;
  final JamController? Function()? jam;

  /// Tope de pistas por lote (límite de red; la Jam aplica además los suyos).
  static const maxBatch = 100;

  /// Pistas del álbum/playlist que se empareja tras la que suena, por tandas.
  static const maxContext = 40;
  static const _chunk = 4;

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

  void _say(
    String text, {
    String? label,
    VoidCallback? onTap,
    int secs = 4,
    String? who,
  }) {
    showUndoSnackBar(
      messenger(),
      who == null
          ? Text(text)
          : Row(
              children: [
                JamAvatar(name: who, size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text(text)),
              ],
            ),
      label: label,
      onAction: onTap,
      duration: Duration(seconds: secs),
    );
  }

  static String _what(Track t) => '${t.title} · ${t.artist}';

  void _noMatch(Track t) => _say(
    'Sin coincidencia en YouTube para «${t.title}».',
    label: 'Buscar a mano',
    onTap: () => manual(t),
    secs: 6,
  );

  void _offline(Track t) => _say(
    'No se pudo buscar en YouTube. Revisa la conexión.',
    label: 'Buscar a mano',
    onTap: () => manual(t),
  );

  /// Toque en la fila. Sin Jam: empareja, suena ya y rehace la cola desde esta
  /// pista ([context] = lo que sigue del álbum/playlist, en orden). Con Jam:
  /// la pone al final de la cola compartida sin tocar lo que suena.
  Future<void> play(Track t, {List<Track> context = const []}) async {
    final m = matcher;
    if (m == null) return manual(t);
    if (jamAvailable) return add(t, toJam: true);
    if (!_busy.add(t.id)) return;
    _notify();
    try {
      final match = await m.match(t, lenient: true);
      if (match == null) return _noMatch(t);
      final y = match.track;
      final rest = context.take(maxContext).toList();
      final ok = await playSeed(
        t,
        y,
        context: rest.isEmpty ? null : _contextChunks(m, rest),
        extras: moreFromArtist == null ? null : () => _extras(m, t),
      );
      if (!ok) {
        _say('No se pudo reproducir «${t.title}».');
      } else if (match.confidence < m.threshold) {
        _say(
          'Coincidencia dudosa: ${_what(y)}',
          label: 'Cambiar',
          onTap: () => manual(t),
          secs: 8,
        );
      }
    } catch (_) {
      _offline(t);
    } finally {
      _busy.remove(t.id);
      _notify();
    }
  }

  /// Empareja el resto del álbum/playlist por tandas de [_chunk]; la primera
  /// tanda llega mientras la pista ya suena.
  Stream<List<(Track, Track)>> _contextChunks(
    YoutubeMatcher m,
    List<Track> rest,
  ) async* {
    for (var i = 0; i < rest.length; i += _chunk) {
      final part = rest.skip(i).take(_chunk).toList();
      final found = await m.matchMany(part, concurrency: 3);
      yield [
        for (var k = 0; k < part.length; k++)
          if (found[k] != null) (part[k], found[k]!.track),
      ];
    }
  }

  /// Más canciones del artista (top tracks de Spotify) ya emparejadas.
  Future<List<Track>> _extras(YoutubeMatcher m, Track seed) async {
    final top = (await moreFromArtist!(seed)).where((t) => t.id != seed.id);
    final found = await m.matchMany(top.take(10).toList(), concurrency: 3);
    return [
      for (final f in found)
        if (f != null) f.track,
    ];
  }

  /// «+» y ⋯: empareja y añade a la cola ([next] = a continuación) o a la Jam,
  /// sin reproducir, y confirma con «Deshacer».
  Future<void> add(
    Track t, {
    bool next = false,
    bool toJam = false,
    JamAddMode jamMode = JamAddMode.end,
  }) async {
    final m = matcher;
    if (m == null) return manual(t);
    if (!_busy.add(t.id)) return;
    _notify();
    try {
      final match = await m.match(t, lenient: true);
      if (match == null) return _noMatch(t);
      final doubtful = match.confidence < m.threshold;
      final y = match.track;
      if (toJam) {
        final j = jam?.call();
        final ok = j?.addTracks([y], mode: jamMode) ?? false;
        final dudosa = doubtful ? ' (coincidencia dudosa)' : '';
        _say(
          ok
              ? 'Añadida a la Jam: ${_what(y)}$dudosa'
              : (j?.error ?? 'No se pudo añadir a la Jam.'),
          label: ok && doubtful ? 'Cambiar' : null,
          onTap: () => manual(t),
          who: ok ? j?.service.me?.name : null,
        );
        return;
      }
      final before = queueLength();
      if (!await save(t, y, next: next)) {
        _say('No se pudo añadir «${t.title}».');
        return;
      }
      final added = queueLength() > before;
      if (doubtful) {
        _say(
          'Coincidencia dudosa: ${_what(y)}',
          label: 'Cambiar',
          onTap: () => manual(t, replacing: y),
          secs: 8,
        );
      } else {
        _say(
          added
              ? '${next ? 'Sonará a continuación' : 'Añadida'}: ${_what(y)}'
              : 'Ya estaba en la cola: ${_what(y)}',
          label: added ? 'Deshacer' : null,
          onTap: () => unqueue(y.id),
        );
      }
    } catch (_) {
      _offline(t);
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
        await save(p.$1, p.$2);
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
