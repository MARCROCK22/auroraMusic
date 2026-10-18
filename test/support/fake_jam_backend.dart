import 'dart:async';
import 'dart:convert';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/transport/jam_transport.dart';

/// Servidor falso en memoria: imita lo que valida el SQL real (pertenencia,
/// silencio, bloqueos, límites de invitados). No prueba Supabase.
class FakeJamBackend {
  final rooms = <String, FakeRoom>{};
  var _next = 0;
  var _seq = 0;
  int cmdCount = 0;

  FakeJamTransport transport() => FakeJamTransport(this, 'u${++_next}');
}

int _tick = 0;

class _Member {
  _Member(this.uid, this.name, this.role)
    : joinedAt = DateTime.fromMillisecondsSinceEpoch(1000000 + _tick++);
  final String uid;
  String name;
  JamRole role;
  bool muted = false;
  final DateTime joinedAt;
}

class FakeRoom {
  FakeRoom(this.code, this.host);
  String code;
  String host;
  bool open = true;
  int maxGuests = 15;
  final members = <String, _Member>{};
  final banned = <String>{};
  final down = <FakeChannel>[];
  final up = <FakeChannel>[];
  bool closed = false;
}

class FakeChannel implements JamChannel {
  FakeChannel(this.room, this.uid, this.asHost);
  final FakeRoom room;
  final String uid;
  final bool asHost;
  final _in = StreamController<JamEnvelope>.broadcast();
  final _pres = StreamController<JamPresenceEvent>.broadcast();
  final _on = StreamController<bool>.broadcast();
  bool _online = true;
  bool tracked = false;
  @override
  Stream<JamEnvelope> get incoming => _in.stream;
  @override
  Stream<JamPresenceEvent> get presence => _pres.stream;
  @override
  Stream<bool> get online => _on.stream;
  @override
  bool get isOnline => _online;

  void deliver(JamEnvelope e) {
    if (_online) scheduleMicrotask(() => _in.isClosed ? null : _in.add(e));
  }

  void setOnline(bool v) {
    if (_online == v) return;
    _online = v;
    _on.add(v);
    if (tracked) {
      for (final c in room.down) {
        if (c != this) c._pres.add(JamPresenceEvent(uid, joined: v));
      }
    }
  }

  @override
  Future<void> track() async {
    if (asHost) room.up.add(this);
    room.down.add(this);
    tracked = true;
    for (final c in room.down) {
      if (c != this) c._pres.add(JamPresenceEvent(uid, joined: true));
    }
  }

  @override
  Future<void> send(JamEnvelope e) async {
    if (!_online) throw JamRemoteException('network');
    final me = room.members[uid];
    if (!asHost || me == null || me.role == JamRole.guest) {
      throw JamRemoteException('forbidden');
    }
    for (final c in [...room.down]) {
      if (c != this) c.deliver(e);
    }
  }

  @override
  Future<void> close() async {
    room.down.remove(this);
    room.up.remove(this);
    if (tracked) {
      for (final c in room.down) {
        c._pres.add(JamPresenceEvent(uid, joined: false));
      }
    }
    await _in.close();
  }
}

class FakeJamTransport implements JamTransport {
  FakeJamTransport(this.backend, this.uid);
  final FakeJamBackend backend;
  final String uid;
  bool offline = false;
  @override
  bool get available => true;
  @override
  String? get unavailableReason => null;

  void _net() {
    if (offline) throw JamRemoteException('network');
  }

  FakeRoom _room(String code) {
    final r = backend.rooms[code];
    if (r == null) throw JamRemoteException('invalid');
    if (r.closed) throw JamRemoteException('expired');
    return r;
  }

  _Member _me(FakeRoom r) {
    final m = r.members[uid];
    if (m == null) throw JamRemoteException('forbidden');
    return m;
  }

  @override
  Future<String> signIn() async {
    _net();
    return uid;
  }

  JamRoomInfo _info(FakeRoom r) => JamRoomInfo(
    code: r.code,
    hostUid: r.host,
    expiresAt: DateTime.now().add(const Duration(hours: 12)),
    role: r.members[uid]?.role ?? JamRole.guest,
  );

  @override
  Future<JamRoomInfo> createRoom({
    required String name,
    required String device,
  }) async {
    _net();
    if (backend.rooms.values.any((r) => r.host == uid && !r.closed)) {
      throw JamRemoteException('active');
    }
    final n = backend._seq++;
    final code = 'ABCD${2 + n % 8}${2 + (n ~/ 8) % 8}';
    final r = FakeRoom(code, uid)
      ..members[uid] = _Member(uid, name, JamRole.host);
    backend.rooms[code] = r;
    return _info(r);
  }

