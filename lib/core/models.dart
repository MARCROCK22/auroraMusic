enum RepeatMode { off, all, one }

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.duration = Duration.zero,
    this.artworkUrl,
    this.pageUrl,
    this.localPath,
  });
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String? artworkUrl;
  final String? pageUrl;
  final String? localPath;
  bool get isLocal => localPath != null;
  Track copyWith({
    String? localPath,
    Duration? duration,
    bool clearLocalPath = false,
  }) => Track(
    id: id,
    title: title,
    artist: artist,
    duration: duration ?? this.duration,
    artworkUrl: artworkUrl,
    pageUrl: pageUrl,
    localPath: clearLocalPath ? null : localPath ?? this.localPath,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'durationMs': duration.inMilliseconds,
    'artworkUrl': artworkUrl,
    'pageUrl': pageUrl,
    'localPath': localPath,
  };
  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    artworkUrl: json['artworkUrl'] as String?,
    pageUrl: json['pageUrl'] as String?,
    localPath: json['localPath'] as String?,
  );
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    this.trackIds = const [],
  });
  final String id;
  final String name;
  final List<String> trackIds;
}

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.track,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
    this.localPath,
  });
  final String id;
  final Track track;
  DownloadStatus status;
  double progress;
  String? error;
  String? localPath;
}

class ResolvedAudio {
  const ResolvedAudio({
    required this.input,
    this.headers = const {},
    this.duration = Duration.zero,
  });
  final String input;
  final Map<String, String> headers;
  final Duration duration;
}
