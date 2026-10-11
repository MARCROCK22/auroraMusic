import 'dart:io';
import 'models.dart';

abstract class SourceBackend {
  bool get supportsPlaybackCache => false;
  Future<({int bytes, int files})> playbackCacheInfo() async =>
      (bytes: 0, files: 0);

  /// Returns bytes removed while preserving the loaded audio at [protectedPath].
  Future<int> clearPlaybackCache({String? protectedPath}) async => 0;
  Future<List<Track>> search(String query, {int limit = 20});
  Future<List<Track>> importPlaylist(Uri url);
  Future<ResolvedAudio> resolve(Track track);
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  });
  Future<void> cancel(String jobId);
  Future<String> diagnose();
  Future<void> configureToolDirectory(String directory);
  Future<void> configureCookieFile(String? path);
  String? get cookieFile;
  String? get toolDirectory;
  String? get ffmpegExecutable;
  void dispose();
}
