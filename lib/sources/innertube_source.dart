import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../core/source_backend.dart';

typedef InnerTubePost =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, Object?> body,
    );

/// YouTube Music search (InnerTube). Playback resolves to the official watch
/// page; yt-dlp stays for downloads and playlist imports.
class InnerTubeSource extends SourceBackend {
  InnerTubeSource(this.delegate, {InnerTubePost? post})
    : _post = post ?? _httpPost;

  final SourceBackend delegate;
  final InnerTubePost _post;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _clock = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$');
  static const _clientVersion = '1.20250101.01.00';
  // YouTube Music search filters (one category byte differs).
  static const _params = {
    SearchKind.songs: 'EgWKAQIIAWoKEAkQBRAKEAMQBA==',
    SearchKind.albums: 'EgWKAQIYAWoKEAkQBRAKEAMQBA==',
    SearchKind.artists: 'EgWKAQIgAWoKEAkQBRAKEAMQBA==',
    SearchKind.videos: 'EgWKAQIQAWoKEAkQBRAKEAMQBA==',
  };
  static const _timeout = Duration(seconds: 15);

  static bool isValidVideoId(String id) => _videoId.hasMatch(id);

  static Future<Map<String, dynamic>> _httpPost(
    String endpoint,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(
        Uri.https('music.youtube.com', '/youtubei/v1/$endpoint', {
          'prettyPrint': 'false',
        }),
      );
      request.headers
        ..contentType = ContentType.json
        ..set('Origin', 'https://music.youtube.com');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'YouTube Music respondió ${response.statusCode} a la búsqueda.',
        );
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on TimeoutException {
      throw StateError('YouTube Music no respondió a tiempo.');
    } on SocketException {
      throw StateError('Sin conexión con YouTube Music.');
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, Object?> _context() => {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': _clientVersion,
      'hl': 'es',
    },
  };

