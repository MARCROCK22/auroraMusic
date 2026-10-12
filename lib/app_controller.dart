import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/media_controls.dart';
import 'core/audio_backend.dart';
import 'core/models.dart';
import 'core/source_backend.dart';
import 'import/spotify_import.dart';
import 'library/library_database.dart';
import 'dj/recommendations.dart';

final controllerProvider = ChangeNotifierProvider<AppController>((ref) {
  throw StateError('Override controllerProvider at application startup.');
});

class AppController extends ChangeNotifier {
  static const _maxStreamRecoveryAttempts = 2;
  AppController({
    required this.audio,
    required this.source,
    required this.database,
    required this.preferences,
    required this.supportDirectory,
  });
  final AudioBackend audio;
  final SourceBackend source;
  final LibraryDatabase database;
  final SharedPreferences preferences;
  final Directory supportDirectory;
  MediaControls? _controls;
  StreamSubscription<void>? _completedSubscription;
  bool _disposed = false;
  bool ready = false;
  bool busy = false;
  bool searching = false;
  bool diagnosing = false;
  bool sessionBusy = false;
  bool configuringDownloadDirectory = false;
  bool clearingPlaybackCache = false;
  String? playbackCacheMessage;
  String get downloadsDirectoryPath =>
      preferences.getString('downloadsDirectory') ??
      p.join(supportDirectory.path, 'downloads');
  bool get canConfigureDownloadDirectory => Platform.isWindows;
  bool get hasYouTubeSession => source.cookieFile != null;
  String? error;
  String? diagnostics;
  List<Track> tracks = [];
  List<Track> searchResults = [];
  List<Track> discoveredRecommendations = [];
  bool discoveringRecommendations = false;
  String? recommendationDiscoveryError;
  String? personalDjError;
  DjFilters _djFilters = const DjFilters();
  DjFilters get djFilters => _djFilters;
  String _searchQuery = '';
  int _searchLimit = 20;
  bool get hasMoreSearchResults =>
      searchResults.length >= _searchLimit && _searchLimit < 50;
  List<Track> recentTracks = [];
  List<MusicPlaylist> playlists = [];
  List<DownloadJob> downloads = [];
  Set<String> favoriteIds = {};
  List<Track> queue = [];
  int queueIndex = -1;
  bool shuffle = false;
  RepeatMode repeat = RepeatMode.off;
  bool eqEnabled = false;
  bool experimentalProgressivePlayback = false;
  List<double> eqGains = List.filled(8, 0);
  bool adaptiveColors = true;
  String accentPalette = 'automatic';
  static const Map<String, Color> accentPaletteColors = {
    'terracotta': Color(0xffc45c2b),
    'amber': Color(0xffa66b00),
    'forest': Color(0xff28734a),
    'purple': Color(0xff7047a3),
  };
  bool reducedMotion = false;
  ThemeMode themeMode = ThemeMode.dark;
  Color accentColor = const Color(0xffe86927);
  Timer? _sleepTimer;
  DateTime? _sleepEnd;
  int _playGeneration = 0;
  int _recoveryGeneration = 0;
  int _searchGeneration = 0;
  int _recommendationDiscoveryGeneration = 0;
  int _personalDjGeneration = 0;
  int _personalDjDiscoverySearches = 0;
  bool _personalDjActive = false;
  bool _personalDjIncludeDiscovery = false;
  Set<String> _personalDjSeenKeys = {};
  Future<void>? _personalDjRefillTask;
  bool _processingDownloads = false;
  Future<void>? _downloadWorker;
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;
  String? _loadedTrackId;
  String? _loadedAudioInput;
  String? _pendingResolveVideoId;
  Duration _resumePosition = Duration.zero;
  final Random _random = Random();
  final List<int> _shuffleHistory = [];
  final Set<int> _shufflePlayed = {};
  DateTime _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _recovering = false;
  bool _playIntent = false;
  bool _jamPlaybackActive = false;

  /// Jam owns the audio backend temporarily, without persisting its queue.
  bool get jamPlaybackActive => _jamPlaybackActive;
  bool _usingRemote = false;
  String? _recoveryTrackId;
  String? _recoverableRemoteTrackId;
  int _expiryRetries = 0;
  Duration _recoveryProgressPosition = Duration.zero;

  Track? get currentTrack =>
      queueIndex >= 0 && queueIndex < queue.length ? queue[queueIndex] : null;
  List<TrackRecommendation> get recommendations => recommendTracks(
    library: tracks,
    favoriteIds: favoriteIds,
    playlists: playlists,
    history: recentTracks,
    currentTrackId: currentTrack?.id,
    filters: djFilters,
  );
  bool get canDiscoverRecommendations =>
      strongestTasteArtist(
            library: tracks,
            favoriteIds: favoriteIds,
            playlists: playlists,
            history: recentTracks,
          ) !=
          null ||
      recommendations.isNotEmpty;
  bool get personalDjActive => _personalDjActive;
  bool get personalDjIncludeDiscovery => _personalDjIncludeDiscovery;
  bool get canStartPersonalDj {
    final queuedKeys = queue.expand(recommendationTrackKeys).toSet();
    final hasUnqueuedRecommendation = [
      ...recommendations.map((item) => item.track),
      if (_personalDjIncludeDiscovery) ...discoveredRecommendations,
    ].any((track) => !recommendationTrackKeys(track).any(queuedKeys.contains));
    return hasUnqueuedRecommendation || _hasPlayableUpcomingQueue;
  }

  bool get _hasPlayableUpcomingQueue {
    if (currentTrack == null ||
        !(_playIntent || busy || audio.isPlaying || _loadedTrackId != null)) {
      return false;
    }
    bool playable(Track track) =>
        !track.isPendingSpotifyMatch &&
        (track.isLocal || track.pageUrl != null);
    if (shuffle) {
      return queue.asMap().entries.any(
        (entry) =>
            entry.key != queueIndex &&
            (repeat == RepeatMode.all || !_shufflePlayed.contains(entry.key)) &&
            playable(entry.value),
      );
    }
    if (queueIndex + 1 < queue.length) {
      return queue.skip(queueIndex + 1).any(playable);
    }
    return repeat == RepeatMode.all &&
        queue.asMap().entries.any(
          (entry) => entry.key != queueIndex && playable(entry.value),
        );
  }

  String _recommendationTasteKey() {
    final sortedFavorites = favoriteIds.toList()..sort();
    return [
      jsonEncode(djFilters.toJson()),
      ...sortedFavorites,
      ...playlists.map(
        (playlist) => '${playlist.id}:${playlist.trackIds.join(',')}',
      ),
      ...recentTracks.map((track) => track.id),
    ].join('|');
  }

  Future<void> setDjFilters(DjFilters filters) async {
    // Copy lists so external mutations cannot bypass invalidation.
    _djFilters = DjFilters.fromJson(filters.toJson());
    ++_recommendationDiscoveryGeneration;
    ++_personalDjGeneration;
    discoveringRecommendations = false;
    discoveredRecommendations = [];
    recommendationDiscoveryError = null;
    personalDjError = null;
    _notify();
    await preferences.setString('djFilters', jsonEncode(djFilters.toJson()));
    if (_personalDjActive && _playIntent) unawaited(_refillPersonalDjQueue());
  }

  Future<void> refreshRecommendations() async {
    ++_recommendationDiscoveryGeneration;
    discoveringRecommendations = false;
    discoveredRecommendations = [];
    recommendationDiscoveryError = null;
    _notify();
    if (canDiscoverRecommendations) await discoverRecommendations();
  }

