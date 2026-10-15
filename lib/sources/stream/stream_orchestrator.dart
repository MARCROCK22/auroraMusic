import 'dart:async';

import 'player_clients.dart';
import 'resolved_stream.dart';

typedef PlayerPost =
    Future<Map<String, dynamic>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, Object?> body,
    );

class HttpGetResult {
  const HttpGetResult(
    this.statusCode, {
    this.body = '',
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

typedef HttpGet =
    Future<HttpGetResult> Function(
      Uri url,
      Map<String, String> headers, {
      Duration timeout,
    });

/// Resolves a videoId to a validated audio stream with client fallback.
class StreamOrchestrator {
  StreamOrchestrator({
    PlayerPost? post,
    HttpGet? get,
    List<PlayerClient>? clients,
    this.preferMp4a = false,
    DateTime Function()? now,
  });

  final bool preferMp4a;

  Future<ResolvedStream> resolve(
    String videoId, {
    bool forceRefresh = false,
    Duration? trackDuration,
    int? sameItag,
  }) => throw UnimplementedError();

  void reportFailure(String videoId, {int? httpStatus, String? reason}) =>
      throw UnimplementedError();

  bool isBlacklisted(String videoId) => throw UnimplementedError();
}
