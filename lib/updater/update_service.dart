import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Repositorio del que se leen las versiones (API pública, sin token).
const updateRepo = 'kaz-py/auroraMusic';

/// Hosts permitidos para API, descarga y redirecciones de GitHub.
const _allowedHosts = {
  'api.github.com',
  'github.com',
  'objects.githubusercontent.com',
  'release-assets.githubusercontent.com',
};

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------- SemVer

class SemVer implements Comparable<SemVer> {
  SemVer(this.core, this.pre);
  final List<int> core;
  final List<String> pre;

  /// Acepta `v1.2.3`, `1.2.3+9` y `1.2.3-beta.1`; null si no es SemVer.
  static SemVer? tryParse(String text) {
    final m = RegExp(
      r'^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$',
    ).firstMatch(text.trim());
    if (m == null) return null;
    return SemVer([
      for (var i = 1; i <= 3; i++) int.parse(m[i]!),
    ], m[4]?.split('.') ?? const []);
  }

  @override
  int compareTo(SemVer other) {
    for (var i = 0; i < 3; i++) {
      final d = core[i].compareTo(other.core[i]);
      if (d != 0) return d;
    }
    if (pre.isEmpty || other.pre.isEmpty) {
      return pre.isEmpty == other.pre.isEmpty ? 0 : (pre.isEmpty ? 1 : -1);
    }
    for (var i = 0; i < pre.length && i < other.pre.length; i++) {
      final a = int.tryParse(pre[i]), b = int.tryParse(other.pre[i]);
      final d = a != null && b != null
          ? a.compareTo(b)
          : a != null
          ? -1
          : b != null
          ? 1
          : pre[i].compareTo(other.pre[i]);
      if (d != 0) return d;
    }
    return pre.length.compareTo(other.pre.length);
  }

  @override
  String toString() =>
      '${core.join('.')}${pre.isEmpty ? '' : '-${pre.join('.')}'}';
}

// --------------------------------------------------------------- Release

class ReleaseAsset {
  const ReleaseAsset(this.name, this.url, this.size);
  final String name;
  final Uri url;
  final int size;
}

class ReleaseInfo {
  ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.prerelease,
    required this.assets,
  });

  final String tag;
  final SemVer version;
  final String notes;
  final bool prerelease;
  final List<ReleaseAsset> assets;

  /// null si es borrador o la etiqueta no es SemVer.
  static ReleaseInfo? fromJson(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final tag = '${json['tag_name'] ?? ''}';
    final version = SemVer.tryParse(tag);
    if (version == null) return null;
    final assets = <ReleaseAsset>[
      for (final a in (json['assets'] as List? ?? const []))
        if (a is Map && Uri.tryParse('${a['browser_download_url']}') != null)
          ReleaseAsset(
            '${a['name']}',
            Uri.parse('${a['browser_download_url']}'),
            (a['size'] as num?)?.toInt() ?? 0,
          ),
    ];
    return ReleaseInfo(
      tag: tag,
      version: version,
      notes: '${json['body'] ?? ''}',
      prerelease: json['prerelease'] == true,
      assets: assets,
    );
  }

  ReleaseAsset? get checksums =>
      assets.where((a) => a.name == 'checksums.txt').firstOrNull;

  /// Instalador según plataforma. En Android prefiere el APK de la ABI del
  /// dispositivo (`Aurora-x.y.z-arm64-v8a.apk`) y cae al universal.
  ReleaseAsset? assetFor({
    required bool windows,
    List<String> abis = const [],
  }) {
    if (windows) {
      return assets
          .where((a) => a.name == 'Aurora-Setup-$version.exe')
          .firstOrNull;
    }
    for (final abi in abis) {
      final hit = assets.where((a) => a.name == 'Aurora-$version-$abi.apk');
      if (hit.isNotEmpty) return hit.first;
    }
    return assets.where((a) => a.name == 'Aurora-$version.apk').firstOrNull;
  }
}

/// `checksums.txt`: líneas `<sha256>  <archivo>` (también `*archivo`).
String? checksumFor(String text, String file) {
  for (final line in const LineSplitter().convert(text)) {
    final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$').firstMatch(line);
    if (m != null && m[2] == file) return m[1]!.toLowerCase();
  }
  return null;
}

// ------------------------------------------------------------- Transporte

class UpdateResponse {
  UpdateResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers; // claves en minúsculas
  final Stream<List<int>> body;
}

abstract class UpdateTransport {
  Future<UpdateResponse> get(Uri url, {Map<String, String> headers});
}

void checkUpdateUrl(Uri url) {
  if (url.scheme != 'https' || !_allowedHosts.contains(url.host)) {
    throw UpdateException('Dirección de actualización no permitida.');
  }
}

/// Cliente real: HTTPS, redirecciones manuales validadas contra la lista blanca.
class HttpUpdateTransport implements UpdateTransport {
  @override
  Future<UpdateResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var current = url;
      for (var hop = 0; hop < 6; hop++) {
        checkUpdateUrl(current);
        final req = await client.getUrl(current);
        req.followRedirects = false;
        headers.forEach(req.headers.set);
        final res = await req.close();
        if (res.isRedirect) {
          await res.drain<void>();
          final loc = res.headers.value('location');
          if (loc == null) throw UpdateException('Redirección inválida.');
          current = current.resolve(loc);
          continue;
        }
        final h = <String, String>{};
        res.headers.forEach((k, v) => h[k.toLowerCase()] = v.join(','));
        final body = res
            .timeout(const Duration(seconds: 30))
            .transform(
              StreamTransformer<List<int>, List<int>>.fromHandlers(
                handleDone: (sink) {
                  client.close();
                  sink.close();
                },
              ),
            );
        return UpdateResponse(res.statusCode, h, body);
      }
      throw UpdateException('Demasiadas redirecciones.');
    } catch (_) {
      client.close(force: true);
      rethrow;
    }
  }
}

