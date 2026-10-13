// Opt-in, manual device observation. Never supplies credentials or starts media.
// flutter test integration_test/youtube_music_webview_test.dart -d <device>
//   --dart-define=RUN_YOUTUBE_MUSIC_WEBVIEW=true
//   --dart-define=YOUTUBE_MUSIC_OBSERVATION_SECONDS=180
// During the observation window, use the official page to start media manually,
// listen in foreground, switch apps, turn the screen off, then return. Note audio,
// official account/region restrictions and interruptions in your device report.
// Lifecycle events prove app visibility only; they cannot prove audible playback.
import 'package:aurora_music/youtube_music/youtube_music_page.dart';
import 'package:aurora_music/youtube_music/youtube_music_platform.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _LifecycleObservation with WidgetsBindingObserver {
  final events = <Map<String, Object>>[];
  final started = DateTime.now();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    events.add({
      'state': state.name,
      'elapsedSeconds': DateTime.now().difference(started).inSeconds,
    });
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const enabled = bool.fromEnvironment('RUN_YOUTUBE_MUSIC_WEBVIEW');
  const observationSeconds = int.fromEnvironment(
    'YOUTUBE_MUSIC_OBSERVATION_SECONDS',
    defaultValue: 180,
  );

  testWidgets('official visible WebView and manual lifecycle observation', (
    tester,
  ) async {
    final platform = NativeYouTubeMusicPlatform();
    final observation = _LifecycleObservation();
    WidgetsBinding.instance.addObserver(observation);
    addTearDown(() => WidgetsBinding.instance.removeObserver(observation));
    await tester.pumpWidget(
      MaterialApp(home: YouTubeMusicPage(platform: platform)),
    );

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while ((!platform.ready || platform.loading) &&
        platform.error == null &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    }
    expect(
      platform.ready,
      isTrue,
      reason:
          'Native runtime must initialize. Inspect visible error if unavailable.',
    );
    expect(
      platform.loading,
      isFalse,
      reason: 'Official page must finish loading within 60 seconds.',
    );
    expect(
      platform.error,
      isNull,
      reason: 'A network failure is a genuine device test failure.',
    );
    debugPrint(
      'OBSERVE YOUTUBE MUSIC: manually start media in the official page; listen in foreground, background and screen-off, then return. No automatic playback or sign-in is performed.',
    );
    await tester.runAsync(
      () => Future<void>.delayed(
        Duration(seconds: observationSeconds.clamp(1, 900)),
      ),
    );
    await tester.pump();
    binding.reportData = {
      'platform': defaultTargetPlatform.name,
      'observationSeconds': observationSeconds.clamp(1, 900),
      'lifecycleEvents': observation.events,
      'officialPageErrorAfterObservation': platform.error,
      'audiblePlayback':
          'Requires human observation; not inferred from lifecycle events',
      'automatedMediaCommands': false,
      'credentialsProvided': false,
      'adFilterStatus': platform.adBlocker.status.name,
      'adFilterEnabled': platform.adBlocker.enabled,
      'videoAdRemoval': 'Not inferred from a successful load or filter status',
    };
    expect(find.byType(YouTubeMusicPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, skip: !enabled);
}
