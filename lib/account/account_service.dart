import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase/supabase.dart';

import '../jam/transport/jam_config.dart';

/// Se sobrescribe al arrancar (main.dart) con la instancia de AppController.
final accountServiceProvider = ChangeNotifierProvider<AccountService>(
  // main.dart la sobrescribe; sin claves (tests) queda no disponible.
  (ref) => AccountService(),
);

class AccountProfile {
  const AccountProfile({
    required this.id,
    required this.username,
    this.avatarUrl,
  });
  final String id;
  final String username;
  final String? avatarUrl;
}

/// Error con mensaje listo para mostrar (nunca contiene credenciales).
class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
final _usernameRe = RegExp(r'^[a-z0-9_.]{3,24}$');
final _avatarPathRe = RegExp(r'^[0-9a-f-]{36}/[0-9]{1,16}\.png$');

String? validateEmail(String v) =>
    v.trim().length <= 254 && _emailRe.hasMatch(v.trim())
    ? null
    : 'Escribe un correo válido.';
String? validateUsername(String v) => _usernameRe.hasMatch(v.trim())
    ? null
    : 'Usuario de 3 a 24 caracteres: minúsculas, números, _ y .';
String? validatePassword(String v) => v.length < 8
    ? 'La contraseña debe tener al menos 8 caracteres.'
    : v.length > 72
    ? 'La contraseña es demasiado larga (máximo 72).'
    : null;

/// Traduce errores de Supabase/red a mensajes en español.
AccountException mapAccountError(Object e) {
  if (e is AccountException) return e;
  if (e is SocketException || e is TimeoutException || e is HttpException) {
    return const AccountException(
      'Sin conexión. Revisa tu red e inténtalo de nuevo.',
    );
  }
  final text = e is AuthException
      ? '${e.code ?? ''} ${e.message}'.toLowerCase()
      : e is PostgrestException
      ? '${e.code ?? ''} ${e.message}'.toLowerCase()
      : e.toString().toLowerCase();
  if (text.contains('already') || text.contains('registered')) {
    return const AccountException('Ese correo ya tiene una cuenta.');
  }
  if (text.contains('weak_password') || text.contains('password should')) {
    return const AccountException(
      'Contraseña débil: usa al menos 8 caracteres.',
    );
  }
  if (text.contains('invalid_credentials') || text.contains('invalid login')) {
    return const AccountException('Correo o contraseña incorrectos.');
  }
  if (text.contains('email_not_confirmed') || text.contains('not confirmed')) {
    return const AccountException('Confirma tu correo antes de entrar.');
  }
  if (text.contains('23505') ||
      text.contains('duplicate') ||
      text.contains('database error saving new user') ||
      text.contains('username')) {
    return const AccountException('Ese nombre de usuario ya está en uso.');
  }
  if (text.contains('over_') || text.contains('rate limit')) {
    return const AccountException('Demasiados intentos. Espera un momento.');
  }
  if (text.contains('socket') ||
      text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('host lookup') ||
      text.contains('getaddrinfo') ||
      text.contains('connection')) {
    return const AccountException(
      'Sin conexión. Revisa tu red e inténtalo de nuevo.',
    );
  }
  return const AccountException('No se pudo completar la operación.');
}

/// Operaciones de almacenamiento de avatares (falsificable en pruebas).
abstract class AvatarStorage {
  Future<void> upload(String path, Uint8List png);
  Future<void> remove(String path);
  Future<void> setProfilePath(String? path);
}

/// Sube el nuevo archivo, apunta el perfil a él y SOLO entonces borra el
/// anterior (si algo falla antes, el avatar viejo sigue intacto).
Future<String> replaceAvatar({
  required AvatarStorage storage,
  required String uid,
  required String? previous,
  required Uint8List png,
  required int millis,
}) async {
  final path = '$uid/$millis.png';
  await storage.upload(path, png);
  try {
    await storage.setProfilePath(path);
  } catch (_) {
    try {
      await storage.remove(path);
    } catch (_) {}
    rethrow;
  }
  if (previous != null && previous != path) {
    try {
      await storage.remove(previous);
    } catch (_) {} // huérfano inofensivo; no debe fallar el cambio
  }
  return path;
}

class AccountService extends ChangeNotifier {
  AccountService({JamSupabaseConfig? config, FlutterSecureStorage? storage})
    : _config = config ?? JamSupabaseConfig.fromEnvironment,
      _storage = storage ?? const FlutterSecureStorage();

  static const _sessionKey = 'aurora.account.session';
  final JamSupabaseConfig? _config;
  final FlutterSecureStorage _storage;
  SupabaseClient? _client;
  StreamSubscription<AuthState>? _sub;
  AccountProfile? _profile;
  String? _avatarPath;

  bool get available => _config != null;
  SupabaseClient? get client => _client ??= _build();
  AccountProfile? get profile => _profile;
  bool get signedIn => _client?.auth.currentSession != null;

