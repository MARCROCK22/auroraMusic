import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import 'models.dart';

/// Preferencia «Mostrar en Duvet lo que escuchas»: activada salvo que se apague.
abstract final class DuvetPresenceSetting {
  static const key = 'duvetPresence';
  static bool read(SharedPreferences p) => p.getBool(key) ?? true;
}

/// Lo que suena, como actividad «Escuchando» de Duvet: la app de escritorio la
/// recibe por su tubería IPC y la muestra en el perfil del usuario. Solo
/// Windows. Escribe solo cuando cambia lo que se ve (otra pista, pausa o un
/// salto) y cada 30 s mientras suena, lo que la vuelve a mostrar si Duvet se
/// abre o se reinicia después; sin Duvet abierto no hace nada más.
class DuvetPresence {
  DuvetPresence(
    this.controller, {
    DuvetPipe? pipe,
    @visibleForTesting bool? supported,
  }) : _pipe = pipe ?? DuvetPipe(),
       _supported = supported ?? Platform.isWindows;
  final AppController controller;
  final DuvetPipe _pipe;
  final bool _supported;
  Timer? _heartbeat;

  /// La pista y el inicio (ms) que Duvet ya tiene.
  ({String id, int start})? _sent;

  bool get enabled => DuvetPresenceSetting.read(controller.preferences);

  Future<void> setEnabled(bool value) async {
    await controller.preferences.setBool(DuvetPresenceSetting.key, value);
    _push();
  }

  // El controlador no avisa de un salto; el motor de audio, sí (y de cada
  // avance, que no cambia el inicio y no se reenvía).
  void start() {
    if (!_supported) return;
    controller.addListener(_push);
    controller.audio.addListener(_push);
    _push();
  }

  void dispose() {
    if (!_supported) return;
    controller.removeListener(_push);
    controller.audio.removeListener(_push);
    _clear();
  }

  void _push({bool force = false}) {
    final track = controller.nowTrack;
    final audio = controller.audio;
    if (!enabled || track == null || !audio.isPlaying) {
      _clear();
      return;
    }
    final start =
        DateTime.now().millisecondsSinceEpoch - audio.position.inMilliseconds;
    final sent = _sent;
    // La posición avanza con el reloj: solo un salto mueve el inicio.
    if (!force &&
        sent != null &&
        sent.id == track.id &&
        (sent.start - start).abs() < 2000) {
      return;
    }
    final duration = audio.duration > Duration.zero
        ? audio.duration
        : track.duration;
    // Cuenta aunque falle: sin Duvet abierto, el latido lo reintenta en vez de
    // cada avance.
    _sent = (id: track.id, start: start);
    _pipe.send({
      'type': 'SET_ACTIVITY',
      'data': duvetActivity(track, start: start, duration: duration),
    });
    _heartbeat ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _push(force: true),
    );
  }

  // Cerrar la tubería borra la actividad en Duvet.
  void _clear() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _sent = null;
    _pipe.close();
  }
}

/// La actividad de [track] para Duvet: «Escuchando Aurora Music», el título, el
/// artista, cuándo empezó y acaba la canción, y la portada si es pública (una
/// local, como la del proxy, no la vería nadie más).
Map<String, Object?> duvetActivity(
  Track track, {
  required int start,
  required Duration duration,
}) => {
  'type': 2,
  'name': 'Aurora Music',
  'details': track.title,
  'state': track.artist,
  'timestamps': {
    'start': start,
    if (duration > Duration.zero) 'end': start + duration.inMilliseconds,
  },
  if (Uri.tryParse(track.artworkUrl ?? '') case final art?
      when art.scheme == 'https')
    'assets': {
      'large_image': track.artworkUrl,
      'large_text': track.album ?? track.title,
    },
};

/// La tubería IPC de la app de escritorio de Duvet, por FFI: el `File` de Dart
/// no abre tuberías con nombre en Windows (convierte la ruta en UNC). Un mensaje
/// JSON por línea; cerrarla borra la actividad.
class DuvetPipe {
  static const path = r'\\.\pipe\duvet-ipc';
  int? _handle;

  /// Abre la tubería si hace falta y escribe [message]: false si Duvet no está
  /// abierto o la cerró.
  bool send(Map<String, Object?> message) {
    final handle = _handle ?? _open();
    if (handle == null) return false;
    _handle = handle;
    final bytes = utf8.encode('${jsonEncode(message)}\n');
    final buffer = calloc<Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    final written = calloc<Uint32>();
    try {
      if (_writeFile(handle, buffer, bytes.length, written, nullptr) != 0 &&
          written.value == bytes.length) {
        return true;
      }
    } finally {
      calloc
        ..free(buffer)
        ..free(written);
    }
    close();
    return false;
  }

  void close() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _closeHandle(handle);
  }

  static int? _open() {
    final name = path.toNativeUtf16();
    try {
      final handle = _createFile(
        name,
        _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      return handle == _invalidHandle ? null : handle;
    } finally {
      calloc.free(name);
    }
  }
}

const _genericWrite = 0x40000000;
const _openExisting = 3;
const _invalidHandle = -1;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _createFile = _kernel32
    .lookupFunction<
      IntPtr Function(
        Pointer<Utf16>,
        Uint32,
        Uint32,
        Pointer<Void>,
        Uint32,
        Uint32,
        IntPtr,
      ),
      int Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int, int)
    >('CreateFileW');
final _writeFile = _kernel32
    .lookupFunction<
      Int32 Function(
        IntPtr,
        Pointer<Uint8>,
        Uint32,
        Pointer<Uint32>,
        Pointer<Void>,
      ),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Void>)
    >('WriteFile');
final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
