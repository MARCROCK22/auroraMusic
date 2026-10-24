import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/ui/brand/aurora_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Regenera assets/brand/*.png (los lee flutter_launcher_icons).
Future<void> _png(String path, int px, CustomPainter p) async {
  final rec = ui.PictureRecorder();
  p.paint(Canvas(rec), Size.square(px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  testWidgets('exporta el logo', (tester) async {
    await tester.runAsync(() async {
      await _png('assets/brand/icon.png', 1024, const AuroraLogoPainter());
      await _png(
        'assets/brand/icon_foreground.png',
        1024,
        const AuroraLogoPainter(background: false, markScale: .62),
      );
      await _png(
        'assets/brand/discord_large.png',
        512,
        const AuroraLogoPainter(),
      );
    });
    expect(File('assets/brand/icon.png').lengthSync(), greaterThan(1000));
  });
}
