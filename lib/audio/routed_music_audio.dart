import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';
import '../audio_web/web_music_metadata.dart';

/// Aurora owns one queue; the source selects the web or native playback engine.
class RoutedMusicAudio extends AudioBackend {
  RoutedMusicAudio({required this.native, required this.web, this.metadata})
    : _active = native {
    native.addListener(_nativeChanged);
    web.addListener(_webChanged);
    _nativeCompleted = native.completed.listen((_) {
      if (identical(_active, native)) _completed.add(null);
    });
    _webCompleted = web.completed.listen((_) {
      if (identical(_active, web)) _completed.add(null);
    });
  }

  final AudioBackend native;
  final AudioBackend web;
  final WebMusicMetadata? metadata;
  AudioBackend _active;
  final _completed = StreamController<void>.broadcast();
  late final StreamSubscription<void> _nativeCompleted;
  late final StreamSubscription<void> _webCompleted;
  int _generation = 0;
  bool _disposed = false;
  double _volume = 0.75;
  String? webInitializationError;
  bool get usingWeb => identical(_active, web);

  void _nativeChanged() {
    if (!_disposed && !usingWeb) notifyListeners();
  }

  void _webChanged() {
    if (!_disposed && usingWeb) notifyListeners();
  }

  @override
  bool get supportsEqualizer => _active.supportsEqualizer;
  @override
  bool get supportsVisualization => _active.supportsVisualization;
  @override
  String? get lastError => _active.lastError;
  @override
  bool get isPlaying => _active.isPlaying;
  @override
  bool get isBuffering => _active.isBuffering;
  @override
  Duration get position => _active.position;
  @override
  Duration get duration => _active.duration;
  @override
  double get volume => _volume;
  @override
  List<double> get eqFrequencies => _active.eqFrequencies;
  @override
  ValueListenable<List<double>> get spectrum => _active.spectrum;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get mediaActions => native.mediaActions;
  @override
  Track? get currentTrackMetadata => _active.currentTrackMetadata;
  @override
  Future<void> updateTrackMetadata(Track track) =>
      usingWeb ? Future<void>.value() : native.updateTrackMetadata(track);

  @override
  Future<void> initialize() async {
    await native.initialize();
    try {
      await web.initialize();
      webInitializationError = null;
    } catch (_) {
      webInitializationError =
          'No se pudo iniciar WebView. La reproducción local sigue disponible; '
          'en Windows comprueba Microsoft Edge WebView2 Runtime.';
    }
  }

  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    final revision = ++_generation;
    final uri = Uri.tryParse(source.input);
    final next = uri?.scheme == 'https' && uri?.host == 'music.youtube.com'
        ? web
        : native;
    if (identical(next, web) && webInitializationError != null) {
      throw StateError(webInitializationError!);
    }
    if (identical(_active, web) && identical(next, web)) {
      await web.pause();
    } else {
      await _active.stop();
    }
    if (_disposed || revision != _generation) return;
    _active = next;
    _active.setVolume(_volume);
    notifyListeners();
    await next.load(source, ffmpegExecutable: ffmpegExecutable, start: start);
  }

  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> seek(Duration position) => _active.seek(position);
  @override
  Future<void> stop() async {
    ++_generation;
    await _active.stop();
  }

  @override
  void setVolume(double value) {
    if (!value.isFinite || _disposed) return;
    _volume = value.clamp(0, 1);
    native.setVolume(_volume);
    web.setVolume(_volume);
  }

  @override
  void setEqualizer(bool enabled, List<double> gainsDb) =>
      native.setEqualizer(enabled, gainsDb);
  @override
  void setVisualizationEnabled(bool enabled) =>
      native.setVisualizationEnabled(enabled && !usingWeb);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    native.removeListener(_nativeChanged);
    web.removeListener(_webChanged);
    unawaited(_nativeCompleted.cancel());
    unawaited(_webCompleted.cancel());
    unawaited(_completed.close());
    native.dispose();
    web.dispose();
    metadata?.dispose();
    super.dispose();
  }
}
