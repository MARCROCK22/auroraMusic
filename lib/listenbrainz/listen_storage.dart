import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'listen.dart';

/// Dónde vive el token. Nunca texto plano: Windows Credential Locker/DPAPI y
/// Android Keystore (vía flutter_secure_storage). Si no hay, no se guarda.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  static const _key = 'aurora.listenbrainz.token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Cola de listens pendientes (sin credenciales), acotada a [max] entradas.
abstract class ListenQueueStore {
  Future<List<Listen>> load();
  Future<void> save(List<Listen> listens);
}

class MemoryListenQueueStore implements ListenQueueStore {
  List<Listen> saved = [];
  @override
  Future<List<Listen>> load() async => [...saved];
  @override
  Future<void> save(List<Listen> listens) async => saved = [...listens];
}

/// JSON en el directorio de soporte de la app; escritura atómica.
class FileListenQueueStore implements ListenQueueStore {
  FileListenQueueStore(Directory directory)
    : _file = File(p.join(directory.path, 'listenbrainz_queue.json'));
  final File _file;

  @override
  Future<List<Listen>> load() async {
    try {
      if (!await _file.exists()) return [];
      final raw = jsonDecode(await _file.readAsString());
      return raw is List ? raw.map(Listen.fromJson).nonNulls.toList() : [];
    } on Object {
      return []; // archivo corrupto: se empieza de cero
    }
  }

  @override
  Future<void> save(List<Listen> listens) async {
    if (listens.isEmpty) {
      if (await _file.exists()) await _file.delete();
      return;
    }
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final l in listens) l.toJson()]));
    await tmp.rename(_file.path);
  }
}
