import 'dart:convert';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lastfm/lastfm_client.dart';
import 'package:aurora_music/lastfm/lastfm_storage.dart';
import 'package:aurora_music/lastfm/listen.dart';
import 'package:aurora_music/lastfm/scrobbler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const sk = 'sessionkey1234567890abcdef';
const password = 'hunter2-contraseña';

const song = Track(
  id: 'yt:aaaaaaaaaaa',
  title: 'Song One (Official Video)',
  artist: 'Some Band - Topic',
  album: 'The Album',
  duration: Duration(minutes: 3),
);
const other = Track(
  id: 'yt:bbbbbbbbbbb',
  title: 'Song Two',
  artist: 'Other Artist',
  duration: Duration(minutes: 3),
);

/// Transporte falso: guarda las peticiones y responde con [script].
class FakeNet {
  final requests = <LfmRequest>[];
  final script = <LfmResponse>[];
  LfmResponse fallback = const LfmResponse(200, '{"scrobbles":{}}');
  Object? throwOnce;

  Future<LfmResponse> call(LfmRequest r) async {
    requests.add(r);
    if (throwOnce != null) {
      final e = throwOnce!;
      throwOnce = null;
      throw e;
    }
    return script.isEmpty ? fallback : script.removeAt(0);
  }

  Map<String, String> form(LfmRequest r) =>
      Uri.splitQueryString(r.body ?? r.uri.query);

  List<Map<String, String>> method(String name) => [
    for (final r in requests)
      if (form(r)['method'] == name) form(r),
  ];
}

LastfmClient clientOf(FakeNet net) =>
    LastfmClient(transport: net.call, apiKey: 'key', secret: 'sec');

class Rig {
  Rig() {
    scrobbler = Scrobbler(
      client: clientOf(net),
      store: store,
      readSession: () async => sk,
      clock: () => now,
      delay: (_) async {},
      scheduleRetry: (d, f) => retries.add(d),
    )..enabled = true;
  }
  final net = FakeNet();
  final store = MemoryListenQueueStore();
  final retries = <Duration>[];
  var now = DateTime.utc(2026, 10, 24, 12);
  late final Scrobbler scrobbler;

  Future<void> play(Track track, int seconds, {int from = 0}) async {
    for (var i = 0; i <= seconds; i++) {
      scrobbler.observe(
        track,
        playing: true,
        position: Duration(seconds: from + i),
        duration: track.duration,
      );
      now = now.add(const Duration(seconds: 1));
    }
    await pumpEventQueue();
  }
}

