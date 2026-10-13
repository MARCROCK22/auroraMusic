import 'dart:async';
import 'dart:io';

import 'package:aurora_music/audio/android_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// Official Media3 demo fixture, independent of YouTube and yt-dlp:
// https://github.com/androidx/media/blob/release/demos/cast/src/main/java/androidx/media3/demo/cast/DemoUtil.java
const _fixture =
    'https://storage.googleapis.com/exoplayer-test-media-1/mp3/Keys_To_The_Kingdom.mp3';

Future<void> _waitFor(AndroidMusicAudio audio, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready()) {
    if (audio.lastError != null) fail(audio.lastError!);
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Media3 did not settle: position=${audio.position}, '
        'duration=${audio.duration}, buffering=${audio.isBuffering}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(audio.lastError, isNull);
}

Future<int> _cacheBytes(Directory directory) async {
  if (!await directory.exists()) return 0;
  var bytes = 0;
  await for (final entry in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entry is File) bytes += await entry.length();
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android Media3 streams an official HTTPS fixture without an extractor',
    (tester) async {
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        final cache = Directory('${support.path}/yt-dlp-audio');
        final before = await _cacheBytes(cache);
        final audio = AndroidMusicAudio();
        var completions = 0;
        final completed = Completer<void>();
        final subscription = audio.completed.listen((_) {
          completions++;
          if (!completed.isCompleted) completed.complete();
        });
        try {
          await audio.initialize();
          audio.setVolume(0);
          await audio.load(const ResolvedAudio(input: _fixture));
          await audio.play();
          await _waitFor(
            audio,
            () =>
                audio.isPlaying && audio.position > const Duration(seconds: 1),
          );
          expect(audio.duration, greaterThan(const Duration(seconds: 10)));
          final state = await const MethodChannel(
            'aurora/audio',
          ).invokeMapMethod<String, dynamic>('state');
          expect(state!['audioNetworkRequests'], greaterThan(0));
          expect(state['audioNetworkBytes'], greaterThan(0));
          expect(state['audioNetworkBytes'], lessThan(8882875));
          expect(await _cacheBytes(cache), before);
          expect(completions, 0);

          await audio.pause();
          await _waitFor(audio, () => !audio.isPlaying);
          // Position events are sampled every 250 ms; let the paused sample arrive.
          await Future<void>.delayed(const Duration(milliseconds: 350));
          final pausedAt = audio.position;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          expect(
            (audio.position - pausedAt).inMilliseconds.abs(),
            lessThan(200),
          );
          await audio.seek(const Duration(seconds: 8));
          await _waitFor(
            audio,
            () =>
                (audio.position - const Duration(seconds: 8)).inMilliseconds
                    .abs() <
                500,
          );
          expect(audio.isPlaying, false);
          await audio.play();
          await _waitFor(
            audio,
            () =>
                audio.isPlaying && audio.position > const Duration(seconds: 9),
          );

          await audio.seek(audio.duration - const Duration(seconds: 2));
          await completed.future.timeout(const Duration(seconds: 10));
          await Future<void>.delayed(const Duration(milliseconds: 700));
          expect(audio.lastError, isNull);
          expect(completions, 1);
          expect(audio.isPlaying, false);
          expect(await _cacheBytes(cache), before);
          debugPrint(
            'ANDROID_PUBLIC_STREAM: HTTPS MP3 played; '
            'native requests=${state['audioNetworkRequests']}, '
            'native bytes=${state['audioNetworkBytes']}; '
            'pause/seek/resume/EOF passed; extractor cache delta=0',
          );
        } finally {
          try {
            await audio.stop();
          } on PlatformException {
            // Preserve the playback assertion if the service already failed.
          }
          await subscription.cancel();
          audio.dispose();
        }
      });
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('AURORA_LIVE_MEDIA3_TEST'),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
