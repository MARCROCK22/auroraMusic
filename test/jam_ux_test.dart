import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/ui/jam/jam_add_sheet.dart';
import 'package:aurora_music/ui/jam/jam_session_panel.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'support/fakes.dart';

const _song = Track(id: 'song', title: 'Canción base', artist: 'Artista');

JamTrack _jt(String id, String title, String artist) =>
    JamTrack.fromTrack(Track(id: id, title: title, artist: artist));

/// Jam en memoria: sin red ni transporte. [host] decide el rol local.
JamController _jam(AppController app, {required bool host}) {
  final jam = JamController(app: app);
  final s = jam.service;
  s.connection = host ? JamConnection.hosting : JamConnection.connected;
  s.participantId = host ? 'host' : 'guest';
  s.participants = [
    const JamParticipant(
      id: 'host',
      name: 'Lucía',
      role: JamRole.host,
      permissions: JamPermissions.all,
    ),
    const JamParticipant(id: 'guest', name: 'Beto'),
  ];
  s.mode = JamMode.synchronized;
  s.queue = [
    JamQueueEntry(
      id: 'q1',
      track: _jt('a', 'Tema uno', 'Artista A'),
      addedBy: 'host',
    ),
    JamQueueEntry(
      id: 'q2',
      track: _jt('b', 'Tema dos', 'Artista B'),
      addedBy: 'guest',
      status: JamEntryStatus.suggested,
      suggestedFor: 'guest',
    ),
  ];
  return jam;
}

Future<AppController> _app(WidgetTester tester) async {
  final app = (await tester.runAsync(
    () => createTestController(
      tracks: [_song],
      playlists: [
        const MusicPlaylist(id: 'p', name: 'Mi playlist', trackIds: ['song']),
      ],
    ),
  ))!;
  addTearDown(() => closeTestController(app));
  return app;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _transport(AppController app, JamController jam) => _host(
  Align(
    alignment: Alignment.bottomCenter,
    child: StudioTransport(
      controller: app,
      jam: jam,
      onLyrics: () {},
      onVinyl: () {},
      onQueue: () {},
      onOpenPlayer: () {},
      onJam: () {},
      onStartJam: () {},
    ),
  ),
);

void main() {
  testWidgets(
    'barra: píldora con personas, rol y modo; sin Jam solo el botón',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await _app(tester);
      final guest = _jam(app, host: false);
      await tester.pumpWidget(_transport(app, guest));
      expect(find.text('Jam · 2 · Invitado'), findsOneWidget);
      tester.view.physicalSize = const Size(1700, 900);
      await tester.pumpWidget(_transport(app, guest));
      expect(find.text('Jam · 2 personas'), findsOneWidget);
      expect(find.text('Invitado · Escuchando'), findsOneWidget);
      final idle = JamController(app: app);
      await tester.pumpWidget(_transport(app, idle));
      expect(find.byTooltip('Iniciar una Jam'), findsOneWidget);
      expect(find.textContaining('Jam ·'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('barra: invitado sin permiso ve play/siguiente atenuados', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await _app(tester);
    await tester.runAsync(app.beginJamPlayback);
    final guest = _jam(app, host: false)
      ..service.rules = const JamRules(votes: false);
    guest.service.playback = const JamPlayback(
      sequence: 1,
      serverTimeMs: 0,
      entryId: 'q1',
      isPlaying: true,
    );
    await tester.pumpWidget(_transport(app, guest));
    final play = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Lo controla Lucía').first,
        matching: find.byType(IconButton),
      ),
    );
    expect(play.onPressed, isNull);
    expect(find.byTooltip('Lo controla Lucía'), findsWidgets);
    // El anfitrión sí puede.
    final host = _jam(app, host: true);
    await tester.pumpWidget(_transport(app, host));
    expect(find.byTooltip('Lo controla Lucía'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('panel: invitado no ve ajustes; host sí; "Sugerida para"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await _app(tester);
    final guest = _jam(app, host: false);
    await tester.pumpWidget(_host(JamSessionPanel(controller: guest)));
    expect(find.text('Ajustes de la Jam'), findsNothing);
    expect(find.text('Sugerida para Beto'), findsOneWidget);
    expect(find.text('Salir de la Jam'), findsOneWidget);
    final host = _jam(app, host: true);
    await tester.pumpWidget(_host(JamSessionPanel(controller: host)));
    expect(find.text('Ajustes de la Jam'), findsOneWidget);
    for (final label in [
      'Permitir que otros cambien lo que suena',
      'Aprobar sugerencias',
      'Votos',
      'Autoplay de la Jam',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Terminar la Jam'), findsOneWidget);
    expect(find.byTooltip('Acciones para Beto'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hoja Añadir: recomendado con 1 toque y playlists por rol', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = await _app(tester);
    final host = _jam(app, host: true);
    await tester.pumpWidget(_host(JamAddSheet(jam: host)));
    await tester.pump();
    expect(find.text('Tema dos'), findsOneWidget);
    expect(find.textContaining('Sugerida para Beto'), findsOneWidget);
    await tester.tap(find.text('Mis playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir al final'), findsOneWidget);
    expect(find.text('Reproducir ahora'), findsOneWidget);
    expect(find.text('Mezclar'), findsOneWidget);
    // Un invitado no puede forzar «Reproducir ahora».
    final guest = _jam(app, host: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(JamAddSheet(jam: guest)));
    await tester.pump();
    await tester.tap(find.text('Mis playlists'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mi playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Reproducir ahora'), findsNothing);
    expect(find.text('Mezclar'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
