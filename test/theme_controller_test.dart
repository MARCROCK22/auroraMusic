import 'package:aurora_music/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';

import 'support/fakes.dart';

void main() {
  test(
    'manual palette remains selected and persisted after artwork failure',
    () async {
      const track = Track(
        id: 'theme-race',
        title: 'Theme race',
        artist: 'Aurora',
        pageUrl: 'https://www.youtube.com/watch?v=theme-race',
        artworkUrl: 'https://127.0.0.1:1/artwork',
      );
      final controller = await createTestController(tracks: const [track]);
      addTearDown(() => closeTestController(controller));
      const nextTrack = Track(
        id: 'theme-next',
        title: 'Next track',
        artist: 'Aurora',
        pageUrl: 'https://www.youtube.com/watch?v=theme-next',
      );

      await controller.playTrack(track);
      controller.setAccentPalette('purple');
      await controller.playTrack(nextTrack);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(controller.accentPalette, 'purple');
      expect(
        controller.accentColor,
        AppController.accentPaletteColors['purple'],
      );
      expect(controller.preferences.getString('accentPalette'), 'purple');
      expect(controller.preferences.getBool('adaptiveColors'), isFalse);
    },
  );
}
