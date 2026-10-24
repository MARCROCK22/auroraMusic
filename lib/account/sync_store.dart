import 'dart:convert';
import 'package:drift/drift.dart';

import '../core/models.dart';
import '../library/library_database.dart';

/// Marca local de un elemento sincronizable (tabla sync_meta).
class SyncMeta {
  const SyncMeta(this.updatedAt, this.deleted, this.dirty);
  final int updatedAt; // ms desde epoch
  final bool deleted, dirty;
}

/// Claves del servidor que ganan sobre lo local: no hay copia local, o la
/// remota es más reciente (última escritura gana). Lo local pendiente que no
/// aparece aquí es lo que se sube. Las lápidas compiten igual que el resto.
Set<String> remoteWinners(
  Map<String, SyncMeta> local,
  Map<String, int> remote,
) => {
  for (final e in remote.entries)
    if (local[e.key] == null || e.value > local[e.key]!.updatedAt) e.key,
};

const _kinds = ['favorites', 'playlists', 'history', 'taste'];

/// Acceso a la base para sincronizar. Todo lo que escribe aquí es «ya
/// sincronizado» (dirty=0); los cambios del usuario pasan por LibraryDatabase.
extension SyncStore on LibraryDatabase {
  /// Elementos locales anteriores a la cuenta: ts 0 para que, ante conflicto,
  /// gane el servidor, y el resto se suba (unión).
  Future<void> seedSyncMeta() async {
    for (final q in const [
      "SELECT 'favorites', track_id FROM favorites",
      "SELECT 'playlists', id FROM playlists",
      "SELECT 'history', track_id FROM history",
      "SELECT 'taste', '1' FROM taste_profile",
    ]) {
      await customStatement(
        'INSERT OR IGNORE INTO sync_meta (kind,key,updated_at,deleted,dirty) '
        'SELECT *, 0, 0, 1 FROM ($q)',
      );
    }
  }

  Future<void> markAllSyncDirty() =>
      customStatement('UPDATE sync_meta SET dirty=1');

  Future<Map<String, SyncMeta>> readSyncMeta(String kind) async => {
    for (final r in await customSelect(
      'SELECT key,updated_at,deleted,dirty FROM sync_meta WHERE kind=?',
      variables: [Variable<String>(kind)],
    ).get())
      r.read<String>('key'): SyncMeta(
        r.read<int>('updated_at'),
        r.read<int>('deleted') == 1,
        r.read<int>('dirty') == 1,
      ),
  };

  /// Claves pendientes de subir (el historial se limita a las 500 más nuevas).
  Future<List<String>> dirtySyncKeys(String kind) async => (await customSelect(
    'SELECT key FROM sync_meta WHERE kind=? AND dirty=1 '
    'ORDER BY updated_at DESC LIMIT 500',
    variables: [Variable<String>(kind)],
  ).get()).map((r) => r.read<String>('key')).toList();

  Future<void> setSyncMeta(
    String kind,
    String key,
    int ts,
    bool deleted,
  ) => customStatement(
    'INSERT INTO sync_meta VALUES (?,?,?,?,0) ON CONFLICT(kind,key) DO UPDATE '
    'SET updated_at=?, deleted=?, dirty=0',
    [kind, key, ts, deleted ? 1 : 0, ts, deleted ? 1 : 0],
  );

  /// Quita «pendiente» solo si nadie lo cambió mientras se subía.
  Future<void> clearSyncDirty(
    String kind,
    String key,
    int sentTs,
    int serverTs,
  ) => customStatement(
    'UPDATE sync_meta SET dirty=0, updated_at=? WHERE kind=? AND key=? '
    'AND updated_at=?',
    [serverTs, kind, key, sentTs],
  );

