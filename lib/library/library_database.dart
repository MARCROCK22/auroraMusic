import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';

class LibraryDatabase extends GeneratedDatabase {
  LibraryDatabase(super.executor);

  static Future<LibraryDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return LibraryDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'aurora.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE favorites (track_id TEXT PRIMARY KEY)',
      );
      await customStatement(
        'CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, tracks TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE history (track_id TEXT PRIMARY KEY, played_at INTEGER NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE downloads (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
      );
    },
  );

  Future<List<Track>> readTracks() async =>
      (await customSelect('SELECT data FROM tracks ORDER BY rowid DESC').get())
          .map(
            (row) => Track.fromJson(
              jsonDecode(row.read<String>('data')) as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<void> saveTrack(Track track) => customStatement(
    'INSERT INTO tracks (id,data) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
    [track.id, jsonEncode(track.toJson())],
  );

  Future<Set<String>> readFavorites() async => (await customSelect(
    'SELECT track_id FROM favorites',
  ).get()).map((row) => row.read<String>('track_id')).toSet();

  Future<void> setFavorite(String id, bool selected) => customStatement(
    selected
        ? 'INSERT OR IGNORE INTO favorites VALUES (?)'
        : 'DELETE FROM favorites WHERE track_id=?',
    [id],
  );

  Future<List<MusicPlaylist>> readPlaylists() async =>
      (await customSelect('SELECT * FROM playlists ORDER BY rowid').get())
          .map(
            (row) => MusicPlaylist(
              id: row.read<String>('id'),
              name: row.read<String>('name'),
              trackIds: (jsonDecode(row.read<String>('tracks')) as List)
                  .cast<String>(),
            ),
          )
          .toList();

  Future<void> savePlaylist(MusicPlaylist playlist) => customStatement(
    'INSERT INTO playlists (id,name,tracks) VALUES (?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,tracks=excluded.tracks',
    [playlist.id, playlist.name, jsonEncode(playlist.trackIds)],
  );

  Future<void> deletePlaylist(String id) =>
      customStatement('DELETE FROM playlists WHERE id=?', [id]);

  Future<void> recordPlay(String id) => customStatement(
    'INSERT INTO history VALUES (?,?) ON CONFLICT(track_id) DO UPDATE SET played_at=excluded.played_at',
    [id, DateTime.now().millisecondsSinceEpoch],
  );

  Future<List<String>> readHistory() async => (await customSelect(
    'SELECT track_id FROM history ORDER BY played_at DESC LIMIT 100',
  ).get()).map((row) => row.read<String>('track_id')).toList();

  Future<void> saveDownload(DownloadJob job) => customStatement(
    'INSERT INTO downloads VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
    [
      job.id,
      jsonEncode({
        'track': job.track.toJson(),
        'status': job.status.name,
        'progress': job.progress,
        'error': job.error,
        'localPath': job.localPath,
        'destinationRoot': job.destinationRoot,
      }),
    ],
  );

  Future<List<DownloadJob>> readDownloads() async =>
      (await customSelect(
        'SELECT id,data FROM downloads ORDER BY rowid DESC',
      ).get()).map((row) {
        final data =
            jsonDecode(row.read<String>('data')) as Map<String, dynamic>;
        final status = DownloadStatus.values.byName(data['status'] as String);
        final interrupted =
            status == DownloadStatus.downloading ||
            status == DownloadStatus.queued;
        return DownloadJob(
          id: row.read<String>('id'),
          track: Track.fromJson(data['track'] as Map<String, dynamic>),
          status: interrupted ? DownloadStatus.failed : status,
          progress: (data['progress'] as num).toDouble(),
          error: interrupted
              ? 'Descarga interrumpida. Puedes reintentar.'
              : data['error'] as String?,
          localPath: data['localPath'] as String?,
          destinationRoot: data['destinationRoot'] as String?,
        );
      }).toList();

  Future<void> deleteDownload(String id) =>
      customStatement('DELETE FROM downloads WHERE id=?', [id]);
}
