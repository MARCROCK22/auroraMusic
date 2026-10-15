import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:zxing2/qrcode.dart';
import 'jam_models.dart';

const jamMaxImageBytes = 8 * 1024 * 1024;
const jamMaxImagePixels = 4 * 1024 * 1024;

Future<String> decodeJamQrImage(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > jamMaxImageBytes) {
    throw const JamException('La imagen QR es demasiado grande o está vacía.');
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > jamMaxImagePixels ||
        descriptor.width > 4096 ||
        descriptor.height > 4096) {
      throw const JamException(
        'La imagen QR supera el límite de cuatro megapíxeles.',
      );
    }
    codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    image = frame.image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) throw const JamException('No se pudo leer la imagen QR.');
    return decodeJamQrPixels(
      rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      image.width,
      image.height,
    );
  } on JamException {
    rethrow;
  } catch (_) {
    throw const JamException(
      'No se encontró un código QR legible en la imagen.',
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

String decodeJamQrPixels(Uint8List rgba, int width, int height) {
  if (width <= 0 ||
      height <= 0 ||
      width * height > jamMaxImagePixels ||
      rgba.length != width * height * 4) {
    throw const JamException('Dimensiones de QR inválidas.');
  }
  final pixels = Int32List(width * height);
  for (var i = 0; i < pixels.length; i++) {
    final offset = i * 4;
    // Composite transparent images against the QR's white background.
    final alpha = rgba[offset + 3];
    final red = (rgba[offset] * alpha + 255 * (255 - alpha)) ~/ 255;
    final green = (rgba[offset + 1] * alpha + 255 * (255 - alpha)) ~/ 255;
    final blue = (rgba[offset + 2] * alpha + 255 * (255 - alpha)) ~/ 255;
    pixels[i] = (red << 16) | (green << 8) | blue;
  }
  final bitmap = BinaryBitmap(
    HybridBinarizer(RGBLuminanceSource(width, height, pixels)),
  );
  try {
    return _read(bitmap);
  } catch (_) {
    // zxing2's detector misses ~2% of clean version 9 codes (bad alignment
    // pattern estimate); a clean exported QR still decodes without it.
    try {
      return _read(bitmap, pure: true);
    } catch (_) {
      throw const JamException(
        'No se encontró un código QR legible en la imagen.',
      );
    }
  }
}

String _read(BinaryBitmap bitmap, {bool pure = false}) => QRCodeReader()
    .decode(
      bitmap,
      hints: pure ? (DecodeHints()..put(DecodeHintType.pureBarcode)) : null,
    )
    .text;