  SupabaseClient? _build() {
    final config = _config;
    if (config == null) return null;
    final client = SupabaseClient(config.url, config.anonKey);
    _sub = client.auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (state.event == AuthChangeEvent.signedOut || session == null) {
        unawaited(_storage.delete(key: _sessionKey).catchError((_) {}));
      } else if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.tokenRefreshed ||
          state.event == AuthChangeEvent.userUpdated) {
        unawaited(
          _storage
              .write(key: _sessionKey, value: jsonEncode(session.toJson()))
              .catchError((_) {}),
        );
      }
    });
    return client;
  }

  Future<void> init() async {
    final c = client;
    if (c == null) return;
    try {
      final saved = await _storage.read(key: _sessionKey);
      if (saved == null) return;
      // La sesión anónima de la Jam no cuenta como cuenta.
      await c.auth.recoverSession(saved);
      if (c.auth.currentUser?.isAnonymous ?? true) {
        await c.auth.signOut(scope: SignOutScope.local);
        return;
      }
      await _loadProfile();
    } on AuthException catch (e) {
      // Token inválido/revocado: se descarta. Los fallos de red conservan la sesión.
      if (e is! AuthRetryableFetchException) {
        await _storage.delete(key: _sessionKey).catchError((_) {});
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    final user = client?.auth.currentUser;
    if (user == null) return;
    try {
      final row = await client!
          .from('profiles')
          .select('id,username,avatar_path')
          .eq('id', user.id)
          .single();
      _avatarPath = _validPath(row['avatar_path'] as String?);
      _profile = AccountProfile(
        id: user.id,
        username: row['username'] as String,
        avatarUrl: avatarUrlFor(_avatarPath),
      );
    } catch (_) {
      // Sin red: perfil mínimo con el nombre guardado en la sesión.
      _profile ??= AccountProfile(
        id: user.id,
        username: '${user.userMetadata?['username'] ?? ''}',
      );
    }
  }

  static String? _validPath(String? p) =>
      p != null && _avatarPathRe.hasMatch(p) ? p : null;

  Future<T> _guard<T>(Future<T> Function() run) async {
    if (client == null) {
      throw const AccountException('Las cuentas no están configuradas.');
    }
    try {
      return await run();
    } catch (e) {
      throw mapAccountError(e);
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    final problem =
        validateEmail(email) ??
        validateUsername(username) ??
        validatePassword(password);
    if (problem != null) throw AccountException(problem);
    await _guard(() async {
      final res = await client!.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username.trim()},
      );
      if (res.session == null) {
        throw const AccountException(
          'Cuenta creada. Confirma tu correo y luego inicia sesión.',
        );
      }
      await _loadProfile();
    });
    notifyListeners();
  }

  Future<void> signIn({required String email, required String password}) async {
    final problem = validateEmail(email) ?? validatePassword(password);
    if (problem != null) {
      throw const AccountException('Correo o contraseña incorrectos.');
    }
    await _guard(() async {
      await client!.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      await _loadProfile();
    });
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await client?.auth.signOut();
    } catch (_) {
      // Sin red igualmente se cierra en este dispositivo.
      try {
        await client?.auth.signOut(scope: SignOutScope.local);
      } catch (_) {}
    }
    _profile = null;
    _avatarPath = null;
    await _storage.delete(key: _sessionKey).catchError((_) {});
    notifyListeners();
  }

  Future<void> resetPassword(String email) async {
    final problem = validateEmail(email);
    if (problem != null) throw AccountException(problem);
    await _guard(() => client!.auth.resetPasswordForEmail(email.trim()));
  }

  late final _avatarStorage = _SupabaseAvatarStorage(this);

  Future<void> setAvatar(Uint8List png) async {
    final p = _profile;
    if (p == null) throw const AccountException('Inicia sesión primero.');
    if (png.length > 65536) {
      throw const AccountException('La imagen es demasiado grande.');
    }
    await _guard(() async {
      _avatarPath = await replaceAvatar(
        storage: _avatarStorage,
        uid: p.id,
        previous: _avatarPath,
        png: png,
        millis: DateTime.now().millisecondsSinceEpoch,
      );
      _profile = AccountProfile(
        id: p.id,
        username: p.username,
        avatarUrl: avatarUrlFor(_avatarPath),
      );
    });
    notifyListeners();
  }

  Future<void> removeAvatar() async {
    final p = _profile;
    if (p == null) return;
    final old = _avatarPath;
    await _guard(() async {
      await _avatarStorage.setProfilePath(null);
      if (old != null) {
        try {
          await _avatarStorage.remove(old);
        } catch (_) {}
      }
      _avatarPath = null;
      _profile = AccountProfile(id: p.id, username: p.username);
    });
    notifyListeners();
  }

  String? avatarUrlFor(String? avatarPath) {
    final config = _config;
    final path = _validPath(avatarPath);
    if (config == null || path == null) return null;
    return '${config.url}/storage/v1/object/public/avatars/$path';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class _SupabaseAvatarStorage implements AvatarStorage {
  _SupabaseAvatarStorage(this._s);
  final AccountService _s;

  @override
  Future<void> upload(String path, Uint8List png) => _s.client!.storage
      .from('avatars')
      .uploadBinary(
        path,
        png,
        fileOptions: const FileOptions(contentType: 'image/png'),
      );

  @override
  Future<void> remove(String path) =>
      _s.client!.storage.from('avatars').remove([path]);

  @override
  Future<void> setProfilePath(String? path) => _s.client!
      .from('profiles')
      .update({'avatar_path': path})
      .eq('id', _s._profile!.id);
}
