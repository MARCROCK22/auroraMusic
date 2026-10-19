import 'package:aurora_music/listenbrainz/listen.dart';
import 'package:aurora_music/listenbrainz/listen_storage.dart';
import 'package:aurora_music/listenbrainz/listenbrainz_client.dart';
import 'package:aurora_music/listenbrainz/listenbrainz_service.dart';
import 'package:aurora_music/ui/listenbrainz_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const secret = '11111111-2222-3333-4444-555555555555';

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

Future<(ListenBrainzService, FakeTokenStore)> _service({
  LbResponse response = const LbResponse(
    200,
    '{"valid":true,"user_name":"ana"}',
  ),
  Map<String, Object> prefs = const {},
  bool broken = false,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final store = FakeTokenStore()..broken = broken;
  final service = ListenBrainzService(
    preferences: await SharedPreferences.getInstance(),
    tokenStore: store,
    queueStore: MemoryListenQueueStore(),
    client: ListenBrainzClient(transport: (_) async => response),
  );
  await service.init();
  return (service, store);
}

void main() {
  group('ListenBrainzService', () {
    test('desactivado por defecto y sin token', () async {
      final (s, store) = await _service();
      expect(s.enabled, isFalse);
      expect(s.active, isFalse);
      expect(store.value, isNull);
    });

    test(
      'token válido: se guarda en el almacén seguro y se muestra solo el usuario',
      () async {
        final (s, store) = await _service();
        await s.validateAndSave('  $secret ');
        expect(store.value, secret);
        expect(s.username, 'ana');
        expect(s.message, contains('ana'));
        expect(s.message, isNot(contains(secret)));
        expect(s.enabled, isFalse); // validar no activa nada
        await s.setEnabled(true);
        expect(s.active, isTrue);
      },
    );

    test('token inválido: no se guarda', () async {
      final (s, store) = await _service(response: const LbResponse(401, '{}'));
      await s.validateAndSave(secret);
      expect(store.value, isNull);
      expect(s.status, LbStatus.invalid);
      expect(s.message, isNot(contains(secret)));
    });

    test(
      'sin almacenamiento seguro no se guarda y queda desactivado',
      () async {
        final (s, store) = await _service(broken: true);
        expect(s.secureUnavailable, isTrue);
        await s.validateAndSave(secret);
        expect(store.value, isNull);
        await s.setEnabled(true);
        expect(s.enabled, isFalse);
        expect(s.message ?? '', isNot(contains(secret)));
      },
    );

    test('un fallo al guardar no filtra el token', () async {
      final (s, store) = await _service();
      store.broken = true;
      await s.validateAndSave(secret);
      expect(s.status, LbStatus.error);
      expect(s.message, isNot(contains(secret)));
    });

    test('cerrar sesión borra token, usuario, interruptor y cola', () async {
      final (s, store) = await _service();
      await s.validateAndSave(secret);
      await s.setEnabled(true);
      await s.signOut();
      expect(store.value, isNull);
      expect(s.username, isNull);
      expect(s.enabled, isFalse);
      expect(s.pending, 0);
      expect(await s.freshReleases(), isEmpty);
    });

    test('freshReleases solo con ListenBrainz activo y con caché', () async {
      var calls = 0;
      SharedPreferences.setMockInitialValues({});
      final s = ListenBrainzService(
        preferences: await SharedPreferences.getInstance(),
        tokenStore: FakeTokenStore(),
        queueStore: MemoryListenQueueStore(),
        client: ListenBrainzClient(
          transport: (r) async {
            if (r.uri.path.endsWith('validate-token')) {
              return const LbResponse(200, '{"valid":true,"user_name":"ana"}');
            }
            calls++;
            return const LbResponse(
              200,
              '{"payload":{"releases":[{"artist_credit_name":"A","release_name":"R"}]}}',
            );
          },
        ),
      );
      await s.init();
      expect(await s.freshReleases(), isEmpty);
      expect(calls, 0);
      await s.validateAndSave(secret);
      await s.setEnabled(true);
      expect((await s.freshReleases()).single.title, 'R');
      await s.freshReleases();
      expect(calls, 1);
    });
  });

  group('ListenBrainzSettingsPanel', () {
    Future<void> pump(
      WidgetTester tester,
      ListenBrainzService s,
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
                child: ListenBrainzSettingsPanel(service: s),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('campo oculto, validar y cerrar sesión', (tester) async {
      final (s, store) = (await tester.runAsync(_service))!;
      await pump(tester, s, const Size(500, 900), 1);
      expect(find.textContaining('públicos'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );

      await tester.enterText(find.byType(TextField), secret);
      await tester.tap(find.text('Validar'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(store.value, secret);
      expect(find.textContaining('ana'), findsWidgets);
      expect(find.textContaining(secret), findsNothing);
      expect(find.byType(TextField), findsNothing); // el token ya no se muestra

      await tester.tap(find.textContaining('Cerrar sesión'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(store.value, isNull);
      expect(find.byType(TextField), findsOneWidget);
    });

    for (final size in const [
      Size(320, 640),
      Size(500, 800),
      Size(1400, 900),
    ]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('sin desbordes a ${size.width.toInt()} px, texto x$scale', (
          tester,
        ) async {
          final (s, _) = (await tester.runAsync(_service))!;
          await pump(tester, s, size, scale);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() => s.validateAndSave(secret));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('causas de «no llega nada»', () {
    test(
      'validar guarda el token pero deja el interruptor apagado y avisa',
      () async {
        final (s, _) = await _service();
        await s.validateAndSave(secret);
        expect(s.hasToken, isTrue);
        expect(s.enabled, isFalse);
        expect(s.needsEnable, isTrue);
        expect(s.message, contains('Activa'));
        expect(s.scrobbler.enabled, isFalse);
        await s.setEnabled(true);
        expect(s.needsEnable, isFalse);
        expect(s.scrobbler.enabled, isTrue);
      },
    );

    test(
      'Probar conexión: token rechazado se refleja sin mostrar el token',
      () async {
        final (s, store) = await _service(
          response: const LbResponse(401, '{"code":401}'),
        );
        store.value = secret;
        await s.init();
        await s.testConnection();
        expect(s.status, LbStatus.invalid);
        expect(s.message, contains('rechaz'));
        expect(s.message, isNot(contains(secret)));
      },
    );

    test(
      'Probar conexión correcta avisa si el interruptor está apagado',
      () async {
        final (s, store) = await _service();
        store.value = secret;
        await s.init();
        await s.testConnection();
        expect(s.status, LbStatus.ok);
        expect(s.message, contains('apagado'));
      },
    );

    test('fallo al leer el token en el envío avisa en vez de callar', () async {
      SharedPreferences.setMockInitialValues({
        'listenbrainz.enabled': true,
        'listenbrainz.user': 'ana',
      });
      final store = FakeTokenStore()..value = secret;
      final s = ListenBrainzService(
        preferences: await SharedPreferences.getInstance(),
        tokenStore: store,
        queueStore: MemoryListenQueueStore()
          ..saved = [
            const Listen(artist: 'A', title: 'T', listenedAt: 1700000000),
          ],
        client: ListenBrainzClient(
          transport: (_) async => const LbResponse(500, '{}'),
        ),
      );
      await s.init();
      await pumpEventQueue();
      expect(s.scrobbler.pending, 1);
      store.broken = true;
      await s.scrobbler.flush();
      expect(s.secureUnavailable, isTrue);
      expect(s.status, LbStatus.error);
    });
  });
}