  Future<void> discoverRecommendations() async {
    if (discoveringRecommendations || _disposed) return;
    final seed =
        strongestTasteArtist(
          library: tracks,
          favoriteIds: favoriteIds,
          playlists: playlists,
          history: recentTracks,
        ) ??
        recommendations.firstOrNull?.track.artist;
    if (seed == null) return;
    final generation = ++_recommendationDiscoveryGeneration;
    final tasteKey = _recommendationTasteKey();
    discoveringRecommendations = true;
    recommendationDiscoveryError = null;
    _notify();
    try {
      final results = await source.search('$seed songs', limit: 12);
      if (generation != _recommendationDiscoveryGeneration ||
          _disposed ||
          tasteKey != _recommendationTasteKey()) {
        return;
      }
      final seenIds = {...tracks.expand(recommendationTrackKeys)};
      final fresh = <Track>[];
      for (final track in results) {
        final keys = recommendationTrackKeys(track);
        if (!djFilters.permits(track) ||
            keys.any(seenIds.contains) ||
            track.isPendingSpotifyMatch ||
            track.pageUrl == null) {
          continue;
        }
        seenIds.addAll(keys);
        fresh.add(track);
      }
      discoveredRecommendations = fresh.take(6).toList();
    } catch (exception) {
      if (generation == _recommendationDiscoveryGeneration &&
          !_disposed &&
          tasteKey == _recommendationTasteKey()) {
        recommendationDiscoveryError = exception.toString();
      }
    } finally {
      if (generation == _recommendationDiscoveryGeneration && !_disposed) {
        discoveringRecommendations = false;
        _notify();
      }
    }
  }

  void cancelRecommendationDiscovery() {
    if (!discoveringRecommendations) return;
    ++_recommendationDiscoveryGeneration;
    discoveringRecommendations = false;
    _notify();
  }

  Future<void> startPersonalDj({bool includeDiscovery = false}) async {
    if (_jamPlaybackActive) return;
    if (personalDjActive) return;
    final preserveCurrent =
        currentTrack != null &&
        (_playIntent || busy || audio.isPlaying || _loadedTrackId != null);
    final existingKeys = preserveCurrent
        ? queue.expand(recommendationTrackKeys).toSet()
        : <String>{};
    final seedTracks = <Track>[];
    final seenKeys = <String>{...existingKeys};
    for (final track in [
      ...recommendations.map((item) => item.track),
      if (includeDiscovery) ...discoveredRecommendations,
    ]) {
      if (preserveCurrent && queue.length + seedTracks.length >= 24) break;
      final keys = recommendationTrackKeys(track);
      if (!djFilters.permits(track) || keys.any(seenKeys.contains)) continue;
      seenKeys.addAll(keys);
      seedTracks.add(track);
      if (seedTracks.length == 6) break;
    }
    if (seedTracks.isEmpty && !(preserveCurrent && _hasPlayableUpcomingQueue)) {
      return;
    }
    ++_personalDjGeneration;
    _personalDjActive = true;
    _personalDjIncludeDiscovery = includeDiscovery;
    _personalDjDiscoverySearches = 0;
    personalDjError = null;
    _personalDjSeenKeys = seenKeys;
    _notify();
    if (preserveCurrent) {
      final insertAt = queueIndex + 1;
      for (var i = 0; i < _shuffleHistory.length; i++) {
        if (_shuffleHistory[i] >= insertAt) {
          _shuffleHistory[i] += seedTracks.length;
        }
      }
      final shiftedPlayed = _shufflePlayed
          .map((index) => index >= insertAt ? index + seedTracks.length : index)
          .toSet();
      _shufflePlayed
        ..clear()
        ..addAll(shiftedPlayed);
      queue.insertAll(insertAt, seedTracks);
      await _saveQueue();
      _notify();
      if (audio.isPlaying) unawaited(_refillPersonalDjQueue());
      return;
    }
    queue = seedTracks;
    queueIndex = 0;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    _resumePosition = Duration.zero;
    _playIntent = true;
    await _playCurrent();
  }

  void stopPersonalDj() {
    if (!_personalDjActive) return;
    ++_personalDjGeneration;
    _personalDjActive = false;
    personalDjError = null;
    _notify();
  }

  void setPersonalDjIncludeDiscovery(bool value) {
    if (_personalDjIncludeDiscovery == value) return;
    _personalDjIncludeDiscovery = value;
    _notify();
  }

  Future<void> _refillPersonalDjQueue() async {
    if (!_personalDjActive || !_playIntent || _disposed) return;
    final pending = _personalDjRefillTask;
    if (pending != null) {
      await pending;
      if (_personalDjActive && _playIntent && !_disposed) {
        await _refillPersonalDjQueue();
      }
      return;
    }
    if (queue.isEmpty || queueIndex < 0 || queue.length >= 24) return;
    final upcoming = shuffle
        ? queue.length - _shufflePlayed.length
        : queue.length - queueIndex - 1;
    if (upcoming > 2) return;
    final generation = _personalDjGeneration;
    final task = _performPersonalDjRefill(generation);
    _personalDjRefillTask = task;
    try {
      await task;
    } finally {
      if (identical(_personalDjRefillTask, task)) {
        _personalDjRefillTask = null;
      }
    }
  }

  Future<void> _performPersonalDjRefill(int generation) async {
    final target = (24 - queue.length).clamp(0, 3);
    if (target == 0) return;
    _personalDjSeenKeys.addAll(queue.expand(recommendationTrackKeys));
    var added = 0;
    void addTrack(Track track) {
      if (queue.length >= 24) return;
      queue.add(track);
      _personalDjSeenKeys.addAll(recommendationTrackKeys(track));
      added++;
    }

    final local = recommendTracks(
      library: tracks,
      favoriteIds: favoriteIds,
      playlists: playlists,
      history: recentTracks,
      currentTrackId: currentTrack?.id,
      limit: 24,
      filters: djFilters,
    );
    for (final recommendation in local) {
      final track = recommendation.track;
      final keys = recommendationTrackKeys(track);
      if (keys.any(_personalDjSeenKeys.contains)) continue;
      addTrack(track);
      if (added >= target) break;
    }

    if (added < target &&
        _personalDjIncludeDiscovery &&
        _personalDjDiscoverySearches < 2 &&
        generation == _personalDjGeneration &&
        _personalDjActive) {
      final artist =
          strongestTasteArtist(
            library: tracks,
            favoriteIds: favoriteIds,
            playlists: playlists,
            history: recentTracks,
          ) ??
          currentTrack?.artist;
      if (artist != null) {
        _personalDjDiscoverySearches++;
        try {
          final results = await source.search('$artist songs', limit: 12);
          if (generation == _personalDjGeneration &&
              _personalDjActive &&
              _personalDjIncludeDiscovery &&
              !_disposed) {
            final libraryKeys = tracks.expand(recommendationTrackKeys).toSet();
            for (final track in results) {
              final keys = recommendationTrackKeys(track);
              if (!djFilters.permits(track) ||
                  track.isPendingSpotifyMatch ||
                  track.pageUrl == null ||
                  keys.any(libraryKeys.contains) ||
                  keys.any(_personalDjSeenKeys.contains)) {
                continue;
              }
              addTrack(track);
              if (added >= target) break;
            }
          }
        } catch (exception) {
          if (generation == _personalDjGeneration &&
              _personalDjActive &&
              _personalDjIncludeDiscovery) {
            personalDjError = exception.toString();
            _notify();
          }
        }
      }
    }
    if (added > 0 && generation == _personalDjGeneration && !_disposed) {
      await _saveQueue();
      _notify();
    }
  }

