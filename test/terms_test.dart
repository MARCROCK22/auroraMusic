import 'package:aurora_music/terms/terms_acceptance.dart';
import 'package:aurora_music/terms/terms_screen.dart';
import 'package:aurora_music/terms/terms_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  group('TermsAcceptance', () {
    test('primera vez: no aceptado', () async {
      expect(TermsAcceptance(await _prefs()).isAccepted, isFalse);
    });

    test('aceptar guarda versión y fecha', () async {
      final prefs = await _prefs();
      await TermsAcceptance(prefs).accept(now: DateTime.utc(2026, 10, 19));
      expect(TermsAcceptance(prefs).isAccepted, isTrue);
      expect(
        prefs.getString(TermsAcceptance.dateKey),
        startsWith('2026-10-19'),
      );
    });

    test('versión distinta vuelve a pedir', () async {
      final prefs = await _prefs();
      await TermsAcceptance(prefs, version: 'viejo').accept();
      expect(TermsAcceptance(prefs).isAccepted, isFalse);
    });

    test('rechazar no persiste nada', () async {
      final prefs = await _prefs();
      TermsAcceptance(prefs); // rechazar = no llamar a accept()
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('texto de los términos', () {
    final all =
        '$kTermsIntro ${kTermsSections.map((s) => '${s.title} ${s.body}').join(' ')}';

    test('quien aceptó la versión anterior vuelve a verlos', () async {
      final prefs = await _prefs({
        TermsAcceptance.versionKey: '2026-10-19',
        TermsAcceptance.dateKey: '2026-10-19T00:00:00.000Z',
      });
      expect(kTermsVersion, isNot('2026-10-19'));
      expect(TermsAcceptance(prefs).isAccepted, isFalse);
    });

    test(
      'explica ListenBrainz: qué se envía, opcional, privacidad y borrado',
      () {
        for (final fragment in [
          'ListenBrainz',
          'MetaBrainz Foundation',
          'desactivado por defecto',
          'tu propio token',
          'artista, título',
          'duración',
          'hora de inicio',
          'públicas en tu perfil',
          'política de privacidad',
          'cerrar sesión',
          'no vende',
          'recomendaciones',
          'busca esas canciones en YouTube',
          'Artistas que sigues',
          'solo en tu dispositivo',
        ]) {
          expect(
            all.toLowerCase(),
            contains(fragment.toLowerCase()),
            reason: fragment,
          );
        }
      },
    );

    test('el texto nunca incluye un token', () {
      expect(
        all,
        isNot(
          matches(
            RegExp(
              r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
            ),
          ),
        ),
      );
    });
  });

  group('TermsScreen', () {
    Future<void> pump(
      WidgetTester tester,
      Size size, {
      double scale = 1,
      VoidCallback? onReject,
      Future<void> Function()? onAccept,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TermsScreen(
            hookWindow: false,
            onAccept: onAccept ?? () async {},
            onReject: onReject ?? () {},
          ),
        ),
      );
    }

    testWidgets('Aceptar y Rechazar llaman a sus callbacks', (tester) async {
      var accepted = 0, rejected = 0;
      await pump(
        tester,
        const Size(500, 800),
        onAccept: () async => accepted++,
        onReject: () => rejected++,
      );
      await tester.tap(find.text('Rechazar'));
      await tester.tap(find.text('Aceptar'));
      expect((accepted, rejected), (1, 1));
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
          await pump(tester, size, scale: scale);
          expect(find.text('Aceptar'), findsOneWidget);
          expect(find.text('Rechazar'), findsOneWidget);
          await tester.drag(find.byType(ListView), const Offset(0, -3000));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