  @override
  bool get supportsOnlineMetadataSearch => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    if (limit <= 0) return [];
    final page = await searchPage(query, SearchKind.songs);
    return page.tracks.take(limit).toList();
  }

  @override
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return const SearchPage();
    if (text.length > 500) {
      throw ArgumentError('La búsqueda es demasiado larga.');
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      return continuation != null
          ? const SearchPage()
          : SearchPage(tracks: await delegate.search(text));
    }
    final data = await _post(
      'search',
      continuation == null
          ? {'context': _context(), 'query': text, 'params': _params[kind]}
          : {'context': _context(), 'continuation': continuation},
    );
    return parseSearchPage(data, kind);
  }

  @override
  Future<List<Track>> browseTracks(SearchEntry entry) async {
    final data = await _post('browse', {
      'context': _context(),
      'browseId': entry.browseId,
    });
    final album = entry.kind == SearchKind.albums;
    return parseBrowseTracks(
      data,
      artist: album
          ? entry.subtitle.split(' • ').skip(1).firstOrNull
          : entry.title,
      album: album ? entry.title : null,
      artwork: album ? entry.artworkUrl : null,
    );
  }

  static SearchPage parseSearchPage(
    Map<String, dynamic> data,
    SearchKind kind,
  ) {
    String? token;
    void find(Object? node) {
      if (token != null) return;
      if (node is Map) {
        token =
            node['nextContinuationData']?['continuation'] as String? ??
            node['continuationItemRenderer']?['continuationEndpoint']?['continuationCommand']?['token']
                as String?;
        node.values.forEach(find);
      } else if (node is List) {
        node.forEach(find);
      }
    }

    find(data);
    if (kind == SearchKind.songs || kind == SearchKind.videos) {
      return SearchPage(tracks: parseSearch(data), continuation: token);
    }
    final wanted = kind == SearchKind.albums
        ? 'MUSIC_PAGE_TYPE_ALBUM'
        : 'MUSIC_PAGE_TYPE_ARTIST';
    final seen = <String>{};
    final entries = <SearchEntry>[];
    for (final row in _rows(data)) {
      final browse = row['navigationEndpoint']?['browseEndpoint'] as Map?;
      final id = browse?['browseId'] as String?;
      final page =
          browse?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
      final columns = _columns(row);
      if (id == null ||
          page != wanted ||
          columns.isEmpty ||
          columns.first.isEmpty ||
          !seen.add(id)) {
        continue;
      }
      entries.add(
        SearchEntry(
          kind: kind,
          browseId: id,
          title: (columns.first.first as Map)['text'] as String? ?? '',
          subtitle: columns.length > 1
              ? columns[1].map((r) => (r as Map)['text'] ?? '').join()
              : '',
          artworkUrl: _artwork(row['thumbnail']),
        ),
      );
    }
    return SearchPage(entries: entries, continuation: token);
  }

  /// Parses `musicResponsiveListItemRenderer` rows of a search response.
  static List<Track> parseSearch(Map<String, dynamic> data) =>
      parseBrowseTracks(data);

  /// Track rows of a search, album page or artist songs shelf. A page header
  /// owns artist/album/artwork, so rows fall back to the given values.
  static List<Track> parseBrowseTracks(
    Map<String, dynamic> data, {
    String? artist,
    String? album,
    String? artwork,
  }) {
    final seen = <String>{};
    final tracks = <Track>[];
    for (final row in _rows(data)) {
      final track = _row(row, artist, album, artwork);
      if (track != null && seen.add(track.id)) tracks.add(track);
    }
    return tracks;
  }

  static List<Map> _rows(Object? root) {
    final rows = <Map>[];
    void walk(Object? node) {
      if (node is Map) {
        final row = node['musicResponsiveListItemRenderer'];
        if (row is Map) {
          rows.add(row);
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(root);
    return rows;
  }

  static List<List> _columns(Map row) =>
      (row['flexColumns'] as List? ?? const [])
          .map(
            (c) =>
                ((c as Map?)?['musicResponsiveListItemFlexColumnRenderer']
                        as Map?)?['text']?['runs']
                    as List? ??
                const [],
          )
          .toList();

  static Duration? _clockOf(String text) {
    final clock = _clock.firstMatch(text.trim());
    return clock == null
        ? null
        : Duration(
            hours: int.parse(clock[1] ?? '0'),
            minutes: int.parse(clock[2]!),
            seconds: int.parse(clock[3]!),
          );
  }

  static Track? _row(
    Map row,
    String? fbArtist,
    String? fbAlbum,
    String? fbArt,
  ) {
    final columns = _columns(row);
    if (columns.isEmpty || columns.first.isEmpty) return null;
    final titleRun = columns.first.first as Map;
    final id =
        row['playlistItemData']?['videoId'] as String? ??
        titleRun['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
    final title = titleRun['text'] as String?;
    if (id == null || !_videoId.hasMatch(id) || title == null) return null;
    final artists = <String>[];
    String? album;
    Duration? duration;
    final details = columns.length > 1 ? columns[1] : const [];
    for (final run in details.whereType<Map>()) {
      final text = (run['text'] as String? ?? '').trim();
      final page =
          run['navigationEndpoint']?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
      if (page == 'MUSIC_PAGE_TYPE_ALBUM') {
        album = text;
      } else if (page == 'MUSIC_PAGE_TYPE_ARTIST' ||
          page == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
        artists.add(text);
      } else {
        duration ??= _clockOf(text);
      }
    }
    if (artists.isEmpty && fbArtist != null) artists.add(fbArtist);
    if (artists.isEmpty && details.isNotEmpty) {
      final first = ((details.first as Map)['text'] as String? ?? '').trim();
      if (first.isNotEmpty && _clockOf(first) == null) artists.add(first);
    }
    final fixed =
        (((row['fixedColumns'] as List?)?.firstOrNull
                    as Map?)?['musicResponsiveListItemFixedColumnRenderer']
                as Map?)?['text']?['runs']
            as List?;
    duration ??= _clockOf(
      (fixed?.firstOrNull as Map?)?['text'] as String? ?? '',
    );
    return Track(
      id: 'yt:$id',
      title: title,
      artist: artists.isEmpty ? 'YouTube Music' : artists.join(', '),
      album: album ?? fbAlbum,
      duration: duration ?? Duration.zero,
      artworkUrl: _artwork(row['thumbnail']) ?? fbArt,
      pageUrl: 'https://music.youtube.com/watch?v=$id',
    );
  }

  static String? _artwork(Object? thumbnail) {
    final list =
        ((thumbnail as Map?)?['musicThumbnailRenderer']?['thumbnail']
                as Map?)?['thumbnails']
            as List? ??
        const [];
    Map? best;
    for (final image in list.whereType<Map>()) {
      final uri = Uri.tryParse(image['url'] as String? ?? '');
      if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        continue;
      }
      if (best == null ||
          (image['width'] as num? ?? 0) > (best['width'] as num? ?? 0)) {
        best = image;
      }
    }
    final url = best?['url'] as String?;
    // Music thumbnails are resizable; the listing only offers 60/120 px.
    return url?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
  }

  String? _youTubeId(Track track) {
    final page = Uri.tryParse(track.pageUrl ?? '');
    final id = track.id.startsWith('yt:')
        ? track.id.substring(3)
        : page?.host == 'youtu.be'
        ? page?.pathSegments.firstOrNull
        : page != null && page.host.endsWith('youtube.com')
        ? page.queryParameters['v']
        : null;
    return id != null && _videoId.hasMatch(id) ? id : null;
  }

  /// YouTube plays in the official music.youtube.com player (WebMusicAudio);
  /// nothing is extracted. yt-dlp is reserved for explicit downloads.
  @override
  Future<ResolvedAudio> resolve(Track track) async {
    if (track.isLocal && await File(track.localPath!).exists()) {
      return ResolvedAudio(input: track.localPath!, duration: track.duration);
    }
    final id = _youTubeId(track);
    if (id == null) {
      throw StateError(
        'Solo se pueden reproducir canciones de YouTube Music o archivos locales.',
      );
    }
    return ResolvedAudio(
      input: Uri.https('music.youtube.com', '/watch', {'v': id}).toString(),
      duration: track.duration,
    );
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) => delegate.importPlaylist(url);
  @override
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) => delegate.download(
    track,
    destination,
    jobId: jobId,
    onProgress: onProgress,
  );
  @override
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) => delegate.downloadVideo(
    url,
    destination,
    jobId: jobId,
    onProgress: onProgress,
  );
  @override
  Future<void> cancel(String jobId) => delegate.cancel(jobId);
  @override
  void reportPlaybackFailure(String message) =>
      delegate.reportPlaybackFailure(message);
  @override
  String? get toolUpdateMessage => delegate.toolUpdateMessage;
  @override
  bool get updatingTools => delegate.updatingTools;
  @override
  Future<void> initializeUpdates({
    required bool Function() isPlaybackActive,
    required void Function() onStatusChanged,
  }) => delegate.initializeUpdates(
    isPlaybackActive: isPlaybackActive,
    onStatusChanged: onStatusChanged,
  );
  @override
  Future<void> checkForUpdates() => delegate.checkForUpdates();
  @override
  Future<String> diagnose() => delegate.diagnose();
  @override
  Future<void> configureToolDirectory(String directory) =>
      delegate.configureToolDirectory(directory);
  @override
  Future<void> configureCookieFile(String? path) =>
      delegate.configureCookieFile(path);
  @override
  String? get cookieFile => delegate.cookieFile;
  @override
  String? get toolDirectory => delegate.toolDirectory;
  @override
  String? get ffmpegExecutable => delegate.ffmpegExecutable;
  @override
  void dispose() {
    delegate.dispose();
  }
}
