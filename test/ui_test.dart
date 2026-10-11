import 'dart:async';
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

  testWidgets(
    'typing and repeated submission cannot duplicate a pending YouTube search',
    (tester) async {
      await mount(tester, const Size(800, 900));
      await tester.tap(find.byTooltip('Buscar música'));
      await tester.pumpAndSettle();
      final source = controller.source as FakeSource;
      source.pendingSearch = Completer<List<Track>>();
      await tester.enterText(find.byType(TextField), 'Me at the zoo');
      await tester.pump(const Duration(seconds: 1));
      expect(source.searchQueries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(source.searchQueries, ['Me at the zoo']);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.searching, isTrue);
      expect(source.searchQueries, ['Me at the zoo']);
      source.pendingSearch!.complete([controller.tracks.first]);
      await tester.pumpAndSettle();
      expect(controller.searching, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(800, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('Navigation works without overflow at ${size.width} dp', (
      tester,
    ) async {
      await mount(tester, size);
      expect(find.text('Inicio').first, findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width >= 600) {
        await tester.tap(find.byTooltip('Buscar música'));
      } else {
        await tester.tap(find.byTooltip('Buscar').last);
      }
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 320) {
        await tester.enterText(find.byType(TextField), 'sin coincidencias');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Sin resultados'), findsOneWidget);
        controller.searchResults = [controller.tracks.first];
        controller.clearError();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'ab');
        await tester.pumpAndSettle();
        expect(controller.searchResults, [controller.tracks.first]);
        expect(find.text(controller.tracks.first.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('600px-high desktop navigation stays scroll-safe and routes', (
    tester,
  ) async {
    await mount(tester, const Size(1100, 600));
    expect(tester.takeException(), isNull);
    for (final destination in [
      'Buscar',
      'Biblioteca',
      'Descargas locales',
      'Modo Vinilo',
      'Cola de reproducción',
      'Ajustes',
    ]) {
      await tester.tap(find.byTooltip(destination).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: destination);
    }
    await tester.tap(find.byTooltip('Letras').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cerrar letras'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar letras'));
    await tester.pumpAndSettle();
    expect(find.text('Hola de nuevo'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile navigation has four destinations and settings shortcut', (
    tester,
  ) async {
    await mount(tester, const Size(320, 700), scale: 2);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Modo Vinilo'), findsOneWidget);
    expect(find.text('Cola de reproducción'), findsOneWidget);
    expect(find.text('Letras'), findsOneWidget);
    await tester.tap(find.text('Modo Vinilo'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cola de reproducción'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('No hay canciones en la cola'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    expect(find.text('No hay canciones en la cola'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letras'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cerrar letras'), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar letras'));
    await tester.pumpAndSettle();
    expect(find.text('Hola de nuevo'), findsOneWidget);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Almacenamiento y biblioteca'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('200 percent text remains usable on a narrow screen', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.toggleFavorite(
        controller.tracks.firstWhere((track) => track.id == 'one'),
      ),
    );
    await mount(tester, const Size(320, 800), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.library_music_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Me gusta'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Una canción con un título muy largo para comprobar la interfaz',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Descargas locales').last);
    await tester.pumpAndSettle();
    expect(find.text('Carpeta de descargas'), findsOneWidget);
    final downloadsScroll = find.byType(ListView).first;
    await tester.dragUntilVisible(
      find.text('Cambiar carpeta'),
      downloadsScroll,
      const Offset(0, -240),
    );
    expect(find.text('Cambiar carpeta'), findsOneWidget);
    expect(find.text('Abrir carpeta'), findsOneWidget);
    expect(find.text(controller.downloadsDirectoryPath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Deleting a completed download requires confirmation and keeps collections',
    (tester) async {
      late File file;
      late DownloadJob job;
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
        job = DownloadJob(
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
      await tester.tap(find.byTooltip('Descargas locales').last);
      await tester.pumpAndSettle();
      final deleteDownload = find.byTooltip('Eliminar archivo descargado');
      await tester.dragUntilVisible(
        deleteDownload,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(deleteDownload);
      await tester.pumpAndSettle();
      await tester.tap(deleteDownload);
      await tester.pumpAndSettle();
      expect(find.text('Eliminar descarga'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(file.exists), isTrue);
      expect(controller.downloads, hasLength(1));
      await tester.dragUntilVisible(
        deleteDownload,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(deleteDownload);
      await tester.pumpAndSettle();
      await tester.tap(deleteDownload);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Eliminar archivo'));
      await tester.runAsync(() => tester.tap(find.text('Eliminar archivo')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.removeDownload(job));
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
        find.text('Sesión de YouTube opcional sin importar'),
        settingsScroll,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Sesión de YouTube opcional sin importar'),
        findsOneWidget,
      );
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
      expect(find.textContaining('ni errores 429.'), findsOneWidget);
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
        find.text('Sesión de YouTube configurada'),
        settingsScroll,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sesión de YouTube configurada'), findsOneWidget);
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

  testWidgets(
    'Biblioteca shows only Likes and user playlists with their own members',
    (tester) async {
      final extraTracks = List.generate(
        24,
        (index) => Track(
          id: 'catalog-$index',
          title: 'Catálogo $index',
          artist: 'Aurora',
          pageUrl: 'https://www.youtube.com/watch?v=catalog$index',
          duration: const Duration(minutes: 3),
        ),
      );
      controller.tracks.addAll(extraTracks);
      await tester.runAsync(() async {
        await controller.toggleFavorite(controller.tracks.first);
        await controller.createPlaylist('Mi lista');
        await controller.addToPlaylist(
          controller.playlists.single,
          controller.tracks[1],
        );
      });
      await mount(tester, const Size(320, 800));
      await tester.tap(find.byIcon(Icons.library_music_outlined).last);
      await tester.pumpAndSettle();

      expect(find.text('Me gusta'), findsOneWidget);
      expect(find.text('Mi lista'), findsOneWidget);
      expect(find.text('Catálogo 0'), findsNothing);
      expect(find.text('Catálogo 23'), findsNothing);

      await tester.tap(find.text('Me gusta'));
      await tester.pumpAndSettle();
      expect(find.text(controller.tracks.first.title), findsOneWidget);
      expect(find.text(controller.tracks[1].title), findsNothing);
      expect(find.text('Catálogo 0'), findsNothing);

      await tester.tap(find.text('Todas las listas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi lista'));
      await tester.pumpAndSettle();
      expect(find.text(controller.tracks[1].title), findsOneWidget);
      expect(find.text(controller.tracks.first.title), findsNothing);
      expect(find.text('Catálogo 0'), findsNothing);
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
    await tester.scrollUntilVisible(
      find.text('Nombre anterior'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
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
    expect(find.byTooltip('Letras'), findsNWidgets(2));
    final lyricsButton = find.byTooltip('Letras').last;
    await tester.ensureVisible(lyricsButton);
    await tester.tap(lyricsButton);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Letras').last, findsOneWidget);
    expect(find.byTooltip('Cerrar letras'), findsOneWidget);
    final closeLyrics = find.byTooltip('Cerrar letras');
    await tester.ensureVisible(closeLyrics);
    await tester.tap(closeLyrics);
    await tester.pumpAndSettle();
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
