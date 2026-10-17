import 'dart:async';
import 'package:supabase/supabase.dart';
import '../jam_models.dart';
import 'jam_config.dart';
import 'jam_transport.dart';

/// Transporte Supabase. Solo usa la clave anónima y llama RPC `jam_*`
/// (docs/jam_supabase.sql); nunca lee ni escribe tablas. Sin probar contra un
/// proyecto real: ver docs/jam_supabase.md.
class SupabaseJamTransport implements JamTransport {
  SupabaseJamTransport(this._config);
  final JamSupabaseConfig? _config;
  SupabaseClient? _client;

  @override
  bool get available => _config != null;
  @override
  String? get unavailableReason =>
      _config == null ? JamSupabaseConfig.environmentProblem : null;

  SupabaseClient get _c {
    final config = _config;
    if (config == null) throw JamRemoteException('network');
    return _client ??= SupabaseClient(config.url, config.anonKey);
  }

  @override
  Future<String> signIn() async {
    try {
      final auth = _c.auth;
      if (auth.currentUser == null) await auth.signInAnonymously();
      final id = auth.currentUser?.id;
      if (id == null) throw JamRemoteException('network');
      return id;
    } on JamRemoteException {
      rethrow;
    } catch (_) {
      throw JamRemoteException('network');
    }
  }

  Future<Object?> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      return await _c.rpc<Object?>(fn, params: params);
    } on PostgrestException catch (failure) {
      // El servidor responde `jam:<código>`; cualquier otro texto no se muestra.
      final match = RegExp(r'^jam:([a-z]{3,12})$').firstMatch(failure.message);
      throw JamRemoteException(match?.group(1) ?? 'unknown');
    } on JamException {
      rethrow;
    } catch (_) {
      throw JamRemoteException('network');
    }
  }

  JamRoomInfo _room(Object? raw) {
    try {
      final m = jamMap(raw);
      if (m['error'] is String) {
        throw JamRemoteException(
          RegExp(r'^[a-z]{3,12}$').hasMatch(m['error'] as String)
              ? m['error'] as String
              : 'unknown',
        );
      }
      return JamRoomInfo(
        code: jamNormalizeCode(m['code'] as String)!,
        hostUid: jamIdentifier(m['host']),
        expiresAt: DateTime.parse(m['expires_at'] as String).toLocal(),
        role: JamRole.values.firstWhere(
          (r) => r.name == m['role'],
          orElse: () => JamRole.guest,
        ),
      );
    } on JamRemoteException {
      rethrow;
    } catch (_) {
      throw JamRemoteException('unknown');
    }
  }

  @override
  Future<JamRoomInfo> createRoom({
    required String name,
    required String device,
  }) async =>
      _room(await _rpc('jam_create', {'p_name': name, 'p_device': device}));

  @override
  Future<JamRoomInfo> joinRoom({
    required String code,
    required String name,
    required String device,
  }) async => _room(
    await _rpc('jam_join', {
      'p_code': code,
      'p_name': name,
      'p_device': device,
    }),
  );

  @override
  Future<List<JamMemberRow>> members(String code) async {
    final raw = await _rpc('jam_members', {'p_code': code});
    if (raw is! List) throw JamRemoteException('unknown');
    return [
      for (final item in raw)
        if (item is Map)
          JamMemberRow(
            uid: item['uid'] as String,
            name: jamCleanName(item['name'] as String? ?? ''),
            role: JamRole.values.firstWhere(
              (r) => r.name == item['role'],
              orElse: () => JamRole.guest,
            ),
            muted: item['muted'] == true,
            joinedAt: DateTime.parse(item['joined_at'] as String),
          ),
    ];
  }

  @override
  Future<void> heartbeat(String code, {bool activity = false}) async {
    await _rpc('jam_heartbeat', {'p_code': code, 'p_activity': activity});
  }

  @override
  Future<void> command(
    String code,
    String kind,
    Map<String, Object?> payload,
  ) async {
    await _rpc('jam_cmd', {
      'p_code': code,
      'p_kind': kind,
      'p_payload': payload,
    });
  }

  @override
  Future<void> leave(String code) async => _rpc('jam_leave', {'p_code': code});
  @override
  Future<void> closeRoom(String code) async =>
      _rpc('jam_close', {'p_code': code});
  @override
  Future<void> kick(String code, String uid, {bool ban = false}) async =>
      _rpc('jam_kick', {'p_code': code, 'p_uid': uid, 'p_ban': ban});
  @override
  Future<void> setMuted(String code, String uid, bool muted) async =>
      _rpc('jam_mute', {'p_code': code, 'p_uid': uid, 'p_muted': muted});
  @override
  Future<void> setCoHost(String code, String uid, bool coHost) async =>
      _rpc('jam_cohost', {'p_code': code, 'p_uid': uid, 'p_on': coHost});
  @override
  Future<void> setAccess(
    String code, {
    required bool open,
    required int maxGuests,
  }) async =>
      _rpc('jam_access', {'p_code': code, 'p_open': open, 'p_max': maxGuests});
  @override
  Future<String> rotateCode(String code) async {
    final raw = await _rpc('jam_rotate', {'p_code': code});
    final next = raw is String ? jamNormalizeCode(raw) : null;
    if (next == null) throw JamRemoteException('unknown');
    return next;
  }

  @override
  Future<void> transferHost(String code, String uid) async =>
      _rpc('jam_transfer', {'p_code': code, 'p_uid': uid});
  @override
  Future<JamRoomInfo> claimHost(String code) async =>
      _room(await _rpc('jam_claim_host', {'p_code': code}));

  @override
  JamChannel openChannel(String code, {required bool asHost}) =>
      _SupabaseChannel(_c, code, asHost: asHost);
}

