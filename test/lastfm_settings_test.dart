import 'dart:io';

import 'package:aurora_music/lastfm/listen.dart';
import 'package:aurora_music/lastfm/lastfm_client.dart';
import 'package:aurora_music/lastfm/lastfm_service.dart';
import 'package:aurora_music/lastfm/lastfm_storage.dart';
import 'package:aurora_music/ui/lastfm_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sk = 'sessionkey1234567890abcdef';
const password = 'hunter2-contraseña';

class FakeTokenStore implements TokenStore {
  String? value;
  bool broken = false;
  @override
  Future<String?> read() async {
    if (broken) throw StateError('sin almacén');
    return value;
  }

  @override
  Future<void> write(String token) async {
    if (broken) throw StateError('sin almacén $token');
    value = token;
  }

  @override
  Future<void> delete() async => value = null;
}

Future<(LastfmService, FakeTokenStore)> _service({
  LfmResponse response = const LfmResponse(
    200,
    '{"session":{"name":"ana","key":"$sk"}}',
  ),
  bool broken = false,
  bool configured = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = FakeTokenStore()..broken = broken;
  final service = LastfmService(
    preferences: await SharedPreferences.getInstance(),
    tokenStore: store,
    queueStore: MemoryListenQueueStore(),
    client: LastfmClient(
      apiKey: configured ? 'k' : '',
      secret: configured ? 's' : '',
      transport: (_) async => response,
    ),
  );
  await service.init();
  return (service, store);
}

void main() {
  group('LastfmService', () {
    test('desactivado por defecto y sin sesión', () async {
      final (s, store) = await _service();
      expect(s.enabled, isFalse);
      expect(s.active, isFalse);
      expect(store.value, isNull);
    });

    test('conectar guarda solo la sesión; encender activa', () async {
      final (s, store) = await _service();
      await s.connect(' ana ', password);
      expect(store.value, sk);
      expect(s.username, 'ana');
      expect(s.message, isNot(contains(password)));
      expect(s.enabled, isFalse);
      expect(s.needsEnable, isTrue);
      await s.setEnabled(true);
      expect(s.active, isTrue);
      expect(s.scrobbler.enabled, isTrue);
    });

    test('credenciales incorrectas: no se guarda nada', () async {
      final (s, store) = await _service(
        response: const LfmResponse(
          403,
          '{"error":4,"message":"Invalid authentication"}',
        ),
      );
      await s.connect('ana', password);
      expect(store.value, isNull);
      expect(s.status, LfmStatus.invalid);
      expect(s.message, isNot(contains(password)));
    });

    test('sin claves de compilación no se conecta', () async {
      final (s, store) = await _service(configured: false);
      expect(s.configured, isFalse);
      await s.connect('ana', password);
      expect(store.value, isNull);
      expect(s.message, contains('no está configurado'));
    });

    test('sin almacenamiento seguro no se guarda', () async {
      final (s, store) = await _service(broken: true);
      expect(s.secureUnavailable, isTrue);
      await s.connect('ana', password);
      expect(store.value, isNull);
      await s.setEnabled(true);
      expect(s.enabled, isFalse);
    });

    test('desconectar borra sesión, usuario, interruptor y cola', () async {
      final (s, store) = await _service();
      await s.connect('ana', password);
      await s.setEnabled(true);
      await s.signOut();
      expect(store.value, isNull);
      expect(s.username, isNull);
      expect(s.enabled, isFalse);
      expect(s.pending, 0);
    });

    test('error 9 al enviar desconecta la sesión y conserva la cola', () async {
      SharedPreferences.setMockInitialValues({});
      final store = FakeTokenStore();
      final queue = MemoryListenQueueStore()
        ..saved = [
          const Listen(artist: 'A', title: 'T', listenedAt: 1700000000),
        ];
      final s = LastfmService(
        preferences: await SharedPreferences.getInstance(),
        tokenStore: store,
        queueStore: queue,
        client: LastfmClient(
          apiKey: 'k',
          secret: 's',
          transport: (r) async => r.body!.contains('getMobileSession')
              ? const LfmResponse(200, '{"session":{"name":"ana","key":"$sk"}}')
              : const LfmResponse(
                  403,
                  '{"error":9,"message":"Invalid session key"}',
                ),
        ),
      );
      await s.init();
      await s.connect('ana', password);
      await s.setEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.hasSession, isFalse);
      expect(store.value, isNull);
      expect(s.status, LfmStatus.invalid);
      expect(s.pending, 1);
    });
  });

  group('limpieza de restos anteriores', () {
    test('borra solo las claves del servicio anterior', () async {
      final removed = <String>[];
      await removeLegacyScrobbleData(Directory.systemTemp.createTempSync(), [
        'listenbrainz.enabled',
        'listenbrainz.user',
        'otra.cosa',
      ], (k) async => removed.add(k));
      expect(removed, ['listenbrainz.enabled', 'listenbrainz.user']);
    });
  });

  group('LastfmSettingsPanel', () {
    Future<void> pump(
      WidgetTester tester,
      LastfmService s,
      Size size,
      double scale,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: LastfmSettingsPanel(service: s),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('formulario, conectar, estado y desconectar', (tester) async {
      final (s, store) = (await tester.runAsync(_service))!;
      await pump(tester, s, const Size(500, 900), 1);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(
        tester.widget<EditableText>(find.byType(EditableText).last).obscureText,
        isTrue,
      );
      await tester.enterText(find.byType(TextField).first, 'ana');
      await tester.enterText(find.byType(TextField).last, password);
      await tester.tap(find.text('Conectar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(store.value, sk);
      expect(find.textContaining('ana'), findsWidgets);
      expect(find.textContaining(password), findsNothing);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.textContaining('Desconectar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(store.value, isNull);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('sin claves muestra aviso y no hay formulario', (tester) async {
      final (s, _) = (await tester.runAsync(
        () => _service(configured: false),
      ))!;
      await pump(tester, s, const Size(500, 900), 1);
      expect(
        find.text('Last.fm no está configurado en esta compilación.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    for (final size in const [Size(320, 640), Size(1400, 900)]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('sin desbordes a ${size.width.toInt()} px, texto x$scale', (
          tester,
        ) async {
          final (s, _) = (await tester.runAsync(_service))!;
          await pump(tester, s, size, scale);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() => s.connect('ana', password));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
