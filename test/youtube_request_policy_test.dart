import 'dart:async';
import 'package:aurora_music/sources/youtube_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'classification distinguishes blocked denied unavailable and transient',
    () {
      expect(YouTubeRequestPolicy.classify('HTTP 429'), YouTubeFailure.blocked);
      expect(
        YouTubeRequestPolicy.classify('confirm you are not a bot'),
        YouTubeFailure.blocked,
      );
      expect(
        YouTubeRequestPolicy.classify('HTTP 403 Forbidden'),
        YouTubeFailure.accessDenied,
      );
      expect(
        YouTubeRequestPolicy.classify('video unavailable'),
        YouTubeFailure.unavailable,
      );
      expect(
        YouTubeRequestPolicy.classify('Connection reset'),
        YouTubeFailure.transient,
      );
    },
  );
  test(
    'metadata transport retries once; explicit download never retries',
    () async {
      final waits = <Duration>[];
      final policy = YouTubeRequestPolicy(
        requestSpacing: Duration.zero,
        sleep: (d) async => waits.add(d),
      );
      var count = 0;
      final result = await policy.run(() async {
        if (++count == 1) throw StateError('Connection reset');
        return 12;
      }, retryTransient: true);
      expect(result, 12);
      expect(count, 2);
      expect(waits, [const Duration(seconds: 2)]);
      await expectLater(
        policy.run(() async {
          count++;
          throw StateError('Connection reset');
        }),
        throwsStateError,
      );
      expect(count, 3);
    },
  );
  test('blocked requests never retry and cooldown expires', () async {
    var now = DateTime.utc(2026, 1, 1), count = 0;
    final policy = YouTubeRequestPolicy(
      now: () => now,
      requestSpacing: Duration.zero,
    );
    Future<int> request() async {
      count++;
      throw StateError('HTTP 429');
    }

    await expectLater(
      policy.run(request, retryTransient: true),
      throwsStateError,
    );
    await expectLater(policy.run(request), throwsStateError);
    expect(count, 1);
    now = now.add(const Duration(minutes: 16));
    await expectLater(policy.run(request), throwsStateError);
    expect(count, 2);
  });
  test('only two requests run simultaneously', () async {
    final policy = YouTubeRequestPolicy(requestSpacing: Duration.zero);
    final gates = List.generate(3, (_) => Completer<int>());
    var starts = 0;
    final futures = List.generate(
      3,
      (i) => policy.run(() {
        starts++;
        return gates[i].future;
      }),
    );
    await Future<void>.delayed(Duration.zero);
    expect(starts, 2);
    gates[0].complete(1);
    await Future<void>.delayed(Duration.zero);
    expect(starts, 3);
    gates[1].complete(2);
    gates[2].complete(3);
    expect(await Future.wait(futures), [1, 2, 3]);
  });
}
