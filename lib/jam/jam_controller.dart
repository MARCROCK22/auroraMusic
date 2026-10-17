import 'dart:async';
import 'package:flutter/foundation.dart';
import '../app_controller.dart';
import '../core/models.dart';
import 'jam_models.dart';
import 'jam_service.dart';
import 'jam_suggestions.dart';
import 'transport/jam_config.dart';
import 'transport/jam_transport.dart';
import 'transport/supabase_jam_transport.dart';
import '../sources/innertube_source.dart';
import 'jam_playback_bridge.dart';

class JamController extends ChangeNotifier {
  JamController({
    required this.app,
    JamService? service,
    JamTransport? transport,
  }) : service = service ?? JamService(),
       _transport = transport {
    bridge = JamPlaybackBridge(app: app, service: this.service);
    this.service.addListener(_sessionChanged);
    bridge.addListener(_notify);
    this.service.onSkip = next;
    this.service.onPlayPause = (play) async {
      if (play != app.audio.isPlaying) await togglePlayback();
    };
    _completed = app.audio.completed.listen((_) {
      if (this.service.isHost && bridge.enabled) unawaited(next());
    });
  }
  final AppController app;
  JamTransport? _transport;

  /// Transporte en línea (Supabase); no está disponible sin --dart-define.
  JamTransport get remote =>
      _transport ??= SupabaseJamTransport(JamSupabaseConfig.fromEnvironment);
  bool get remoteAvailable => remote.available;
  String? get remoteProblem => remote.unavailableReason;
  Timer? _suggestTimer, _refreshLater;
  DateTime? _nextRefreshAt;
  String? _lastEntryId;
  bool _suggesting = false, _cancelAdd = false;

  /// Avance de «añadir en lotes» (playlist larga); la UI lo escucha.
  final ValueNotifier<JamAddProgress> addProgress = ValueNotifier(
    const JamAddProgress(),
  );

  // --- API estable para la UI -------------------------------------------
  /// Rol y permisos del usuario actual en la Jam.
  bool get isHost => service.isHost;
  bool get active => service.connected;
  JamRole get role => service.me?.role ?? JamRole.guest;
  JamMode get mode => service.mode;
  JamPermissions get _perm => service.me?.permissions ?? const JamPermissions();
  bool get _muted => service.me?.muted ?? false;
  bool get canPause => isHost || _perm.pause;
  bool get canSkip => isHost || _perm.skip;

  /// Play/pausa/saltar (los invitados se enrutan al anfitrión si hay permiso).
  bool get canControlPlayback => canPause || canSkip;
  bool get canAdd => active && !_muted && (isHost || _perm.add);
  bool get canReorder => isHost || _perm.reorder;
  bool get canRemove => isHost || _perm.remove;
  String get hostName => service.participants
      .firstWhere(
        (p) => p.isHost,
        orElse: () => const JamParticipant(id: 'host', name: 'el anfitrión'),
      )
      .name;
  List<JamParticipant> get participants => service.participants;

  /// Sugerencias de todo el grupo, intercaladas (round-robin por persona).
  List<GroupSuggestion> get groupSuggestions => service.groupSuggestions;

