import 'dart:math' as math;

double equalizerGain(double db) =>
    math.pow(10, db.clamp(-12, 12) / 20).toDouble();

/// Input-scoped HTTPS options; Schannel checks the Windows certificate store.
List<String> ffmpegHttpsOptions(String input) =>
    Uri.tryParse(input)?.scheme == 'https'
    ? const ['-tls_verify', '1', '-rw_timeout', '15000000']
    : const [];

String redactAudioError(Object error) => '$error'
    .replaceAll(RegExp(r'https?://[^\s<>"\x27]+'), '[recurso remoto]')
    .replaceAll(
      RegExp(r'(authorization|cookie):[^\r\n]+', caseSensitive: false),
      '[cabecera privada]',
    );

/// Log-frequency display bars from the native mixer's first 256 FFT bins.
List<double> spectrumBars(List<double> fft) {
  if (fft.length < 256) return List.filled(48, 0);
  return List.generate(48, (index) {
    final lo = math.pow(256, index / 48).floor().clamp(0, 255);
    final hi = math
        .max(lo + 1, math.pow(256, (index + 1) / 48).floor())
        .clamp(1, 256);
    var peak = 0.0;
    for (var bin = lo; bin < hi; bin++) {
      if (fft[bin].isFinite) peak = math.max(peak, fft[bin]);
    }
    return (math.log(1 + peak * 30) / math.log(31)).clamp(0, 1).toDouble();
  });
}
