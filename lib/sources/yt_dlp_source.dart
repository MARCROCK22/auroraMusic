import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models.dart';
import '../core/source_backend.dart';

class YtDlpSource extends SourceBackend {
  YtDlpSource(this._preferences) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = call.arguments as Map;
        _progress[args['jobId']]?.call((args['progress'] as num).toDouble());
      }
    });
  }
  final SharedPreferences _preferences;
  static const _channel = MethodChannel('aurora/source');
  final Map<String, Process> _jobs = {};
  final Set<String> _cancelled = {};
  final Map<String, void Function(double)> _progress = {};
  int _activeOperations = 0;
  bool _changingCookie = false;
  @override
  String? get cookieFile => _preferences.getString('cookieFile');

  @override
  Future<void> configureCookieFile(String? path) async {
    if (_activeOperations > 0 || _changingCookie) {
      throw StateError(
        'Espera a que terminen las búsquedas o descargas antes de cambiar la sesión.',
      );
    }
    _changingCookie = true;
    try {
      if (path == null) {
        await _preferences.remove('cookieFile');
        return;
      }
      final absolute = await _validateCookieFile(path);
      await _preferences.setString('cookieFile', absolute);
    } finally {
      _changingCookie = false;
    }
  }

  Future<String> _operation(Future<String> Function() execute) async {
    if (_changingCookie) {
      throw StateError('Espera a que termine el cambio de sesión.');
    }
    _activeOperations++;
    try {
      return await execute();
    } finally {
      _activeOperations--;
    }
  }

  Future<String> _validateCookieFile(String path) async {
    final file = File(path).absolute;
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(
        'El archivo de sesión no está disponible. Impórtalo nuevamente.',
      );
    }
    final length = await file.length();
    if (length == 0 || length > 1024 * 1024) {
      throw ArgumentError(
        'El archivo de sesión debe ocupar como máximo 1 MiB.',
      );
    }
    final String text;
    try {
      text = await file.readAsString();
    } on FormatException {
      throw ArgumentError(
        'El archivo de sesión tiene un formato inválido. Expórtalo nuevamente.',
      );
    }
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty ||
        !const {
          '# Netscape HTTP Cookie File',
          '# HTTP Cookie File',
        }.contains(lines.first)) {
      throw ArgumentError('Usa un archivo de cookies en formato Netscape.');
    }
    // Validate without including any cookie value in errors or diagnostics.
    var youtubeRows = 0;
    for (var line in lines.skip(1)) {
      if (line.startsWith('#HttpOnly_')) line = line.substring(10);
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields = line.split('\t');
      if (fields.length != 7 ||
          fields[0].isEmpty ||
          !const {'TRUE', 'FALSE'}.contains(fields[1]) ||
          fields[0].startsWith('.') != (fields[1] == 'TRUE') ||
          !const {'TRUE', 'FALSE'}.contains(fields[3]) ||
          (fields[4].isNotEmpty && int.tryParse(fields[4]) == null)) {
        throw ArgumentError(
          'El archivo de sesión tiene un formato inválido. Expórtalo nuevamente.',
        );
      }
      if (const {'youtube.com', '.youtube.com'}.contains(fields[0])) {
        youtubeRows++;
      }
    }
    if (youtubeRows == 0) {
      throw ArgumentError(
        'El archivo de sesión debe incluir cookies de YouTube.',
      );
    }
    return file.path;
  }

  @override
  String? get toolDirectory {
    final configured = _preferences.getString('toolDirectory');
    if (configured != null) return configured;
    if (!Platform.isWindows) return null;
    final adjacent = p.join(p.dirname(Platform.resolvedExecutable), 'tools');
    return File(p.join(adjacent, 'yt-dlp.exe')).existsSync() &&
            File(p.join(adjacent, 'ffmpeg.exe')).existsSync() &&
            File(p.join(adjacent, 'ffprobe.exe')).existsSync() &&
            File(p.join(adjacent, 'deno.exe')).existsSync()
        ? adjacent
        : null;
  }

  @override
  String? get ffmpegExecutable => Platform.isWindows && toolDirectory != null
      ? p.join(toolDirectory!, 'ffmpeg.exe')
      : null;
  static const _safe = [
    '--ignore-config',
    '--no-plugin-dirs',
    '--no-remote-components',
    '--no-warnings',
  ];

  static String redactError(String message) =>
      message.replaceAllMapped(RegExp(r'https?://[^\s<>"\x27]+'), (match) {
        final uri = Uri.tryParse(match.group(0)!);
        if (uri == null) return '[URL]';
        return uri.replace(userInfo: '', query: '', fragment: '').toString();
      });

  static String sourceError(String message) {
    final sanitized = redactError(message);
    final normalized = sanitized.toLowerCase();
    if (normalized.contains('429') ||
        normalized.contains('not a bot') ||
        normalized.contains('confirm you')) {
      return 'YouTube limitó temporalmente las solicitudes o pide verificar la sesión. Espera unos minutos y vuelve a intentar. Puedes importar o renovar tu sesión opcional en Ajustes; esto no garantiza quitar el límite. Los archivos locales siguen disponibles.';
    }
    if (normalized.contains('video unavailable') ||
        normalized.contains('private video') ||
        normalized.contains('video has been removed')) {
      return 'Este contenido de YouTube no está disponible públicamente. Prueba otro enlace.';
    }
    if (normalized.contains('403') || normalized.contains('forbidden')) {
      return 'YouTube rechazó el acceso al audio (403). Vuelve a intentar para renovar el enlace.';
    }
    if (normalized.contains('cookie')) {
      return 'YouTube rechazó el archivo de sesión. Renueva tu sesión opcional en Ajustes.';
    }
    return sanitized.length > 2000
        ? '${sanitized.substring(0, 2000)}…'
        : sanitized;
  }

  Future<String> _native(String method, Map<String, Object?> arguments) async {
    if (const {'search', 'playlist', 'resolve', 'download'}.contains(method)) {
      return _operation(() => _invokeNative(method, arguments));
    }
    return _invokeNative(method, arguments);
  }

  Future<String> _invokeNative(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final cookie = cookieFile;
    if (cookie != null &&
        const {'search', 'playlist', 'resolve', 'download'}.contains(method)) {
      arguments = {
        ...arguments,
        'cookieFile': await _validateCookieFile(cookie),
      };
    }
    try {
      return (await _channel.invokeMethod<String>(method, arguments)) ?? '';
    } on PlatformException catch (error) {
      throw StateError(sourceError(error.message ?? 'Error de la fuente.'));
    }
  }

  static Uri validateYouTube(String value) {
    final uri = Uri.tryParse(value);
    const hosts = {
      'youtube.com',
      'www.youtube.com',
      'music.youtube.com',
      'm.youtube.com',
      'youtu.be',
    };
    if (uri == null ||
        uri.scheme != 'https' ||
        !hosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw ArgumentError('Usa un enlace HTTPS de YouTube.');
    }
    return uri;
  }

  @override
  Future<void> configureToolDirectory(String directory) async {
    final absolute = Directory(directory).absolute.path;
    for (final name in [
      'yt-dlp.exe',
      'ffmpeg.exe',
      'ffprobe.exe',
      'deno.exe',
    ]) {
      if (!await File(p.join(absolute, name)).exists()) {
        throw StateError('Falta $name en la carpeta.');
      }
    }
    await _preferences.setString('toolDirectory', absolute);
  }

  Future<String> _run(
    List<String> arguments, {
    String? jobId,
    void Function(double)? onProgress,
  }) async {
    return _operation(
      () => _runWindows(arguments, jobId: jobId, onProgress: onProgress),
    );
  }

  Future<String> _runWindows(
    List<String> arguments, {
    String? jobId,
    void Function(double)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Esta fuente requiere Windows o Android.');
    }
    final directory = toolDirectory;
    if (directory == null) {
      throw StateError(
        'Selecciona la carpeta de yt-dlp, FFmpeg y Deno en Ajustes.',
      );
    }
    final executable = p.join(directory, 'yt-dlp.exe');
    if (!await File(executable).exists()) {
      throw StateError('No se encuentra yt-dlp.exe.');
    }
    if (jobId != null && _cancelled.remove(jobId)) {
      throw StateError('Descarga cancelada.');
    }
    final process = await Process.start(executable, [
      ..._safe,
      if (cookieFile != null) ...[
        '--cookies',
        await _validateCookieFile(cookieFile!),
      ],
      '--js-runtimes',
      'deno:${p.join(directory, 'deno.exe')}',
      '--ffmpeg-location',
      directory,
      ...arguments,
    ], runInShell: false);
    final id = jobId ?? 'operation-${DateTime.now().microsecondsSinceEpoch}';
    _jobs[id] = process;
    if (_cancelled.contains(id)) {
      await _killTree(process);
    }
    final output = StringBuffer(), errors = StringBuffer();
    int outputBytes = 0;
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          final previousBytes = outputBytes;
          outputBytes += line.length;
          if (outputBytes > 8 * 1024 * 1024) {
            if (previousBytes <= 8 * 1024 * 1024) {
              unawaited(_killTree(process));
            }
            return;
          }
          output.writeln(line);
          if (onProgress != null && line.startsWith('AURORA_PROGRESS:')) {
            final percent = double.tryParse(
              line.substring(16).trim().replaceAll('%', ''),
            );
            if (percent != null) onProgress((percent / 100).clamp(0, 1));
          }
        });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach((chunk) {
          if (errors.length < 8192) errors.write(chunk);
        });
    try {
      final code = await process.exitCode.timeout(
        jobId == null
            ? const Duration(seconds: 90)
            : const Duration(minutes: 30),
        onTimeout: () async {
          await _killTree(process);
          throw TimeoutException('La fuente tardó demasiado.');
        },
      );
      await Future.wait([stdoutDone, stderrDone]);
      if (_cancelled.remove(id)) throw StateError('Descarga cancelada.');
      if (outputBytes > 8 * 1024 * 1024) {
        throw StateError('La respuesta supera el límite permitido.');
      }
      if (code != 0) {
        throw StateError('yt-dlp: ${sourceError(errors.toString().trim())}');
      }
      return output.toString();
    } finally {
      _jobs.remove(id);
    }
  }

  Future<void> _killTree(Process process) async {
    try {
      final taskkill = p.join(
        Platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'taskkill.exe',
      );
      await Process.run(taskkill, [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ], runInShell: false);
    } on ProcessException {
      // The process may already have exited while its streams were draining.
    } finally {
      process.kill();
    }
  }

  Track _track(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final thumbs = json['thumbnails'] as List?;
    return Track(
      id: 'yt:$id',
      title: json['title']?.toString() ?? 'Sin título',
      artist:
          (json['artist'] ?? json['uploader'] ?? json['channel'] ?? 'YouTube')
              .toString(),
      duration: Duration(
        milliseconds: ((json['duration'] as num? ?? 0) * 1000).round(),
      ),
      artworkUrl:
          json['thumbnail'] as String? ??
          (thumbs?.isNotEmpty == true
              ? (thumbs!.last as Map)['url'] as String?
              : null),
      pageUrl: 'https://www.youtube.com/watch?v=$id',
    );
  }

  Future<List<Track>> _listing(String target, int limit, String method) async {
    final String raw;
    if (Platform.isAndroid) {
      raw = await _native(method, {'target': target, 'limit': limit});
    } else {
      raw = await _run([
        '--flat-playlist',
        '--dump-single-json',
        '--playlist-end',
        '$limit',
        '--',
        target,
      ]);
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ((data['entries'] as List?) ?? [data])
        .whereType<Map>()
        .map((e) => _track(Map<String, dynamic>.from(e)))
        .where((t) => t.id != 'yt:')
        .take(limit)
        .toList();
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    if (text.length > 500) {
      throw ArgumentError('La búsqueda es demasiado larga.');
    }
    final count = limit.clamp(1, 50);
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      return _listing(validateYouTube(text).toString(), count, 'playlist');
    }
    return _listing('ytsearch$count:$text', count, 'search');
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) =>
      _listing(validateYouTube(url.toString()).toString(), 200, 'playlist');
  @override
  Future<ResolvedAudio> resolve(Track track) async {
    if (track.isLocal && await File(track.localPath!).exists()) {
      return ResolvedAudio(input: track.localPath!, duration: track.duration);
    }
    if (track.isLocal && track.pageUrl == null) {
      throw StateError(
        'El archivo local ya no está disponible. Impórtalo nuevamente.',
      );
    }
    final target = validateYouTube(track.pageUrl ?? '').toString();
    final raw = Platform.isAndroid
        ? await _native('resolve', {'target': target})
        : await _run([
            '--no-playlist',
            '-f',
            'bestaudio/best',
            '--dump-single-json',
            '--',
            target,
          ]);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null || Uri.tryParse(url)?.scheme != 'https') {
      throw StateError('No hay audio disponible.');
    }
    return ResolvedAudio(
      input: url,
      headers: (data['http_headers'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      duration: Duration(
        milliseconds: ((data['duration'] as num? ?? 0) * 1000).round(),
      ),
    );
  }

  @override
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    final target = validateYouTube(track.pageUrl ?? '').toString();
    if (await destination.exists()) {
      throw StateError('El archivo de destino ya existe.');
    }
    await destination.parent.create(recursive: true);
    final temp = await Directory(
      destination.parent.path,
    ).createTemp('.aurora-');
    try {
      if (Platform.isAndroid) {
        if (onProgress != null) _progress[jobId] = onProgress;
        await _native('download', {
          'target': target,
          'directory': temp.path,
          'jobId': jobId,
        });
      } else {
        await _run(
          [
            '--no-playlist',
            '-f',
            'bestaudio/best',
            '-x',
            '--audio-format',
            'mp3',
            '--audio-quality',
            '0',
            '--newline',
            '--progress-template',
            'download:AURORA_PROGRESS:%(progress._percent_str)s',
            '-o',
            p.join(temp.path, 'audio.%(ext)s'),
            '--',
            target,
          ],
          jobId: jobId,
          onProgress: onProgress,
        );
      }
      final file = File(p.join(temp.path, 'audio.mp3'));
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('La descarga no produjo audio.');
      }
      if (await destination.exists()) throw StateError('El destino ya existe.');
      await file.rename(destination.path);
      onProgress?.call(1);
    } finally {
      _progress.remove(jobId);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    if (Platform.isAndroid) {
      await _channel.invokeMethod('cancel', {'jobId': jobId});
      return;
    }
    _cancelled.add(jobId);
    final process = _jobs[jobId];
    if (process != null) {
      await _killTree(process);
    }
  }

  @override
  Future<String> diagnose() async {
    if (Platform.isAndroid) {
      return _native('diagnose', {});
    }
    final version = await _run(['--version']);
    return 'yt-dlp ${version.trim()} · ${toolDirectory ?? "Sin configurar"}';
  }

  @override
  void dispose() {
    for (final process in _jobs.values) {
      unawaited(_killTree(process));
    }
    _jobs.clear();
    _progress.clear();
    _channel.setMethodCallHandler(null);
  }
}
