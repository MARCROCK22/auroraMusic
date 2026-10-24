import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'listen.dart';

/// Claves de la app en Last.fm (se inyectan con --dart-define en la compilación).
const kLastfmApiKey = String.fromEnvironment('AURORA_LASTFM_API_KEY');
const kLastfmSecret = String.fromEnvironment('AURORA_LASTFM_SECRET');
const kLastfmRoot = 'https://ws.audioscrobbler.com/2.0/';
const kLastfmUserAgent =
    'Aurora/$kLastfmClientVersion (https://github.com/kaz-py/auroraMusic)';

/// `api_sig`: md5 de los parámetros ordenados (`nombrevalor`…) más el secreto.
/// `format` y `callback` quedan fuera, como exige la API.
String lastfmSignature(Map<String, String> params, String secret) {
  final keys = [
    for (final k in params.keys)
      if (k != 'format' && k != 'callback') k,
  ]..sort();
  final text = StringBuffer();
  for (final k in keys) {
    text
      ..write(k)
      ..write(params[k]);
  }
  text.write(secret);
  return md5.convert(utf8.encode(text.toString())).toString();
}

/// Quita secretos (contraseña, clave de sesión…) de [text] antes de que salga
/// hacia logs, errores o UI.
String redactSecrets(String text, Iterable<String?> secrets) {
  var out = text;
  for (final s in secrets) {
    if (s != null && s.trim().length > 3) out = out.replaceAll(s.trim(), '***');
  }
  return out;
}

class LfmRequest {
  const LfmRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class LfmResponse {
  const LfmResponse(this.status, this.body, [this.headers = const {}]);
  final int status;
  final String body;

  /// Nombres en minúsculas.
  final Map<String, String> headers;
}

typedef LfmTransport = Future<LfmResponse> Function(LfmRequest request);

/// Error de Last.fm con mensaje ya redactado. [code] es el de la API (9 =
/// sesión inválida, 29 = límite…); [status] el HTTP si lo hubo.
class LastfmException implements Exception {
  LastfmException(
    String message, {
    this.code,
    this.status,
    this.retryAfter,
    Iterable<String?> secrets = const [],
  }) : message = redactSecrets(message, secrets);
  final String message;
  final int? code, status;
  final Duration? retryAfter;

  bool get invalidSession => code == 9;
  bool get rateLimited => code == 29 || status == 429;
  bool get retryable =>
      code == 11 ||
      code == 16 ||
      (status ?? 0) >= 500 ||
      (code == null && status == null);
  @override
  String toString() => 'LastfmException: $message';
}

enum LfmSubmitStatus { ok, rateLimited, unauthorized, rejected, retry }

class LfmSubmitResult {
  const LfmSubmitResult(this.status, [this.retryAfter, this.detail]);
  final LfmSubmitStatus status;
  final Duration? retryAfter;

  /// Motivo legible (ya sin secretos) cuando el envío no fue `ok`.
  final String? detail;
}

class LfmSession {
  const LfmSession(this.name, this.key);
  final String name, key;
}

/// Cliente HTTPS mínimo de Last.fm. La contraseña solo viaja una vez, en el
/// POST de `auth.getMobileSession`; después solo la clave de sesión.
class LastfmClient {
  LastfmClient({
    LfmTransport? transport,
    String? apiKey,
    String? secret,
    Uri? base,
  }) : apiKey = apiKey ?? kLastfmApiKey,
       secret = secret ?? kLastfmSecret,
       _base = base ?? Uri.parse(kLastfmRoot),
       _transport = transport ?? _httpTransport {
    if (_base.scheme != 'https') {
      throw ArgumentError('Last.fm solo se usa por HTTPS.');
    }
  }

  final String apiKey, secret;
  final Uri _base;
  final LfmTransport _transport;

  /// Sin claves en la compilación la función queda desactivada.
  bool get configured => apiKey.isNotEmpty && secret.isNotEmpty;

  static const _timeout = Duration(seconds: 20);

  static Future<LfmResponse> _httpTransport(LfmRequest r) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.openUrl(r.method, r.uri).timeout(_timeout);
      r.headers.forEach(request.headers.set);
      if (r.body != null) {
        final bytes = utf8.encode(r.body!);
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(_timeout);
      final body = await utf8.decodeStream(response).timeout(_timeout);
      final headers = <String, String>{};
      response.headers.forEach(
        (name, values) => headers[name.toLowerCase()] = values.join(','),
      );
      return LfmResponse(response.statusCode, body, headers);
    } finally {
      client.close(force: true);
    }
  }

