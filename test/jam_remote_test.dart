import 'dart:async';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/jam/jam_suggestions.dart';
import 'package:aurora_music/jam/transport/jam_config.dart';
import 'package:aurora_music/jam/transport/jam_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_jam_backend.dart';

JamTrack song(int n) {
  final id = 'abcdefghi${(n ~/ 10) % 10}${n % 10}'.padRight(11, 'x');
  return JamTrack.fromTrack(
    Track(
      id: 'yt:$id',
      title: 'Song $n',
      artist: 'Artist',
      pageUrl: 'https://www.youtube.com/watch?v=$id',
    ),
  );
}

Future<void> until(JamService s, bool Function() ok, {int seconds = 5}) async {
  if (ok()) return;
  final done = Completer<void>();
  void check() {
    if (ok() && !done.isCompleted) done.complete();
  }

  s.addListener(check);
  try {
    await done.future.timeout(Duration(seconds: seconds));
  } on TimeoutException {
    throw TestFailure(
      'until timeout ${StackTrace.current.toString().split(String.fromCharCode(10)).take(4).join(' | ')}',
    );
  } finally {
    s.removeListener(check);
  }
}

class Room {
  Room(this.backend, this.hostT, this.host);
  final FakeJamBackend backend;
  final FakeJamTransport hostT;
  final JamService host;
  String get code => host.invite!.code;
}

Future<Room> newRoom() async {
  final backend = FakeJamBackend();
  final t = backend.transport();
  final host = JamService();
  addTearDown(host.close);
  await host.hostRemote(t, name: 'Ana');
  return Room(backend, t, host);
}

Future<(JamService, FakeJamTransport)> guest(
  Room room,
  String name, {
  DateTime Function()? clock,
}) async {
  final t = room.backend.transport();
  final s = JamService(clock: clock);
  addTearDown(s.close);
  await s.joinRemote(t, room.code, name: name);
  return (s, t);
}

