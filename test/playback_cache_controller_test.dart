import 'dart:async';

import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _CacheSource extends FakeSource {
  String? protectedInput;
  int clearCalls = 0;
  Completer<int>? pendingClear;
  Completer<ResolvedAudio>? pendingResolve;
  final resolutionStarted = Completer<void>();
  final cancelled = <String>[];

  @override
  bool get supportsPlaybackCache => true;

  @override
  Future<ResolvedAudio> resolve(Track track) async {
    if (!resolutionStarted.isCompleted) resolutionStarted.complete();
    return pendingResolve?.future ??
        const ResolvedAudio(
          input: 'C:/private-cache/abcdefghijk.audio',
          duration: Duration(minutes: 3),
        );
  }

  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);

  @override
  Future<int> clearPlaybackCache({String? protectedPath}) async {
    protectedInput = protectedPath;
    clearCalls++;
    return pendingClear?.future ?? 2 * 1024 * 1024;
  }
}

void main() {
  test(
    'pause cancels cached resolution by video URL for imported IDs',
    () async {
      final source = _CacheSource()
        ..pendingResolve = Completer<ResolvedAudio>();
      final audio = FakeAudio();
      final c = await createTestController(source: source, audio: audio);
      addTearDown(() async {
        c.dispose();
        await c.closed;
        await c.supportDirectory.delete(recursive: true);
      });
      final playing = c.playTrack(
        const Track(
          id: 'spotify-stable-id',
          title: 'Matched song',
          artist: 'Fixture',
          pageUrl: 'https://youtu.be/abcdefghijk',
        ),
      );
      await source.resolutionStarted.future;
      await c.pausePlayback();
      expect(source.cancelled, ['resolve:abcdefghijk']);
      source.pendingResolve!.complete(
        const ResolvedAudio(input: 'cached.audio'),
      );
      await playing;
      expect(audio.isPlaying, isFalse);
      expect(audio.loadCount, 0);
      expect(c.error, isNull);
    },
  );

  test(
    'cache cleanup protects loaded audio and keeps playback and library',
    () async {
      final source = _CacheSource();
      final audio = FakeAudio();
      final c = await createTestController(source: source, audio: audio);
      addTearDown(() async {
        c.dispose();
        await c.closed;
        await c.supportDirectory.delete(recursive: true);
      });
      const track = Track(
        id: 'yt:abcdefghijk',
        title: 'Current song',
        artist: 'Fixture',
        pageUrl: 'https://youtu.be/abcdefghijk',
      );
      await c.playTrack(track);
      await c.toggleFavorite(track);
      await c.createPlaylist('Keep this playlist');
      await c.addToPlaylist(c.playlists.single, track);
      final loadCount = audio.loadCount;

      source.pendingClear = Completer<int>();
      final clearing = c.clearPlaybackCache();
      await c.clearPlaybackCache();
      expect(source.clearCalls, 1);
      expect(source.protectedInput, audio.loaded!.input);
      expect(c.clearingPlaybackCache, isTrue);
      source.pendingClear!.complete(2 * 1024 * 1024);
      await clearing;
      expect(audio.isPlaying, isTrue);
      expect(audio.loadCount, loadCount);
      expect(c.currentTrack!.id, track.id);
      expect(c.favoriteIds, contains(track.id));
      expect(c.playlists.single.trackIds, [track.id]);
      expect(c.clearingPlaybackCache, isFalse);
      expect(c.playbackCacheMessage, contains('2.0 MB liberados'));

      await c.pausePlayback();
      source.pendingClear = null;
      await c.clearPlaybackCache();
      expect(source.protectedInput, audio.loaded!.input);
      expect(audio.isPlaying, isFalse);
      await c.stopPlayback();
      await c.clearPlaybackCache();
      expect(source.protectedInput, isNull);
    },
  );
}
