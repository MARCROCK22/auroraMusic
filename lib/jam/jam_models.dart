import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import '../core/models.dart';

enum JamMode { queueOnly, synchronized }

enum JamConnection { idle, hosting, connected, disconnected, closed }

class JamException implements Exception {
  const JamException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool isJamAddress(String address, {bool allowLoopback = false}) {
  final parsed = InternetAddress.tryParse(address);
  if (parsed == null ||
      parsed.type != InternetAddressType.IPv4 ||
      parsed.address != address) {
    return false;
  }
  final bytes = parsed.rawAddress;
  return (bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (allowLoopback && address == '127.0.0.1')) &&
      bytes[3] != 0 &&
      bytes[3] != 255;
}

String jamRandomSecret([int bytes = 32]) => base64Url
    .encode(List.generate(bytes, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String jamText(Object? value, {int max = 256, bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty) ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const JamException('Datos de Jam inválidos.');
  }
  return value.trim();
}

int jamInt(Object? value, {int max = 2147483647}) {
  if (value is! int || value < 0 || value > max) {
    throw const JamException('Datos de Jam inválidos.');
  }
  return value;
}

Map<String, dynamic> jamMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const JamException('Mensaje de Jam inválido.');
  }
  return value;
}

void jamKeys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const JamException('Mensaje de Jam inválido.');
  }
}

String jamIdentifier(Object? value) {
  final id = jamText(value, max: 64);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id)) {
    throw const JamException('Identificador de Jam inválido.');
  }
  return id;
}

class JamInvite {
  const JamInvite({
    required this.address,
    required this.port,
    required this.sessionId,
    required this.accessToken,
    required this.expiresAt,
  });
  final String address;
  final int port;
  final String sessionId;
  final String accessToken;
  final DateTime expiresAt;
  String get endpoint => '$address:$port';
  String encode() => jsonEncode({
    'v': 1,
    'address': address,
    'port': port,
    'sessionId': sessionId,
    'accessToken': accessToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch,
  });
  factory JamInvite.decode(
    String encoded, {
    bool allowLoopback = false,
    DateTime? now,
  }) {
    try {
      if (encoded.length > 2048) throw const FormatException();
      final data = jamMap(jsonDecode(encoded));
      jamKeys(data, {
        'v',
        'address',
        'port',
        'sessionId',
        'accessToken',
        'expiresAt',
      });
      if (data['v'] != 1) throw const FormatException();
      final address = jamText(data['address'], max: 15);
      if (!isJamAddress(address, allowLoopback: allowLoopback)) {
        throw const FormatException();
      }
      final port = jamInt(data['port'], max: 65535);
      final id = jamIdentifier(data['sessionId']);
      final token = jamIdentifier(data['accessToken']);
      final expires = DateTime.fromMillisecondsSinceEpoch(
        jamInt(data['expiresAt'], max: 8640000000000000),
      );
      final current = now ?? DateTime.now();
      if (port == 0 ||
          id.length != 22 ||
          token.length != 43 ||
          !expires.isAfter(current) ||
          expires.difference(current) > const Duration(hours: 4, minutes: 5)) {
        throw const FormatException();
      }
      return JamInvite(
        address: address,
        port: port,
        sessionId: id,
        accessToken: token,
        expiresAt: expires,
      );
    } catch (_) {
      throw const JamException(
        'El QR no contiene una Jam local válida o ya venció.',
      );
    }
  }
}