/// Canales privados `jam:<código>:down` (publican anfitrión/coanfitriones, lee
/// todo miembro) y `jam:<código>:up` (publica solo el servidor; lee el
/// anfitrión). Las políticas RLS de realtime.messages lo aplican.
class _SupabaseChannel implements JamChannel {
  _SupabaseChannel(this._c, this._code, {required this.asHost});
  final SupabaseClient _c;
  final String _code;
  final bool asHost;
  final _in = StreamController<JamEnvelope>.broadcast();
  final _presence = StreamController<JamPresenceEvent>.broadcast();
  final _online = StreamController<bool>.broadcast();
  RealtimeChannel? _down, _up;
  bool _isOnline = false, _closed = false;
  final _status = <RealtimeChannel, bool>{};

  @override
  Stream<JamEnvelope> get incoming => _in.stream;
  @override
  Stream<JamPresenceEvent> get presence => _presence.stream;
  @override
  Stream<bool> get online => _online.stream;
  @override
  bool get isOnline => _isOnline;

  void _state(RealtimeChannel channel, bool ok) {
    _status[channel] = ok;
    final all =
        _status.length == (asHost ? 2 : 1) && _status.values.every((v) => v);
    if (all != _isOnline && !_closed) {
      _isOnline = all;
      _online.add(all);
    }
  }

  void _listen(RealtimeChannel channel) {
    channel.onBroadcast(
      event: 'm',
      callback: (raw) {
        final body = raw['payload'] ?? raw;
        final envelope = JamEnvelope.tryParse(body);
        if (envelope != null && !_closed) _in.add(envelope);
      },
    );
  }

  @override
  Future<void> track() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null || _closed) throw JamRemoteException('network');
    final ready = Completer<void>();
    RealtimeChannel build(String suffix) {
      final channel = _c.channel(
        'jam:$_code:$suffix',
        opts: RealtimeChannelConfig(private: true, key: uid, enabled: true),
      );
      _listen(channel);
      return channel;
    }

    final down = _down = build('down');
    down.onPresenceLeave((p) {
      for (final left in p.leftPresences) {
        final id = left.payload['uid'];
        if (id is String) _presence.add(JamPresenceEvent(id, joined: false));
      }
    });
    down.onPresenceJoin((p) {
      for (final joined in p.newPresences) {
        final id = joined.payload['uid'];
        if (id is String) _presence.add(JamPresenceEvent(id, joined: true));
      }
    });
    final channels = [down];
    if (asHost) channels.add(_up = build('up'));
    var pending = channels.length;
    for (final channel in channels) {
      channel.subscribe((status, error) {
        final ok = status == RealtimeSubscribeStatus.subscribed;
        _state(channel, ok);
        if (ok && --pending == 0 && !ready.isCompleted) ready.complete();
        if (!ok &&
            !ready.isCompleted &&
            status != RealtimeSubscribeStatus.closed) {
          ready.completeError(JamRemoteException('network'));
        }
      });
    }
    await ready.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw JamRemoteException('network'),
    );
    await down.track({'uid': uid});
  }

  @override
  Future<void> send(JamEnvelope envelope) async {
    final down = _down;
    if (!asHost || down == null || !_isOnline) {
      throw JamRemoteException('network');
    }
    await down.sendBroadcastMessage(event: 'm', payload: envelope.toJson());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final channel in [?_down, ?_up]) {
      try {
        await _c.removeChannel(channel);
      } catch (_) {}
    }
    await _in.close();
    await _presence.close();
    await _online.close();
  }
}
