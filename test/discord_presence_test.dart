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

  test('límites de Discord: recorte, relleno y portada', () {
    expect(discordText('x' * 300).runes.length, 128);
    expect(discordText('x' * 300).endsWith('…'), isTrue);
    expect(discordText('a').runes.length, 2);
    expect(discordText('  ', 'Respaldo'), 'Respaldo');
    expect(discordCover('https://${'a' * 300}'), 'aurora');
    expect(discordCover('http://x/y.jpg'), 'aurora');
    expect(discordCover('https://x/y.jpg'), 'https://x/y.jpg');

    final cmd = buildDiscordActivityCommand(
      pid: 1,
      nonce: 'n',
      track: Track(
        id: 'a',
        title: 'T',
        artist: '',
        artworkUrl: 'https://${'a' * 300}',
      ),
    );
    final act = (cmd['args'] as Map)['activity'] as Map;
    expect((act['details'] as String).length, 2);
    expect(act['state'], 'Artista desconocido');
    expect((act['timestamps'] as Map).containsKey('end'), isFalse);
    expect((act['assets'] as Map)['large_image'], 'aurora');
  });

  test('Jam: estado, grupo hasheado y sin código crudo', () {
    const track = Track(id: 'a', title: 'Tema', artist: 'Ana');
    final cmd = buildDiscordActivityCommand(
      pid: 1,
      nonce: 'n',
      track: track,
      jam: true,
      partySize: 3,
      partyId: 'ABCD1234',
    );
    final act = (cmd['args'] as Map)['activity'] as Map;
    expect(act['state'], 'Ana · en una Jam');
    final party = act['party'] as Map;
    expect(party['size'], [3, 16]);
    expect(party['id'], discordPartyId('ABCD1234'));
    expect(party['id'], isNot(contains('ABCD1234')));
    final solo = buildDiscordActivityCommand(pid: 1, nonce: 'n', track: track);
    expect(
      ((solo['args'] as Map)['activity'] as Map).containsKey('party'),
      false,
    );
  });
}