void main() {
  group('firma', () {
    test('md5 de parámetros ordenados + secreto, sin format ni callback', () {
      final sig = lastfmSignature({
        'method': 'auth.getMobileSession',
        'api_key': 'key',
        'username': 'ana',
        'format': 'json',
        'callback': 'x',
      }, 'sec');
      final expected = md5
          .convert(
            utf8.encode('api_keykeymethodauth.getMobileSessionusernameanasec'),
          )
          .toString();
      expect(sig, expected);
    });

    test('los envíos van firmados por POST HTTPS y sin contraseña', () async {
      final net = FakeNet()
        ..script.add(
          const LfmResponse(200, '{"session":{"name":"Ana","key":"$sk"}}'),
        );
      final s = await clientOf(net).getMobileSession('ana', password);
      expect(s.name, 'Ana');
      expect(s.key, sk);
      final r = net.requests.single;
      expect(r.method, 'POST');
      expect(r.uri.scheme, 'https');
      expect(r.uri.toString(), isNot(contains(password)));
      final f = net.form(r);
      expect(f['password'], password); // solo en el cuerpo de este POST
      expect(f['format'], 'json');
      final signed = {...f}
        ..remove('api_sig')
        ..remove('format');
      expect(f['api_sig'], lastfmSignature(signed, 'sec'));
    });

    test('rechaza una base que no sea HTTPS', () {
      expect(
        () =>
            LastfmClient(base: Uri.parse('http://ws.audioscrobbler.com/2.0/')),
        throwsArgumentError,
      );
    });

    test('sin claves la función queda desactivada', () async {
      final c = LastfmClient(apiKey: '', secret: '');
      expect(c.configured, isFalse);
      expect(
        () => c.getMobileSession('a', 'b'),
        throwsA(isA<LastfmException>()),
      );
    });
  });

  group('errores', () {
    test('código 9 es sesión inválida; 29 límite; 11 y 16 reintento', () async {
      Future<LfmSubmitStatus> status(String body, [int http = 200]) async {
        final net = FakeNet()..fallback = LfmResponse(http, body);
        final r = await clientOf(
          net,
        ).scrobble(sk, [const Listen(artist: 'A', title: 'T', listenedAt: 1)]);
        return r.status;
      }

      expect(
        await status('{"error":9,"message":"Invalid session key"}', 403),
        LfmSubmitStatus.unauthorized,
      );
      expect(
        await status('{"error":29,"message":"Rate limit"}', 429),
        LfmSubmitStatus.rateLimited,
      );
      expect(
        await status('{"error":11,"message":"x"}', 500),
        LfmSubmitStatus.retry,
      );
      expect(
        await status('{"error":16,"message":"x"}', 500),
        LfmSubmitStatus.retry,
      );
      expect(await status('', 503), LfmSubmitStatus.retry);
      expect(
        await status('{"error":6,"message":"x"}', 400),
        LfmSubmitStatus.rejected,
      );
    });

    test('las excepciones no contienen contraseña ni sesión', () async {
      final client = LastfmClient(
        apiKey: 'key',
        secret: 'sec',
        transport: (r) async => throw Exception('boom ${r.body}'),
      );
      try {
        await client.getMobileSession('ana', password);
        fail('debía lanzar');
      } on LastfmException catch (e) {
        expect(e.message, isNot(contains(password)));
      }
      final r = await LastfmClient(
        apiKey: 'key',
        secret: 'sec',
        transport: (r) async => throw Exception('boom ${r.body}'),
      ).scrobble(sk, [const Listen(artist: 'A', title: 'T', listenedAt: 1)]);
      expect(r.detail, isNot(contains(sk)));
    });
  });

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
      expect(rig.net.method('track.scrobble'), isEmpty);
      await rig.play(song, 15, from: 81);
      expect(rig.net.method('track.scrobble'), hasLength(1));
    });

    test('saltar hacia delante no suma tiempo', () async {
      final rig = Rig();
      await rig.play(song, 5);
      rig.scrobbler.observe(
        song,
        playing: true,
        position: const Duration(seconds: 170),
        duration: song.duration,
      );
      await pumpEventQueue();
      expect(rig.net.method('track.scrobble'), isEmpty);
    });

    test('desactivado no envía nada y pistas cortas no cuentan', () async {
      final rig = Rig()..scrobbler.enabled = false;
      await rig.play(song, 120);
      expect(rig.net.requests, isEmpty);
      rig.scrobbler.enabled = true;
      const short = Track(
        id: 'x',
        title: 'Corta',
        artist: 'Alguien',
        duration: Duration(seconds: 25),
      );
      await rig.play(short, 25);
      expect(rig.net.method('track.scrobble'), isEmpty);
    });
  });

  group('deduplicación y parámetros', () {
    test('una sesión se cuenta una vez; repetir cuenta otra', () async {
      final rig = Rig();
      await rig.play(song, 170);
      expect(rig.net.method('track.scrobble'), hasLength(1));
      await rig.play(song, 100);
      expect(rig.net.method('track.scrobble'), hasLength(2));
    });

    test(
      'scrobble: campos, marca de tiempo y sesión, sin contraseña',
      () async {
        final rig = Rig();
        final start = rig.now;
        await rig.play(song, 100);
        final f = rig.net.method('track.scrobble').single;
        expect(f['artist[0]'], 'Some Band');
        expect(f['track[0]'], 'Song One');
        expect(f['album[0]'], 'The Album');
        expect(f['duration[0]'], '180');
        expect(f['timestamp[0]'], '${start.millisecondsSinceEpoch ~/ 1000}');
        expect(f['sk'], sk);
        expect(f.containsKey('password'), isFalse);
        expect(
          rig.store.saved.map((l) => jsonEncode(l.toJson())).join(),
          isNot(contains(sk)),
        );
      },
    );

    test('updateNowPlaying sin marca de tiempo y una vez por pista', () async {
      final rig = Rig();
      await rig.play(song, 20);
      final nows = rig.net.method('track.updateNowPlaying');
      expect(nows, hasLength(1));
      expect(nows.single.containsKey('timestamp'), isFalse);
      expect(nows.single['artist'], 'Some Band');
    });

    test('normaliza ruido de YouTube', () {
      expect(listenTitle('Canción [Official Audio]'), 'Canción');
      expect(listenTitle('Song (Remastered 2011)'), 'Song (Remastered 2011)');
      expect(listenTitle('(Official Video)'), isNull);
      expect(listenArtist('Band - Topic'), 'Band');
      expect(listenArtist('Unknown Artist'), isNull);
    });
  });

  group('cola, reintentos y límite', () {
    test(
      'sin red: se encola, persiste y se reintenta con espera creciente',
      () async {
        final rig = Rig();
        rig.net.fallback = const LfmResponse(503, '');
        await rig.play(song, 100);
        expect(rig.scrobbler.pending, 1);
        expect(rig.store.saved, hasLength(1));
        expect(rig.retries.single, const Duration(seconds: 30));
        await rig.scrobbler.flush();
        expect(rig.retries.last, const Duration(seconds: 60));
      },
    );

    test('al volver la red se envía todo en un lote', () async {
      final rig = Rig();
      rig.net.fallback = const LfmResponse(503, '');
      await rig.play(song, 100);
      await rig.play(other, 100);
      expect(rig.scrobbler.pending, 2);
      rig.net.fallback = const LfmResponse(200, '{"scrobbles":{}}');
      await rig.scrobbler.flush();
      final batch = rig.net.method('track.scrobble').last;
      expect(batch.containsKey('artist[1]'), isTrue);
      expect(rig.scrobbler.pending, 0);
      expect(rig.store.saved, isEmpty);
    });

    test('error 29 respeta el bloqueo y no reenvía antes', () async {
      final rig = Rig();
      rig.net.script.addAll([
        const LfmResponse(200, '{}'), // updateNowPlaying
        const LfmResponse(429, '{"error":29,"message":"limit"}', {
          'retry-after': '42',
        }),
      ]);
      await rig.play(song, 100);
      expect(rig.scrobbler.pending, 1);
      expect(rig.retries.last, const Duration(seconds: 43));
      final before = rig.net.requests.length;
      await rig.scrobbler.flush();
      expect(rig.net.requests.length, before);
      rig.now = rig.now.add(const Duration(seconds: 45));
      await rig.scrobbler.flush();
      expect(rig.scrobbler.pending, 0);
    });

    test('error 9 detiene el envío y conserva la cola', () async {
      final rig = Rig();
      rig.net.script.addAll([
        const LfmResponse(200, '{}'),
        const LfmResponse(403, '{"error":9,"message":"Invalid session key"}'),
      ]);
      await rig.play(song, 100);
      expect(rig.scrobbler.authFailed, isTrue);
      expect(rig.scrobbler.pending, 1);
    });

    test('lote rechazado se parte; el malo se descarta', () async {
      final rig = Rig();
      rig.net.fallback = const LfmResponse(503, '');
      await rig.play(song, 100);
      await rig.play(other, 100);
      rig.net.script.addAll([
        const LfmResponse(400, '{"error":6,"message":"bad"}'),
        const LfmResponse(400, '{"error":6,"message":"bad"}'),
        const LfmResponse(200, '{}'),
      ]);
      rig.net.fallback = const LfmResponse(200, '{}');
      await rig.scrobbler.flush();
      expect(rig.scrobbler.pending, 0);
    });

    test('la cola está acotada', () async {
      final store = MemoryListenQueueStore();
      final net = FakeNet()..fallback = const LfmResponse(503, '');
      var now = DateTime.utc(2026);
      final s = Scrobbler(
        client: clientOf(net),
        store: store,
        readSession: () async => sk,
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
}
