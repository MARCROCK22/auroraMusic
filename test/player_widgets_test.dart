import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/ui/lyrics_panel.dart';
import 'package:aurora_music/ui/queue_panel.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _QuietLyrics extends LyricsService {
  @override
  Future<LyricsResult> load(Track track, Directory supportDirectory) async =>
      const LyricsResult(LyricsKind.notFound);
}

void main() {
  const previous = Track(
    id: 'previous',
    title: 'Earlier record',
    artist: 'Artist',
    pageUrl: 'https://example.test/previous',
  );
  const current = Track(
    id: 'current',
    title: 'Current record',
    artist: 'Artist',
    pageUrl: 'https://example.test/current',
  );
  const duplicateA = Track(
    id: 'duplicate',
    title: 'Duplicate one',
    artist: 'Artist',
    pageUrl: 'https://example.test/duplicate-one',
  );
  const duplicateB = Track(
    id: 'duplicate',
    title: 'Duplicate two',
    artist: 'Artist',
    pageUrl: 'https://example.test/duplicate-two',
  );

  group('player widgets', () {
    late AppController controller;
    late FakeAudio audio;
    late _QuietLyrics lyrics;

    setUp(() async {
      audio = FakeAudio();
      controller = await createTestController(audio: audio);
      controller.queue = [previous, current, duplicateA, duplicateB];
      controller.queueIndex = 1;
      await controller.playQueueAt(1);
      await audio.pause();
      expect(controller.error, isNull);
      expect(audio.loaded, isNotNull);
      lyrics = _QuietLyrics();
    });

    tearDown(() async {
      await closeTestController(controller);
      lyrics.dispose();
    });

    Future<void> mount(
      WidgetTester tester,
      Widget screen, {
      Size size = const Size(320, 600),
      double scale = 1,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      );
    }

    testWidgets('slider seeks the real playback backend', (tester) async {
      await mount(tester, VinylPlayer(controller: controller));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
      slider.onChanged!(90000);
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(audio.position, const Duration(seconds: 90));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'vinyl stays safe while paused by reduced motion and background',
      (tester) async {
        await mount(tester, VinylPlayer(controller: controller));
        await audio.play();
        controller.reducedMotion = true;
        controller.notifyListeners();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('queue handles duplicate IDs on narrow enlarged text', (
      tester,
    ) async {
      await mount(tester, QueuePanel(controller: controller), scale: 2);
      expect(find.text('Current record'), findsOneWidget);
      expect(find.text('Duplicate one'), findsOneWidget);
      expect(find.text('Duplicate two'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('queue fits a short desktop viewport', (tester) async {
      await mount(
        tester,
        QueuePanel(controller: controller),
        size: const Size(900, 600),
      );
      expect(find.text('Current record'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lyrics layout fits narrow enlarged text', (tester) async {
      await mount(
        tester,
        LyricsPanel(controller: controller, service: lyrics),
        scale: 2,
      );
      await tester.pump();
      expect(find.text('Current record\nArtist'), findsOneWidget);
      expect(find.text('No se encontraron letras.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