  Duration? get sleepRemaining {
    final end = _sleepEnd;
    if (end == null) return null;
    final remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> initialize({bool mediaControls = true}) async {
    try {
      tracks = await database.readTracks();
      favoriteIds = await database.readFavorites();
      playlists = await database.readPlaylists();
      downloads = await database.readDownloads();
      final legacyRoot = Directory(p.join(supportDirectory.path, 'downloads'));
      await legacyRoot.create(recursive: true);
      for (final job in downloads) {
        job.destinationRoot ??= await _canonicalDownloadRoot(
          p.join(supportDirectory.path, 'downloads'),
        );
        await database.saveDownload(job);
      }
      recentTracks = _lookup(await database.readHistory());
      final savedFilters = preferences.getString('djFilters');
      if (savedFilters != null) {
        try {
          _djFilters = DjFilters.fromJson(
            jsonDecode(savedFilters) as Map<String, dynamic>,
          );
        } on FormatException {
          _djFilters = const DjFilters();
        } on TypeError {
          _djFilters = const DjFilters();
        }
      }
      final savedPalette = preferences.getString('accentPalette');
      accentPalette =
          savedPalette == 'automatic' ||
              accentPaletteColors.containsKey(savedPalette)
          ? savedPalette!
          : (preferences.getBool('adaptiveColors') == false
                ? 'terracotta'
                : 'automatic');
      adaptiveColors = accentPalette == 'automatic';
      accentColor = accentPaletteColors[accentPalette] ?? accentColor;
      reducedMotion = preferences.getBool('reducedMotion') ?? false;
      experimentalProgressivePlayback =
          source.supportsExperimentalProgressivePlayback &&
          (preferences.getBool('experimentalProgressivePlayback') ?? false);
      if (source.supportsExperimentalProgressivePlayback) {
        source.setExperimentalProgressivePlayback(
          experimentalProgressivePlayback,
        );
      }
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == preferences.getString('themeMode'),
        orElse: () => ThemeMode.dark,
      );
      eqEnabled = preferences.getBool('eqEnabled') ?? false;
      final savedGains = preferences.getStringList('eqGains');
      if (savedGains?.length == 8) {
        eqGains = savedGains!
            .map((v) => (double.tryParse(v) ?? 0).clamp(-12.0, 12.0))
            .toList();
      }
      queue = _lookup(preferences.getStringList('queue') ?? []);
      queueIndex = queue.isEmpty
          ? -1
          : (preferences.getInt('queueIndex') ?? 0).clamp(0, queue.length - 1);
      _resumePosition = Duration(
        milliseconds: preferences.getInt('position') ?? 0,
      );
      repeat = RepeatMode.values.firstWhere(
        (mode) => mode.name == preferences.getString('repeat'),
        orElse: () => RepeatMode.off,
      );
      shuffle = preferences.getBool('shuffle') ?? false;
      final directory = preferences.getString('toolDirectory');
      if (directory != null && Platform.isWindows) {
        try {
          await source.configureToolDirectory(directory);
        } catch (_) {
          error =
              'La carpeta de herramientas cambió. Configúrala en Ajustes para usar YouTube.';
        }
      }
      await audio.initialize();
      audio.setVolume(preferences.getDouble('volume') ?? 0.75);
      audio.setEqualizer(eqEnabled, eqGains);
      audio.addListener(_audioChanged);
      _completedSubscription = audio.completed.listen(
        (_) => unawaited(_onCompleted()),
      );
      if (mediaControls) {
        try {
          _controls = MediaControls(
            audio: audio,
            onPlay: resumePlayback,
            onPause: pausePlayback,
            onStop: stopPlayback,
            onNext: next,
            onPrevious: previous,
            onSeek: seek,
          );
          await _controls!.initialize();
          _controls!.updateTrack(currentTrack);
        } catch (_) {
          error =
              'No se pudieron iniciar los controles multimedia del sistema. Puedes usar los controles de la app.';
        }
      }
      if (currentTrack != null) unawaited(_updateAccent(currentTrack!));
    } catch (exception) {
      _report(exception);
    } finally {
      ready = true;
      _notify();
    }
  }

  List<Track> _lookup(List<String> ids) {
    final byId = {for (final track in tracks) track.id: track};
    return ids.map((id) => byId[id]).whereType<Track>().toList();
  }

  void _audioChanged() {
    if (_jamPlaybackActive) {
      _notify();
      return;
    }
    final audioError = audio.lastError;
    if (audioError != null && audioError != error) error = audioError;
    if (_playIntent &&
        !_recovering &&
        audio.isPlaying &&
        audio.position - _recoveryProgressPosition >=
            const Duration(seconds: 30)) {
      _expiryRetries = 0;
      _recoveryProgressPosition = audio.position;
    }
    if (audioError != null &&
        _usingRemote &&
        _recoverableRemoteTrackId == currentTrack?.id &&
        _playIntent &&
        !_recovering &&
        !busy &&
        _expiryRetries < _maxStreamRecoveryAttempts &&
        _isRecoverableStreamError(audioError)) {
      unawaited(_recoverExpiredStream());
    }
    if (audio.isPlaying &&
        DateTime.now().difference(_lastSnapshot).inSeconds >= 5) {
      _lastSnapshot = DateTime.now();
      unawaited(_saveQueue());
    }
    _notify();
  }

