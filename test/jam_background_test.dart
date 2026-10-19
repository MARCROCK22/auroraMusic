import 'dart:async';
import 'dart:convert';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/jam/transport/jam_hub.dart';
import 'package:aurora_music/jam/transport/jam_transport.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'jam_remote_test.dart' show Room, guest, newRoom, song, until;
import 'support/fake_jam_backend.dart';
import 'support/fakes.dart';

/// Canal a mano: la prueba inyecta mensajes, presencia y cortes de red.
class _Stub implements JamChannel {
  final in_ = StreamController<JamEnvelope>.broadcast();
  final pres = StreamController<JamPresenceEvent>.broadcast();
  final on = StreamController<bool>.broadcast();
  final sent = <JamEnvelope>[];
  bool up = true;
  @override
  Stream<JamEnvelope> get incoming => in_.stream;
  @override
  Stream<JamPresenceEvent> get presence => pres.stream;
  @override
  Stream<bool> get online => on.stream;
  @override
  bool get isOnline => up;
  @override
  Future<void> send(JamEnvelope envelope) async => sent.add(envelope);
  @override
  Future<void> track() async {}
  @override
  Future<void> close() async {}
  void net(bool v) {
    up = v;
    on.add(v);
  }
}

Future<void> _wait([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

String _bg(int s) => jsonEncode({'kind': 'bg', 's': s});
JamEnvelope _from(String uid, String text, {String to = '*'}) =>
    JamEnvelope(from: uid, to: to, text: text);

typedef _G = ({JamGuestPeer peer, _Stub ch, List<String> got});

Future<_G> _peer({DateTime Function()? now}) async {
  final backend = FakeJamBackend();
  final host = backend.transport();
  final t = backend.transport();
  final room = await host.createRoom(name: 'H', device: 'other');
  await t.signIn();
  await t.joinRoom(code: room.code, name: 'G', device: 'other');
  final ch = _Stub();
  final peer = JamGuestPeer(
    transport: t,
    channel: ch,
    code: room.code,
    uid: 'g1',
    hostUid: 'h',
    silence: const Duration(milliseconds: 120),
    hostGrace: const Duration(milliseconds: 100),
    netGrace: const Duration(milliseconds: 150),
    now: now,
  );
  final got = <String>[];
  peer.listen((m) => got.add(m as String));
  await peer.start();
  return (peer: peer, ch: ch, got: got);
}

void main() {
  group('invitado en segundo plano (JamGuestPeer)', () {
    test('paused→resumed no cierra: el silencio no cuenta en pausa', () async {
      final g = await _peer();
      g.peer.pause();
      await _wait(400); // más de 3 × silence
      expect(g.peer.isOpen, isTrue);
      g.peer.resume();
      await _wait(60);
      expect(g.peer.isOpen, isTrue);
      // Reanudada, el silencio vuelve a contar.
      await _wait(200);
      expect(g.peer.closeReason, 'silence');
    });

    test('corte de red en segundo plano se tolera; sin red al volver, '
        'se espera netGrace y vuelve', () async {
      final g = await _peer();
      g.peer.pause();
      g.ch.net(false);
      await _wait(250);
      expect(g.peer.closeReason, isNull);
      g.ch.up = false; // sigue sin red al reanudar
      g.peer.resume();
      await _wait(60);
      g.ch.net(true); // vuelve dentro de la gracia (150 ms)
      for (var i = 0; i < 4; i++) {
        g.ch.in_.add(_from('h', '{"kind":"state"}'));
        await _wait(80); // pasada la gracia el temporizador de red se canceló
      }
      expect(g.peer.closeReason, isNull);
      expect(g.peer.isOpen, isTrue);
      await g.peer.close();
    });

    test('sin red tras la gracia de reanudación, se cierra por red', () async {
      final g = await _peer();
      g.peer.pause();
      g.ch.net(false);
      g.peer.resume();
      await _wait(300);
      expect(g.peer.closeReason, 'network');
    });

    test(
      'en primer plano un corte de red sigue cerrando al instante',
      () async {
        final g = await _peer();
        g.ch.net(false);
        await _wait();
        expect(g.peer.closeReason, 'network');
      },
    );

    test(
      'temporizador congelado (despertar tardío) no cuenta como silencio',
      () async {
        var skew = Duration.zero;
        final g = await _peer(now: () => DateTime.now().add(skew));
        skew = const Duration(seconds: 30); // el SO congeló el proceso
        await _wait(180); // el temporizador de 120 ms vence "tarde"
        expect(g.peer.isOpen, isTrue);
        expect(g.peer.closeReason, isNull);
        skew = Duration.zero;
        await _wait(450); // sin congelación, el silencio real sí cierra
        expect(g.peer.closeReason, 'silence');
      },
    );

    test('presencia que se pierde en pausa no arma la gracia', () async {
      final g = await _peer();
      g.peer.pause();
      g.ch.pres.add(const JamPresenceEvent('h', joined: false));
      await _wait(300);
      expect(g.peer.isOpen, isTrue);
      await g.peer.close();
    });
  });

  group('aviso bg del anfitrión', () {
    test('solo vale si viene del anfitrión y no llega al servicio', () async {
      final g = await _peer();
      // Un invitado/coanfitrión que lo falsifica no cambia nada.
      g.ch.in_.add(_from('cohost', _bg(90)));
      g.ch.in_.add(_from('cohost', _bg(90), to: 'g1'));
      await _wait();
      expect(g.peer.hostInBackground, isFalse);
      await _wait(250);
      expect(g.peer.closeReason, 'silence');
    });

    test(
      'del anfitrión: amplía el silencio, no se reenvía y s=0 lo anula',
      () async {
        final g = await _peer();
        g.ch.in_.add(_from('h', _bg(1)));
        await _wait();
        expect(g.peer.hostInBackground, isTrue);
        expect(g.got, isEmpty); // el servicio no ve el 'bg'
        await _wait(400); // > silence (120 ms), < aviso (1 s)
        expect(g.peer.isOpen, isTrue);
        g.ch.in_.add(_from('h', _bg(0)));
        await _wait();
        expect(g.peer.hostInBackground, isFalse);
        await _wait(300);
        expect(g.peer.closeReason, 'silence');
      },
    );

    test(
      'la presencia del anfitrión que sale se tolera durante el aviso',
      () async {
        final g = await _peer();
        g.ch.in_.add(_from('h', _bg(1)));
        await _wait();
        g.ch.pres.add(const JamPresenceEvent('h', joined: false));
        await _wait(300); // > hostGrace (100 ms)
        expect(g.peer.isOpen, isTrue);
        await g.peer.close();
      },
    );

    test('está acotado a 90 s aunque pidan más', () async {
      var t = DateTime(2030);
      final g = await _peer(now: () => t);
      g.ch.in_.add(_from('h', _bg(99999)));
      await _wait();
      t = t.add(const Duration(seconds: 89));
      expect(g.peer.hostInBackground, isTrue);
      t = t.add(const Duration(seconds: 2));
      expect(g.peer.hostInBackground, isFalse);
      await g.peer.close();
    });

    test('rehello del anfitrión: el invitado vuelve a saludar', () async {
      final backend = FakeJamBackend();
      final host = backend.transport();
      final t = backend.transport();
      final room = await host.createRoom(name: 'H', device: 'other');
      await t.joinRoom(code: room.code, name: 'G', device: 'other');
      final up = FakeChannel(backend.rooms[room.code]!, 'h', true);
      await up.track();
      final hellos = <String>[];
      up.incoming.listen((e) => hellos.add(e.text));
      final ch = _Stub();
      final peer = JamGuestPeer(
        transport: t,
        channel: ch,
        code: room.code,
        uid: 'g1',
        hostUid: 'h',
      );
      peer.listen((_) {}); // sin oyente, cerrar el par no termina
      await peer.start();
      await _wait();
      hellos.clear();
      ch.in_.add(_from('cohost', jamRehelloText, to: 'g1')); // falso: ignorado
      await _wait();
      expect(hellos, isEmpty);
      ch.in_.add(_from('h', jamRehelloText, to: 'g1'));
      await _wait();
      expect(hellos.single, contains('"hello"'));
      await peer.close();
    });
  });

  group('anfitrión en segundo plano (JamHubHost)', () {
    JamEnvelope hello() => _from('g1', '{"kind":"hello"}');

    test(
      'barrido pausado o congelado no expulsa; el silencio real sí',
      () async {
        var t = DateTime(2030);
        final ch = _Stub();
        final hub = JamHubHost(ch, hostUid: 'h', now: () => t);
        ch.in_.add(hello());
        await _wait();
        void advance(int seconds) {
          t = t.add(Duration(seconds: seconds));
          hub.sweep();
        }

        // Pausado: pasa mucho tiempo y nadie se da de baja.
        hub.pause();
        for (var i = 0; i < 10; i++) {
          advance(10);
        }
        // Al reanudar tienen ventana nueva.
        hub.resume();
        advance(10);
        expect(hub.channel.isOnline, isTrue);
        // Temporizador congelado (un barrido mil segundos tarde): se perdona.
        advance(1000);
        advance(10);
        // Con barridos puntuales y silencio real (>30 s) sí se cierra.
        final arrivals = <JamHubPeer>[];
        hub.arrivals.listen(arrivals.add);
        ch.in_.add(_from('g2', '{"kind":"hello"}'));
        await _wait();
        final peer = arrivals.single;
        expect(peer.isOpen, isTrue);
        for (var i = 0; i < 4; i++) {
          advance(10);
        }
        expect(peer.isOpen, isFalse);
        await hub.close();
      },
    );

    test(
      'un invitado desconocido recibe una petición de hello, con límite',
      () async {
        final ch = _Stub();
        final hub = JamHubHost(ch, hostUid: 'h');
        ch.in_.add(_from('g9', '{"kind":"ping","sent":1}'));
        ch.in_.add(_from('g9', '{"kind":"ping","sent":2}'));
        await _wait();
        expect(ch.sent, hasLength(1));
        expect(ch.sent.single.to, 'g9');
        expect(ch.sent.single.text, jamRehelloText);
        await hub.close();
      },
    );
  });

  group('JamService con servidor falso', () {
    Future<Room> twoPeople(void Function(JamService) mk) async {
      final room = await newRoom();
      mk(room.host);
      return room;
    }

    test(
      'invitado: paused→resumed no cierra ni pide unirse de nuevo',
      () async {
        final room = await twoPeople((_) {});
        final (g1, _) = await guest(room, 'Beto');
        await until(room.host, () => room.host.participants.length == 2);
        final id = g1.participantId;
        final invite = g1.invite;
        g1.appBackgrounded();
        expect(g1.inBackground, isTrue);
        room.host.addTrack(song(1));
        await until(g1, () => g1.queue.length == 1);
        g1.appResumed();
        expect(g1.connection, JamConnection.connected);
        expect(g1.invite, same(invite));
        expect(g1.participantId, id);
        expect(g1.me?.role, JamRole.guest);
        expect(g1.error, isNull);
        expect(room.host.participants.length, 2); // no se unió otra vez
        await _wait(100);
        expect(g1.connection, JamConnection.connected);
      },
    );

    test('enlace caído en segundo plano: al volver reconecta ya, con el mismo '
        'participante y sin perder el estado', () async {
      final room = await twoPeople((_) {});
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      final id = g1.participantId;
      g1.appBackgrounded();
      await g1.disconnect(); // el SO cortó el socket mientras estaba oculta
      expect(g1.reconnecting, isTrue);
      room.host.addTrack(song(1));
      g1.appResumed();
      await until(
        g1,
        () => g1.connection == JamConnection.connected && g1.queue.length == 1,
        seconds: 4,
      );
      expect(g1.participantId, id);
      expect(g1.invite, isNotNull);
      expect(g1.error, isNull);
    });

    test(
      'sin red en segundo plano: no cierra y se recupera al volver',
      () async {
        final room = await newRoom();
        final (g1, t1) = await guest(room, 'Beto');
        await until(room.host, () => room.host.participants.length == 2);
        g1.appBackgrounded();
        t1.cut(true); // canal caído, RPC fallan
        await _wait(150);
        expect(g1.connection, isNot(JamConnection.closed));
        t1.cut(false);
        g1.appResumed();
        await until(
          g1,
          () => g1.connection == JamConnection.connected,
          seconds: 6,
        );
        expect(g1.invite, isNotNull);
        expect(g1.error, isNull);
      },
    );

    test('anfitrión en segundo plano sigue siéndolo y los invitados no lo '
        'dan por caído', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      room.host.appBackgrounded();
      // La red del anfitrión parpadea: presencia fuera y dentro.
      final hubChannel = room.hostT.channels.first;
      hubChannel.setOnline(false);
      await _wait(100);
      expect(g1.connection, JamConnection.connected);
      hubChannel.setOnline(true);
      room.host.appResumed();
      expect(room.host.isHost, isTrue);
      room.host.addTrack(song(1));
      await until(g1, () => g1.queue.length == 1);
      g1.addTrack(song(2));
      await until(room.host, () => room.host.queue.length == 2);
    });

    test('canal del anfitrión que no vuelve: se reabre y los invitados '
        'se reincorporan solos', () async {
      final room = await newRoom();
      room.host.hubRecoveryDelay = const Duration(milliseconds: 100);
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      room.host.appBackgrounded();
      room.hostT.channels.first.setOnline(false); // Realtime no se recupera
      room.host.appResumed();
      await until(
        room.host,
        () => room.host.error == null && room.hostT.channels.length >= 2,
        seconds: 3,
      );
      // El primer comando se pierde (hub nuevo sin hello) y dispara el
      // rehello; tras él, el invitado vuelve a estar admitido.
      g1.addTrack(song(1));
      await until(
        room.host,
        () => room.host.participants.any((p) => p.id != 'host' && p.connected),
        seconds: 4,
      );
      g1.addTrack(song(2));
      await until(room.host, () => room.host.queue.isNotEmpty, seconds: 4);
      expect(room.host.isHost, isTrue);
    });
  });

  testWidgets(
    'JamController: paused/inactive/resumed del SO no cierra la Jam',
    (tester) async {
      final app = (await tester.runAsync(() => createTestController()))!;
      addTearDown(() => closeTestController(app));
      final jam = JamController(app: app);
      final s = jam.service
        ..connection = JamConnection.connected
        ..participantId = 'guest'
        ..participants = const [
          JamParticipant(id: 'host', name: 'Ana', role: JamRole.host),
          JamParticipant(id: 'guest', name: 'Beto'),
        ]
        ..invite = JamInvite.remote(
          code: 'ABCD22',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(s.inBackground, isFalse); // transitorio: se ignora
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(s.inBackground, isTrue);
      expect(s.connection, JamConnection.connected);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(s.inBackground, isFalse);
      expect(s.connection, JamConnection.connected);
      expect(s.invite, isNotNull);
      expect(jam.active, isTrue);
      jam.dispose(); // cancela el sondeo de enlace pendiente
    },
  );
}
