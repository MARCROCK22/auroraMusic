import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/audio/audio_math.dart';

void main() {
  const duration = Duration(minutes: 3);

  test('completes only after clean EOF and full decoded audio is consumed', () {
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: true,
        decoded: duration,
        consumed: duration,
        expected: duration,
      ),
      isTrue,
    );
  });

  test('allows float32 time rounding at long track durations', () {
    const sampleRate = 48000;
    const sampleCount = 600 * sampleRate + 4;
    final decoded = Duration(
      microseconds: sampleCount * Duration.microsecondsPerSecond ~/ sampleRate,
    );
    final bytes = ByteData(4)
      ..setFloat32(0, decoded.inMicroseconds / Duration.microsecondsPerSecond);
    final nativeSeconds = bytes.getFloat32(0);
    final consumed = Duration(
      microseconds: (nativeSeconds * Duration.microsecondsPerSecond).round(),
    );

    expect(consumed, lessThan(decoded));
    expect(decoded - consumed, greaterThan(const Duration(microseconds: 21)));
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: true,
        decoded: decoded,
        consumed: consumed,
        expected: decoded,
      ),
      isTrue,
    );
  });

  test('rejects incomplete EOF and streams shorter than known duration', () {
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: false,
        decoded: duration,
        consumed: duration,
        expected: duration,
      ),
      isFalse,
    );
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: true,
        decoded: const Duration(minutes: 2),
        consumed: const Duration(minutes: 2),
        expected: duration,
      ),
      isFalse,
    );
  });

  test('a clean EOF rejects any decoded shortfall against known duration', () {
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: true,
        decoded: duration,
        consumed: duration,
        expected: duration,
      ),
      isTrue,
    );
    expect(
      isCompleteAudioStream(
        isPlaying: true,
        isBuffering: false,
        cleanEof: true,
        decoded: duration - const Duration(milliseconds: 1),
        consumed: duration - const Duration(milliseconds: 1),
        expected: duration,
      ),
      isFalse,
    );
  });

  test('only the newest seek may restore current play intent', () {
    expect(
      shouldResumeAfterSeek(request: 4, latestRequest: 4, playIntent: true),
      isTrue,
    );
    expect(
      shouldResumeAfterSeek(request: 3, latestRequest: 4, playIntent: true),
      isFalse,
    );
    expect(
      shouldResumeAfterSeek(request: 4, latestRequest: 4, playIntent: false),
      isFalse,
    );
  });

  test(
    'does not complete while paused, buffering, or before full consumption',
    () {
      for (final state in [
        (playing: false, buffering: false, consumed: duration),
        (playing: true, buffering: true, consumed: duration),
        (
          playing: true,
          buffering: false,
          consumed: duration - const Duration(seconds: 1),
        ),
        (
          playing: true,
          buffering: false,
          consumed: duration - const Duration(milliseconds: 22),
        ),
      ]) {
        expect(
          isCompleteAudioStream(
            isPlaying: state.playing,
            isBuffering: state.buffering,
            cleanEof: true,
            decoded: duration,
            consumed: state.consumed,
            expected: duration,
          ),
          isFalse,
        );
      }
    },
  );
}