// ---------------------------------------------------------------- Servicio

/// Almacén clave-valor mínimo (SharedPreferences en la app, mapa en tests).
abstract class UpdateStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

class UpdateService {
  UpdateService({required this.transport, required this.store});

  final UpdateTransport transport;
  final UpdateStore store;

  static Uri _api(String path) =>
      Uri.parse('https://api.github.com/repos/$updateRepo/$path');

  /// Última versión mayor que [current], o null si ya está al día.
  /// Usa ETag: un 304 reutiliza la respuesta cacheada.
  Future<ReleaseInfo?> check(SemVer current, {bool beta = false}) async {
    final url = beta ? _api('releases?per_page=10') : _api('releases/latest');
    final key = beta ? 'beta' : 'stable';
    final etag = store.read('updateEtag_$key');
    final cached = store.read('updateBody_$key');
    final UpdateResponse res;
    try {
      res = await transport.get(
        url,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'AuroraMusic-Updater',
          if (etag != null && cached != null) 'If-None-Match': etag,
        },
      );
    } on UpdateException {
      rethrow;
    } on Object {
      throw UpdateException('Sin conexión. No se pudo buscar actualizaciones.');
    }
    String body;
    if (res.status == 304 && cached != null) {
      await res.body.drain<void>();
      body = cached;
    } else if (res.status == 200) {
      body = await utf8.decodeStream(res.body);
      final tag = res.headers['etag'];
      if (tag != null) {
        await store.write('updateEtag_$key', tag);
        await store.write('updateBody_$key', body);
      }
    } else {
      await res.body.drain<void>();
      if (res.status == 403 || res.status == 429) {
        throw UpdateException(
          'Límite de la API de GitHub alcanzado. Inténtalo más tarde.',
        );
      }
      throw UpdateException('GitHub respondió ${res.status}.');
    }
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw UpdateException('Respuesta de GitHub no válida.');
    }
    ReleaseInfo? best;
    for (final r in (json is List ? json : [json])) {
      if (r is! Map<String, dynamic>) continue;
      final info = ReleaseInfo.fromJson(r);
      if (info == null || (info.prerelease && !beta)) continue;
      if (best == null || info.version.compareTo(best.version) > 0) best = info;
    }
    return best != null && best.version.compareTo(current) > 0 ? best : null;
  }

  /// Descarga [asset] a [dir] (reanuda con Range tras un corte), verifica su
  /// SHA-256 contra `checksums.txt` y devuelve el archivo. Si el hash no
  /// coincide borra el archivo y lanza; nunca devuelve un archivo sin verificar.
  Future<File> download(
    ReleaseInfo release,
    ReleaseAsset asset,
    Directory dir, {
    void Function(int received, int total)? onProgress,
  }) async {
    final sums = release.checksums;
    if (sums == null) {
      throw UpdateException('El release no incluye checksums.txt.');
    }
    final String expected;
    try {
      final sumsRes = await transport.get(sums.url);
      if (sumsRes.status != 200) {
        await sumsRes.body.drain<void>();
        throw UpdateException(
          'No se pudo leer checksums.txt (${sumsRes.status}).',
        );
      }
      final text = await utf8.decodeStream(sumsRes.body);
      final found = checksumFor(text, asset.name);
      if (found == null) {
        throw UpdateException('checksums.txt no lista ${asset.name}.');
      }
      expected = found;
    } on UpdateException {
      rethrow;
    } on Object {
      throw UpdateException('Sin conexión. Reintenta la descarga.');
    }

    await dir.create(recursive: true);
    final target = File('${dir.path}/${asset.name}');
    final part = File('${target.path}.part');
    var have = part.existsSync() ? part.lengthSync() : 0;
    try {
      final res = await transport.get(
        asset.url,
        headers: {if (have > 0) 'Range': 'bytes=$have-'},
      );
      if (res.status != 200 && res.status != 206) {
        await res.body.drain<void>();
        throw UpdateException('Descarga rechazada (${res.status}).');
      }
      if (res.status == 200) have = 0; // el servidor ignoró Range
      final sink = part.openSync(
        mode: have > 0 ? FileMode.append : FileMode.write,
      );
      try {
        var received = have;
        await for (final chunk in res.body) {
          sink.writeFromSync(chunk);
          received += chunk.length;
          onProgress?.call(received, asset.size);
        }
      } finally {
        sink.closeSync();
      }
    } on UpdateException {
      rethrow;
    } on Object {
      // Se conserva el .part para reanudar al reintentar.
      throw UpdateException('Se interrumpió la descarga. Reintenta.');
    }
    if (asset.size > 0 && part.lengthSync() != asset.size) {
      throw UpdateException('Descarga incompleta. Reintenta.');
    }
    final actual = (await sha256.bind(part.openRead()).first).toString();
    if (actual != expected) {
      await part.delete();
      throw UpdateException(
        'El archivo descargado está corrupto (SHA-256 no coincide).',
      );
    }
    if (target.existsSync()) await target.delete();
    return part.rename(target.path);
  }

  /// Borra descargas de versiones ya instaladas (se conserva lo pendiente).
  static void cleanup(Directory dir, SemVer current) {
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(f.uri.pathSegments.last);
      final v = m == null ? null : SemVer.tryParse(m[1]!);
      if (v == null || v.compareTo(current) <= 0) {
        try {
          f.deleteSync();
        } on FileSystemException {
          // En uso: se reintentará en el próximo arranque.
        }
      }
    }
  }
}
