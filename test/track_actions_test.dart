import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/shortcuts/shortcut_host.dart';
import 'package:aurora_music/shortcuts/shortcut_service.dart';
import 'package:aurora_music/ui/track_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fakes.dart';

const _a = Track(id: 'a', title: 'Tema A', artist: 'Ana');
const _b = Track(id: 'b', title: 'Tema B', artist: 'Beto');
const _c = Track(id: 'c', title: 'Tema C', artist: 'Cleo');

/// Jam en memoria que registra lo que se le añade (sin red).
class _SpyJam extends JamController {
  _SpyJam(AppController app, {required bool host, bool canAddTracks = true})
    : super(app: app) {
    service.connection = host ? JamConnection.hosting : JamConnection.connected;
    service.participantId = host ? 'host' : 'guest';
    service.participants = [
      const JamParticipant(
        id: 'host',
        name: 'Lucía',
        role: JamRole.host,
        permissions: JamPermissions.all,
      ),
      JamParticipant(
        id: 'guest',
        name: 'Beto',
        permissions: JamPermissions(add: canAddTracks),
      ),
    ];
  }
  final added = <Track>[];
  @override
  bool addTracks(List<Track> tracks, {JamAddMode mode = JamAddMode.end}) {
    if (!canAdd) return super.addTracks(tracks, mode: mode);
    added.addAll(tracks);
    return true;
  }
}

Future<AppController> _app(WidgetTester tester) async {
  final app = (await tester.runAsync(
    () => createTestController(tracks: [_a, _b, _c]),
  ))!;
  addTearDown(() => closeTestController(app));
  return app;
}

Widget _row(AppController app, JamController? jam, {bool batch = false}) =>
    MaterialApp(
      home: Scaffold(
        body: TrackActionsScope(
          jam: jam,
          ensureJam: () => jam ?? JamController(app: app),
          child: Column(
            children: [
              TrackActionsRegion(
                controller: app,
                track: _a,
                builder: (context, hot) => ListTile(
                  title: Text(_a.title),
                  onTap: () {},
                  trailing: TrackMenuButton(
                    controller: app,
                    track: _a,
                    quickAdd: true,
                    quickAddVisible: hot,
                  ),
                ),
              ),
              if (batch)
                TrackBatchButtons(controller: app, tracks: const [_a, _b, _c]),
            ],
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pump();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Opciones de Tema A'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sin Jam: ofrece cola e iniciar Jam, no «Añadir a la Jam»', (
    tester,
  ) async {
    final app = await _app(tester);
    await tester.pumpWidget(_row(app, null));
    await _openMenu(tester);
    expect(find.text('Reproducir a continuación'), findsOneWidget);
    expect(find.text('Añadir a la cola'), findsOneWidget);
    expect(find.text('Iniciar una Jam con esto'), findsOneWidget);
    expect(find.text('Añadir a la Jam'), findsNothing);
    await tester.tap(find.text('Añadir a la cola'));
    await tester.pump();
    await _settle(tester);
    expect(app.queue.map((t) => t.id), ['a']);
    expect(find.text('Añadida a la cola'), findsOneWidget);
    expect(find.text('Deshacer'), findsOneWidget);
  });

  testWidgets('el «+» rápido añade a la cola y Deshacer la quita', (
    tester,
  ) async {
    final app = await _app(tester);
    await tester.pumpWidget(_row(app, null));
    await tester.tap(find.byTooltip('Añadir a la cola'));
    await tester.pump();
    await _settle(tester);
    expect(app.queue.map((t) => t.id), ['a']);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Deshacer'));
    await tester.pump();
    await _settle(tester);
    expect(app.queue, isEmpty);
  });

  testWidgets('con Jam activa: «Añadir a la Jam» llama a addTracks', (
    tester,
  ) async {
    final app = await _app(tester);
    final jam = _SpyJam(app, host: true);
    await tester.pumpWidget(_row(app, jam));
    await _openMenu(tester);
    expect(find.text('Iniciar una Jam con esto'), findsNothing);
    await tester.tap(find.text('Añadir a la Jam'));
    await tester.pump();
    expect(jam.added, [_a]);
    expect(find.text('Añadida a la Jam'), findsOneWidget);
  });

  testWidgets('sin permiso: «Añadir a la Jam» atenuado y sin efecto', (
    tester,
  ) async {
    final app = await _app(tester);
    final jam = _SpyJam(app, host: false, canAddTracks: false);
    await tester.pumpWidget(_row(app, jam));
    await _openMenu(tester);
    final item = tester.widget<PopupMenuItem<VoidCallback>>(
      find.ancestor(
        of: find.text('Añadir a la Jam'),
        matching: find.byType(PopupMenuItem<VoidCallback>),
      ),
    );
    expect(item.enabled, isFalse);
    expect(find.byType(Tooltip), findsWidgets);
    await tester.tap(find.text('Añadir a la Jam'), warnIfMissed: false);
    await tester.pump();
    expect(jam.added, isEmpty);
  });

  testWidgets('«Solo añadir» (invitado con permiso de añadir) puede añadir', (
    tester,
  ) async {
    final app = await _app(tester);
    final jam = _SpyJam(app, host: false);
    await tester.pumpWidget(_row(app, jam));
    await _openMenu(tester);
    await tester.tap(find.text('Añadir a la Jam'));
    await tester.pump();
    expect(jam.added, [_a]);
  });

  testWidgets('clic derecho abre el menú completo', (tester) async {
    final app = await _app(tester);
    await tester.pumpWidget(_row(app, null));
    await tester.tap(find.text('Tema A'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Añadir a la cola'), findsOneWidget);
  });

  testWidgets('añadir todo: cola y Jam por lotes', (tester) async {
    final app = await _app(tester);
    final jam = _SpyJam(app, host: true);
    await tester.pumpWidget(_row(app, jam, batch: true));
    await tester.tap(find.text('Añadir todo a la cola'));
    await tester.pump();
    await _settle(tester);
    expect(app.queue.map((t) => t.id), ['a', 'b', 'c']);
    expect(find.text('Añadidas 3 canciones a la cola'), findsOneWidget);
    await tester.tap(find.text('Añadir todo a la Jam'));
    await tester.pump();
    expect(jam.added.map((t) => t.id), ['a', 'b', 'c']);
  });

  testWidgets('atajo Ctrl+Mayús+A con la fila enfocada añade a la cola', (
    tester,
  ) async {
    final app = await _app(tester);
    SharedPreferences.setMockInitialValues({});
    final service = ShortcutService(await SharedPreferences.getInstance());
    final others = <ShortcutId>[];
    await tester.pumpWidget(
      ShortcutHost(
        service: service,
        onAction: others.add,
        child: _row(app, null),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await _settle(tester);
    expect(app.queue.map((t) => t.id), ['a']);
    expect(others, isEmpty);
  });
}
