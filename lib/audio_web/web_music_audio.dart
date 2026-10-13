import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';
import '../youtube_music/youtube_music_ad_blocker.dart';
import 'web_music_bridge.dart';

export 'web_music_bridge.dart' show WebMusicBridge, NativeWebMusicBridge;

/// Experimental official-page bridge: hidden video presentation, not audio-only
/// network transport. The website retains account, consent and media policies.
class WebMusicAudio extends AudioBackend {
  WebMusicAudio({
    WebMusicBridge? bridge,
    this.pollInterval = const Duration(milliseconds: 500),
    this.mediaWaitTimeout = const Duration(seconds: 45),
  }) : _bridge = bridge ?? NativeWebMusicBridge();

  final WebMusicBridge _bridge;
  final Duration pollInterval;
  final Duration mediaWaitTimeout;
  final _spectrum = ValueNotifier<List<double>>(List.filled(48, 0));
  final _completed = StreamController<void>.broadcast();
  Timer? _timer;
  Widget? _view;
  Uri? _target;
  DateTime? _waitingSince;
  int _generation = 0;
  bool _disposed = false, _sampling = false, _ended = false;
  bool _playIntent = false, _playing = false, _buffering = false;
  bool needsWebsiteAccess = false, adPlaying = false;
  String title = '', artist = '';
  Duration _position = Duration.zero, _duration = Duration.zero;
  Duration _pendingSeek = Duration.zero;
  double _volume = 0.8;
  Future<void> _operations = Future.value();
  Future<void>? _initialization;

  @override
  bool get supportsEqualizer => false;
  @override
  bool get supportsVisualization => false;
  @override
  String? lastError;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isBuffering => _buffering;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get volume => _volume;
  @override
  List<double> get eqFrequencies => const [];
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  YouTubeMusicAdBlocker? get adBlocker => _bridge.adBlocker;

  Track? get currentTrackMetadata => _target == null || title.isEmpty
      ? null
      : Track(
          id: 'yt:${_target!.queryParameters['v']}',
          title: title,
          artist: artist,
          duration: _duration,
          pageUrl: _target.toString(),
        );

