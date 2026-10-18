import 'dart:async';
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/ui/lyrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _a = Track(id: 'a', artist: 'Artista A', title: 'Tema uno');
const _b = Track(id: 'b', artist: 'Artista B', title: 'Tema dos');

class _Lyrics extends LyricsService {
  final loads = <String>[];
  final pending = <String, Completer<LyricsResult>>{};
  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) {
    loads.add(track.id);
    return (pending[track.id] ??= Completer<LyricsResult>()).future;
  }
}

JamController _guest(AppController app) {
  final jam = JamController(app: app);
  final s = jam.service
    ..connection = JamConnection.connected
    ..participantId = 'guest'
    ..participants = const [
      JamParticipant(
        id: 'host',
        name: 'Lucía',
        role: JamRole.host,
        permissions: JamPermissions.all,
      ),
      JamParticipant(id: 'guest', name: 'Beto'),
    ]
    ..rules = const JamRules(votes: false);
  s.queue = [
    JamQueueEntry(id: 'q1', track: JamTrack.fromTrack(_a), addedBy: 'host'),
  ];
  return jam;
}

void main() {
  late AppController app;
  late _Lyrics service;

  setUp(() async {
    app = await createTestController(tracks: [_a, _b]);
    app.queue = [_a, _b];
    app.queueIndex = 0;
    service = _Lyrics();
  });
  tearDown(() async {
    await closeTestController(app);
    service.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 360,
    double scale = 1,
    double height = 700,
    JamController? jam,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: LyricsPanel(controller: app, service: service, jam: jam),
        ),
      ),
    );
    app.notifyListeners();
    await tester.pump();
  }

  LyricsResult synced() => LyricsResult(
    LyricsKind.synced,
    lines: [
      for (var i = 0; i < 60; i++) LyricLine(Duration(seconds: i), 'v$i'),
    ],
    source: 't',
  );

  testWidgets('Siguiente cambia la pista y reinicia letra y scroll', (
    tester,
  ) async {
    await mount(tester);
    (service.pending['a'] ??= Completer()).complete(synced());
    await tester.pump();
    await tester.pump();
    expect(find.text('v0'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pump();
    expect(find.text('v0'), findsNothing);

    await tester.tap(find.byTooltip('Siguiente'));
    await tester.pump();
    await tester.pump();
    expect(app.currentTrack?.id, 'b');
    expect(service.loads.last, 'b');
    expect(find.text('Buscando letra…'), findsOneWidget);
    expect(find.text('v0'), findsNothing);
    (service.pending['b'] ??= Completer()).complete(synced());
    await tester.pump();
    await tester.pump();
    expect(find.text('v0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Anterior y Pausa llaman al controlador', (tester) async {
    await mount(tester);
    app.queueIndex = 1;
    app.notifyListeners();
    await tester.pump();
    await tester.tap(find.byTooltip('Anterior'));
    await tester.pump();
    expect(app.currentTrack?.id, 'a');
    final audio = app.audio as FakeAudio..isPlaying = true;
    audio.notifyListeners();
    await tester.pump();
    await tester.tap(find.byTooltip('Pausar'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(audio.isPlaying, isFalse);
  });

  testWidgets('Jam sin permiso: botones atenuados con el anfitrión', (
    tester,
  ) async {
    await tester.runAsync(app.beginJamPlayback);
    await mount(tester, jam: _guest(app));
    expect(find.byTooltip('Lo controla Lucía'), findsNWidgets(2));
    expect(find.byTooltip('No disponible en una Jam'), findsOneWidget);
    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((b) => b.tooltip?.startsWith('Lo controla') ?? false);
    expect(buttons, isNotEmpty);
    expect(buttons.every((b) => b.onPressed == null), isTrue);
  });

  for (final w in [320.0, 500.0, 1400.0]) {
    testWidgets('sin overflow a ${w.toInt()} px y texto al 200 %', (
      tester,
    ) async {
      await mount(tester, width: w, scale: 2, height: w > 900 ? 1000 : 700);
      expect(find.byTooltip('Siguiente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
