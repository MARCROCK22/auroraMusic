import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/friends/friends_data.dart';
import 'package:aurora_music/friends/friends_providers.dart';
import 'package:aurora_music/friends/friends_service.dart';
import 'package:aurora_music/ui/friends_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class FakeAuth extends ChangeNotifier {
  String? uid;
  void set(String? v) {
    uid = v;
    notifyListeners();
  }
}

class FakeData implements FriendsData {
  FakeData(this.me);
  final String me;
  final profiles = <String, Map<String, dynamic>>{
    'u1': {'id': 'u1', 'username': 'ana', 'avatar_path': null},
    'u2': {'id': 'u2', 'username': 'beto', 'avatar_path': null},
    'u3': {'id': 'u3', 'username': 'carla', 'avatar_path': null},
  };
  final requests = <Map<String, dynamic>>[];
  final shares = <Map<String, dynamic>>[];
  void Function(String, Map<String, dynamic>)? onRequest;
  void Function(Map<String, dynamic>)? onShare;
  bool unsubscribed = false;
  Map<String, Object?>? lastTrack;
  String? lastKind;

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String prefix, {
    required String excludeId,
    int limit = 20,
  }) async => [
    for (final p in profiles.values)
      if ((p['username'] as String).startsWith(prefix) && p['id'] != excludeId)
        p,
  ];
  @override
  Future<List<Map<String, dynamic>>> profilesByIds(List<String> ids) async => [
    for (final i in ids)
      if (profiles[i] != null) profiles[i]!,
  ];
  @override
  Future<List<Map<String, dynamic>>> listRequests() async => [...requests];
  @override
  Future<void> insertRequest(String toId) async => requests.add({
    'id': 'r${requests.length}',
    'from_id': me,
    'to_id': toId,
    'status': 'pending',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
  @override
  Future<void> setRequestStatus(String id, String status) async =>
      requests.firstWhere((r) => r['id'] == id)['status'] = status;
  @override
  Future<void> deleteRequest(String id) async =>
      requests.removeWhere((r) => r['id'] == id);
  @override
  Future<void> insertShare(
    String toId,
    String kind,
    Map<String, Object?> payload,
    String? note,
  ) async {
    lastKind = kind;
    lastTrack = payload;
  }

  @override
  Future<List<Map<String, dynamic>>> listInbox({
    required int limit,
    DateTime? before,
  }) async {
    final rows = [
      for (final s in shares)
        if (before == null ||
            DateTime.parse(s['created_at'] as String).isBefore(before))
          s,
    ]..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at']));
    return rows.take(limit).toList();
  }

  @override
  Future<void> markSeen(List<String> ids) async {
    for (final s in shares) {
      if (ids.contains(s['id'])) s['seen'] = true;
    }
  }

  @override
  Future<int> countUnseen() async =>
      shares.where((s) => s['seen'] != true).length;
  @override
  Future<Future<void> Function()> subscribe({
    required void Function(String, Map<String, dynamic>) onRequest,
    required void Function(Map<String, dynamic>) onShare,
  }) async {
    this.onRequest = onRequest;
    this.onShare = onShare;
    return () async => unsubscribed = true;
  }
}

Map<String, dynamic> share(int i, {String from = 'u1', bool seen = false}) => {
  'id': 's$i',
  'from_id': from,
  'to_id': 'me',
  'track': {'id': 'v$i', 'title': 'Canción $i', 'artist': 'Artista'},
  'note': i == 0 ? 'Escúchala' : null,
  'created_at': DateTime.utc(2026, 1, 1, 0, i).toIso8601String(),
  'seen': seen,
};

Map<String, dynamic> req(String id, String from, String to, String status) => {
  'id': id,
  'from_id': from,
  'to_id': to,
  'status': status,
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  late FakeAuth auth;
  late FakeData data;
  FriendsService make() => FriendsService(
    auth: auth,
    currentUid: () => auth.uid,
    dataFor: (uid) => data,
    avatarUrl: (_) => null,
  );

  setUp(() {
    auth = FakeAuth();
    data = FakeData('me');
  });

  test('sin sesión no carga nada; al iniciar sesión sí', () async {
    final f = make();
    expect(f.signedIn, isFalse);
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    auth.set('me');
    await settle();
    expect(f.signedIn, isTrue);
    expect(f.friends.map((u) => u.username), ['ana']);
    auth.set(null);
    expect(f.friends, isEmpty);
    expect(data.unsubscribed, isTrue);
    f.dispose();
  });

  test(
    'transiciones de solicitud: enviar, aceptar, rechazar, borrar',
    () async {
      data.requests
        ..add(req('in1', 'u1', 'me', 'pending'))
        ..add(req('in2', 'u2', 'me', 'pending'));
      auth.set('me');
      final f = make();
      await settle();
      expect(f.incoming.length, 2);
      expect(await f.accept('in1'), isNull);
      expect(await f.decline('in2'), isNull);
      expect(f.friends.map((u) => u.username), ['ana']);
      expect(f.incoming, isEmpty);
      expect(await f.sendRequest('u3'), isNull);
      expect(f.outgoing.single.user.username, 'carla');
      expect(f.relationTo('u3'), 'sent');
      expect(await f.removeFriend('u1'), isNull);
      expect(f.friends, isEmpty);
      expect(await f.sendRequest('me'), isNotNull);
      f.dispose();
    },
  );

  test('búsqueda: mínimo 3 letras y excluye al propio usuario', () async {
    data.profiles['me'] = {'id': 'me', 'username': 'yo_mismo'};
    auth.set('me');
    final f = make();
    await settle();
    expect(await f.searchUsers('yo'), isEmpty);
    expect(await f.searchUsers('yo_'), isEmpty);
    data.profiles['u4'] = {'id': 'u4', 'username': 'yoli'};
    expect((await f.searchUsers('yol')).single.username, 'yoli');
    f.dispose();
  });

  test('bandeja: paginación, sin vistas y markSeen', () async {
    for (var i = 0; i < 25; i++) {
      data.shares.add(share(i));
    }
    auth.set('me');
    final f = make();
    await settle();
    expect(f.inbox.length, 20);
    expect(f.hasMoreInbox, isTrue);
    expect(f.inbox.first.track.title, 'Canción 24');
    expect(f.unseenCount, 25);
    await f.loadMoreInbox();
    expect(f.inbox.length, 25);
    expect(f.hasMoreInbox, isFalse);
    await f.markSeen(['s24', 's23']);
    expect(f.unseenCount, 23);
    expect(data.shares.where((s) => s['seen'] == true).length, 2);
    f.dispose();
  });

  test('tiempo real: nueva canción y solicitud avisan y suman', () async {
    auth.set('me');
    final f = make();
    await settle();
    final notices = <FriendsNotice>[];
    f.notices.listen(notices.add);
    data.onShare!(share(1));
    await settle();
    expect(f.unseenCount, 1);
    expect(f.inbox.single.from.username, 'ana');
    data.requests.add(req('x', 'u2', 'me', 'pending'));
    data.onRequest!('insert', req('x', 'u2', 'me', 'pending'));
    await settle();
    expect(f.incoming.single.user.username, 'beto');
    expect(notices.map((n) => n.kind), [
      FriendsNoticeKind.share,
      FriendsNoticeKind.request,
    ]);
    f.dispose();
  });

  test(
    'enviar: solo amigos, sin locales y sin ruta local en el JSON',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      const t = Track(id: 'abc', title: 'T', artist: 'A', pageUrl: 'file:///x');
      expect(await f.shareTrack('u2', t), isNotNull);
      expect(
        await f.shareTrack(
          'u1',
          const Track(id: 'l', title: 'L', artist: 'A', localPath: 'C:/m.mp3'),
        ),
        isNotNull,
      );
      expect(await f.shareTrack('u1', t, note: 'hola'), isNull);
      expect(data.lastTrack!.containsKey('localPath'), isFalse);
      expect(data.lastTrack!.containsKey('pageUrl'), isFalse);
      f.dispose();
    },
  );

  test('pista recibida no confiable se valida', () {
    expect(trackFromShared('x'), isNull);
    expect(trackFromShared({'id': 1, 'title': 't', 'artist': 'a'}), isNull);
    final t = trackFromShared({
      'id': 'v',
      'title': 't',
      'artist': 'a',
      'localPath': 'C:/secreto',
      'artworkUrl': 'javascript:alert(1)',
    })!;
    expect(t.localPath, isNull);
    expect(t.artworkUrl, isNull);
  });

  test(
    'listas: se filtran locales, se recorta y se valida al recibir',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      final many = [
        for (var i = 0; i < 600; i++)
          Track(id: 'v$i', title: 'T$i', artist: 'A'),
        const Track(id: 'loc', title: 'L', artist: 'A', localPath: 'C:/m.mp3'),
      ];
      expect(await f.sharePlaylist('u2', 'Mix', many), isNotNull);
      expect(await f.sharePlaylist('u1', 'Mix', many.sublist(600)), isNotNull);
      expect(await f.sharePlaylist('u1', 'Mix', many, note: 'toma'), isNull);
      expect(data.lastKind, 'playlist');
      final sent = data.lastTrack!['tracks'] as List;
      expect(sent.length, maxSharedPlaylistTracks);
      expect(sent.any((t) => (t as Map).containsKey('localPath')), isFalse);
      final back = playlistFromShared(data.lastTrack)!;
      expect(back.tracks.length, maxSharedPlaylistTracks);
      expect(playlistFromShared({'name': 'x', 'tracks': 'no'}), isNull);
      expect(playlistFromShared({'name': '', 'tracks': []}), isNull);
      f.dispose();
    },
  );

  test(
    'invitación a Jam: solo amigos, código válido, caduca a las 2 h',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      expect(await f.shareJamInvite('u1', 'no es un código'), isNotNull);
      expect(await f.shareJamInvite('u2', 'ABCD2345'), isNotNull);
      expect(await f.shareJamInvite('u1', 'abcd-2345'), isNull);
      expect(data.lastKind, 'jam');
      expect(data.lastTrack, {'code': 'ABCD2345'});
      expect(jamCodeFromShared({'code': 'abcd2345'}), 'ABCD2345');
      expect(jamCodeFromShared({'code': 'aurora://x'}), isNull);
      expect(jamCodeFromShared({'code': 5}), isNull);
      final item = SharedItem(
        id: 'j',
        from: f.friends.first,
        track: const Track(id: '-', title: '', artist: ''),
        createdAt: DateTime(2026, 1, 1, 10),
        seen: false,
        kind: SharedKind.jam,
        jamCode: 'ABCD2345',
      );
      expect(item.jamExpired(DateTime(2026, 1, 1, 11, 59)), isFalse);
      expect(item.jamExpired(DateTime(2026, 1, 1, 12, 1)), isTrue);
      f.dispose();
    },
  );

  test('bandeja con los tres tipos; los inválidos se descartan', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    data.shares
      ..add({...share(1), 'created_at': now})
      ..add({
        ...share(2),
        'kind': 'playlist',
        'created_at': now,
        'track': {
          'name': 'Mix',
          'tracks': [
            {'id': 'a', 'title': 'T', 'artist': 'A'},
          ],
        },
      })
      ..add({
        ...share(3),
        'kind': 'jam',
        'created_at': now,
        'track': {'code': 'ABCD2345'},
      })
      ..add({
        ...share(4),
        'kind': 'jam',
        'track': {'code': '<x>'},
      })
      ..add({...share(5), 'kind': 'otro'});
    auth.set('me');
    final f = make();
    await settle();
    expect(f.inbox.map((i) => i.kind).toSet(), {
      SharedKind.track,
      SharedKind.playlist,
      SharedKind.jam,
    });
    expect(f.inbox.length, 3);
    final notices = <FriendsNoticeKind>[];
    f.notices.map((n) => n.kind).listen(notices.add);
    data.onShare!({
      ...share(9),
      'kind': 'jam',
      'created_at': now,
      'track': {'code': 'ZZZZ2345'},
    });
    await settle();
    expect(notices, [FriendsNoticeKind.jam]);
    f.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool signedIn,
    Size? size,
    Future<void> Function(String)? onJoinJam,
  }) async {
    final controller = await createTestController();
    auth.uid = signedIn ? 'me' : null;
    final f = make();
    addTearDown(() {
      auth.dispose();
    });
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [friendsServiceProvider.overrideWith((ref) => f)],
        child: MaterialApp(
          home: Scaffold(
            body: FriendsPage(controller: controller, onJoinJam: onJoinJam),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('página sin sesión invita a Ajustes → Cuenta', (tester) async {
    await tester.runAsync(() => pump(tester, signedIn: false));
    expect(find.byKey(const ValueKey('friends-signin-hint')), findsOneWidget);
    expect(find.textContaining('Ajustes → Cuenta'), findsOneWidget);
  });

  for (final size in [const Size(1000, 800), const Size(320, 640)]) {
    testWidgets('bandeja con listas e invitaciones ${size.width.toInt()}px', (
      tester,
    ) async {
      final now = DateTime.now().toUtc().toIso8601String();
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      data.shares
        ..add({
          ...share(2),
          'kind': 'playlist',
          'created_at': now,
          'track': {
            'name': 'Mix de ana',
            'tracks': [
              {'id': 'a', 'title': 'T', 'artist': 'A'},
            ],
          },
        })
        ..add({
          ...share(3),
          'kind': 'jam',
          'created_at': now,
          'track': {'code': 'ABCD2345'},
        });
      String? joined;
      await tester.runAsync(
        () => pump(
          tester,
          signedIn: true,
          size: size,
          onJoinJam: (c) async => joined = c,
        ),
      );
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
      await tester.pump();
      expect(find.text('Mix de ana'), findsOneWidget);
      expect(find.text('1 canciones'), findsOneWidget);
      expect(find.text('Guardar en mi biblioteca'), findsOneWidget);
      expect(find.text('ana te invita a su Jam'), findsOneWidget);
      await tester.tap(find.text('Unirse'));
      expect(joined, 'ABCD2345');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('menú de canción: «Enviar a un amigo» sigue a la sesión', (
    tester,
  ) async {
    final controller = await tester.runAsync(createTestController);
    final f = make();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [friendsServiceProvider.overrideWith((ref) => f)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SendToFriendButton(
                  track: const Track(id: 'x', title: 'T', artist: 'A'),
                ),
                SendToFriendButton(
                  track: const Track(
                    id: 'y',
                    title: 'L',
                    artist: 'A',
                    localPath: 'C:/m.mp3',
                  ),
                ),
                Text('${controller != null}'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('send-to-friend')), findsNothing);
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    auth.set('me');
    await tester.runAsync(settle);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-to-friend')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-to-friend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-to-u1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-to-u1')));
    await tester.pumpAndSettle();
    expect(data.lastKind, 'track');
    auth.set(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-to-friend')), findsNothing);
  });

  for (final size in [const Size(1000, 800), const Size(320, 640)]) {
    testWidgets('página con datos ${size.width.toInt()}px', (tester) async {
      data.requests
        ..add(req('a', 'u1', 'me', 'accepted'))
        ..add(req('b', 'u2', 'me', 'pending'));
      data.shares.add(share(0));
      await tester.runAsync(() => pump(tester, signedIn: true, size: size));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.text('ana'), findsOneWidget);
      expect(find.text('Solicitudes · 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friends-tab-1')));
      await tester.pump();
      expect(find.text('beto'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
      await tester.pump();
      expect(find.text('Canción 0'), findsOneWidget);
      expect(find.textContaining('Escúchala'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }
}
