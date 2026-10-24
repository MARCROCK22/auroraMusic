import 'dart:async';
import 'dart:math' as math;

import '../core/models.dart';
import '../dj/reco_memory.dart';
import 'listen.dart';
import 'lastfm_storage.dart';
import 'lastfm_client.dart';

/// Mínimo para contar un listen y tope de la regla «50 % o 4 minutos».
const kMinListenDuration = Duration(seconds: 30);
const kMaxListenThreshold = Duration(minutes: 4);
const kPlayingNowAfter = Duration(seconds: 3);
const kMaxBatch = 50; // máximo de track.scrobble
const kMaxQueue = 500;

/// Tiempo que hay que haber escuchado para contar la pista, o `null` si no
/// cuenta nunca (dura menos de 30 s). Duración desconocida: 4 minutos.
Duration? scrobbleThreshold(Duration duration) {
  if (duration <= Duration.zero) return kMaxListenThreshold;
  if (duration < kMinListenDuration) return null;
  final half = duration ~/ 2;
  final value = half > kMaxListenThreshold ? kMaxListenThreshold : half;
  return value < kMinListenDuration ? kMinListenDuration : value;
}

class _Session {
  _Session(this.track, this.startedAt, this.lastPosition);
  final Track track;
  final DateTime startedAt;
  Duration lastPosition, listened = Duration.zero;
  DateTime? lastTick;
  bool nowSent = false, counted = false;
}

/// Lógica pura del scrobbling: sesiones de escucha, umbral, deduplicación,
/// cola persistente con reintentos y respeto del 429. No conoce Flutter ni
/// el reproductor: recibe observaciones con [observe].
class Scrobbler {
  Scrobbler({
    required this.client,
    required this.store,
    required this.readSession,
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
    this.scheduleRetry,
    this.onChanged,
    this.onAuthFailed,
    this.maxQueue = kMaxQueue,
  }) : _now = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  /// Para tests: sustituye al temporizador real de reintentos.
  final void Function(Duration, void Function())? scheduleRetry;

  final LastfmClient client;
  final ListenQueueStore store;
  final Future<String?> Function() readSession;
  final void Function()? onChanged, onAuthFailed;
  final int maxQueue;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  Timer? _timer;

  void _schedule(Duration wait, void Function() action) {
    final custom = scheduleRetry;
    if (custom != null) return custom(wait, action);
    _timer?.cancel();
    _timer = Timer(wait, action);
  }

  bool enabled = false;
  _Session? _session;
  List<Listen> _queue = [];
  final _recent = <(String, int)>[]; // (identidad, listened_at) ya contados
  bool _flushing = false, _singleMode = false, _authFailed = false;
  DateTime? _blockedUntil;
  int _failures = 0;

  int get pending => _queue.length;
  bool get authFailed => _authFailed;

  /// Diagnóstico para el panel: qué pista se sigue y qué pasó en el último envío.
  Track? get tracking => _session?.track;
  Duration get listenedSoFar => _session?.listened ?? Duration.zero;
  bool get trackingCounted => _session?.counted ?? false;
  Duration? get trackingThreshold {
    final s = _session;
    return s == null ? null : scrobbleThreshold(s.track.duration);
  }

  DateTime? lastSentAt;
  String? lastError;
  int sentCount = 0;

  void _failed(LfmSubmitResult r) {
    lastError = r.detail ?? r.status.name;
    onChanged?.call();
  }

  Future<void> clearAuthFailure() async {
    _authFailed = false;
    lastError = null;
    onChanged?.call();
    await flush();
  }

  Future<void> loadQueue() async {
    _queue = (await store.load()).take(maxQueue).toList();
    onChanged?.call();
  }

  /// Vacía la cola y el estado (cerrar sesión / desactivar).
  Future<void> clear() async {
    _session = null;
    _queue = [];
    _recent.clear();
    _authFailed = false;
    _blockedUntil = null;
    _failures = 0;
    await store.save(const []);
    onChanged?.call();
  }

  /// Sesión nueva: se reanuda el envío.
  void sessionReplaced() {
    _authFailed = false;
    unawaited(flush());
  }

