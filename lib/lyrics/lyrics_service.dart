import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../core/models.dart';

enum LyricsKind { synced, plain, instrumental, notFound }

class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

class LyricsResult {
  const LyricsResult(this.kind, {this.lines = const [], this.text = ''});
  final LyricsKind kind;
  final List<LyricLine> lines;
  final String text;
}

class LyricsService {
  LyricsService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;
  static const maxBytes = 1024 * 1024;
  static const timeout = Duration(seconds: 10);
  final HttpClient Function() _clientFactory;
  bool _disposed = false;
  int _generation = 0;
  final Set<HttpClient> _clients = {};

  static List<LyricLine> parseLrc(String input) {
    final out = <LyricLine>[];
    var offset = 0;
    final lyricLines = input.split(RegExp(r'\r?\n'));
    for (final line in lyricLines) {
      final off = RegExp(
        r'\[offset:([+-]?\d+)\]',
        caseSensitive: false,
      ).firstMatch(line);
      if (off != null) offset = int.tryParse(off.group(1)!) ?? 0;
    }
    for (final line in lyricLines) {
      if (RegExp(r'\[offset:[+-]?\d+\]', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      final tags = RegExp(
        r'\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]',
      ).allMatches(line).toList();
      if (tags.isEmpty) continue;
      final validTags = tags
          .where((tag) => (int.tryParse(tag.group(2)!) ?? 60) < 60)
          .toList();
      if (validTags.isEmpty) continue;
      final lyric = line
          .replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:\.\d{1,3})?\]'), '')
          .trim();
      if (lyric.isEmpty) continue;
      for (final tag in validTags) {
        final fraction = (tag.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        final millis =
            (int.tryParse(tag.group(1)!) ?? 0) * 60000 +
            (int.tryParse(tag.group(2)!) ?? 0) * 1000 +
            (int.tryParse(fraction) ?? 0) +
            offset;
        out.add(
          LyricLine(Duration(milliseconds: millis.clamp(0, 1 << 60)), lyric),
        );
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static String _queryTitle(String s) => s
      .replaceAll(
        RegExp(
          r'\s*[-–|]\s*(official\s+)?(music\s+)?(video|audio|lyrics?)(\s+\w+)*\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\s*\([^)]*(official|video|audio|lyrics?)[^)]*\)',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  static String _clean(String s) => _queryTitle(
    s,
  ).toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  static (String, String) _metadata(Track track) {
    final split = RegExp(r'^(.+?)\s+-\s+(.+)$').firstMatch(track.title);
    if (split != null && _clean(split.group(1)!) == _clean(track.artist)) {
      return (track.artist, _queryTitle(split.group(2)!));
    }
    return (track.artist, _queryTitle(track.title));
  }

  Future<LyricsResult> load(Track track, Directory supportDirectory) async {
    final generation = ++_generation;
    final local = await _readCache(track, supportDirectory);
    if (_disposed || generation != _generation) {
      return const LyricsResult(LyricsKind.notFound);
    }
    if (local != null) return _result(local);
    final (artist, title) = _metadata(track);
    final client = _clientFactory()..connectionTimeout = timeout;
    _clients.add(client);
    try {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'artist_name': artist,
        'track_name': title,
      });
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        return const LyricsResult(LyricsKind.notFound);
      }
      if (response.statusCode != 200) {
        throw HttpException('Lyrics service returned ${response.statusCode}.');
      }
      final bytes = await _readBounded(response).timeout(timeout);
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic> ||
          !_matches(data, artist, title, track.duration)) {
        return const LyricsResult(LyricsKind.notFound);
      }
      if (data['instrumental'] == true) {
        return const LyricsResult(LyricsKind.instrumental);
      }
      final synced = data['syncedLyrics'];
      final plain = data['plainLyrics'];
      final content = synced is String && synced.trim().isNotEmpty
          ? synced
          : plain is String
          ? plain
          : '';
      if (content.isEmpty) return const LyricsResult(LyricsKind.notFound);
      if (_disposed || generation != _generation) {
        return const LyricsResult(LyricsKind.notFound);
      }
      await _writeCache(track, supportDirectory, content);
      return _result(content);
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  static Future<List<int>> _readBounded(HttpClientResponse response) async {
    if (response.contentLength > maxBytes) {
      throw const FormatException('Lyrics exceed 1 MiB.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('Lyrics exceed 1 MiB.');
      }
    }
    return builder.takeBytes();
  }

  static bool _matches(
    Map<String, dynamic> data,
    String artist,
    String title,
    Duration duration,
  ) =>
      _clean('${data['artistName'] ?? ''}') == _clean(artist) &&
      _clean('${data['trackName'] ?? ''}') == _clean(title) &&
      (duration <= Duration.zero ||
          (data['duration'] is num &&
              ((data['duration'] as num) - duration.inSeconds).abs() <= 2));
  static LyricsResult _result(String content) {
    final lines = parseLrc(content);
    if (lines.isNotEmpty) return LyricsResult(LyricsKind.synced, lines: lines);
    final text = content.trim();
    return text.isEmpty
        ? const LyricsResult(LyricsKind.notFound)
        : LyricsResult(LyricsKind.plain, text: text);
  }

  String _path(Track track, Directory root) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(track.id)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return p.join(
      root.path,
      'lyrics',
      '${hash.toRadixString(16).padLeft(8, '0')}.txt',
    );
  }

  Future<String?> _readCache(Track track, Directory root) async {
    final file = File(_path(track, root));
    if (!await file.exists() || await file.length() > maxBytes) return null;
    final content = await file.readAsString();
    // Cache payload is prefixed with the exact track ID to prevent filename collisions.
    final marker = 'AURORA-LYRICS:${track.id}\n';
    return content.startsWith(marker) ? content.substring(marker.length) : null;
  }

  Future<void> _writeCache(Track track, Directory root, String content) async {
    if (_disposed) return;
    Directory(p.join(root.path, 'lyrics')).createSync(recursive: true);
    final bytes = utf8.encode('AURORA-LYRICS:${track.id}\n$content');
    if (bytes.length > maxBytes) {
      throw const FormatException('Lyrics exceed 1 MiB.');
    }
    await File(_path(track, root)).writeAsBytes(bytes, flush: true);
  }

  Future<LyricsResult?> importFile(Track track, Directory root) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    if (files.isEmpty || files.first.path == null || _disposed) return null;
    final source = File(files.first.path!);
    final input = source.openRead(0, maxBytes + 1);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in input) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('Choose a lyrics file up to 1 MiB.');
      }
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Choose a lyrics file up to 1 MiB.');
    }
    final content = utf8.decode(bytes, allowMalformed: false);
    await _writeCache(track, root, content);
    return _result(content);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
