import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hard_exit.dart';
import 'update_service.dart';

enum UpdatePhase { idle, checking, available, downloading, installing, error }

/// Resultado de la última actualización, evaluado al arrancar.
class UpdateOutcome {
  const UpdateOutcome.updated(this.version)
    : failed = false,
      logPath = null,
      installerPath = null;
  const UpdateOutcome.failed(this.version, this.logPath, this.installerPath)
    : failed = true;
  final bool failed;
  final String version;
  final String? logPath;
  final String? installerPath;
}

/// Lanza un proceso sin esperarlo (inyectable para pruebas).
typedef ProcessLauncher = Future<void> Function(String exe, List<String> args);

Future<void> _launchDetached(String exe, List<String> args) =>
    Process.start(exe, args, mode: ProcessStartMode.detached);

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
  UpdateController(
    this.prefs, {
    UpdateService? service,
    ProcessLauncher? launcher,
    Future<void> Function()? hardExit,
    void Function(int)? exitProcess,
    Future<Directory> Function()? dirProvider,
    bool? windows,
  }) : _launch = launcher ?? _launchDetached,
       _hardExit = hardExit ?? requestHardExit,
       _exit = exitProcess ?? exit,
       _dirProvider = dirProvider,
       _windows = windows ?? Platform.isWindows,
       _service =
           service ??
           UpdateService(
             transport: HttpUpdateTransport(),
             store: PrefsUpdateStore(prefs),
           );

  static const _channel = MethodChannel('aurora/updater');
  static const _interval = Duration(hours: 6);

  final SharedPreferences prefs;
  final UpdateService _service;
  final ProcessLauncher _launch;
  final Future<void> Function() _hardExit;
  final void Function(int) _exit;
  final Future<Directory> Function()? _dirProvider;
  final bool _windows;
  Timer? _timer;
  SemVer? _current;
  List<String> _abis = const [];

  UpdatePhase phase = UpdatePhase.idle;
  ReleaseInfo? release;
  double? progress; // 0..1, null si se desconoce el total
  String? error;
  String? info; // «Estás al día», etc.
  bool dismissed = false; // «Más tarde»: oculto hasta reiniciar
  UpdateOutcome? outcome; // éxito/fracaso de la actualización anterior

  bool get supported => _windows || Platform.isAndroid;
  String get currentVersion => _current?.toString() ?? '';
  bool get autoCheck => prefs.getBool('updateAuto') ?? true;
  bool get beta => prefs.getBool('updateBeta') ?? false;
  bool get showBanner =>
      release != null &&
      !dismissed &&
      (phase == UpdatePhase.available ||
          phase == UpdatePhase.downloading ||
          phase == UpdatePhase.installing ||
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
      await _verifyPending(dir);
    } on Object {
      return; // sin versión no se puede comparar
    }
    // Revisa cada hora si ya pasaron 6 h: cubre la app viva en la bandeja.
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _auto());
    unawaited(_auto());
  }

  /// Compara la marca `pendingUpdate` con la versión instalada. Si coincide,
  /// limpia instaladores viejos; si no, conserva todo para reintentar a mano.
  Future<void> _verifyPending(Directory dir) async {
    final cur = _current;
    if (cur == null) return;
    final target = prefs.getString('pendingUpdate');
    final log = File('${dir.path}${Platform.pathSeparator}install.log');
    if (target == null) {
      UpdateService.cleanup(dir, cur);
      return;
    }
    await prefs.remove('pendingUpdate');
    final want = SemVer.tryParse(target);
    if (want != null && cur.compareTo(want) >= 0) {
      outcome = UpdateOutcome.updated('$cur');
      UpdateService.cleanup(dir, cur);
      try {
        if (log.existsSync()) log.deleteSync();
      } on FileSystemException {
        // Se borrará en la próxima actualización correcta.
      }
    } else {
      String? installer;
      if (dir.existsSync()) {
        for (final f in dir.listSync().whereType<File>()) {
          if (f.path.toLowerCase().endsWith('.exe')) installer = f.path;
        }
      }
      outcome = UpdateOutcome.failed(target, log.path, installer);
    }
    notifyListeners();
  }

  void dismissOutcome() {
    outcome = null;
    notifyListeners();
  }

  /// «Abrir el instalador»: lo selecciona en el Explorador (o abre la carpeta).
  Future<void> openInstaller() async {
    final o = outcome;
    if (o == null || !_windows) return;
    final path = o.installerPath;
    if (path != null) {
      await _launch('explorer.exe', ['/select,$path']);
    } else if (o.logPath != null) {
      await _launch('explorer.exe', [File(o.logPath!).parent.path]);
    }
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

  Future<Directory> _dir() async =>
      _dirProvider != null ? await _dirProvider() : await _defaultDir();

  Future<Directory> _defaultDir() async => Directory(
    '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}aurora_update',
  );

  /// Descarga, verifica e instala. Si algo falla queda en `error` y el botón
  /// «Actualizar ahora» permite reintentar (la descarga se reanuda).
  Future<void> install() async {
    final r = release;
    if (r == null || phase == UpdatePhase.downloading) return;
    final asset = r.assetFor(windows: _windows, abis: _abis);
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
      if (_windows) {
        // El instalador (Inno Setup) cierra, reemplaza y relanza Aurora.
        // /SILENT (no /VERYSILENT) deja una ventanita de progreso; el log
        // permite diagnosticar si no se completa.
        await prefs.setString('pendingUpdate', '${r.version}');
        phase = UpdatePhase.installing;
        progress = null;
        notifyListeners();
        await _launch(file.path, [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/FORCECLOSEAPPLICATIONS',
          '/LOG=${file.parent.path}${Platform.pathSeparator}install.log',
        ]);
        // Red de seguridad en Dart; el runner nativo tiene la suya (3 s).
        await _hardExit().timeout(
          const Duration(seconds: 3),
          onTimeout: () => _exit(0),
        );
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
    unawaited(prefs.remove('pendingUpdate'));
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
