import '../youtube_request_policy.dart';

/// How a resolved stream reaches the player: never [direct] for YouTube media.
enum StreamBackend { direct, proxy }

/// A validated googlevideo audio URL plus everything needed to fetch it again.
class ResolvedStream {
  const ResolvedStream({
    required this.videoId,
    required this.url,
    required this.expiresAt,
    required this.client,
    required this.itag,
    this.headers = const {},
    this.backend = StreamBackend.direct,
    this.mimeType,
    this.contentLength,
    this.duration,
  });

  final String videoId;
  final Uri url;

  /// Only the issuing client's User-Agent; the CDN binds URLs to it.
  final Map<String, String> headers;
  final DateTime expiresAt;
  final String client;
  final int itag;
  final StreamBackend backend;
  final String? mimeType;
  final int? contentLength;

  /// Real length from the player response (`approxDurationMs`), if known.
  final Duration? duration;

  bool expiredAt(
    DateTime now, {
    Duration margin = const Duration(seconds: 30),
  }) => !now.isBefore(expiresAt.subtract(margin));

  ResolvedStream withBackend(StreamBackend value) => ResolvedStream(
    videoId: videoId,
    url: url,
    expiresAt: expiresAt,
    client: client,
    itag: itag,
    headers: headers,
    backend: value,
    mimeType: mimeType,
    contentLength: contentLength,
    duration: duration,
  );
}

class StreamResolveException implements Exception {
  const StreamResolveException(this.kind, this.message);

  final YouTubeFailure kind;

  /// Must keep [YouTubeRequestPolicy.classify] mapping to [kind].
  final String message;

  @override
  String toString() => message;
}
