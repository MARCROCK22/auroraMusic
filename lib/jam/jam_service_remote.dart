part of 'jam_service.dart';

/// Jam en línea (Supabase u otro [JamTransport]). Reutiliza el protocolo de la
/// Jam LAN: el anfitrión sigue siendo la fuente de verdad y el servidor solo
/// valida identidad, pertenencia, límites y reenvía.
extension JamServiceRemote on JamService {
  static String _device() => Platform.isAndroid
      ? 'android'
      : Platform.isWindows
      ? 'windows'
      : 'other';

  Future<void> hostRemote(
    JamTransport transport, {
    required String name,
  }) async {
    if (!transport.available) {
      throw JamException(
        transport.unavailableReason ?? 'Jam en línea no disponible.',
      );
    }
    name = jamCleanName(name, fallback: 'Anfitrión');
    await close();
    final generation = ++_generation;
    _stopRetry = false;
    try {
      final uid = await transport.signIn();
      final room = await transport.createRoom(name: name, device: _device());
      if (_disposed || generation != _generation) {
        unawaited(transport.closeRoom(room.code).catchError((Object _) {}));
        return;
      }
      _transport = transport;
      _room = room;
      _uid = uid;
      invite = JamInvite.remote(code: room.code, expiresAt: room.expiresAt);
      connection = JamConnection.hosting;
      participantId = 'host';
      participants = [
        JamParticipant(
          id: 'host',
          name: name,
          role: JamRole.host,
          permissions: JamPermissions.all,
        ),
      ];
      error = null;
      await _startHub(transport, room);
      _startBeat();
      _changed();
    } catch (failure) {
      await _closeRemote();
      connection = JamConnection.closed;
      error = _remoteError(failure);
      _notify();
      throw JamException(error!);
    }
  }

  Future<void> _startHub(JamTransport transport, JamRoomInfo room) async {
    final channel = transport.openChannel(room.code, asHost: true);
    final hub = JamHubHost(channel, hostUid: _uid);
    _hub = hub;
    hub.arrivals.listen((peer) => unawaited(_admit(peer)));
    channel.online.listen((online) {
      if (_disposed || !isHost) return;
      if (online) {
        error = null;
        _broadcast();
      } else {
        error = 'Sin conexión; reconectando la Jam…';
      }
      _notify();
    });
    await channel.track();
  }

  /// El servidor ya verificó la identidad (`from`); aquí se consulta rol,
  /// nombre y silencio en la lista de miembros del servidor.
  Future<void> _admit(JamHubPeer peer) async {
    final id = peer.uid;
    try {
      final rows = await _transport!.members(_room!.code);
      final row = rows.where((m) => m.uid == id).firstOrNull;
      if (row == null || row.role == JamRole.host || !isHost) {
        await peer.close();
        return;
      }
      _sockets.remove(id);
      _sockets[id] = peer;
      final prior = participants.where((p) => p.id == id).firstOrNull;
      participants = [
        ...participants.where((p) => p.id != id),
        JamParticipant(
          id: id,
          name: jamCleanName(row.name),
          role: row.role,
          muted: row.muted,
          permissions: row.role == JamRole.coHost
              ? JamPermissions.all
              : prior?.permissions ?? const JamPermissions(),
          listening: prior?.listening ?? true,
        ),
      ];
      peer.add(
        jsonEncode({
          'kind': 'welcome',
          'participantId': id,
          'resumeToken': 'remote',
        }),
      );
      peer.listen(
        (m) => _receiveCommand(id, m),
        onDone: () => _disconnected(id, peer),
      );
      _changed();
    } catch (_) {
      await peer.close();
    }
  }

  Future<JamPeer> _remotePeer(JamInvite session) async {
    final transport = _transport!;
    final uid = await transport.signIn();
    final room = await transport.joinRoom(
      code: session.code,
      name: _name,
      device: JamServiceRemote._device(),
    );
    _room = room;
    _uid = uid;
    final guest = JamGuestPeer(
      transport: transport,
      channel: transport.openChannel(room.code, asHost: false),
      code: room.code,
      uid: uid,
      hostUid: room.hostUid,
    );
    await guest.start();
    _startBeat();
    return guest;
  }

