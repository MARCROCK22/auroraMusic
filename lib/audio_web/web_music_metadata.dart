import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/models.dart';
import 'web_music_bridge.dart';

export 'web_music_bridge.dart' show WebMusicBridge;

/// Searches the official YouTube Music page in a view separate from playback.
class WebMusicMetadata extends ChangeNotifier {
  WebMusicMetadata({
    WebMusicBridge? bridge,
    this.timeout = const Duration(seconds: 20),
    this.pollInterval = const Duration(milliseconds: 250),
  }) : _bridge = bridge ?? NativeWebMusicBridge(),
       _ownsBridge = bridge == null;

  static const int maxResults = 50;
  static const Duration cacheTtl = Duration(minutes: 5);

  final WebMusicBridge _bridge;
  final bool _ownsBridge;
  final Duration timeout;
  final Duration pollInterval;
  final Map<String, ({DateTime at, List<Track> tracks})> _cache = {};
  Future<void> _operations = Future.value();
  Future<bool>? _initialization;
  Widget? _view;
  Timer? _waitTimer;
  Completer<void>? _waitCompleter;
  int _revision = 0;
  bool _activated = false;
  bool _ready = false;
  bool _disposed = false;
  bool _searching = false;
  String? _error;
  List<Track> _tracks = const [];

  bool get activated => _activated;
  bool get searching => _searching;
  String? get error => _error;
  List<Track> get tracks => _tracks;

  /// Initializes once. A default native bridge is limited to Android/Windows.
  Future<bool> initialize() => _initialization ??= _initialize();

  Future<bool> _initialize() async {
    if (_disposed) return false;
    if (_ownsBridge &&
        (kIsWeb ||
            !const {
              TargetPlatform.android,
              TargetPlatform.windows,
            }.contains(defaultTargetPlatform))) {
      _error = 'La búsqueda web requiere Android o Windows.';
      notifyListeners();
      return false;
    }
    _bridge.onFailure = (_) {
      if (!_disposed) _setError('No se pudo cargar la búsqueda web.');
    };
    try {
      await _bridge.initialize();
      _ready = !_disposed;
      if (_ready) notifyListeners();
      return _ready;
    } catch (_) {
      _setError('No se pudo iniciar la búsqueda web.');
      return false;
    }
  }

  /// Keep this widget mounted in the app shell; it stays 1×1 and hidden.
  Widget buildMetadataView() {
    if (!_activated || !_ready || _disposed) return const SizedBox.shrink();
    return SizedBox(width: 1, height: 1, child: _view ??= _bridge.buildView());
  }

  Future<List<Track>> search(String query, {int limit = 20}) {
    final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (_disposed || normalized.isEmpty) return Future.value(const <Track>[]);
    final key = normalized.toLowerCase();
    final revision = ++_revision;
    _activated = true;
    _searching = true;
    _error = null;
    notifyListeners();

    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < cacheTtl) {
      _tracks = cached.tracks.take(_limit(limit)).toList(growable: false);
      _searching = false;
      notifyListeners();
      return Future.value(_tracks);
    }

    final result = Completer<List<Track>>();
    _operations = _operations
        .then((_) async {
          if (_disposed || revision != _revision) {
            result.complete(const <Track>[]);
            return;
          }
          final tracks = await _runSearch(normalized, key, revision);
          final bounded = tracks.take(_limit(limit)).toList(growable: false);
          if (!_disposed && revision == _revision) {
            _tracks = bounded;
            _searching = false;
            notifyListeners();
          }
          result.complete(revision == _revision ? bounded : const <Track>[]);
        })
        .catchError((Object _) {
          if (!result.isCompleted) result.complete(const <Track>[]);
          if (!_disposed && revision == _revision) {
            _searching = false;
            _setError('No se pudo completar la búsqueda.');
          }
        });
    return result.future;
  }

  Future<List<Track>> _runSearch(String query, String key, int revision) async {
    if (!await initialize() || _disposed || revision != _revision) {
      return const <Track>[];
    }
    final deadline = DateTime.now().add(timeout);
    final uri = Uri.https('music.youtube.com', '/search', {'q': query});
    try {
      await _bridge.navigate(uri).timeout(timeout);
    } catch (_) {
      if (revision == _revision) {
        _setError(
          DateTime.now().isBefore(deadline)
              ? 'No se pudo abrir la búsqueda.'
              : 'La búsqueda tardó demasiado. Inténtalo de nuevo.',
        );
      }
      return const <Track>[];
    }

    while (!_disposed &&
        revision == _revision &&
        DateTime.now().isBefore(deadline)) {
      Map<String, dynamic>? response;
      try {
        response = await _bridge
            .command('search', videoId: query, generation: revision)
            .timeout(deadline.difference(DateTime.now()));
      } catch (_) {
        if (revision == _revision) {
          _setError(
            DateTime.now().isBefore(deadline)
                ? 'La búsqueda web falló.'
                : 'La búsqueda tardó demasiado. Inténtalo de nuevo.',
          );
        }
        return const <Track>[];
      }
      if (response != null) {
        final status = response['status'];
        if (status == 'ready') {
          final tracks = _parseTracks(response['tracks']);
          _cache[key] = (at: DateTime.now(), tracks: tracks);
          return tracks;
        }
        if (status == 'blocked' || status == 'providerBlocked') {
          if (revision == _revision) {
            _setError(
              'YouTube Music bloqueó la búsqueda. Inténtalo más tarde.',
            );
          }
          return const <Track>[];
        }
        if (status != 'waiting' && status != 'loading') {
          if (revision == _revision) _setError('No se encontraron resultados.');
          return const <Track>[];
        }
      }
      await _delay(pollInterval);
    }
    if (!_disposed && revision == _revision) {
      _setError('La búsqueda tardó demasiado. Inténtalo de nuevo.');
    }
    return const <Track>[];
  }

  List<Track> _parseTracks(Object? value) {
    if (value is! List) return const <Track>[];
    final result = <Track>[];
    for (final item in value) {
      if (item is! Map) continue;
      final id = item['videoId'];
      final title = item['title'];
      if (id is! String || !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id)) {
        continue;
      }
      if (title is! String || title.trim().isEmpty) continue;
      final artist = item['artist'];
      final album = item['album'];
      final artwork = item['artworkUrl'];
      final duration = item['durationSeconds'];
      result.add(
        Track(
          id: 'yt:$id',
          title: title.trim(),
          artist: artist is String ? artist.trim() : '',
          album: album is String ? album.trim() : null,
          artworkUrl: artwork is String && artwork.startsWith('https://')
              ? artwork
              : null,
          duration: duration is num && duration.isFinite && duration > 0
              ? Duration(seconds: duration.round())
              : Duration.zero,
          pageUrl: Uri.https('music.youtube.com', '/watch', {
            'v': id,
          }).toString(),
        ),
      );
      if (result.length == maxResults) break;
    }
    return result;
  }

  Future<void> _delay(Duration duration) {
    final completer = Completer<void>();
    _waitCompleter = completer;
    _waitTimer = Timer(duration, () {
      _waitTimer = null;
      _waitCompleter = null;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  int _limit(int value) => value.clamp(1, maxResults).toInt();

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _waitTimer?.cancel();
    _waitTimer = null;
    if (!(_waitCompleter?.isCompleted ?? true)) _waitCompleter!.complete();
    _waitCompleter = null;
    _bridge.onFailure = null;
    _bridge.onNavigation = null;
    _bridge.dispose();
    super.dispose();
  }
}
