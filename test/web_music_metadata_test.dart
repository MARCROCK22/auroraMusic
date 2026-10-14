import 'dart:async';

import 'package:aurora_music/audio_web/web_music_metadata.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'searches the official page and maps only valid public metadata',
    () async {
      final bridge = _MetadataBridge(
        (_, videoId, _) async => {
          'status': 'ready',
          'tracks': [
            {
              'videoId': 'abcdefghijk',
              'title': '  Song  ',
              'artist': ' Artist ',
            },
            {'videoId': 'bad', 'title': 'Invalid ID'},
            {'videoId': 'lmnopqrstuv', 'title': '   '},
            {
              'videoId': 'mnopqrstuvw',
              'title': 'No duration',
              'durationSeconds': -4,
            },
          ],
        },
      );
      final metadata = WebMusicMetadata(bridge: bridge);

      final tracks = await metadata.search('  jazz   mix ');

      expect(bridge.initialized, 1);
      expect(
        bridge.navigated,
        Uri.https('music.youtube.com', '/search', {'q': 'jazz mix'}),
      );
      expect(bridge.commands.single, ('jazz mix', 1));
      expect(tracks, hasLength(2));
      expect(tracks.first.id, 'yt:abcdefghijk');
      expect(tracks.first.title, 'Song');
      expect(tracks.first.artist, 'Artist');
      expect(tracks.last.duration, Duration.zero);
      expect(
        tracks.first.pageUrl,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
      expect(metadata.activated, isTrue);
      metadata.buildMetadataView();
      expect(bridge.viewBuilds, 1);
      metadata.dispose();
    },
  );

  test('normalizes and caches queries for five minutes', () async {
    final bridge = _MetadataBridge(
      (_, _, _) async => {
        'status': 'ready',
        'tracks': [
          {'videoId': 'abcdefghijk', 'title': 'Song'},
          {'videoId': 'lmnopqrstuv', 'title': 'Song 2'},
        ],
      },
    );
    final metadata = WebMusicMetadata(bridge: bridge);

    expect(await metadata.search('  Indie  Pop ', limit: 1), hasLength(1));
    expect(await metadata.search('indie pop', limit: 2), hasLength(2));
    expect(bridge.commands, hasLength(1));
    metadata.dispose();
  });

  test('caps results and reports timeout without inventing tracks', () async {
    final bridge = _MetadataBridge((_, _, _) async => {'status': 'waiting'});
    final metadata = WebMusicMetadata(
      bridge: bridge,
      timeout: const Duration(milliseconds: 25),
      pollInterval: const Duration(milliseconds: 5),
    );

    expect(await metadata.search('ambient', limit: 500), isEmpty);
    expect(metadata.tracks, isEmpty);
    expect(metadata.error, contains('tardó demasiado'));
    metadata.dispose();
  });

  test('superseded searches cannot publish their results', () async {
    final oldSearch = Completer<Map<String, dynamic>?>();
    final bridge = _MetadataBridge((_, query, _) async {
      if (query == 'old') return oldSearch.future;
      return {
        'status': 'ready',
        'tracks': [
          {'videoId': 'lmnopqrstuv', 'title': 'New result'},
        ],
      };
    });
    final metadata = WebMusicMetadata(bridge: bridge);

    final oldResult = metadata.search('old');
    await pumpEventQueue();
    final newResult = metadata.search('new');
    oldSearch.complete({
      'status': 'ready',
      'tracks': [
        {'videoId': 'abcdefghijk', 'title': 'Stale result'},
      ],
    });

    expect(await oldResult, isEmpty);
    expect((await newResult).single.title, 'New result');
    expect(metadata.tracks.single.title, 'New result');
    metadata.dispose();
  });

  test(
    'deduplicates tracks and rejects unsafe artwork and excessive durations',
    () async {
      final bridge = _MetadataBridge(
        (_, _, _) async => {
          'status': 'ready',
          'tracks': [
            {
              'videoId': 'abcdefghijk',
              'title': 'Song',
              'artworkUrl': 'https://secret@i.ytimg.com/cover.jpg',
              'durationSeconds': 1e30,
            },
            {'videoId': 'abcdefghijk', 'title': 'Duplicate'},
            {
              'videoId': 'lmnopqrstuv',
              'title': 'Other song',
              'artworkUrl': 'https://i.ytimg.com/cover.jpg',
              'durationSeconds': 210,
            },
          ],
        },
      );
      final metadata = WebMusicMetadata(bridge: bridge);
      addTearDown(metadata.dispose);
      final tracks = await metadata.search('music');
      expect(tracks, hasLength(2));
      expect(tracks.first.artworkUrl, isNull);
      expect(tracks.first.duration, Duration.zero);
      expect(tracks.last.duration.inSeconds, 210);
    },
  );

  test('zero limit and excessive query do not navigate the provider', () async {
    final bridge = _MetadataBridge((_, _, _) async => null);
    final metadata = WebMusicMetadata(bridge: bridge);
    addTearDown(metadata.dispose);
    expect(await metadata.search('music', limit: 0), isEmpty);
    await expectLater(metadata.search('x' * 501), throwsArgumentError);
    expect(bridge.navigated, isNull);
    expect(metadata.activated, isFalse);
  });

  test(
    'disposing cancels a waiting search without late notifications',
    () async {
      final bridge = _MetadataBridge((_, _, _) async => {'status': 'waiting'});
      final metadata = WebMusicMetadata(
        bridge: bridge,
        pollInterval: const Duration(seconds: 10),
      );
      final result = metadata.search('music');
      await pumpEventQueue();
      metadata.dispose();
      expect(await result, isEmpty);
    },
  );
}

class _MetadataBridge extends WebMusicBridge {
  _MetadataBridge(this.respond);

  final Future<Map<String, dynamic>?> Function(
    String action,
    String query,
    int generation,
  )
  respond;
  int initialized = 0;
  int viewBuilds = 0;
  Uri? navigated;
  final commands = <(String, int)>[];

  @override
  Future<void> initialize() async {
    initialized++;
  }

  @override
  Widget buildView() {
    viewBuilds++;
    return const SizedBox.shrink();
  }

  @override
  Future<void> navigate(Uri uri) async {
    navigated = uri;
  }

  @override
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
  }) {
    commands.add((videoId, generation));
    return respond(action, videoId, generation);
  }

  @override
  void dispose() {}
}