  /// Autoplay de la Jam (activo por defecto). Solo lo cambia el anfitrión.
  bool get autoplayEnabled => service.rules.autoplay;
  Future<void> setAutoplay(bool on) => _run(() async {
    await service.setRules(service.rules.copyWith(autoplay: on));
    if (on) _autoplay();
  });

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
    _startHostTimer();
    _startSuggestions();
  });
  void _startHostTimer() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (bridge.enabled && !_hostLoading && service.isHost) _publish();
    });
  }

  Future<void> hostOnline(String name) => _run(() async {
    await bridge.disable();
    await service.hostRemote(remote, name: name);
    _startHostTimer();
    _startSuggestions();
  });
  Future<void> join(String code, String name) => _run(() async {
    await bridge.disable();
    if (jamRemoteCodeFrom(code) != null) {
      await service.joinRemote(remote, code, name: name);
      _startSuggestions();
    } else {
      await service.join(JamInvite.decode(code), name: name);
      _startSuggestions();
    }
  });

  /// Enlace `aurora://jam/CODIGO` recibido del sistema (Android/Windows).
  Future<void> joinFromLink(String link, String name) {
    final code = jamRemoteCodeFrom(link);
    if (code == null) {
      error = 'El enlace de Jam no es válido.';
      _notify();
      return Future.value();
    }
    return join(code, name);
  }

  /// Cada dispositivo calcula SUS sugerencias con SU perfil y publica solo
  /// pistas públicas (máx. 5 cada 60 s). Nada del perfil sale del equipo.
  void _startSuggestions() {
    _suggestTimer?.cancel();
    _nextRefreshAt = null;
    _cancelAdd = false;
    unawaited(refreshSuggestions());
    _suggestTimer = Timer.periodic(
      jamSuggestionsInterval + const Duration(seconds: 5),
      (_) => unawaited(refreshSuggestions()),
    );
  }

  /// Como mucho una publicación por minuto; si llega antes, se difiere.
  Future<void> refreshSuggestions() async {
    if (_suggesting || !service.connected || _disposed) return;
    final wait = _nextRefreshAt?.difference(DateTime.now());
    if (wait != null && wait > Duration.zero) {
      _refreshLater ??= Timer(wait, () {
        _refreshLater = null;
        unawaited(refreshSuggestions());
      });
      return;
    }
    _nextRefreshAt = DateTime.now().add(
      jamSuggestionsInterval + const Duration(seconds: 2),
    );
    _suggesting = true;
    try {
      final adapter = JamSuggestionAdapter(
        related: (track) {
          final source = app.source;
          final id = track.id.startsWith('yt:') ? track.id.substring(3) : null;
          return source is InnerTubeSource && id != null
              ? source.related(id)
              : Future.value(const []);
        },
        seeds: () => app.recentTracks,
        local: () => app.queue,
        rank: app.rankForJam,
      );
      final items = await adapter.build(current: app.currentTrack);
      if (items.isNotEmpty && service.connected) {
        service.publishSuggestions(items);
      }
    } on JamException {
      // Límite de ritmo o permiso desactivado: se reintenta en el siguiente ciclo.
    } catch (_) {
    } finally {
      _suggesting = false;
    }
  }

  Future<void> reconnect() => _run(service.reconnect);
  Future<void> leave() => _run(() async {
    _broadcastTimer?.cancel();
    _suggestTimer?.cancel();
    _refreshLater?.cancel();
    _nextRefreshAt = null;
    _cancelAdd = true;
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
    if (!service.isHost) {
      if (!canPause) throw JamException('Lo controla $hostName.');
      service.requestPlayPause(!(service.playback?.isPlaying ?? false));
      return;
    }
    if (!bridge.enabled) return;
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
        if (!canSkip) throw JamException('Lo controla $hostName.');
        service.skip();
      } on JamException catch (failure) {
        error = _friendly(failure);
        _notify();
      }
      return;
    }
    var upcoming = _nextEntry();
    if (upcoming == null && service.rules.autoplay) {
      service.promoteSuggested();
      upcoming = _nextEntry();
    }
    if (upcoming != null) {
      await play(upcoming);
    } else {
      await app.audio.pause();
      _publish();
    }
  }

  JamQueueEntry? _nextEntry() {
    final current = service.queue.indexWhere(
      (entry) => entry.id == bridge.currentEntryId,
    );
    for (var i = current + 1; i < service.queue.length; i++) {
      final e = service.queue[i];
      if (e.playable &&
          (service.rules.autoplay || e.status != JamEntryStatus.suggested)) {
        return e;
      }
    }
    return null;
  }

  /// Autoplay: con menos de 3 pistas por delante, sube sugerencias a la cola.
  void _autoplay() {
    if (!service.isHost || !service.connected || !service.rules.autoplay) {
      return;
    }
    if (service.upcomingQueued >= 3) return;
    if (service.promoteSuggested() == 0) unawaited(refreshSuggestions());
  }

  /// Añade pistas a la Jam. Devuelve false (y deja [error]) si no hay permiso.
  /// Las listas largas se envían por lotes; observa [addProgress].
  bool addTracks(List<Track> tracks, {JamAddMode mode = JamAddMode.end}) {
    if (!canAdd) {
      error = !active
          ? 'Únete a una Jam para añadir canciones.'
          : _muted
          ? 'El anfitrión te silenció.'
          : 'El anfitrión no permite añadir canciones.';
      _notify();
      return false;
    }
    error = null;
    final wire = <JamTrack>[];
    for (final t in tracks) {
      try {
        wire.add(JamTrack.fromTrack(t));
        bridge.remember(t);
      } on JamException {
        continue; // datos inválidos: no entran
      }
    }
    _cancelAdd = false;
    unawaited(() async {
      try {
        final result = await service.addMany(
          wire,
          mode: mode,
          onProgress: (p) {
            if (!_disposed) addProgress.value = p;
          },
          cancelled: () => _cancelAdd || _disposed,
        );
        if (mode == JamAddMode.playNow && result.firstEntryId != null) {
          final entry = service.queue.firstWhere(
            (e) => e.id == result.firstEntryId,
          );
          await play(entry);
        }
      } on JamException catch (failure) {
        error = _friendly(failure);
        if (!_disposed) addProgress.value = JamAddProgress(message: error);
      }
      _notify();
    }());
    return true;
  }

  /// Añade una playlist de la biblioteca local (las pistas se resuelven por id).
  Future<void> addPlaylist(
    MusicPlaylist playlist, {
    JamAddMode mode = JamAddMode.end,
  }) async {
    final byId = {for (final t in app.tracks) t.id: t};
    final found = [
      for (final id in playlist.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (found.isEmpty) {
      error = 'La playlist «${playlist.name}» no tiene canciones.';
      _notify();
      return;
    }
    addTracks(found, mode: mode);
  }

  void cancelAdd() => _cancelAdd = true;

  /// Añade una sugerencia del grupo con un toque.
  void addSuggestion(GroupSuggestion s) {
    try {
      service.addTrack(s.track);
      error = null;
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
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
      : failure.message == 'limit'
      ? 'Llegaste al límite de canciones que puedes agregar.'
      : failure.message == 'muted'
      ? 'El anfitrión te silenció.'
      : failure.message == 'full'
      ? 'La cola compartida llegó al límite de 200 canciones.'
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
    final entry = service.playback?.entryId;
    if (entry != _lastEntryId) {
      _lastEntryId = entry;
      if (entry != null && service.connected) {
        unawaited(refreshSuggestions()); // la pista cambió: nuevas ideas
      }
    }
    _autoplay();
    if (service.isHost &&
        service.isRemote &&
        !(_broadcastTimer?.isActive ?? false)) {
      _startHostTimer(); // tras recibir el mando por traspaso
    }
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
    _suggestTimer?.cancel();
    _refreshLater?.cancel();
    addProgress.dispose();
    unawaited(_completed?.cancel());
    service.removeListener(_sessionChanged);
    bridge.removeListener(_notify);
    service.dispose();
    bridge.dispose();
    super.dispose();
  }
}
