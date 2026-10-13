import 'dart:async';
import 'dart:io';

import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aurora/source');
  late YtDlpSource source;
  late Future<Object?> Function(MethodCall) handler;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    handler = (_) async => null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) => handler(call),
    );
    source = YtDlpSource(
      await SharedPreferences.getInstance(),
      androidOverride: true,
    );
  });

  tearDown(() {
    source.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'accepts one public video and rejects Music, playlists and spoofed hosts',
    () {
      expect(
        YtDlpSource.validateVideoUrl(
          'https://www.youtube.com/watch?v=abcdefghijk',
        ).host,
        'www.youtube.com',
      );
      expect(
        YtDlpSource.validateVideoUrl('https://youtu.be/abcdefghijk').host,
        'youtu.be',
      );
      for (final url in [
        'https://music.youtube.com/watch?v=abcdefghijk',
        'https://www.youtube.com/watch?v=abcdefghijk&list=PL123',
        'https://www.youtube.com.evil.test/watch?v=abcdefghijk',
        'https://user@www.youtube.com/watch?v=abcdefghijk',
        'https://www.youtube.com/watch?v=short',
      ]) {
        expect(
          () => YtDlpSource.validateVideoUrl(url),
          throwsArgumentError,
          reason: url,
        );
      }
    },
  );

  test(
    'stages a real video extension and publishes only after completion',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'aurora-video-test-',
      );
      handler = (call) async {
        if (call.method == 'downloadVideo') {
          await File(
            '${call.arguments['directory']}/video.mp4',
          ).writeAsBytes([1, 2, 3]);
        }
        return null;
      };
      try {
        await source.downloadVideo(
          Uri.parse('https://youtu.be/abcdefghijk'),
          File('${parent.path}/abcdefghijk.video'),
          jobId: 'video-1',
        );
        expect(await File('${parent.path}/abcdefghijk.mp4').readAsBytes(), [
          1,
          2,
          3,
        ]);
        expect(await parent.list().length, 1);
      } finally {
        await parent.delete(recursive: true);
      }
    },
  );

  test(
    'cancelled video download leaves no published or staging files',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'aurora-video-cancel-',
      );
      final started = Completer<void>();
      final finish = Completer<void>();
      handler = (call) async {
        if (call.method == 'cancel') return null;
        await File(
          '${call.arguments['directory']}/video.mp4',
        ).writeAsBytes([1, 2, 3]);
        started.complete();
        await finish.future;
        return null;
      };
      try {
        final attempt = expectLater(
          source.downloadVideo(
            Uri.parse('https://youtu.be/abcdefghijk'),
            File('${parent.path}/abcdefghijk.video'),
            jobId: 'video-cancel',
          ),
          throwsStateError,
        );
        await started.future;
        await source.cancel('video-cancel');
        finish.complete();
        await attempt;
        expect(await parent.list().length, 0);
      } finally {
        if (!finish.isCompleted) finish.complete();
        await parent.delete(recursive: true);
      }
    },
  );
}
