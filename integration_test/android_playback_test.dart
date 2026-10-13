import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aurora_music/audio/android_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Native playback did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Uint8List silentWav() {
  const sampleRate = 8000, seconds = 5;
  final bytes = Uint8List(44 + sampleRate * seconds * 2);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) =>
      bytes.setRange(offset, offset + value.length, value.codeUnits);
  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, bytes.length - 44, Endian.little);
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android Media3 local playback and Flutter controls', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    await tester.runAsync(() async {
      final directory = await getTemporaryDirectory();
      final file = await File(
        '${directory.path}/aurora-media3-test.wav',
      ).writeAsBytes(silentWav());
      final audio = AndroidMusicAudio();
      try {
        await audio.initialize();
        await audio.load(
          ResolvedAudio(input: file.path, duration: const Duration(seconds: 5)),
        );
        await audio.play();
        await waitUntil(
          () =>
              audio.position > const Duration(milliseconds: 300) ||
              audio.lastError != null,
        );
        expect(audio.lastError, isNull);
        expect(audio.isPlaying, isTrue);
        await audio.pause();
        expect(audio.isPlaying, isFalse);
        await audio.seek(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(audio.position.inMilliseconds, inInclusiveRange(1900, 2300));
        final state = await const MethodChannel(
          'aurora/audio',
        ).invokeMapMethod<String, dynamic>('state');
        expect(state!['audioNetworkBytes'], 0);
        await audio.play();
        await waitUntil(() => audio.isPlaying);
        await audio.stop();
        expect(audio.isPlaying, isFalse);
        debugPrint(
          'ANDROID_LOCAL: Media3 play/pause/seek/stop passed; network bytes=0',
        );
      } finally {
        audio.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await file.delete();
      }
    });
  });
  testWidgets('Android reuses cached audio for an explicit offline download', (
    tester,
  ) async {
    if (!Platform.isAndroid) return;
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final cache = await Directory(
        '${support.path}/yt-dlp-audio',
      ).create(recursive: true);
      final cached = File('${cache.path}/aaaaaaaaaaa.audio');
      expect(await cached.exists(), false);
      await cached.writeAsBytes(silentWav());
      final destination = File('${support.path}/aurora-offline-test.mp3');
      final source = YtDlpSource(await SharedPreferences.getInstance());
      final audio = AndroidMusicAudio();
      try {
        await source.initializeUpdates(
          isPlaybackActive: () => true,
          onStatusChanged: () {},
        );
        const track = Track(
          id: 'yt:aaaaaaaaaaa',
          title: 'Local generated audio',
          artist: 'Test',
          pageUrl: 'https://youtu.be/aaaaaaaaaaa',
          duration: Duration(seconds: 5),
        );
        await source.download(track, destination, jobId: 'offline-cache-test');
        expect(await destination.length(), greaterThan(0));
        expect(source.requestsStarted, 0);
        final local = await source.resolve(
          track.copyWith(localPath: destination.path),
        );
        await audio.initialize();
        await audio.load(local);
        await audio.play();
        await waitUntil(
          () =>
              audio.position > const Duration(milliseconds: 300) ||
              audio.lastError != null,
        );
        expect(audio.lastError, isNull);
        expect(audio.isPlaying, true);
        await audio.stop();
        debugPrint(
          'ANDROID_OFFLINE: cached WAV converted by bundled FFmpeg and played locally; upstream invocations=0',
        );
      } finally {
        audio.dispose();
        source.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (await destination.exists()) await destination.delete();
        await cached.delete();
      }
    });
  });
  testWidgets(
    'Android nightly checks official integrity and persists daily cadence',
    (tester) async {
      await tester.runAsync(() async {
        const channel = MethodChannel('aurora/source');
        final result =
            jsonDecode(
                  (await channel.invokeMethod<String>('updateNightly', {}))!,
                )
                as Map;
        expect(result['status'], anyOf('updated', 'upToDate', 'throttled'));
        final version = await channel.invokeMethod<String>('diagnose', {});
        expect(version, startsWith(result['version'] as String));
        final second =
            jsonDecode(
                  (await channel.invokeMethod<String>('updateNightly', {}))!,
                )
                as Map;
        expect(second['status'], 'throttled');
        debugPrint(
          'ANDROID_NIGHTLY: ${result['status']}; version=${result['version']}; repeated check throttled',
        );
      });
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('AURORA_LIVE_UPDATE_TEST'),
  );
  testWidgets(
    'Android yt-dlp resolves on-device and Media3 streams without a cache download',
    (tester) async {
      if (!Platform.isAndroid) return;
      await tester.runAsync(() async {
        final source = YtDlpSource(await SharedPreferences.getInstance());
        final audio = AndroidMusicAudio();
        final support = await getApplicationSupportDirectory();
        final cache = Directory('${support.path}/yt-dlp-audio');
        Future<int> cacheBytes() async {
          if (!await cache.exists()) return 0;
          var bytes = 0;
          await for (final entry in cache.list(
            recursive: true,
            followLinks: false,
          )) {
            if (entry is File) bytes += await entry.length();
          }
          return bytes;
        }

        try {
          final version = await source.diagnose();
          debugPrint('ANDROID_RESOLVER: $version');
          final before = await cacheBytes();
          const target = String.fromEnvironment(
            'AURORA_YOUTUBE_SMOKE_URL',
            defaultValue: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
          );
          final uri = Uri.parse(target);
          final id = uri.host == 'youtu.be'
              ? uri.pathSegments.first
              : uri.queryParameters['v']!;
          final track = Track(
            id: 'yt:$id',
            title: 'Public extractor smoke fixture',
            artist: 'Test',
            pageUrl: target,
          );
          final resolved = await source.resolve(track);
          expect(Uri.parse(resolved.input).scheme, 'https');
          expect(source.requestsStarted, 1);
          expect(await cacheBytes(), before);
          debugPrint(
            'ANDROID_RESOLVER: HTTPS resolution passed; extractor invocations=1; cached audio delta=0',
          );
          await audio.initialize();
          await audio.load(resolved);
          await audio.play();
          await waitUntil(
            () =>
                audio.position > const Duration(seconds: 2) ||
                audio.lastError != null,
          );
          expect(audio.lastError, isNull);
          final state = await const MethodChannel(
            'aurora/audio',
          ).invokeMapMethod<String, dynamic>('state');
          expect(state!['audioNetworkBytes'] as int, greaterThan(0));
          expect(await cacheBytes(), before);
          debugPrint(
            'ANDROID_STREAM: requests=${state['audioNetworkRequests']}; bytes=${state['audioNetworkBytes']}; cached audio delta=0',
          );
        } finally {
          try {
            await audio.stop();
          } on PlatformException {
            /* Cleanup must not replace the resolver failure. */
          }
          audio.dispose();
          source.dispose();
        }
      });
    },
    skip: !const bool.fromEnvironment('AURORA_LIVE_YOUTUBE_TEST'),
  );
}
