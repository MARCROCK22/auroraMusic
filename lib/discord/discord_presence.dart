import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/models.dart';

const discordClientId = String.fromEnvironment('AURORA_DISCORD_CLIENT_ID');

/// Rich Presence solo existe en Windows y con un client id compilado.
bool get discordAvailable => Platform.isWindows && discordClientId.isNotEmpty;

/// Trama IPC de Discord: int32le opcode + int32le longitud + JSON utf8.
Uint8List encodeDiscordFrame(int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final out = ByteData(8 + body.length)
    ..setInt32(0, opcode, Endian.little)
    ..setInt32(4, body.length, Endian.little);
  return Uint8List.view(out.buffer)..setRange(8, 8 + body.length, body);
}

/// Decodifica una trama completa al inicio de [bytes]; null si está incompleta.
({int opcode, Map<String, dynamic> payload, int length})? decodeDiscordFrame(
  List<int> bytes,
) {
  if (bytes.length < 8) return null;
  final head = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 8)));
  final size = head.getInt32(4, Endian.little);
  if (size < 0 || bytes.length < 8 + size) return null;
  final json = jsonDecode(utf8.decode(bytes.sublist(8, 8 + size)));
  return (
    opcode: head.getInt32(0, Endian.little),
    payload: json is Map<String, dynamic> ? json : const {},
    length: 8 + size,
  );
}

/// Comando SET_ACTIVITY; [track] null borra la actividad.
Map<String, Object?> buildDiscordActivityCommand({
  required int pid,
  required String nonce,
  Track? track,
  Duration position = Duration.zero,
  DateTime? now,
}) {
  Map<String, Object?>? activity;
  if (track != null) {
    final start =
        (now ?? DateTime.now()).millisecondsSinceEpoch -
        position.inMilliseconds;
    final cover = track.artworkUrl;
    activity = {
      'type': 2,
      'details': track.title,
      'state': track.artist,
      'timestamps': {
        'start': start,
        if (track.duration > Duration.zero)
          'end': start + track.duration.inMilliseconds,
      },
      'assets': {
        'large_image': cover != null && cover.startsWith('https://')
            ? cover
            : 'aurora',
        'large_text': track.album ?? 'Aurora Music',
      },
    };
  }
  return {
    'cmd': 'SET_ACTIVITY',
    'args': {'pid': pid, 'activity': activity},
    'nonce': nonce,
  };
}

/// Presencia en Discord por IPC (tubería con nombre). Nunca lanza.
class DiscordPresence {
  DiscordPresence({this.clientId = discordClientId});
  final String clientId;
  bool enabled = true;
  RandomAccessFile? _pipe;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastKey;
  int _nonce = 0;

  /// Llamar solo ante cambio de pista o de play/pausa.
  void update(Track? track, {required bool playing, Duration? position}) {
    final shown = enabled && playing ? track : null;
    final key = '${shown?.id}';
    if (key == _lastKey && _pipe != null) return;
    _send(shown, position ?? Duration.zero, key);
  }

  void clear() => _send(null, Duration.zero, 'null');

  void dispose() {
    try {
      if (_pipe != null) clear();
      _pipe?.closeSync();
    } catch (_) {}
    _pipe = null;
  }

  void _send(Track? track, Duration position, String key) {
    if (clientId.isEmpty || !Platform.isWindows) return;
    try {
      if (_pipe == null && !_connect()) return;
      _pipe!.writeFromSync(
        encodeDiscordFrame(
          1,
          buildDiscordActivityCommand(
            pid: pid,
            nonce: '${++_nonce}',
            track: track,
            position: position,
          ),
        ),
      );
      _lastKey = key;
    } catch (_) {
      _drop();
    }
  }

  bool _connect() {
    final now = DateTime.now();
    if (now.difference(_lastAttempt) < const Duration(seconds: 30)) {
      return false;
    }
    _lastAttempt = now;
    for (var i = 0; i < 10; i++) {
      try {
        // Solo escritura: no leemos las respuestas de Discord. La ruta
        // \\.\pipe\ falla en dart:io (errno 53); GLOBALROOT sí abre.
        final pipe = File(
          r'\\?\GLOBALROOT\Device\NamedPipe\discord-ipc-'
          '$i',
        ).openSync(mode: FileMode.append);
        try {
          pipe.writeFromSync(
            encodeDiscordFrame(0, {'v': 1, 'client_id': clientId}),
          );
          _pipe = pipe;
          return true;
        } catch (_) {
          pipe.closeSync();
        }
      } catch (_) {}
    }
    return false;
  }

  void _drop() {
    try {
      _pipe?.closeSync();
    } catch (_) {}
    _pipe = null;
    _lastKey = null;
  }
}
