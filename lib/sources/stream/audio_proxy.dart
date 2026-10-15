import 'dart:async';
import 'dart:io';

import 'resolved_stream.dart';

/// Loopback range proxy in front of googlevideo (127.0.0.1 only).
class AudioProxy {
  AudioProxy._();

  static Future<AudioProxy> start({
    int chunkBytes = 4 << 20,
    int maxUpstream = 6,
    Duration headerTimeout = const Duration(seconds: 15),
    Duration stallTimeout = const Duration(seconds: 20),
    HttpClient? client,
  }) => throw UnimplementedError();

  Uri register(
    String videoId,
    ResolvedStream stream, {
    required Future<ResolvedStream> Function() refresh,
    void Function(int? status, String reason)? onFailure,
  }) => throw UnimplementedError();

  ResolvedStream? current(String videoId) => throw UnimplementedError();

  void unregister(String videoId) => throw UnimplementedError();

  Future<void> close() => throw UnimplementedError();
}
