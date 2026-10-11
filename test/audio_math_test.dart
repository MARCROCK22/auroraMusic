import 'dart:math' as math;

import 'package:aurora_music/audio/audio_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'HTTPS decoder inputs require certificate checks and a read timeout',
    () {
      expect(ffmpegHttpsOptions('https://host/audio?signature=secret'), [
        '-tls_verify',
        '1',
        '-rw_timeout',
        '15000000',
      ]);
      expect(ffmpegHttpsOptions('HTTPS://host/audio'), [
        '-tls_verify',
        '1',
        '-rw_timeout',
        '15000000',
      ]);
      expect(ffmpegHttpsOptions('C:/music/tone.wav'), isEmpty);
    },
  );
  test('decoder errors retain HTTP status without signed URL or cookies', () {
    final error = redactAudioError(
      'HTTP 403 https://host/audio?sig=private Authorization: token\nCookie: private',
    );
    expect(error, contains('403'));
    expect(error, isNot(contains('sig=')));
    expect(error, isNot(contains('private')));
    expect(error, isNot(contains('token')));
  });
  test('EQ decibels map to native linear gain with bounded boost', () {
    expect(equalizerGain(0), 1);
    expect(equalizerGain(6), closeTo(1.9953, 0.0001));
    expect(equalizerGain(-6), closeTo(0.5012, 0.0001));
    expect(equalizerGain(100), equalizerGain(12));
  });
  test('native hard clipping preserves loud flat and EQ-preamped PCM', () {
    const sampleCount = 4096;
    final sine = List.generate(
      sampleCount,
      (i) => 0.98 * math.sin(2 * math.pi * 440 * i / 48000),
    );
    final flatOutput = sine.map(_nativeHardClip).toList();
    expect(_peak(flatOutput), lessThanOrEqualTo(1));
    expect(_rmsError(sine, flatOutput), lessThan(1e-9));

    final multitone = List.generate(sampleCount, (i) {
      final t = i / 48000;
      return 0.28 * math.sin(2 * math.pi * 440 * t) +
          0.24 * math.sin(2 * math.pi * 1000 * t) +
          0.18 * math.sin(2 * math.pi * 6000 * t);
    });
    final eqGain = equalizerGain(6);
    final preamp = 1 / eqGain;
    expect(
      _peak(multitone.map((sample) => sample * eqGain).toList()),
      greaterThan(1),
    );
    final eqOutput = multitone
        .map((sample) => _nativeHardClip(sample * eqGain * preamp))
        .toList();
    expect(eqOutput.every((sample) => sample.isFinite), isTrue);
    expect(_peak(eqOutput), lessThan(1));
    expect(_rmsError(multitone, eqOutput), lessThan(1e-9));

    final oldRoundoffOutput = sine.map(_oldRoundoffClip).toList();
    expect(_rmsError(sine, oldRoundoffOutput), greaterThan(0.1));
    expect(_oldRoundoffClip(0.1), closeTo(0.082555, 1e-6));
    expect(_oldRoundoffClip(1), closeTo(0.7315, 1e-5));
  });
  test('FFT bars preserve silence and a measured frequency peak', () {
    expect(spectrumBars(List.filled(256, 0)), everyElement(0));
    final fft = List.filled(256, 0.0)..[128] = 1;
    final bars = spectrumBars(fft);
    expect(bars.length, 48);
    expect(bars.where((value) => value > 0).length, 1);
    expect(bars.reduce((a, b) => a > b ? a : b), 1);
    fft[128] = double.nan;
    expect(spectrumBars(fft), everyElement(0));
  });
}

double _nativeHardClip(double sample) => sample.clamp(-1, 1).toDouble();

double _oldRoundoffClip(double sample) =>
    (0.87 * sample - 0.1 * sample * sample * sample) * 0.95;

double _peak(List<double> samples) =>
    samples.map((sample) => sample.abs()).reduce(math.max);

double _rmsError(List<double> expected, List<double> actual) {
  var sum = 0.0;
  for (var i = 0; i < expected.length; i++) {
    final delta = expected[i] - actual[i];
    sum += delta * delta;
  }
  return math.sqrt(sum / expected.length);
}
