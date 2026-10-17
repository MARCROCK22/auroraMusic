import 'dart:io';

/// Punto único para cerrar Aurora «de verdad» (audio, bandeja, instancia única).
///
/// El frente 2 (ventana) debe asignar [hardExitHandler] al cierre real de la
/// app. Mientras no esté conectado se usa `exit(0)`, que basta para que el
/// instalador pueda reemplazar los archivos.
Future<void> Function() hardExitHandler = () async => exit(0);

Future<void> requestHardExit() => hardExitHandler();