String? jamYouTubeId(Track track) {
  final uri = Uri.tryParse(track.pageUrl ?? '');
  if (uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort) {
    String? id;
    if (uri.host == 'www.youtube.com' ||
        uri.host == 'youtube.com' ||
        uri.host == 'm.youtube.com') {
      if (uri.path == '/watch') id = uri.queryParameters['v'];
      if (uri.pathSegments.length == 2 &&
          {'shorts', 'embed'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments.last;
      }
    } else if (uri.host == 'youtu.be' && uri.pathSegments.length == 1) {
      id = uri.pathSegments.first;
    }
    if (id != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return id;
  }
  return null;
}

String? jamSafeArtwork(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.toString().length > 512 ||
      !{
        'i.ytimg.com',
        'img.youtube.com',
        'i.scdn.co',
        'image-cdn-ak.spotifycdn.com',
      }.contains(uri.host)) {
    return null;
  }
  return uri.toString();
}

String jamNormalized(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Deliberately excludes local IDs/paths, extracted URLs, cookies and provider tokens.
class JamTrack {
  const JamTrack({
    required this.key,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.youtubeId,
    this.spotifyUri,
    this.artworkUrl,
    this.localOnly = false,
  });
  final String key;
  final String title;
  final String artist;
  final int durationMs;
  final String? youtubeId;
  final String? spotifyUri;
  final String? artworkUrl;
  final bool localOnly;
  String get titleArtist => '${jamNormalized(title)}|${jamNormalized(artist)}';
  Set<String> get keys => {
    key,
    'text:$titleArtist',
    if (youtubeId != null) 'yt:$youtubeId',
    ?spotifyUri,
  };
  factory JamTrack.fromTrack(Track track) {
    final title = jamText(track.title);
    final artist = jamText(track.artist);
    final youtube = jamYouTubeId(track);
    final spotify =
        track.spotifyUri != null &&
            RegExp(
              r'^spotify:track:[a-zA-Z0-9]{22}$',
            ).hasMatch(track.spotifyUri!)
        ? track.spotifyUri
        : null;
    final key = youtube != null
        ? 'yt_$youtube'
        : spotify != null
        ? 'sp_${spotify.split(':').last}'
        : 'local_${sha256.convert(utf8.encode('${jamNormalized(title)}|${jamNormalized(artist)}')).toString().substring(0, 24)}';
    return JamTrack(
      key: key,
      title: title,
      artist: artist,
      durationMs: track.duration.inMilliseconds.clamp(0, 86400000),
      youtubeId: youtube,
      spotifyUri: spotify,
      artworkUrl: jamSafeArtwork(track.artworkUrl),
      localOnly: youtube == null && spotify == null,
    );
  }
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'artist': artist,
    'durationMs': durationMs,
    'youtubeId': youtubeId,
    'spotifyUri': spotifyUri,
    'artworkUrl': artworkUrl,
    'localOnly': localOnly,
  };
  factory JamTrack.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'key',
      'title',
      'artist',
      'durationMs',
      'youtubeId',
      'spotifyUri',
      'artworkUrl',
      'localOnly',
    });
    final youtube = data['youtubeId'];
    final spotify = data['spotifyUri'];
    final artwork = data['artworkUrl'];
    if ((youtube != null &&
            (youtube is! String ||
                !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(youtube))) ||
        (spotify != null &&
            (spotify is! String ||
                !RegExp(
                  r'^spotify:track:[a-zA-Z0-9]{22}$',
                ).hasMatch(spotify))) ||
        (artwork != null &&
            (artwork is! String || jamSafeArtwork(artwork) != artwork)) ||
        data['localOnly'] is! bool) {
      throw const JamException('Metadatos de canción inválidos.');
    }
    final track = JamTrack(
      key: jamIdentifier(data['key']),
      title: jamText(data['title']),
      artist: jamText(data['artist']),
      durationMs: jamInt(data['durationMs'], max: 86400000),
      youtubeId: youtube as String?,
      spotifyUri: spotify as String?,
      artworkUrl: artwork as String?,
      localOnly: data['localOnly'] as bool,
    );
    final expected = JamTrack.fromTrack(
      Track(
        id: '',
        title: track.title,
        artist: track.artist,
        spotifyUri: track.spotifyUri,
        pageUrl: youtube == null
            ? null
            : 'https://www.youtube.com/watch?v=$youtube',
      ),
    );
    if (track.key != expected.key || track.localOnly != expected.localOnly) {
      throw const JamException('Identidad de canción inválida.');
    }
    return track;
  }
}

class JamPermissions {
  const JamPermissions({
    this.skip = false,
    this.reorder = false,
    this.remove = false,
  });
  final bool skip, reorder, remove;
  Map<String, bool> toJson() => {
    'skip': skip,
    'reorder': reorder,
    'remove': remove,
  };
  factory JamPermissions.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {'skip', 'reorder', 'remove'});
    if (data['skip'] is! bool ||
        data['reorder'] is! bool ||
        data['remove'] is! bool) {
      throw const JamException('Permisos inválidos.');
    }
    return JamPermissions(
      skip: data['skip'],
      reorder: data['reorder'],
      remove: data['remove'],
    );
  }
}

class JamParticipant {
  const JamParticipant({
    required this.id,
    required this.name,
    this.connected = true,
    this.permissions = const JamPermissions(),
  });
  final String id, name;
  final bool connected;
  final JamPermissions permissions;
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'connected': connected,
    'permissions': permissions.toJson(),
  };
  factory JamParticipant.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {'id', 'name', 'connected', 'permissions'});
    if (data['connected'] is! bool) {
      throw const JamException('Participante inválido.');
    }
    return JamParticipant(
      id: jamIdentifier(data['id']),
      name: jamText(data['name'], max: 32),
      connected: data['connected'],
      permissions: JamPermissions.fromJson(data['permissions']),
    );
  }
}

class JamQueueEntry {
  const JamQueueEntry({
    required this.id,
    required this.track,
    required this.addedBy,
  });
  final String id, addedBy;
  final JamTrack track;
  Map<String, Object> toJson() => {
    'id': id,
    'track': track.toJson(),
    'addedBy': addedBy,
  };
  factory JamQueueEntry.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {'id', 'track', 'addedBy'});
    return JamQueueEntry(
      id: jamIdentifier(data['id']),
      track: JamTrack.fromJson(data['track']),
      addedBy: jamIdentifier(data['addedBy']),
    );
  }
}

class JamPlayback {
  const JamPlayback({
    required this.sequence,
    required this.serverTimeMs,
    this.entryId,
    this.isPlaying = false,
    this.positionMs = 0,
  });
  final int sequence, serverTimeMs, positionMs;
  final String? entryId;
  final bool isPlaying;
  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'serverTimeMs': serverTimeMs,
    'entryId': entryId,
    'isPlaying': isPlaying,
    'positionMs': positionMs,
  };
  factory JamPlayback.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'sequence',
      'serverTimeMs',
      'entryId',
      'isPlaying',
      'positionMs',
    });
    if (data['isPlaying'] is! bool) {
      throw const JamException('Reproducción inválida.');
    }
    return JamPlayback(
      sequence: jamInt(data['sequence']),
      serverTimeMs: jamInt(data['serverTimeMs'], max: 8640000000000000),
      entryId: data['entryId'] == null ? null : jamIdentifier(data['entryId']),
      isPlaying: data['isPlaying'],
      positionMs: jamInt(data['positionMs'], max: 86400000),
    );
  }
}
