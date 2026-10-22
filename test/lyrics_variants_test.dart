import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/lyrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _track = Track(
  id: 'v-track',
  artist: 'Artist',
  title: 'Song',
  duration: Duration(seconds: 180),
  pageUrl: 'https://example.test/v',
);

class _Lyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration(seconds: 1), 'uno'),
      LyricLine(Duration(seconds: 2), 'dos'),
      LyricLine(Duration(seconds: 3), 'tres'),
      LyricLine(Duration(seconds: 4), 'cuatro'),
      LyricLine(Duration(seconds: 5), 'cinco'),
    ],
  );
}

void main() {
  for (final name in ['modern', 'brasa']) {
    testWidgets('letras $name: activa, vecinas y salto', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final audio = FakeAudio();
      final controller = (await tester.runAsync(
        () => createTestController(audio: audio),
      ))!;
      addTearDown(() => tester.runAsync(() => closeTestController(controller)));
      final theme = name == 'modern'
          ? modernTheme(Brightness.dark, Colors.teal)
          : brasaTheme(Brightness.dark, Colors.teal);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: LyricsPanel(controller: controller, service: _Lyrics()),
          ),
        ),
      );
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await tester.runAsync(controller.togglePlayback);
      await audio.seek(const Duration(milliseconds: 2500));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('dos'), findsOneWidget);
      expect(find.text('tres'), findsOneWidget);
      if (name == 'brasa') {
        expect(find.text('uno'), findsOneWidget);
        expect(find.text('cuatro'), findsNothing);
        expect(find.text('cinco'), findsNothing);
        expect(find.text('ESTUDIO DE LETRAS'), findsNothing);
      }
      await tester.tap(find.text('tres'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(audio.position, const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
