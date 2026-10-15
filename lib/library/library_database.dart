import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
  int get schemaVersion => 2;
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
      await _createVectorTables();
    },
    onUpgrade: (_, from, _) async {
      if (from < 2) await _createVectorTables();
    },
  );

  Future<void> _createVectorTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS track_vectors (track_key TEXT PRIMARY KEY, '
      'track TEXT NOT NULL, dims INTEGER NOT NULL, vector BLOB NOT NULL, '
      'updated_at INTEGER NOT NULL)',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS taste_profile (id INTEGER PRIMARY KEY '
      'CHECK (id = 1), dims INTEGER NOT NULL, vector BLOB NOT NULL, '
      'updated_at INTEGER NOT NULL)',
    );
  }

  static const maxTrackVectors = 5000;
  static Uint8List _bytes(Float32List vector) => Uint8List.fromList(
    vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes),
  );
  // Copy first: SQLite blobs are not guaranteed to be 4-byte aligned.
  static Float32List _floats(Uint8List bytes) =>
      Float32List.view(Uint8List.fromList(bytes).buffer, 0, bytes.length ~/ 4);

  /// Stores track embeddings keyed by track ID, keeping the newest
  /// [maxTrackVectors] rows.
  Future<void> upsertTrackVectors(
    Iterable<({Track track, Float32List vector})> entries,
  ) async {
    final items = entries.toList();
    if (items.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      for (final item in items) {
        await customStatement(
          'INSERT INTO track_vectors VALUES (?,?,?,?,?) ON CONFLICT(track_key) '
          'DO UPDATE SET track=excluded.track, dims=excluded.dims, '
          'vector=excluded.vector, updated_at=excluded.updated_at',
          [
            item.track.id,
            jsonEncode(item.track.toJson()),
            item.vector.length,
            _bytes(item.vector),
            now,
          ],
        );
      }
      await customStatement(
        'DELETE FROM track_vectors WHERE track_key NOT IN (SELECT track_key '
        'FROM track_vectors ORDER BY updated_at DESC LIMIT $maxTrackVectors)',
      );
    });
  }

  Future<int> countTrackVectors() async => (await customSelect(
    'SELECT COUNT(*) AS c FROM track_vectors',
  ).getSingle()).read<int>('c');

  /// Cosine nearest neighbours of [query], best first.
  // shortcut: brute-force scan of every row; fine for a few thousand tracks,
  // move to an ANN index (or sqlite-vec) if the store grows far beyond that.
  Future<List<({Track track, double score})>> nearestTracks(
    List<double> query, {
    int k = 20,
    Set<String> exclude = const {},
  }) async {
    final rows = await customSelect(
      'SELECT track_key, track, vector FROM track_vectors WHERE dims=?',
      variables: [Variable<int>(query.length)],
    ).get();
    var queryNorm = 0.0;
    for (final value in query) {
      queryNorm += value * value;
    }
    if (queryNorm == 0) return const [];
    final scored = <({QueryRow row, double score})>[];
    for (final row in rows) {
      if (exclude.contains(row.read<String>('track_key'))) continue;
      final vector = _floats(row.read<Uint8List>('vector'));
      var dot = 0.0, norm = 0.0;
      for (var i = 0; i < vector.length; i++) {
        dot += query[i] * vector[i];
        norm += vector[i] * vector[i];
      }
      if (norm == 0) continue;
      scored.add((row: row, score: dot / math.sqrt(queryNorm * norm)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    // Decode JSON only for the top k, not for every stored vector.
    return [
      for (final entry in scored.take(k))
        (
          track: Track.fromJson(
            jsonDecode(entry.row.read<String>('track')) as Map<String, dynamic>,
          ),
          score: entry.score,
        ),
    ];
  }

  Future<Float32List?> readTasteProfile() async {
    final row = await customSelect(
      'SELECT vector FROM taste_profile WHERE id=1',
    ).getSingleOrNull();
    return row == null ? null : _floats(row.read<Uint8List>('vector'));
  }

  Future<void> saveTasteProfile(Float32List vector) => customStatement(
    'INSERT INTO taste_profile VALUES (1,?,?,?) ON CONFLICT(id) DO UPDATE SET '
    'dims=excluded.dims, vector=excluded.vector, updated_at=excluded.updated_at',
    [vector.length, _bytes(vector), DateTime.now().millisecondsSinceEpoch],
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
