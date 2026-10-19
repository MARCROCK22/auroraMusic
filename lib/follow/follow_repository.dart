import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../library/library_database.dart';
import 'follow_models.dart';

/// Artistas seguidos y novedades en SQLite (tablas creadas en LibraryDatabase).
class FollowRepository {
  FollowRepository(this._db);
  final LibraryDatabase _db;
  final _changes = StreamController<List<FollowedArtist>>.broadcast();

  static FollowedArtist _artist(QueryRow row) {
    Set<String> known;
    try {
      known = (jsonDecode(row.read<String>('known_releases')) as List)
          .whereType<String>()
          .toSet();
    } catch (_) {
      known = {};
    }
    final checked = row.read<int?>('checked_at');
    return FollowedArtist(
      browseId: row.read<String>('browse_id'),
      name: row.read<String>('name'),
      imageUrl: row.read<String?>('image_url'),
      followedAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('followed_at'),
      ),
      lastReleaseId: row.read<String?>('last_release_id'),
      lastReleaseTitle: row.read<String?>('last_release_title'),
      knownReleases: known,
      checkedAt: checked == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checked),
    );
  }

  Future<List<FollowedArtist>> list() async =>
      (await _db
              .customSelect(
                'SELECT * FROM followed_artists ORDER BY followed_at DESC',
              )
              .get())
          .map(_artist)
          .toList();

  /// Emite la lista actual y después cada cambio.
  Stream<List<FollowedArtist>> watch() async* {
    yield await list();
    yield* _changes.stream;
  }

  Future<void> _emit() async {
    if (!_changes.isClosed && _changes.hasListener) _changes.add(await list());
  }

  /// Seguir es idempotente: volver a seguir conserva fecha y línea base.
  Future<void> follow(
    String browseId,
    String name, {
    String? imageUrl,
    DateTime? at,
  }) async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO followed_artists '
      '(browse_id,name,image_url,followed_at) VALUES (?,?,?,?)',
      [browseId, name, imageUrl, (at ?? DateTime.now()).millisecondsSinceEpoch],
    );
    await _emit();
  }

  Future<void> unfollow(String browseId) async {
    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM followed_artists WHERE browse_id=?',
        [browseId],
      );
      await _db.customStatement('DELETE FROM new_releases WHERE artist_id=?', [
        browseId,
      ]);
    });
    await _emit();
  }

  Future<void> saveCheck(FollowedArtist artist) async {
    await _db.customStatement(
      'UPDATE followed_artists SET last_release_id=?, last_release_title=?, '
      'known_releases=?, checked_at=? WHERE browse_id=?',
      [
        artist.lastReleaseId,
        artist.lastReleaseTitle,
        jsonEncode(artist.knownReleases.toList()),
        artist.checkedAt?.millisecondsSinceEpoch,
        artist.browseId,
      ],
    );
    await _emit();
  }

  Future<List<NewRelease>> news() async =>
      (await _db
              .customSelect(
                'SELECT * FROM new_releases ORDER BY detected_at DESC',
              )
              .get())
          .map(
            (row) => NewRelease(
              id: row.read<String>('release_id'),
              artistId: row.read<String>('artist_id'),
              artistName: row.read<String>('artist_name'),
              title: row.read<String>('title'),
              subtitle: row.read<String>('subtitle'),
              artworkUrl: row.read<String?>('artwork_url'),
              detectedAt: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('detected_at'),
              ),
            ),
          )
          .toList();

  Future<void> addNews(Iterable<NewRelease> releases) async {
    for (final r in releases) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO new_releases VALUES (?,?,?,?,?,?,?)',
        [
          r.id,
          r.artistId,
          r.artistName,
          r.title,
          r.subtitle,
          r.artworkUrl,
          r.detectedAt.millisecondsSinceEpoch,
        ],
      );
    }
  }

  /// Sin [id] descarta todas («marcar como vistas»).
  Future<void> dismissNews([String? id]) => id == null
      ? _db.customStatement('DELETE FROM new_releases')
      : _db.customStatement('DELETE FROM new_releases WHERE release_id=?', [
          id,
        ]);

  Future<void> pruneNews(DateTime olderThan) => _db.customStatement(
    'DELETE FROM new_releases WHERE detected_at<?',
    [olderThan.millisecondsSinceEpoch],
  );

  Future<void> close() => _changes.close();
}
