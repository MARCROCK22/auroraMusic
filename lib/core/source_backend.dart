import 'dart:io';
import 'models.dart';

abstract class SourceBackend {
  bool get usesOfficialYouTubeMusic => false;
  bool get usesYouTubeWebAudio => false;
  bool get supportsOnlineMetadataSearch => false;

  bool get supportsExperimentalProgressivePlayback => false;

  /// Applies to the next resolve; an already loaded input keeps its mode.
  void setExperimentalProgressivePlayback(bool enabled) {}

  bool get supportsPlaybackCache => false;
  Future<({int bytes, int files})> playbackCacheInfo() async =>
      (bytes: 0, files: 0);

  /// Returns bytes removed while preserving the loaded audio at [protectedPath].
  Future<int> clearPlaybackCache({String? protectedPath}) async => 0;
  Future<List<Track>> search(String query, {int limit = 20});
  Future<List<Track>> importPlaylist(Uri url);
  Future<ResolvedAudio> resolve(Track track);

  /// Warms the stream URL of an upcoming track; must swallow its own errors.
  Future<void> prefetch(Track track) async {}

  /// Called before a bounded retry of an expired or interrupted stream.
  void invalidateResolvedAudio(Track track) {}
  void reportPlaybackFailure(String message) {}
  bool isExpiredStream(Track track) => false;
  String? get toolUpdateMessage => null;
  bool get updatingTools => false;
  Future<void> initializeUpdates({
    required bool Function() isPlaybackActive,
    required void Function() onStatusChanged,
  }) async {}
  Future<void> checkForUpdates() async {}
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  });
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async => throw UnsupportedError('La fuente no permite descargar videos.');
  Future<void> cancel(String jobId);
  Future<String> diagnose();
  Future<void> configureToolDirectory(String directory);
  Future<void> configureCookieFile(String? path);
  String? get cookieFile;
  String? get toolDirectory;
  String? get ffmpegExecutable;
  void dispose();
}
