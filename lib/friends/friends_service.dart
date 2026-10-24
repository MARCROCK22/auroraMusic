import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import '../core/models.dart';
import 'friends_data.dart';

class FriendUser {
  const FriendUser({required this.id, required this.username, this.avatarUrl});
  final String id;
  final String username;
  final String? avatarUrl;
}

/// Solicitud vista desde mi lado: [user] es la otra persona.
class FriendRequestView {
  const FriendRequestView({
    required this.id,
    required this.user,
    required this.incoming,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final FriendUser user;
  final bool incoming;
  final String status;
  final DateTime createdAt;
}

class SharedItem {
  const SharedItem({
    required this.id,
    required this.from,
    required this.track,
    required this.createdAt,
    required this.seen,
    this.note,
  });
  final String id;
  final FriendUser from;
  final Track track;
  final String? note;
  final DateTime createdAt;
  final bool seen;
  SharedItem withSeen() => SharedItem(
    id: id,
    from: from,
    track: track,
    createdAt: createdAt,
    seen: true,
    note: note,
  );
}

enum FriendsNoticeKind { request, share }

class FriendsNotice {
  const FriendsNotice(this.kind, this.username);
  final FriendsNoticeKind kind;
  final String username;
}

const _pageSize = 20;
const _maxNote = 200;

/// Amigos, solicitudes y canciones recibidas. Sin sesión no hace nada.
class FriendsService extends ChangeNotifier {
  FriendsService({
    required Listenable auth,
    required String? Function() currentUid,
    required FriendsData? Function(String uid) dataFor,
    required String? Function(String? avatarPath) avatarUrl,
  }) : _auth = auth,
       _uid = currentUid,
       _dataFor = dataFor,
       _avatarUrl = avatarUrl {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final Listenable _auth;
  final String? Function() _uid;
  final FriendsData? Function(String uid) _dataFor;
  final String? Function(String?) _avatarUrl;

  String? _boundUid;
  FriendsData? _data;
  Future<void> Function()? _unsubscribe;
  int _epoch = 0;
  bool _disposed = false;
  final _notices = StreamController<FriendsNotice>.broadcast();
  final _profiles = <String, FriendUser>{};

  List<FriendUser> friends = const [];
  List<FriendRequestView> incoming = const [];
  List<FriendRequestView> outgoing = const [];
  List<SharedItem> inbox = const [];
  bool hasMoreInbox = false;
  bool loading = false;
  int unseenCount = 0;

  Stream<FriendsNotice> get notices => _notices.stream;
  bool get signedIn => _boundUid != null;

  void _onAuth() {
    final uid = _uid();
    if (uid == _boundUid) return;
    _teardown();
    _boundUid = uid;
    _data = uid == null ? null : _dataFor(uid);
    if (_data == null) {
      _boundUid = null;
      _notify();
      return;
    }
    unawaited(refresh());
    unawaited(_listen(_epoch));
  }

  void _teardown() {
    _epoch++;
    final off = _unsubscribe;
    _unsubscribe = null;
    if (off != null) unawaited(off().catchError((Object _) {}));
    _profiles.clear();
    friends = const [];
    incoming = outgoing = const [];
    inbox = const [];
    hasMoreInbox = false;
    unseenCount = 0;
    loading = false;
  }

  Future<void> _listen(int epoch) async {
    try {
      final off = await _data!.subscribe(
        onRequest: (event, row) => _onRequestEvent(epoch, event, row),
        onShare: (row) => _onShare(epoch, row),
      );
      if (epoch != _epoch) {
        unawaited(off().catchError((Object _) {}));
      } else {
        _unsubscribe = off;
      }
    } catch (_) {
      // Sin tiempo real sigue funcionando con refresh manual.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- carga ----

  Future<void> refresh() async {
    final data = _data, epoch = _epoch, uid = _boundUid;
    if (data == null || uid == null) return;
    loading = true;
    _notify();
    try {
      await _loadRequests(data, uid, epoch);
      await _loadInbox(data, epoch, reset: true);
      final unseen = await data.countUnseen();
      if (epoch == _epoch) unseenCount = unseen;
    } catch (_) {
      // Mantiene lo último que se tenía.
    }
    if (epoch == _epoch) loading = false;
    _notify();
  }

  Future<void> _ensureProfiles(FriendsData data, Iterable<String> ids) async {
    final missing = ids.where((i) => !_profiles.containsKey(i)).toSet();
    if (missing.isEmpty) return;
    for (final row in await data.profilesByIds(missing.toList())) {
      final user = _userFrom(row);
      if (user != null) _profiles[user.id] = user;
    }
  }

  FriendUser? _userFrom(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['username'];
    if (id is! String || name is! String) return null;
    return FriendUser(
      id: id,
      username: name,
      avatarUrl: _avatarUrl(row['avatar_path'] as String?),
    );
  }

  Future<void> _loadRequests(FriendsData data, String uid, int epoch) async {
    final rows = await data.listRequests();
    final others = [
      for (final r in rows) (r['from_id'] == uid ? r['to_id'] : r['from_id']),
    ].whereType<String>();
    await _ensureProfiles(data, others);
    if (epoch != _epoch) return;
    final f = <FriendUser>[];
    final inc = <FriendRequestView>[];
    final out = <FriendRequestView>[];
    for (final r in rows) {
      final mine = r['from_id'] == uid;
      final other = _profiles[(mine ? r['to_id'] : r['from_id']) as String?];
      final status = r['status'];
      final id = r['id'];
      if (other == null || status is! String || id is! String) continue;
      if (status == 'accepted') {
        f.add(other);
      } else if (status == 'pending') {
        final v = FriendRequestView(
          id: id,
          user: other,
          incoming: !mine,
          status: status,
          createdAt: _date(r['created_at']),
        );
        (mine ? out : inc).add(v);
      }
    }
    f.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );
    friends = f;
    incoming = inc;
    outgoing = out;
  }

  Future<void> _loadInbox(
    FriendsData data,
    int epoch, {
    required bool reset,
  }) async {
    final rows = await data.listInbox(
      limit: _pageSize,
      before: reset || inbox.isEmpty ? null : inbox.last.createdAt,
    );
    await _ensureProfiles(
      data,
      rows.map((r) => r['from_id']).whereType<String>(),
    );
    if (epoch != _epoch) return;
    final items = [for (final r in rows) ?_itemFrom(r)];
    inbox = reset ? items : [...inbox, ...items];
    hasMoreInbox = rows.length >= _pageSize;
  }

  Future<void> loadMoreInbox() async {
    final data = _data, epoch = _epoch;
    if (data == null || !hasMoreInbox || loading) return;
    loading = true;
    try {
      await _loadInbox(data, epoch, reset: false);
    } catch (_) {}
    if (epoch == _epoch) loading = false;
    _notify();
  }

  DateTime _date(Object? v) =>
      DateTime.tryParse('$v')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  SharedItem? _itemFrom(Map<String, dynamic> r) {
    final from = _profiles[r['from_id']];
    final id = r['id'];
    final track = trackFromShared(r['track']);
    if (from == null || id is! String || track == null) return null;
    final note = r['note'];
    return SharedItem(
      id: id,
      from: from,
      track: track,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      createdAt: _date(r['created_at']),
      seen: r['seen'] == true,
    );
  }

  // ---- tiempo real ----

  Future<void> _onRequestEvent(
    int epoch,
    String event,
    Map<String, dynamic> row,
  ) async {
    final data = _data, uid = _boundUid;
    if (epoch != _epoch || data == null || uid == null) return;
    try {
      await _loadRequests(data, uid, epoch);
      if (event == 'insert' && row['to_id'] == uid) {
        final name = _profiles[row['from_id']]?.username;
        if (name != null) _emit(FriendsNotice(FriendsNoticeKind.request, name));
      }
    } catch (_) {}
    _notify();
  }

  Future<void> _onShare(int epoch, Map<String, dynamic> row) async {
    final data = _data;
    if (epoch != _epoch || data == null) return;
    try {
      await _ensureProfiles(data, [row['from_id']].whereType<String>());
      if (epoch != _epoch) return;
      final item = _itemFrom(row);
      if (item == null || inbox.any((i) => i.id == item.id)) return;
      inbox = [item, ...inbox];
      if (!item.seen) unseenCount++;
      _emit(FriendsNotice(FriendsNoticeKind.share, item.from.username));
    } catch (_) {}
    _notify();
  }

  void _emit(FriendsNotice n) {
    if (!_notices.isClosed) _notices.add(n);
  }

  // ---- acciones (devuelven mensaje de error o null) ----

  Future<List<FriendUser>> searchUsers(String prefix) async {
    final q = prefix.trim();
    final data = _data, uid = _boundUid;
    if (q.length < 3 || data == null || uid == null) return const [];
    final rows = await data.searchProfiles(q, excludeId: uid);
    return [
      for (final r in rows) ?_userFrom(r),
    ].where((u) => u.id != uid).toList();
  }

  /// Estado de relación con [userId] para la búsqueda.
  String relationTo(String userId) {
    if (friends.any((u) => u.id == userId)) return 'friend';
    if (outgoing.any((r) => r.user.id == userId)) return 'sent';
    if (incoming.any((r) => r.user.id == userId)) return 'incoming';
    return 'none';
  }

  Future<String?> _run(Future<void> Function(FriendsData d) body) async {
    final data = _data;
    if (data == null) return 'Inicia sesión para usar Amigos.';
    try {
      await body(data);
      await refresh();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'Ya hay una solicitud con esa persona.';
      if (e.code == '42501') return 'No tienes permiso para hacer eso.';
      if (e.message.contains('Demasiados')) {
        return 'Demasiados envíos; prueba en un rato.';
      }
      return 'No se pudo completar. Inténtalo de nuevo.';
    } catch (_) {
      return 'Sin conexión. Inténtalo de nuevo.';
    }
  }

  Future<String?> sendRequest(String userId) {
    if (userId == _boundUid) {
      return Future.value('No puedes añadirte a ti mismo.');
    }
    return _run((d) => d.insertRequest(userId));
  }

  Future<String?> accept(String requestId) =>
      _run((d) => d.setRequestStatus(requestId, 'accepted'));

  Future<String?> decline(String requestId) =>
      _run((d) => d.setRequestStatus(requestId, 'declined'));

  /// Cancela una solicitud enviada.
  Future<String?> cancelRequest(String requestId) =>
      _run((d) => d.deleteRequest(requestId));

  Future<String?> removeFriend(String userId) async {
    // La fila de amistad se localiza entre las solicitudes aceptadas.
    return _run((d) async {
      final uid = _boundUid;
      final rows = await d.listRequests();
      for (final r in rows) {
        final pair = {r['from_id'], r['to_id']};
        if (r['status'] == 'accepted' && pair.containsAll([uid, userId])) {
          await d.deleteRequest(r['id'] as String);
        }
      }
    });
  }

  Future<String?> shareTrack(String friendId, Track track, {String? note}) {
    if (track.isLocal) {
      return Future.value('Las canciones locales no se pueden enviar.');
    }
    if (!friends.any((f) => f.id == friendId)) {
      return Future.value('Solo puedes enviar a tus amigos.');
    }
    final n = note?.trim();
    final text = n == null || n.isEmpty
        ? null
        : (n.length > _maxNote ? n.substring(0, _maxNote) : n);
    return _run((d) => d.insertShare(friendId, trackForShare(track), text));
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final data = _data;
    final unseen = {
      for (final i in inbox)
        if (!i.seen && ids.contains(i.id)) i.id,
    };
    if (data == null || unseen.isEmpty) return;
    inbox = [for (final i in inbox) unseen.contains(i.id) ? i.withSeen() : i];
    unseenCount = (unseenCount - unseen.length).clamp(0, 1 << 30);
    _notify();
    try {
      await data.markSeen(unseen.toList());
    } catch (_) {
      // El siguiente refresh reconcilia.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuth);
    _teardown();
    unawaited(_notices.close());
    super.dispose();
  }
}

/// JSON mínimo que viaja: sin ruta local ni estado interno.
Map<String, Object?> trackForShare(Track t) => {
  'id': t.id,
  'title': _cut(t.title, 200),
  'artist': _cut(t.artist, 200),
  'durationMs': t.duration.inMilliseconds,
  'artworkUrl': _httpOrNull(t.artworkUrl),
  'album': t.album == null ? null : _cut(t.album!, 200),
  'genres': t.genres.take(5).map((g) => _cut(g, 40)).toList(),
};

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

String? _httpOrNull(String? url) {
  final u = url == null ? null : Uri.tryParse(url);
  return u != null &&
          (u.scheme == 'https' || u.scheme == 'http') &&
          url!.length <= 1000
      ? url
      : null;
}

/// Reconstruye una pista recibida; es entrada no confiable, así que se valida
/// y se descartan campos peligrosos (ruta local, enlaces no http).
Track? trackFromShared(Object? json) {
  if (json is! Map) return null;
  final id = json['id'], title = json['title'], artist = json['artist'];
  if (id is! String || title is! String || artist is! String) return null;
  if (id.isEmpty || id.length > 64 || title.isEmpty) return null;
  final ms = json['durationMs'];
  return Track(
    id: id,
    title: _cut(title, 200),
    artist: _cut(artist, 200),
    duration: Duration(
      milliseconds: ms is num ? ms.toInt().clamp(0, 86400000) : 0,
    ),
    artworkUrl: _httpOrNull(json['artworkUrl'] as String?),
    album: json['album'] is String ? _cut(json['album'] as String, 200) : null,
    genres:
        (json['genres'] as List?)?.whereType<String>().take(5).toList() ??
        const [],
  );
}
