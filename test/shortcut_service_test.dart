import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aurora_music/shortcuts/shortcut_host.dart';
import 'package:aurora_music/shortcuts/shortcut_service.dart';

Future<ShortcutService> make([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return ShortcutService(await SharedPreferences.getInstance());
}

void main() {
  test('defaults sin conflictos ni reservados', () async {
    final s = await make();
    for (final id in ShortcutId.values) {
      expect(
        ShortcutService.isReserved(s.activatorOf(id)),
        isFalse,
        reason: '$id',
      );
      expect(
        s.conflictOf(s.activatorOf(id), except: id),
        isNull,
        reason: '$id',
      );
    }
  });

  test('rechaza reservados y conflictos', () async {
    final s = await make();
    expect(
      s.assign(
        ShortcutId.mute,
        const SingleActivator(LogicalKeyboardKey.f4, alt: true),
      ),
      isNotNull,
    );
    expect(
      s.assign(
        ShortcutId.mute,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true),
      ),
      isNotNull,
    );
    expect(
      s.assign(
        ShortcutId.mute,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
      ),
      isNotNull,
    );
    expect(
      s.assign(
        ShortcutId.mute,
        const SingleActivator(LogicalKeyboardKey.space),
      ),
      contains('Reproducir'),
    );
  });

  test('persiste, exporta, importa y restablece', () async {
    final s = await make();
    const a = SingleActivator(
      LogicalKeyboardKey.keyU,
      control: true,
      shift: true,
    );
    expect(s.assign(ShortcutId.lyrics, a), isNull);
    final prefs = await SharedPreferences.getInstance();
    final again = ShortcutService(prefs);
    expect(again.labelOf(ShortcutId.lyrics), 'Ctrl+Mayús+U');
    final json = again.exportJson();
    again.resetAll();
    expect(again.labelOf(ShortcutId.lyrics), 'Ctrl+L');
    expect(again.importJson(json), isNull);
    expect(again.labelOf(ShortcutId.lyrics), 'Ctrl+Mayús+U');
    expect(again.importJson('{"mute":{"key":1}}'), isNotNull);
    expect(again.importJson('basura'), isNotNull);
  });

  testWidgets('Espacio alterna reproducción salvo en un campo de texto', (
    tester,
  ) async {
    final s = await make();
    var plays = 0;
    final field = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShortcutHost(
            service: s,
            onAction: (id) {
              if (id == ShortcutId.playPause) plays++;
            },
            child: Column(
              children: [
                TextField(key: const Key('t'), controller: field),
                const Focus(autofocus: true, child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(plays, 1);
    await tester.tap(find.byKey(const Key('t')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(plays, 1);
  });
}
