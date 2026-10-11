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
