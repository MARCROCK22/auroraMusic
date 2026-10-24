import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../dj/suggestions_api.dart';
import '../metadata/youtube_match.dart';
import 'lastfm_client.dart';
import 'lastfm_recs.dart';
import 'lastfm_stats.dart';
import 'lastfm_storage.dart';
import 'scrobbler.dart';

enum LfmStatus { idle, working, ok, invalid, error }

/// Last.fm opcional: cada usuario conecta su cuenta (usuario y contraseña, solo
/// para obtener una clave de sesión que va al almacenamiento seguro). El
/// interruptor está apagado por defecto; sin sesión o apagado no sale ninguna
/// petición de envío ni de recomendaciones.
class LastfmService extends ChangeNotifier {
  LastfmService({
    required this.preferences,
    required this.tokenStore,
    required this.queueStore,
    LastfmClient? client,
    DateTime Function()? clock,
  }) : client = client ?? LastfmClient(),
       _now = clock ?? DateTime.now {
    scrobbler = Scrobbler(
      client: this.client,
      store: queueStore,
      readSession: _readSession,
      onChanged: notifyListeners,
      onAuthFailed: _sessionLost,
    );
  }

  static const enabledKey = 'lastfm.enabled';
  static const userKey = 'lastfm.user';

  final SharedPreferences preferences;
  final TokenStore tokenStore;
  final ListenQueueStore queueStore;
  final LastfmClient client;
  late final Scrobbler scrobbler;
  final DateTime Function() _now;

  bool _hasSession = false, _secureUnavailable = false, _disposed = false;
  LfmStatus status = LfmStatus.idle;
  String? message;

  /// Falta la clave de la app en esta compilación: todo queda desactivado.
  bool get configured => client.configured;
  bool get enabled => preferences.getBool(enabledKey) ?? false;
  String? get username => preferences.getString(userKey);
  bool get hasSession => _hasSession;
  bool get secureUnavailable => _secureUnavailable;
  int get pending => scrobbler.pending;

  /// Cuenta conectada (permite leer estadísticas públicas).
  bool get connected => configured && _hasSession && username != null;

  /// Conectada y con el interruptor encendido: puede enviar y pedir.
  bool get active => connected && enabled;

  /// Sesión guardada pero interruptor apagado: no se publica nada aún.
  bool get needsEnable => connected && !enabled;

  Future<String?> _readSession() async {
    try {
      return await tokenStore.read();
    } on Object {
      if (!_secureUnavailable && !_disposed) {
        _secureUnavailable = true;
        _set(LfmStatus.error, 'No se pudo leer la sesión del almacén seguro.');
      }
      return null;
    }
  }

  void _set(LfmStatus s, [String? text]) {
    status = s;
    message = text;
    if (!_disposed) notifyListeners();
  }

  /// Last.fm devolvió «sesión inválida» (9): se desconecta; la cola se conserva.
  Future<void> _sessionLost() async {
    try {
      await tokenStore.delete();
    } on Object {
      // nada que borrar
    }
    _hasSession = false;
    scrobbler.enabled = false;
    _set(
      LfmStatus.invalid,
      'Last.fm cerró tu sesión. Vuelve a conectar tu cuenta.',
    );
  }

  /// Al arrancar: lee el estado y, si estaba activo, reanuda la cola.
  Future<void> init() async {
    try {
      _hasSession = (await tokenStore.read()) != null;
    } on Object {
      _secureUnavailable = true; // sin almacenamiento seguro no se guarda nada
      _hasSession = false;
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
    if (value && !connected) {
      _set(LfmStatus.invalid, 'Conecta primero tu cuenta de Last.fm.');
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

  /// Inicia sesión en Last.fm. La contraseña solo viaja en esa petición HTTPS:
  /// no se guarda ni se registra; se conserva únicamente la clave de sesión.
  Future<void> connect(String rawUser, String password) async {
    final user = rawUser.trim();
    if (!configured) {
      _set(LfmStatus.error, 'Last.fm no está configurado en esta compilación.');
      return;
    }
    if (user.isEmpty || password.isEmpty) {
      _set(LfmStatus.invalid, 'Escribe tu usuario y contraseña de Last.fm.');
      return;
    }
    if (_secureUnavailable) {
      _set(
        LfmStatus.error,
        'Este sistema no ofrece almacenamiento seguro: Last.fm queda desactivado.',
      );
      return;
    }
    _set(LfmStatus.working);
    try {
      final session = await client.getMobileSession(user, password);
      await tokenStore.write(session.key);
      _hasSession = true;
      await preferences.setString(userKey, session.name);
      scrobbler.enabled = active;
      scrobbler.sessionReplaced();
      _set(
        LfmStatus.ok,
        'Conectado como ${session.name}. Activa «Enviar mi historial» para empezar a publicar.',
      );
    } on LastfmException catch (e) {
      _set(
        LfmStatus.invalid,
        e.code == 4 || e.code == 26
            ? 'Usuario o contraseña incorrectos.'
            : e.message,
      );
    } on Object {
      // No se muestra el error crudo: podría arrastrar datos de la petición.
      _set(LfmStatus.error, 'No se pudo conectar con Last.fm.');
    }
  }

  /// Borra sesión, usuario, interruptor y cola.
  Future<void> signOut() async {
    scrobbler.enabled = false;
    try {
      await tokenStore.delete();
    } on Object {
      // sin almacenamiento seguro no había nada guardado
    }
    _hasSession = false;
    await preferences.remove(userKey);
    await preferences.setBool(enabledKey, false);
    await scrobbler.clear();
    _set(LfmStatus.idle, 'Cuenta desconectada. Sesión y cola borradas.');
  }

  /// Estadísticas de escucha con caché en preferencias (1 h). Lanza si no hay
  /// cuenta conectada o la red falla sin caché.
  Future<ListenStats> stats(StatsRange range, {bool force = false}) async {
    final user = username;
    final key = 'lastfm.stats.$user.${range.api}';
    ListenStats? cached;
    DateTime? at;
    try {
      final raw = preferences.getString(key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
        cached = ListenStats.fromJson(j['d']);
      }
    } on Object {
      cached = null;
    }
    if (!force &&
        cached != null &&
        at != null &&
        _now().difference(at) < const Duration(hours: 1)) {
      return cached;
    }
    if (!connected || user == null) {
      throw LastfmException('Last.fm no está conectado.');
    }
    try {
      final s = await client.userStats(user, range);
      await preferences.setString(
        key,
        jsonEncode({'at': _now().millisecondsSinceEpoch, 'd': s.toJson()}),
      );
      return s;
    } on Object {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Fuente de candidatos del DJ; se consulta solo si [active].
  RecSource recSource(YoutubeMatcher matcher) => LastfmRecsSource(
    client: client,
    matcher: matcher,
    enabled: () => active,
  ).source;

  @override
  void dispose() {
    _disposed = true;
    scrobbler.dispose();
    super.dispose();
  }
}
