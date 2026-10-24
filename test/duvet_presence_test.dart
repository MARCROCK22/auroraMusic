import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/duvet_presence.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Lo que recibiría Duvet, sin tubería.
class _Pipe extends DuvetPipe {
  final sent = <Map<String, Object?>>[];
  int closed = 0;

  @override
  bool send(Map<String, Object?> message) {
    sent.add(message);
    return true;
  }

  @override
  void close() => closed++;
}

const _song = Track(
  id: 'a',
  title: 'Ruido blanco',
  artist: 'Aurora',
  duration: Duration(minutes: 3),
  artworkUrl: 'https://i.ytimg.com/vi/a/hqdefault.jpg',
  album: 'Noches',
  pageUrl: 'https://youtu.be/a',
);

void main() {
  test(
    'la actividad: escuchando Aurora Music, título, artista, inicio y fin, y la portada pública',
    () {
      expect(
        duvetActivity(_song, start: 1000, duration: const Duration(minutes: 3)),
        {
          'type': 2,
          'name': 'Aurora Music',
          'details': 'Ruido blanco',
          'state': 'Aurora',
          'timestamps': {'start': 1000, 'end': 181000},
          'assets': {
            'large_image': 'https://i.ytimg.com/vi/a/hqdefault.jpg',
            'large_text': 'Noches',
          },
        },
      );
      // Una portada local (la del proxy) no la vería nadie; sin duración no hay fin.
      const local = Track(
        id: 'b',
        title: 'b',
        artist: 'x',
        artworkUrl: 'http://127.0.0.1:4000/b.jpg',
      );
      final activity = duvetActivity(
        local,
        start: 1000,
        duration: Duration.zero,
      );
      expect(activity.containsKey('assets'), isFalse);
      expect(activity['timestamps'], {'start': 1000});
    },
  );

  test(
    'envía lo que suena una vez, otra tras un salto, y lo borra al pausar y al apagarlo',
    () async {
      final audio = FakeAudio();
      final controller = await createTestController(
        tracks: [_song],
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      final pipe = _Pipe();
      final presence = DuvetPresence(controller, pipe: pipe, supported: true)
        ..start();
      addTearDown(presence.dispose);

      await controller.playTrack(_song, context: [_song]);
      expect(pipe.sent, hasLength(1));
      expect(pipe.sent.single['type'], 'SET_ACTIVITY');
      expect((pipe.sent.single['data']! as Map)['details'], 'Ruido blanco');

      await audio.seek(audio.position);
      expect(pipe.sent, hasLength(1), reason: 'nada cambió');
      await controller.seek(const Duration(minutes: 1));
      expect(pipe.sent, hasLength(2), reason: 'un salto mueve el inicio');

      final closed = pipe.closed;
      await controller.pausePlayback();
      expect(
        pipe.closed,
        greaterThan(closed),
        reason: 'cerrar la tubería borra la actividad',
      );

      await controller.resumePlayback();
      expect(pipe.sent, hasLength(3));
      await presence.setEnabled(false);
      await controller.seek(const Duration(minutes: 2));
      expect(pipe.sent, hasLength(3), reason: 'apagado no envía nada');
    },
  );

  test('transporte: tubería en Windows, socket Unix en Linux', () {
    final windows = duvetTransport(windows: true);
    expect(windows, isA<DuvetPipe>());
    expect(windows, isNot(isA<DuvetSocket>()));
    final linux = duvetTransport(
      windows: false,
      environment: {'XDG_RUNTIME_DIR': '/run/user/1000', 'TMPDIR': '/tmp'},
    );
    expect(linux, isA<DuvetSocket>());
    expect((linux as DuvetSocket).paths, [
      '/run/user/1000/duvet-ipc',
      '/tmp/duvet-ipc',
    ]);
  });

  test(
    'socket Unix: conecta, envía un JSON por línea y cerrar corta',
    () async {
      final dir = await Directory.systemTemp.createTemp('duvet');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/duvet-ipc';
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      addTearDown(server.close);
      final lines = StreamController<String>();
      final closed = Completer<void>();
      server.listen(
        (client) => client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(lines.add, onDone: closed.complete),
      );

      final socket = DuvetSocket(['${dir.path}/falta', path]);
      expect(socket.send({'type': 'SET_ACTIVITY'}), isFalse);
      final first = await lines.stream.first;
      expect(jsonDecode(first), {'type': 'SET_ACTIVITY'});
      socket.close();
      await closed.future.timeout(const Duration(seconds: 5));
    },
    skip: Platform.isLinux ? false : 'Solo Linux',
  );
}