  Future<Map<String, dynamic>?> _trackJson(String id) async {
    final row = await customSelect(
      'SELECT data FROM tracks WHERE id=?',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
    // La ruta local no tiene sentido en otro dispositivo (y es privada).
    return json..remove('localPath');
  }

  Future<void> _saveTrackIfAbsent(Object? raw) async {
    if (raw is! Map || raw['title'] is! String || raw['artist'] is! String) {
      return;
    }
    final track = Track.fromJson(
      Map<String, dynamic>.from(raw)..remove('localPath'),
    );
    await customStatement(
      'INSERT OR IGNORE INTO tracks (id,data) VALUES (?,?)',
      [track.id, jsonEncode(track.toJson())],
    );
  }

  /// Fila a subir para [key], o null si no se puede (p. ej. pista desconocida).
  Future<Map<String, dynamic>?> buildSyncRow(
    String kind,
    String key,
    bool deleted,
  ) async {
    switch (kind) {
      case 'favorites':
        final track = await _trackJson(key);
        if (track == null && !deleted) return null;
        return {
          'track_id': key,
          'track': track ?? {'id': key},
          'deleted': deleted,
        };
      case 'playlists':
        if (deleted) {
          return {
            'id': key,
            'name': '-',
            'tracks': <Object>[],
            'deleted': true,
          };
        }
        final row = await customSelect(
          'SELECT name,tracks FROM playlists WHERE id=?',
          variables: [Variable<String>(key)],
        ).getSingleOrNull();
        if (row == null) return null;
        final ids = (jsonDecode(row.read<String>('tracks')) as List)
            .cast<String>();
        var items = <Object>[
          for (final id in ids) await _trackJson(id) ?? {'id': id},
        ];
        if (jsonEncode(items).length > 500000) {
          items = [
            for (final id in ids) {'id': id},
          ];
        }
        return {
          'id': key,
          'name': row.read<String>('name'),
          'tracks': items,
          'deleted': false,
        };
      case 'history':
        final track = await _trackJson(key);
        final row = await customSelect(
          'SELECT played_at FROM history WHERE track_id=?',
          variables: [Variable<String>(key)],
        ).getSingleOrNull();
        if (track == null || row == null) return null;
        return {
          'track_id': key,
          'track': track,
          'played_at': DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('played_at'),
            isUtc: true,
          ).toIso8601String(),
        };
      case 'taste':
        final row = await customSelect(
          'SELECT dims,vector FROM taste_profile WHERE id=1',
        ).getSingleOrNull();
        if (row == null) return null;
        return {
          'profile': {
            'dims': row.read<int>('dims'),
            'v': base64Encode(row.read<Uint8List>('vector')),
          },
        };
    }
    return null;
  }

  /// Aplica una fila remota ya validada como ganadora. Devuelve false si estaba mal formada.
  Future<bool> applyRemoteRow(String kind, Map<String, dynamic> r) async {
    try {
      final deleted = r['deleted'] == true;
      switch (kind) {
        case 'favorites':
          final id = r['track_id'] as String;
          if (deleted) {
            await customStatement('DELETE FROM favorites WHERE track_id=?', [
              id,
            ]);
          } else {
            await _saveTrackIfAbsent(r['track']);
            await customStatement(
              'INSERT OR IGNORE INTO favorites VALUES (?)',
              [id],
            );
          }
        case 'playlists':
          final id = r['id'] as String;
          if (deleted) {
            await customStatement('DELETE FROM playlists WHERE id=?', [id]);
          } else {
            final items = (r['tracks'] as List).whereType<Map>().toList();
            for (final t in items) {
              await _saveTrackIfAbsent(t);
            }
            await customStatement(
              'INSERT INTO playlists (id,name,tracks) VALUES (?,?,?) ON CONFLICT(id) '
              'DO UPDATE SET name=excluded.name,tracks=excluded.tracks',
              [
                id,
                (r['name'] as String).trim(),
                jsonEncode([for (final t in items) t['id'] as String]),
              ],
            );
          }
        case 'history':
          final id = r['track_id'] as String;
          await _saveTrackIfAbsent(r['track']);
          await customStatement(
            'INSERT INTO history VALUES (?,?) ON CONFLICT(track_id) DO UPDATE SET '
            'played_at=excluded.played_at',
            [
              id,
              DateTime.parse(r['played_at'] as String).millisecondsSinceEpoch,
            ],
          );
        case 'taste':
          final p = r['profile'] as Map;
          final dims = p['dims'] as int;
          final bytes = base64Decode(p['v'] as String);
          if (dims < 1 || dims > 4096 || bytes.length != dims * 4) return false;
          await customStatement(
            'INSERT INTO taste_profile VALUES (1,?,?,?) ON CONFLICT(id) DO UPDATE SET '
            'dims=excluded.dims, vector=excluded.vector, updated_at=excluded.updated_at',
            [
              dims,
              Uint8List.fromList(bytes),
              DateTime.now().millisecondsSinceEpoch,
            ],
          );
        default:
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

List<String> get syncKinds => _kinds;
