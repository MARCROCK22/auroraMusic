import 'dart:async';
import 'dart:io';

/// Extremo de una conexión de Jam: un WebSocket de la LAN o un par virtual
/// montado sobre un canal remoto. JamService solo conoce esta interfaz.
abstract class JamPeer {
  bool get isOpen;

  /// Por qué se cerró (host, network, silence, banned...); null en la LAN.
  String? get closeReason;

  /// Devuelve false si el mensaje no pudo salir.
  bool add(String data);
  Future<void> close([int? code]);
  StreamSubscription<Object?> listen(
    void Function(Object? message) onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  });
}

class WebSocketPeer implements JamPeer {
  WebSocketPeer(this.socket);
  final WebSocket socket;
  @override
  String? get closeReason => null;
  @override
  bool get isOpen => socket.readyState == WebSocket.open;
  @override
  bool add(String data) {
    if (!isOpen) return false;
    try {
      socket.add(data);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> close([int? code]) => socket.close(code);
  @override
  StreamSubscription<Object?> listen(
    void Function(Object? message) onData, {
    void Function()? onDone,
    void Function(Object error)? onError,
  }) => socket.listen(
    onData,
    onDone: onDone,
    onError: onError == null ? null : (Object e) => onError(e),
    cancelOnError: true,
  );
}
