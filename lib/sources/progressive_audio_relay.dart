import 'dart:async';
import 'dart:io';
import 'dart:math';

/// An app-owned growing WebM file exposed through a private loopback endpoint.
/// [completed] must validate the full download before returning its final file.
/// A temporary end of the file is never an HTTP EOF. Failed streams are aborted.
class ProgressiveAudioRelay {
  ProgressiveAudioRelay._(
    this._file,
    this._server,
    this._cancel,
    this.expectedBytes,
    this.maxBytes,
    this.stallTimeout,
    this.pollInterval,
  ) : _token = List.generate(
        32,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  static const byteLimit = 512 * 1024 * 1024;
  File _file;
  final HttpServer _server;
  final Future<void> Function() _cancel;
  final String _token;
  final int? expectedBytes;
  final int maxBytes;
  final Duration stallTimeout;
  final Duration pollInterval;
  final _settled = Completer<void>();
  Timer? _monitor;
  bool _checking = false;
  bool _finished = false;
  bool _disposed = false;
  Object? _error;
  int _length = 0;
  int _clients = 0;
  int _readers = 0;
  bool _publishing = false;
  DateTime _lastGrowth = DateTime.now();
  Future<void>? _closing;

  Uri get uri =>
      Uri.parse('http://127.0.0.1:${_server.port}/aurora-progressive/$_token');
  File get file => _file;
  bool get isComplete => _finished && _error == null;
  Object? get error => _error;
  Future<void> get settled => _settled.future;

  static Future<ProgressiveAudioRelay> start({
    required File file,
    required Future<File> completed,
    required Future<void> Function() cancel,
    int? expectedBytes,
    int maxBytes = byteLimit,
    Duration stallTimeout = const Duration(seconds: 90),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    completed
        .ignore(); // Binding is asynchronous; observe even an immediate failure.
    if (maxBytes <= 0 ||
        maxBytes > byteLimit ||
        (expectedBytes != null &&
            (expectedBytes <= 0 || expectedBytes > maxBytes))) {
      throw ArgumentError('El audio supera el limite de la cache.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = ProgressiveAudioRelay._(
      file,
      server,
      cancel,
      expectedBytes,
      maxBytes,
      stallTimeout,
      pollInterval,
    );
    // Attach immediately so failed downloads never produce unhandled futures.
    unawaited(
      completed.then((published) async {
        if (relay._disposed || relay._error != null) return;
        relay._file = published;
        try {
          final length = await relay._readLength();
          if (length == 0 ||
              (expectedBytes != null && length != expectedBytes)) {
            throw StateError('La descarga de audio esta incompleta.');
          }
          relay._length = length;
          relay._finished = true;
          relay._monitor?.cancel();
          relay._settle();
        } catch (error) {
          relay._fail(error);
        }
      }, onError: (Object error, StackTrace stack) => relay._fail(error)),
    );
    server.listen((request) => unawaited(relay._serve(request)));
    relay._monitor = Timer.periodic(pollInterval, (_) {
      unawaited(relay._checkGrowth());
    });
    return relay;
  }

  Future<int> _readLength() async {
    final type = await FileSystemEntity.type(_file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound && !_finished) return 0;
    if (type != FileSystemEntityType.file) {
      throw StateError('El archivo de audio no es seguro.');
    }
    final length = await _file.length();
    if (length > maxBytes ||
        (expectedBytes != null && length > expectedBytes!)) {
      throw StateError('El audio supera el limite de la cache.');
    }
    return length;
  }

  Future<void> _checkGrowth() async {
    if (_checking || _disposed || _finished || _error != null) return;
    _checking = true;
    try {
      final length = await _readLength();
      if (length > _length) _lastGrowth = DateTime.now();
      _length = length;
      if (DateTime.now().difference(_lastGrowth) > stallTimeout) {
        throw StateError('La descarga dejo de avanzar. Vuelve a intentar.');
      }
    } on FileSystemException {
      // Publication can rename the private file between two asynchronous reads.
      if (DateTime.now().difference(_lastGrowth) > stallTimeout) {
        _fail(StateError('El archivo de audio ya no esta disponible.'));
      }
    } catch (error) {
      _fail(error);
    } finally {
      _checking = false;
    }
  }

  void _settle() {
    if (!_settled.isCompleted) _settled.complete();
  }

  void _fail(Object error) {
    if (_error != null || _disposed) return;
    _error = error;
    _monitor?.cancel();
    _settle();
    unawaited(_cancel().catchError((Object _) {}));
  }

  void _throwIfFailed() {
    if (_disposed) throw StateError('Descarga cancelada.');
    if (_error != null) {
      throw StateError('La descarga fallo. Vuelve a intentar.');
    }
  }

  Future<void> waitUntilReady({int minimumBytes = 4096}) async {
    while (true) {
      _throwIfFailed();
      if (!_publishing && (_length >= minimumBytes || _finished)) {
        _readers++;
        try {
          final handle = await _file.open();
          List<int> header;
          try {
            header = await handle.read(4);
          } finally {
            await handle.close();
          }
          if (header.length != 4 ||
              header[0] != 0x1a ||
              header[1] != 0x45 ||
              header[2] != 0xdf ||
              header[3] != 0xa3) {
            _fail(
              StateError('El contenedor no permite reproduccion progresiva.'),
            );
            _throwIfFailed();
          }
        } finally {
          _readers--;
        }
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Windows cannot rename a file while a reader has it open. Pause new reads
  /// briefly and wait for bounded chunks to close before atomic publication.
  Future<File> publishTo(File destination) async {
    _publishing = true;
    try {
      while (_readers > 0) {
        _throwIfFailed();
        await Future<void>.delayed(pollInterval);
      }
      _throwIfFailed();
      _file = await _file.rename(destination.path);
      return _file;
    } finally {
      _publishing = false;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    response.bufferOutput = false;
    var disconnected = false;
    var started = false;
    unawaited(
      response.done.then(
        (_) {
          disconnected = true;
        },
        onError: (Object _, StackTrace stack) {
          disconnected = true;
        },
      ),
    );
    if (request.uri.path != uri.path || request.uri.hasQuery) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      await response.close();
      return;
    }
    if (_clients >= 8) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    _clients++;
    try {
      _throwIfFailed();
      var range = request.headers.value(HttpHeaders.rangeHeader);
      // FFmpeg may send bytes=0- even for its first read. HTTP permits a server
      // to answer that request with 200; preserve early unknown-length playback.
      if (range == 'bytes=0-' && expectedBytes == null && !_finished) {
        range = null;
      }
      int start = 0;
      int? end;
      if (range != null) {
        final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
        if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await response.close();
          return;
        }
        // Unknown-length open and suffix ranges wait for validation to obtain
        // truthful Content-Range headers. Initial GET still streams immediately.
        if (expectedBytes == null && (match[1]!.isEmpty || match[2]!.isEmpty)) {
          while (!_finished && !disconnected) {
            _throwIfFailed();
            await Future<void>.delayed(pollInterval);
          }
        }
        final total = expectedBytes ?? (_finished ? _length : null);
        if (match[1]!.isEmpty) {
          final suffix = int.tryParse(match[2]!);
          if (suffix == null || suffix <= 0 || total == null) {
            throw const FormatException('Range');
          }
          start = max(0, total - suffix);
          end = total - 1;
        } else {
          start = int.tryParse(match[1]!) ?? maxBytes;
          end = match[2]!.isEmpty ? total! - 1 : int.tryParse(match[2]!);
          if (end == null || start > end || start >= maxBytes) {
            throw const FormatException('Range');
          }
          if (total != null) {
            if (start >= total) throw const FormatException('Range');
            end = min(end, total - 1);
          } else {
            if (end >= maxBytes) throw const FormatException('Range');
            while (_length <= end && !_finished && !disconnected) {
              _throwIfFailed();
              await Future<void>.delayed(pollInterval);
            }
            if (_finished) {
              if (start >= _length) throw const FormatException('Range');
              end = min(end, _length - 1);
            }
          }
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${total ?? (_finished ? _length : '*')}',
        );
        response.contentLength = end - start + 1;
      } else if (expectedBytes != null || _finished) {
        response.contentLength = expectedBytes ?? _length;
      }
      response.headers
        ..contentType = ContentType('audio', 'webm')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      var offset = start;
      while (!disconnected) {
        _throwIfFailed();
        if (_publishing) {
          await Future<void>.delayed(pollInterval);
          continue;
        }
        // Hold back the final byte until full validation, including bounded
        // range responses that reach the actual end of the download.
        final available = _finished ? _length : max(0, _length - 1);
        final limit = min(available, end == null ? available : end + 1);
        if (offset < limit) {
          final currentFile = _file;
          List<int> bytes;
          _readers++;
          try {
            final handle = await currentFile.open();
            try {
              await handle.setPosition(offset);
              bytes = await handle.read(min(65536, limit - offset));
            } finally {
              await handle.close();
            }
          } on FileSystemException {
            await Future<void>.delayed(pollInterval);
            continue;
          } finally {
            _readers--;
          }
          if (bytes.isEmpty) {
            await Future<void>.delayed(pollInterval);
            continue;
          }
          started = true;
          response.add(bytes);
          await response.flush();
          offset += bytes.length;
          continue;
        }
        if ((end != null && offset > end) || (_finished && offset >= _length)) {
          await response.close();
          return;
        }
        await Future<void>.delayed(pollInterval);
      }
    } on FormatException {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await response.close();
    } catch (_) {
      if (!disconnected) {
        if (started) {
          // No successful chunked terminator / clean EOF on a failed download.
          response.deadline = Duration.zero;
        } else {
          response.statusCode = HttpStatus.serviceUnavailable;
          try {
            await response.close();
          } catch (_) {}
        }
      }
    } finally {
      _clients--;
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _monitor?.cancel();
    _settle();
    await _server.close(force: true);
    await _cancel();
  }
}
