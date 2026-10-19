import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/source_backend.dart';
import '../dj/coherence.dart';
import 'follow_models.dart';
import 'follow_repository.dart';

typedef FetchArtistPage = Future<ArtistPage> Function(String browseId);
typedef FindArtist = Future<List<SearchEntry>> Function(String name);

/// Artistas seguidos (locales: ni Last.fm ni ListenBrainz permiten seguir) y
/// novedades de sus páginas de YouTube Music. Sin hilos propios: la consulta
/// corre solo cuando [refreshIfDue] se llama (al abrir la app).
class FollowService extends ChangeNotifier {
  FollowService({
    required this.repository,
    required this.fetchArtist,
    required this.findArtist,
    DateTime Function()? now,
    this.interval = const Duration(hours: 12),
    this.concurrency = 3,
    this.timeout = const Duration(seconds: 20),
    this.newsRetention = const Duration(days: 60),
  }) : _now = now ?? DateTime.now;

  final FollowRepository repository;
  final FetchArtistPage fetchArtist;
  final FindArtist findArtist;
  final DateTime Function() _now;
  final Duration interval;
  final int concurrency;
  final Duration timeout;
  final Duration newsRetention;

  static const _maxKnown = 300;

  List<FollowedArtist> _artists = const [];
  List<NewRelease> _news = const [];
  final _busy = <String>{};
  bool _checking = false;
  bool _disposed = false;

  List<FollowedArtist> get artists => _artists;
  List<NewRelease> get news => _news;
  bool get checking => _checking;

  /// Nombres normalizados (`coherenceNorm`) y en minúsculas: lo que el DJ
  /// compara con `djPrimaryArtist(track)`. Ver docs/follow_artists.md.
  Set<String> get followedArtistKeys => {
    for (final a in _artists) ...[
      a.name.toLowerCase().trim(),
      coherenceNorm(a.name),
    ],
  };

  bool isFollowing(String browseId) =>
      _artists.any((a) => a.browseId == browseId);
  bool isFollowingName(String name) {
    final key = coherenceNorm(name);
    return key.isNotEmpty && _artists.any((a) => coherenceNorm(a.name) == key);
  }

  /// Hay un seguir/dejar de seguir en curso para ese nombre o id.
  bool isBusy(String key) => _busy.contains(key);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    await repository.pruneNews(_now().subtract(newsRetention));
    _artists = await repository.list();
    _news = await repository.news();
    _changed();
  }

  /// Sigue a un artista. Sin [browseId] lo busca por nombre en YouTube Music
  /// (las pistas solo conocen el nombre); lanza [StateError] si no hay un
  /// artista con ese nombre.
  Future<FollowedArtist> follow(
    String name, {
    String? browseId,
    String? imageUrl,
  }) async {
    final key = browseId ?? name;
    if (!_busy.add(key)) throw StateError('Ya se está procesando.');
    _changed();
    try {
      var id = browseId, title = name.trim(), image = imageUrl;
      if (id == null) {
        final wanted = coherenceNorm(title);
        final hits = await findArtist(title).timeout(timeout);
        final hit = hits
            .where((e) => e.kind == SearchKind.artists)
            .where((e) => coherenceNorm(e.title) == wanted)
            .firstOrNull;
        if (hit == null) {
          throw StateError('No se encontró a «$title» en YouTube Music.');
        }
        id = hit.browseId;
        title = hit.title;
        image ??= hit.artworkUrl;
      }
      await repository.follow(id, title, imageUrl: image, at: _now());
      _artists = await repository.list();
      _changed();
      final created = _artists.firstWhere((a) => a.browseId == id);
      unawaited(_check(created)); // línea base: no bloquea el botón
      return created;
    } finally {
      _busy.remove(key);
      _changed();
    }
  }

  Future<void> unfollow(String browseId) async {
    await repository.unfollow(browseId);
    _artists = await repository.list();
    _news = await repository.news();
    _changed();
  }

  /// Consulta a los seguidos cuya última comprobación tiene más de [interval],
  /// con [concurrency] peticiones a la vez. Tolera fallos por artista: se
  /// reintentará en la siguiente apertura.
  Future<void> refreshIfDue() async {
    if (_checking) return;
    final cutoff = _now().subtract(interval);
    final due = [
      for (final a in _artists)
        if (a.checkedAt == null || a.checkedAt!.isBefore(cutoff)) a,
    ];
    if (due.isEmpty) return;
    _checking = true;
    _changed();
    try {
      var next = 0;
      Future<void> worker() async {
        while (!_disposed && next < due.length) {
          await _check(due[next++]);
        }
      }

      await Future.wait([
        for (var i = 0; i < math.min(concurrency, due.length); i++) worker(),
      ]);
    } finally {
      _checking = false;
      if (!_disposed) {
        _news = await repository.news();
        _changed();
      }
    }
  }

  /// Compara la página del artista con lo ya visto. Nunca lanza.
  Future<void> _check(FollowedArtist artist) async {
    try {
      final page = await fetchArtist(artist.browseId).timeout(timeout);
      if (_disposed || !isFollowing(artist.browseId)) return;
      final baseline = artist.checkedAt == null;
      final fresh = [
        for (final r in page.releases)
          if (!artist.knownReleases.contains(r.id)) r,
      ];
      final latest = _latest(page.releases);
      final now = _now();
      if (!baseline && fresh.isNotEmpty) {
        await repository.addNews([
          for (final r in fresh)
            NewRelease(
              id: r.id,
              artistId: artist.browseId,
              artistName: artist.name,
              title: r.title,
              subtitle: [
                if (r.kind.isNotEmpty) r.kind,
                artist.name,
                if (r.year != null) '${r.year}',
              ].join(' • '),
              artworkUrl: r.artworkUrl,
              detectedAt: now,
            ),
        ]);
      }
      final known = {
        ...page.releases.map((r) => r.id),
        ...artist.knownReleases,
      }.take(_maxKnown).toSet();
      await repository.saveCheck(
        artist.copyWith(
          knownReleases: known,
          lastReleaseId: latest?.id,
          lastReleaseTitle: latest?.title,
          checkedAt: now,
        ),
      );
      _artists = await repository.list();
      if (!baseline) _news = await repository.news();
      _changed();
    } catch (_) {
      // Red, timeout o formato cambiado: se reintenta en la próxima apertura.
    }
  }

  static ArtistRelease? _latest(List<ArtistRelease> releases) {
    ArtistRelease? best;
    for (final r in releases) {
      if (best == null || (r.year ?? 0) > (best.year ?? 0)) best = r;
    }
    return best;
  }

  Future<void> dismissNews([String? releaseId]) async {
    await repository.dismissNews(releaseId);
    _news = await repository.news();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(repository.close());
    super.dispose();
  }
}