  static Uri validateInput(String input) {
    final uri = Uri.tryParse(input);
    final id = uri?.queryParameters['v'];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'music.youtube.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/watch' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['v']?.length != 1 ||
        id == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      throw ArgumentError('Se requiere un enlace oficial de canción válido.');
    }
    return Uri.https('music.youtube.com', '/watch', {'v': id});
  }

  /// Mount exactly once after initialize, inside the persistent app shell.
  /// Toggle visibility in place for consent/playback errors; do not reparent it.
  Widget buildEngineView({bool showWebsite = false}) => SizedBox(
    width: showWebsite ? double.infinity : 1,
    height: showWebsite ? double.infinity : 1,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: !showWebsite,
          child: IgnorePointer(
            ignoring: !showWebsite,
            child: _view ??= _bridge.buildView(),
          ),
        ),
        if (!showWebsite)
          const Positioned.fill(child: ColoredBox(color: Color(0xff000000))),
      ],
    ),
  );

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _bridge.onFailure = _failure;
    _bridge.onNavigation = (uri) {
      if (uri?.host != 'music.youtube.com' && _target != null) {
        _failure(
          'Abre la página oficial para revisar el consentimiento o acceso.',
        );
      }
    };
    await _bridge.initialize();
    if (_disposed) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  void _failure(String message) {
    if (_disposed) return;
    lastError = message;
    needsWebsiteAccess = true;
    _playIntent = false;
    _playing = _buffering = false;
    notifyListeners();
  }

  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    final target = validateInput(source.input);
    if (source.headers.isNotEmpty) {
      throw ArgumentError('La sesión permanece dentro de la vista oficial.');
    }
    ++_generation;
    _target = target;
    _playIntent = _playing = _ended = adPlaying = false;
    _buffering = true;
    needsWebsiteAccess = false;
    lastError = null;
    title = artist = '';
    _position = _duration = Duration.zero;
    _pendingSeek = start;
    _waitingSince = DateTime.now();
    notifyListeners();
    try {
      await _bridge.navigate(target);
    } catch (_) {
      _failure('No se pudo abrir la canción en la página oficial.');
      rethrow;
    }
  }

  Future<void> _command(String action, [double? value]) {
    final generation = _generation;
    final target = _target;
    final result = _operations.then((_) async {
      if (_disposed || target == null || generation != _generation) return;
      try {
        final snapshot = await _bridge
            .command(
              action,
              videoId: target.queryParameters['v']!,
              generation: generation,
              value: value,
            )
            .timeout(const Duration(seconds: 8));
        if (!_disposed && generation == _generation) _receive(snapshot);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          _failure(
            'No respondió el reproductor web. Abre la página para revisar.',
          );
        }
      }
    });
    _operations = result.catchError((Object _) {});
    return result;
  }

  /// Samples actual page media state; also a deterministic fake-bridge test seam.
  Future<void> refresh() async {
    if (_disposed || _target == null || _sampling) return;
    _sampling = true;
    try {
      await _command('snapshot');
    } finally {
      _sampling = false;
    }
  }

  void _receive(Map<String, dynamic>? data) {
    if (data == null || data['status'] == 'waiting') {
      if (_waitingSince != null &&
          DateTime.now().difference(_waitingSince!) > mediaWaitTimeout) {
        _failure('No hay audio disponible todavía. Abre la página oficial.');
      }
      return;
    }
    switch (data['status']) {
      case 'website':
        _failure('La página necesita consentimiento o acceso.');
        return;
      case 'differentTrack':
        // During initial navigation the previous document may still be active.
        if (_waitingSince != null) return;
        if (needsWebsiteAccess) return;
        _failure(
          'El sitio cambió de canción. Selecciona una canción en Aurora.',
        );
        unawaited(_command('pause'));
        return;
      case 'playBlocked':
        _failure(
          'El sitio requiere una acción. Abre la página y pulsa reproducir.',
        );
        return;
      case 'seekUnavailable':
        lastError = 'La búsqueda no está disponible durante anuncios o carga.';
        notifyListeners();
        return;
      case 'commandFailed':
        _failure('El sitio no pudo aplicar ese control.');
        return;
    }
    if (data['generation'] != _generation ||
        data['videoId'] != _target?.queryParameters['v']) {
      return;
    }
    _waitingSince = null;
    if (data['mediaError'] is num && data['mediaError'] != 0) {
      _failure('El sitio no pudo reproducir este contenido.');
      return;
    }
    adPlaying = data['adPlaying'] == true;
    _playing = data['playing'] == true;
    _buffering = data['buffering'] == true;
    if (_playing) {
      needsWebsiteAccess = false;
      lastError = null;
    }
    if (!adPlaying) {
      _position = _seconds(data['position']);
      _duration = _seconds(data['duration']);
      title = _text(data['title']);
      artist = _text(data['artist']);
      if (data['ended'] == true && !_ended) {
        _ended = true;
        _playIntent = _playing = _buffering = false;
        _completed.add(null);
      }
    }
    notifyListeners();
  }

  static Duration _seconds(Object? value) => value is num && value.isFinite
      ? Duration(milliseconds: (value.clamp(0, 864000) * 1000).round())
      : Duration.zero;
  static String _text(Object? value) =>
      value is String ? value.substring(0, value.length.clamp(0, 500)) : '';

  @override
  Future<void> play() async {
    if (_target == null || _disposed) {
      throw StateError('Selecciona una canción.');
    }
    final generation = _generation;
    _playIntent = true;
    _ended = false;
    needsWebsiteAccess = false;
    lastError = null;
    final deadline = DateTime.now().add(mediaWaitTimeout);
    while (_waitingSince != null &&
        !needsWebsiteAccess &&
        generation == _generation &&
        !_disposed &&
        DateTime.now().isBefore(deadline)) {
      await _command('snapshot');
      if (_waitingSince != null && !needsWebsiteAccess) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (generation != _generation || _disposed || !_playIntent) return;
    if (_waitingSince != null && !needsWebsiteAccess) {
      _failure(
        'La página no presentó audio a tiempo. Abre el sitio para revisar.',
      );
    }
    if (!needsWebsiteAccess) {
      await _command('volume', _volume);
      if (_pendingSeek > Duration.zero) {
        final pending = _pendingSeek;
        _pendingSeek = Duration.zero;
        await seek(pending);
      }
      await _command('play');
    }
    if (generation == _generation && needsWebsiteAccess) {
      throw StateError(lastError ?? 'El sitio no pudo reproducir.');
    }
  }

  @override
  Future<void> pause() {
    _playIntent = false;
    return _command('pause');
  }

  @override
  Future<void> stop() async {
    final generation = _generation;
    _playIntent = false;
    await _command('pause');
    if (generation != _generation || _disposed) return;
    ++_generation;
    _target = null;
    _playing = _buffering = false;
    _position = _duration = Duration.zero;
    await _bridge.navigate(Uri.https('music.youtube.com', '/'));
    if (!_disposed) notifyListeners();
  }

  @override
  Future<void> seek(Duration position) =>
      _command('seek', position.inMilliseconds.clamp(0, 864000000) / 1000);

  @override
  void setVolume(double volume) {
    if (!volume.isFinite) return;
    _volume = volume.clamp(0, 1);
    unawaited(_command('volume', _volume));
    if (!_disposed) notifyListeners();
  }

  @override
  void setEqualizer(bool enabled, List<double> gainsDb) {}
  @override
  void setVisualizationEnabled(bool enabled) {}

  @override
  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    final target = _target;
    if (target != null) {
      unawaited(
        _bridge
            .command(
              'pause',
              videoId: target.queryParameters['v']!,
              generation: _generation,
            )
            .catchError((Object _) => null),
      );
    }
    _disposed = true;
    ++_generation;
    _bridge.dispose();
    _spectrum.dispose();
    unawaited(_completed.close());
    super.dispose();
  }
}
