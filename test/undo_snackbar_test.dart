import 'package:aurora_music/ui/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('snackbar with action auto-dismisses and action works', (
    tester,
  ) async {
    var undone = 0;
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    void show() => showUndoSnackBar(
      ScaffoldMessenger.of(ctx),
      const Text('Añadida'),
      label: 'Deshacer',
      onAction: () => undone++,
    );

    show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Deshacer'));
    expect(undone, 1);

    await tester
        .pumpAndSettle(); // deja cerrar el primero antes de mostrar el 2.º
    show();
    await tester.pump();
    await tester.pump(
      const Duration(seconds: 7),
    ); // entra y arranca el temporizador
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Añadida'), findsNothing);
  });
}
