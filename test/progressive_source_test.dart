import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('aurora/source');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const track = Track(
    id: 'yt:abcdefghijk',
    title: 'Test',
    artist: 'Artist',
    pageUrl: 'https://youtu.be/abcdefghijk',
    duration: Duration(minutes: 1),
  );
  final audio = List<int>.filled(8192, 0)..setAll(0, [0x1a, 0x45, 0xdf, 0xa3]);
  late Directory support;
  late YtDlpSource source;
  late HttpClient client;
  late Completer<void> download;
  late Completer<void> validation;
  late Completer<void> validationStarted;
  late List<String> calls;
  late HttpOverrides? httpOverride;
  late Map<String, Object> metadata;
  late int durationMs;
  late File? staging;

  Future<void> waitFor(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('Operation did not settle');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'aurora-progressive-source-',
    );
    SharedPreferences.setMockInitialValues({});
    source = YtDlpSource(
      await SharedPreferences.getInstance(),
      androidOverride: true,
    );
    httpOverride = HttpOverrides.current;
    HttpOverrides.global = null;
    client = HttpClient();
    download = Completer<void>();
    validation = Completer<void>();
    validationStarted = Completer<void>();
    calls = [];
    staging = null;
    durationMs = 60000;
    metadata = {
      'format_id': '251',
      'ext': 'webm',
      'protocol': 'https',
      'duration': 60,
      'filesize': audio.length,
    };
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(paths, (_) async => support.path)
      ..setMockMethodCallHandler(native, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'progressiveInfo':
            return jsonEncode(metadata);
          case 'progressiveAudio':
            expect(call.arguments['formatId'], '251');
            final file = File('${call.arguments['directory']}/audio.webm');
            staging = file;
            await file.writeAsBytes(audio.sublist(0, 4096));
            await download.future;
            await file.writeAsBytes(audio.sublist(4096), mode: FileMode.append);
            return '$durationMs';
          case 'probeAudio':
            return '$durationMs';
          case 'validateProgressiveAudio':
            expect(
              await File(call.arguments['path'] as String).length(),
              audio.length,
            );
            validationStarted.complete();
            await validation.future;
            return 'ok';
          case 'cacheAudio':
            await File(
              '${call.arguments['directory']}/audio.webm',
            ).writeAsBytes(audio);
            return '$durationMs';
          case 'cancel':
            if (!download.isCompleted) {
              download.completeError(
                PlatformException(
                  code: 'CANCELLED',
                  message: 'Descarga cancelada',
                ),
              );
            }
            if (validationStarted.isCompleted && !validation.isCompleted) {
              validation.completeError(PlatformException(code: 'CANCELLED'));
            }
            return null;
          default:
            throw StateError('Unexpected native method ${call.method}');
        }
      });
  });

  tearDown(() async {
    client.close(force: true);
    source.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    binding.defaultBinaryMessenger
      ..setMockMethodCallHandler(paths, null)
      ..setMockMethodCallHandler(native, null);
    HttpOverrides.global = httpOverride;
    await support.delete(recursive: true);
  });

  test(
    'default off keeps complete native cache and unsupported containers fall back',
    () async {
      expect(source.supportsExperimentalProgressivePlayback, isTrue);
      final stable = await source.resolve(track);
      expect(Uri.tryParse(stable.input)?.scheme, isNot('http'));
      expect(stable.validateCompletion, isNull);
      expect(calls, ['cacheAudio']);
      expect(await source.clearPlaybackCache(), audio.length);
      calls.clear();
      source.setExperimentalProgressivePlayback(true);
      metadata['ext'] = 'm4a';
      final fallback = await source.resolve(track);
      expect(fallback.input, endsWith('abcdefghijk.audio'));
      expect(calls, ['progressiveInfo', 'cacheAudio']);
    },
  );

  test(
    'early playback stays private until duration and full decode validation; clear protects relay',
    () async {
      source.setExperimentalProgressivePlayback(true);
      final resolved = await source
          .resolve(track)
          .timeout(const Duration(seconds: 2));
      expect(resolved.input, startsWith('http://127.0.0.1:'));
      expect(download.isCompleted, isFalse);
      var cleanEof = false;
      final completionGate = resolved.validateCompletion!().then((_) {
        cleanEof = true;
      });
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      await expectLater(
        source.clearPlaybackCache(protectedPath: resolved.input),
        throwsStateError,
      );
      final response = await (await client.getUrl(
        Uri.parse(resolved.input),
      )).close();
      final first = Completer<void>();
      final done = Completer<void>();
      var bytes = 0;
      response.listen(
        (chunk) {
          bytes += chunk.length;
          if (!first.isCompleted) first.complete();
        },
        onDone: done.complete,
        onError: done.completeError,
        cancelOnError: true,
      );
      await first.future.timeout(const Duration(seconds: 1));
      expect(bytes, greaterThan(0));
      // Changing the preference does not stop the already loaded relay.
      source.setExperimentalProgressivePlayback(false);
      download.complete();
      await validationStarted.future.timeout(const Duration(seconds: 1));
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      expect(done.isCompleted, isFalse);
      expect(cleanEof, isFalse);
      validation.complete();
      await done.future.timeout(const Duration(seconds: 1));
      await completionGate;
      expect(cleanEof, isTrue);
      expect(bytes, audio.length);
      expect(await source.playbackCacheInfo(), (bytes: audio.length, files: 1));
      expect(await source.clearPlaybackCache(protectedPath: resolved.input), 0);
      final next = await source.resolve(track);
      expect(next.input, endsWith('abcdefghijk.audio'));
      expect(calls.where((call) => call == 'progressiveInfo'), hasLength(1));
    },
  );

  test(
    'failed partial is discarded and retry creates a fresh source',
    () async {
      source.setExperimentalProgressivePlayback(true);
      final resolved = await source.resolve(track);
      final response = await (await client.getUrl(
        Uri.parse(resolved.input),
      )).close();
      final first = Completer<void>();
      final done = Completer<void>();
      response.listen(
        (_) {
          if (!first.isCompleted) first.complete();
        },
        onDone: done.complete,
        onError: done.completeError,
        cancelOnError: true,
      );
      await first.future;
      final failed = expectLater(done.future, throwsA(isA<HttpException>()));
      final rejectedEof = expectLater(
        resolved.validateCompletion!(),
        throwsStateError,
      );
      download.completeError(
        PlatformException(code: 'SOURCE_ERROR', message: 'HTTP 403'),
      );
      await failed.timeout(const Duration(seconds: 2));
      await rejectedEof;
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      await waitFor(() => !staging!.parent.existsSync());
      download = Completer<void>();
      validation = Completer<void>();
      validationStarted = Completer<void>();
      final retried = await source.resolve(track);
      expect(retried.input, isNot(resolved.input));
      download.complete();
      validation.complete();
      final retryResponse = await (await client.getUrl(
        Uri.parse(retried.input),
      )).close();
      await retryResponse.drain<void>();
      expect(await source.playbackCacheInfo(), (bytes: audio.length, files: 1));
    },
  );

  test(
    'duration mismatch and failed full decode never promote partial input',
    () async {
      source.setExperimentalProgressivePlayback(true);
      await source.resolve(track);
      durationMs = 10000;
      download.complete();
      await waitFor(() => !staging!.parent.existsSync());
      expect(calls, isNot(contains('validateProgressiveAudio')));
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      durationMs = 60000;
      download = Completer<void>();
      await source.resolve(track);
      download.complete();
      await validationStarted.future;
      validation.completeError(PlatformException(code: 'INVALID_AUDIO'));
      await waitFor(() => !staging!.parent.existsSync());
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
    },
  );

  test(
    'resolve cancellation and dispose cancel downloader and clean private stage',
    () async {
      source.setExperimentalProgressivePlayback(true);
      final resolved = await source.resolve(track);
      await source.cancel('resolve:abcdefghijk');
      await waitFor(() => !staging!.parent.existsSync());
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      expect(calls, contains('cancel'));
      await expectLater(
        () async => (await client.getUrl(Uri.parse(resolved.input))).close(),
        throwsA(isA<Exception>()),
      );
      download = Completer<void>();
      await source.resolve(track);
      source.dispose();
      await waitFor(() => !staging!.parent.existsSync());
      await expectLater(source.resolve(track), throwsStateError);
    },
  );

  test(
    'late validation failure rejects clean EOF despite full bytes and matching duration',
    () async {
      source.setExperimentalProgressivePlayback(true);
      final resolved = await source.resolve(track);
      download.complete();
      await validationStarted.future.timeout(const Duration(seconds: 1));
      expect(await staging!.length(), metadata['filesize']);
      expect(resolved.duration.inMilliseconds, durationMs);
      var acceptedEof = false;
      final eof = resolved.validateCompletion!().then((_) {
        acceptedEof = true;
      });
      final rejected = expectLater(eof, throwsStateError);
      validation.completeError(PlatformException(code: 'LATE_DECODE_FAILURE'));
      await rejected.timeout(const Duration(seconds: 1));
      expect(acceptedEof, isFalse);
      expect(await source.playbackCacheInfo(), (bytes: 0, files: 0));
      await waitFor(() => !staging!.parent.existsSync());
    },
  );

  test('oversize metadata is rejected before a downloader starts', () async {
    source.setExperimentalProgressivePlayback(true);
    metadata['filesize'] = 512 * 1024 * 1024 + 1;
    await expectLater(source.resolve(track), throwsStateError);
    expect(calls, ['progressiveInfo']);
    expect(staging, isNull);
  });
}