void main() {
  test('host y dos invitados comparten cola con autor y roles', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    final (g2, _) = await guest(room, 'Cris');
    await until(room.host, () => room.host.participants.length == 3);
    g1.addTrack(song(1));
    g2.addTrack(song(2));
    room.host.addTrack(song(3));
    await until(g2, () => g2.queue.length == 3);
    final authors = g2.queue.map((e) => g2.participantName(e.addedBy)).toList();
    expect(authors.toSet(), {'Beto', 'Cris', 'Ana'});
    expect(g1.me?.role, JamRole.guest);
    expect(g1.participants.firstWhere((p) => p.isHost).name, 'Ana');
    // Un duplicado no entra dos veces.
    g1.addTrack(song(2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(room.host.queue.length, 3);
  });

  test('invitado sin permiso no reordena; coanfitrión sí', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    await until(room.host, () => room.host.participants.length == 2);
    room.host.addTrack(song(1));
    room.host.addTrack(song(2));
    await until(g1, () => g1.queue.length == 2);
    g1.reorder(g1.queue.last.id, 0);
    await until(g1, () => g1.error != null);
    expect(room.host.queue.first.track.title, 'Song 1');
    await room.host.setCoHost(g1.participantId, true);
    await until(g1, () => g1.me?.role == JamRole.coHost);
    g1.error = null;
    g1.reorder(g1.queue.last.id, 0);
    await until(room.host, () => room.host.queue.first.track.title == 'Song 2');
  });

  test('límites: por invitado, silencio y aprobación', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    await until(room.host, () => room.host.participants.length == 2);
    await room.host.setRules(const JamRules(maxPerGuest: 2));
    for (var i = 0; i < 3; i++) {
      g1.addTrack(song(i));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    await until(g1, () => g1.error != null);
    expect(room.host.queue.length, 2);
    await room.host.setMuted(g1.participantId, true);
    await until(g1, () => g1.me?.muted == true);
    g1.error = null;
    g1.addTrack(song(9));
    await until(g1, () => g1.error != null);
    expect(room.host.queue.length, 2);
    await room.host.setMuted(g1.participantId, false);
    await room.host.setRules(const JamRules(approve: true, maxPerGuest: 5));
    await until(g1, () => g1.rules.approve);
    g1.addTrack(song(10));
    await until(room.host, () => room.host.queue.length == 3);
    final pending = room.host.queue.last;
    expect(pending.status, JamEntryStatus.pending);
    room.host.approve(pending.id, accept: true);
    await until(g1, () => g1.queue.last.status == JamEntryStatus.queued);
  });

  test('votos reordenan las sugeridas y el voto es único', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    final (g2, _) = await guest(room, 'Cris');
    await until(room.host, () => room.host.participants.length == 3);
    room.host.addTrack(song(1));
    room.host.addSuggested(song(2));
    room.host.addSuggested(song(3));
    await until(g1, () => g1.queue.length == 3);
    final third = g1.queue.last.id;
    g1.vote(third, 1);
    g1.vote(third, 1);
    g2.vote(third, 1);
    await until(
      room.host,
      () => room.host.queue[1].id == third && room.host.queue[1].up.length == 2,
    );
    expect(room.host.queue.first.track.title, 'Song 1');
  });

  test(
    'expulsar con bloqueo impide reingresar; código rotado invalida el viejo',
    () async {
      final room = await newRoom();
      final (g1, t1) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      final oldCode = room.code;
      await room.host.kick(g1.participantId, ban: true);
      await until(g1, () => g1.connection == JamConnection.closed);
      expect(g1.error, contains('expulsaron'));
      final again = JamService();
      addTearDown(again.close);
      await expectLater(
        again.joinRemote(t1, oldCode, name: 'Beto'),
        throwsA(isA<JamException>()),
      );
      expect(again.error, jamRemoteMessage('banned'));
      await room.host.rotateCode();
      final late = JamService();
      addTearDown(late.close);
      await expectLater(
        late.joinRemote(room.backend.transport(), oldCode, name: 'X'),
        throwsA(isA<JamException>()),
      );
      expect(late.error, jamRemoteMessage('invalid'));
    },
  );

  test(
    'corte de red: el invitado reconecta con backoff y recupera estado',
    () async {
      final room = await newRoom();
      final (g1, t1) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      t1.cut(true);
      await until(g1, () => g1.connection == JamConnection.disconnected);
      room.host.addTrack(song(1));
      t1.cut(false);
      await until(
        g1,
        () => g1.connection == JamConnection.connected && g1.queue.length == 1,
        seconds: 10,
      );
      expect(g1.error, isNull);
    },
  );

  test(
    'deriva de reloj: el invitado estima el desfase con el anfitrión',
    () async {
      final room = await newRoom();
      final (g1, _) = await guest(
        room,
        'Beto',
        clock: () => DateTime.now().add(const Duration(seconds: 5)),
      );
      await until(g1, () => g1.roundTripMs != null);
      expect(g1.clockOffsetMs, closeTo(-5000, 400));
    },
  );

  test('cierre del anfitrión cierra a todos con mensaje claro', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    await until(room.host, () => room.host.participants.length == 2);
    await room.host.close();
    await until(g1, () => g1.connection == JamConnection.closed);
    expect(g1.error, contains('cerró'));
  });

  test('transferir anfitrión mantiene cola y autores', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    await until(room.host, () => room.host.participants.length == 2);
    room.host.addTrack(song(1));
    await until(g1, () => g1.queue.length == 1);
    final target = g1.participantId;
    await room.host.transferHost(target);
    await until(g1, () => g1.isHost, seconds: 8);
    await until(
      room.host,
      () =>
          room.host.connection == JamConnection.connected &&
          room.host.me?.role == JamRole.coHost,
      seconds: 8,
    );
    expect(g1.queue.length, 1);
    expect(g1.participantName(g1.queue.first.addedBy), 'Ana');
    g1.addTrack(song(2));
    await until(room.host, () => room.host.queue.length == 2);
  });

  test('ráfaga de mensajes: el anfitrión descarta el exceso', () async {
    final room = await newRoom();
    final (g1, _) = await guest(room, 'Beto');
    await until(room.host, () => room.host.participants.length == 2);
    for (var i = 0; i < 60; i++) {
      g1.addTrack(song(i));
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(room.host.queue.length, lessThanOrEqualTo(10));
  });

  group('sugerencias por participante', () {
    Track tr(String id, String artist) => Track(
      id: 'yt:$id',
      title: 'T $id',
      artist: artist,
      pageUrl: 'https://music.youtube.com/watch?v=$id',
    );
    // Cada dispositivo ordena con su propio perfil (aquí: su lista de gustos).
    Future<List<JamSuggestion>> mine(List<Track> likes) => JamSuggestionAdapter(
      related: (_) async => likes,
      seeds: () => likes,
      local: () => const [],
    ).build();

    test(
      'tres gustos distintos, intercalado justo y sin fuga de perfil',
      () async {
        final room = await newRoom();
        final (g1, _) = await guest(room, 'Beto');
        final (g2, _) = await guest(room, 'Cris');
        await until(room.host, () => room.host.participants.length == 3);
        final a = await mine([
          tr('aaaaaaaaaa1', 'Rock A'),
          tr('aaaaaaaaaa2', 'Rock B'),
        ]);
        final b = await mine([
          tr('bbbbbbbbbb1', 'Jazz A'),
          tr('bbbbbbbbbb2', 'Jazz B'),
        ]);
        final c = await mine([
          tr('cccccccccc1', 'Pop A'),
          tr('cccccccccc2', 'Pop B'),
        ]);
        expect(a.map((s) => s.track.key), isNot(b.map((s) => s.track.key)));
        room.host.publishSuggestions(a);
        g1.publishSuggestions(b);
        g2.publishSuggestions(c);
        await until(room.host, () => room.host.queue.length == 6);
        final authors = room.host.queue
            .map((e) => room.host.participantName(e.addedBy))
            .toList();
        expect(authors, ['Ana', 'Beto', 'Cris', 'Ana', 'Beto', 'Cris']);
        expect(
          room.host.queue.every((e) => e.status == JamEntryStatus.suggested),
          isTrue,
        );
        // Solo viajan pistas y razón: ninguna clave de perfil/historial.
        final wire = a.map((s) => s.toJson()).toString();
        for (final forbidden in ['profile', 'favorite', 'history', 'vector']) {
          expect(wire.toLowerCase().contains(forbidden), isFalse);
        }
        expect(a.first.toJson().keys, {'track', 'reason'});
      },
    );

    test('limite de ritmo: segunda publicación en 60 s se rechaza', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      g1.publishSuggestions(await mine([tr('bbbbbbbbbb1', 'Jazz A')]));
      await until(room.host, () => room.host.queue.length == 1);
      g1.error = null;
      g1.publishSuggestions(await mine([tr('bbbbbbbbbb2', 'Jazz B')]));
      await until(g1, () => g1.error != null);
      expect(room.host.queue.length, 1);
    });

    test(
      'sin red de YouTube cae a lo local y rechaza datos inválidos',
      () async {
        final local = [
          tr('dddddddddd1', 'Local'),
          tr('dddddddddd2', 'Local 2'),
        ];
        final out = await JamSuggestionAdapter(
          related: (_) async => throw Exception('sin red'),
          seeds: () => local,
          local: () => local,
        ).build();
        expect(out.length, 2);
        expect(out.first.reason, 'De tu biblioteca');
        expect(
          () => JamSuggestion.fromJson({
            'track': song(1).toJson()..['youtubeId'] = "x'; DROP--",
            'reason': 'r',
          }),
          throwsA(isA<JamException>()),
        );
      },
    );

    test('mismo artista no se repite seguido y se deduplica', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      room.host.publishSuggestions(
        await mine([
          tr('aaaaaaaaaa1', 'Mismo'),
          tr('aaaaaaaaaa2', 'Mismo'),
          tr('aaaaaaaaaa3', 'Otro'),
        ]),
      );
      g1.publishSuggestions(
        await mine([tr('aaaaaaaaaa1', 'Mismo'), tr('bbbbbbbbbb1', 'Mismo')]),
      );
      await until(room.host, () => room.host.queue.length == 4);
      final artists = room.host.queue.map((e) => e.track.artist).toList();
      for (var i = 1; i < artists.length; i++) {
        if (artists[i] == artists[i - 1]) {
          // solo se permite cuando no queda alternativa
          expect(artists.where((x) => x != artists[i]).length, lessThan(2));
        }
      }
      expect(room.host.queue.map((e) => e.track.key).toSet().length, 4);
    });
  });

  group('entradas hostiles', () {
    final hostile = [
      "'; DROP TABLE jam_rooms;--",
      '%',
      '_%_',
      'a\u0000b',
      '\u202eevil',
      '😀' * 500,
      '" OR 1=1 --',
      '\n\r\t',
    ];
    test('códigos', () {
      for (final h in hostile) {
        expect(jamNormalizeCode(h), isNull, reason: h);
        expect(jamRemoteCodeFrom(h), isNull, reason: h);
      }
      expect(jamNormalizeCode('abcd23'), 'ABCD23');
      expect(jamNormalizeCode('ABCD0I'), isNull);
      expect(jamRemoteCodeFrom('aurora://jam/abcd23'), 'ABCD23');
      // 8 caracteres (nuevo) y 6 (salas antiguas); cualquier otra longitud no.
      expect(jamNormalizeCode('abcd2345'), 'ABCD2345');
      expect(jamNormalizeCode('abcd-2345'), 'ABCD2345');
      expect(jamRemoteCodeFrom('aurora://jam/ABCD2345'), 'ABCD2345');
      expect(jamNormalizeCode('ABCD234'), isNull);
      expect(jamNormalizeCode('ABCD23456'), isNull);
      expect(jamNormalizeCode('ABCD23I5'), isNull);
      expect(jamNormalizeCode('ABCD'), isNull);
      expect(jamRemoteCodeFrom('aurora://jam/abcd23/extra'), isNull);
      expect(jamRemoteCodeFrom('aurora://evil/ABCD23'), isNull);
      expect(jamRemoteCodeFrom('https://jam/ABCD23'), isNull);
    });
    test('nombres', () {
      for (final h in hostile) {
        final clean = jamCleanName(h);
        expect(clean.length, lessThanOrEqualTo(32));
        expect(RegExp(r'[\x00-\x1f\u202a-\u202e]').hasMatch(clean), isFalse);
      }
      expect(jamCleanName('\u0000'), 'Invitado');
    });
    test('ids de vídeo y metadatos', () {
      for (final h in hostile) {
        expect(
          () => JamTrack.fromJson({
            'key': 'yt_abcdefghijk',
            'title': 't',
            'artist': 'a',
            'durationMs': 1,
            'youtubeId': h,
            'spotifyUri': null,
            'artworkUrl': null,
            'localOnly': false,
          }),
          throwsA(isA<JamException>()),
          reason: h,
        );
      }
    });
    test('sobres Realtime inválidos se descartan', () {
      expect(JamEnvelope.tryParse({'f': "x'; --", 't': '*', 'm': 'a'}), isNull);
      expect(JamEnvelope.tryParse({'f': 'u1', 't': 'u2%', 'm': 'a'}), isNull);
      expect(
        JamEnvelope.tryParse({'f': 'u1', 't': '*', 'm': 'a' * 300000}),
        isNull,
      );
      expect(JamEnvelope.tryParse('texto'), isNull);
      expect(JamEnvelope.tryParse({'f': 'u1', 't': '*', 'm': 'ok'}), isNotNull);
    });
  });

  group('configuración', () {
    test('sin credenciales el modo remoto se desactiva con mensaje', () {
      expect(JamSupabaseConfig.tryParse('', ''), isNull);
      expect(
        JamSupabaseConfig.validate('', ''),
        contains('AURORA_SUPABASE_URL'),
      );
    });
    test('rechaza http, clave secreta y service_role', () {
      expect(
        JamSupabaseConfig.validate('http://x.supabase.co', 'sb_publishable_x'),
        isNotNull,
      );
      expect(
        JamSupabaseConfig.validate('https://x.supabase.co', 'sb_secret_x'),
        isNotNull,
      );
      // Coma pegada al copiar la URL: el host no resuelve.
      expect(
        JamSupabaseConfig.validate(
          'https://x.supabase.co,',
          'sb_publishable_x',
        ),
        isNotNull,
      );
      expect(
        JamSupabaseConfig.validate(
          'https://x.supabase.co',
          'sb_publishable_abc',
        ),
        isNull,
      );
      // JWT con role=service_role (no es una clave real).
      const payload = 'eyJyb2xlIjoic2VydmljZV9yb2xlIn0';
      expect(
        JamSupabaseConfig.validate('https://x.supabase.co', 'aaa.$payload.ccc'),
        isNotNull,
      );
      const anon = 'eyJyb2xlIjoiYW5vbiJ9';
      expect(
        JamSupabaseConfig.validate('https://x.supabase.co', 'aaa.$anon.ccc'),
        isNull,
      );
    });
  });
}
