import 'dart:async';
import 'dart:convert';
import '../jam_peer.dart';
import 'jam_transport.dart';

/// Par virtual en el lado del anfitrión: representa a un invitado remoto.
class JamHubPeer implements JamPeer {
  JamHubPeer._(this._hub, this.uid) : lastHeard = DateTime.now();
  final JamHubHost _hub;
  final String uid;
  DateTime lastHeard;
  int _burst = 0;
  int _burstSecond = 0;
  bool _open = true;
  final _inbox = StreamController<Object?>();
  @override
  String? closeReason;
  @override
  bool get isOpen => _open && _hub.channel.isOnline;
  @override
  bool add(String data) {
    if (!isOpen) return false;
    unawaited(
      _hub.channel
          .send(JamEnvelope(from: _hub.hostUid, to: uid, text: data))
          .catchError((Object _) {}),
    );
    return true;
  }

  @override
  Future<void> close([int? code]) async {
    if (!_open) return;
    _open = false;
    if (identical(_hub._peers[uid], this)) _hub._peers.remove(uid);
    await _inbox.close();
  }

  @override
  StreamSubscription<Object?> listen(
    void Function(Object? message) onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) => _inbox.stream.listen(onData, onDone: onDone);
}

/// Convierte un [JamChannel] en un par virtual por invitado. El `from` de cada
/// mensaje lo fija el servidor, así que un invitado no puede hacerse pasar
/// por otro.
class JamHubHost {
  JamHubHost(
    this.channel, {
    required this.hostUid,
    this.silence = const Duration(seconds: 30),
  }) {
    _sub = channel.incoming.listen(_receive);
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) => _sweep());
  }
  final JamChannel channel;
  final String hostUid;
  final Duration silence;
  final Map<String, JamHubPeer> _peers = {};
  final _arrivals = StreamController<JamHubPeer>.broadcast();
  late final StreamSubscription<JamEnvelope> _sub;
  late final Timer _watchdog;

  /// Un invitado envió `hello` (nuevo o reconectando).
  Stream<JamHubPeer> get arrivals => _arrivals.stream;

  /// Un único mensaje para todos (estado y reproducción).
  bool broadcast(String text) {
    if (!channel.isOnline) return false;
    unawaited(
      channel
          .send(JamEnvelope(from: hostUid, to: '*', text: text))
          .catchError((Object _) {}),
    );
    return true;
  }

  void _receive(JamEnvelope e) {
    if (e.from == hostUid) return;
    final peer = _peers[e.from];
    var isHello = false;
    if (e.text.length < 64 && e.text.contains('"hello"')) {
      try {
        isHello = (jsonDecode(e.text) as Map)['kind'] == 'hello';
      } catch (_) {}
    }
    if (isHello) {
      // Una reconexión sustituye al par anterior sin dejar fantasmas.
      if (peer != null) unawaited(peer.close());
      final fresh = JamHubPeer._(this, e.from);
      _peers[e.from] = fresh;
      _arrivals.add(fresh);
      return;
    }
    if (peer == null) return; // sin hello previo: se ignora
    peer.lastHeard = DateTime.now();
    // Backpressure: más de 20 mensajes por segundo de un par se descartan.
    final second = peer.lastHeard.millisecondsSinceEpoch ~/ 1000;
    if (second != peer._burstSecond) {
      peer._burstSecond = second;
      peer._burst = 0;
    }
    if (++peer._burst > 20) return;
    if (!peer._inbox.isClosed) peer._inbox.add(e.text);
  }

  void _sweep() {
    final now = DateTime.now();
    for (final peer in [..._peers.values]) {
      if (now.difference(peer.lastHeard) > silence) unawaited(peer.close());
    }
  }

  Future<void> close() async {
    _watchdog.cancel();
    await _sub.cancel();
    for (final peer in [..._peers.values]) {
      await peer.close();
    }
    await _arrivals.close();
    await channel.close();
  }
}

/// Par virtual en el lado del invitado: un único "socket" hacia el anfitrión.
class JamGuestPeer implements JamPeer {
  JamGuestPeer({
    required this.transport,
    required this.channel,
    required this.code,
    required this.uid,
    required this.hostUid,
    this.silence = const Duration(seconds: 25),
  });
  final JamTransport transport;
  final JamChannel channel;
  final String code, uid, hostUid;
  final Duration silence;
  bool _open = true;
  final _inbox = StreamController<Object?>();
  final _subs = <StreamSubscription<Object?>>[];
  Timer? _watchdog;
  @override
  String? closeReason;
  @override
  bool get isOpen => _open && channel.isOnline;

  /// Anuncia presencia y saluda al anfitrión. El saludo lo reenvía el servidor.
  Future<void> start() async {
    _subs.add(
      channel.incoming.listen((e) {
        if (e.to != uid && e.to != '*') return;
        _rearm();
        if (!_inbox.isClosed) _inbox.add(e.text);
      }),
    );
    _subs.add(
      channel.presence.listen((p) {
        if (!p.joined && p.uid == hostUid) _drop('host');
      }),
    );
    _subs.add(
      channel.online.listen((online) {
        if (!online) _drop('network');
      }),
    );
    await channel.track();
    _rearm();
    await transport.command(code, 'hello', const {});
  }

  void _rearm() {
    _watchdog?.cancel();
    _watchdog = Timer(silence, () => _drop('silence'));
  }

  void _drop(String reason) {
    if (!_open) return;
    closeReason = reason;
    unawaited(close());
  }

  @override
  bool add(String data) {
    if (!isOpen) return false;
    final Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      return false;
    }
    final kind = map.remove('kind');
    if (kind is! String) return false;
    transport.command(code, kind, map).catchError((Object failure) {
      final text = failure is JamRemoteException ? failure.code : 'network';
      // Fallos terminales (expulsado, caducada...) cierran el par; el resto se ignora.
      if ({
        'banned',
        'expired',
        'invalid',
        'forbidden',
        'closed',
      }.contains(text)) {
        _drop(text);
      } else if (!_inbox.isClosed) {
        // Rechazos del servidor (silencio, límites): el invitado debe verlos.
        final code = switch (text) {
          'muted' => 'muted',
          'limit' => 'limit',
          'rate' => 'rate',
          'full' => 'full',
          _ => 'invalid',
        };
        if (text != 'network') {
          _inbox.add(jsonEncode({'kind': 'error', 'code': code}));
        }
      }
    });
    return true;
  }

  @override
  Future<void> close([int? code]) async {
    if (!_open) return;
    _open = false;
    _watchdog?.cancel();
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _inbox.close();
    await channel.close();
  }

  @override
  StreamSubscription<Object?> listen(
    void Function(Object? message) onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) => _inbox.stream.listen(onData, onDone: onDone);
}
