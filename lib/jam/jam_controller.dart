import 'dart:async';
import 'package:flutter/foundation.dart';
import '../app_controller.dart';
import '../core/models.dart';
import 'jam_models.dart';
import 'jam_service.dart';
import 'jam_playback_bridge.dart';

class JamController extends ChangeNotifier {
  JamController({required this.app, JamService? service})
    : service = service ?? JamService() {
    bridge = JamPlaybackBridge(app: app, service: this.service);
    this.service.addListener(_sessionChanged);
    bridge.addListener(_notify);
    this.service.onSkip = next;
    _completed = app.audio.completed.listen((_) {
      if (this.service.isHost && bridge.enabled) unawaited(next());
    });
  }
  final AppController app;
  final JamService service;
  late final JamPlaybackBridge bridge;
  bool busy = false, searching = false;
  String? error;
  List<String> addresses = [];
  List<Track> results = [];
  Timer? _broadcastTimer;
  StreamSubscription<void>? _completed;
  int _searchGeneration = 0;
  bool _disposed = false;
  bool _hostLoading = false;
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (failure) {
      error = failure is JamException
          ? failure.message
          : 'No se pudo completar la acción de Jam.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> loadAddresses() => _run(() async {
    addresses = await JamService.localAddresses();
    if (addresses.isEmpty) {
      throw const JamException(
        'No encontramos una dirección privada. Conéctate a una red Wi-Fi o Ethernet.',
      );
    }
  });
  Future<void> host(String address, String name) => _run(() async {
    await bridge.disable();
    await service.host(address: address, name: name);
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (bridge.enabled && !_hostLoading && service.isHost) _publish();
    });
  });
  Future<void> join(String code, String name) => _run(() async {
    await bridge.disable();
    await service.join(JamInvite.decode(code), name: name);
  });
  Future<void> reconnect() => _run(service.reconnect);
  Future<void> leave() => _run(() async {
    _broadcastTimer?.cancel();
    await service.close();
    await bridge.disable();
  });
  Future<void> setMode(JamMode mode) => _run(() async {
    service.setMode(mode);
    if (mode == JamMode.synchronized) await bridge.enable();
  });
  Future<void> setListening(bool listen) => _run(() async {
    if (listen) {
      if (!service.connected || service.mode != JamMode.synchronized) {
        throw const JamException(
          'El anfitrión debe habilitar reproducción sincronizada.',
        );
      }
      await bridge.enable();
      if (service.playback != null) await bridge.apply(service.playback!);
    } else {
      await bridge.disable();
    }
  });
  Future<void> play(JamQueueEntry entry) => _run(() async {
    if (!service.isHost) {
      throw const JamException('El anfitrión controla la reproducción.');
    }
    await bridge.enable();
    _hostLoading = true;
    try {
      final state = JamPlayback(
        sequence: (service.playback?.sequence ?? 0) + 1,
        entryId: entry.id,
        isPlaying: true,
        serverTimeMs: service.clock().millisecondsSinceEpoch,
      );
      await bridge.apply(state);
      _publish(entryId: entry.id);
    } finally {
      _hostLoading = false;
    }
  });
  Future<void> togglePlayback() => _run(() async {
    if (!service.isHost || !bridge.enabled) return;
    if (app.audio.isPlaying) {
      await app.audio.pause();
    } else {
      await app.audio.play();
    }
    _publish();
  });
  Future<void> seek(Duration position) => _run(() async {
    if (!service.isHost || !bridge.enabled) return;
    await app.audio.seek(position);
    _publish();
  });
  Future<void> next() async {
    if (!service.isHost) {
      try {
        service.skip();
      } on JamException catch (failure) {
        error = failure.message;
        _notify();
      }
      return;
    }
    final current = service.queue.indexWhere(
      (entry) => entry.id == bridge.currentEntryId,
    );
    if (current + 1 < service.queue.length) {
      await play(service.queue[current + 1]);
    } else {
      await app.audio.pause();
      _publish();
    }
  }

  void add(Track track) {
    try {
      bridge.remember(track);
      service.addTrack(JamTrack.fromTrack(track));
      error = null;
    } on JamException catch (failure) {
      error = failure.message == 'rate'
          ? 'Espera unos segundos antes de agregar más canciones.'
          : failure.message;
    }
    _notify();
  }

  void remove(JamQueueEntry entry) {
    try {
      service.remove(entry.id);
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
  }

  void reorder(JamQueueEntry entry, int to) {
    try {
      service.reorder(entry.id, to);
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
  }

  String _friendly(JamException failure) => failure.message == 'permissions'
      ? 'El anfitrión no habilitó ese permiso.'
      : failure.message == 'rate'
      ? 'Espera unos segundos antes de cambiar la cola.'
      : failure.message;
  void setPermissions(String id, JamPermissions permissions) {
    try {
      service.setPermissions(id, permissions);
    } on JamException catch (failure) {
      error = failure.message;
    }
    _notify();
  }

  Future<void> search(String query) async {
    final generation = ++_searchGeneration;
    query = query.trim();
    results = [];
    searching = query.isNotEmpty;
    error = null;
    _notify();
    if (query.isEmpty) return;
    if (query.length > 300) {
      searching = false;
      error = 'La búsqueda es demasiado larga.';
      _notify();
      return;
    }
    try {
      final matches = await app.source.search(query, limit: 12);
      if (!_disposed && generation == _searchGeneration) results = matches;
    } catch (_) {
      if (!_disposed && generation == _searchGeneration) {
        error =
            'No se pudieron buscar canciones. Puedes agregar desde tu biblioteca.';
      }
    } finally {
      if (!_disposed && generation == _searchGeneration) {
        searching = false;
        _notify();
      }
    }
  }

  void _publish({String? entryId}) {
    service.publishPlayback(
      entryId: entryId ?? bridge.currentEntryId,
      playing: app.audio.isPlaying && !app.audio.isBuffering,
      positionMs: app.audio.position.inMilliseconds,
    );
  }

  void _sessionChanged() {
    if (_disposed) return;
    if (!service.connected && bridge.enabled) {
      unawaited(bridge.disable());
    } else if (!service.isHost && bridge.enabled) {
      if (service.mode == JamMode.queueOnly) {
        unawaited(bridge.disable());
      } else if (service.playback != null) {
        unawaited(bridge.apply(service.playback!));
      }
    } else if (service.isHost &&
        bridge.enabled &&
        !_hostLoading &&
        service.playback?.entryId == null &&
        bridge.currentEntryId != null) {
      unawaited(app.audio.pause());
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchGeneration++;
    _broadcastTimer?.cancel();
    unawaited(_completed?.cancel());
    service.removeListener(_sessionChanged);
    bridge.removeListener(_notify);
    service.dispose();
    bridge.dispose();
    super.dispose();
  }
}
