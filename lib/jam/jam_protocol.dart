import 'dart:io';
import 'jam_models.dart';

/// Registro del protocolo `aurora://` en Windows (HKCU, sin administrador).
/// En Android lo cubre el intent-filter del AndroidManifest.
Future<void> registerAuroraProtocol({String? exe}) async {
  if (!Platform.isWindows) return;
  final path = exe ?? Platform.resolvedExecutable;
  const root = r'HKCU\Software\Classes\aurora';
  Future<void> reg(List<String> args) async {
    try {
      await Process.run('reg', ['add', ...args, '/f']);
    } catch (_) {}
  }

  await reg([root, '/ve', '/d', 'URL:Aurora Music']);
  await reg([root, '/v', 'URL Protocol', '/d', '']);
  await reg(['$root\\shell\\open\\command', '/ve', '/d', '"$path" "%1"']);
}

/// Punto de integración (frente 2, instancia única): al recibir el argumento
/// de línea de comandos `aurora://jam/CODIGO` (o el intent de Android), llamar
/// a `JamController.joinFromLink`. Devuelve el código o null si no es válido.
String? jamCodeFromLaunchArgument(String argument) =>
    argument.startsWith('aurora://') ? jamRemoteCodeFrom(argument) : null;
