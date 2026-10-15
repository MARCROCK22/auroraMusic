import 'dart:async';

import 'package:aurora_music/audio_web/web_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const input = 'https://music.youtube.com/watch?v=6geljA2OZSY';
const otherInput = 'https://music.youtube.com/watch?v=M7lc1UVf-VE';

void main() {
  late FakeWebBridge bridge;
  late WebMusicAudio audio;
  setUp(() async {
    bridge = FakeWebBridge();
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
    expect(audio.currentTrackMetadata, isNull);
  });

  test('reports observed state and sends serialized controls', () async {
    await audio.load(
      const ResolvedAudio(input: input, duration: Duration(seconds: 150)),
    );
    expect(audio.duration, const Duration(seconds: 150));
    expect(audio.isPlaying, isFalse);
    await audio.play();
    expect(audio.isPlaying, isTrue);
    expect(audio.position, const Duration(milliseconds: 12500));
    expect(bridge.timeouts.last, const Duration(seconds: 20));
    await audio.seek(const Duration(seconds: 30));
    expect(bridge.commands.last, 'seek');
    expect(bridge.values.last, 30);
    audio.setVolume(5);
    await audio.pause();
    expect(
      bridge.commands,
      containsAllInOrder(['snapshot', 'volume', 'play', 'seek', 'volume']),
    );
    expect(bridge.commands.last, 'pause');
    expect(audio.volume, 1);
    expect(audio.isPlaying, isFalse);
  });

  test('play timeout is its own retryable error, not a site action', () async {
    await audio.load(const ResolvedAudio(input: input));
    bridge.playResult = {
      'status': 'playTimeout',
      'action': 'play',
      'errorName': 'TimeoutError',
    };
    await expectLater(audio.play(), throwsStateError);
    expect(audio.lastError, contains('a tiempo'));
    expect(audio.lastError, contains('TimeoutError'));
    expect(audio.lastError, isNot(contains('aplicar ese control')));
    expect(audio.needsWebsiteAccess, isFalse);
    expect(audio.isPlaying, isFalse);
    // Retrying works once the page plays.
    await audio.play();
    expect(audio.isPlaying, isTrue);
    expect(audio.lastError, isNull);
  });

  test('failed control names the allowlisted error only', () async {
    await audio.load(const ResolvedAudio(input: input));
    bridge.playResult = {
      'status': 'commandFailed',
      'action': 'play',
      'errorName': 'NotSupportedError',
    };
    await expectLater(audio.play(), throwsStateError);
    expect(
      audio.lastError,
      'El sitio no pudo aplicar ese control (play: NotSupportedError).',
    );
    bridge.playResult = {
      'status': 'commandFailed',
      'action': 'play',
      'errorName': 'https://secret.test/?token=1',
    };
    await expectLater(audio.play(), throwsStateError);
    expect(audio.lastError, 'El sitio no pudo aplicar ese control.');
  });

  test('gesture block asks the user to review the site', () async {
    await audio.load(const ResolvedAudio(input: input));
    bridge.playResult = {
      'status': 'playBlocked',
      'action': 'play',
      'errorName': 'NotAllowedError',
    };
    await expectLater(audio.play(), throwsStateError);
    expect(audio.needsWebsiteAccess, isTrue);
    expect(audio.lastError, contains('Revisar sitio'));
  });

  test('consent page surfaces an explicit site-access error', () async {
    await audio.load(const ResolvedAudio(input: input));
    bridge.state = {'status': 'website'};
    await expectLater(audio.play(), throwsStateError);
    expect(audio.needsWebsiteAccess, isTrue);
    expect(audio.lastError, contains('consentimiento'));
    expect(audio.isPlaying, isFalse);
    expect(audio.showingWebsite, isFalse);
    audio.setWebsiteVisible(true);
    expect(audio.showingWebsite, isTrue);
    // A new load clears the request once the user resolved it.
    bridge.state = {'status': 'ready', 'playing': false, 'duration': 150};
    await audio.load(const ResolvedAudio(input: input));
    await audio.play();
    expect(audio.needsWebsiteAccess, isFalse);
    expect(audio.isPlaying, isTrue);
  });

  test('ads keep track progress and never complete the track', () async {
    await audio.load(const ResolvedAudio(input: input));
    await audio.play();
    var completions = 0;
    final subscription = audio.completed.listen((_) => completions++);
    addTearDown(subscription.cancel);
    const ad = {
      'status': 'ready',
      'playing': true,
      'adPlaying': true,
      'ended': true,
      'duration': 20,
      'position': 20,
    };
    bridge.state = ad;
    await audio.refresh();
    expect(completions, 0);
    expect(audio.adPlaying, isTrue);
    expect(audio.duration, const Duration(seconds: 150));
    expect(audio.position, const Duration(milliseconds: 12500));
    // An ad playing is not autoplay against Aurora's intent.
    await audio.pause();
    bridge.state = ad;
    bridge.commands.clear();
    await audio.refresh();
    expect(bridge.commands, ['snapshot']);
    bridge.state = {'status': 'ready', 'ended': true, 'duration': 150};
    await audio.refresh();
    await audio.refresh();
    expect(audio.adPlaying, isFalse);
    expect(completions, 1);
  });

  test('site autoplay without Aurora play intent is paused', () async {
    await audio.load(const ResolvedAudio(input: input));
    bridge.state = {'status': 'ready', 'playing': true, 'duration': 150};
    await audio.refresh();
    await audio.refresh();
    expect(bridge.commands, contains('pause'));
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
    });
    await oldRefresh;
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

  test('missing media has a bounded retryable failure', () async {
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
    expect(audio.lastError, contains('a tiempo'));
    expect(audio.isBuffering, isFalse);
    expect(bridge.commands, isNot(contains('play')));
  });

  test('stop pauses without navigating away', () async {
    await audio.load(const ResolvedAudio(input: input));
    await audio.play();
    await audio.stop();
    expect(bridge.commands.last, 'pause');
    expect(bridge.page.toString(), input);
    expect(audio.isPlaying, isFalse);
  });

  testWidgets('hidden host keeps one rendering view without input', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Stack(children: [audio.buildEngineView()])),
    );
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
    expect(
      tester.getSize(find.byKey(const ValueKey('engine'))),
      const Size(1, 1),
    );
    IgnorePointer ignore() => tester.widget<IgnorePointer>(
      find.byWidgetPredicate(
        (widget) => widget is IgnorePointer && widget.child is ColoredBox,
      ),
    );
    expect(ignore().ignoring, isTrue);
    expect(
      tester
          .widget<ExcludeSemantics>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('engine')),
                  matching: find.byType(ExcludeSemantics),
                )
                .first,
          )
          .excluding,
      isTrue,
    );
    audio.setWebsiteVisible(true);
    await tester.pumpWidget(
      MaterialApp(home: Stack(children: [audio.buildEngineView()])),
    );
    expect(bridge.builds, 1);
    expect(ignore().ignoring, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