  static String _form(Map<String, String> p) => [
    for (final e in p.entries)
      '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
  ].join('&');

  /// Llama a [method]. Las de escritura (`post`) van firmadas por POST; las de
  /// lectura, por GET con la clave pública. Lanza [LastfmException].
  Future<Map<String, Object?>> request(
    String method,
    Map<String, String> params, {
    bool post = false,
  }) async {
    if (!configured) {
      throw LastfmException('Last.fm no está configurado en esta compilación.');
    }
    final all = {...params, 'method': method, 'api_key': apiKey};
    if (post) all['api_sig'] = lastfmSignature(all, secret);
    all['format'] = 'json';
    final body = _form(all);
    final secrets = [params['password'], params['sk']];
    final LfmResponse r;
    try {
      r = await _transport(
        post
            ? LfmRequest('POST', _base, {
                'User-Agent': kLastfmUserAgent,
                'Content-Type': 'application/x-www-form-urlencoded',
              }, body)
            : LfmRequest('GET', Uri.parse('$_base?$body'), {
                'User-Agent': kLastfmUserAgent,
              }, null),
      );
    } on Object catch (error) {
      throw LastfmException(
        'Sin conexión con Last.fm: $error',
        secrets: secrets,
      );
    }
    Object? json;
    try {
      json = jsonDecode(r.body);
    } on FormatException {
      json = null;
    }
    final retry = int.tryParse(r.headers['retry-after'] ?? '');
    final wait = retry == null ? null : Duration(seconds: retry);
    if (json is Map && json['error'] is int) {
      throw LastfmException(
        '${json['message'] ?? 'Error de Last.fm'}',
        code: json['error'] as int,
        status: r.status,
        retryAfter: wait,
        secrets: secrets,
      );
    }
    if (r.status < 200 || r.status >= 300 || json is! Map) {
      throw LastfmException(
        'Last.fm respondió ${r.status}.',
        status: r.status == 200 ? 502 : r.status,
        retryAfter: wait,
      );
    }
    return json.cast<String, Object?>();
  }

  /// Inicia sesión con usuario y contraseña (una sola vez). Devuelve el nombre
  /// canónico y la clave de sesión; la contraseña no se guarda en ningún sitio.
  Future<LfmSession> getMobileSession(String user, String password) async {
    final j = await request('auth.getMobileSession', {
      'username': user,
      'password': password,
    }, post: true);
    final s = j['session'];
    if (s is Map && s['name'] is String && s['key'] is String) {
      return LfmSession(s['name'] as String, s['key'] as String);
    }
    throw LastfmException('Last.fm no devolvió una sesión.');
  }

  LfmSubmitResult _result(LastfmException e, String? sk) {
    final why = redactSecrets(e.message, [sk]);
    if (e.invalidSession) {
      return LfmSubmitResult(LfmSubmitStatus.unauthorized, null, why);
    }
    if (e.rateLimited) {
      return LfmSubmitResult(LfmSubmitStatus.rateLimited, e.retryAfter, why);
    }
    if (e.retryable || e.code == 10 || e.code == 26) {
      return LfmSubmitResult(LfmSubmitStatus.retry, e.retryAfter, why);
    }
    return LfmSubmitResult(LfmSubmitStatus.rejected, null, why);
  }

  Future<LfmSubmitResult> updateNowPlaying(String sk, Listen listen) async {
    try {
      await request('track.updateNowPlaying', {
        ...listen.toParams(playingNow: true),
        'sk': sk,
      }, post: true);
      return const LfmSubmitResult(LfmSubmitStatus.ok);
    } on LastfmException catch (e) {
      return _result(e, sk);
    }
  }

  /// Hasta 50 por llamada; las ignoradas por Last.fm cuentan como enviadas.
  Future<LfmSubmitResult> scrobble(String sk, List<Listen> listens) async {
    try {
      await request('track.scrobble', {
        for (final (i, l) in listens.indexed) ...l.toParams(index: i),
        'sk': sk,
      }, post: true);
      return const LfmSubmitResult(LfmSubmitStatus.ok);
    } on LastfmException catch (e) {
      return _result(e, sk);
    }
  }
}
