import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:aurora_music/core/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Active source operations prevent session changes and release the guard on error',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = YtDlpSource(await SharedPreferences.getInstance());
      try {
        final operation = source.diagnose();
        final operationCheck = expectLater(operation, throwsA(isA<Error>()));
        await expectLater(
          source.configureCookieFile(null),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Espera'),
            ),
          ),
        );
        await operationCheck;
        await source.configureCookieFile(null);
      } finally {
        source.dispose();
      }
    },
  );
  test('Cookie jar errors never expose rejected cookie values', () {
    final message = YtDlpSource.sourceError(
      'invalid Netscape cookies line: .youtube.com TRUE / TRUE 99 SID private-session-value',
    );
    expect(message, contains('Renueva'));
    expect(message, isNot(contains('private-session-value')));
  });
  test(
    'Cookie session is opt-in, validates Netscape, and clears only the reference',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final source = YtDlpSource(preferences);
      final directory = await Directory.systemTemp.createTemp(
        'aurora-cookie-test-',
      );
      final cookies = File('${directory.path}/cookies.txt');
      try {
        expect(source.cookieFile, isNull);
        await cookies.writeAsString(
          '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t1999999999\tfake\ttest-only-value\n',
        );
        await source.configureCookieFile(cookies.path);
        expect(source.cookieFile, cookies.absolute.path);
        expect(preferences.getString('cookieFile'), cookies.absolute.path);
        await source.configureCookieFile(null);
        expect(source.cookieFile, isNull);
        expect(await cookies.exists(), isTrue);
        await cookies.writeAsString(
          '# Netscape HTTP Cookie File\nprivate-invalid-line',
        );
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.toString(),
              'safe message',
              isNot(contains('private-invalid-line')),
            ),
          ),
        );
        await cookies.writeAsString('# Netscape HTTP Cookie File\n');
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsArgumentError,
        );
        await cookies.writeAsString(
          '# Netscape HTTP Cookie File\n.example.com\tTRUE\t/\tTRUE\t1999999999\tfake\ttest-only-value\n',
        );
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsArgumentError,
        );
        await cookies.writeAsString('wrong header\n');
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsArgumentError,
        );
        await cookies.writeAsString(
          '# Netscape HTTP Cookie File\n${'x' * (1024 * 1024)}',
        );
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsArgumentError,
        );
        await cookies.delete();
        await expectLater(
          source.configureCookieFile(cookies.path),
          throwsStateError,
        );
        expect(source.cookieFile, isNull);
      } finally {
        source.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
  test('Source errors hide signed URL query credentials', () {
    final result = YtDlpSource.redactError(
      'HTTP 403 https://host.test/audio?sig=secret&token=private',
    );
    expect(result, contains('HTTP 403'));
    expect(result, contains('https://host.test/audio'));
    expect(result, isNot(contains('secret')));
    expect(result, isNot(contains('private')));
  });
  test('Upstream rate limits explain recovery and cap diagnostic text', () {
    expect(
      YtDlpSource.sourceError('HTTP Error 429: Too Many Requests'),
      contains('1 minuto'),
    );
    expect(
      YtDlpSource.sourceError('Sign in to confirm you are not a bot'),
      isNot(contains('cookies')),
    );
    expect(
      YtDlpSource.sourceError(
        'HTTP Error 403 https://host.test/audio?token=private',
      ),
      contains('(403)'),
    );
    expect(YtDlpSource.sourceError('x' * 3000).length, lessThanOrEqualTo(2001));
  });
  test(
    'source errors distinguish status digits from IDs and disclose uncertainty',
    () {
      expect(
        YtDlpSource.sourceError('[youtube] abc429xyzAB: video unavailable'),
        contains('no está disponible públicamente'),
      );
      expect(
        YtDlpSource.sourceError('Failed to inspect audio403.webm'),
        'Failed to inspect audio403.webm',
      );
      expect(
        YtDlpSource.sourceError('HTTP 429'),
        contains('puede mantener la restricción más tiempo'),
      );
      expect(
        YtDlpSource.sourceError('HTTP 403'),
        contains('ni que toda la red esté bloqueada'),
      );
    },
  );
  test(
    'Missing local file reports removal instead of returning a stale path',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = YtDlpSource(await SharedPreferences.getInstance());
      try {
        await expectLater(
          source.resolve(
            const Track(
              id: 'file:missing',
              title: 'Missing',
              artist: 'Local',
              localPath: 'nonexistent-test-audio.mp3',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('archivo local'),
            ),
          ),
        );
        await expectLater(
          source.resolve(
            const Track(
              id: 'yt:abcdefghijk',
              title: 'Missing download',
              artist: 'YouTube',
              localPath: 'nonexistent-test-audio.mp3',
              pageUrl: 'https://youtu.be/abcdefghijk',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('carpeta'),
            ),
          ),
        );
      } finally {
        source.dispose();
      }
    },
  );
  test(
    'Windows cache info and clear touch only owned files and preserve loaded audio',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = YtDlpSource(await SharedPreferences.getInstance());
      final support = await Directory.systemTemp.createTemp(
        'aurora-cache-test-',
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      try {
        final cache = Directory('${support.path}/yt-dlp-audio');
        await cache.create();
        final playing = File('${cache.path}/abcdefghijk.audio');
        final removable = File('${cache.path}/lmnopqrstuv.audio');
        final foreign = File('${cache.path}/library-song.mp3');
        final outside = File('${support.parent.path}/outside.audio');
        await playing.writeAsBytes([1, 2, 3]);
        await removable.writeAsBytes([4, 5, 6, 7]);
        await File('${cache.path}/not_a_video!.audio').writeAsBytes([8, 9]);
        await foreign.writeAsBytes([10, 11]);
        await outside.writeAsBytes([12, 13]);

        expect(source.supportsPlaybackCache, isTrue);
        expect(await source.playbackCacheInfo(), (bytes: 7, files: 2));
        expect(await source.clearPlaybackCache(protectedPath: playing.path), 4);
        expect(await playing.exists(), isTrue);
        expect(await removable.exists(), isFalse);
        expect(await foreign.exists(), isTrue);
        expect(await File('${cache.path}/not_a_video!.audio').exists(), isTrue);
        expect(await outside.exists(), isTrue);
        expect(await source.playbackCacheInfo(), (bytes: 3, files: 1));
        await outside.delete();
      } finally {
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        source.dispose();
        await support.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'Windows cache clear refuses to race an active resolve',
    () async {
      SharedPreferences.setMockInitialValues({
        'toolDirectory': r'C:\aurora-test-tools',
      });
      final probeStarted = Completer<void>();
      final probeResult = Completer<Duration?>();
      final source = YtDlpSource(
        await SharedPreferences.getInstance(),
        audioDuration: (_) {
          probeStarted.complete();
          return probeResult.future;
        },
      );
      final support = await Directory.systemTemp.createTemp(
        'aurora-cache-test-',
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      try {
        final cache = Directory('${support.path}/yt-dlp-audio');
        await cache.create();
        await File('${cache.path}/abcdefghijk.audio').writeAsBytes([1, 2, 3]);
        final resolving = source.resolve(
          const Track(
            id: 'sp:spotify-track-id',
            title: 'Imported track',
            artist: 'Spotify',
            duration: Duration(minutes: 1),
            pageUrl: 'https://youtu.be/abcdefghijk',
          ),
        );
        await probeStarted.future;
        await expectLater(
          source.clearPlaybackCache(),
          throwsA(isA<StateError>()),
        );
        probeResult.complete(const Duration(minutes: 1));
        await resolving;
      } finally {
        if (!probeResult.isCompleted) probeResult.complete(null);
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        source.dispose();
        await support.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'Windows audio cache derives Spotify IDs from safe YouTube page URLs',
    () async {
      SharedPreferences.setMockInitialValues({
        'toolDirectory': r'C:\aurora-test-tools',
      });
      final source = YtDlpSource(
        await SharedPreferences.getInstance(),
        audioDuration: (_) async => const Duration(minutes: 1),
      );
      final support = await Directory.systemTemp.createTemp(
        'aurora-cache-test-',
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      try {
        final cache = Directory('${support.path}/yt-dlp-audio');
        await cache.create();
        final cached = File('${cache.path}/abcdefghijk.audio');
        await cached.writeAsBytes([1, 2, 3]);
        final result = await source.resolve(
          const Track(
            id: 'sp:spotify-track-id',
            title: 'Imported track',
            artist: 'Spotify',
            duration: Duration(minutes: 1),
            pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
          ),
        );
        expect(
          await File(result.input).resolveSymbolicLinks(),
          await cached.resolveSymbolicLinks(),
        );
        expect(result.duration, const Duration(minutes: 1));

        await expectLater(
          source.resolve(
            const Track(
              id: 'yt:zyxwvutsrqp',
              title: 'Mismatched video',
              artist: 'YouTube',
              pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
            ),
          ),
          throwsArgumentError,
        );
      } finally {
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        source.dispose();
        await support.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'Windows cache drops an existing file when its duration is truncated',
    () async {
      SharedPreferences.setMockInitialValues({
        'toolDirectory': r'C:\aurora-test-tools',
      });
      final source = YtDlpSource(
        await SharedPreferences.getInstance(),
        audioDuration: (_) async => const Duration(seconds: 10),
      );
      final support = await Directory.systemTemp.createTemp(
        'aurora-cache-test-',
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      try {
        final cache = Directory('${support.path}/yt-dlp-audio');
        await cache.create();
        final cached = File('${cache.path}/abcdefghijk.audio');
        await cached.writeAsBytes([1, 2, 3]);
        await expectLater(
          source.resolve(
            const Track(
              id: 'sp:spotify-track-id',
              title: 'Imported track',
              artist: 'Spotify',
              duration: Duration(minutes: 1),
              pageUrl: 'https://youtu.be/abcdefghijk',
            ),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('yt-dlp.exe'),
            ),
          ),
        );
        expect(await cached.exists(), isFalse);
      } finally {
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        source.dispose();
        await support.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'Windows cache resolve cancellation remains active while probing duration',
    () async {
      SharedPreferences.setMockInitialValues({
        'toolDirectory': r'C:\aurora-test-tools',
      });
      final probeStarted = Completer<void>();
      final probeResult = Completer<Duration?>();
      final source = YtDlpSource(
        await SharedPreferences.getInstance(),
        audioDuration: (_) {
          probeStarted.complete();
          return probeResult.future;
        },
      );
      final support = await Directory.systemTemp.createTemp(
        'aurora-cache-test-',
      );
      const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      try {
        final cache = Directory('${support.path}/yt-dlp-audio');
        await cache.create();
        await File('${cache.path}/abcdefghijk.audio').writeAsBytes([1, 2, 3]);
        final resolving = source.resolve(
          const Track(
            id: 'sp:spotify-track-id',
            title: 'Imported track',
            artist: 'Spotify',
            duration: Duration(minutes: 1),
            pageUrl: 'https://youtu.be/abcdefghijk',
          ),
        );
        await probeStarted.future;
        await source.cancel('resolve:abcdefghijk');
        probeResult.complete(const Duration(minutes: 1));
        await expectLater(
          resolving,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('cancelada'),
            ),
          ),
        );
      } finally {
        if (!probeResult.isCompleted) probeResult.complete(null);
        TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
            .setMockMethodCallHandler(pathProvider, null);
        source.dispose();
        await support.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'Windows audio cache rejects IDs that could escape its private directory',
    () async {
      SharedPreferences.setMockInitialValues({});
      final source = YtDlpSource(await SharedPreferences.getInstance());
      try {
        await expectLater(
          source.resolve(
            const Track(
              id: 'yt:../../outside',
              title: 'Unsafe ID',
              artist: 'YouTube',
              pageUrl: 'https://youtube.com/watch?v=abcdefghijk',
            ),
          ),
          throwsArgumentError,
        );
      } finally {
        source.dispose();
      }
    },
    skip: !Platform.isWindows,
  );
  test(
    'YouTube input accepts HTTPS pages and rejects other protocols and hosts',
    () {
      expect(
        YtDlpSource.validateYouTube('https://youtu.be/abc').host,
        'youtu.be',
      );
      expect(
        YtDlpSource.validateYouTube(
          'https://music.youtube.com/playlist?list=123',
        ).scheme,
        'https',
      );
      for (final input in [
        'http://youtube.com/watch?v=abc',
        'https://youtube.com.evil.test/watch?v=abc',
        'https://user@youtube.com/watch?v=abc',
        'file:///C:/secret',
        '--exec=calc',
        'https://youtube.com:8080/',
      ]) {
        expect(
          () => YtDlpSource.validateYouTube(input),
          throwsArgumentError,
          reason: input,
        );
      }
    },
  );
}
