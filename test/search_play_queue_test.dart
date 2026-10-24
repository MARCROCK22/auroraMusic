import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track _t(String id) => Track(
  id: id,
  title: id,
  artist: 'Artist $id',
  pageUrl: 'https://youtu.be/$id',
);

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

  test('search result drops the old playlist but keeps manual queue', () async {
    final c = await start();
    await c.playNext(all[3]);
    final results = [all[4], all[5], _t('x')];
    await c.playTrack(results[0], context: results, replaceQueue: false);
    expect(c.currentTrack?.id, 'e');
    expect(ids(c).take(3), ['a', 'e', 'd']);
    expect(ids(c).contains('b'), isFalse);
    expect(ids(c).contains('c'), isFalse);
    expect(ids(c).contains('f'), isFalse);
    expect(ids(c).contains('x'), isFalse);
  });

  test('tapped track already queued is not duplicated', () async {
    final c = await start();
    await c.playTrack(all[2], replaceQueue: false);
    expect(c.currentTrack?.id, 'c');
    expect(ids(c).where((id) => id == 'c'), hasLength(1));
    expect(ids(c).take(2), ['a', 'c']);
  });

  test('empty queue starts from the tapped seed only', () async {
    final c = await createTestController(tracks: all);
    addTearDown(() => closeTestController(c));
    await c.playTrack(all[4], context: [all[4], all[5]], replaceQueue: false);
    expect(c.currentTrack?.id, 'e');
    expect(ids(c).first, 'e');
    expect(ids(c).where((id) => id == 'e'), hasLength(1));
  });

  test('list context still replaces the queue', () async {
    final c = await start();
    await c.playTrack(all[4], context: [all[4], all[5]]);
    expect(ids(c).take(2), ['e', 'f']);
    expect(ids(c).contains('a'), isFalse);
  });
}
