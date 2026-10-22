import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_eq_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(id: 's', title: 'Luz de luna', artist: 'Mare Sol');

void main() {
  testWidgets('pantalla Slush EQ + Cola se construye y el temporizador actúa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(
      () => createTestController(tracks: [_song], audio: FakeAudio()),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(app)));
    app.queue = [_song];
    await tester.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.light, Colors.blue),
        home: Scaffold(
          body: SlushEqQueue(controller: app, onNavigate: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('EQ'), findsOneWidget);
    expect(find.text('COLA'), findsWidgets);
    await tester.ensureVisible(find.text('30'));
    await tester.tap(find.text('30'));
    await tester.pump();
    expect(app.sleepRemaining, isNotNull);
    app.setSleepTimer(null);
  });
}
