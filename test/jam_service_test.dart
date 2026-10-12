import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';

const song = Track(
  id: 'yt:abcdefghijk',
  title: 'Song',
  artist: 'Artist',
  pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk&private=discard',
  artworkUrl: 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
);
Future<void> waitJam(JamService service, bool Function() condition) async {
  if (condition()) return;
  final ready = Completer<void>();
  void changed() {
    if (condition() && !ready.isCompleted) ready.complete();
  }

  service.addListener(changed);
  try {
    await ready.future.timeout(const Duration(seconds: 3));
  } finally {
    service.removeListener(changed);
  }
}

Future<WebSocket> rawJam(
  JamService host, {
  Map<String, String> extra = const {},
}) {
  final invite = host.invite!;
  return WebSocket.connect(
    'ws://${invite.address}:${invite.port}/jam/${invite.sessionId}',
    headers: {
      'Authorization': 'Bearer ${invite.accessToken}',
      'X-Aurora-Name': 'Test',
      ...extra,
    },
  );
}

void main() {
  test('concurrent reconnects cannot replace one participant socket', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    final initial = await rawJam(host);
    final welcome = Completer<Map<String, dynamic>>();
    initial.listen((message) {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      if (data['kind'] == 'welcome' && !welcome.isCompleted) {
        welcome.complete(data);
      }
    });
    final identity = await welcome.future;
    final id = identity['participantId'] as String;
    await initial.close();
    await waitJam(
      host,
      () => host.participants.any((p) => p.id == id && !p.connected),
    );
    Future<WebSocket?> attempt() async {
      try {
        return await rawJam(
          host,
          extra: {
            'X-Aurora-Participant': id,
            'X-Aurora-Resume': identity['resumeToken'] as String,
          },
        );
      } on WebSocketException {
        return null;
      }
    }

    final outcomes = await Future.wait([attempt(), attempt()]);
    expect(outcomes.whereType<WebSocket>().length, 1);
    expect(host.participants.length, 2);
    for (final socket in outcomes.whereType<WebSocket>()) {
      await socket.close();
    }
  });
  test('session rejects a seventeenth participant before upgrade', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    final sockets = <WebSocket>[];
    addTearDown(() => Future.wait(sockets.map((socket) => socket.close())));
    for (var i = 0; i < 15; i++) {
      final socket = await rawJam(host);
      sockets.add(socket);
      socket.listen((_) {});
    }
    await waitJam(host, () => host.participants.length == 16);
    await expectLater(rawJam(host), throwsA(isA<WebSocketException>()));
    expect(host.participants.length, 16);
  });
  test('oversized client message is rejected before JSON decoding', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    final socket = await rawJam(host);
    addTearDown(socket.close);
    final error = Completer<void>();
    socket.listen((message) {
      final data = jsonDecode(message as String) as Map;
      if (data['kind'] == 'error' && !error.isCompleted) error.complete();
    });
    socket.add('x' * 8193);
    await error.future;
    expect(host.queue, isEmpty);
  });
  test('redirect cannot send authorization to another local server', () async {
    final redirect = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(
      () => Future.wait([
        redirect.close(force: true),
        destination.close(force: true),
      ]),
    );
    var contacted = false;
    destination.listen((request) {
      contacted = true;
      request.response.statusCode = 403;
      request.response.close();
    });
    redirect.listen((request) {
      request.response.statusCode = 302;
      request.response.headers.set(
        'location',
        'http://127.0.0.1:${destination.port}/jam',
      );
      request.response.close();
    });
    final guest = JamService(allowLoopback: true);
    addTearDown(guest.close);
    await expectLater(
      guest.join(
        JamInvite(
          address: '127.0.0.1',
          port: redirect.port,
          sessionId: jamRandomSecret(16),
          accessToken: jamRandomSecret(),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        name: 'Guest',
      ),
      throwsA(isA<JamException>()),
    );
    expect(contacted, isFalse);
  });
  test(
    'address validation rejects public wildcard hostnames IPv6 and loopback by default',
    () {
      for (final address in [
        'example.org',
        '0.0.0.0',
        '8.8.8.8',
        '127.0.0.1',
        '::1',
        '192.168.1.255',
        '192.168.1.0',
        '192.168.001.1',
      ]) {
        expect(isJamAddress(address), isFalse);
      }
      for (final address in [
        '10.2.3.4',
        '172.16.1.2',
        '172.31.250.3',
        '192.168.1.2',
      ]) {
        expect(isJamAddress(address), isTrue);
      }
    },
  );
  test(
    'wire tracks strip paths IDs extracted URLs provider tokens and unsafe artwork',
    () {
      final local = JamTrack.fromTrack(
        const Track(
          id: 'C:/private/music.mp3',
          title: 'Local',
          artist: 'Artist',
          localPath: 'C:/private/music.mp3',
          artworkUrl: 'https://i.scdn.co/image/cover?token=discard',
          pageUrl: 'https://temporary.example/audio?token=discard',
        ),
      );
      final serialized = jsonEncode(local.toJson());
      expect(serialized.contains('private'), isFalse);
      expect(serialized.contains('temporary'), isFalse);
      expect(serialized.contains('token'), isFalse);
      expect(local.localOnly, isTrue);
      expect(JamTrack.fromTrack(song).youtubeId, 'abcdefghijk');
      expect(
        JamTrack.fromJson(JamTrack.fromTrack(song).toJson()).key,
        JamTrack.fromTrack(song).key,
      );
      expect(
        () => JamTrack.fromJson({...local.toJson(), 'localPath': 'forbidden'}),
        throwsA(isA<JamException>()),
      );
    },
  );
  test(
    'invite contains only join fields, is temporary and validates before networking',
    () {
      final now = DateTime.utc(2026, 10, 12);
      final invite = JamInvite(
        address: '192.168.1.2',
        port: 12345,
        sessionId: jamRandomSecret(16),
        accessToken: jamRandomSecret(),
        expiresAt: now.add(const Duration(hours: 1)),
      );
      final data = jsonDecode(invite.encode()) as Map;
      expect(data.keys.toSet(), {
        'v',
        'address',
        'port',
        'sessionId',
        'accessToken',
        'expiresAt',
      });
      expect(invite.accessToken.length, 43);
      expect(JamInvite.decode(invite.encode(), now: now).port, 12345);
      expect(
        () => JamInvite.decode(
          invite.encode(),
          now: now.add(const Duration(hours: 2)),
        ),
        throwsA(isA<JamException>()),
      );
      for (final invalid in [
        'https://remote.example',
        'not JSON',
        jsonEncode({...data, 'address': '8.8.8.8'}),
        jsonEncode({...data, 'extra': 'forbidden'}),
      ]) {
        expect(
          () => JamInvite.decode(invalid, now: now),
          throwsA(isA<JamException>()),
        );
      }
    },
  );
  test(
    'creates joins shares queue attribution duplicate prevention and closes',
    () async {
      final host = JamService(allowLoopback: true),
          first = JamService(allowLoopback: true),
          second = JamService(allowLoopback: true);
      addTearDown(
        () => Future.wait([host.close(), first.close(), second.close()]),
      );
      await host.host(address: '127.0.0.1', name: 'Host');
      await first.join(host.invite!, name: 'First');
      await second.join(host.invite!, name: 'Second');
      first.addTrack(JamTrack.fromTrack(song));
      await waitJam(second, () => second.queue.length == 1);
      expect(host.queue.single.addedBy, first.participantId);
      expect(second.participantName(second.queue.single.addedBy), 'First');
      second.addTrack(JamTrack.fromTrack(song));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(host.queue, hasLength(1));
      expect(first.queue, hasLength(1));
      await host.close();
      await waitJam(first, () => first.connection == JamConnection.closed);
      expect(first.invite, isNull);
    },
  );
  test(
    'permissions restrict remote queue edits and preserve attribution',
    () async {
      final host = JamService(allowLoopback: true),
          guest = JamService(allowLoopback: true);
      addTearDown(() => Future.wait([host.close(), guest.close()]));
      await host.host(address: '127.0.0.1', name: 'Host');
      await guest.join(host.invite!, name: 'Guest');
      host.addTrack(JamTrack.fromTrack(song));
      host.addTrack(
        JamTrack.fromTrack(
          const Track(
            id: 'x',
            title: 'Other',
            artist: 'Artist',
            pageUrl: 'https://www.youtube.com/watch?v=lmnopqrstuv',
          ),
        ),
      );
      await waitJam(guest, () => guest.queue.length == 2);
      guest.remove(guest.queue.first.id);
      await waitJam(guest, () => guest.error != null);
      expect(host.queue, hasLength(2));
      var skipped = false;
      host.onSkip = () async {
        skipped = true;
      };
      guest.skip();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(skipped, isFalse);
      host.setPermissions(
        guest.participantId,
        const JamPermissions(skip: true, reorder: true, remove: true),
      );
      await waitJam(guest, () => guest.me!.permissions.remove);
      final first = guest.queue.first.id;
      guest.reorder(first, 1);
      await waitJam(host, () => host.queue.last.id == first);
      guest.skip();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(skipped, isTrue);
      guest.remove(first);
      await waitJam(host, () => host.queue.length == 1);
    },
  );
  test(
    'reconnect retains ephemeral participant identity and permissions',
    () async {
      final host = JamService(allowLoopback: true),
          guest = JamService(allowLoopback: true);
      addTearDown(() => Future.wait([host.close(), guest.close()]));
      await host.host(address: '127.0.0.1', name: 'Host');
      await guest.join(host.invite!, name: 'Guest');
      final id = guest.participantId;
      host.setPermissions(id, const JamPermissions(reorder: true));
      await guest.disconnect();
      await waitJam(
        host,
        () => host.participants.any((p) => p.id == id && !p.connected),
      );
      host.addTrack(JamTrack.fromTrack(song));
      await guest.reconnect();
      expect(guest.participantId, id);
      expect(guest.me!.permissions.reorder, isTrue);
      expect(guest.queue, hasLength(1));
    },
  );
  test(
    'invalid and binary messages do not modify authoritative state',
    () async {
      final host = JamService(allowLoopback: true);
      addTearDown(host.close);
      await host.host(address: '127.0.0.1', name: 'Host');
      final socket = await rawJam(host);
      addTearDown(socket.close);
      final errors = Completer<void>();
      socket.listen((raw) {
        final data = jsonDecode(raw as String) as Map;
        if (data['kind'] == 'error' && !errors.isCompleted) errors.complete();
      });
      socket.add(
        jsonEncode({
          'kind': 'add',
          'track': {'bad': 'invalid'},
        }),
      );
      socket.add([1, 2, 3]);
      socket.add(jsonEncode({'kind': 'play', 'isPlaying': true}));
      await errors.future.timeout(const Duration(seconds: 2));
      expect(host.queue, isEmpty);
      expect(host.playback, isNull);
    },
  );
  test(
    'handshake rejects wrong authorization origins and fabricated resume identity',
    () async {
      final host = JamService(allowLoopback: true);
      addTearDown(host.close);
      await host.host(address: '127.0.0.1', name: 'Host');
      for (final headers in [
        {'Authorization': 'Bearer invalid-test-access'},
        {'Origin': 'https://untrusted.example'},
        {'X-Aurora-Participant': 'unknown_identity', 'X-Aurora-Resume': ''},
      ]) {
        await expectLater(
          rawJam(host, extra: headers),
          throwsA(isA<WebSocketException>()),
        );
      }
      expect(host.participants, hasLength(1));
    },
  );
  test('spam and empty invalid messages count toward request limit', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    final socket = await rawJam(host);
    final closed = Completer<void>();
    socket.listen((_) {}, onDone: closed.complete);
    for (var i = 0; i < 12; i++) {
      socket.add('not-json');
    }
    await closed.future.timeout(const Duration(seconds: 3));
    expect(host.queue, isEmpty);
  });
  test('host queue and per-person limits are bounded', () async {
    var now = DateTime.now();
    final host = JamService(allowLoopback: true, clock: () => now);
    addTearDown(host.close);
    await host.host(address: '127.0.0.1', name: 'Host');
    for (var i = 0; i < 200; i++) {
      now = now.add(const Duration(seconds: 1));
      host.addTrack(
        JamTrack.fromTrack(
          Track(id: 'local$i', title: 'Song$i', artist: 'Artist'),
        ),
      );
    }
    expect(host.queue, hasLength(200));
    expect(
      () => host.addTrack(
        JamTrack.fromTrack(
          const Track(id: 'over', title: 'Overflow', artist: 'Artist'),
        ),
      ),
      throwsA(isA<JamException>()),
    );
    for (var i = 0; i < 9; i++) {
      try {
        host.addTrack(JamTrack.fromTrack(song));
      } on JamException {
        /* Limit remains enforced below. */
      }
    }
    expect(
      () => host.addTrack(JamTrack.fromTrack(song)),
      throwsA(isA<JamException>()),
    );
  });
  test('session expiry invalidates access and closes local server', () async {
    final host = JamService(allowLoopback: true);
    addTearDown(host.close);
    await host.host(
      address: '127.0.0.1',
      name: 'Host',
      lifetime: const Duration(milliseconds: 60),
    );
    await waitJam(host, () => host.connection == JamConnection.closed);
    expect(host.invite, isNull);
  });
  test(
    'connection failures are sanitized and mention local network troubleshooting',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final guest = JamService(allowLoopback: true);
      addTearDown(guest.close);
      await expectLater(
        guest.join(
          JamInvite(
            address: '127.0.0.1',
            port: port,
            sessionId: jamRandomSecret(16),
            accessToken: jamRandomSecret(),
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
          name: 'Guest',
        ),
        throwsA(isA<JamException>()),
      );
      expect(guest.error!.contains('firewall'), isTrue);
      expect(guest.connection, JamConnection.disconnected);
    },
  );
  test('playback state and timestamps come only from host authority', () async {
    final host = JamService(allowLoopback: true),
        guest = JamService(allowLoopback: true);
    addTearDown(() => Future.wait([host.close(), guest.close()]));
    await host.host(address: '127.0.0.1', name: 'Host');
    await guest.join(host.invite!, name: 'Guest');
    host.addTrack(JamTrack.fromTrack(song));
    host.setMode(JamMode.synchronized);
    host.publishPlayback(
      entryId: host.queue.single.id,
      playing: true,
      positionMs: 1000,
    );
    await waitJam(guest, () => guest.playback != null);
    expect(guest.mode, JamMode.synchronized);
    expect(guest.playback!.positionMs, 1000);
    expect(guest.playback!.isPlaying, isTrue);
    final sequence = guest.playback!.sequence;
    guest.publishPlayback(
      entryId: guest.queue.single.id,
      playing: false,
      positionMs: 0,
    );
    expect(host.playback!.sequence, sequence);
  });
}
