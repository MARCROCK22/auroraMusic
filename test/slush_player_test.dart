import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('Slush vinilo se pinta en escritorio y móvil sin errores', (
    tester,
  ) async {
    final controller = (await tester.runAsync(createTestController))!;
    try {
      for (final size in [const Size(1280, 800), const Size(390, 800)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: slushTheme(Brightness.light, const Color(0xffe86927)),
            home: Scaffold(
              body: VinylPlayer(controller: controller, onSection: (_) {}),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('VINILO'), findsOneWidget);
        expect(find.byKey(const ValueKey('cassette-toggle')), findsOneWidget);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => closeTestController(controller));
      await tester.binding.setSurfaceSize(null);
    }
  });
}
