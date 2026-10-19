import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../dj/suggestions_api.dart';
import '../metadata/youtube_match.dart';
import 'lb_recs.dart';
import 'listen_storage.dart';
import 'listenbrainz_client.dart';
import 'scrobbler.dart';

enum LbStatus { idle, working, ok, invalid, error }

/// ListenBrainz opcional: interruptor (apagado por defecto), token en
/// almacenamiento seguro, scrobbling, novedades y recomendaciones del DJ.
/// Sin token guardado o con el interruptor apagado no sale ninguna petición.
///
/// Conectar «Novedades» (sección de seguir artistas): llamar a
/// [freshReleases] cuando [active] sea true; devuelve `FreshRelease`
/// (artista, título, fecha, tipo, mbid) con caché de 6 h y lista vacía ante
/// cualquier fallo.
class ListenBrainzService extends ChangeNotifier {
  ListenBrainzService({
    required this.preferences,
    required this.tokenStore,
    required this.queueStore,
    ListenBrainzClient? client,
    DateTime Function()? clock,
  }) : client = client ?? ListenBrainzClient(),
       _now = clock ?? DateTime.now {
    scrobbler = Scrobbler(
      client: this.client,
      store: queueStore,
      readToken: _readToken,
      onChanged: notifyListeners,
      onAuthFailed: () => _set(
        LbStatus.invalid,
        'ListenBrainz rechazó el token. Valídalo de nuevo.',
      ),
    );
  }

  static const enabledKey = 'listenbrainz.enabled';
  static const userKey = 'listenbrainz.user';

  final SharedPreferences preferences;
  final TokenStore tokenStore;
  final ListenQueueStore queueStore;
  final ListenBrainzClient client;
  late final Scrobbler scrobbler;
  final DateTime Function() _now;

  bool _hasToken = false, _secureUnavailable = false, _disposed = false;
  LbStatus status = LbStatus.idle;
  String? message;
  (DateTime, List<FreshRelease>)? _fresh;

  bool get enabled => preferences.getBool(enabledKey) ?? false;
  String? get username => preferences.getString(userKey);
  bool get hasToken => _hasToken;
  bool get secureUnavailable => _secureUnavailable;
  int get pending => scrobbler.pending;

  /// Hay interruptor, token y usuario: puede enviar y pedir.
  bool get active => enabled && _hasToken && username != null;

  Future<String?> _readToken() async {
    try {
      return await tokenStore.read();
    } on Object {
      // Antes fallaba en silencio y no se enviaba nada: ahora se avisa en el panel.
      if (!_secureUnavailable && !_disposed) {
        _secureUnavailable = true;
        _set(LbStatus.error, 'No se pudo leer el token del almacén seguro.');
      }
      return null;
    }
  }

  /// Token guardado y usuario válidos pero el interruptor está apagado: no se
  /// publica nada hasta que el usuario lo encienda.
  bool get needsEnable => _hasToken && username != null && !enabled;

  /// «Probar conexión»: valida el token guardado contra ListenBrainz.
  Future<void> testConnection() async {
    final String? token;
    try {
      token = await tokenStore.read();
    } on Object {
      _secureUnavailable = true;
      _set(LbStatus.error, 'No se pudo leer el token del almacén seguro.');
      return;
    }
    if (token == null) {
      _hasToken = false;
      _set(LbStatus.invalid, 'No hay token guardado. Valida uno primero.');
      return;
    }
    _set(LbStatus.working);
    try {
      final user = await client.validateToken(token);
      if (user == null) {
        _set(
          LbStatus.invalid,
          'ListenBrainz rechazó el token (autenticación fallida).',
        );
        return;
      }
      await scrobbler.clearAuthFailure();
      _set(
        LbStatus.ok,
        enabled
            ? 'Conexión correcta como $user.'
            : 'Conexión correcta como $user, pero el interruptor está apagado: no se envía nada.',
      );
    } on ListenBrainzException catch (e) {
      _set(LbStatus.error, e.message);
    } on Object {
      _set(LbStatus.error, 'No se pudo comprobar la conexión.');
    }
  }

