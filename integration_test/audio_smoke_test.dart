import 'dart:io';
import 'dart:math' as math;

import 'package:aurora_music/audio/music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'support/soak_fixture.dart';

const toolsDirectory = String.fromEnvironment('AURORA_TOOLS');
const soakMinutes = int.fromEnvironment('AURORA_SOAK_MINUTES');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native WAV: clock, pause, seek, FFT and audible EQ processing', (
    tester,
  ) async {
    final passed = await tester.runAsync(() async {
      final fixture = await _fixture('wav');
      final audio = MusicAudio();
      try {
        await audio.initialize();
        // The default disabled EQ must be safe even before a filter exists.
        audio.setEqualizer(false, List.filled(8, 0));
        audio.setEqualizer(false, List.filled(8, 0));
        expect(SoLoud.instance.filters.equalizerFilter.isActive, isFalse);
        // A quiet test tone: FFT still samples genuine native mixer output.
        audio.setVolume(0.02);
        await audio.load(ResolvedAudio(input: fixture.path));
        expect(audio.duration.inMilliseconds, closeTo(8000, 30));
        await audio.play();
        await _wait(
          () => audio.position > const Duration(milliseconds: 200),
          audio: audio,
        );
        final flat = await _averagePeak(audio);
        final flatRms = await _nativeRms();
        expect(flat, greaterThan(0));
        expect(audio.lastError, isNull);

        await audio.pause();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final pausedAt = audio.position;
        await Future<void>.delayed(const Duration(milliseconds: 160));
        expect((audio.position - pausedAt).inMilliseconds.abs(), lessThan(35));
        expect(audio.spectrum.value, everyElement(0));

        await audio.seek(const Duration(seconds: 2));
        expect(audio.position.inMilliseconds, closeTo(2000, 35));
        await audio.play();
        await _wait(
          () => audio.position > const Duration(milliseconds: 2200),
          audio: audio,
        );
        // All bands cut equally: an actual DSP effect rather than a UI toggle.
        audio.setEqualizer(true, List.filled(8, -12));
        audio.setEqualizer(true, List.filled(8, -12));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        final attenuated = await _nativeRms();
        expect(
          SoLoud.instance.filters.equalizerFilter.band1.value,
          closeTo(math.pow(10, -12 / 20), 0.0001),
        );
        expect(attenuated, lessThan(flatRms * 0.4));
        audio.setEqualizer(false, const []);
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(await _nativeRms(), greaterThan(attenuated * 2));
        audio.setVisualizationEnabled(false);
        expect(audio.spectrum.value, everyElement(0));
        audio.setVisualizationEnabled(true);
        await _wait(
          () => audio.spectrum.value.any((value) => value > 0),
          audio: audio,
        );
        await audio.stop();
        expect(audio.isPlaying, isFalse);
        expect(audio.position, Duration.zero);
        expect(audio.lastError, isNull);
        return true;
      } finally {
        await audio.stop();
        audio.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await fixture.parent.delete(recursive: true);
      }
    });
    expect(passed, isTrue);
  });

  testWidgets(
    'FFmpeg PCM: native consumed clock, seek, cancellation and EOF',
    (tester) async {
      final passed = await tester.runAsync(() async {
        // WAV content with an unknown extension intentionally selects PCM decoding.
        final fixture = await _fixture('decoder');
        final audio = MusicAudio();
        final ffmpeg = Platform.isAndroid
            ? null
            : path.join(
                toolsDirectory,
                Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg',
              );
        final source = ResolvedAudio(
          input: fixture.path,
          duration: const Duration(seconds: 8),
        );
        try {
          if (!Platform.isAndroid) {
            expect(
              await File(ffmpeg!).exists(),
              isTrue,
              reason: 'AURORA_TOOLS must contain FFmpeg',
            );
          }
          await audio.initialize();
          audio.setVolume(0.02);
          await audio.load(source, ffmpegExecutable: ffmpeg);
          await audio.play();
          // 3.1 seconds of stereo f32 PCM exceeds the 1 MB buffer capacity;
          // reaching it proves playback releases space and the producer refills.
          await _wait(
            () => audio.position > const Duration(milliseconds: 3100),
            audio: audio,
          );
          expect(audio.lastError, isNull);
          expect(await _averagePeak(audio), greaterThan(0));
          await audio.pause();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final pausedAt = audio.position;
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(
            (audio.position - pausedAt).inMilliseconds.abs(),
            lessThan(35),
          );
          await audio.seek(const Duration(seconds: 3));
          expect(audio.position, const Duration(seconds: 3));
          await audio.play();
          await _wait(
            () => audio.position > const Duration(milliseconds: 3200),
            audio: audio,
          );
          expect(audio.lastError, isNull);

          // Rapid source replacement invalidates the old producer and its callbacks.
          final first = audio.load(source, ffmpegExecutable: ffmpeg);
          final second = audio.load(
            source,
            ffmpegExecutable: ffmpeg,
            start: const Duration(seconds: 1),
          );
          await Future.wait([first, second]);
          await audio.play();
          await _wait(
            () => audio.position > const Duration(milliseconds: 1200),
            audio: audio,
          );
          expect(audio.lastError, isNull);
          await audio.stop();
          expect(audio.position, Duration.zero);

          final completed = audio.completed.first.timeout(
            const Duration(seconds: 8),
          );
          await audio.load(
            source,
            ffmpegExecutable: ffmpeg,
            start: const Duration(milliseconds: 7500),
          );
          await audio.play();
          await completed;
          expect(audio.isPlaying, isFalse);
          expect(audio.position, const Duration(seconds: 8));
          expect(audio.lastError, isNull);
          // A decoder can finish cleanly even when the download validator fails
          // late. That must become a playback error, never a queue completion.
          var validationCalls = 0;
          var lateCompletions = 0;
          final lateSubscription = audio.completed.listen(
            (_) => lateCompletions++,
          );
          try {
            await audio.load(
              ResolvedAudio(
                input: fixture.path,
                duration: const Duration(seconds: 8),
                validateCompletion: () async {
                  validationCalls++;
                  throw StateError('Fixture: full download validation failed');
                },
              ),
              ffmpegExecutable: ffmpeg,
              start: const Duration(milliseconds: 7500),
            );
            await audio.play();
            await _wait(() => audio.lastError != null);
            expect(validationCalls, 1);
            expect(audio.isPlaying, isFalse);
            expect(lateCompletions, 0);
          } finally {
            await lateSubscription.cancel();
          }
          return true;
        } finally {
          await audio.stop();
          audio.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await fixture.parent.delete(recursive: true);
        }
      });
      expect(passed, isTrue);
    },
    skip: !Platform.isAndroid && toolsDirectory.isEmpty,
  );

  testWidgets(
    'native audio soak: uninterrupted clock and bounded memory report',
    (tester) async {
      final passed = await tester.runAsync(() async {
        final audio = MusicAudio();
        final fixture = await createSoakFixture(soakMinutes * 60 + 20);
        try {
          await audio.initialize();
          audio.setVolume(0.005);
          await audio.load(ResolvedAudio(input: fixture.path));
          await audio.play();
          await _wait(
            () => audio.position > const Duration(milliseconds: 500),
            audio: audio,
          );
          final elapsed = Stopwatch()..start();
          // Ignore initialization warm-up when reporting steady-state RSS.
          await Future<void>.delayed(const Duration(seconds: 10));
          final baseline = ProcessInfo.currentRss;
          var maximum = baseline;
          var previous = audio.position;
          while (elapsed.elapsed < Duration(minutes: soakMinutes)) {
            await Future<void>.delayed(const Duration(seconds: 10));
            expect(audio.lastError, isNull);
            expect(audio.isPlaying, isTrue);
            expect(audio.isBuffering, isFalse);
            expect(
              (audio.position - previous).inMilliseconds,
              greaterThan(8000),
              reason: 'Playback clock must continue advancing during the soak',
            );
            previous = audio.position;
            maximum = math.max(maximum, ProcessInfo.currentRss);
            debugPrint(
              'AURORA_SOAK elapsed=${elapsed.elapsed.inSeconds}s position=${audio.position.inSeconds}s rss=${ProcessInfo.currentRss} maxRss=$maximum baseline=$baseline',
            );
          }
          debugPrint(
            'AURORA_SOAK_COMPLETE minutes=$soakMinutes maxGrowthBytes=${maximum - baseline}',
          );
          // RSS includes VM/JIT and graphics allocations. Report its growth rather
          // than treating a fixed machine-specific RSS limit as a DSP invariant.
          return true;
        } finally {
          await audio.stop();
          audio.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await fixture.parent.delete(recursive: true);
        }
      });
      expect(passed, isTrue);
    },
    skip: soakMinutes <= 0,
    timeout: Timeout(Duration(minutes: soakMinutes + 3)),
  );
}

