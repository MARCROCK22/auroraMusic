// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from NuclearPlayer/nuclear-plugin-something; see third_party/nuclear_spotify/NOTICE.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'spotify_models.dart';

class SpotifyResponse {
  const SpotifyResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

typedef SpotifyTransport =
    Future<SpotifyResponse> Function(
      Uri uri, {
      required String method,
      required Map<String, String> headers,
      String? body,
    });

const spotifyBrowserHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Accept': 'application/json',
  'Accept-Language': 'en-US,en;q=0.9',
  'Origin': 'https://open.spotify.com',
  'Referer': 'https://open.spotify.com/',
};

/// No cookies, credentials, or logs; redirect responses are deliberately rejected.
class SpotifyNetwork {
  SpotifyNetwork(SpotifyTransport? transport) : _transport = transport;
  final SpotifyTransport? _transport;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  static const maxResponseBytes = 4 * 1024 * 1024;
  final List<Completer<void>> _waiting = [];
  int _active = 0;
  bool _closed = false;

  Future<SpotifyResponse> request(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = spotifyBrowserHeaders,
    String? body,
  }) async {
    if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
    if (_active >= 3) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
    } else {
      _active++;
    }
    try {
      if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
      final response = await (_transport != null
          ? _transport(
              uri,
              method: method,
              headers: headers,
              body: body,
            ).timeout(const Duration(seconds: 20))
          : _send(uri, method: method, headers: headers, body: body));
      if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
      if (utf8.encode(response.body).length > maxResponseBytes) {
        throw const SpotifyMetadataException(
          'Respuesta de Spotify demasiado grande.',
        );
      }
      return response;
    } on SpotifyMetadataException {
      rethrow;
    } catch (_) {
      throw const SpotifyMetadataException(
        'No se pudo conectar con los metadatos de Spotify.',
      );
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }

  Future<SpotifyResponse> _send(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    HttpClientRequest? activeRequest;
    StreamSubscription<List<int>>? subscription;
    Completer<void>? activeFinished;
    var expired = false;
    final task = () async {
      final request = await _client.openUrl(method, uri);
      activeRequest = request;
      if (expired || _closed) {
        request.abort();
        throw const SpotifyMetadataException('Proveedor cerrado.');
      }
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.write(body);
      final response = await request.close();
      final bytes = <int>[];
      final finished = Completer<void>();
      activeFinished = finished;
      subscription = response.listen(
        (chunk) {
          if (bytes.length + chunk.length > maxResponseBytes) {
            request.abort();
            subscription?.cancel();
            if (!finished.isCompleted) {
              finished.completeError(
                const SpotifyMetadataException(
                  'Respuesta de Spotify demasiado grande.',
                ),
              );
            }
          } else {
            bytes.addAll(chunk);
          }
        },
        onError: (Object error) {
          if (!finished.isCompleted) finished.completeError(error);
        },
        onDone: () {
          if (!finished.isCompleted) finished.complete();
        },
        cancelOnError: true,
      );
      await finished.future;
      return SpotifyResponse(response.statusCode, utf8.decode(bytes));
    }();
    return task.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        expired = true;
        activeRequest?.abort();
        subscription?.cancel();
        if (activeFinished != null && !activeFinished!.isCompleted) {
          activeFinished!.completeError(
            const SpotifyMetadataException(
              'La consulta de Spotify tardó demasiado.',
            ),
          );
        }
        throw const SpotifyMetadataException(
          'La consulta de Spotify tardó demasiado.',
        );
      },
    );
  }

  Map<String, dynamic> decode(SpotifyResponse response) {
    if (response.statusCode == 429) {
      throw const SpotifyMetadataException(
        'Spotify limitó las solicitudes. Intenta nuevamente más tarde.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const SpotifyMetadataException(
        'Los metadatos de Spotify no están disponibles.',
      );
    }
    try {
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } catch (_) {
      throw const SpotifyMetadataException(
        'Spotify devolvió metadatos inválidos.',
      );
    }
  }

  void close() {
    _closed = true;
    _client.close(force: true);
    for (final waiter in _waiting) {
      waiter.completeError(
        const SpotifyMetadataException('Proveedor cerrado.'),
      );
    }
    _waiting.clear();
  }
}

class SpotifyAuth {
  SpotifyAuth(this.network, this.clock);
  final SpotifyNetwork network;
  final DateTime Function() clock;
  String? _token;
  DateTime? _expires;
  Future<String>? _pending;
  Map<String, dynamic>? _secrets;
  DateTime? _secretsFetched;
  bool _closed = false;

