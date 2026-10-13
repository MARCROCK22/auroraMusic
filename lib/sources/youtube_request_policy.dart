import 'dart:async';

enum YouTubeFailure { blocked, unavailable, accessDenied, transient, other }

/// A bounded request lane. It never changes clients, accounts or network routes.
class YouTubeRequestPolicy {
  YouTubeRequestPolicy({
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
    this.requestSpacing = const Duration(seconds: 1),
    this.cooldown = const Duration(minutes: 15),
  }) : _now = now ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed;

  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;
  final Duration requestSpacing, cooldown;
  void Function(DateTime)? onBlocked;
  Future<void> _lane = Future.value();
  int _active = 0;
  final List<Completer<void>> _waiting = [];
  DateTime? _lastStart, _blockedUntil;
  DateTime? get blockedUntil => _blockedUntil;
  void restoreCooldown(DateTime? until) {
    _blockedUntil = until;
  }

  int requestsStarted = 0;

  static YouTubeFailure classify(String message) {
    final text = message.toLowerCase();
    if (RegExp(
      r'429|too many requests|not a bot|confirm you|unusual traffic|rate.?limit',
    ).hasMatch(text)) {
      return YouTubeFailure.blocked;
    }
    if (RegExp(
      r'video unavailable|private video|removed|not available in your country',
    ).hasMatch(text)) {
      return YouTubeFailure.unavailable;
    }
    if (RegExp(r'403|forbidden').hasMatch(text)) {
      return YouTubeFailure.accessDenied;
    }
    if (RegExp(
      r'timeout|timed out|connection reset|connection closed|socketexception|\b50[234]\b',
    ).hasMatch(text)) {
      return YouTubeFailure.transient;
    }
    return YouTubeFailure.other;
  }

  void recordFailure(String message) {
    final failure = classify(message);
    if (failure == YouTubeFailure.blocked ||
        failure == YouTubeFailure.accessDenied) {
      if (_blockedUntil == null || !_now().isBefore(_blockedUntil!)) {
        _blockedUntil = _now().add(cooldown);
        onBlocked?.call(_blockedUntil!);
      }
    }
  }

  void _checkCooldown() {
    final until = _blockedUntil;
    if (until != null && _now().isBefore(until)) {
      throw StateError(
        'YouTube limitó o rechazó las solicitudes. Aurora ha detenido los reintentos durante 15 minutos. La música local sigue disponible.',
      );
    }
  }

  Future<void> _reserveStart() async {
    final task = _lane.then((_) async {
      _checkCooldown();
      final last = _lastStart;
      if (last != null) {
        final delay = requestSpacing - _now().difference(last);
        if (delay > Duration.zero) await _sleep(delay);
      }
      _checkCooldown();
      _lastStart = _now();
    });
    _lane = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    await task;
  }

  Future<T> run<T>(
    Future<T> Function() request, {
    bool retryTransient = false,
  }) async {
    _checkCooldown();
    if (_active >= 2) {
      final ready = Completer<void>();
      if (_waiting.length >= 8) {
        throw StateError(
          'La fuente está ocupada. Espera a que termine una solicitud.',
        );
      }
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      for (var attempt = 0; ; attempt++) {
        await _reserveStart();
        requestsStarted++;
        try {
          return await request();
        } catch (error) {
          recordFailure(error.toString());
          if (!retryTransient ||
              attempt >= 1 ||
              classify(error.toString()) != YouTubeFailure.transient) {
            rethrow;
          }
          await _sleep(const Duration(seconds: 2));
          _checkCooldown();
        }
      }
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeAt(0).complete();
      } else {
        _active--;
      }
    }
  }
}