  bool _isRecoverableStreamError(String message) => RegExp(
    r'403|410|Forbidden|expired|termin[oó] antes de completar|premature\s+(?:eof|end)|timed?\s*out|timeout|socketexception|httpexception|connection\s+(?:reset|closed|aborted)|broken\s+pipe|unexpected\s+eof',
    caseSensitive: false,
  ).hasMatch(message);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _report(Object exception) {
    error = exception.toString().replaceFirst(
      RegExp(r'^(Exception|StateError|Bad state):\s*'),
      '',
    );
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> _remember(Track track) async {
    final index = tracks.indexWhere((item) => item.id == track.id);
    if (index >= 0 &&
        track.localPath == null &&
        tracks[index].localPath != null) {
      track = track.copyWith(localPath: tracks[index].localPath);
    }
    if (index < 0) {
      tracks.insert(0, track);
    } else {
      tracks[index] = track;
    }
    await database.saveTrack(track);
  }

  Future<void> search(String query, {int limit = 20}) async {
    final generation = ++_searchGeneration;
    _searchQuery = query.trim();
    _searchLimit = limit.clamp(1, 50);
    if (query.trim().isEmpty) {
      searchResults = [];
      searching = false;
      _notify();
      return;
    }
    searching = true;
    error = null;
    _notify();
    try {
      final result = await source.search(query.trim(), limit: _searchLimit);
      if (generation == _searchGeneration) searchResults = result;
    } catch (exception) {
      if (generation == _searchGeneration) _report(exception);
    } finally {
      if (generation == _searchGeneration) {
        searching = false;
        _notify();
      }
    }
  }

  Future<void> loadMoreSearch() =>
      search(_searchQuery, limit: (_searchLimit + 20).clamp(1, 50));

  Future<void> playTrack(Track track, {List<Track>? context}) async {
    if (_jamPlaybackActive) return;
    if (_personalDjActive) stopPersonalDj();
    await _playTrack(track, context: context);
  }

  Future<void> _playTrack(Track track, {List<Track>? context}) async {
    _playIntent = true;
    _expiryRetries = 0;
    final remembered = {for (final item in tracks) item.id: item};
    final selected = remembered[track.id] ?? track;
    final seen = <String>{};
    queue = [];
    for (final candidate in context?.isNotEmpty == true ? context! : [track]) {
      final item = remembered[candidate.id] ?? candidate;
      if (item.id != selected.id && recommendationTracksMatch(item, selected)) {
        continue;
      }
      final keys = recommendationTrackKeys(item);
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      queue.add(item);
    }
    queueIndex = queue.indexWhere((item) => item.id == selected.id);
    if (queueIndex < 0) {
      queue.insert(0, selected);
      queueIndex = 0;
    }
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> playQueueAt(int index) async {
    if (_jamPlaybackActive) return;
    if (index < 0 || index >= queue.length) return;
    stopPersonalDj();
    _playIntent = true;
    _expiryRetries = 0;
    queueIndex = index;
    _resumePosition = Duration.zero;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(index);
    await _playCurrent();
  }

  Future<void> _playCurrent({bool fromRecovery = false}) async {
    if (_jamPlaybackActive) return;
    if (!fromRecovery) _cancelRecovery();
    final track = currentTrack;
    if (track == null) return;
    final generation = ++_playGeneration;
    if (!fromRecovery) _cancelPendingResolution();
    if (track.isPendingSpotifyMatch) {
      _playIntent = false;
      _recoverableRemoteTrackId = null;
      busy = true;
      _notify();
      try {
        try {
          await audio.stop();
        } catch (_) {}
        if (generation != _playGeneration || _disposed) return;
        _loadedTrackId = null;
        _loadedAudioInput = null;
        _usingRemote = false;
        _report(
          StateError(
            'Esta canción de Spotify aún no tiene una coincidencia. '
            'Abre la biblioteca y elige su video de YouTube.',
          ),
        );
      } finally {
        if (generation == _playGeneration) {
          busy = false;
          _notify();
        }
      }
      return;
    }
    if (_recoveryTrackId != track.id) {
      _recoveryTrackId = track.id;
      _expiryRetries = 0;
    }
    busy = true;
    error = null;
    _loadedTrackId = null;
    _notify();
    try {
      await audio.stop();
      if (generation != _playGeneration || _disposed) return;
      _loadedAudioInput = null;
      for (final item in List<Track>.of(queue)) {
        await _remember(item);
        if (generation != _playGeneration || _disposed) return;
      }
      if (generation != _playGeneration || _disposed) return;
      final remembered = tracks
          .where((item) => item.id == track.id)
          .firstOrNull;
      final local = track.localPath ?? remembered?.localPath;
      final availableLocally = local != null && await File(local).exists();
      if (generation != _playGeneration || _disposed) return;
      _usingRemote = !availableLocally;
      if (!availableLocally && track.pageUrl == null) {
        throw StateError(
          'El archivo ya no está disponible. Vuelve a importarlo.',
        );
      }
      if (!availableLocally && source.supportsPlaybackCache) {
        final page = Uri.tryParse(track.pageUrl ?? '');
        final videoId = page?.host == 'youtu.be'
            ? page?.pathSegments.firstOrNull
            : page?.queryParameters['v'];
        if (videoId != null &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
          _pendingResolveVideoId = videoId;
        }
      }
      final resolved = availableLocally
          ? ResolvedAudio(input: local, duration: track.duration)
          : await source.resolve(track);
      if (generation != _playGeneration || _disposed) return;
      _pendingResolveVideoId = null;
      _loadedAudioInput = resolved.input;
      await audio.load(
        resolved,
        ffmpegExecutable: source.ffmpegExecutable,
        start: _resumePosition,
      );
      if (generation != _playGeneration || _disposed) return;
      _resumePosition = Duration.zero;
      _loadedTrackId = track.id;
      if (_controls != null && !await _controls!.activate()) {
        throw StateError(
          'Otra aplicación está usando el audio. Intenta reproducir de nuevo.',
        );
      }
      if (generation != _playGeneration || _disposed) return;
      await audio.play();
      if (generation != _playGeneration || _disposed) return;
      _recoverableRemoteTrackId = _usingRemote ? track.id : null;
      final readyTrack = audio.duration > Duration.zero
          ? track.copyWith(duration: audio.duration, localPath: local)
          : track;
      if (generation == _playGeneration &&
          queueIndex >= 0 &&
          queueIndex < queue.length) {
        queue[queueIndex] = readyTrack;
      }
      await _remember(readyTrack);
      if (generation != _playGeneration || _disposed) return;
      _controls?.updateTrack(readyTrack);
      await database.recordPlay(track.id);
      if (generation != _playGeneration || _disposed) return;
      recentTracks = [
        readyTrack,
        ...recentTracks.where((item) => item.id != track.id),
      ].take(100).toList();
      await _saveQueue();
      unawaited(_updateAccent(track));
    } catch (exception) {
      if (generation == _playGeneration) _report(exception);
    } finally {
      if (generation == _playGeneration) {
        _pendingResolveVideoId = null;
        busy = false;
        _notify();
        if (_personalDjActive &&
            _loadedTrackId == track.id &&
            audio.isPlaying) {
          unawaited(_refillPersonalDjQueue());
        }
      }
    }
  }

  /// Suspend personal playback before Jam starts using [audio].
  Future<void> beginJamPlayback() async {
    if (_jamPlaybackActive) return;
    if (_loadedTrackId != null) _resumePosition = audio.position;
    _jamPlaybackActive = true;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    ++_playGeneration;
    busy = false;
    stopPersonalDj();
    await audio.pause();
    _controls?.updateTrack(null);
    _notify();
  }

  /// Release Jam audio. The Jam bridge restores its captured personal session.
  Future<void> endJamPlayback() async {
    if (!_jamPlaybackActive) return;
    try {
      await audio.stop();
    } finally {
      _loadedTrackId = null;
      _loadedAudioInput = null;
      _recoverableRemoteTrackId = null;
      _usingRemote = false;
      _playIntent = false;
      _jamPlaybackActive = false;
      _controls?.updateTrack(currentTrack);
      _notify();
    }
  }

  Future<void> resumePlayback() async {
    if (_jamPlaybackActive) return;
    if (currentTrack == null) return;
    _playIntent = true;
    if (_loadedTrackId != currentTrack!.id || audio.lastError != null) {
      if (audio.lastError != null) {
        _resumePosition = audio.position > Duration.zero
            ? audio.position
            : _resumePosition;
        _expiryRetries = 0;
      }
      await _playCurrent();
      return;
    }
    try {
      final generation = _playGeneration;
      if (_controls != null && !await _controls!.activate()) return;
      if (generation != _playGeneration || _disposed) return;
      await audio.play();
      if (_personalDjActive) unawaited(_refillPersonalDjQueue());
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> _recoverExpiredStream() async {
    final trackId = currentTrack?.id;
    final occurrence = queueIndex;
    final recoveryGeneration = ++_recoveryGeneration;
    final failedError = audio.lastError;
    final resumePosition = audio.position > Duration.zero
        ? audio.position
        : _resumePosition;
    if (trackId == null || _playGeneration == 0) return;
    _recovering = true;
    _resumePosition = resumePosition;
    try {
      while (_expiryRetries < _maxStreamRecoveryAttempts) {
        _expiryRetries++;
        if (_expiryRetries > 1) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (_expiryRetries - 1)),
          );
        }
        if (recoveryGeneration != _recoveryGeneration ||
            occurrence != queueIndex ||
            currentTrack?.id != trackId ||
            !_playIntent ||
            _disposed) {
          return;
        }
        _resumePosition = resumePosition;
        await _playCurrent(fromRecovery: true);
        if (recoveryGeneration != _recoveryGeneration ||
            occurrence != queueIndex ||
            currentTrack?.id != trackId ||
            !_playIntent ||
            _disposed) {
          return;
        }
        if (_loadedTrackId == trackId &&
            audio.isPlaying &&
            audio.lastError == null) {
          _recoveryProgressPosition = audio.position;
          if (error == failedError) error = null;
          _notify();
          return;
        }
      }
    } finally {
      if (recoveryGeneration == _recoveryGeneration) _recovering = false;
    }
  }

  void _cancelRecovery() {
    ++_recoveryGeneration;
    _recovering = false;
  }

  void _cancelPendingResolution() {
    final videoId = _pendingResolveVideoId;
    _pendingResolveVideoId = null;
    if (videoId != null) {
      unawaited(source.cancel('resolve:$videoId').catchError((Object _) {}));
    }
  }

  Future<void> togglePlayback() async {
    if (_jamPlaybackActive) return;
    if (_playIntent && (audio.isPlaying || busy || _recovering)) {
      await pausePlayback();
      await _saveQueue();
    } else {
      await resumePlayback();
    }
  }

  Future<void> pausePlayback() async {
    if (_jamPlaybackActive) return;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    ++_playGeneration;
    busy = false;
    await audio.pause();
    _notify();
  }

  Future<void> stopPlayback() async {
    if (_jamPlaybackActive) return;
    stopPersonalDj();
    ++_playGeneration;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    busy = false;
    _recoverableRemoteTrackId = null;
    await audio.stop();
    _loadedAudioInput = null;
    _controls?.updateTrack(null);
    _loadedTrackId = null;
    _resumePosition = Duration.zero;
    await _saveQueue();
    _notify();
  }

  Future<void> seek(Duration position) async {
    if (_jamPlaybackActive) return;
    if (_loadedTrackId == null) return;
    try {
      await audio.seek(position);
      await _saveQueue();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> _onCompleted() async {
    if (_jamPlaybackActive) return;
    if (!_playIntent || _disposed) return;
    final duration = audio.duration;
    if (duration > Duration.zero &&
        audio.position + const Duration(milliseconds: 750) < duration) {
      return;
    }
    if (repeat == RepeatMode.one) {
      _resumePosition = Duration.zero;
      await _playCurrent();
      return;
    }
    final generation = _playGeneration;
    final occurrence = queueIndex;
    final hasNoUpcoming = shuffle
        ? queue.length - _shufflePlayed.length <= 0
        : queueIndex == queue.length - 1;
    if (_personalDjActive && hasNoUpcoming) {
      await _refillPersonalDjQueue();
      if (!_playIntent ||
          _disposed ||
          generation != _playGeneration ||
          occurrence != queueIndex) {
        return;
      }
    }
    await next();
  }

  Future<void> next() async {
    if (_jamPlaybackActive) return;
    if (queue.isEmpty) return;
    _playIntent = true;
    if (shuffle && queue.length > 1) {
      var candidates = List.generate(
        queue.length,
        (i) => i,
      ).where((i) => !_shufflePlayed.contains(i)).toList();
      if (candidates.isEmpty) {
        if (repeat != RepeatMode.all) {
          await stopPlayback();
          return;
        }
        _shufflePlayed
          ..clear()
          ..add(queueIndex);
        candidates = List.generate(
          queue.length,
          (i) => i,
        ).where((i) => i != queueIndex).toList();
      }
      _shuffleHistory.add(queueIndex);
      queueIndex = candidates[_random.nextInt(candidates.length)];
      _shufflePlayed.add(queueIndex);
    } else if (queueIndex + 1 < queue.length) {
      queueIndex++;
    } else if (repeat == RepeatMode.all) {
      queueIndex = 0;
    } else {
      await stopPlayback();
      return;
    }
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_jamPlaybackActive) return;
    if (audio.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    _playIntent = true;
    if (shuffle && _shuffleHistory.isNotEmpty) {
      queueIndex = _shuffleHistory.removeLast();
    } else {
      queueIndex = (queueIndex - 1).clamp(0, queue.length - 1);
    }
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> _saveQueue() async {
    if (_jamPlaybackActive) return;
    await preferences.setStringList('queue', queue.map((t) => t.id).toList());
    await preferences.setInt('queueIndex', queueIndex);
    await preferences.setInt(
      'position',
      (_loadedTrackId == null ? _resumePosition : audio.position)
          .inMilliseconds,
    );
  }

  Future<void> persistSession() => _saveQueue();
  Future<void> addToQueue(Track track) async {
    if (queue.any((queued) => recommendationTracksMatch(queued, track))) return;
    await _remember(track);
    // Recheck after persistence: concurrent enqueue calls may finish together.
    if (queue.any((queued) => recommendationTracksMatch(queued, track))) return;
    queue.add(track);
    if (_personalDjActive) {
      _personalDjSeenKeys.addAll(recommendationTrackKeys(track));
    }
    if (queueIndex < 0) queueIndex = 0;
    await _saveQueue();
    _notify();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    final currentRemoved = index == queueIndex;
    queue.removeAt(index);
    if (index < queueIndex || queueIndex >= queue.length) queueIndex--;
    _shuffleHistory.clear();
    _shufflePlayed.clear();
    if (currentRemoved) {
      _resumePosition = Duration.zero;
      if (queue.isEmpty) {
        queueIndex = -1;
        await stopPlayback();
      } else {
        queueIndex = index.clamp(0, queue.length - 1);
        await _playCurrent();
      }
    }
    await _saveQueue();
    _notify();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= queue.length ||
        newIndex < 0 ||
        newIndex > queue.length) {
      return;
    }
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = queue.removeAt(oldIndex);
    queue.insert(target, item);
    if (queueIndex == oldIndex) {
      queueIndex = target;
    } else if (oldIndex < queueIndex && target >= queueIndex) {
      queueIndex--;
    } else if (oldIndex > queueIndex && target <= queueIndex) {
      queueIndex++;
    }
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    await _saveQueue();
    _notify();
  }

  void setShuffle(bool value) {
    shuffle = value;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    unawaited(preferences.setBool('shuffle', value));
    _notify();
  }

  void cycleRepeat() {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    unawaited(preferences.setString('repeat', repeat.name));
    _notify();
  }

  Future<void> toggleFavorite(Track track) async {
    try {
      await _remember(track);
      final selected = !favoriteIds.contains(track.id);
      await database.setFavorite(track.id, selected);
      if (selected) {
        favoriteIds.add(track.id);
      } else {
        favoriteIds.remove(track.id);
      }
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    final playlist = MusicPlaylist(
      id: 'list_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
    );
    await database.savePlaylist(playlist);
    playlists.add(playlist);
    _notify();
  }

  Future<void> renamePlaylist(MusicPlaylist playlist, String name) async {
    if (name.trim().isEmpty) return;
    playlist = _latestPlaylist(playlist);
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: name.trim(),
        trackIds: playlist.trackIds,
      ),
    );
  }

  Future<void> deletePlaylist(MusicPlaylist playlist) async {
    await database.deletePlaylist(playlist.id);
    playlists.removeWhere((item) => item.id == playlist.id);
    _notify();
  }

  Future<void> _replacePlaylist(MusicPlaylist playlist) async {
    final index = playlists.indexWhere((item) => item.id == playlist.id);
    if (index < 0) return;
    playlists[index] = playlist;
    await database.savePlaylist(playlist);
    _notify();
  }

  MusicPlaylist _latestPlaylist(MusicPlaylist playlist) => playlists.firstWhere(
    (item) => item.id == playlist.id,
    orElse: () => playlist,
  );
  Future<void> addToPlaylist(MusicPlaylist playlist, Track track) async {
    await _remember(track);
    playlist = _latestPlaylist(playlist);
    if (playlist.trackIds.contains(track.id)) return;
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        trackIds: [...playlist.trackIds, track.id],
      ),
    );
  }

