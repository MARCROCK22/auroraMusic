import 'dart:convert';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/listenbrainz/listen.dart';
import 'package:aurora_music/listenbrainz/listen_storage.dart';
import 'package:aurora_music/listenbrainz/listenbrainz_client.dart';
import 'package:aurora_music/listenbrainz/scrobbler.dart';
import 'package:flutter_test/flutter_test.dart';

const secret = '11111111-2222-3333-4444-555555555555';

const song = Track(
  id: 'yt:aaaaaaaaaaa',
  title: 'Song One (Official Video)',
  artist: 'Some Band - Topic',
  album: 'The Album',
  duration: Duration(minutes: 3),
  pageUrl: 'https://music.youtube.com/watch?v=aaaaaaaaaaa',
);
const other = Track(
  id: 'yt:bbbbbbbbbbb',
  title: 'Song Two',
  artist: 'Other Artist',
  duration: Duration(minutes: 3),
);

/// Transporte falso: guarda las peticiones y responde con [script].
class FakeNet {
  final requests = <LbRequestData>[];
  final script = <LbResponse>[];
  LbResponse fallback = const LbResponse(200, '{"status":"ok"}');
  Object? throwOnce;

  Future<LbResponse> call(LbRequestData r) async {
    requests.add(r);
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    return script.isEmpty ? fallback : script.removeAt(0);
  }

  List<Map<String, dynamic>> get submits => [
    for (final r in requests)
      if (r.uri.path == '/1/submit-listens')
        jsonDecode(r.body!) as Map<String, dynamic>,
  ];
}

class Rig {
  Rig({String? token = secret}) {
    scrobbler = Scrobbler(
      client: ListenBrainzClient(transport: net.call),
      store: store,
      readToken: () async => token,
      clock: () => now,
      delay: (_) async {},
      scheduleRetry: (d, f) => retries.add(d),
    )..enabled = true;
  }
  final net = FakeNet();
  final store = MemoryListenQueueStore();
  final retries = <Duration>[];
  var now = DateTime.utc(2026, 10, 19, 12);
  late final Scrobbler scrobbler;

  /// Reproduce [seconds] de [track] avanzando reloj y posición a la vez.
  Future<void> play(
    Track track,
    int seconds, {
    int from = 0,
    Duration? duration,
  }) async {
    for (var i = 0; i <= seconds; i++) {
      scrobbler.observe(
        track,
        playing: true,
        position: Duration(seconds: from + i),
        duration: duration ?? track.duration,
      );
      now = now.add(const Duration(seconds: 1));
    }
    await pumpEventQueue();
  }
}