  @override
  Future<JamRoomInfo> joinRoom({
    required String code,
    required String name,
    required String device,
  }) async {
    _net();
    final r = _room(code);
    if (r.banned.contains(uid)) throw JamRemoteException('banned');
    if (!r.members.containsKey(uid)) {
      if (!r.open) throw JamRemoteException('closed');
      if (r.members.length > r.maxGuests) throw JamRemoteException('full');
      r.members[uid] = _Member(uid, name, JamRole.guest);
    }
    return _info(r);
  }

  @override
  Future<List<JamMemberRow>> members(String code) async {
    _net();
    final r = _room(code);
    _me(r);
    return [
      for (final m in r.members.values)
        JamMemberRow(
          uid: m.uid,
          name: m.name,
          role: m.role,
          muted: m.muted,
          joinedAt: m.joinedAt,
        ),
    ];
  }

  @override
  Future<void> heartbeat(String code, {bool activity = false}) async => _net();

  @override
  Future<void> command(
    String code,
    String kind,
    Map<String, Object?> payload,
  ) async {
    _net();
    backend.cmdCount++;
    final r = _room(code);
    final m = _me(r);
    if (m.muted && kind == 'add') throw JamRemoteException('muted');
    final text = jsonEncode({'kind': kind, ...payload});
    if (text.length > 8192) throw JamRemoteException('payload');
    for (final c in [...r.up]) {
      c.deliver(JamEnvelope(from: uid, to: '*', text: text));
    }
  }

  @override
  Future<void> leave(String code) async {
    backend.rooms[code]?.members.remove(uid);
  }

  @override
  Future<void> closeRoom(String code) async {
    final r = _room(code);
    if (r.host != uid) throw JamRemoteException('forbidden');
    r.closed = true;
  }

  FakeRoom _hostRoom(String code) {
    final r = _room(code);
    if (r.host != uid) throw JamRemoteException('forbidden');
    return r;
  }

  @override
  Future<void> kick(String code, String target, {bool ban = false}) async {
    final r = _hostRoom(code);
    r.members.remove(target);
    if (ban) r.banned.add(target);
  }

  @override
  Future<void> setMuted(String code, String target, bool muted) async =>
      _hostRoom(code).members[target]?.muted = muted;

  @override
  Future<void> setCoHost(String code, String target, bool coHost) async =>
      _hostRoom(code).members[target]?.role = coHost
      ? JamRole.coHost
      : JamRole.guest;

  @override
  Future<void> setAccess(
    String code, {
    required bool open,
    required int maxGuests,
  }) async {
    final r = _hostRoom(code);
    r.open = open;
    r.maxGuests = maxGuests;
  }

  @override
  Future<String> rotateCode(String code) async {
    final r = _hostRoom(code);
    backend.rooms.remove(code);
    r.code = 'ZZZZ${2 + backend._seq++ % 8}2';
    backend.rooms[r.code] = r;
    return r.code;
  }

  @override
  Future<void> transferHost(String code, String target) async {
    final r = _hostRoom(code);
    r.members[uid]!.role = JamRole.coHost;
    r.members[target]!.role = JamRole.host;
    r.host = target;
  }

  @override
  Future<JamRoomInfo> claimHost(String code) async {
    final r = _room(code);
    if (r.host != uid) {
      final hostPresent = r.down.any((c) => c.uid == r.host && c.isOnline);
      if (hostPresent) throw JamRemoteException('forbidden');
      final others = r.members.values.where((m) => m.uid != r.host).toList()
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      if (others.isEmpty || others.first.uid != uid) {
        throw JamRemoteException('forbidden');
      }
      r.members[r.host]?.role = JamRole.guest;
      r.members[uid]!.role = JamRole.host;
      r.host = uid;
    }
    return _info(r);
  }

  final channels = <FakeChannel>[];
  @override
  JamChannel openChannel(String code, {required bool asHost}) {
    final c = FakeChannel(_room(code), uid, asHost);
    channels.add(c);
    return c;
  }

  /// Corta o restablece la red de este dispositivo.
  void cut(bool value) {
    offline = value;
    for (final c in channels) {
      c.setOnline(!value);
    }
  }
}
