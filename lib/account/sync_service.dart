import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library_database.dart';
import 'account_service.dart';
import 'sync_store.dart';

/// Acceso al servidor (falsificable en pruebas).
abstract class SyncRemote {
  /// Filas de [table] con updated_at >= [since] (el borde se repite a propósito:
  /// un lote comparte marca de tiempo y puede partirse entre páginas) (texto tal cual lo devolvió el servidor).
  Future<List<Map<String, dynamic>>> pull(
    String table,
    String? since,
    int limit,
  );

  /// Sube [rows] y devuelve, por fila, su clave y el updated_at del servidor.
  Future<List<Map<String, dynamic>>> push(
    String table,
    String conflict,
    List<Map<String, dynamic>> rows,
  );
}

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._accounts);
  final AccountService _accounts;

  String get _uid => _accounts.client!.auth.currentUser!.id;

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table,
    String? since,
    int limit,
  ) {
    var q = _accounts.client!.from(table).select().eq('user_id', _uid);
    if (since != null) q = q.gte('updated_at', since);
    return q.order('updated_at').limit(limit);
  }

  @override
  Future<List<Map<String, dynamic>>> push(
    String table,
    String conflict,
    List<Map<String, dynamic>> rows,
  ) => _accounts.client!
      .from(table)
      .upsert([
        for (final r in rows) {...r, 'user_id': _uid},
      ], onConflict: conflict)
      .select('${conflict.replaceFirst('user_id,', '')},updated_at');
}

class _Kind {
  const _Kind(this.table, this.key);
  final String table, key; // key = columna clave (taste: user_id)
  String get conflict => key == 'user_id' ? 'user_id' : 'user_id,$key';
}

const _kindDefs = {
  'favorites': _Kind('user_favorites', 'track_id'),
  'playlists': _Kind('user_playlists', 'id'),
  'history': _Kind('user_history', 'track_id'),
  'taste': _Kind('user_taste', 'user_id'),
};

class SyncService extends ChangeNotifier {
  SyncService({
    required this.accounts,
    required this.database,
    required this.preferences,
    required this.onPulled,
    SyncRemote? remote,
    this.debounce = const Duration(seconds: 3),
  }) : _remote = remote ?? SupabaseSyncRemote(accounts);

  final AccountService accounts;
  final LibraryDatabase database;
  final SharedPreferences preferences;

  /// Se llama cuando la sincronización cambió datos locales (recargar memoria).
  final Future<void> Function() onPulled;
  final Duration debounce;
  final SyncRemote _remote;

  bool syncing = false;
  DateTime? lastSync;
  String? lastError;
  Timer? _timer;
  String? _lastUid;
  bool _again = false;

  void start() {
    database.onLocalChange = _schedule;
    accounts.addListener(_onAccount);
    _onAccount();
  }

  void _onAccount() {
    final uid = accounts.profile?.id;
    if (uid == _lastUid) return;
    _lastUid = uid;
    if (uid == null) {
      _timer?.cancel();
      lastSync = null;
      notifyListeners();
    } else {
      unawaited(syncNow());
    }
  }

  void _schedule() {
    if (_lastUid == null) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(syncNow()));
  }

  Future<void> syncNow() async {
    final uid = accounts.profile?.id;
    if (uid == null) return;
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    lastError = null;
    notifyListeners();
    try {
      await runSync(uid);
      lastSync = DateTime.now();
    } catch (e) {
      lastError = mapAccountError(e).message;
    } finally {
      syncing = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      _schedule();
    }
  }

  /// Un ciclo completo: bajar lo nuevo, resolver, subir lo pendiente.
  @visibleForTesting
  Future<void> runSync(String uid) async {
    if (preferences.getString('sync.lastUser') != uid) {
      // Otra cuenta en este dispositivo: se une lo local con lo de esa cuenta.
      await database.markAllSyncDirty();
    }
    await database.seedSyncMeta();
    var changed = false;
    for (final kind in syncKinds) {
      changed |= await _pull(uid, kind);
    }
    for (final kind in syncKinds) {
      await _push(kind);
    }
    await preferences.setString('sync.lastUser', uid);
    if (changed) await onPulled();
  }

  String _wmKey(String uid, String kind) => 'sync.wm.$uid.$kind';

  Future<bool> _pull(String uid, String kind) async {
    final def = _kindDefs[kind]!;
    var since = preferences.getString(_wmKey(uid, kind));
    var changed = false;
    while (true) {
      final rows = await _remote.pull(def.table, since, 500);
      if (rows.isEmpty) break;
      final remote = {
        for (final r in rows)
          _keyOf(def, uid, r): DateTime.parse(
            r['updated_at'] as String,
          ).millisecondsSinceEpoch,
      };
      final meta = await database.readSyncMeta(kind);
      final winners = remoteWinners(meta, remote);
      for (final r in rows) {
        final key = _keyOf(def, uid, r);
        if (!winners.contains(key)) continue;
        if (await database.applyRemoteRow(kind, r)) {
          await database.setSyncMeta(
            kind,
            key,
            remote[key]!,
            r['deleted'] == true,
          );
          changed = true;
        }
      }
      since = rows.last['updated_at'] as String;
      await preferences.setString(_wmKey(uid, kind), since);
      if (rows.length < 500) break;
    }
    return changed;
  }

  String _keyOf(_Kind def, String uid, Map<String, dynamic> r) =>
      def.key == 'user_id' ? '1' : r[def.key] as String;

  Future<void> _push(String kind) async {
    final def = _kindDefs[kind]!;
    final meta = await database.readSyncMeta(kind);
    final keys = await database.dirtySyncKeys(kind);
    for (var i = 0; i < keys.length; i += 100) {
      final sent = <String, int>{};
      final rows = <Map<String, dynamic>>[];
      for (final key in keys.skip(i).take(100)) {
        final m = meta[key];
        if (m == null) continue;
        final row = await database.buildSyncRow(kind, key, m.deleted);
        if (row == null) continue;
        rows.add(row);
        sent[key] = m.updatedAt;
      }
      if (rows.isEmpty) continue;
      final back = await _remote.push(def.table, def.conflict, rows);
      for (final r in back) {
        final key = _keyOf(def, '', r);
        final ts = sent[key];
        if (ts == null) continue;
        await database.clearSyncDirty(
          kind,
          key,
          ts,
          DateTime.parse(r['updated_at'] as String).millisecondsSinceEpoch,
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    accounts.removeListener(_onAccount);
    database.onLocalChange = null;
    super.dispose();
  }
}