  Future<void> joinRemote(
    JamTransport transport,
    String input, {
    required String name,
  }) async {
    if (!transport.available) {
      throw JamException(
        transport.unavailableReason ?? 'Jam en línea no disponible.',
      );
    }
    final code = jamRemoteCodeFrom(input);
    if (code == null) {
      throw const JamException('El código debe tener 6 letras o números.');
    }
    final clean = jamCleanName(name);
    await close();
    _stopRetry = false;
    _transport = transport;
    invite = JamInvite.remote(
      code: code,
      expiresAt: clock().add(const Duration(hours: 12)),
    );
    _name = clean;
    participantId = '';
    try {
      await reconnect();
    } on JamException {
      // Un código inválido o una sala llena no se reintentan.
      if (_terminalError) {
        final message = error;
        await close();
        error = message;
        _notify();
      }
      rethrow;
    }
  }

  bool get _terminalError =>
      _lastCode != null &&
      {
        'invalid',
        'expired',
        'full',
        'banned',
        'closed',
        'rate',
      }.contains(_lastCode);

  String _remoteError(Object failure) {
    if (failure is JamRemoteException) {
      _lastCode = failure.code;
      return failure.message;
    }
    return failure is JamException
        ? failure.message
        : jamRemoteMessage('network');
  }

  String _remoteLostMessage() => _hostGone
      ? 'El anfitrión se desconectó. Esperando su regreso…'
      : jamRemoteMessage('network');

  /// Reconexión con backoff exponencial y jitter; nunca un bucle agresivo.
  void _scheduleRetry() {
    if (!isRemote || isHost || _stopRetry || _disposed || _terminalError) {
      return;
    }
    if (invite == null) return;
    _retryTimer?.cancel();
    final base = min(60, 1 << min(_attempt, 6));
    final wait = Duration(
      milliseconds: (base * 1000 * (0.5 + Random().nextDouble() / 2)).round(),
    );
    _attempt++;
    _retryTimer = Timer(wait, () {
      if (_disposed || _stopRetry || connection == JamConnection.closed) return;
      reconnect().catchError((Object _) {});
    });
    if (_hostGone) {
      _hostLostTimer ??= Timer(const Duration(seconds: 60), _claimAbandoned);
    }
  }

  /// Pasados 60 s sin anfitrión, el servidor decide si este invitado (el más
  /// antiguo) puede heredar la sala.
  Future<void> _claimAbandoned() async {
    _hostLostTimer = null;
    final transport = _transport, room = _room;
    if (transport == null || room == null || isHost || _stopRetry) return;
    try {
      final claimed = await transport.claimHost(room.code);
      await _becomeHost(claimed, previousHostUid: room.hostUid);
    } catch (_) {
      error = 'El anfitrión sigue ausente. Puedes esperar o salir de la Jam.';
      _notify();
    }
  }

  bool get _hostGone =>
      (_client is JamGuestPeer) &&
          (_client as JamGuestPeer).closeReason == 'host' ||
      error?.contains('anfitrión se desconect') == true;

