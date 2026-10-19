import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../jam_peer.dart';
import 'jam_transport.dart';

/// Control del hub hacia un invitado desconocido: que vuelva a saludar.
const jamRehelloText = '{"kind":"rehello"}';

/// Par virtual en el lado del anfitrión: representa a un invitado remoto.
class JamHubPeer implements JamPeer {
  JamHubPeer._(this._hub, this.uid) : lastHeard = _hub._now();
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _lastSweep = _now();
    _sub = channel.incoming.listen(_receive);
    _watchdog = Timer.periodic(_sweepEvery, (_) => sweep());
  }
  static const _sweepEvery = Duration(seconds: 5);
  final JamChannel channel;
  final String hostUid;
  final Duration silence;
  final DateTime Function() _now;
  late DateTime _lastSweep;
  bool _paused = false;
  final _askedHello = <String, DateTime>{};
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
    if (peer == null) {
      // Sin hello previo no se atiende, pero se le pide uno (como mucho cada
      // 5 s): pasa tras reabrir el canal o dar de baja a un invitado callado.
      final last = _askedHello[e.from];
      final now = _now();
      if (last == null || now.difference(last) > const Duration(seconds: 5)) {
        _askedHello[e.from] = now;
        unawaited(
          channel
              .send(
                JamEnvelope(from: hostUid, to: e.from, text: jamRehelloText),
              )
              .catchError((Object _) {}),
        );
      }
      return;
    }
    peer.lastHeard = _now();
    // Backpressure: más de 20 mensajes por segundo de un par se descartan.
    final second = peer.lastHeard.millisecondsSinceEpoch ~/ 1000;
    if (second != peer._burstSecond) {
      peer._burstSecond = second;
      peer._burst = 0;
    }
    if (++peer._burst > 20) return;
    if (!peer._inbox.isClosed) peer._inbox.add(e.text);
  }

  /// App en segundo plano: el SO puede congelar la red y los temporizadores,
  /// así que el silencio de los invitados no cuenta hasta [resume].
  void pause() => _paused = true;

  /// Vuelve al primer plano: da a todos los pares una ventana nueva (llevaban
  /// el mismo tiempo sin poder hablar que nosotros sin poder oírlos).
  void resume() {
    _paused = false;
    _forgive();
  }

  void _forgive() {
    final now = _now();
    _lastSweep = now;
    for (final peer in _peers.values) {
      peer.lastHeard = now;
    }
  }

  @visibleForTesting
  void sweep() {
    final now = _now();
    // Un barrido que llega muy tarde es un temporizador congelado, no
    // invitados mudos: se perdona en vez de expulsar a todos.
    final starved = now.difference(_lastSweep) > _sweepEvery * 3;
    if (_paused || starved) return _forgive();
    _lastSweep = now;
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
    this.hostGrace = const Duration(seconds: 12),
    this.netGrace = const Duration(seconds: 10),
    this.starveSlack = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final DateTime Function() _now;

  /// Tiempo que se espera a que vuelva la red tras reanudar la app antes de
  /// rendirse (en primer plano un corte cierra el par al instante).
  final Duration netGrace;

  /// Retraso admitido en un temporizador antes de tomarlo por congelado.
  final Duration starveSlack;
  final JamTransport transport;
  final JamChannel channel;
  final String code, uid;

  /// Único emisor aceptado en `down`. Cambia solo con un `handoff` del propio
  /// anfitrión actual.
  String hostUid;
  final Duration silence;

  /// Tiempo que se espera tras ver salir al anfitrión de la presencia antes de
  /// darlo por caído: la presencia no es una identidad verificada, así que solo
  /// cuenta si además calla (cualquier mensaje suyo la desmiente).
  final Duration hostGrace;
  Timer? _graceTimer, _netTimer;
  bool _open = true;
  bool _paused = false;
  DateTime? _hostBgUntil, _armedAt;
  Duration _armedFor = Duration.zero;
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
        // `f` en `down` lo declara quien publica (los coanfitriones también
        // pueden): solo se acepta lo que dice venir del anfitrión.
        if (e.from != hostUid) return;
        if (e.to != uid && e.to != '*') return;
        // Avisos de control (`bg`, `rehello`): solo para este par, no llegan
        // al servicio. Se leen antes de rearmar para que el margen cuente ya.
        final control = _followBackground(e.text);
        _graceTimer?.cancel();
        _graceTimer = null;
        _rearm();
        if (control) return;
        _followHandoff(e.text);
        if (!_inbox.isClosed) _inbox.add(e.text);
      }),
    );
    _subs.add(
      channel.presence.listen((p) {
        if (p.uid != hostUid) return;
        if (p.joined) {
          _graceTimer?.cancel();
          _graceTimer = null;
        } else {
          if (!_paused && _graceTimer == null) _armGrace();
        }
      }),
    );
    _subs.add(
      channel.online.listen((online) {
        if (online) {
          _netTimer?.cancel();
          _netTimer = null;
        } else if (!_paused) {
          // En segundo plano el SO corta sockets sin que la sala esté caída:
          // se reevalúa al volver ([resume]).
          _drop('network');
        }
      }),
    );
    await channel.track();
    _rearm();
    await transport.command(code, 'hello', const {});
  }

  /// Tras un `handoff` legítimo los mensajes pasan a venir del nuevo anfitrión.
  void _followHandoff(String text) {
    if (text.length > 256 || !text.contains('"handoff"')) return;
    try {
      final m = jsonDecode(text);
      if (m is Map && m['kind'] == 'handoff' && m['to'] is String) {
        final next = m['to'] as String;
        if (RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(next)) hostUid = next;
      }
    } catch (_) {}
  }

  /// El anfitrión avisó (`bg`) de que pasa a segundo plano: mientras dure el
  /// aviso se le da más margen de silencio. Acotado y solo si el sobre viene
  /// del anfitrión (el filtro `e.from` de [start]); `s: 0` lo anula.
  static const maxHostBackground = Duration(seconds: 90);
  bool get hostInBackground => _bgExtra() > Duration.zero;
  Duration _bgExtra() {
    final until = _hostBgUntil;
    final left = until?.difference(_now());
    return left != null && left > Duration.zero ? left : Duration.zero;
  }

  bool _followBackground(String text) {
    if (text == jamRehelloText) {
      if (!_paused) {
        transport.command(code, 'hello', const {}).catchError((Object _) {});
      }
      return true;
    }
    if (text.length > 64 || !text.contains('"bg"')) return false;
    try {
      final m = jsonDecode(text);
      if (m is! Map || m['kind'] != 'bg') return false;
      final s = m['s'];
      final seconds = s is int ? s.clamp(0, maxHostBackground.inSeconds) : 0;
      _hostBgUntil = seconds == 0
          ? null
          : _now().add(Duration(seconds: seconds));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _armGrace() {
    final armed = _now(), span = hostGrace + _bgExtra();
    _graceTimer = Timer(span, () {
      _graceTimer = null;
      // Despertar tardío = proceso congelado: la presencia no es de fiar aún.
      if (!_late(armed, span)) _drop('host');
    });
  }

  bool _late(DateTime armed, Duration span) =>
      _now().difference(armed) > span + starveSlack;

  void _rearm() {
    _watchdog?.cancel();
    if (_paused) return;
    _armedAt = _now();
    _armedFor = silence + _bgExtra();
    _watchdog = Timer(_armedFor, _silent);
  }

  void _silent() {
    if (!_open) return;
    // Despertar tardío = proceso congelado: los mensajes siguen en cola.
    if (_late(_armedAt ?? _now(), _armedFor)) return _rearm();
    _drop('silence');
  }

  /// App en segundo plano: el silencio y la presencia dejan de contar.
  void pause() {
    _paused = true;
    _watchdog?.cancel();
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  /// Vuelve al primer plano: ventana de silencio nueva, un `hello` por si el
  /// anfitrión nos dio de baja mientras callábamos, y margen para que la red
  /// vuelva antes de darla por perdida.
  void resume() {
    if (!_open) return;
    _paused = false;
    _rearm();
    if (!channel.isOnline) {
      _netTimer ??= Timer(netGrace, () => _drop('network'));
    } else {
      transport.command(code, 'hello', const {}).catchError((Object _) {});
    }
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
    _graceTimer?.cancel();
    _netTimer?.cancel();
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
