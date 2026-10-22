import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/home_music_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in const [Size(1280, 800), Size(390, 800)]) {
    testWidgets('Inicio Slush pinta a ${size.width.toInt()} px', (
      tester,
    ) async {
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: List.generate(
            6,
            (i) => Track(
              id: 's$i',
              title: 'Canción $i',
              artist: 'Artista $i',
              pageUrl: 'https://www.youtube.com/watch?v=f$i',
            ),
          ),
        ),
      ))!;
      addTearDown(() => closeTestController(c));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: slushTheme(Brightness.light, Colors.blue),
          home: Scaffold(
            body: HomeMusicPage(
              controller: c,
              onSearch: () {},
              onDownloads: () {},
              onLikes: () {},
              onOpenPlaylist: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsWidgets);
    });
  }
}