  void _startBeat() {
    _beatTimer?.cancel();
    _beatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final room = _room;
      if (room != null) {
        _transport?.heartbeat(room.code).catchError((Object _) {});
      }
    });
  }

  void _endRemote(String message) {
    _stopRetry = true;
    connection = JamConnection.closed;
    error = message;
    invite = null;
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    unawaited(_closeRemote());
    _notify();
  }

  Future<void> _closeRemote() async {
    final transport = _transport, room = _room, hub = _hub;
    _beatTimer?.cancel();
    _retryTimer?.cancel();
    _hostLostTimer?.cancel();
    _hostLostTimer = null;
    _hub = null;
    _room = null;
    _transport = null;
    _skipVotes.clear();
    _attempt = 0;
    _lastCode = null;
    if (hub != null && connection == JamConnection.hosting) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await hub?.close();
    if (transport != null && room != null) {
      final wasHost = connection == JamConnection.hosting;
      try {
        await (wasHost
            ? transport.closeRoom(room.code)
            : transport.leave(room.code));
      } catch (_) {}
    }
  }

  // --- Moderación y reglas (solo anfitrión / coanfitrión según el servidor) ---

  void _requireHost() {
    if (!isHost) throw const JamException('Solo el anfitrión puede hacer eso.');
  }

  Future<void> kick(String id, {bool ban = false}) async {
    _requireHost();
    if (id == 'host') return;
    final peer = _sockets[id];
    if (isRemote) await _transport!.kick(_room!.code, id, ban: ban);
    _sendSocket(peer, jsonEncode({'kind': 'kicked'}));
    _sockets.remove(id);
    unawaited(peer?.close());
    participants = [
      for (final p in participants)
        if (p.id == id) p.copyWith(connected: false) else p,
    ];
    _changed();
  }

  Future<void> setMuted(String id, bool muted) async {
    _requireHost();
    if (isRemote) await _transport!.setMuted(_room!.code, id, muted);
    participants = [
      for (final p in participants) p.id == id ? p.copyWith(muted: muted) : p,
    ];
    _changed();
  }

  Future<void> setCoHost(String id, bool on) async {
    _requireHost();
    if (isRemote) await _transport!.setCoHost(_room!.code, id, on);
    participants = [
      for (final p in participants)
        if (p.id == id)
          p.copyWith(
            role: on ? JamRole.coHost : JamRole.guest,
            permissions: on ? JamPermissions.all : const JamPermissions(),
          )
        else
          p,
    ];
    _changed();
  }

  Future<void> setRules(JamRules next) async {
    _requireHost();
    if (isRemote) {
      await _transport!.setAccess(
        _room!.code,
        open: next.open,
        maxGuests: next.maxGuests,
      );
    }
    rules = next;
    _changed();
  }

  /// Cambia el código de la sala; el anterior deja de servir.
  Future<void> rotateCode() async {
    _requireHost();
    if (!isRemote) throw const JamException('Solo disponible en Jam en línea.');
    final code = await _transport!.rotateCode(_room!.code);
    _room = JamRoomInfo(
      code: code,
      hostUid: _room!.hostUid,
      expiresAt: _room!.expiresAt,
    );
    invite = JamInvite.remote(code: code, expiresAt: _room!.expiresAt);
    _changed();
  }

  void approve(String entryId, {required bool accept}) {
    _requireHost();
    queue = [
      for (final e in queue)
        if (e.id != entryId)
          e
        else if (accept)
          e.copyWith(status: JamEntryStatus.queued),
    ];
    _changed();
  }

  void _vote(String id, String entryId, int v) {
    final index = queue.indexWhere((e) => e.id == entryId);
    if (index < 0) throw const JamException('invalid');
    final e = queue[index];
    final up = e.up.where((x) => x != id).toList();
    final down = e.down.where((x) => x != id).toList();
    if (v > 0) up.add(id);
    if (v < 0) down.add(id);
    final copy = [...queue]..[index] = e.copyWith(up: up, down: down);
    queue = _sortedSuggested(copy);
    _changed();
  }

  /// Las sugeridas se ordenan por votos (estable) reutilizando sus huecos.
  List<JamQueueEntry> _sortedSuggested(List<JamQueueEntry> list) {
    final slots = [
      for (var i = 0; i < list.length; i++)
        if (list[i].status == JamEntryStatus.suggested &&
            list[i].id != playback?.entryId)
          i,
    ];
    final order = [...slots]
      ..sort((a, b) {
        final byScore = list[b].score.compareTo(list[a].score);
        return byScore != 0 ? byScore : a.compareTo(b);
      });
    final copy = [...list];
    for (var k = 0; k < slots.length; k++) {
      copy[slots[k]] = list[order[k]];
    }
    return copy;
  }

  static String _artist(String artist) =>
      artist.split(',').first.trim().toLowerCase();

  /// «A continuación»: intercala (round-robin) las listas de cada participante,
  /// sin duplicados ni el mismo artista seguido, respetando límites por invitado.
  void _rebuildSuggested() {
    final playing = playback?.entryId;
    final fixed = [
      for (final e in queue)
        if (e.status != JamEntryStatus.suggested || e.id == playing) e,
    ];
    final old = {
      for (final e in queue)
        if (e.status == JamEntryStatus.suggested && e.id != playing)
          e.track.key: e,
    };
    final seen = <String>{for (final e in fixed) ...e.track.keys};
    final order = [
      for (final p in participants)
        if (_suggestions[p.id]?.isNotEmpty == true) p,
    ];
    final pools = {
      for (final p in order) p.id: [..._suggestions[p.id]!],
    };
    final out = <JamQueueEntry>[];
    String? lastArtist = fixed.isEmpty
        ? null
        : _artist(fixed.last.track.artist);
    var progress = true;
    while (progress && fixed.length + out.length < 200) {
      progress = false;
      for (final p in order) {
        final pool = pools[p.id]!;
        pool.removeWhere((s) => s.track.keys.any(seen.contains));
        if (pool.isEmpty) continue;
        if (!p.isStaff &&
            [...fixed, ...out].where((e) => e.addedBy == p.id).length >=
                rules.maxPerGuest) {
          pool.clear();
          continue;
        }
        final pick = pool.firstWhere(
          (s) => _artist(s.track.artist) != lastArtist,
          orElse: () => pool.first,
        );
        pool.remove(pick);
        seen.addAll(pick.track.keys);
        final entry =
            old[pick.track.key] ??
            JamQueueEntry(
              id: jamRandomSecret(12),
              track: pick.track,
              addedBy: p.id,
              suggestedFor: p.id,
              status: rules.approve && !p.isStaff
                  ? JamEntryStatus.pending
                  : JamEntryStatus.suggested,
            );
        out.add(entry);
        lastArtist = _artist(entry.track.artist);
        progress = true;
      }
    }
    queue = _sortedSuggested([...fixed, ...out]);
  }

  /// En línea no se conservan participantes ausentes sin canciones (tope 16).
  void _prune() {
    if (!isRemote) return;
    participants = [
      for (final p in participants)
        if (p.id == 'host' ||
            p.connected ||
            queue.any((e) => e.addedBy == p.id))
          p,
    ];
  }

  // --- Transferencia de anfitrión ---

  /// El anfitrión actual cede el mando a [id] y pasa a ser coanfitrión.
  Future<void> transferHost(String id) async {
    _requireHost();
    final target = participants
        .where((p) => p.id == id && p.connected)
        .firstOrNull;
    if (!isRemote || target == null || id == 'host') {
      throw const JamException('Elige a un invitado conectado.');
    }
    await _transport!.transferHost(_room!.code, id);
    final message = jsonEncode({'kind': 'handoff', 'to': id, 'from': _uid});
    for (final peer in _sockets.values) {
      _sendSocket(peer, message);
    }
    // Deja un instante para que el aviso salga antes de cerrar el canal.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final code = _room!.code;
    final transport = _transport!;
    final name = participants.firstWhere((p) => p.id == 'host').name;
    _hub?.close().ignore();
    _hub = null;
    _sockets.clear();
    connection = JamConnection.disconnected;
    _beatTimer?.cancel();
    _room = null;
    // Vuelve a entrar como invitado (coanfitrión según el servidor).
    _transport = transport;
    invite = JamInvite.remote(
      code: code,
      expiresAt: clock().add(const Duration(hours: 12)),
    );
    _name = name;
    participantId = '';
    await reconnect();
  }

  void _handoff(String to, String from) {
    if (to != _uid || _transport == null || isHost) return;
    unawaited(() async {
      try {
        final claimed = await _transport!.claimHost(_room!.code);
        await _becomeHost(claimed, previousHostUid: from);
      } catch (failure) {
        error = _remoteError(failure);
        _notify();
      }
    }());
  }

  /// Asume la sala con la última instantánea recibida: el anfitrión anterior
  /// pasa de `host` a su uid y el nuevo ocupa el id `host`.
  Future<void> _becomeHost(
    JamRoomInfo room, {
    required String previousHostUid,
  }) async {
    final transport = _transport!;
    final myId = participantId;
    await _client?.close();
    _client = null;
    _pingTimer?.cancel();
    _retryTimer?.cancel();
    _hostLostTimer?.cancel();
    _hostLostTimer = null;
    String swap(String id) => id == 'host'
        ? previousHostUid
        : id == myId
        ? 'host'
        : id;
    participants =
        [
              for (final p in participants)
                p.copyWith(
                  role: p.id == myId
                      ? JamRole.host
                      : p.id == 'host'
                      ? JamRole.coHost
                      : null,
                ),
            ]
            .map(
              (p) => JamParticipant(
                id: swap(p.id),
                name: p.name,
                connected: p.connected,
                permissions: p.id == myId ? JamPermissions.all : p.permissions,
                role: p.role,
                muted: p.muted,
                listening: p.listening,
              ),
            )
            .toList();
    queue = [
      for (final e in queue)
        JamQueueEntry(
          id: e.id,
          track: e.track,
          addedBy: swap(e.addedBy),
          status: e.status,
          up: e.up,
          down: e.down,
          suggestedFor: e.suggestedFor == null ? null : swap(e.suggestedFor!),
        ),
    ];
    participantId = 'host';
    _room = room;
    _uid = (_uid.isEmpty) ? myId : _uid;
    invite = JamInvite.remote(code: room.code, expiresAt: room.expiresAt);
    connection = JamConnection.hosting;
    error = null;
    await _startHub(transport, room);
    _startBeat();
    _changed();
  }
}