  Future<void> removeFromPlaylist(MusicPlaylist playlist, Track track) async {
    playlist = _latestPlaylist(playlist);
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        trackIds: playlist.trackIds.where((id) => id != track.id).toList(),
      ),
    );
  }

  Future<void> reorderPlaylist(
    MusicPlaylist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    playlist = _latestPlaylist(playlist);
    final ids = List.of(playlist.trackIds);
    if (oldIndex < 0 ||
        oldIndex >= ids.length ||
        newIndex < 0 ||
        newIndex > ids.length) {
      return;
    }
    ids.insert(
      newIndex > oldIndex ? newIndex - 1 : newIndex,
      ids.removeAt(oldIndex),
    );
    await _replacePlaylist(
      MusicPlaylist(id: playlist.id, name: playlist.name, trackIds: ids),
    );
  }

  Future<void> clearPlaybackCache() async {
    if (busy || clearingPlaybackCache) return;
    clearingPlaybackCache = true;
    playbackCacheMessage = null;
    _notify();
    try {
      final removed = await source.clearPlaybackCache(
        protectedPath: _loadedAudioInput,
      );
      playbackCacheMessage = removed == 0
          ? 'No hay archivos temporales que limpiar. La canción actual se conserva.'
          : 'Caché limpiada: ${(removed / (1024 * 1024)).toStringAsFixed(1)} MB liberados. La canción actual se conserva.';
    } catch (exception) {
      _report(exception);
    } finally {
      clearingPlaybackCache = false;
      _notify();
    }
  }

  Future<void> importFiles() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'opus', 'm4a', 'aac'],
      );
      if (selection.isEmpty) return;
      final directory = Directory(p.join(supportDirectory.path, 'imports'));
      await directory.create(recursive: true);
      for (final file in selection) {
        final path = file.path;
        if (path == null) continue;
        final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
        final destination = p.join(
          directory.path,
          '$id${p.extension(path).toLowerCase()}',
        );
        await File(path).copy(destination);
        await _remember(
          Track(
            id: id,
            title: p.basenameWithoutExtension(file.name),
            artist: 'Archivo local',
            localPath: destination,
          ),
        );
      }
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<SpotifyImportResult?> pickSpotifyImport() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
      );
      if (selection.isEmpty) return null;
      final file = selection.first;
      final path = file.path;
      if (path == null) {
        throw const FormatException(
          'No se pudo abrir el archivo seleccionado.',
        );
      }
      if (await File(path).length() > maxSpotifyImportBytes) {
        throw const FormatException('El archivo supera el límite de 20 MB.');
      }
      return SpotifyImportParser.parse(
        await File(path).readAsString(),
        extension: p.extension(file.name).replaceFirst('.', ''),
        fallbackPlaylistName: p.basenameWithoutExtension(file.name),
      );
    } catch (exception) {
      _report(exception);
      return null;
    }
  }

  Future<bool> importSpotifyPlaylists(
    List<SpotifyImportPlaylist> imported,
  ) async {
    if (imported.isEmpty) return false;
    busy = true;
    _notify();
    try {
      final stamp =
          '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
      var trackNumber = 0;
      final newTracks = <Track>[];
      final newPlaylists = <MusicPlaylist>[];
      for (
        var playlistNumber = 0;
        playlistNumber < imported.length;
        playlistNumber++
      ) {
        final playlist = imported[playlistNumber];
        final trackIds = <String>[];
        for (final importedTrack in playlist.tracks) {
          final track = Track(
            id: 'spotify_${stamp}_${trackNumber++}',
            title: importedTrack.title,
            artist: importedTrack.artist,
            album: importedTrack.album,
            spotifyUri: importedTrack.uri,
            spotifyMatchPending: true,
          );
          newTracks.add(track);
          trackIds.add(track.id);
        }
        newPlaylists.add(
          MusicPlaylist(
            id: 'spotify_list_${stamp}_$playlistNumber',
            name: playlist.name,
            trackIds: trackIds,
          ),
        );
      }
      await database.transaction(() async {
        for (final track in newTracks) {
          await database.saveTrack(track);
        }
        for (final playlist in newPlaylists) {
          await database.savePlaylist(playlist);
        }
      });
      tracks.insertAll(0, newTracks);
      playlists.addAll(newPlaylists);
      error = null;
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<List<Track>> findSpotifyMatches(Track track) =>
      source.search('${track.title} ${track.artist}', limit: 3);

  /// Spotify supplies descriptions only; the selected match supplies audio.
  Future<bool> importSpotifyMetadataMatch(
    Track metadata,
    Track match, {
    bool play = false,
  }) async {
    final uri = Uri.tryParse(match.pageUrl ?? '');
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final hasAudioPage =
        uri?.scheme == 'https' &&
        const {'youtube.com', 'music.youtube.com', 'youtu.be'}.contains(host);
    if (match.isPendingSpotifyMatch || (!match.isLocal && !hasAudioPage)) {
      _report(StateError('Selecciona una coincidencia de audio v\u00e1lida.'));
      return false;
    }
    final track = Track(
      id: match.id,
      title: metadata.title,
      artist: metadata.artist,
      duration: metadata.duration == Duration.zero
          ? match.duration
          : metadata.duration,
      artworkUrl: metadata.artworkUrl ?? match.artworkUrl,
      album: metadata.album ?? match.album,
      genres: metadata.genres.isEmpty ? match.genres : metadata.genres,
      spotifyUri: metadata.spotifyUri,
      pageUrl: match.pageUrl,
      localPath: match.localPath,
    );
    try {
      if (play) {
        await _remember(track);
        await playTrack(track);
      } else {
        await addToQueue(track);
      }
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    }
  }

  Future<bool> matchSpotifyTrack(
    String trackId,
    Track match, {
    bool play = false,
  }) async {
    final index = tracks.indexWhere((track) => track.id == trackId);
    if (index < 0 || !tracks[index].isPendingSpotifyMatch) return false;
    if (match.pageUrl == null || match.pageUrl!.isEmpty) {
      _report(
        StateError('El resultado no incluye un enlace de YouTube válido.'),
      );
      return false;
    }
    final original = tracks[index];
    final updated = original.copyWith(
      pageUrl: match.pageUrl,
      artworkUrl: match.artworkUrl,
      duration: match.duration,
      spotifyMatchPending: false,
    );
    try {
      await database.saveTrack(updated);
      tracks[index] = updated;
      for (var i = 0; i < queue.length; i++) {
        if (queue[i].id == trackId) queue[i] = updated;
      }
      error = null;
      _notify();
      if (play) {
        final queuePosition = queue.indexWhere((track) => track.id == trackId);
        if (queuePosition >= 0) {
          await playQueueAt(queuePosition);
        } else {
          await playTrack(updated);
        }
      }
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    }
  }

  Future<void> importPlaylist(String url) async {
    busy = true;
    _notify();
    try {
      final imported = await source.importPlaylist(Uri.parse(url.trim()));
      for (final track in imported) {
        await _remember(track);
      }
      final playlist = MusicPlaylist(
        id: 'list_${DateTime.now().microsecondsSinceEpoch}',
        name: 'Lista importada',
        trackIds: imported.map((item) => item.id).toList(),
      );
      await database.savePlaylist(playlist);
      playlists.add(playlist);
    } catch (exception) {
      _report(exception);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> downloadTrack(Track track) async {
    if (track.isLocal ||
        downloads.any(
          (job) =>
              job.track.id == track.id &&
              (job.status == DownloadStatus.queued ||
                  job.status == DownloadStatus.downloading ||
                  job.status == DownloadStatus.completed),
        )) {
      return;
    }
    late final String destinationRoot;
    try {
      final directory = Directory(downloadsDirectoryPath);
      if (downloadsDirectoryPath ==
          p.join(supportDirectory.path, 'downloads')) {
        await directory.create(recursive: true);
      }
      destinationRoot = await _canonicalDownloadRoot(downloadsDirectoryPath);
      await _remember(track);
    } catch (exception) {
      _report(exception);
      return;
    }
    final job = DownloadJob(
      id: 'job_${DateTime.now().microsecondsSinceEpoch}',
      track: track,
      destinationRoot: destinationRoot,
    );
    downloads.insert(0, job);
    await database.saveDownload(job);
    _notify();
    if (!_processingDownloads) {
      _downloadWorker = _processDownloads();
      unawaited(_downloadWorker);
    }
  }

  Future<void> _processDownloads() async {
    if (_processingDownloads || _disposed) return;
    _processingDownloads = true;
    try {
      while (!_disposed) {
        final waiting = downloads.where(
          (job) => job.status == DownloadStatus.queued,
        );
        if (waiting.isEmpty) break;
        final job = waiting.last;
        job.status = DownloadStatus.downloading;
        await database.saveDownload(job);
        if (_disposed) return;
        if (job.status == DownloadStatus.cancelled) continue;
        _notify();
        try {
          final directory = Directory(job.destinationRoot!);
          await directory.create(recursive: true);
          if (_disposed) return;
          final safeId = _safeDownloadId(job.track.id);
          final destination = File(p.join(directory.path, '$safeId.mp3'));
          if (await destination.exists()) {
            throw FileSystemException(
              'El archivo de destino ya existe.',
              destination.path,
            );
          }
          await source.download(
            job.track,
            destination,
            jobId: job.id,
            onProgress: (progress) {
              if (job.status != DownloadStatus.downloading) return;
              job.progress = progress.clamp(0, 1);
              _notify();
            },
          );
          if (_disposed) return;
          if (job.status != DownloadStatus.cancelled) {
            job.status = DownloadStatus.completed;
            job.progress = 1;
            job.localPath = destination.path;
            final downloaded = job.track.copyWith(localPath: destination.path);
            await _remember(downloaded);
            queue = queue
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
            searchResults = searchResults
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
            recentTracks = recentTracks
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
          } else if (await destination.exists()) {
            final root = await directory.resolveSymbolicLinks();
            final target = await destination.resolveSymbolicLinks();
            if (p.dirname(target) == root &&
                p.basename(target) == '${_safeDownloadId(job.track.id)}.mp3') {
              await File(target).delete();
            }
          }
        } catch (exception) {
          if (_disposed) return;
          if (job.status != DownloadStatus.cancelled) {
            job.status = DownloadStatus.failed;
            job.error = exception.toString();
          }
        }
        if (_disposed) return;
        await database.saveDownload(job);
        _notify();
      }
    } finally {
      _processingDownloads = false;
    }
  }

  Future<void> cancelDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.queued &&
        job.status != DownloadStatus.downloading) {
      return;
    }
    job.status = DownloadStatus.cancelled;
    await source.cancel(job.id);
    await database.saveDownload(job);
    _notify();
  }

  Future<void> retryDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.failed &&
        job.status != DownloadStatus.cancelled) {
      return;
    }
    await downloadTrack(job.track);
  }

  Future<void> removeDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.completed) return;
    try {
      final localPath = job.localPath;
      if (localPath != null && await File(localPath).exists()) {
        final root = await _canonicalDownloadRoot(
          job.destinationRoot ?? p.join(supportDirectory.path, 'downloads'),
        );
        final file = File(localPath);
        final absolutePath = p.normalize(p.absolute(file.path));
        final expectedName = '${_safeDownloadId(job.track.id)}.mp3';
        final target = await file.resolveSymbolicLinks();
        if (!p.equals(p.dirname(absolutePath), root) ||
            p.basename(absolutePath) != expectedName ||
            !p.equals(p.dirname(target), root) ||
            p.basename(target) != expectedName) {
          throw StateError('La descarga está fuera de la carpeta de Aurora.');
        }
        if (currentTrack?.id == job.track.id && !_usingRemote) {
          _resumePosition = audio.position;
          ++_playGeneration;
          await audio.stop();
          _loadedTrackId = null;
          _controls?.updateTrack(null);
        }
        await File(target).delete();
      }
      final remembered = tracks
          .where((track) => track.id == job.track.id)
          .firstOrNull;
      if (remembered != null) {
        final updated = remembered.copyWith(clearLocalPath: true);
        tracks = tracks
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        queue = queue
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        searchResults = searchResults
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        recentTracks = recentTracks
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        await database.saveTrack(updated);
      }
      await database.deleteDownload(job.id);
      downloads.removeWhere((item) => item.id == job.id);
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<String> _canonicalDownloadRoot(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) throw ArgumentError('La carpeta no existe.');
    final root = await directory.resolveSymbolicLinks();
    final probe = File(
      p.join(root, '.aurora-write-${DateTime.now().microsecondsSinceEpoch}'),
    );
    try {
      await probe.writeAsBytes(const []);
    } finally {
      if (await probe.exists()) await probe.delete();
    }
    return p.normalize(root);
  }

  String _safeDownloadId(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<void> configureDownloadDirectory(String? path) async {
    if (!canConfigureDownloadDirectory) {
      error = 'La carpeta de descargas no se puede configurar en Android.';
      _notify();
      return;
    }
    if (downloads.any(
      (job) =>
          job.status == DownloadStatus.queued ||
          job.status == DownloadStatus.downloading,
    )) {
      _report(
        StateError(
          'Espera a que terminen las descargas antes de cambiar la carpeta.',
        ),
      );
      return;
    }
    try {
      final selected = path ?? p.join(supportDirectory.path, 'downloads');
      if (path == null) await Directory(selected).create(recursive: true);
      final root = await _canonicalDownloadRoot(selected);
      await preferences.setString('downloadsDirectory', root);
      error = null;
    } catch (exception) {
      _report(exception);
    }
    _notify();
  }

  Future<void> chooseDownloadDirectory() async {
    if (!canConfigureDownloadDirectory) return configureDownloadDirectory('');
    if (configuringDownloadDirectory) return;
    configuringDownloadDirectory = true;
    _notify();
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected != null) await configureDownloadDirectory(selected);
    } catch (exception) {
      _report(exception);
    } finally {
      configuringDownloadDirectory = false;
      _notify();
    }
  }

  Future<void> openDownloadDirectory() async {
    if (!Platform.isWindows) {
      _report(
        UnsupportedError(
          'Abrir la carpeta de descargas no está disponible en Android.',
        ),
      );
      return;
    }
    try {
      final root = p.normalize(p.absolute(downloadsDirectoryPath));
      await Directory(root).create(recursive: true);
      await Process.start('explorer.exe', [
        root,
      ], mode: ProcessStartMode.detached);
    } catch (exception) {
      _report(exception);
    }
  }

  void setVolume(double value) {
    audio.setVolume(value.clamp(0, 1));
    unawaited(preferences.setDouble('volume', value.clamp(0, 1)));
    _notify();
  }

  void setEqualizerEnabled(bool value) {
    eqEnabled = value;
    audio.setEqualizer(value, eqGains);
    unawaited(preferences.setBool('eqEnabled', value));
    _notify();
  }

  void setExperimentalProgressivePlayback(bool value) {
    if (!source.supportsExperimentalProgressivePlayback ||
        experimentalProgressivePlayback == value) {
      return;
    }
    experimentalProgressivePlayback = value;
    source.setExperimentalProgressivePlayback(value);
    unawaited(preferences.setBool('experimentalProgressivePlayback', value));
    _notify();
  }

  void setEqGain(int index, double value) {
    if (index < 0 || index >= eqGains.length) return;
    eqGains[index] = value.clamp(-12, 12);
    audio.setEqualizer(eqEnabled, eqGains);
    unawaited(
      preferences.setStringList(
        'eqGains',
        eqGains.map((v) => v.toString()).toList(),
      ),
    );
    _notify();
  }

  void applyEqPreset(String name) {
    eqGains = switch (name) {
      'Graves' => [6, 3, 0, -1, -2, -2, -2, 0],
      'Vocal' => [-3, 2, 4, 2, -1, -2, -2, 0],
      'Rock' => [4, 1, -2, 1, 3, 2, 1, 0],
      _ => List.filled(8, 0),
    };
    audio.setEqualizer(eqEnabled, eqGains);
    unawaited(
      preferences.setStringList(
        'eqGains',
        eqGains.map((v) => v.toString()).toList(),
      ),
    );
    _notify();
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    unawaited(preferences.setString('themeMode', value.name));
    _notify();
  }

  void setAdaptiveColors(bool value) {
    setAccentPalette(value ? 'automatic' : 'terracotta');
  }

  void setAccentPalette(String value) {
    if (value != 'automatic' && !accentPaletteColors.containsKey(value)) return;
    accentPalette = value;
    adaptiveColors = value == 'automatic';
    unawaited(preferences.setString('accentPalette', value));
    unawaited(preferences.setBool('adaptiveColors', adaptiveColors));
    if (adaptiveColors && currentTrack != null) {
      unawaited(_updateAccent(currentTrack!));
    } else {
      accentColor = accentPaletteColors[value] ?? const Color(0xffe86927);
      _notify();
    }
  }

  void setReducedMotion(bool value) {
    reducedMotion = value;
    unawaited(preferences.setBool('reducedMotion', value));
    _notify();
  }

  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    _sleepEnd = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (sleepRemaining == Duration.zero) {
          timer.cancel();
          _sleepEnd = null;
          unawaited(pausePlayback());
        }
        _notify();
      });
    }
    _notify();
  }

  Future<void> _updateAccent(Track track) async {
    const fallback = Color(0xffe86927);
    if (!adaptiveColors) {
      accentColor = accentPaletteColors[accentPalette] ?? fallback;
      _notify();
      return;
    }
    if (track.artworkUrl == null) {
      accentColor = fallback;
      _notify();
      return;
    }
    final key = 'palette_${track.id}';
    final cached = preferences.getInt(key);
    if (cached != null) {
      accentColor = Color(cached);
      _notify();
      return;
    }
    ui.Codec? codec;
    ui.Image? image;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(track.artworkUrl!);
      if (uri.scheme != 'https') return;
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200 ||
          response.contentLength > 2 * 1024 * 1024) {
        return;
      }
      final builder = BytesBuilder(copy: false);
      await for (final bytes in response.timeout(const Duration(seconds: 5))) {
        builder.add(bytes);
        if (builder.length > 2 * 1024 * 1024) return;
      }
      codec = await ui.instantiateImageCodec(
        builder.takeBytes(),
        targetWidth: 32,
        targetHeight: 32,
      );
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return;
      final buckets = <int, int>{};
      final bytes = pixels.buffer.asUint8List();
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final color = HSLColor.fromColor(
          Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]),
        );
        if (color.saturation < 0.25 ||
            color.lightness < 0.12 ||
            color.lightness > 0.9) {
          continue;
        }
        final bucket = (color.hue / 15).floor();
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      var selected = fallback;
      if (buckets.isNotEmpty) {
        final best = buckets.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        selected = HSLColor.fromAHSL(
          1,
          best * 15.0 + 7.5,
          0.65,
          0.65,
        ).toColor();
      }
      if (currentTrack?.id != track.id || !adaptiveColors || _disposed) {
        return;
      }
      await preferences.setInt(key, selected.toARGB32());
      if (currentTrack?.id == track.id && adaptiveColors && !_disposed) {
        accentColor = selected;
        _notify();
      }
    } catch (_) {
      if (currentTrack?.id == track.id && adaptiveColors && !_disposed) {
        accentColor = fallback;
        _notify();
      }
    } finally {
      image?.dispose();
      codec?.dispose();
      client.close(force: true);
    }
  }

  Future<void> importYouTubeSession() async {
    if (sessionBusy) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        dialogTitle: 'Importar cookies.txt de tu sesión de YouTube',
      );
      if (files.isEmpty || files.first.path == null || _disposed) return;
      await configureYouTubeSession(File(files.first.path!));
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> configureYouTubeSession(File selected) async {
    if (sessionBusy || _disposed) return;
    sessionBusy = true;
    _notify();
    File? copy;
    try {
      if (await selected.length() > 1024 * 1024) {
        throw ArgumentError(
          'El archivo de sesión debe ocupar como máximo 1 MiB.',
        );
      }
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty || bytes.length > 1024 * 1024) {
        throw ArgumentError(
          'El archivo de sesión debe ocupar como máximo 1 MiB.',
        );
      }
      final directory = Directory(p.join(supportDirectory.path, 'session'));
      await directory.create(recursive: true);
      final root = await supportDirectory.resolveSymbolicLinks();
      final target = await directory.resolveSymbolicLinks();
      if (!p.isWithin(root, target)) {
        throw StateError('La carpeta de sesión está fuera de Aurora.');
      }
      copy = File(
        p.join(target, 'youtube-${DateTime.now().microsecondsSinceEpoch}.txt'),
      );
      await copy.writeAsBytes(bytes, flush: true);
      final previous = source.cookieFile;
      await source.configureCookieFile(copy.path);
      copy = null;
      if (previous != selected.absolute.path) {
        await _deleteSessionFile(previous);
      }
      error = null;
      diagnostics =
          'Sesión de YouTube importada. Puedes volver a intentar la búsqueda.';
    } catch (exception) {
      if (copy != null && await copy.exists()) await copy.delete();
      _report(exception);
    } finally {
      sessionBusy = false;
      _notify();
    }
  }

  Future<void> clearYouTubeSession() async {
    if (sessionBusy || _disposed) return;
    sessionBusy = true;
    _notify();
    try {
      final previous = source.cookieFile;
      await source.configureCookieFile(null);
      await _deleteSessionFile(previous);
      diagnostics = 'Sesión de YouTube eliminada de Aurora.';
      _notify();
    } catch (exception) {
      _report(exception);
    } finally {
      sessionBusy = false;
      _notify();
    }
  }

  Future<void> _deleteSessionFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final root = await supportDirectory.resolveSymbolicLinks();
    final directory = p.join(root, 'session');
    final target = await file.resolveSymbolicLinks();
    if (p.isWithin(directory, target)) await File(target).delete();
  }

  Future<void> configureTools() async {
    if (!Platform.isWindows) {
      await runDiagnostics();
      return;
    }
    try {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle:
            'Carpeta con yt-dlp.exe, ffmpeg.exe, ffprobe.exe y deno.exe',
      );
      if (directory == null) return;
      await source.configureToolDirectory(directory);
      await preferences.setString('toolDirectory', directory);
      await runDiagnostics();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> runDiagnostics() async {
    diagnosing = true;
    _notify();
    try {
      diagnostics = await source.diagnose();
    } catch (exception) {
      diagnostics = exception.toString();
    } finally {
      diagnosing = false;
      _notify();
    }
  }

  Future<void> clearCache() async {
    try {
      if (_processingDownloads) {
        throw StateError(
          'Espera a que terminen las descargas antes de limpiar la caché.',
        );
      }
      final directory = Directory(p.join(supportDirectory.path, 'cache'));
      if (await directory.exists()) {
        final root = await supportDirectory.resolveSymbolicLinks();
        final target = await directory.resolveSymbolicLinks();
        if (!p.isWithin(root, target)) {
          throw StateError('La caché está fuera de la carpeta de Aurora.');
        }
        await Directory(target).delete(recursive: true);
      }
      final downloadsDirectory = Directory(
        p.join(supportDirectory.path, 'downloads'),
      );
      if (await downloadsDirectory.exists()) {
        final root = await downloadsDirectory.resolveSymbolicLinks();
        await for (final entry in downloadsDirectory.list(followLinks: false)) {
          if (entry is! Directory ||
              !p.basename(entry.path).startsWith('.aurora-')) {
            continue;
          }
          final target = await entry.resolveSymbolicLinks();
          if (p.isWithin(root, target)) {
            await Directory(target).delete(recursive: true);
          }
        }
      }
      for (final key
          in preferences
              .getKeys()
              .where((key) => key.startsWith('palette_'))
              .toList()) {
        await preferences.remove(key);
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      diagnostics =
          'Caché temporal eliminada. Tu biblioteca y descargas se conservaron.';
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_playGeneration;
    ++_searchGeneration;
    _sleepTimer?.cancel();
    unawaited(_completedSubscription?.cancel());
    audio.removeListener(_audioChanged);
    unawaited(_saveQueue());
    if (_controls != null) unawaited(_controls!.dispose());
    audio.dispose();
    source.dispose();
    unawaited(_closeDatabase());
    super.dispose();
  }

  Future<void> _closeDatabase() async {
    try {
      await _downloadWorker;
    } finally {
      try {
        await database.close();
      } finally {
        _closed.complete();
      }
    }
  }
}
