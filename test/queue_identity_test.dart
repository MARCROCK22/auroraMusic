import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  const selected = Track(
    id: 'selected',
    title: 'Selected',
    artist: 'Artist',
    pageUrl: 'https://youtu.be/video',
  );
  const alias = Track(
    id: 'alias',
    title: 'Alias',
    artist: 'Artist',
    pageUrl: 'https://www.youtube.com/watch?v=video&si=shared',
  );
  test(
    'play context keeps the selected song and removes canonical duplicates',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(
        selected,
        context: [alias, selected, selected],
      );
      expect(controller.queue.map((t) => t.id), ['selected']);
      expect(controller.currentTrack?.id, 'selected');
    },
  );
  test('selected song absent from context replaces its duplicate', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(selected, context: [alias, alias]);
    expect(controller.queue.map((t) => t.id), ['selected']);
  });
  test(
    'playing a metadata match enriches an audio track already in the library',
    () async {
      final controller = await createTestController(tracks: [selected]);
      addTearDown(() => closeTestController(controller));
      const metadata = Track(
        id: 'metadata',
        title: 'Spotify title',
        artist: 'Spotify artist',
        spotifyUri: 'spotify:track:abcdefghijklmnopqrstuv',
        spotifyMatchPending: true,
      );
      expect(
        await controller.importSpotifyMetadataMatch(
          metadata,
          selected,
          play: true,
        ),
        isTrue,
      );
      expect(controller.currentTrack?.title, metadata.title);
      expect(controller.currentTrack?.spotifyUri, metadata.spotifyUri);
      expect(controller.currentTrack?.pageUrl, selected.pageUrl);
    },
  );
}
