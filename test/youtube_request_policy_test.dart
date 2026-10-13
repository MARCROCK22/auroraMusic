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
  test('IDs and URL parameters never masquerade as HTTP failures', () {
    for (final message in [
      '[youtube] abc429xyzAB: video unavailable',
      '[youtube] aa-429-bbbb: extraction failed',
      'Cannot inspect audio403.webm',
      'Cannot inspect https://host/429/audio?status=403',
      'Cannot inspect https://host/502/audio',
    ]) {
      expect(
        YouTubeRequestPolicy.classify(message),
        isNot(
          anyOf(
            YouTubeFailure.blocked,
            YouTubeFailure.accessDenied,
            YouTubeFailure.transient,
          ),
        ),
        reason: message,
      );
    }
    expect(
      YouTubeRequestPolicy.classify('HTTP Error 403: Forbidden'),
      YouTubeFailure.accessDenied,
    );
    expect(
      YouTubeRequestPolicy.classify('response code: 429'),
      YouTubeFailure.blocked,
    );
    expect(
      YouTubeRequestPolicy.classify('statusCode=503'),
      YouTubeFailure.transient,
    );
  });
  test('documented guest limit and sanitized errors retain their category', () {
    expect(
      YouTubeRequestPolicy.classify(
        "This content isn't available, try again later",
      ),
      YouTubeFailure.blocked,
    );
    expect(
      YouTubeRequestPolicy.classify(
        'YouTube limitó las solicitudes o pidió una verificación.',
      ),
      YouTubeFailure.blocked,
    );
    expect(
      YouTubeRequestPolicy.classify('YouTube rechazó el acceso (403).'),
      YouTubeFailure.accessDenied,
    );
  });
  test(
    'a video ID with status digits does not stop subsequent requests',
    () async {
      final policy = YouTubeRequestPolicy(requestSpacing: Duration.zero);
      await expectLater(
        policy.run(() async {
          throw StateError('[youtube] abc429xyzAB: video unavailable');
        }),
        throwsStateError,
      );
      expect(policy.blockedUntil, isNull);
      expect(await policy.run(() async => 42), 42);
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
    now = now.add(const Duration(seconds: 59));
    await expectLater(policy.run(request), throwsStateError);
    expect(count, 1);
    now = now.add(const Duration(seconds: 1));
    await expectLater(policy.run(request), throwsStateError);
    expect(count, 2);
  });
  test('restored longer pauses migrate once and retain the remaining time', () {
    var now = DateTime.utc(2026, 1, 1);
    final policy = YouTubeRequestPolicy(now: () => now);
    DateTime? saved;
    policy.onBlocked = (until) => saved = until;
    policy.restoreCooldown(now.add(const Duration(minutes: 15)));
    expect(saved, now.add(const Duration(minutes: 1)));
    now = now.add(const Duration(seconds: 30));
    final restored = YouTubeRequestPolicy(now: () => now);
    restored.restoreCooldown(saved);
    expect(restored.blockedUntil!.difference(now), const Duration(seconds: 30));
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
