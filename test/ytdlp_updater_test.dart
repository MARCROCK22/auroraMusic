import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/sources/ytdlp_updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late File executable;
  late File state;
  late List<Uri> requests;
  const version = '2026.10.10.233141';
  const sourceCommit = '897341241f2bfb2439fe0367f4c7c9ccd29a3828';
  final bytes = [0x4d, 0x5a, ...utf8.encode('verified nightly')];
  final oldBytes = [0x4d, 0x5a, ...utf8.encode('previous executable')];
  final expected = sha256.convert(bytes).toString();
  var idle = true;
  var now = DateTime.utc(2026, 10, 12);

  Future<List<int>> fetch(Uri uri) async {
    requests.add(uri);
    if (uri.host == 'api.github.com') {
      return utf8.encode(
        jsonEncode({
          'tag_name': version,
          'draft': false,
          'body':
              'Generated from: https://github.com/yt-dlp/yt-dlp/commit/$sourceCommit\n',
          'assets': ['yt-dlp.exe', 'SHA2-256SUMS']
              .map(
                (name) => {
                  'name': name,
                  'browser_download_url':
                      'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/$version/$name',
                },
              )
              .toList(),
        }),
      );
    }
    if (uri.path.endsWith('SHA2-256SUMS')) {
      return utf8.encode('$expected  yt-dlp.exe\n');
    }
    if (uri.path.endsWith('.exe')) return bytes;
    return utf8.encode('Official license notice');
  }

  YtDlpUpdater updater({
    Future<List<int>> Function(Uri)? download,
    Future<String> Function(File)? probe,
    Future<void> Function(File, File)? replace,
  }) => YtDlpUpdater(
    executable: executable,
    stateFile: state,
    canUpdate: () => idle,
    fetch: download ?? fetch,
    executableVersion: probe ?? (_) async => version,
    replace: replace,
    clock: () => now,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aurora-ytdlp-test-');
    executable = File(p.join(directory.path, 'yt-dlp.exe'));
    state = File(p.join(directory.path, 'update.json'));
    await executable.writeAsBytes(oldBytes);
    requests = [];
    idle = true;
    now = DateTime.utc(2026, 10, 12);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test(
    'installs verified nightly, preserves notices, persists daily cadence',
    () async {
      expect(
        (await updater().checkForUpdate()).status,
        YtDlpUpdateStatus.updated,
      );
      expect(await executable.readAsBytes(), bytes);
      final saved = jsonDecode(await state.readAsString()) as Map;
      expect(saved['version'], version);
      expect(saved['sha256'], expected);
      expect(saved['sourceCommit'], sourceCommit);
      expect(saved['pendingInstallation'], isNull);
      expect(
        await File(
          p.join(directory.path, 'licenses', 'yt-dlp-$version-LICENSE'),
        ).exists(),
        isTrue,
      );
      expect(
        await File('${executable.path}.aurora-previous').exists(),
        isFalse,
      );
      final count = requests.length;
      expect(
        (await updater().checkForUpdate()).status,
        YtDlpUpdateStatus.throttled,
      );
      expect(requests.length, count);
      now = now.add(const Duration(hours: 24));
      expect(
        (await updater().checkForUpdate()).status,
        YtDlpUpdateStatus.upToDate,
      );
      expect(requests.where((uri) => uri.path.endsWith('.exe')).length, 1);
    },
  );

  test(
    'hash mismatch preserves executable and throttles failed checks',
    () async {
      final result = await updater(
        download: (uri) async =>
            uri.path.endsWith('.exe') ? [0x4d, 0x5a, 0] : await fetch(uri),
      ).checkForUpdate();
      expect(result.status, YtDlpUpdateStatus.failed);
      expect(await executable.readAsBytes(), oldBytes);
      expect(
        (await updater().checkForUpdate()).status,
        YtDlpUpdateStatus.throttled,
      );
    },
  );

  test('post-install probe failure restores previous executable', () async {
    final result = await updater(
      probe: (file) async =>
          file.path == executable.path ? 'wrong version' : version,
    ).checkForUpdate();
    expect(result.status, YtDlpUpdateStatus.failed);
    expect(await executable.readAsBytes(), oldBytes);
    expect((jsonDecode(await state.readAsString()) as Map)['version'], isNull);
  });

  test(
    'sharing violation before install leaves previous executable usable',
    () async {
      final result = await updater(
        replace: (_, _) async {
          throw const FileSystemException('Simulated executable lock');
        },
      ).checkForUpdate();
      expect(result.status, YtDlpUpdateStatus.failed);
      expect(await executable.readAsBytes(), oldBytes);
    },
  );

  test('initial busy guard performs no network or state writes', () async {
    idle = false;
    expect(
      (await updater().checkForUpdate()).status,
      YtDlpUpdateStatus.deferred,
    );
    expect(requests, isEmpty);
    expect(await state.exists(), isFalse);
  });

  test('playback started during download defers replacement', () async {
    final result = await updater(
      download: (uri) async {
        final result = await fetch(uri);
        if (uri.path.endsWith('.exe')) idle = false;
        return result;
      },
    ).checkForUpdate();
    expect(result.status, YtDlpUpdateStatus.deferred);
    expect(await executable.readAsBytes(), oldBytes);
  });

  test(
    'concurrent instances share request, expose install lock before rename',
    () async {
      final gate = Completer<void>();
      late YtDlpUpdater first;
      first = updater(
        download: (uri) async {
          if (uri.host == 'api.github.com') await gate.future;
          return fetch(uri);
        },
        replace: (from, to) async {
          expect(first.isInstalling, isTrue);
          expect(updater().isInstalling, isTrue);
          final journal =
              (jsonDecode(await state.readAsString())
                      as Map)['pendingInstallation']
                  as Map;
          expect(journal['sha256'], expected);
          expect(
            journal['previousSha256'],
            sha256.convert(oldBytes).toString(),
          );
          expect(
            await File('${executable.path}.aurora-previous').readAsBytes(),
            oldBytes,
          );
          await from.rename(to.path);
        },
      );
      final firstFuture = first.checkForUpdate();
      final secondFuture = updater().checkForUpdate();
      expect(identical(firstFuture, secondFuture), isTrue);
      expect(first.isUpdating, isTrue);
      expect(first.isInstalling, isFalse);
      gate.complete();
      expect((await firstFuture).status, YtDlpUpdateStatus.updated);
      expect(requests.where((uri) => uri.host == 'api.github.com').length, 1);
      expect(first.isUpdating, isFalse);
      expect(first.isInstalling, isFalse);
    },
  );

  test(
    'rejects release assets pointing outside official nightly repository',
    () async {
      final result = await updater(
        download: (uri) async {
          final response = await fetch(uri);
          if (uri.host != 'api.github.com') return response;
          return utf8.encode(
            utf8
                .decode(response)
                .replaceAll(
                  'github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/',
                  'evil.example/releases/download/',
                ),
          );
        },
      ).checkForUpdate();
      expect(result.status, YtDlpUpdateStatus.failed);
      expect(requests.length, 1);
      expect(await executable.readAsBytes(), oldBytes);
    },
  );

  test('network rate limit consumes one persisted daily check', () async {
    final result = await updater(
      download: (_) async {
        throw const HttpException('429');
      },
    ).checkForUpdate();
    expect(result.status, YtDlpUpdateStatus.failed);
    expect(await executable.readAsBytes(), oldBytes);
    expect(
      (await updater().checkForUpdate()).status,
      YtDlpUpdateStatus.throttled,
    );
  });

  Future<void> pendingInstallation() async {
    await File('${executable.path}.aurora-previous').writeAsBytes(oldBytes);
    await state.writeAsString(
      jsonEncode({
        'lastCheckAt': now.toIso8601String(),
        'version': '2026.08.19',
        'sha256': sha256.convert(oldBytes).toString(),
        'pendingInstallation': {
          'sha256': expected,
          'previousSha256': sha256.convert(oldBytes).toString(),
          'version': version,
          'sourceCommit': sourceCommit,
        },
      }),
    );
  }

  test('recovers interrupted broken install before daily throttle', () async {
    await pendingInstallation();
    await executable.writeAsBytes(bytes);
    final result = await updater(probe: (_) async => 'broken').checkForUpdate();
    expect(result.status, YtDlpUpdateStatus.throttled);
    expect(await executable.readAsBytes(), oldBytes);
    final saved = jsonDecode(await state.readAsString()) as Map;
    expect(saved['pendingInstallation'], isNull);
    expect(saved['version'], '2026.08.19');
    expect(requests, isEmpty);
  });

  test('startup commits valid interrupted install without network', () async {
    await pendingInstallation();
    await executable.writeAsBytes(bytes);
    final result = await updater().recoverPendingInstallation();
    expect(result.status, YtDlpUpdateStatus.updated);
    expect(await executable.readAsBytes(), bytes);
    final saved = jsonDecode(await state.readAsString()) as Map;
    expect(saved['pendingInstallation'], isNull);
    expect(saved['version'], version);
    expect(await File('${executable.path}.aurora-previous').exists(), isFalse);
    expect(requests, isEmpty);
  });

  test(
    'startup restores missing executable from hash-verified backup',
    () async {
      await pendingInstallation();
      await executable.delete();
      final result = await updater().recoverPendingInstallation();
      expect(result.status, YtDlpUpdateStatus.upToDate);
      expect(await executable.readAsBytes(), oldBytes);
      expect(
        (jsonDecode(await state.readAsString()) as Map)['pendingInstallation'],
        isNull,
      );
      expect(requests, isEmpty);
    },
  );

  test('startup rejects corrupt backup and retains recovery journal', () async {
    await pendingInstallation();
    await executable.writeAsBytes([0]);
    await File('${executable.path}.aurora-previous').writeAsBytes([1]);
    final result = await updater().recoverPendingInstallation();
    expect(result.status, YtDlpUpdateStatus.failed);
    expect(
      (jsonDecode(await state.readAsString()) as Map)['pendingInstallation'],
      isNotNull,
    );
    expect(await executable.readAsBytes(), [0]);
    expect(requests, isEmpty);
  });

  for (final location in [
    'https://evil.example/payload',
    'http://github.com/payload',
  ]) {
    test('rejects redirect $location before contacting destination', () async {
      final client = _RedirectClient(location);
      final result = await HttpOverrides.runZoned(
        () => YtDlpUpdater(
          executable: executable,
          stateFile: state,
          canUpdate: () => true,
        ).checkForUpdate(),
        createHttpClient: (_) => client,
      );
      expect(result.status, YtDlpUpdateStatus.failed);
      expect(client.destinations, [
        Uri.parse(
          'https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest',
        ),
      ]);
    });
  }

  test('stops after five official redirects', () async {
    final client = _RedirectClient('https://api.github.com/redirect-loop');
    final result = await HttpOverrides.runZoned(
      () => YtDlpUpdater(
        executable: executable,
        stateFile: state,
        canUpdate: () => true,
      ).checkForUpdate(),
      createHttpClient: (_) => client,
    );
    expect(result.status, YtDlpUpdateStatus.failed);
    expect(client.destinations.length, 6);
  });
}

class _RedirectClient implements HttpClient {
  _RedirectClient(this.location);
  final String location;
  final destinations = <Uri>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    destinations.add(url);
    return _RedirectRequest(location);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RedirectRequest implements HttpClientRequest {
  _RedirectRequest(this.location);
  final String location;
  @override
  bool followRedirects = true;
  @override
  HttpHeaders get headers => _RedirectHeaders(location);
  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    return _RedirectResponse(location);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RedirectResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _RedirectResponse(this.location);
  final String location;
  @override
  int get statusCode => 302;
  @override
  HttpHeaders get headers => _RedirectHeaders(location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RedirectHeaders implements HttpHeaders {
  _RedirectHeaders(this.location);
  final String location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
