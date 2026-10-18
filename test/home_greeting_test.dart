import 'package:aurora_music/ui/studio/home_introduction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => studioClock = DateTime.now);

  test('el título cambia con la hora y cubre las 24 horas', () {
    String at(int h) => studioGreeting(DateTime(2026, 10, 18, h));
    expect(at(0), 'Madrugada acústica');
    expect(at(4), 'Madrugada acústica');
    expect(at(5), 'Amanecer sonoro');
    expect(at(7), 'Amanecer sonoro');
    expect(at(8), 'Mañana en calma');
    expect(at(11), 'Mañana en calma');
    expect(at(12), 'Mediodía de vinilo');
    expect(at(14), 'Mediodía de vinilo');
    expect(at(15), 'Tarde en cinta');
    expect(at(18), 'Tarde en cinta');
    expect(at(19), 'Anochecer cálido');
    expect(at(21), 'Anochecer cálido');
    expect(at(22), 'Noche de válvulas');
    expect(at(23), 'Noche de válvulas');
    for (var h = 0; h < 24; h++) {
      expect(at(h), isNotEmpty);
    }
  });

  testWidgets('la portada actualiza el título al cambiar la hora', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 18, 4, 59);
    studioClock = () => now;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 900, child: StudioGreetingRow()),
          ),
        ),
      ),
    );
    expect(find.text('Madrugada acústica'), findsOneWidget);
    now = DateTime(2026, 10, 18, 5, 1);
    await tester.pump(const Duration(seconds: 21));
    expect(find.text('Amanecer sonoro'), findsOneWidget);
    expect(find.text('Madrugada acústica'), findsNothing);
  });
}
