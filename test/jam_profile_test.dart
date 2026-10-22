import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'jam_service_test.dart' show rawJam, waitJam;
import 'jam_sync_test.dart' show eventually, peer;
import 'support/fake_jam_backend.dart';

Uint8List png([int size = 600, int fill = 7]) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  ...List.filled(size - 4, fill),
]);

Uint8List jpeg([int size = 600]) =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(size - 3, 1)]);

void main() {
  test('jamAvatarFromBase64 valida firma, base64 y tamaño', () {
    expect(jamAvatarFromBase64(base64Encode(png())), isNotNull);
    expect(jamAvatarFromBase64(base64Encode(jpeg())), isNotNull);
    expect(
      jamAvatarFromBase64(base64Encode(png(jamMaxAvatarBytes))),
      isNotNull,
    );
    expect(
      jamAvatarFromBase64(base64Encode(png(jamMaxAvatarBytes + 1))),
      isNull,
    );
    expect(jamAvatarFromBase64(base64Encode(Uint8List(600))), isNull);
    expect(jamAvatarFromBase64('esto no es base64 !!!'), isNull);
    expect(jamAvatarFromBase64(42), isNull);
    expect(jamAvatarFromBase64(null), isNull);
  });

  test(
    'el nombre por defecto sale del perfil (crear, unirse y enlace)',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      host.app.profileName = 'Lucía';
      await host.jam.hostOnline(null);
      expect(host.jam.service.me?.name, 'Lucía');
      final code = host.jam.service.invite!.code;

      final g1 = await peer(backend);
      g1.app.profileName = 'Beto';
      await g1.jam.join(code, '');
      final g2 = await peer(backend);
      g2.app.profileName = 'Cris';
      await g2.jam.joinFromLink('aurora://jam/$code', 'Invitado');
      final g3 = await peer(backend);
      await g3.jam.join(code, 'Explícito');
      await eventually(() => host.jam.participants.length == 4);
      expect(host.jam.participants.map((p) => p.name).toSet(), {
        'Lucía',
        'Beto',
        'Cris',
        'Explícito',
      });
    },
  );

  test(
    'un avatar válido llega a anfitrión e invitados, también a los tardíos',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      host.app.profileAvatar = png(800, 1);
      await host.jam.hostOnline('Ana');
      final code = host.jam.service.invite!.code;
      final g1 = await peer(backend);
      g1.app.profileAvatar = jpeg(900);
      await g1.jam.join(code, 'Beto');
      final g1id = g1.jam.service.participantId;

      await eventually(
        () => host.jam.service.avatarOf(g1id) != null,
        'host ve a g1',
      );
      expect(host.jam.service.avatarOf(g1id), orderedEquals(jpeg(900)));
      await eventually(() => g1.jam.avatarOf('host') != null, 'g1 ve al host');
      expect(g1.jam.avatarOf('host'), orderedEquals(png(800, 1)));
      // El propio sale del perfil.
      expect(identical(g1.jam.avatarOf(g1id), g1.app.profileAvatar), isTrue);

      final late = await peer(backend);
      await late.jam.join(code, 'Tarde');
      await eventually(
        () =>
            late.jam.avatarOf('host') != null &&
            late.jam.avatarOf(g1id) != null,
        'el tardío recibe los avatares',
      );
    },
  );

  test('un avatar inválido en LAN se ignora sin romper la sesión', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    final socket = await rawJam(host);
    addTearDown(() => socket.close());
    final welcome = Completer<String>();
    final closed = Completer<void>();
    socket.listen((m) {
      final d = jsonDecode(m as String) as Map<String, dynamic>;
      if (d['kind'] == 'welcome' && !welcome.isCompleted) {
        welcome.complete(d['participantId'] as String);
      }
    }, onDone: closed.complete);
    final id = await welcome.future;
    await waitJam(host, () => host.participants.any((p) => p.id == id));

    for (final bad in [
      'basura que no es base64 !!',
      base64Encode(Uint8List(600)), // firma errónea
      base64Encode(png(jamMaxAvatarBytes + 1)), // demasiado grande
      base64Encode(png(60 * 1024)), // enorme: supera hasta el límite de trama
    ]) {
      socket.add(jsonEncode({'kind': 'avatar', 'data': bad}));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    expect(host.avatarOf(id), isNull);
    expect(closed.isCompleted, isFalse);
    expect(host.participants.firstWhere((p) => p.id == id).connected, isTrue);

    // La sesión sigue viva y un avatar bueno posterior sí se acepta.
    socket.add(jsonEncode({'kind': 'avatar', 'data': base64Encode(png())}));
    await waitJam(host, () => host.avatarOf(id) != null);
    expect(host.avatarOf(id), orderedEquals(png()));
  });

  test(
    'un invitado antiguo no recibe avatares ni se desconecta; el nuevo sí',
    () async {
      final host = JamService(allowLoopback: true);
      addTearDown(host.close);
      await host.host(address: '127.0.0.1', name: 'Host');
      host.setLocalAvatar(png(700, 3));
      final old = await rawJam(host);
      addTearDown(() => old.close());
      final oldFrames = <String>[];
      var oldClosed = false;
      old.listen(
        (m) =>
            oldFrames.add((jsonDecode(m as String) as Map)['kind'] as String),
        onDone: () => oldClosed = true,
      );
      final fresh = JamService(allowLoopback: true)..localAvatar = jpeg(500);
      addTearDown(fresh.close);
      await fresh.join(host.invite!, name: 'Nuevo');
      await waitJam(
        fresh,
        () =>
            fresh.avatarOf('host') != null &&
            host.avatarOf(fresh.participantId) != null,
      );
      expect(fresh.avatarOf('host'), orderedEquals(png(700, 3)));
      // Cambios posteriores: al nuevo le llegan, al antiguo nunca.
      host.setLocalAvatar(png(710, 4));
      await waitJam(fresh, () => fresh.avatarOf('host')!.length == 710);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(oldFrames, isNotEmpty);
      expect(oldFrames, isNot(contains('avatar')));
      expect(oldClosed, isFalse);
      expect(host.avatarOf(fresh.participantId), orderedEquals(jpeg(500)));
    },
  );
}