  /// Observa el reproductor. [track] es `null` si no hay pista cargada (o en
  /// Jam compartido: nunca se publica). Se llama muchas veces por segundo.
  void observe(
    Track? track, {
    required bool playing,
    required Duration position,
    required Duration duration,
  }) {
    if (!enabled || track == null) {
      if (_session != null) {
        _session = null;
        onChanged?.call();
      }
      return;
    }
    final now = _now();
    var s = _session;
    final restarted =
        s != null &&
        position < s.lastPosition - const Duration(seconds: 10) &&
        position < const Duration(seconds: 5);
    if (s == null || s.track.id != track.id || restarted) {
      final fresh = position < const Duration(seconds: 5);
      // Reanudar a mitad de pista: el inicio es «ahora», no un instante inventado.
      s = _session = _Session(
        track,
        fresh ? now.subtract(position) : now,
        position,
      );
    }
    if (!playing) {
      s.lastTick = null;
      s.lastPosition = position;
      return;
    }
    final last = s.lastTick;
    if (last != null) {
      final wall = now.difference(last);
      final moved = position - s.lastPosition;
      // Solo cuenta lo realmente reproducido: un salto adelante no suma.
      if (moved > Duration.zero && wall > Duration.zero) {
        final step = moved < wall ? moved : wall;
        s.listened += step > const Duration(seconds: 15)
            ? const Duration(seconds: 15)
            : step;
      }
    }
    s.lastTick = now;
    s.lastPosition = position;
    if (!s.nowSent && s.listened >= kPlayingNowAfter) {
      s.nowSent = true;
      unawaited(_playingNow(s, duration));
    }
    final threshold = scrobbleThreshold(
      duration > Duration.zero ? duration : track.duration,
    );
    if (!s.counted && threshold != null && s.listened >= threshold) {
      s.counted = true;
      onChanged?.call();
      final listen = buildListen(track, s.startedAt, duration: duration);
      if (listen == null) {
        lastError =
            'No se pudo publicar «${track.title}»: falta artista o título fiable.';
      } else if (_enqueue(listen)) {
        unawaited(flush());
      }
    }
  }

  Future<void> _playingNow(_Session s, Duration duration) async {
    if (_authFailed || _blocked) return;
    final listen = buildListen(s.track, s.startedAt, duration: duration);
    final token = await readSession();
    if (listen == null || token == null || !enabled) return;
    final r = await client.updateNowPlaying(token, listen);
    if (r.status == LfmSubmitStatus.rateLimited) _block(r.retryAfter);
    if (r.status == LfmSubmitStatus.unauthorized) _failAuth();
    if (r.status != LfmSubmitStatus.ok) _failed(r);
    // Si falla, se ignora: es solo informativo y se rehace con la siguiente pista.
  }

  bool get _blocked => _blockedUntil != null && _now().isBefore(_blockedUntil!);

  void _block(Duration? after) {
    final wait = after ?? const Duration(seconds: 5);
    _blockedUntil = _now().add(wait);
    _schedule(wait + const Duration(seconds: 1), () => unawaited(flush()));
  }

  void _failAuth() {
    _authFailed = true;
    onAuthFailed?.call();
    onChanged?.call();
  }

  /// `false` si es duplicado (misma pista con inicio casi idéntico).
  bool _enqueue(Listen listen) {
    final key =
        '${listen.artist.toLowerCase()}|${recsNormalizeTitle(listen.title)}';
    for (final (k, at) in _recent) {
      if (k == key && (at - listen.listenedAt).abs() < 20) return false;
    }
    _recent.add((key, listen.listenedAt));
    if (_recent.length > 50) _recent.removeAt(0);
    _queue.add(listen);
    if (_queue.length > maxQueue) {
      _queue = _queue.sublist(_queue.length - maxQueue);
    }
    unawaited(store.save(_queue));
    onChanged?.call();
    return true;
  }

  /// Envía lo pendiente por lotes de hasta 50. Se
  /// reintenta con espera creciente; respeta 429 y su cabecera.
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty || _authFailed || !enabled) return;
    _flushing = true;
    try {
      final token = await readSession();
      if (token == null) {
        lastError = 'No se pudo leer la sesión guardada.';
        onChanged?.call();
        return;
      }
      while (_queue.isNotEmpty) {
        if (_blocked) {
          _schedule(
            _blockedUntil!.difference(_now()) + const Duration(seconds: 1),
            () => unawaited(flush()),
          );
          return;
        }
        final batch = _queue
            .take(_singleMode ? 1 : kMaxBatch)
            .toList(growable: false);
        final r = await client.scrobble(token, batch);
        switch (r.status) {
          case LfmSubmitStatus.ok:
            _failures = 0;
            lastError = null;
            lastSentAt = _now();
            sentCount += batch.length;
            await _drop(batch.length);
            if (_queue.isNotEmpty) await _delay(const Duration(seconds: 1));
          case LfmSubmitStatus.rateLimited:
            _failed(r);
            _block(r.retryAfter);
            return;
          case LfmSubmitStatus.unauthorized:
            _failed(r);
            _failAuth();
            return;
          case LfmSubmitStatus.rejected:
            _failed(r);
            // Un lote rechazado se parte; un listen suelto rechazado se descarta.
            if (batch.length > 1) {
              _singleMode = true;
            } else {
              await _drop(1);
            }
          case LfmSubmitStatus.retry:
            _failed(r);
            _failures++;
            final wait = r.retryAfter ?? _backoff(_failures);
            _schedule(wait, () => unawaited(flush()));
            return;
        }
      }
      _singleMode = false;
    } finally {
      _flushing = false;
    }
  }

  static Duration _backoff(int failures) => Duration(
    seconds: math.min(900, 30 * math.pow(2, math.min(failures, 6) - 1).toInt()),
  );

  Future<void> _drop(int count) async {
    _queue = _queue.sublist(math.min(count, _queue.length));
    await store.save(_queue);
    onChanged?.call();
  }

  void dispose() {
    _timer?.cancel();
    enabled = false;
  }
}
