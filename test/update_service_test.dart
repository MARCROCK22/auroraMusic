import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/updater/update_service.dart';

class _Store implements UpdateStore {
  final map = <String, String>{};
  @override
  String? read(String key) => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

typedef _Handler = UpdateResponse Function(Uri url, Map<String, String> h);

class _Fake implements UpdateTransport {
  _Fake(this.handler);
  final _Handler handler;
  final calls = <Uri>[];
  final headers = <Map<String, String>>[];
  @override
  Future<UpdateResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    calls.add(url);
    this.headers.add(headers);
    return handler(url, headers);
  }
}

UpdateResponse _ok(String body, {int status = 200, Map<String, String>? h}) =>
    UpdateResponse(status, h ?? {}, Stream.value(utf8.encode(body)));

String _release(
  String tag, {
  bool pre = false,
  bool draft = false,
  List<String> assets = const [],
}) => jsonEncode({
  'tag_name': tag,
  'prerelease': pre,
  'draft': draft,
  'body': '## Novedades\n- algo',
  'assets': [
    for (final a in assets)
      {
        'name': a,
        'size': 5,
        'browser_download_url':
            'https://github.com/kaz-py/auroraMusic/releases/download/$tag/$a',
      },
  ],
});

void main() {
  final v = SemVer.tryParse('1.1.2+9')!;

  group('versiones', () {
    test('mayor, igual y menor', () async {
      Future<ReleaseInfo?> run(String tag) => UpdateService(
        store: _Store(),
        transport: _Fake((_, _) => _ok(_release(tag), h: {'etag': 'x'})),
      ).check(v);
      expect(await run('v1.2.0'), isNotNull);
      expect(await run('1.1.2'), isNull);
      expect(await run('v1.1.1'), isNull);
    });

    test(
      'pre-release e ignorado salvo canal beta; borrador siempre ignorado',
      () async {
        final list = jsonEncode([
          jsonDecode(_release('v2.0.0-beta.1', pre: true)),
          jsonDecode(_release('v3.0.0', draft: true)),
          jsonDecode(_release('v1.5.0')),
        ]);
        Future<ReleaseInfo?> run(bool beta) => UpdateService(
          store: _Store(),
          transport: _Fake((_, _) => _ok(list, h: {'etag': 'x'})),
        ).check(v, beta: beta);
        expect((await run(true))!.tag, 'v2.0.0-beta.1');
        expect((await run(false))!.tag, 'v1.5.0');
        final stable = UpdateService(
          store: _Store(),
          transport: _Fake((_, _) => _ok(_release('v9.0.0', pre: true))),
        );
        expect(await stable.check(v), isNull);
      },
    );

    test('beta es menor que su versión final', () {
      expect(
        SemVer.tryParse('2.0.0-beta.1')!.compareTo(SemVer.tryParse('2.0.0')!),
        lessThan(0),
      );
    });
  });

  test(
    'ETag: la segunda consulta envía If-None-Match y usa la caché en 304',
    () async {
      final store = _Store();
      final fake = _Fake(
        (_, h) => h.containsKey('If-None-Match')
            ? _ok('', status: 304)
            : _ok(_release('v1.2.0'), h: {'etag': '"abc"'}),
      );
      final s = UpdateService(store: store, transport: fake);
      expect(await s.check(v), isNotNull);
      expect(fake.headers[0].containsKey('If-None-Match'), isFalse);
      expect((await s.check(v))!.tag, 'v1.2.0');
      expect(fake.headers[1]['If-None-Match'], '"abc"');
    },
  );

  test('límite de API y falta de red dan mensajes claros', () async {
    final limited = UpdateService(
      store: _Store(),
      transport: _Fake((_, _) => _ok('', status: 403)),
    );
    expect(limited.check(v), throwsA(isA<UpdateException>()));
    final offline = UpdateService(
      store: _Store(),
      transport: _Fake((_, _) => throw const SocketException('x')),
    );
    await expectLater(
      offline.check(v),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'm',
          contains('Sin conexión'),
        ),
      ),
    );
  });

  group('assets', () {
    final r = ReleaseInfo.fromJson(
      jsonDecode(
            _release(
              'v1.2.0',
              assets: [
                'Aurora-Setup-1.2.0.exe',
                'Aurora-1.2.0.apk',
                'Aurora-1.2.0-arm64-v8a.apk',
                'checksums.txt',
              ],
            ),
          )
          as Map<String, dynamic>,
    )!;
    test('Windows elige el instalador', () {
      expect(r.assetFor(windows: true)!.name, 'Aurora-Setup-1.2.0.exe');
    });
    test('Android prefiere la ABI y cae al universal', () {
      expect(
        r.assetFor(windows: false, abis: ['arm64-v8a'])!.name,
        'Aurora-1.2.0-arm64-v8a.apk',
      );
      expect(
        r.assetFor(windows: false, abis: ['x86_64'])!.name,
        'Aurora-1.2.0.apk',
      );
    });
    test('asset faltante', () {
      final none = ReleaseInfo.fromJson(
        jsonDecode(_release('v1.2.0', assets: ['checksums.txt']))
            as Map<String, dynamic>,
      )!;
      expect(none.assetFor(windows: true), isNull);
      expect(none.assetFor(windows: false), isNull);
    });
  });

  group('descarga', () {
    const name = 'Aurora-1.2.0.apk';
    final bytes = utf8.encode('hello');
    final good = sha256.convert(bytes).toString();
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('aurora_upd'));
    tearDown(() => dir.deleteSync(recursive: true));

    ReleaseInfo release() => ReleaseInfo.fromJson(
      jsonDecode(_release('v1.2.0', assets: [name, 'checksums.txt']))
          as Map<String, dynamic>,
    )!;

    test('hash correcto: devuelve el archivo', () async {
      final rel = release();
      final s = UpdateService(
        store: _Store(),
        transport: _Fake(
          (u, _) => u.path.endsWith('checksums.txt')
              ? _ok('$good  $name\n')
              : UpdateResponse(200, {}, Stream.value(bytes)),
        ),
      );
      final f = await s.download(rel, rel.assets.first, dir);
      expect(f.readAsBytesSync(), bytes);
    });

    test('hash incorrecto: error y se borra el archivo', () async {
      final rel = release();
      final s = UpdateService(
        store: _Store(),
        transport: _Fake(
          (u, _) => u.path.endsWith('checksums.txt')
              ? _ok('${'0' * 64}  $name\n')
              : UpdateResponse(200, {}, Stream.value(bytes)),
        ),
      );
      await expectLater(
        s.download(rel, rel.assets.first, dir),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'm',
            contains('corrupto'),
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('checksums.txt sin la entrada: no instala', () async {
      final rel = release();
      final s = UpdateService(
        store: _Store(),
        transport: _Fake((_, _) => _ok('$good  otro.apk')),
      );
      expect(
        s.download(rel, rel.assets.first, dir),
        throwsA(isA<UpdateException>()),
      );
    });

    test('corte a mitad de descarga y reintento reanuda con Range', () async {
      final rel = release();
      var attempt = 0;
      final s = UpdateService(
        store: _Store(),
        transport: _Fake((u, h) {
          if (u.path.endsWith('checksums.txt')) return _ok('$good  $name');
          if (attempt++ == 0) {
            final c = StreamController<List<int>>();
            c.add(bytes.sublist(0, 2));
            c.addError(const SocketException('corte'));
            c.close();
            return UpdateResponse(200, {}, c.stream);
          }
          expect(h['Range'], 'bytes=2-');
          return UpdateResponse(206, {}, Stream.value(bytes.sublist(2)));
        }),
      );
      await expectLater(
        s.download(rel, rel.assets.first, dir),
        throwsA(isA<UpdateException>()),
      );
      final f = await s.download(rel, rel.assets.first, dir);
      expect(f.readAsBytesSync(), bytes);
    });
  });

  test('solo HTTPS y hosts de GitHub', () {
    expect(
      () => checkUpdateUrl(Uri.parse('http://github.com/x')),
      throwsA(isA<UpdateException>()),
    );
    expect(
      () => checkUpdateUrl(Uri.parse('https://evil.example/x')),
      throwsA(isA<UpdateException>()),
    );
    checkUpdateUrl(Uri.parse('https://objects.githubusercontent.com/x'));
  });
}
