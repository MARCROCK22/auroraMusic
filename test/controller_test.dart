import 'dart:async';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const first = Track(
  id: 'one',
  title: 'Uno',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/abcdefghijk',
);
const second = Track(
  id: 'two',
  title: 'Dos',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/lmnopqrstuv',
);
const third = Track(
  id: 'three',
  title: 'Tres',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/wxyz1234567',
);

void main() {
  test(
    'session import copies privately, replaces and clears without deleting the original',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      final original = File('${controller.supportDirectory.path}/original.txt');
      await original.writeAsString(
        '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\ttest-value\n',
      );
      await controller.configureYouTubeSession(original);
      final firstCopy = File(controller.source.cookieFile!);
      expect(firstCopy.path, isNot(original.path));
      expect(await firstCopy.readAsString(), await original.readAsString());
      await controller.configureYouTubeSession(original);
      expect(await firstCopy.exists(), isFalse);
      final secondCopy = File(controller.source.cookieFile!);
      await controller.clearYouTubeSession();
      expect(controller.hasYouTubeSession, isFalse);
      expect(await secondCopy.exists(), isFalse);
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'failed session validation preserves the previous session and cleans the rejected copy',
    () async {
      final source = FakeSource();
      final controller = await createTestController(source: source);
      addTearDown(() => closeTestController(controller));
      final original = File('${controller.supportDirectory.path}/original.txt');
      await original.writeAsString('test session');
      await controller.configureYouTubeSession(original);
      final previous = source.cookieFile;
      source.cookieError = ArgumentError('Invalid cookie format');
      await controller.configureYouTubeSession(original);
      expect(source.cookieFile, previous);
      expect(
        await Directory(
          '${controller.supportDirectory.path}/session',
        ).list().length,
        1,
      );
      expect(controller.sessionBusy, isFalse);
      expect(controller.error, contains('Invalid cookie format'));
      // An old preference must never cause removal of a user-owned file.
      source.cookieFile = original.path;
      await controller.clearYouTubeSession();
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'queue advances, previous restarts, and reorder preserves playing item',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first, context: [first, second, third]);
      await controller.next();
      expect(controller.currentTrack?.id, second.id);
      await controller.reorderQueue(1, 3);
      expect(controller.queueIndex, 2);
      expect(controller.currentTrack?.id, second.id);
      (controller.audio as FakeAudio).position = const Duration(seconds: 15);
      await controller.previous();
      expect(controller.audio.position, Duration.zero);
      expect(controller.currentTrack?.id, second.id);
      await controller.next();
      expect(controller.audio.isPlaying, isFalse);
    },
  );

  test('clearing search invalidates an in-flight result', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(source: source);
    addTearDown(() => closeTestController(controller));
    final searching = controller.search('consulta');
    await controller.search('');
    source.pendingSearch!.complete([first]);
    await searching;
    expect(controller.searchResults, isEmpty);
    expect(controller.searching, isFalse);
  });

  test(
    'requested discovery is bounded, deduplicated, and library-neutral',
    () async {
      final source = FakeSource();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      source.searchMatches = [
        first,
        const Track(
          id: 'new-one',
          title: 'Nuevo uno',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/new-one',
        ),
        const Track(
          id: 'new-one',
          title: 'Duplicado',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/new-one',
        ),
        const Track(id: 'unplayable', title: 'Sin enlace', artist: 'Artista'),
        const Track(
          id: 'pending',
          title: 'Pendiente',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/pending',
          spotifyMatchPending: true,
        ),
        for (var i = 2; i <= 8; i++)
          Track(
            id: 'new-$i',
            title: 'Nuevo $i',
            artist: 'Artista',
            pageUrl: 'https://youtu.be/new-$i',
          ),
      ];

      await controller.discoverRecommendations();

      expect(source.searchQueries, ['Artista songs']);
      expect(source.searchLimits, [12]);
      expect(controller.discoveredRecommendations, hasLength(6));
      expect(
        controller.discoveredRecommendations.map((track) => track.id).toSet(),
        hasLength(6),
      );
      expect(controller.tracks.map((track) => track.id).toSet(), {
        'one',
        'two',
        'three',
      });
      expect(
        (await controller.database.readTracks())
            .map((track) => track.id)
            .toSet(),
        {'one', 'two', 'three'},
      );
    },
  );

  test('cancelled discovery ignores its late source result', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(
      tracks: [first, second],
      source: source,
    );
    addTearDown(() => closeTestController(controller));
    final discovery = controller.discoverRecommendations();
    controller.cancelRecommendationDiscovery();
    source.pendingSearch!.complete([third]);
    await discovery;

    expect(controller.discoveredRecommendations, isEmpty);
    expect(controller.discoveringRecommendations, isFalse);
  });

  test('discovery failure stays separate from the main search error', () async {
    final source = FakeSource()..searchError = StateError('offline');
    final controller = await createTestController(
      tracks: [first, second],
      source: source,
    );
    addTearDown(() => closeTestController(controller));

    await controller.discoverRecommendations();

    expect(controller.recommendationDiscoveryError, contains('offline'));
    expect(controller.error, isNull);
    expect(controller.searching, isFalse);
  });

  test('older extraction cannot replace a newer selected track', () async {
    final source = FakeSource();
    source.pendingResolves['one'] = Completer<ResolvedAudio>();
    final controller = await createTestController(source: source);
    addTearDown(() => closeTestController(controller));
    final original = controller.playTrack(first);
    while (!source.resolved.contains('one')) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.playTrack(second);
    source.pendingResolves['one']!.complete(
      const ResolvedAudio(input: 'https://example.test/old'),
    );
    await original;
    expect(controller.currentTrack?.id, second.id);
    expect((controller.audio as FakeAudio).loaded?.input, contains('two'));
  });

  test(
    'favorites and playlist ordering are persisted, stale playlist edits merge',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(first);
      await controller.createPlaylist('Viaje');
      final stale = controller.playlists.single;
      await controller.addToPlaylist(stale, first);
      await controller.addToPlaylist(stale, second);
      await controller.reorderPlaylist(stale, 0, 2);
      expect((await controller.database.readPlaylists()).single.trackIds, [
        'two',
        'one',
      ]);
      expect(await controller.database.readFavorites(), {'one'});
    },
  );

  test(
    'downloads run serially and become playable local library files',
    () async {
      final source = FakeSource()..downloadGate = Completer<void>();
      final controller = await createTestController(source: source);
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      await controller.downloadTrack(second);
      while (source.activeDownloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      source.downloadGate!.complete();
      while (controller.downloads.any(
        (job) =>
            job.status == DownloadStatus.queued ||
            job.status == DownloadStatus.downloading,
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(source.maxActiveDownloads, 1);
      expect(
        controller.tracks.every((track) => track.localPath != null),
        isTrue,
      );
      await controller.playTrack(controller.tracks.first);
      expect(source.resolved, isEmpty);
    },
  );

  test(
    'concurrent playlist additions and stale rename preserve every item',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.createPlaylist('Primera');
      final stale = controller.playlists.single;
      await Future.wait([
        controller.addToPlaylist(stale, first),
        controller.addToPlaylist(stale, second),
        controller.addToPlaylist(stale, third),
      ]);
      await controller.renamePlaylist(stale, 'Final');
      final saved = (await controller.database.readPlaylists()).single;
      expect(saved.name, 'Final');
      expect(saved.trackIds.toSet(), {'one', 'two', 'three'});
    },
  );

  test(
    'session restores paused with saved position and no network access',
    () async {
      final source = FakeSource();
      final controller = await createTestController(
        source: source,
        tracks: [first, second],
        preferences: {
          'queue': ['one', 'two'],
          'queueIndex': 1,
          'position': 42000,
        },
      );
      addTearDown(() => closeTestController(controller));
      expect(controller.currentTrack?.id, 'two');
      expect(controller.audio.isPlaying, isFalse);
      expect(source.resolved, isEmpty);
      await controller.persistSession();
      expect(controller.preferences.getInt('position'), 42000);
      await controller.togglePlayback();
      expect(controller.audio.position, const Duration(seconds: 42));
    },
  );

  test(
    'stale favorites preserve offline files and deletion retains library metadata',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final file = File(controller.tracks.single.localPath!);
      await controller.toggleFavorite(first);
      expect(controller.tracks.single.localPath, file.path);
      await controller.createPlaylist('Offline');
      await controller.addToPlaylist(controller.playlists.single, first);
      await controller.removeDownload(controller.downloads.single);
      expect(await file.exists(), isFalse);
      expect(controller.tracks.single.localPath, isNull);
      expect(controller.downloads, isEmpty);
      expect(await controller.database.readDownloads(), isEmpty);
      expect(await controller.database.readFavorites(), {'one'});
      expect(controller.playlists.single.trackIds, ['one']);
    },
  );

  test(
    'Windows download deletion accepts equivalent drive casing',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final job = controller.downloads.single;
      final original = File(job.localPath!);
      final path = original.absolute.path;
      expect(path[1], ':');
      final drive = path[0] == path[0].toUpperCase()
          ? path[0].toLowerCase()
          : path[0].toUpperCase();
      job.localPath = '$drive${path.substring(1)}';
      await controller.removeDownload(job);
      expect(controller.error, isNull);
      expect(await original.exists(), isFalse);
      expect(controller.downloads, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test('download deletion rejects files outside app storage', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    final directory = Directory(
      '${controller.supportDirectory.path}/downloads',
    );
    await directory.create();
    final outside = File('${controller.supportDirectory.path}/keep.mp3');
    await outside.writeAsBytes([1, 2, 3]);
    final job = DownloadJob(id: 'outside', track: first)
      ..status = DownloadStatus.completed
      ..localPath = outside.path;
    controller.downloads.add(job);
    await controller.removeDownload(job);
    expect(await outside.exists(), isTrue);
    expect(controller.downloads, contains(job));
    expect(controller.error, contains('fuera'));
  });

  test(
    'download jobs retain their destination root and never overwrite files',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final job = controller.downloads.single;
      final original = File(job.localPath!);
      expect(
        job.destinationRoot,
        await Directory(original.parent.path).resolveSymbolicLinks(),
      );
      await controller.preferences.setString(
        'downloadsDirectory',
        '${controller.supportDirectory.path}/another-folder',
      );
      await controller.removeDownload(job);
      expect(await original.exists(), isFalse);
    },
  );

  test(
    'expired remote audio is re-extracted once and resumes position',
    () async {
      final source = FakeSource();
      final audio = FakeAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first);
      audio.position = const Duration(seconds: 27);
      audio.lastError = 'HTTP 403 Forbidden';
      audio.notifyListeners();
      while (controller.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(source.resolved, ['one', 'one']);
      expect(audio.position, const Duration(seconds: 27));
      audio.lastError = 'HTTP 403 Forbidden';
      audio.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.resolved.length, 2);
    },
  );

  test(
    'reordering duplicate queue entries preserves the selected occurrence',
    () async {
      final controller = await createTestController(
        tracks: [first, second],
        preferences: {
          'queue': ['one', 'one', 'two'],
          'queueIndex': 1,
          'position': 42000,
        },
      );
      addTearDown(() => closeTestController(controller));
      await controller.reorderQueue(2, 0);
      expect(controller.queueIndex, 2);
      expect(controller.currentTrack?.id, 'one');
      await controller.playQueueAt(2);
      expect(controller.queueIndex, 2);
      expect(controller.audio.position, Duration.zero);
      await controller.removeFromQueue(2);
      expect(controller.audio.position, Duration.zero);
    },
  );

  test(
    'shutdown waits for an active download before closing its database',
    () async {
      final source = FakeSource()..downloadGate = Completer<void>();
      final controller = await createTestController(source: source);
      await controller.downloadTrack(first);
      while (source.activeDownloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.dispose();
      source.downloadGate!.complete();
      await controller.closed;
      await controller.supportDirectory.delete(recursive: true);
      expect(source.activeDownloads, 0);
    },
  );
}
