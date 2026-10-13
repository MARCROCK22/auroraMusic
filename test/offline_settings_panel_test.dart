import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/offline_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

void main() {
  late AppController controller;
  tearDown(() async => closeTestController(controller));
  testWidgets('empty offline settings opens search and download management', (
    tester,
  ) async {
    controller = (await tester.runAsync(() => createTestController()))!;
    var searches = 0, manages = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: SingleChildScrollView(
              child: OfflineSettingsPanel(
                controller: controller,
                onManage: () => manages++,
                onSearch: () => searches++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Descargar una canción'));
    await tester.pumpAndSettle();
    expect(searches, 1);
    expect(controller.downloads, isEmpty);
    await tester.tap(find.text('Gestionar descargas'));
    expect(manages, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('only explicit selection starts an offline download', (
    tester,
  ) async {
    const track = Track(
      id: 'yt:abcdefghijk',
      title: 'Offline fixture',
      artist: 'Test',
      pageUrl: 'https://youtu.be/abcdefghijk',
    );
    controller = (await tester.runAsync(
      () => createTestController(tracks: [track]),
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineSettingsPanel(
            controller: controller,
            onManage: () {},
            onSearch: () {},
          ),
        ),
      ),
    );
    expect(controller.downloads, isEmpty);
    await tester.tap(find.text('Descargar una canción'));
    await tester.pumpAndSettle();
    expect(controller.downloads, isEmpty);
    await tester.runAsync(() => tester.tap(find.text('Offline fixture')));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (controller.downloads.isEmpty ||
          controller.downloads.single.status == DownloadStatus.downloading ||
          controller.downloads.single.status == DownloadStatus.queued) {
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(controller.downloads, hasLength(1));
    expect(controller.downloads.single.track.id, track.id);
    expect(tester.takeException(), isNull);
  });
}
