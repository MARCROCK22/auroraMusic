import 'dart:math' as math;
import 'dart:typed_data';

import 'eq_model.dart';

/// Limitador de codo suave: lineal hasta [eqLimiterKnee] y asintótico a 1, así
/// ningún pico supera la escala completa ni se recorta en duro.
const eqLimiterKnee = 0.95;

double softLimit(double x) {
  final a = x.abs();
  if (a <= eqLimiterKnee) return x;
  const room = 1 - eqLimiterKnee;
  final y = eqLimiterKnee + room * _tanh((a - eqLimiterKnee) / room);
  return x < 0 ? -y : y;
}

double _tanh(double x) {
  if (x > 20) return 1;
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}

/// Ecualizador paramétrico estéreo de 8 bandas peaking (RBJ, forma
/// transpuesta II) sobre PCM float32 entrelazado.
///
/// Todo cambio (ganancia, frecuencia, Q, activación, preamp) se acerca al
/// objetivo con una rampa exponencial de ~[timeConstantMs] ms, actualizada cada
/// [blockFrames] muestras, para que mover un deslizador no produzca clics ni
/// saltos de volumen. Con el EQ apagado y la rampa terminada, [process] no toca
/// el audio.
class ParametricEqualizer {
  ParametricEqualizer({
    this.sampleRate = eqSampleRate,
    this.channels = 2,
    double timeConstantMs = 12,
  }) : _smoothing =
           1 - math.exp(-blockFrames / (sampleRate * timeConstantMs / 1000)),
       _bands = [for (final f in eqDefaultFrequencies) _BandState(f, channels)];

  static const blockFrames = 32;
  final double sampleRate;
  final int channels;
  final double _smoothing;
  final List<_BandState> _bands;

  bool _targetEnabled = false;
  double _targetPreamp = 1;
  double _mix = 0, _preamp = 1;

  /// El EQ no modifica el audio y no hay rampa pendiente.
  bool get isIdle => !_targetEnabled && _mix == 0;

  void configure({
    required bool enabled,
    required List<EqBand> bands,
    bool autoPreamp = true,
  }) {
    // Un EQ que estaba apagado no arrastra el estado de audio antiguo.
    if (isIdle && enabled) {
      for (final band in _bands) {
        band.reset();
      }
    }
    _targetEnabled = enabled;
    for (var i = 0; i < _bands.length; i++) {
      final b = i < bands.length ? bands[i] : EqBand(eqDefaultFrequencies[i]);
      _bands[i].setTarget(b);
    }
    final active = [
      for (var i = 0; i < _bands.length; i++)
        if (i < bands.length) bands[i],
    ];
    _targetPreamp = enabled && autoPreamp ? eqAutoPreamp(active) : 1;
  }

  /// Procesa [pcm] en el sitio. Muestras no finitas se tratan como silencio.
  void process(Float32List pcm) {
    if (isIdle) return;
    final frames = pcm.length ~/ channels;
    for (var start = 0; start < frames; start += blockFrames) {
      final end = math.min(start + blockFrames, frames);
      _advance();
      if (_mix == 0 && !_targetEnabled) continue;
      for (var ch = 0; ch < channels; ch++) {
        for (var n = start; n < end; n++) {
          final index = n * channels + ch;
          final dry = pcm[index].isFinite ? pcm[index] : 0.0;
          var wet = dry;
          for (final band in _bands) {
            if (band.active) wet = band.run(ch, wet);
          }
          if (!wet.isFinite) {
            for (final band in _bands) {
              band.reset();
            }
            wet = dry;
          }
          pcm[index] = softLimit(dry + (wet * _preamp - dry) * _mix);
        }
      }
    }
  }

  void _advance() {
    for (final band in _bands) {
      band.advance(_smoothing, sampleRate);
    }
    _mix = _approach(_mix, _targetEnabled ? 1 : 0);
    _preamp = _approach(_preamp, _targetPreamp);
  }

  double _approach(double current, double target) {
    final next = current + (target - current) * _smoothing;
    return (next - target).abs() < 1e-5 ? target : next;
  }
}

class _BandState {
  _BandState(double frequency, int channels)
    : _f = math.log(frequency),
      _tf = math.log(frequency),
      _s1 = Float64List(channels),
      _s2 = Float64List(channels);

  // Frecuencia y Q se interpolan en el dominio logarítmico, la ganancia en dB.
  double _f, _tf, _g = 0, _tg = 0, _q = 0, _tq = 0;
  bool _configured = false;
  final Float64List _s1, _s2;
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  bool active = false;
  bool _dirty = false;

  void setTarget(EqBand band) {
    _tf = math.log(band.frequency);
    _tg = band.gainDb;
    _tq = math.log(band.q);
    // La primera vez la Q parte directamente del objetivo.
    if (!_configured) _q = _tq;
    _configured = true;
  }

  void reset() {
    _s1.fillRange(0, _s1.length, 0);
    _s2.fillRange(0, _s2.length, 0);
  }

  void advance(double k, double sampleRate) {
    if (_f != _tf || _g != _tg || _q != _tq || _dirty) {
      _f = _step(_f, _tf, k, 1e-4);
      _g = _step(_g, _tg, k, 1e-3);
      _q = _step(_q, _tq, k, 1e-4);
      final c = peakingCoefficients(sampleRate, math.exp(_f), _g, math.exp(_q));
      _b0 = c[0];
      _b1 = c[1];
      _b2 = c[2];
      _a1 = c[3];
      _a2 = c[4];
      _dirty = _f != _tf || _g != _tg || _q != _tq;
      // Una banda a 0 dB es la identidad: se salta y su estado se descarta.
      final wasActive = active;
      active = _g != 0 || _dirty;
      if (wasActive && !active) reset();
    }
  }

  static double _step(double c, double t, double k, double snap) {
    final next = c + (t - c) * k;
    return (next - t).abs() < snap ? t : next;
  }

  double run(int ch, double x) {
    final y = _b0 * x + _s1[ch];
    _s1[ch] = _b1 * x - _a1 * y + _s2[ch];
    _s2[ch] = _b2 * x - _a2 * y;
    return y;
  }
}
