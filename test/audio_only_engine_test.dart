import 'dart:async';

import 'package:aurora_music/audio_web/web_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const input = 'https://music.youtube.com/watch?v=6geljA2OZSY';
const otherInput = 'https://music.youtube.com/watch?v=M7lc1UVf-VE';

class FakeBridge extends WebMusicBridge {
  Uri? page;
  int builds = 0;
  bool disposed = false;
  final commands = <String>[];
  final values = <double?>[];
  Map<String, dynamic> state = {
    'status': 'ready',
    'playing': false,
    'position': 12.5,
    'duration': 150,
    'title': 'Observed title',
    'artist': 'Observed artist',
  };
  Completer<Map<String, dynamic>?>? pending;

  @override
  Future<void> initialize() async {}
  @override
  Widget buildView() {
    builds++;
    return const ColoredBox(key: ValueKey('engine'), color: Colors.red);
  }

  @override
  Future<void> navigate(Uri uri) async => page = uri;
  @override
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
  }) async {
    commands.add(action);
    values.add(value);
    if (pending != null) {
      final future = pending!.future;
      pending = null;
      return future;
    }
    if (action == 'play' && state['status'] == 'ready') {
      state = {...state, 'playing': true, 'ended': false};
    } else if (action == 'pause') {
      state = {...state, 'playing': false};
    }
    return {...state, 'generation': generation, 'videoId': videoId};
  }

  @override
  void dispose() => disposed = true;
}

