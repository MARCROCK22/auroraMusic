import 'dart:convert';

const maxSpotifyImportBytes = 20 * 1024 * 1024;
const maxSpotifyImportTracks = 20000;

class SpotifyImportTrack {
  const SpotifyImportTrack({
    required this.title,
    required this.artist,
    this.album = '',
    this.uri,
  });

  final String title;
  final String artist;
  final String album;
  final String? uri;
}

class SpotifyImportPlaylist {
  const SpotifyImportPlaylist({required this.name, required this.tracks});

  final String name;
  final List<SpotifyImportTrack> tracks;
}

class SpotifyImportResult {
  const SpotifyImportResult({required this.playlists, required this.skipped});

  final List<SpotifyImportPlaylist> playlists;
  final int skipped;
}

class SpotifyImportParser {
  static SpotifyImportResult parse(
    String contents, {
    String? extension,
    String? fallbackPlaylistName,
  }) {
    if (utf8.encode(contents).length > maxSpotifyImportBytes) {
      throw const FormatException('El archivo supera el límite de 20 MB.');
    }
    final type = extension?.toLowerCase();
    if (type == 'csv') {
      return _parseCsv(contents, fallbackPlaylistName: fallbackPlaylistName);
    }
    if (type == 'json') return _parseJson(contents);
    final trimmed = contents.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[')
        ? _parseJson(contents)
        : _parseCsv(contents, fallbackPlaylistName: fallbackPlaylistName);
  }

  static SpotifyImportResult _parseJson(String contents) {
    final root = jsonDecode(contents);
    if (root is! Map<String, dynamic> || root['playlists'] is! List) {
      throw const FormatException('El JSON no contiene la lista «playlists».');
    }
    var total = 0;
    var skipped = 0;
    final playlists = <SpotifyImportPlaylist>[];
    for (final rawPlaylist in root['playlists'] as List) {
      if (rawPlaylist is! Map<String, dynamic> ||
          rawPlaylist['name'] is! String ||
          rawPlaylist['items'] is! List) {
        throw const FormatException('Una lista tiene un formato inválido.');
      }
      final tracks = <SpotifyImportTrack>[];
      for (final rawItem in rawPlaylist['items'] as List) {
        if (++total > maxSpotifyImportTracks) {
          throw const FormatException(
            'El archivo contiene demasiadas canciones.',
          );
        }
        final track = rawItem is Map<String, dynamic> ? rawItem['track'] : null;
        if (track is! Map<String, dynamic>) {
          skipped++;
          continue;
        }
        final title = _string(track['trackName']);
        final artist = _string(track['artistName']);
        if (title.isEmpty || artist.isEmpty) {
          skipped++;
          continue;
        }
        final uri = track['trackUri'];
        if (!_isTrackUri(uri)) {
          skipped++;
          continue;
        }
        tracks.add(
          SpotifyImportTrack(
            title: title,
            artist: artist,
            album: _string(track['albumName']),
            uri: _trackUri(uri),
          ),
        );
      }
      playlists.add(
        SpotifyImportPlaylist(
          name: (rawPlaylist['name'] as String).trim(),
          tracks: tracks,
        ),
      );
    }
    return SpotifyImportResult(playlists: playlists, skipped: skipped);
  }

  static SpotifyImportResult _parseCsv(
    String contents, {
    String? fallbackPlaylistName,
  }) {
    final rows = _csvRows(contents);
    if (rows.isEmpty) throw const FormatException('El CSV está vacío.');
    final header = {
      for (var i = 0; i < rows.first.length; i++) _normalize(rows.first[i]): i,
    };
    final titleColumn = _column(header, const ['track name', 'name']);
    final artistColumn = _column(header, const [
      'artist name',
      'artist name(s)',
      'artist(s)',
      'artists',
    ]);
    final albumColumn = _column(header, const ['album name', 'album']);
    final playlistColumn = _column(header, const [
      'playlistname',
      'playlist name',
    ]);
    final uriColumn = _column(header, const ['track uri', 'uri']);
    if (titleColumn == null || artistColumn == null) {
      throw const FormatException(
        'El CSV requiere las columnas Track Name y Artist Name(s).',
      );
    }
    final fallback = _string(fallbackPlaylistName).isEmpty
        ? 'Lista importada'
        : _string(fallbackPlaylistName);
    final grouped = <String, List<SpotifyImportTrack>>{};
    var skipped = 0;
    var total = 0;
    for (final row in rows.skip(1)) {
      if (row.every((value) => value.trim().isEmpty)) continue;
      if (row.length > rows.first.length) {
        throw const FormatException(
          'Una fila CSV tiene más columnas que el encabezado.',
        );
      }
      final title = _cell(row, titleColumn);
      final artist = _cell(row, artistColumn);
      final playlist = playlistColumn == null
          ? fallback
          : _cell(row, playlistColumn);
      if (title.isEmpty || artist.isEmpty || playlist.isEmpty) {
        skipped++;
        continue;
      }
      if (++total > maxSpotifyImportTracks) {
        throw const FormatException(
          'El archivo contiene demasiadas canciones.',
        );
      }
      final uri = uriColumn == null ? '' : _cell(row, uriColumn);
      if (uri.isNotEmpty && !_isTrackUri(uri)) {
        skipped++;
        continue;
      }
      (grouped[playlist] ??= []).add(
        SpotifyImportTrack(
          title: title,
          artist: artist,
          album: albumColumn == null ? '' : _cell(row, albumColumn),
          uri: _trackUri(uri),
        ),
      );
    }
    return SpotifyImportResult(
      playlists: [
        for (final entry in grouped.entries)
          SpotifyImportPlaylist(name: entry.key, tracks: entry.value),
      ],
      skipped: skipped,
    );
  }

  static List<List<String>> _csvRows(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"' && i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else if (char == '"') {
          quoted = false;
        } else {
          cell.write(char);
        }
      } else if (char == '"' && cell.isEmpty) {
        quoted = true;
      } else if (char == ',') {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if (char == '\n' || char == '\r') {
        row.add(cell.toString());
        if (rows.length >= maxSpotifyImportTracks + 1) {
          throw const FormatException(
            'El archivo contiene demasiadas canciones.',
          );
        }
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      } else {
        cell.write(char);
      }
    }
    if (quoted) {
      throw const FormatException('El CSV tiene comillas sin cerrar.');
    }
    if (row.isNotEmpty || cell.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  static int? _column(Map<String, int> columns, List<String> names) {
    for (final name in names) {
      final index = columns[_normalize(name)];
      if (index != null) return index;
    }
    return null;
  }

  static String _normalize(String value) => value
      .replaceAll('\uFEFF', '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _cell(List<String> row, int index) =>
      index < row.length ? row[index].trim() : '';

  static String _string(Object? value) => value is String ? value.trim() : '';

  static bool _isTrackUri(Object? value) =>
      value is String &&
      RegExp(r'^spotify:track:[A-Za-z0-9]+$').hasMatch(value.trim());

  static String? _trackUri(Object? value) =>
      _isTrackUri(value) ? (value as String).trim() : null;
}
