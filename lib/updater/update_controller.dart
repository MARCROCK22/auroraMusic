import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hard_exit.dart';
import 'update_service.dart';

enum UpdatePhase { idle, checking, available, downloading, error }

class PrefsUpdateStore implements UpdateStore {
  PrefsUpdateStore(this.prefs);
  final SharedPreferences prefs;
  @override
  String? read(String key) => prefs.getString(key);
  @override
  Future<void> write(String key, String value) => prefs.setString(key, value);
}

/// Estado de las actualizaciones: chequeo (auto cada 6 h o manual), descarga
/// verificada e instalación. Solo Windows y Android; en otras plataformas no
/// hace nada.
class UpdateController extends ChangeNotifier {
  UpdateController(this.prefs, {UpdateService? service})
    : _service =
          service ??
          UpdateService(
            transport: HttpUpdateTransport(),
            store: PrefsUpdateStore(prefs),
          );

  static const _channel = MethodChannel('aurora/updater');
  static const _interval = Duration(hours: 6);

  final SharedPreferences prefs;
  final UpdateService _service;
  Timer? _timer;
  SemVer? _current;
  List<String> _abis = const [];

  UpdatePhase phase = UpdatePhase.idle;
  ReleaseInfo? release;
  double? progress; // 0..1, null si se desconoce el total
  String? error;
  String? info; // «Estás al día», etc.
  bool dismissed = false; // «Más tarde»: oculto hasta reiniciar

  bool get supported => Platform.isWindows || Platform.isAndroid;
  String get currentVersion => _current?.toString() ?? '';
  bool get autoCheck => prefs.getBool('updateAuto') ?? true;
  bool get beta => prefs.getBool('updateBeta') ?? false;
  bool get showBanner =>
      release != null &&
      !dismissed &&
      (phase == UpdatePhase.available ||
          phase == UpdatePhase.downloading ||
          (phase == UpdatePhase.error));

  Future<void> start() async {
    if (!supported) return;
    try {
      final p = await PackageInfo.fromPlatform();
      _current = SemVer.tryParse(p.version);
      if (Platform.isAndroid) {
        _abis = List<String>.from(
          await _channel.invokeMethod<List<Object?>>('abis') ?? const [],
        );
      }
      final dir = await _dir();
      if (_current != null) UpdateService.cleanup(dir, _current!);
    } on Object {
      return; // sin versión no se puede comparar
    }
    // Revisa cada hora si ya pasaron 6 h: cubre la app viva en la bandeja.
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _auto());
    unawaited(_auto());
  }

  Future<void> setAuto(bool v) async {
    await prefs.setBool('updateAuto', v);
    notifyListeners();
  }

  Future<void> setBeta(bool v) async {
    await prefs.setBool('updateBeta', v);
    notifyListeners();
  }

  Future<void> _auto() async {
    if (!autoCheck || phase != UpdatePhase.idle) return;
    final last = prefs.getInt('updateLastCheck') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last <
        _interval.inMilliseconds) {
      return;
    }
    await check(manual: false);
  }

  Future<void> check({bool manual = true}) async {
    final current = _current;
    if (current == null ||
        phase == UpdatePhase.checking ||
        phase == UpdatePhase.downloading) {
      return;
    }
    phase = UpdatePhase.checking;
    error = info = null;
    notifyListeners();
    try {
      final found = await _service.check(current, beta: beta);
      await prefs.setInt(
        'updateLastCheck',
        DateTime.now().millisecondsSinceEpoch,
      );
      final skipped = prefs.getString('updateSkipped') == found?.tag;
      if (found == null || (!manual && skipped)) {
        release = null;
        phase = UpdatePhase.idle;
        if (manual) info = 'Aurora $current está al día.';
      } else {
        release = found;
        dismissed = false;
        phase = UpdatePhase.available;
      }
    } on UpdateException catch (e) {
      phase = UpdatePhase.idle;
      if (manual) {
        error = e.message;
        phase = UpdatePhase.error;
      }
    }
    notifyListeners();
  }

  void later() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> skip() async {
    final r = release;
    if (r != null) await prefs.setString('updateSkipped', r.tag);
    release = null;
    phase = UpdatePhase.idle;
    notifyListeners();
  }

  Future<Directory> _dir() async => Directory(
    '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}aurora_update',
  );

  /// Descarga, verifica e instala. Si algo falla queda en `error` y el botón
  /// «Actualizar ahora» permite reintentar (la descarga se reanuda).
  Future<void> install() async {
    final r = release;
    if (r == null || phase == UpdatePhase.downloading) return;
    final asset = r.assetFor(windows: Platform.isWindows, abis: _abis);
    if (asset == null) {
      _fail('Este release no incluye un instalador para tu plataforma.');
      return;
    }
    if (Platform.isAndroid &&
        await _channel.invokeMethod<bool>('canInstall') != true) {
      await _channel.invokeMethod<void>('openInstallSettings');
      _fail(
        'Activa «Instalar apps desconocidas» para Aurora y vuelve a pulsar Actualizar ahora.',
      );
      return;
    }
    phase = UpdatePhase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final file = await _service.download(
        r,
        asset,
        await _dir(),
        onProgress: (got, total) {
          progress = total > 0 ? (got / total).clamp(0, 1).toDouble() : null;
          notifyListeners();
        },
      );
      if (Platform.isWindows) {
        // El instalador (Inno Setup) cierra, reemplaza y relanza Aurora.
        await Process.start(file.path, const [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
        ], mode: ProcessStartMode.detached);
        await requestHardExit();
      } else {
        await _channel.invokeMethod<void>('install', {'path': file.path});
        phase = UpdatePhase.available;
        progress = null;
        notifyListeners();
      }
    } on UpdateException catch (e) {
      _fail(e.message);
    } on Object catch (e) {
      _fail('No se pudo iniciar la instalación: $e');
    }
  }

  void _fail(String message) {
    error = message;
    phase = UpdatePhase.error;
    progress = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
