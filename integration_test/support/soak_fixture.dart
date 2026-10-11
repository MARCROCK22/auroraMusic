import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:path/path.dart' as path;

/// Generates a disk-streamable WAV using one second of memory at a time.
Future<File> createSoakFixture(int seconds) async {
  if (seconds < 1 || seconds > 21600) throw ArgumentError.value(seconds);
  const rate = 48000, channels = 2;
  final directory = await Directory.systemTemp.createTemp('aurora_soak_test_');
  final file = File(path.join(directory.path, 'continuous.wav'));
  final output = await file.open(mode: FileMode.write);
  final header = ByteData(44);
  final block = ByteData(rate * channels * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  final dataBytes = seconds * block.lengthInBytes;
  text(0, 'RIFF');
  header.setUint32(4, dataBytes + 36, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, rate, Endian.little);
  header.setUint32(28, rate * channels * 2, Endian.little);
  header.setUint16(32, channels * 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  text(36, 'data');
  header.setUint32(40, dataBytes, Endian.little);
  for (var frame = 0; frame < rate; frame++) {
    final sample = (math.sin(2 * math.pi * 375 * frame / rate) * 0.2 * 32767)
        .round();
    for (var channel = 0; channel < channels; channel++) {
      block.setInt16((frame * channels + channel) * 2, sample, Endian.little);
    }
  }
  try {
    await output.writeFrom(header.buffer.asUint8List());
    for (var index = 0; index < seconds; index++) {
      await output.writeFrom(block.buffer.asUint8List());
    }
  } finally {
    await output.close();
  }
  return file;
}
