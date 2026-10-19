import 'dart:async';
import 'dart:convert';
import 'package:aurora_music/jam/transport/jam_hub.dart';
import 'package:aurora_music/jam/transport/jam_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_jam_backend.dart';

/// Canal que deja a la prueba inyectar mensajes y presencia a mano (lo que un
/// miembro hostil puede hacer en Realtime).
class _Stub implements JamChannel {
  final in_ = StreamController<JamEnvelope>.broadcast();
  final pres = StreamController<JamPresenceEvent>.broadcast();
  final on = StreamController<bool>.broadcast();
  @override
  Stream<JamEnvelope> get incoming => in_.stream;
  @override
  Stream<JamPresenceEvent> get presence => pres.stream;
  @override
  Stream<bool> get online => on.stream;
  @override
  bool get isOnline => true;
  @override
  Future<void> send(JamEnvelope envelope) async {}
  @override
  Future<void> track() async {}
  @override
  Future<void> close() async {}
}

const _grace = Duration(milliseconds: 150);

Future<void> _pause([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

String _kind(String kind, [Map<String, Object?> extra = const {}]) =>
    jsonEncode({'kind': kind, ...extra});

Future<({JamGuestPeer peer, _Stub ch, List<String> got})> _guest() async {
  final backend = FakeJamBackend();
  final host = backend.transport();
  final guest = backend.transport();
  final room = await host.createRoom(name: 'H', device: 'other');
  await guest.signIn();
  await guest.joinRoom(code: room.code, name: 'G', device: 'other');
  final ch = _Stub();
  final peer = JamGuestPeer(
    transport: guest,
    channel: ch,
    code: room.code,
    uid: 'g1',
    hostUid: 'h',
    hostGrace: _grace,
  );
  final got = <String>[];
  peer.listen((m) => got.add(m as String));
  await peer.start();
  return (peer: peer, ch: ch, got: got);
}

JamEnvelope _from(String uid, String text, {String to = '*'}) =>
    JamEnvelope(from: uid, to: to, text: text);

void main() {
  test(
    'presencia falsa del anfitrión no lo expulsa si sigue hablando',
    () async {
      final g = await _guest();
      // Un invitado hace track({'uid': host}) y luego untrack.
      g.ch.pres.add(const JamPresenceEvent('h', joined: false));
      await _pause();
      g.ch.in_.add(_from('h', _kind('state')));
      await _pause(250);
      expect(g.peer.isOpen, isTrue);
      expect(g.peer.closeReason, isNull);
      expect(g.got, [_kind('state')]);
      await g.peer.close();
    },
  );

  test('si el anfitrión sale de verdad y calla, se da por caído', () async {
    final g = await _guest();
    g.ch.pres.add(const JamPresenceEvent('h', joined: false));
    await _pause(300);
    expect(g.peer.isOpen, isFalse);
    expect(g.peer.closeReason, 'host');
  });

  test('si el anfitrión vuelve a la presencia no se le da por caído', () async {
    final g = await _guest();
    g.ch.pres.add(const JamPresenceEvent('h', joined: false));
    await _pause();
    g.ch.pres.add(const JamPresenceEvent('h', joined: true));
    await _pause(250);
    expect(g.peer.isOpen, isTrue);
    await g.peer.close();
  });

  test('la presencia de otros no afecta', () async {
    final g = await _guest();
    g.ch.pres.add(const JamPresenceEvent('someone', joined: false));
    await _pause(250);
    expect(g.peer.isOpen, isTrue);
    await g.peer.close();
  });

  test('control falso de un coanfitrión se ignora', () async {
    final g = await _guest();
    for (final kind in ['closed', 'kicked', 'state']) {
      g.ch.in_.add(_from('cohost', _kind(kind)));
      g.ch.in_.add(_from('cohost', _kind(kind), to: 'g1'));
    }
    g.ch.in_.add(
      _from('cohost', _kind('handoff', {'to': 'cohost', 'from': 'h'})),
    );
    await _pause();
    expect(g.got, isEmpty);
    // Un handoff falso tampoco cambia quién es el anfitrión.
    g.ch.in_.add(_from('cohost', _kind('closed')));
    await _pause();
    expect(g.got, isEmpty);
    // Lo auténtico del anfitrión sí llega, general o dirigido a este invitado.
    g.ch.in_.add(_from('h', _kind('state')));
    g.ch.in_.add(_from('h', _kind('welcome'), to: 'g1'));
    g.ch.in_.add(_from('h', _kind('welcome'), to: 'otro'));
    await _pause();
    expect(g.got, [_kind('state'), _kind('welcome')]);
    await g.peer.close();
  });

  test(
    'el handoff legítimo sigue funcionando y traspasa la confianza',
    () async {
      final g = await _guest();
      final handoff = _kind('handoff', {'to': 'n', 'from': 'h'});
      g.ch.in_.add(_from('h', handoff));
      await _pause();
      expect(g.got, [handoff]);
      expect(g.peer.hostUid, 'n');
      // Ahora manda el nuevo anfitrión; el anterior ya no.
      g.ch.in_.add(_from('n', _kind('state')));
      g.ch.in_.add(_from('h', _kind('closed')));
      await _pause();
      expect(g.got, [handoff, _kind('state')]);
      // La salida del anfitrión anterior de la presencia es irrelevante...
      g.ch.pres.add(const JamPresenceEvent('h', joined: false));
      await _pause(250);
      expect(g.peer.isOpen, isTrue);
      // ...y la del nuevo, si calla, sí cuenta.
      g.ch.pres.add(const JamPresenceEvent('n', joined: false));
      await _pause(300);
      expect(g.peer.closeReason, 'host');
    },
  );

  test('el anfitrión descarta lo que dice venir de él mismo', () async {
    final ch = _Stub();
    final hub = JamHubHost(ch, hostUid: 'h');
    final arrivals = <JamHubPeer>[];
    hub.arrivals.listen(arrivals.add);
    ch.in_.add(_from('h', _kind('hello')));
    await _pause();
    expect(arrivals, isEmpty);
    ch.in_.add(_from('g1', _kind('hello')));
    await _pause();
    expect(arrivals.single.uid, 'g1');
    arrivals.single.listen((_) {}); // sin oyente, cerrar el par no termina
    await hub.close();
  });
}
