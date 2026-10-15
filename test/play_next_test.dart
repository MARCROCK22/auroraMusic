import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track _t(String id) =>
    Track(id: id, title: id, artist: 'Artist', pageUrl: 'https://youtu.be/$id');

void main() {
  final all = [
    for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) _t(id),
  ];

  Future<AppController> start() async {
    final c = await createTestController(tracks: all);
    addTearDown(() => closeTestController(c));
    await c.playTrack(all[0], context: [all[0], all[1], all[2]]);
    return c;
  }

  List<String> ids(AppController c) => c.queue.map((x) => x.id).toList();

  test('inserts right after the current track and persists', () async {
    final c = await start();
    await c.playNext(all[3]);
    expect(ids(c), ['a', 'd', 'b', 'c']);
    expect(c.preferences.getStringList('queue'), ['a', 'd', 'b', 'c']);
  });

  test('several play-next calls keep FIFO order', () async {
    final c = await start();
    await c.playNext(all[3]);
    await c.playNext(all[4]);
    expect(ids(c), ['a', 'd', 'e', 'b', 'c']);
  });

  test('moves an already queued track', () async {
    final c = await start();
    await c.playNext(all[2]);
    expect(ids(c), ['a', 'c', 'b']);
    await c.playNext(all[3]);
    await c.playNext(all[1]);
    expect(ids(c), ['a', 'c', 'd', 'b']);
  });

  test('empty queue just enqueues', () async {
    final c = await createTestController(tracks: all);
    addTearDown(() => closeTestController(c));
    await c.playNext(all[0]);
    expect(ids(c), ['a']);
  });

  test('changing the current track resets the cursor', () async {
    final c = await start();
    await c.playNext(all[3]);
    await c.next();
    expect(c.currentTrack?.id, 'd');
    await c.playNext(all[4]);
    expect(ids(c), ['a', 'd', 'e', 'b', 'c']);
  });

  test('pending play-next items stay FIFO after advancing', () async {
    final c = await start();
    await c.playNext(all[3]);
    await c.playNext(all[4]);
    await c.next();
    expect(c.currentTrack?.id, 'd');
    await c.playNext(all[5]);
    expect(ids(c), ['a', 'd', 'e', 'f', 'b', 'c']);
  });

  test('shuffle plays the play-next track first', () async {
    for (var run = 0; run < 10; run++) {
      final c = await start();
      c.setShuffle(true);
      await c.playNext(all[3]);
      await c.next();
      expect(c.currentTrack?.id, 'd');
    }
  });
}
