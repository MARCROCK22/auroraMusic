import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/discord/discord_presence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tramas IPC: codifica y decodifica', () {
    final bytes = encodeDiscordFrame(1, {'cmd': 'x', 'ñ': 'é'});
    final frame = decodeDiscordFrame(bytes)!;
    expect(frame.opcode, 1);
    expect(frame.payload['ñ'], 'é');
    expect(frame.length, bytes.length);
    expect(decodeDiscordFrame(bytes.sublist(0, bytes.length - 1)), isNull);
    expect(decodeDiscordFrame([1, 2]), isNull);
  });

  test('actividad de escucha y borrado', () {
    const track = Track(
      id: 'yt:a',
      title: 'Canción',
      artist: 'Artista',
      duration: Duration(seconds: 200),
      artworkUrl: 'https://img/x.jpg',
    );
    final now = DateTime.fromMillisecondsSinceEpoch(1000000);
    final cmd = buildDiscordActivityCommand(
      pid: 7,
      nonce: 'n',
      track: track,
      position: const Duration(seconds: 10),
      now: now,
    );
    final args = cmd['args'] as Map;
    final act = args['activity'] as Map;
    expect(cmd['cmd'], 'SET_ACTIVITY');
    expect(args['pid'], 7);
    expect(act['type'], 2);
    expect(act['details'], 'Canción');
    expect(act['state'], 'Artista');
    expect(act['timestamps'], {'start': 990000, 'end': 1190000});
    expect((act['assets'] as Map)['large_image'], 'https://img/x.jpg');
    expect((act['assets'] as Map)['large_text'], 'Aurora Music');

    final local = buildDiscordActivityCommand(
      pid: 7,
      nonce: 'n',
      track: const Track(id: 'l', title: 't', artist: 'a', artworkUrl: 'C:\\a'),
    );
    final la = (local['args'] as Map)['activity'] as Map;
    expect((la['assets'] as Map)['large_image'], 'aurora');
    expect((la['timestamps'] as Map).containsKey('end'), isFalse);

    final clear = buildDiscordActivityCommand(pid: 7, nonce: 'n');
    expect((clear['args'] as Map)['activity'], isNull);
  });
}
