import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/audio/routed_music_audio.dart';
import 'package:aurora_music/audio_web/web_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Resolves like InnerTubeSource: YouTube tracks go to the official page.
class _WatchSource extends FakeSource {
  @override
  Future<ResolvedAudio> resolve(Track track) async => ResolvedAudio(
    input: 'https://music.youtube.com/watch?v=${track.id.substring(3)}',
    duration: track.duration,
    engine: AudioEngine.web,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = Track(
    id: 'yt:6geljA2OZSY',
    title: 'Que Se Mueran',
    artist: 'Romeo Santos',
    duration: Duration(seconds: 150),
    pageUrl: 'https://music.youtube.com/watch?v=6geljA2OZSY',
  );
  late AppController controller;
  late ProviderContainer container;
  late FakeWebBridge bridge;
  late WebMusicAudio web;

  setUp(() async {
    bridge = FakeWebBridge();
    web = WebMusicAudio(bridge: bridge, pollInterval: const Duration(days: 1));
    controller = await createTestController(
      tracks: [track],
      audio: RoutedMusicAudio(native: FakeAudio(), web: web),
      source: _WatchSource(),
    );
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => controller)],
    );
  });
  tearDown(() async {
    container.dispose();
    await controller.closed;
    await controller.supportDirectory.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuroraApp()),
    );
    await tester.pump();
  }

  testWidgets('YouTube plays through the hidden page with Aurora on top', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.runAsync(() => controller.playTrack(track));
    await tester.pump();
    expect(controller.webPlayback, isTrue);
    expect(controller.audio.isPlaying, isTrue);
    expect(bridge.page.toString(), track.pageUrl);
    final engine = find.byKey(const ValueKey('engine'));
    expect(engine, findsOneWidget);
    expect(tester.getSize(engine), const Size(1, 1));
    expect(engine.hitTestable(), findsNothing);
    expect(find.text('Revisar sitio'), findsNothing);
    expect(find.text('Que Se Mueran'), findsWidgets);

    bridge.state = {...bridge.state, 'adPlaying': true, 'playing': true};
    await tester.runAsync(web.refresh);
    await tester.pump();
    expect(find.text('Anuncio · tu canción sigue después'), findsWidgets);
    expect(find.text('Que Se Mueran'), findsWidgets);
    expect(bridge.builds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('site consent shows a sheet only on request, then hides it', (
    tester,
  ) async {
    await pumpApp(tester);
    bridge.state = {'status': 'website'};
    await tester.runAsync(() => controller.playTrack(track));
    await tester.pump();
    expect(controller.error, contains('consentimiento'));
    final engine = find.byKey(const ValueKey('engine'));
    expect(tester.getSize(engine), const Size(1, 1));

    await tester.tap(find.text('Revisar sitio'));
    await tester.pump();
    expect(web.showingWebsite, isTrue);
    expect(tester.getSize(engine).width, greaterThan(1));
    expect(engine.hitTestable(), findsOneWidget);
    expect(bridge.builds, 1);

    bridge.state = {'status': 'ready', 'playing': false, 'duration': 150};
    await tester.tap(find.text('Listo'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(web.showingWebsite, isFalse);
    expect(tester.getSize(engine), const Size(1, 1));
    expect(bridge.builds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