  void _set(LbStatus s, [String? text]) {
    status = s;
    message = text == null ? null : redactToken(text);
    if (!_disposed) notifyListeners();
  }

  /// Al arrancar: lee el estado y, si estaba activo, reanuda la cola.
  Future<void> init() async {
    try {
      _hasToken = (await tokenStore.read()) != null;
    } on Object {
      _secureUnavailable = true; // sin almacenamiento seguro no se guarda nada
      _hasToken = false;
    }
    scrobbler.enabled = active;
    if (active) {
      await scrobbler.loadQueue();
      unawaited(scrobbler.flush());
    }
    notifyListeners();
  }

  /// `null` si no hay pista cargada o suena en Jam: se reinicia la sesión.
  void observe(
    Track? track, {
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    if (!scrobbler.enabled) return;
    scrobbler.observe(
      track,
      playing: playing,
      position: position,
      duration: duration,
    );
  }

  Future<void> setEnabled(bool value) async {
    if (value && !(_hasToken && username != null)) {
      _set(LbStatus.invalid, 'Valida primero tu token.');
      return;
    }
    await preferences.setBool(enabledKey, value);
    scrobbler.enabled = active;
    if (active) {
      await scrobbler.loadQueue();
      unawaited(scrobbler.flush());
    } else {
      await scrobbler.clear(); // al apagar no queda historial pendiente
    }
    notifyListeners();
  }

  /// Comprueba el token contra ListenBrainz y, si es válido, lo guarda de
  /// forma segura. El token no se muestra ni se registra nunca.
  Future<void> validateAndSave(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) {
      _set(LbStatus.invalid, 'Pega tu token de usuario de ListenBrainz.');
      return;
    }
    if (_secureUnavailable) {
      _set(
        LbStatus.error,
        'Este sistema no ofrece almacenamiento seguro: ListenBrainz queda desactivado.',
      );
      return;
    }
    _set(LbStatus.working);
    try {
      final user = await client.validateToken(token);
      if (user == null) {
        _set(LbStatus.invalid, 'ListenBrainz no reconoce ese token.');
        return;
      }
      await tokenStore.write(token);
      _hasToken = true;
      await preferences.setString(userKey, user);
      scrobbler.enabled = active;
      scrobbler.tokenReplaced();
      _set(
        LbStatus.ok,
        'Conectado como $user. Activa «Enviar mi historial» para empezar a publicar.',
      );
    } on ListenBrainzException catch (e) {
      _set(LbStatus.error, e.message);
    } on Object {
      // No se muestra el error crudo: podría arrastrar datos de la petición.
      _set(LbStatus.error, 'No se pudo guardar o comprobar el token.');
    }
  }

  /// Borra token, usuario, interruptor y cola.
  Future<void> signOut() async {
    scrobbler.enabled = false;
    try {
      await tokenStore.delete();
    } on Object {
      // sin almacenamiento seguro no había nada guardado
    }
    _hasToken = false;
    _fresh = null;
    await preferences.remove(userKey);
    await preferences.setBool(enabledKey, false);
    await scrobbler.clear();
    _set(LbStatus.idle, 'Sesión cerrada. Token y cola borrados.');
  }

  /// Novedades personalizadas por tu historial. Vacío si no está activo o falla.
  Future<List<FreshRelease>> freshReleases({bool force = false}) async {
    final user = username;
    if (!active || user == null) return const [];
    final cached = _fresh;
    if (!force &&
        cached != null &&
        _now().difference(cached.$1) < const Duration(hours: 6)) {
      return cached.$2;
    }
    try {
      final list = await client.freshReleases(user);
      _fresh = (_now(), list);
      return list;
    } on Object {
      return cached?.$2 ?? const [];
    }
  }

  /// Fuente de candidatos del DJ; se consulta solo si [active].
  RecSource recSource(YoutubeMatcher matcher) => LbRecsSource(
    client: client,
    matcher: matcher,
    readToken: _readToken,
    userName: () => username,
    enabled: () => active,
  ).source;

  @override
  void dispose() {
    _disposed = true;
    scrobbler.dispose();
    super.dispose();
  }
}
