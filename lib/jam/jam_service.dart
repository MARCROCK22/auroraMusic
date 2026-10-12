import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'jam_models.dart';

/// Host owns every mutation. Participant commands never carry playback/provider credentials.
class JamService extends ChangeNotifier {
  JamService({DateTime Function()? clock, this.allowLoopback = false})
    : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final bool allowLoopback;
  JamConnection connection = JamConnection.idle;
  JamMode mode = JamMode.queueOnly;
  JamInvite? invite;
  String participantId = 'host';
  String? error;
  int revision = 0;
  int clockOffsetMs = 0;
  int? roundTripMs;
  List<JamQueueEntry> queue = [];
  List<JamParticipant> participants = [];
  JamPlayback? playback;
  Future<void> Function()? onSkip;
  HttpServer? _server;
  WebSocket? _client;
  HttpClient? _httpClient;
  Timer? _expiryTimer, _pingTimer;
  final Map<String, WebSocket> _sockets = {};
  final Map<String, String> _resumeTokens = {};
  final Map<String, List<DateTime>> _rates = {};
  final Set<String> _joiningIds = {};
  final Map<int, int> _pings = {};
  String? _resumeToken;
  String _name = '';
  int _generation = 0;
  int _pendingUpgrades = 0;
  bool _disposed = false;
  bool get isHost => connection == JamConnection.hosting;
  bool get connected => isHost || connection == JamConnection.connected;
  JamParticipant? get me =>
      participants.where((p) => p.id == participantId).firstOrNull;
  String participantName(String id) =>
      participants.where((p) => p.id == id).firstOrNull?.name ?? 'Participante';
  static const connectionHelp =
      'No se pudo conectar. Comprueba la misma red Wi-Fi, el aislamiento del router y el permiso de firewall de Aurora.';

  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where((a) => isJamAddress(a))
        .toSet()
        .toList();
  }

  Future<void> host({
    required String address,
    required String name,
    Duration lifetime = const Duration(hours: 4),
  }) async {
    if (!isJamAddress(address, allowLoopback: allowLoopback) ||
        lifetime <= Duration.zero ||
        lifetime > const Duration(hours: 4)) {
      throw const JamException(
        'Selecciona una dirección privada de tu red local.',
      );
    }
    name = jamText(name, max: 32);
    await close();
    final generation = ++_generation;
    try {
      final server = await HttpServer.bind(
        InternetAddress(address),
        0,
        backlog: 16,
      );
      if (_disposed || generation != _generation) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.idleTimeout = const Duration(seconds: 10);
      invite = JamInvite(
        address: address,
        port: server.port,
        sessionId: jamRandomSecret(16),
        accessToken: jamRandomSecret(),
        expiresAt: clock().add(lifetime),
      );
      connection = JamConnection.hosting;
      participantId = 'host';
      participants = [
        JamParticipant(
          id: 'host',
          name: name,
          permissions: const JamPermissions(
            skip: true,
            reorder: true,
            remove: true,
          ),
        ),
      ];
      error = null;
      server.listen(
        (request) {
          unawaited(
            _accept(request).catchError((Object _) async {
              try {
                request.response.statusCode = HttpStatus.forbidden;
                await request.response.close();
              } catch (_) {}
            }),
          );
        },
        onError: (_) {
          error = connectionHelp;
          _notify();
        },
      );
      _expiryTimer = Timer(lifetime, () {
        unawaited(close());
      });
      _changed();
    } catch (_) {
      connection = JamConnection.closed;
      error = connectionHelp;
      _notify();
      throw const JamException(connectionHelp);
    }
  }

  Future<void> _accept(HttpRequest request) async {
    final session = invite;
    final remote = request.connectionInfo?.remoteAddress.address;
    if (_pendingUpgrades >= 16 ||
        session == null ||
        !isHost ||
        !session.expiresAt.isAfter(clock()) ||
        remote == null ||
        !isJamAddress(remote, allowLoopback: allowLoopback) ||
        request.method != 'GET' ||
        request.uri.path != '/jam/${session.sessionId}' ||
        request.uri.hasQuery ||
        request.headers.value('origin') != null ||
        !_equalSecret(
          request.headers.value('authorization') ?? '',
          'Bearer ${session.accessToken}',
        ) ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    _pendingUpgrades++;
    String? reservedId;
    try {
      final name = jamText(
        Uri.decodeComponent(request.headers.value('x-aurora-name') ?? ''),
        max: 32,
      );
      final requestedId = request.headers.value('x-aurora-participant');
      final requestedResume = request.headers.value('x-aurora-resume');
      String id;
      if (requestedId != null || requestedResume != null) {
        if (requestedId == null ||
            requestedResume == null ||
            requestedId == 'host' ||
            requestedId.length != 16 ||
            requestedResume.length != 43 ||
            !_resumeTokens.containsKey(requestedId) ||
            !participants.any((person) => person.id == requestedId) ||
            _joiningIds.contains(requestedId) ||
            !_equalSecret(_resumeTokens[requestedId] ?? '', requestedResume) ||
            _sockets.containsKey(requestedId)) {
          throw const JamException('Reconexión inválida.');
        }
        id = requestedId;
      } else {
        if (participants.length + _pendingUpgrades > 16) {
          throw const JamException(
            'La Jam llegó a su límite de participantes.',
          );
        }
        id = jamRandomSecret(12);
      }
      _joiningIds.add(id);
      reservedId = id;
      final socket = await WebSocketTransformer.upgrade(request);
      if (!isHost || invite != session) {
        await socket.close();
        return;
      }
      _sockets[id] = socket;
      _resumeTokens.putIfAbsent(id, () => jamRandomSecret());
      final prior = participants.where((p) => p.id == id).firstOrNull;
      participants = [
        ...participants.where((p) => p.id != id),
        JamParticipant(
          id: id,
          name: name,
          permissions: prior?.permissions ?? const JamPermissions(),
        ),
      ];
      socket.add(
        jsonEncode({
          'kind': 'welcome',
          'participantId': id,
          'resumeToken': _resumeTokens[id],
        }),
      );
      socket.listen(
        (message) => _receiveCommand(id, message),
        onDone: () => _disconnected(id, socket),
        onError: (_) => _disconnected(id, socket),
        cancelOnError: true,
      );
      _changed();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      } catch (_) {}
    } finally {
      if (reservedId != null) _joiningIds.remove(reservedId);
      _pendingUpgrades--;
    }
  }

  Future<void> join(JamInvite session, {required String name}) async {
    // Revalidate constructed invitations too; URLs/hostnames never reach the transport.
    session = JamInvite.decode(
      session.encode(),
      allowLoopback: allowLoopback,
      now: clock(),
    );
    name = jamText(name, max: 32);
    await close();
    invite = session;
    _name = name;
    _resumeToken = null;
    participantId = '';
    await reconnect();
  }

  Future<void> reconnect() async {
    final session = invite;
    if (session == null || !session.expiresAt.isAfter(clock())) {
      throw const JamException(
        'La invitación de Jam venció. Solicita un QR nuevo.',
      );
    }
    final generation = ++_generation;
    final ready = Completer<void>();
    error = null;
    connection = JamConnection.disconnected;
    _notify();
    try {
      await _client?.close();
      _httpClient?.close(force: true);
      final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      // A redirect can never leak authorization to another host or port.
      http.connectionFactory = (uri, proxyHost, proxyPort) {
        if (uri.host != session.address ||
            uri.port != session.port ||
            proxyHost != null) {
          throw const JamException('Destino de conexión de Jam inválido.');
        }
        return Socket.startConnect(
          InternetAddress(session.address),
          session.port,
        );
      };
      http.findProxy = (_) => 'DIRECT';
      _httpClient = http;
      final socket = await WebSocket.connect(
        'ws://${session.address}:${session.port}/jam/${session.sessionId}',
        customClient: http,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'X-Aurora-Name': Uri.encodeComponent(_name),
          if (_resumeToken != null) ...{
            'X-Aurora-Participant': participantId,
            'X-Aurora-Resume': _resumeToken!,
          },
        },
      ).timeout(const Duration(seconds: 6));
      if (_disposed || generation != _generation) {
        await socket.close();
        return;
      }
      _client = socket;
      socket.listen(
        (message) {
          if (_disposed || generation != _generation) return;
          try {
            final data = _message(message, maxBytes: 1024 * 1024);
            switch (data['kind']) {
              case 'welcome':
                jamKeys(data, {'kind', 'participantId', 'resumeToken'});
                final id = jamIdentifier(data['participantId']);
                final resume = jamIdentifier(data['resumeToken']);
                if (id == 'host' || resume.length != 43) {
                  throw const JamException('Identidad inválida.');
                }
                participantId = id;
                _resumeToken = resume;
              case 'state':
                _snapshot(data);
                if (participantId.isEmpty ||
                    !participants.any((p) => p.id == participantId)) {
                  throw const JamException('Participante ausente.');
                }
                connection = JamConnection.connected;
                if (!ready.isCompleted) ready.complete();
                _notify();
              case 'pong':
                jamKeys(data, {'kind', 'sent', 'serverTimeMs'});
                final sent = jamInt(data['sent'], max: 8640000000000000);
                final before = _pings.remove(sent);
                if (before != null) {
                  final after = clock().millisecondsSinceEpoch;
                  final roundTrip = after - before;
                  if (roundTrip >= 0 && roundTrip < 10000) {
                    roundTripMs = roundTrip;
                    clockOffsetMs =
                        jamInt(data['serverTimeMs'], max: 8640000000000000) -
                        (before + roundTrip ~/ 2);
                  }
                }
              case 'playback':
                jamKeys(data, {'kind', 'playback'});
                final state = JamPlayback.fromJson(data['playback']);
                if (state.entryId != null &&
                    !queue.any((entry) => entry.id == state.entryId)) {
                  throw const JamException('Pista de reproducción inválida.');
                }
                if (playback == null || state.sequence >= playback!.sequence) {
                  playback = state;
                }
                _notify();
              case 'error':
                jamKeys(data, {'kind', 'code'});
                if (!{
                  'permissions',
                  'rate',
                  'full',
                  'invalid',
                }.contains(data['code'])) {
                  throw const JamException('Código de error inválido.');
                }
                error = _commandError(data['code']);
                _notify();
              case 'closed':
                jamKeys(data, {'kind'});
                connection = JamConnection.closed;
                error = 'El anfitrión cerró la Jam.';
                invite = null;
                _pingTimer?.cancel();
                _notify();
              default:
                throw const JamException('Protocolo de Jam inválido.');
            }
          } catch (_) {
            error = 'La Jam recibió un mensaje inválido.';
            if (!ready.isCompleted) {
              ready.completeError(
                const JamException('La sesión no respondió correctamente.'),
              );
            }
            unawaited(socket.close(WebSocketStatus.policyViolation));
            _notify();
          }
        },
        onError: (_) {
          if (generation == _generation) {
            _clientDisconnected();
            if (!ready.isCompleted) {
              ready.completeError(const JamException(connectionHelp));
            }
          }
        },
        onDone: () {
          if (generation == _generation) {
            _clientDisconnected();
            if (!ready.isCompleted) {
              ready.completeError(const JamException(connectionHelp));
            }
          }
        },
        cancelOnError: true,
      );
      await ready.future.timeout(const Duration(seconds: 5));
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) => _ping());
      _ping();
    } catch (_) {
      if (generation != _generation || _disposed) return;
      _httpClient?.close(force: true);
      await _client?.close();
      _client = null;
      connection = JamConnection.disconnected;
      error = connectionHelp;
      _notify();
      throw const JamException(connectionHelp);
    }
  }

  void _snapshot(Map<String, dynamic> data) {
    jamKeys(data, {
      'kind',
      'revision',
      'mode',
      'queue',
      'participants',
      'playback',
    });
    final next = jamInt(data['revision']);
    if (next < revision) return;
    final rawQueue = data['queue'];
    final rawPeople = data['participants'];
    if (rawQueue is! List ||
        rawQueue.length > 200 ||
        rawPeople is! List ||
        rawPeople.length > 16 ||
        rawPeople.isEmpty ||
        !JamMode.values.any((v) => v.name == data['mode'])) {
      throw const JamException('Estado de Jam inválido.');
    }
    final entries = rawQueue.map(JamQueueEntry.fromJson).toList();
    final people = rawPeople.map(JamParticipant.fromJson).toList();
    if (entries.map((e) => e.id).toSet().length != entries.length ||
        people.map((p) => p.id).toSet().length != people.length ||
        !people.any((p) => p.id == 'host') ||
        entries.any((e) => !people.any((p) => p.id == e.addedBy))) {
      throw const JamException('Estado de Jam inválido.');
    }
    final state = data['playback'] == null
        ? null
        : JamPlayback.fromJson(data['playback']);
    if (state?.entryId != null &&
        !entries.any((entry) => entry.id == state!.entryId)) {
      throw const JamException('Pista de reproducción inválida.');
    }
    revision = next;
    queue = entries;
    participants = people;
    mode = JamMode.values.firstWhere((v) => v.name == data['mode']);
    if (state != null &&
        (playback == null || state.sequence >= playback!.sequence)) {
      playback = state;
    }
  }

  void _receiveCommand(String id, Object? message) {
    try {
      if (!isHost || invite == null || !invite!.expiresAt.isAfter(clock())) {
        return;
      }
      _takeRequest(id);
      final data = _message(message, maxBytes: 8192);
      _command(id, data);
    } on JamException catch (failure) {
      _sendSocket(
        _sockets[id],
        jsonEncode({
          'kind': 'error',
          'code': {'permissions', 'rate', 'full'}.contains(failure.message)
              ? failure.message
              : 'invalid',
        }),
      );
      if (failure.message == 'rate') {
        unawaited(_sockets[id]?.close(WebSocketStatus.policyViolation));
      }
    } catch (_) {
      _sendSocket(
        _sockets[id],
        jsonEncode({'kind': 'error', 'code': 'invalid'}),
      );
    }
  }

  void _command(String id, Map<String, dynamic> data) {
    final participant = participants
        .where((p) => p.id == id && p.connected)
        .firstOrNull;
    if (participant == null) throw const JamException('permissions');
    switch (data['kind']) {
      case 'add':
        jamKeys(data, {'kind', 'track'});
        final track = JamTrack.fromJson(data['track']);
        if (queue.any((entry) => entry.track.keys.any(track.keys.contains))) {
          return;
        }
        if (queue.length >= 200) throw const JamException('full');
        queue = [
          ...queue,
          JamQueueEntry(id: jamRandomSecret(12), track: track, addedBy: id),
        ];
        _changed();
      case 'remove':
        jamKeys(data, {'kind', 'entryId'});
        if (!participant.permissions.remove) {
          throw const JamException('permissions');
        }
        final entryId = jamIdentifier(data['entryId']);
        queue = queue.where((entry) => entry.id != entryId).toList();
        if (playback?.entryId == entryId) {
          playback = JamPlayback(
            sequence: (playback?.sequence ?? 0) + 1,
            serverTimeMs: clock().millisecondsSinceEpoch,
          );
        }
        _changed();
      case 'reorder':
        jamKeys(data, {'kind', 'entryId', 'to'});
        if (!participant.permissions.reorder) {
          throw const JamException('permissions');
        }
        final entryId = jamIdentifier(data['entryId']);
        final target = jamInt(data['to'], max: 199);
        final index = queue.indexWhere((entry) => entry.id == entryId);
        if (index < 0 || target >= queue.length) {
          throw const JamException('invalid');
        }
        final copy = [...queue];
        final entry = copy.removeAt(index);
        copy.insert(target, entry);
        queue = copy;
        _changed();
      case 'skip':
        jamKeys(data, {'kind'});
        if (!participant.permissions.skip) {
          throw const JamException('permissions');
        }
        unawaited(
          onSkip?.call().catchError((Object _) {
            error = 'No se pudo avanzar la reproducción.';
            _notify();
          }),
        );
      case 'ping':
        jamKeys(data, {'kind', 'sent'});
        final sent = jamInt(data['sent'], max: 8640000000000000);
        _sendSocket(
          _sockets[id],
          jsonEncode({
            'kind': 'pong',
            'sent': sent,
            'serverTimeMs': clock().millisecondsSinceEpoch,
          }),
        );
      case 'leave':
        jamKeys(data, {'kind'});
        // Keep public author information for existing queue entries, invalidate reconnect permission.
        _resumeTokens.remove(id);
        unawaited(_sockets[id]?.close());
      default:
        throw const JamException('invalid');
    }
  }

  void addTrack(JamTrack track) =>
      _sendCommand({'kind': 'add', 'track': track.toJson()});
  void remove(String entryId) =>
      _sendCommand({'kind': 'remove', 'entryId': entryId});
  void reorder(String entryId, int to) =>
      _sendCommand({'kind': 'reorder', 'entryId': entryId, 'to': to});
  void skip() => _sendCommand({'kind': 'skip'});
  void _sendCommand(Map<String, dynamic> command) {
    if (!connected) {
      throw const JamException(
        'Vuelve a conectar con la Jam para modificar la cola.',
      );
    }
    if (isHost) {
      _takeRequest('host');
      _command('host', command);
    } else {
      if (!_sendSocket(_client, jsonEncode(command))) {
        throw const JamException(connectionHelp);
      }
    }
  }

  void _takeRequest(String id) {
    final rates = _rates.putIfAbsent(id, () => []);
    rates.removeWhere(
      (time) => clock().difference(time) >= const Duration(seconds: 5),
    );
    if (rates.length >= 10) throw const JamException('rate');
    rates.add(clock());
  }

  void setPermissions(String id, JamPermissions permissions) {
    if (!isHost || id == 'host') {
      throw const JamException('Solo el anfitrión puede cambiar permisos.');
    }
    participants = participants
        .map(
          (person) => person.id == id
              ? JamParticipant(
                  id: id,
                  name: person.name,
                  connected: person.connected,
                  permissions: permissions,
                )
              : person,
        )
        .toList();
    _changed();
  }

  void setMode(JamMode value) {
    if (!isHost) {
      throw const JamException('Solo el anfitrión puede cambiar el modo.');
    }
    mode = value;
    _changed();
  }

  void publishPlayback({
    String? entryId,
    required bool playing,
    required int positionMs,
  }) {
    if (!isHost) return;
    if (entryId != null && !queue.any((e) => e.id == entryId)) return;
    playback = JamPlayback(
      sequence: (playback?.sequence ?? 0) + 1,
      entryId: entryId,
      isPlaying: playing,
      positionMs: positionMs.clamp(0, 86400000),
      serverTimeMs: clock().millisecondsSinceEpoch,
    );
    final message = jsonEncode({
      'kind': 'playback',
      'playback': playback!.toJson(),
    });
    for (final socket in _sockets.values) {
      _sendSocket(socket, message);
    }
    _notify();
  }

  void _ping() {
    if (connection != JamConnection.connected) return;
    _pings.clear();
    final sent = clock().millisecondsSinceEpoch;
    _pings[sent] = sent;
    _sendSocket(_client, jsonEncode({'kind': 'ping', 'sent': sent}));
  }

  void _changed() {
    revision++;
    _broadcast();
    _notify();
  }

  void _broadcast() {
    if (!isHost) return;
    final data = jsonEncode({
      'kind': 'state',
      'revision': revision,
      'mode': mode.name,
      'queue': queue.map((e) => e.toJson()).toList(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'playback': playback?.toJson(),
    });
    for (final socket in _sockets.values) {
      _sendSocket(socket, data);
    }
  }

  void _disconnected(String id, WebSocket socket) {
    if (_sockets[id] != socket) return;
    _sockets.remove(id);
    participants = participants
        .map(
          (p) => p.id == id
              ? JamParticipant(
                  id: id,
                  name: p.name,
                  connected: false,
                  permissions: p.permissions,
                )
              : p,
        )
        .toList();
    if (isHost) _changed();
  }

  void _clientDisconnected() {
    _pingTimer?.cancel();
    if (connection != JamConnection.closed) {
      connection = JamConnection.disconnected;
      error = connectionHelp;
    }
    _notify();
  }

  Future<void> close() async {
    ++_generation;
    _expiryTimer?.cancel();
    _pingTimer?.cancel();
    _pings.clear();
    final server = _server;
    _server = null;
    final client = _client;
    _client = null;
    if (client != null && client.readyState == WebSocket.open) {
      _sendSocket(client, jsonEncode({'kind': 'leave'}));
    }
    if (isHost) {
      for (final socket in _sockets.values) {
        if (socket.readyState == WebSocket.open) {
          _sendSocket(socket, jsonEncode({'kind': 'closed'}));
        }
      }
    }
    final sockets = [..._sockets.values];
    _sockets.clear();
    connection = JamConnection.closed;
    mode = JamMode.queueOnly;
    invite = null;
    _resumeToken = null;
    _resumeTokens.clear();
    _rates.clear();
    _joiningIds.clear();
    queue = [];
    participants = [];
    playback = null;
    revision = 0;
    clockOffsetMs = 0;
    roundTripMs = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    await Future.wait([
      if (client != null) client.close(),
      ...sockets.map((socket) => socket.close()),
    ]);
    await server?.close(force: true);
    _notify();
  }

  /// Testable transport interruption; reconnection retains ephemeral participant credentials.
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    await _client?.close();
    _client = null;
    _clientDisconnected();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

Map<String, dynamic> _message(Object? message, {required int maxBytes}) {
  if (message is! String ||
      message.length > maxBytes ||
      utf8.encode(message).length > maxBytes) {
    throw const JamException('invalid');
  }
  try {
    return jamMap(jsonDecode(message));
  } catch (_) {
    throw const JamException('invalid');
  }
}

bool _equalSecret(String left, String right) {
  if (left.isEmpty || left.length != right.length || left.length > 128) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return difference == 0;
}

String _commandError(Object? code) => switch (code) {
  'permissions' => 'El anfitrión no habilitó ese permiso.',
  'rate' => 'Demasiadas solicitudes. Espera unos segundos.',
  'full' => 'La cola compartida llegó al límite de 200 canciones.',
  _ => 'La solicitud de Jam no es válida.',
};

bool _sendSocket(WebSocket? socket, String data) {
  if (socket == null || socket.readyState != WebSocket.open) return false;
  try {
    socket.add(data);
    return true;
  } catch (_) {
    return false;
  }
}
