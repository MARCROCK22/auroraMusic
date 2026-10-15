import 'dart:async';
import 'dart:io' show SocketException;

import 'player_clients.dart';
import 'resolved_stream.dart';

typedef PlayerPost =
    Future<Map<String, dynamic>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, Object?> body,
    );

/// Non-2xx reply from [PlayerPost]/[HttpGet] implementations. Network
/// failures throw [SocketException]/[TimeoutException] instead.
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode, [this.message = '']);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode $message'.trim();
}

class HttpGetResult {
  const HttpGetResult(
    this.statusCode, {
    this.body = const [],
    this.headers = const {},
  });

  final int statusCode;

  /// Raw bytes; the tail probe gets binary data, so never decode strictly.
  final List<int> body;
  final Map<String, String> headers;
}

typedef HttpGet =
    Future<HttpGetResult> Function(
      Uri url,
      Map<String, String> headers, {
      // Implementations declare a default (10 s).
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