  void close() {
    _closed = true;
    _token = null;
    _expires = null;
    _secrets = null;
    _secretsFetched = null;
  }

  Future<String> token({String? rejectedToken}) {
    if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
    if (rejectedToken != null && _token == rejectedToken) {
      _token = null;
      _expires = null;
    }
    if (_token != null &&
        _expires != null &&
        clock().add(const Duration(seconds: 30)).isBefore(_expires!)) {
      return Future.value(_token);
    }
    return _pending ??= _fetch()
        .catchError((Object error) {
          if (error is SpotifyMetadataException) throw error;
          throw const SpotifyMetadataException(
            'Spotify devolvió una autorización inválida.',
          );
        })
        .whenComplete(() {
          _pending = null;
        });
  }

  Future<String> _fetch() async {
    if (_secrets == null ||
        _secretsFetched == null ||
        clock().difference(_secretsFetched!) >= const Duration(hours: 1)) {
      await _loadSecrets();
    }
    for (var pass = 0; pass < 2; pass++) {
      final versions =
          _secrets!.keys
              .map(int.tryParse)
              .whereType<int>()
              .where((v) => v > 0)
              .toList()
            ..sort((a, b) => b.compareTo(a));
      final timeData = network.decode(
        await network.request(
          Uri.parse('https://open.spotify.com/api/server-time'),
        ),
      );
      final serverTime = timeData['serverTime'];
      if (serverTime is! num || !serverTime.isFinite || serverTime <= 0) {
        throw const SpotifyMetadataException(
          'No se pudo validar la hora de Spotify.',
        );
      }
      for (final version in versions.take(5)) {
        final encoded = _secrets!['$version'];
        if (encoded is! List ||
            encoded.isEmpty ||
            encoded.length > 256 ||
            encoded.any((v) => v is! int || v < 0 || v > 255)) {
          continue;
        }
        final joined = List.generate(
          encoded.length,
          (i) => (encoded[i] as int) ^ ((i % 33) + 9),
        ).join();
        final key = utf8.encode(joined);
        final uri = Uri.https('open.spotify.com', '/api/token', {
          'reason': 'init',
          'productType': 'web-player',
          'totpVer': '$version',
          'totp': spotifyTotp(key, clock().millisecondsSinceEpoch ~/ 1000, 30),
          'totpServer': spotifyTotp(key, serverTime.toInt(), 900),
        });
        final response = await network.request(uri);
        if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 400) {
          continue;
        }
        final data = network.decode(response);
        final access = data['accessToken'];
        final expires = data['accessTokenExpirationTimestampMs'];
        if (access is! String ||
            access.isEmpty ||
            access.length > 8192 ||
            expires is! num ||
            !expires.isFinite ||
            expires <= clock().millisecondsSinceEpoch + 30000 ||
            expires > 8640000000000000) {
          throw const SpotifyMetadataException(
            'Spotify no pudo renovar la autorización anónima.',
          );
        }
        if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
        _token = access;
        _expires = DateTime.fromMillisecondsSinceEpoch(expires.toInt());
        return access;
      }
      if (pass == 0) await _loadSecrets();
    }
    throw const SpotifyMetadataException(
      'La autorización anónima de Spotify cambió. Intenta más tarde.',
    );
  }

  Future<void> _loadSecrets() async {
    final secrets = network.decode(
      await network.request(
        Uri.parse(
          'https://raw.githubusercontent.com/xyloflake/spot-secrets-go/refs/heads/main/secrets/secretDict.json',
        ),
      ),
    );
    if (_closed) throw const SpotifyMetadataException('Proveedor cerrado.');
    _secrets = secrets;
    _secretsFetched = clock();
  }
}

/// Nuclear's HMAC-SHA1 dynamic truncation, local period 30s / server period 900s.
String spotifyTotp(List<int> key, int seconds, int period) {
  final counter = ByteData(8)..setUint64(0, seconds ~/ period, Endian.big);
  final digest = Hmac(sha1, key).convert(counter.buffer.asUint8List()).bytes;
  final offset = digest.last & 15;
  final value =
      ((digest[offset] & 127) << 24) |
      (digest[offset + 1] << 16) |
      (digest[offset + 2] << 8) |
      digest[offset + 3];
  return (value % 1000000).toString().padLeft(6, '0');
}
