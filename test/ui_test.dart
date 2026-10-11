import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';

import 'support/fakes.dart';

void main() {
  late AppController controller;
  late ProviderContainer container;
  late _TrackingAudio audio;

  setUp(() async {
    audio = _TrackingAudio();
    controller = await createTestController(
      audio: audio,
      tracks: const [
        Track(
          id: 'one',
          title:
              'Una canción con un título muy largo para comprobar la interfaz',
          artist: 'Un artista con un nombre largo',
          pageUrl: 'https://www.youtube.com/watch?v=test-one',
          duration: Duration(minutes: 4),
        ),
        Track(
          id: 'two',
          title: 'Otra canción',
          artist: 'Aurora',
          pageUrl: 'https://www.youtube.com/watch?v=test-two',
          duration: Duration(minutes: 3),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => controller)],
    );
  });

  tearDown(() async {
    container.dispose();
    await controller.database.close();
    if (await controller.supportDirectory.exists()) {
      await controller.supportDirectory.delete(recursive: true);
    }
  });

  Future<void> mount(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: const AuroraApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 700),
    const Size(800, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('Navigation works without overflow at ${size.width} dp', (
      tester,
    ) async {
      await mount(tester, size);
      expect(
        find.text('La música cambia.\nTu espacio también.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (size.width < 600) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Encontrar música'));
      await tester.tap(find.text('Encontrar música'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 320) {
        await tester.enterText(find.byType(TextField), 'sin coincidencias');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pumpAndSettle();
        expect(find.text('Sin resultados'), findsOneWidget);
        controller.searchResults = [controller.tracks.first];
        controller.clearError();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'ab');
        await tester.pumpAndSettle();
        expect(controller.searchResults, isEmpty);
        expect(find.text('Encuentra algo que te mueva'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('200 percent text remains usable on a narrow screen', (
    tester,
  ) async {
    await mount(tester, const Size(320, 800), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.library_music_outlined).last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Una canción con un título muy largo para comprobar la interfaz',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.download_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Música que te acompaña sin conexión'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Deleting a completed download requires confirmation and keeps collections',
    (tester) async {
      late File file;
      await tester.runAsync(() async {
        final directory = Directory(
          p.join(controller.supportDirectory.path, 'downloads'),
        );
        await directory.create(recursive: true);
        file = File(p.join(directory.path, 'one.mp3'));
        await file.writeAsBytes([1, 2, 3]);
        final track = controller.tracks
            .firstWhere((track) => track.id == 'one')
            .copyWith(localPath: file.path);
        final job = DownloadJob(
          id: 'download-one',
          track: track,
          status: DownloadStatus.completed,
          progress: 1,
          localPath: file.path,
        );
        await controller.database.saveDownload(job);
        controller.downloads.add(job);
        await controller.toggleFavorite(track);
        await controller.createPlaylist('Mi lista');
        await controller.addToPlaylist(controller.playlists.single, track);
      });
      await mount(tester, const Size(320, 800), scale: 2);
      await tester.tap(find.byIcon(Icons.download_outlined).last);
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => tester.tap(find.byTooltip('Eliminar archivo descargado')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar descarga'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(file.exists), isTrue);
      expect(controller.downloads, hasLength(1));
      await tester.runAsync(
        () => tester.tap(find.byTooltip('Eliminar archivo descargado')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Eliminar archivo'));
      await tester.runAsync(() => tester.tap(find.text('Eliminar archivo')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(await tester.runAsync(file.exists), isFalse);
      expect(controller.downloads, isEmpty);
      expect(controller.favoriteIds, contains('one'));
      expect(controller.playlists.single.trackIds, contains('one'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'YouTube session settings explain local import and disable controls while busy',
    (tester) async {
      await mount(tester, const Size(320, 800), scale: 2);
      await tester.tap(find.byIcon(Icons.tune).last);
      await tester.pumpAndSettle();
      final settingsScroll = find.byType(ListView).first;
      await tester.dragUntilVisible(
        find.text('Sin sesión importada'),
        settingsScroll,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin sesión importada'), findsOneWidget);
      await tester.dragUntilVisible(
        find.textContaining('cookies.txt en formato Netscape'),
        settingsScroll,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar sesión'), findsNothing);
      expect(
        find.textContaining('cookies.txt en formato Netscape'),
        findsOneWidget,
      );
      expect(
        find.textContaining('No garantiza resolver los límites de la red.'),
        findsOneWidget,
      );
      await tester.dragUntilVisible(
        find.text('Importar sesión'),
        settingsScroll,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.sessionBusy = true;
      controller.clearError();
      await tester.pumpAndSettle();
      final busyButton = find.ancestor(
        of: find.text('Procesando sesión…'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(busyButton).onPressed, isNull);
      expect(tester.takeException(), isNull);
      controller.sessionBusy = false;
      late File exported;
      await tester.runAsync(() async {
        exported = File(
          p.join(controller.supportDirectory.path, 'exported-cookies.txt'),
        );
        await exported.writeAsString(
          '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t2147483647\tTEST\texample\n',
        );
        await controller.configureYouTubeSession(exported);
      });
      await tester.pumpAndSettle();
      final localCopy = File(controller.source.cookieFile!);
      await tester.dragUntilVisible(
        find.text('Sesión configurada en este dispositivo'),
        settingsScroll,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Sesión configurada en este dispositivo'),
        findsOneWidget,
      );
      await tester.dragUntilVisible(
        find.text('Reemplazar sesión'),
        settingsScroll,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar sesión'), findsOneWidget);
      expect(find.textContaining(localCopy.path), findsNothing);
      controller.sessionBusy = true;
      controller.clearError();
      await tester.pumpAndSettle();
      final deleteButton = find.ancestor(
        of: find.text('Eliminar sesión'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      expect(tester.widget<TextButton>(deleteButton).onPressed, isNull);
      controller.sessionBusy = false;
      controller.clearError();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Eliminar sesión'));
        for (
          var attempt = 0;
          attempt < 200 && controller.sessionBusy;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.hasYouTubeSession, isFalse);
      expect(await tester.runAsync(localCopy.exists), isFalse);
      expect(await tester.runAsync(exported.exists), isTrue);
      expect(find.text('Eliminar sesión'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Selected playlist header follows renames', (tester) async {
    await tester.runAsync(() => controller.createPlaylist('Nombre anterior'));
    final selected = controller.playlists.single;
    await mount(tester, const Size(320, 800), scale: 2);
    await tester.tap(find.byIcon(Icons.library_music_outlined).last);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.widgetWithText(ChoiceChip, 'Listas')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Listas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre anterior'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => controller.renamePlaylist(selected, 'Nombre actualizado'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('Nombre anterior'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Queue duplicate songs keep distinct keys and select the tapped occurrence',
    (tester) async {
      final one = controller.tracks.firstWhere((track) => track.id == 'one');
      final two = controller.tracks.firstWhere((track) => track.id == 'two');
      await tester.runAsync(
        () => controller.playTrack(one, context: [one, two, one]),
      );
      await mount(tester, const Size(320, 800));
      await tester.tap(find.byType(Artwork).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cola de reproducción'));
      await tester.pumpAndSettle();
      final rows = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(ListTile),
      );
      expect(rows, findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await tester.tap(rows.at(2));
        for (var attempt = 0; attempt < 200 && controller.busy; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(controller.busy, isFalse);
      await tester.pumpAndSettle();
      expect(controller.queueIndex, 2);
      expect(controller.queue.map((track) => track.id), ['one', 'two', 'one']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Full player, queue and real EQ bands fit a narrow screen', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.playTrack(
        controller.tracks.first,
        context: controller.tracks,
      ),
    );
    await mount(tester, const Size(320, 800), scale: 2);
    expect(audio.analysisEnabled, isFalse);
    await tester.tap(find.text(controller.currentTrack!.title).first);
    await tester.pumpAndSettle();
    expect(find.text('AHORA SUENA'), findsOneWidget);
    expect(audio.analysisEnabled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(audio.analysisEnabled, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(audio.analysisEnabled, isTrue);
    controller.setReducedMotion(true);
    await tester.pumpAndSettle();
    expect(audio.analysisEnabled, isFalse);
    controller.setReducedMotion(false);
    await tester.pumpAndSettle();
    expect(audio.analysisEnabled, isTrue);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -650),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ecualizador'));
    await tester.pumpAndSettle();
    expect(find.text('375 Hz'), findsOneWidget);
    expect(find.text('24k'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar ecualizador'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, 1000),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cola de reproducción'));
    await tester.pumpAndSettle();
    expect(find.text('A continuación'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _TrackingAudio extends FakeAudio {
  bool analysisEnabled = true;
  @override
  void setVisualizationEnabled(bool enabled) => analysisEnabled = enabled;
}
