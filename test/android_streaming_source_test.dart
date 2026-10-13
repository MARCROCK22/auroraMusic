import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:aurora_music/sources/youtube_request_policy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aurora/source');
  const track = Track(
    id: 'yt:abcdefghijk',
    title: 'Test',
    artist: 'Artist',
    pageUrl: 'https://youtu.be/abcdefghijk',
  );
  late YtDlpSource source;
  late DateTime now;
  late List<MethodCall> calls;
  late Map<String, Object> metadata;
  late Future<Object?> Function(MethodCall) handler;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 10, 12);
    calls = [];
    metadata = {
      'url':
          'https://audio.example/song.webm?expire=${now.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000}',
      'duration': 60,
      'http_headers': {'User-Agent': 'test', 'Cookie': 'private'},
    };
    handler = (_) async => jsonEncode(metadata);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return handler(call);
    });
    source = YtDlpSource(
      await SharedPreferences.getInstance(),
      androidOverride: true,
      now: () => now,
      requestPolicy: YouTubeRequestPolicy(
        now: () => now,
        requestSpacing: Duration.zero,
        sleep: (_) async {},
      ),
    );
  });
  tearDown(() {
    source.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'Android resolves metadata without downloading audio or starting a relay',
    () async {
      source.setExperimentalProgressivePlayback(true);
      final resolved = await source.resolve(track);
      expect(source.supportsExperimentalProgressivePlayback, isFalse);
      expect(resolved.input, startsWith('https://'));
      expect(resolved.duration, const Duration(minutes: 1));
      expect(resolved.headers, {'User-Agent': 'test'});
      expect(resolved.validateCompletion, isNull);
      expect(calls.map((c) => c.method), ['resolve']);
    },
  );
  test('concurrent resolutions coalesce and cached URLs expire', () async {
    final gate = Completer<Object?>();
    handler = (_) => gate.future;
    final first = source.resolve(track), second = source.resolve(track);
    await Future<void>.delayed(Duration.zero);
    gate.complete(jsonEncode(metadata));
    expect((await first).input, (await second).input);
    await source.resolve(track);
    expect(calls, hasLength(1));
    handler = (_) async => jsonEncode(metadata);
    now = now.add(const Duration(hours: 2));
    expect(source.isExpiredStream(track), isTrue);
    await expectLater(source.resolve(track), throwsStateError);
    expect(calls, hasLength(2));
  });
  test(
    'cancel aliases native resolution and rejects its stale result',
    () async {
      final gate = Completer<Object?>();
      handler = (call) async {
        if (call.method == 'cancel') {
          gate.complete(jsonEncode(metadata));
          return null;
        }
        return gate.future;
      };
      final check = expectLater(source.resolve(track), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      await source.cancel('resolve:abcdefghijk');
      await check;
      expect(calls.map((c) => c.method), ['resolve', 'cancel']);
    },
  );
  test('offline files do not call the resolver', () async {
    final dir = await Directory.systemTemp.createTemp('aurora-offline-');
    try {
      final file = await File('${dir.path}/song.mp3').writeAsBytes([1, 2]);
      expect(
        (await source.resolve(track.copyWith(localPath: file.path))).input,
        file.path,
      );
      expect(calls, isEmpty);
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'a cache TTL without URL expiry is not evidence for retrying 403',
    () async {
      metadata['url'] = 'https://audio.example/song.webm';
      await source.resolve(track);
      now = now.add(const Duration(minutes: 11));
      expect(source.isExpiredStream(track), false);
    },
  );
  test(
    'cancellation before native job registration makes no resolver call',
    () async {
      final result = source.resolve(track);
      final check = expectLater(result, throwsStateError);
      await source.cancel('resolve:abcdefghijk');
      await check;
      expect(calls, isEmpty);
    },
  );
  test('cooldown survives source recreation', () async {
    source.reportPlaybackFailure('HTTP 429');
    await Future<void>.delayed(Duration.zero);
    source.dispose();
    source = YtDlpSource(
      await SharedPreferences.getInstance(),
      androidOverride: true,
      now: () => now,
      requestPolicy: YouTubeRequestPolicy(
        now: () => now,
        requestSpacing: Duration.zero,
      ),
    );
    await expectLater(source.resolve(track), throwsStateError);
    expect(calls, isEmpty);
  });
  test(
    'cancelled explicit download never publishes its partial file',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'aurora-cancel-download-',
      );
      final started = Completer<void>(), finish = Completer<void>();
      handler = (call) async {
        if (call.method == 'cancel') {
          finish.complete();
          return null;
        }
        await File(
          '${call.arguments['directory']}/audio.mp3',
        ).writeAsBytes([1, 2]);
        started.complete();
        await finish.future;
        return null;
      };
      try {
        final destination = File('${dir.path}/song.mp3');
        final check = expectLater(
          source.download(track, destination, jobId: 'cancel-offline'),
          throwsStateError,
        );
        await started.future;
        await source.cancel('cancel-offline');
        await check;
        expect(await destination.exists(), false);
        expect(await dir.list().length, 0);
        expect(calls.map((c) => c.method), ['download', 'cancel']);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('invalid URLs and injected headers fail safely', () async {
    metadata['url'] = 'http://audio.example/song';
    await expectLater(source.resolve(track), throwsStateError);
    metadata['url'] = 'https://audio.example/song';
    metadata['http_headers'] = {'X-Test': 'bad\r\ninjected'};
    await expectLater(source.resolve(track), throwsStateError);
  });
  test('429 stops repeat calls until cooldown expires', () async {
    handler = (_) async => throw PlatformException(
      code: 'SOURCE_ERROR',
      message: 'HTTP 429 Too Many Requests',
    );
    await expectLater(source.resolve(track), throwsStateError);
    await expectLater(source.resolve(track), throwsStateError);
    expect(calls, hasLength(1));
    now = now.add(const Duration(seconds: 59));
    await expectLater(source.resolve(track), throwsStateError);
    expect(calls, hasLength(1));
    now = now.add(const Duration(seconds: 1));
    handler = (_) async => jsonEncode(metadata);
    await source.resolve(track);
    expect(calls, hasLength(2));
  });
  test('repeated and concurrent searches reuse metadata', () async {
    handler = (_) async => jsonEncode({
      'entries': [
        {'id': 'abcdefghijk', 'title': 'Test', 'uploader': 'Artist'},
      ],
    });
    await Future.wait([source.search('test'), source.search('test')]);
    await source.search('test');
    expect(calls.map((c) => c.method), ['search']);
    now = now.add(const Duration(minutes: 6));
    await source.search('test');
    expect(calls, hasLength(2));
  });
  test(
    'explicit download alone publishes a finished MP3 and removes staging',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'aurora-explicit-download-',
      );
      try {
        handler = (call) async {
          if (call.method == 'download') {
            await File(
              '${call.arguments['directory']}/audio.mp3',
            ).writeAsBytes([1, 2, 3]);
            return null;
          }
          throw StateError('Unexpected method');
        };
        final target = File('${dir.path}/song.mp3');
        final progress = <double>[];
        await source.download(
          track,
          target,
          jobId: 'offline-1',
          onProgress: progress.add,
        );
        expect(await target.readAsBytes(), [1, 2, 3]);
        expect(progress.last, 1);
        expect(calls.map((c) => c.method), ['download']);
        expect(await dir.list().length, 1);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