void main() {
  group('umbral', () {
    test('min(50 %, 4 min) con mínimo 30 s', () {
      expect(
        scrobbleThreshold(const Duration(minutes: 3)),
        const Duration(seconds: 90),
      );
      expect(
        scrobbleThreshold(const Duration(minutes: 20)),
        const Duration(minutes: 4),
      );
      expect(
        scrobbleThreshold(const Duration(seconds: 40)),
        const Duration(seconds: 30),
      );
      expect(scrobbleThreshold(const Duration(seconds: 29)), isNull);
      expect(scrobbleThreshold(Duration.zero), const Duration(minutes: 4));
    });

    test('no cuenta antes del umbral y cuenta justo al llegar', () async {
      final rig = Rig();
      await rig.play(song, 80);
      expect(
        rig.net.submits.where((s) => s['listen_type'] != 'playing_now'),
        isEmpty,
      );
      await rig.play(song, 15, from: 81);
      final single = rig.net.submits.where((s) => s['listen_type'] == 'single');
      expect(single, hasLength(1));
    });

    test('saltar hacia delante no suma tiempo', () async {
      final rig = Rig();
      await rig.play(song, 5);
      // salto a mitad de pista: el tiempo escuchado no crece de golpe
      rig.scrobbler.observe(
        song,
        playing: true,
        position: const Duration(seconds: 170),
        duration: song.duration,
      );
      await pumpEventQueue();
      expect(
        rig.net.submits.where((s) => s['listen_type'] == 'single'),
        isEmpty,
      );
    });

    test('en pausa no suma y pistas de menos de 30 s no cuentan', () async {
      final rig = Rig();
      for (var i = 0; i < 200; i++) {
        rig.scrobbler.observe(
          song,
          playing: false,
          position: const Duration(seconds: 10),
          duration: song.duration,
        );
        rig.now = rig.now.add(const Duration(seconds: 1));
      }
      const short = Track(
        id: 'x',
        title: 'Corta',
        artist: 'Alguien',
        duration: Duration(seconds: 25),
      );
      await rig.play(short, 25);
      await pumpEventQueue();
      expect(
        rig.net.submits.where((s) => s['listen_type'] == 'single'),
        isEmpty,
      );
    });

    test('desactivado no envía nada', () async {
      final rig = Rig()..scrobbler.enabled = false;
      await rig.play(song, 120);
      expect(rig.net.requests, isEmpty);
    });

    test('sin artista o título fiable no se envía', () async {
      final rig = Rig();
      const unknown = Track(
        id: 'u',
        title: 'Algo',
        artist: 'Artista desconocido',
        duration: Duration(minutes: 1),
      );
      const noTitle = Track(
        id: 'n',
        title: '  ',
        artist: 'Alguien',
        duration: Duration(minutes: 1),
      );
      await rig.play(unknown, 40);
      await rig.play(noTitle, 40);
      expect(
        rig.net.submits.where((s) => s['listen_type'] == 'single'),
        isEmpty,
      );
    });
  });

  group('deduplicación', () {
    test('una sesión se cuenta una sola vez aunque siga sonando', () async {
      final rig = Rig();
      await rig.play(song, 170);
      expect(
        rig.net.submits.where((s) => s['listen_type'] == 'single'),
        hasLength(1),
      );
      expect(rig.scrobbler.pending, 0);
    });

    test('repetir la pista otra vez cuenta otra escucha', () async {
      final rig = Rig();
      await rig.play(song, 100);
      await rig.play(song, 100); // posición vuelve a 0: nueva sesión
      expect(
        rig.net.submits.where((s) => s['listen_type'] == 'single'),
        hasLength(2),
      );
    });

    test('misma pista e inicio casi igual no se encola dos veces', () async {
      final rig = Rig();
      rig.net.fallback = const LbResponse(500, '');
      await rig.play(song, 100);
      expect(rig.scrobbler.pending, 1);
      // otra sesión de la misma pista con el mismo inicio (recuperación de stream)
      rig.now = rig.now.subtract(const Duration(seconds: 101));
      rig.scrobbler.observe(
        other,
        playing: true,
        position: Duration.zero,
        duration: other.duration,
      );
      await rig.play(song, 100);
      expect(rig.scrobbler.pending, 1);
    });
  });

  group('payload', () {
    test('single: campos exigidos y listened_at = inicio, sin token', () async {
      final rig = Rig();
      final start = rig.now;
      await rig.play(song, 100);
      final single = rig.net.submits.firstWhere(
        (s) => s['listen_type'] == 'single',
      );
      final listen = (single['payload'] as List).single as Map<String, dynamic>;
      final meta = listen['track_metadata'] as Map<String, dynamic>;
      expect(listen['listened_at'], start.millisecondsSinceEpoch ~/ 1000);
      expect(meta['artist_name'], 'Some Band');
      expect(meta['track_name'], 'Song One');
      expect(meta['release_name'], 'The Album');
      final info = meta['additional_info'] as Map<String, dynamic>;
      expect(info['submission_client'], 'Aurora');
      expect(info['music_service'], 'youtube.com');
      expect(info['origin_url'], song.pageUrl);
      expect(info['duration_ms'], 180000);
      expect(info['submission_client_version'], kListenBrainzClientVersion);
    });

    test('playing_now sin listened_at y una sola vez por pista', () async {
      final rig = Rig();
      await rig.play(song, 20);
      final nows = rig.net.submits
          .where((s) => s['listen_type'] == 'playing_now')
          .toList();
      expect(nows, hasLength(1));
      expect(
        ((nows.single['payload'] as List).single as Map).containsKey(
          'listened_at',
        ),
        isFalse,
      );
    });

    test('el token solo va en la cabecera, nunca en URL ni cuerpo', () async {
      final rig = Rig();
      await rig.play(song, 100);
      expect(rig.net.requests, isNotEmpty);
      for (final r in rig.net.requests) {
        expect(r.uri.scheme, 'https');
        expect(r.uri.toString(), isNot(contains(secret)));
        expect(r.body ?? '', isNot(contains(secret)));
        expect(r.headers['Authorization'], 'Token $secret');
        expect(r.headers['User-Agent'], startsWith('Aurora/'));
      }
      expect(
        rig.store.saved.map((l) => jsonEncode(l.toJson())).join(),
        isNot(contains(secret)),
      );
    });

    test('un listen de más de 10 240 B se descarta', () {
      final huge = Track(
        id: 'h',
        title: 'T',
        artist: 'A',
        album: 'x' * 11000,
        duration: const Duration(minutes: 3),
      );
      expect(buildListen(huge, DateTime.utc(2026)), isNull);
    });

    test('el cliente rechaza una base que no sea HTTPS', () {
      expect(
        () =>
            ListenBrainzClient(base: Uri.parse('http://api.listenbrainz.org')),
        throwsArgumentError,
      );
    });
  });

  group('normalización', () {
    test('limpia ruido de YouTube y valida con la normalización del DJ', () {
      expect(listenTitle('Canción [Official Audio]'), 'Canción');
      expect(listenTitle('Song (Lyrics) (HD)'), 'Song');
      expect(listenTitle('Song (Remastered 2011)'), 'Song (Remastered 2011)');
      expect(listenTitle('(Official Video)'), isNull);
      expect(listenTitle('???'), isNull);
      expect(listenArtist('Band - Topic'), 'Band');
      expect(listenArtist('Unknown Artist'), isNull);
      expect(listenArtist('  '), isNull);
    });
  });

  group('cola, reintentos y 429', () {
    test(
      'sin red: se encola, se persiste y se reintenta con espera creciente',
      () async {
        final rig = Rig();
        rig.net.fallback = const LbResponse(503, '');
        await rig.play(song, 100);
        expect(rig.scrobbler.pending, 1);
        expect(rig.store.saved, hasLength(1));
        expect(rig.retries.single, const Duration(seconds: 30));
        await rig.scrobbler.flush();
        expect(rig.retries.last, const Duration(seconds: 60));
      },
    );

    test('al volver la red se envía todo en un import', () async {
      final rig = Rig();
      rig.net.fallback = const LbResponse(503, '');
      await rig.play(song, 100);
      await rig.play(other, 100);
      expect(rig.scrobbler.pending, 2);
      rig.net.fallback = const LbResponse(200, '{}');
      await rig.scrobbler.flush();
      final imports = rig.net.submits
          .where(
            (s) =>
                s['listen_type'] == 'import' &&
                (s['payload'] as List).length == 2,
          )
          .toList();
      expect(imports, isNotEmpty);
      expect(rig.scrobbler.pending, 0);
      expect(rig.store.saved, isEmpty);
    });

    test('un error de conexión no pierde el listen', () async {
      final rig = Rig();
      await rig.play(song, 20); // playing_now ya enviado
      rig.net.throwOnce = const SocketLikeError();
      await rig.play(song, 100, from: 21);
      expect(rig.scrobbler.pending, 1);
    });

    test('429 respeta X-RateLimit-Reset-In y no reenvía antes', () async {
      final rig = Rig();
      rig.net.script.addAll([
        const LbResponse(200, '{}'), // playing_now
        const LbResponse(429, '{}', {'x-ratelimit-reset-in': '42'}),
      ]);
      await rig.play(song, 100);
      expect(rig.scrobbler.pending, 1);
      expect(rig.retries.last, const Duration(seconds: 43));
      final before = rig.net.requests.length;
      await rig.scrobbler.flush(); // aún bloqueado
      expect(rig.net.requests.length, before);
      rig.now = rig.now.add(const Duration(seconds: 45));
      await rig.scrobbler.flush();
      expect(rig.net.requests.length, before + 1);
      expect(rig.scrobbler.pending, 0);
    });

    test('401 detiene el envío y conserva la cola', () async {
      final rig = Rig();
      rig.net.script.addAll([
        const LbResponse(200, '{}'),
        const LbResponse(401, '{}'),
      ]);
      await rig.play(song, 100);
      expect(rig.scrobbler.authFailed, isTrue);
      expect(rig.scrobbler.pending, 1);
      final before = rig.net.requests.length;
      await rig.scrobbler.flush();
      expect(rig.net.requests.length, before);
    });

    test('lote rechazado (400) se parte; el listen malo se descarta', () async {
      final rig = Rig();
      rig.net.fallback = const LbResponse(503, '');
      await rig.play(song, 100);
      await rig.play(other, 100);
      rig.net.script.addAll([
        const LbResponse(400, '{}'), // import
        const LbResponse(400, '{}'), // single #1 (malo)
        const LbResponse(200, '{}'), // single #2
      ]);
      rig.net.fallback = const LbResponse(200, '{}');
      await rig.scrobbler.flush();
      expect(rig.scrobbler.pending, 0);
    });

    test('la cola está acotada', () async {
      final store = MemoryListenQueueStore();
      final net = FakeNet()..fallback = const LbResponse(503, '');
      var now = DateTime.utc(2026);
      final s = Scrobbler(
        client: ListenBrainzClient(transport: net.call),
        store: store,
        readToken: () async => secret,
        clock: () => now,
        scheduleRetry: (_, _) {},
        maxQueue: 3,
      )..enabled = true;
      for (var i = 0; i < 6; i++) {
        final t = Track(
          id: 't$i',
          title: 'Tema $i',
          artist: 'Artista $i',
          duration: const Duration(minutes: 1),
        );
        for (var k = 0; k <= 40; k++) {
          s.observe(
            t,
            playing: true,
            position: Duration(seconds: k),
            duration: t.duration,
          );
          now = now.add(const Duration(seconds: 1));
        }
        await pumpEventQueue();
      }
      expect(s.pending, 3);
      expect(store.saved.first.title, 'Tema 3');
    });
  });

  group('token fuera de logs y errores', () {
    test('redactToken quita el token y cualquier UUID', () {
      expect(
        redactToken('fallo con $secret en medio', secret),
        isNot(contains(secret)),
      );
      expect(
        redactToken('x 99999999-aaaa-bbbb-cccc-111111111111 y'),
        contains('[token]'),
      );
    });

    test('las excepciones del cliente no contienen el token', () async {
      final client = ListenBrainzClient(
        transport: (r) async =>
            throw Exception('boom ${r.headers['Authorization']}'),
      );
      try {
        await client.validateToken(secret);
        fail('debía lanzar');
      } on ListenBrainzException catch (e) {
        expect(e.message, isNot(contains(secret)));
        expect(e.toString(), isNot(contains(secret)));
      }
    });

    test('validateToken: usuario si es válido, null si no', () async {
      final net = FakeNet()
        ..script.addAll([
          const LbResponse(200, '{"valid":true,"user_name":"ana"}'),
          const LbResponse(200, '{"valid":false}'),
          const LbResponse(401, '{}'),
        ]);
      final client = ListenBrainzClient(transport: net.call);
      expect(await client.validateToken(secret), 'ana');
      expect(await client.validateToken(secret), isNull);
      expect(await client.validateToken(secret), isNull);
      expect(net.requests.first.uri.path, '/1/validate-token');
      expect(net.requests.first.uri.query, isEmpty);
    });

    test('freshReleases se lee de forma tolerante', () async {
      final net = FakeNet()
        ..script.add(
          const LbResponse(
            200,
            '{"payload":{"releases":[{"artist_credit_name":"A","release_name":"R","release_date":"2026-10-01"},{"x":1}]}}',
          ),
        );
      final list = await ListenBrainzClient(
        transport: net.call,
      ).freshReleases('ana');
      expect(list.single.title, 'R');
      expect(net.requests.single.uri.path, '/1/user/ana/fresh_releases');
    });
  });
}

class SocketLikeError implements Exception {
  const SocketLikeError();
}
