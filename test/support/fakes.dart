import 'dart:async';
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/audio_backend.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/library_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudio extends AudioBackend {
  @override
  String? lastError;
  @override
  bool isPlaying = false;
  @override
  bool isBuffering = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  double volume = 0.75;
  @override
  final ValueNotifier<List<double>> spectrum = ValueNotifier<List<double>>(
    List.filled(32, 0),
  );
  @override
  List<double> get eqFrequencies => [
    375,
    1500,
    3375,
    6000,
    9375,
    13500,
    18375,
    24000,
  ];
  final completions = StreamController<void>.broadcast();
  @override
  Stream<void> get completed => completions.stream;
  ResolvedAudio? loaded;
  int loadCount = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    loaded = source;
    loadCount++;
    position = start;
    lastError = null;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  void setVolume(double value) {
    volume = value;
    notifyListeners();
  }

  @override
  void setEqualizer(bool enabled, List<double> gainsDb) {}
  @override
  void setVisualizationEnabled(bool enabled) {}
  @override
  void dispose() {
    spectrum.dispose();
    unawaited(completions.close());
    super.dispose();
  }
}

class FakeSource extends SourceBackend {
  Completer<List<Track>>? pendingSearch;
  final resolved = <String>[];
  final pendingResolves = <String, Completer<ResolvedAudio>>{};
  int activeDownloads = 0;
  int maxActiveDownloads = 0;
  Completer<void>? downloadGate;
  Object? cookieError;
  @override
  String? cookieFile;
  @override
  Future<void> configureCookieFile(String? path) async {
    if (cookieError != null && path != null) throw cookieError!;
    cookieFile = path;
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async =>
      pendingSearch?.future ?? [];
  @override
  Future<List<Track>> importPlaylist(Uri url) async => [];
  @override
  Future<ResolvedAudio> resolve(Track track) async {
    resolved.add(track.id);
    return pendingResolves[track.id]?.future ??
        ResolvedAudio(
          input: 'https://example.test/${track.id}',
          duration: track.duration,
        );
  }

  @override
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    activeDownloads++;
    if (activeDownloads > maxActiveDownloads) {
      maxActiveDownloads = activeDownloads;
    }
    try {
      await downloadGate?.future;
      onProgress?.call(0.5);
      await destination.writeAsBytes([1, 2, 3]);
    } finally {
      activeDownloads--;
    }
  }

  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<String> diagnose() async => 'Herramientas disponibles';
  @override
  Future<void> configureToolDirectory(String directory) async {
    toolDirectory = directory;
  }

  @override
  String? toolDirectory;
  @override
  String? get ffmpegExecutable => null;
  @override
  void dispose() {}
}

Future<AppController> createTestController({
  List<Track> tracks = const [],
  List<MusicPlaylist> playlists = const [],
  FakeAudio? audio,
  FakeSource? source,
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  final prefs = await SharedPreferences.getInstance();
  final directory = await Directory.systemTemp.createTemp('aurora_test_');
  final database = LibraryDatabase(NativeDatabase.memory());
  for (final track in tracks) {
    await database.saveTrack(track);
  }
  for (final playlist in playlists) {
    await database.savePlaylist(playlist);
  }
  final controller = AppController(
    audio: audio ?? FakeAudio(),
    source: source ?? FakeSource(),
    database: database,
    preferences: prefs,
    supportDirectory: directory,
  );
  await controller.initialize(mediaControls: false);
  return controller;
}

Future<void> closeTestController(AppController controller) async {
  controller.dispose();
  await controller.closed;
  if (await controller.supportDirectory.exists()) {
    await controller.supportDirectory.delete(recursive: true);
  }
}
