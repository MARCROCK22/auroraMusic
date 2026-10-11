import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/main.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('application initializes native database, audio and UI', (
    tester,
  ) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundaryKey, child: const AuroraBootstrap()),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (find.byType(AuroraShell).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AuroraShell), findsOneWidget);
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(AuroraShell)),
    ).read(controllerProvider);
    expect(controller.ready, isTrue, reason: controller.error);
    expect(controller.error, isNull);
    if (Platform.isWindows) {
      expect(controller.source.toolDirectory, isNotNull);
      await tester.runAsync(controller.runDiagnostics);
      expect(controller.diagnostics, contains('yt-dlp'));
    }
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 900));
    if (Platform.isWindows) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await tester.runAsync(() async {
        final directory = Directory('build/screenshots');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/aurora-desktop.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
