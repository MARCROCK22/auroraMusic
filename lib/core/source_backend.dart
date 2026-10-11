import 'dart:io';
import 'models.dart';

abstract class SourceBackend {
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
