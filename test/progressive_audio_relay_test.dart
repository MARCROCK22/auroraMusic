import 'dart:async';
import 'dart:io';

import 'package:aurora_music/sources/progressive_audio_relay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File growing;
  late Completer<File> completion;
  late HttpClient client;
  late ProgressiveAudioRelay relay;
  late int cancellations;

  Future<void> start({
    int? expectedBytes,
    int maxBytes = 1024,
    Duration stallTimeout = const Duration(seconds: 2),
  }) async {
    relay = await ProgressiveAudioRelay.start(
      file: growing,
      completed: completion.future,
      expectedBytes: expectedBytes,
      maxBytes: maxBytes,
      pollInterval: const Duration(milliseconds: 5),
      stallTimeout: stallTimeout,
      cancel: () async => cancellations++,
    );
  }

  Future<HttpClientResponse> get({String? range, Uri? uri}) async {
    final request = await client.getUrl(uri ?? relay.uri);
    if (range != null) request.headers.set('Range', range);
    return request.close();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aurora-progressive-');
    growing = File('${directory.path}/audio.webm');
    await growing.writeAsBytes([0x1a, 0x45, 0xdf, 0xa3, 4, 5]);
    completion = Completer<File>();
    cancellations = 0;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await relay.dispose();
    if (!completion.isCompleted) completion.completeError(StateError('cancel'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await directory.delete(recursive: true);
  });

  test(
    'slow download streams before completion and never emits temporary EOF',
    () async {
      await start(expectedBytes: 12);
      await relay.waitUntilReady(minimumBytes: 4);
      final response = await get();
      final first = Completer<void>();
      final finished = Completer<void>();
      final bytes = <int>[];
      response.listen(
        (chunk) {
          bytes.addAll(chunk);
          if (!first.isCompleted) first.complete();
        },
        onDone: finished.complete,
        onError: finished.completeError,
        cancelOnError: true,
      );
      await first.future.timeout(const Duration(seconds: 1));
      expect(bytes, [0x1a, 0x45, 0xdf, 0xa3, 4]);
      expect(completion.isCompleted, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(finished.isCompleted, isFalse);
      await growing.writeAsBytes([6, 7, 8, 9, 10, 11], mode: FileMode.append);
      // Downloader finishing alone is insufficient; validation controls EOF.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(finished.isCompleted, isFalse);
      completion.complete(growing);
      await finished.future.timeout(const Duration(seconds: 1));
      expect(bytes, [0x1a, 0x45, 0xdf, 0xa3, 4, 5, 6, 7, 8, 9, 10, 11]);
      expect(relay.isComplete, isTrue);
    },
  );

  test(
    'forward range seek blocks at missing data and backward seek remains readable',
    () async {
      await start(expectedBytes: 12);
      final seeking = get(range: 'bytes=8-10');
      var gotData = false;
      final result = seeking.then((response) async {
        expect(response.statusCode, 206);
        expect(response.headers.value('Content-Range'), 'bytes 8-10/12');
        final bytes = await response.fold<List<int>>(
          [],
          (all, next) => all..addAll(next),
        );
        gotData = true;
        return bytes;
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(gotData, isFalse);
      await growing.writeAsBytes([6, 7, 8, 9, 10, 11], mode: FileMode.append);
      expect(await result.timeout(const Duration(seconds: 1)), [8, 9, 10]);
      final backward = await get(range: 'bytes=0-3');
      expect(
        await backward.fold<List<int>>([], (all, next) => all..addAll(next)),
        [0x1a, 0x45, 0xdf, 0xa3],
      );
      expect(completion.isCompleted, isFalse);
      completion.complete(growing);
    },
  );

  test(
    'unknown size streams and open or suffix ranges wait for validated total',
    () async {
      await start();
      final first = await get(range: 'bytes=0-3');
      expect(first.headers.value('Content-Range'), 'bytes 0-3/*');
      expect(
        await first.fold<List<int>>([], (all, next) => all..addAll(next)),
        hasLength(4),
      );
      var headersArrived = false;
      final seeking = get(range: 'bytes=4-').then((response) {
        headersArrived = true;
        return response;
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(headersArrived, isFalse);
      completion.complete(growing);
      final response = await seeking.timeout(const Duration(seconds: 1));
      expect(response.headers.value('Content-Range'), 'bytes 4-5/6');
      expect(
        await response.fold<List<int>>([], (all, next) => all..addAll(next)),
        [4, 5],
      );
      final suffix = await get(range: 'bytes=-2');
      expect(
        await suffix.fold<List<int>>([], (all, next) => all..addAll(next)),
        [4, 5],
      );
    },
  );

  test('unknown initial bytes=0- request streams before completion', () async {
    await start();
    final response = await get(range: 'bytes=0-');
    expect(response.statusCode, 200);
    expect(response.contentLength, -1);
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
    await first.future.timeout(const Duration(seconds: 1));
    expect(completion.isCompleted, isFalse);
    completion.complete(growing);
    await done.future;
  });

  test(
    'stalled download bounds waits even when no client is connected',
    () async {
      await start(stallTimeout: const Duration(milliseconds: 80));
      await relay.settled.timeout(const Duration(seconds: 1));
      expect(relay.isComplete, isFalse);
      expect(relay.error, isA<StateError>());
      expect(cancellations, 1);
      await expectLater(relay.waitUntilReady(), throwsStateError);
    },
  );

  test(
    'publication switches file after validation; HTTP endpoint contains no file path',
    () async {
      await start();
      final published = File('${directory.path}/trusted.audio');
      expect(await published.exists(), isFalse);
      await growing.copy(published.path);
      await growing.delete();
      completion.complete(published);
      await relay.settled;
      expect(relay.file.path, published.path);
      expect(relay.uri.host, '127.0.0.1');
      expect(relay.uri.path, matches(r'^/aurora-progressive/[a-f0-9]{64}$'));
      final response = await get();
      expect(
        await response.fold<List<int>>([], (all, next) => all..addAll(next)),
        hasLength(6),
      );
      for (final path in [
        '/audio.webm',
        '/aurora-progressive/wrong',
        '/../../trusted.audio',
      ]) {
        final rejected = await get(uri: relay.uri.replace(path: path));
        expect(rejected.statusCode, 404);
        await rejected.drain<void>();
      }
      final query = await get(
        uri: relay.uri.replace(query: 'path=trusted.audio'),
      );
      expect(query.statusCode, 404);
      await query.drain<void>();
    },
  );

  test(
    'failed partial download aborts response instead of clean EOF',
    () async {
      await start(expectedBytes: 12);
      final response = await get();
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
      final failure = expectLater(done.future, throwsA(isA<HttpException>()));
      completion.completeError(StateError('download rejected'));
      await failure.timeout(const Duration(seconds: 1));
      expect(relay.isComplete, isFalse);
      expect(cancellations, 1);
    },
  );

  test(
    'byte bounds cancel growing input and reject oversize metadata',
    () async {
      await start(maxBytes: 8);
      await growing.writeAsBytes(List.filled(12, 1));
      await relay.settled.timeout(const Duration(seconds: 1));
      expect(relay.error, isA<StateError>());
      expect(cancellations, 1);
      final response = await get();
      expect(response.statusCode, 503);
      await response.drain<void>();
      await expectLater(
        ProgressiveAudioRelay.start(
          file: growing,
          completed: Future.value(growing),
          cancel: () async {},
          expectedBytes: ProgressiveAudioRelay.byteLimit + 1,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'HEAD has truthful length and invalid or multi ranges are rejected',
    () async {
      await start(expectedBytes: 12);
      final request = await client.headUrl(relay.uri);
      final response = await request.close();
      expect(response.contentLength, 12);
      expect(response.headers.value('Accept-Ranges'), 'bytes');
      await response.drain<void>();
      for (final range in [
        'bytes=99-',
        'bytes=4-1',
        'bytes=0-1,4-5',
        'bytes=-0',
      ]) {
        final rejected = await get(range: range);
        expect(rejected.statusCode, 416);
        await rejected.drain<void>();
      }
    },
  );

  test(
    'paused client, disconnected seek, and dispose release pending readers',
    () async {
      await start(expectedBytes: 12);
      final response = await get();
      final subscription = response.listen((_) {});
      subscription.pause();
      final waitingClient = HttpClient();
      final request = await waitingClient.getUrl(relay.uri);
      request.headers.set('Range', 'bytes=9-');
      final waiting = request.close();
      final waitingCheck = expectLater(waiting, throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      waitingClient.close(force: true);
      await waitingCheck;
      await relay.dispose();
      expect(cancellations, 1);
      await subscription.cancel();
      await expectLater(relay.waitUntilReady(), throwsStateError);
      await relay.dispose();
      expect(cancellations, 1);
    },
  );
}
