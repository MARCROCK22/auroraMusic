import 'dart:typed_data';
import 'dart:ui' as ui;

const avatarMaxInputBytes = 8 * 1024 * 1024;
const avatarMaxOutputBytes = 24 * 1024;

class AvatarException implements Exception {
  const AvatarException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Recorta al centro a cuadrado y devuelve un PNG de 128px (96/64 si pesa mucho).
// shortcut: decodifica a tamaño completo antes de reducir; subir a decodificación
// escalada si aparecen fotos enormes.
Future<Uint8List> makeAvatarThumbnail(
  Uint8List source, {
  List<int> sizes = const [128, 96, 64],
  int maxBytes = avatarMaxOutputBytes,
}) async {
  if (source.length > avatarMaxInputBytes) {
    throw const AvatarException('La imagen pesa más de 8 MB.');
  }
  ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(source);
    image = (await codec.getNextFrame()).image;
    codec.dispose();
  } catch (_) {
    throw const AvatarException('El archivo no es una imagen válida.');
  }
  try {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final side = w < h ? w : h;
    final src = ui.Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
    for (final size in sizes) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        image,
        src,
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(size, size);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data == null) continue;
      final bytes = data.buffer.asUint8List();
      if (bytes.length <= maxBytes) return bytes;
    }
    throw const AvatarException('No se pudo reducir la imagen lo suficiente.');
  } finally {
    image.dispose();
  }
}