Future<void> _wait(bool Function() condition, {MusicAudio? audio}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!condition()) {
    if (audio?.lastError != null) {
      fail('Native audio error: ${audio!.lastError}');
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Native audio condition did not complete in 8 seconds; position=${audio?.position} playing=${audio?.isPlaying} buffering=${audio?.isBuffering} error=${audio?.lastError}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

Future<double> _averagePeak(MusicAudio audio) async {
  var total = 0.0;
  for (var index = 0; index < 6; index++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    total += audio.spectrum.value.fold(0.0, math.max);
  }
  return total / 6;
}

// The plugin's display FFT is logarithmic, spectrally scaled and smoothed.
// Verify DSP gain against unscaled mixer waveform energy instead of UI bars.
Future<double> _nativeRms() async {
  final wave = AudioData(GetSamplesKind.wave);
  try {
    var squared = 0.0;
    var count = 0;
    for (var index = 0; index < 6; index++) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      wave.updateSamples();
      for (final value in wave.getAudioData()) {
        squared += value * value;
        count++;
      }
    }
    return math.sqrt(squared / count);
  } finally {
    wave.dispose();
  }
}

Future<File> _fixture(String extension) async {
  const rate = 48000, frames = rate * 8, channels = 2;
  final bytes = ByteData(44 + frames * channels * 2);
  void text(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, bytes.lengthInBytes - 44, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    final sample = (math.sin(2 * math.pi * 375 * frame / rate) * 0.2 * 32767)
        .round();
    for (var channel = 0; channel < channels; channel++) {
      bytes.setInt16(
        44 + (frame * channels + channel) * 2,
        sample,
        Endian.little,
      );
    }
  }
  final directory = await Directory.systemTemp.createTemp('aurora_audio_test_');
  return File(
    path.join(directory.path, 'tone.$extension'),
  ).writeAsBytes(bytes.buffer.asUint8List());
}