void main() {
  late FakeBridge bridge;
  late WebMusicAudio audio;
  setUp(() async {
    bridge = FakeBridge();
    audio = WebMusicAudio(
      bridge: bridge,
      pollInterval: const Duration(days: 1),
    );
    await audio.initialize();
  });
  tearDown(() => audio.dispose());

  test('official watch inputs only, no credential headers', () async {
    for (final invalid in [
      'http://music.youtube.com/watch?v=6geljA2OZSY',
      'https://music.youtube.com.evil.test/watch?v=6geljA2OZSY',
      'https://user:password@music.youtube.com/watch?v=6geljA2OZSY',
      'https://music.youtube.com:444/watch?v=6geljA2OZSY',
      'https://music.youtube.com/watch?v=bad',
      '$input&v=M7lc1UVf-VE',
      '$input&token=secret',
      '$input#fragment',
    ]) {
      expect(() => WebMusicAudio.validateInput(invalid), throwsArgumentError);
    }
    await expectLater(
      audio.load(
        const ResolvedAudio(input: input, headers: {'Cookie': 'secret'}),
      ),
      throwsArgumentError,
    );
    expect(bridge.page, isNull);
    await audio.load(const ResolvedAudio(input: input));
    expect(bridge.page.toString(), input);
    expect(audio.supportsEqualizer, isFalse);
    expect(audio.supportsVisualization, isFalse);
    expect(audio.spectrum.value.every((value) => value == 0), isTrue);
  });

  test('reports observed state and metadata, sends normal controls', () async {
    await audio.load(const ResolvedAudio(input: input));
    expect(audio.isPlaying, isFalse);
    expect(audio.currentTrackMetadata, isNull);
    await audio.play();
    expect(audio.isPlaying, isTrue);
    expect(audio.position, const Duration(milliseconds: 12500));
    expect(audio.currentTrackMetadata?.id, 'yt:6geljA2OZSY');
    expect(audio.currentTrackMetadata?.title, 'Observed title');
    await audio.seek(const Duration(seconds: 30));
    expect(bridge.commands.last, 'seek');
    expect(bridge.values.last, 30);
    audio.setVolume(5);
    await audio.pause();
    expect(
      bridge.commands,
      containsAllInOrder(['volume', 'seek', 'volume', 'pause']),
    );
    expect(audio.volume, 1);
    expect(audio.isPlaying, isFalse);
  });

  test(
    'blocked play throws with actionable state and no secret exception',
    () async {
      await audio.load(const ResolvedAudio(input: input));
      await audio.refresh();
      bridge.state = {'status': 'playBlocked'};
      await expectLater(audio.play(), throwsStateError);
      expect(audio.needsWebsiteAccess, isTrue);
      expect(audio.isPlaying, isFalse);
      expect(audio.lastError, contains('pulsa reproducir'));
      bridge.state = {'status': 'ready', 'playing': true, 'duration': 150};
      await audio.refresh();
      expect(audio.needsWebsiteAccess, isFalse);
      expect(audio.isPlaying, isTrue);
      expect(audio.lastError, isNull);
    },
  );

  test('ad end does not complete track or overwrite song metadata', () async {
    await audio.load(const ResolvedAudio(input: input));
    await audio.refresh();
    var completions = 0;
    final subscription = audio.completed.listen((_) => completions++);
    addTearDown(subscription.cancel);
    bridge.state = {
      'status': 'ready',
      'adPlaying': true,
      'ended': true,
      'duration': 20,
      'position': 20,
      'title': 'Advertisement',
    };
    await audio.refresh();
    expect(completions, 0);
    expect(audio.adPlaying, isTrue);
    expect(audio.duration, const Duration(seconds: 150));
    expect(audio.title, 'Observed title');
    bridge.state = {'status': 'ready', 'ended': true, 'duration': 150};
    await audio.refresh();
    await audio.refresh();
    expect(completions, 1);
  });

  test('stale page response cannot update a newly selected track', () async {
    await audio.load(const ResolvedAudio(input: input));
    final pending = Completer<Map<String, dynamic>?>();
    bridge.pending = pending;
    final oldRefresh = audio.refresh();
    await Future<void>.delayed(Duration.zero);
    await audio.load(const ResolvedAudio(input: otherInput));
    pending.complete({
      'status': 'ready',
      'generation': 1,
      'videoId': '6geljA2OZSY',
      'playing': true,
      'duration': 999,
      'title': 'Stale title',
    });
    await oldRefresh;
    expect(audio.currentTrackMetadata, isNull);
    expect(audio.isPlaying, isFalse);
    expect(audio.duration, Duration.zero);
  });

  test('pause cancels play while initial volume command is pending', () async {
    await audio.load(const ResolvedAudio(input: input));
    await audio.refresh();
    final pending = Completer<Map<String, dynamic>?>();
    bridge.pending = pending;
    final playing = audio.play();
    await Future<void>.delayed(Duration.zero);
    expect(bridge.commands.last, 'volume');
    final pausing = audio.pause();
    pending.complete({
      ...bridge.state,
      'generation': 1,
      'videoId': '6geljA2OZSY',
    });
    await Future.wait([playing, pausing]);
    expect(bridge.commands, isNot(contains('play')));
    expect(audio.isPlaying, isFalse);
  });

  test('missing media has bounded actionable failure', () async {
    audio.dispose();
    audio = WebMusicAudio(
      bridge: bridge,
      pollInterval: const Duration(days: 1),
      mediaWaitTimeout: Duration.zero,
    );
    await audio.initialize();
    bridge.state = {'status': 'waiting'};
    await audio.load(const ResolvedAudio(input: input));
    await expectLater(audio.play(), throwsStateError);
    expect(audio.needsWebsiteAccess, isTrue);
    expect(audio.isBuffering, isFalse);
  });

  test(
    'artwork is observed HTTPS imagery, never a media URL or credentials',
    () async {
      await audio.load(const ResolvedAudio(input: input));
      for (final rejected in [
        'http://i.ytimg.com/vi/6geljA2OZSY/default.jpg',
        'https://secret@i.ytimg.com/cover.jpg',
        'https://rr1.googlevideo.com/videoplayback?token=secret',
        'https://i.ytimg.com.evil.test/cover.jpg',
      ]) {
        bridge.state['artworkUrl'] = rejected;
        await audio.refresh();
        expect(audio.currentTrackMetadata?.artworkUrl, isNull);
      }
      bridge.state['artworkUrl'] =
          'https://i.ytimg.com/vi/6geljA2OZSY/default.jpg';
      await audio.refresh();
      expect(
        audio.currentTrackMetadata?.artworkUrl,
        bridge.state['artworkUrl'],
      );
    },
  );

  test(
    'new selection cancels an older stop before it navigates home',
    () async {
      await audio.load(const ResolvedAudio(input: input));
      final pending = Completer<Map<String, dynamic>?>();
      bridge.pending = pending;
      final stopping = audio.stop();
      await Future<void>.delayed(Duration.zero);
      await audio.load(const ResolvedAudio(input: otherInput));
      pending.complete({
        'status': 'ready',
        'generation': 1,
        'videoId': '6geljA2OZSY',
      });
      await stopping;
      expect(bridge.page.toString(), otherInput);
    },
  );

  testWidgets(
    'hidden/visible host retains one view and excludes hidden input',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: audio.buildEngineView()));
      expect(bridge.builds, 1);
      expect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('engine')),
              matching: find.byType(Offstage),
            )
            .evaluate()
            .every((element) => !(element.widget as Offstage).offstage),
        isTrue,
      );
      final ignore = tester.widget<IgnorePointer>(
        find.byWidgetPredicate(
          (widget) => widget is IgnorePointer && widget.child is ColoredBox,
        ),
      );
      expect(ignore.ignoring, isTrue);
      await tester.pumpWidget(
        MaterialApp(home: audio.buildEngineView(showWebsite: true)),
      );
      expect(bridge.builds, 1);
      expect(
        tester
            .widget<IgnorePointer>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IgnorePointer && widget.child is ColoredBox,
              ),
            )
            .ignoring,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
