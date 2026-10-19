import 'dart:convert';
import 'dart:math' as math;

const eqBandCount = 8;
const eqMinDb = -12.0, eqMaxDb = 12.0;
const eqMinHz = 20.0, eqMaxHz = 20000.0;
const eqMinQ = 0.3, eqMaxQ = 10.0;
const eqSampleRate = 48000.0;

double _bounded(Object? value, double min, double max, double fallback) {
  final v = value is num ? value.toDouble() : fallback;
  return v.isFinite ? v.clamp(min, max).toDouble() : fallback;
}

/// Una banda paramétrica (filtro peaking RBJ): frecuencia, ganancia y Q.
/// Los valores siempre quedan dentro de rango y son finitos.
class EqBand {
  EqBand(double frequency, [double gainDb = 0, double q = 1])
    : frequency = _bounded(frequency, eqMinHz, eqMaxHz, 1000),
      gainDb = _bounded(gainDb, eqMinDb, eqMaxDb, 0),
      q = _bounded(q, eqMinQ, eqMaxQ, 1);

  factory EqBand.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return EqBand(
      _bounded(map['frequency'], eqMinHz, eqMaxHz, 1000),
      _bounded(map['gainDb'], eqMinDb, eqMaxDb, 0),
      _bounded(map['q'], eqMinQ, eqMaxQ, 1),
    );
  }

  final double frequency, gainDb, q;

  EqBand copyWith({double? frequency, double? gainDb, double? q}) =>
      EqBand(frequency ?? this.frequency, gainDb ?? this.gainDb, q ?? this.q);

  Map<String, Object> toJson() => {
    'frequency': frequency,
    'gainDb': gainDb,
    'q': q,
  };

  @override
  bool operator ==(Object other) =>
      other is EqBand &&
      other.frequency == frequency &&
      other.gainDb == gainDb &&
      other.q == q;

  @override
  int get hashCode => Object.hash(frequency, gainDb, q);
}

const eqDefaultFrequencies = [
  60.0,
  170.0,
  310.0,
  600.0,
  1000.0,
  3000.0,
  6000.0,
  12000.0,
];

List<EqBand> eqFlatBands() => [for (final f in eqDefaultFrequencies) EqBand(f)];

/// Bandas por defecto con las ganancias dadas (las que falten quedan en 0).
List<EqBand> eqBandsWithGains(List<double> gains) => [
  for (var i = 0; i < eqBandCount; i++)
    EqBand(eqDefaultFrequencies[i], i < gains.length ? gains[i] : 0),
];

class EqPreset {
  EqPreset(this.name, List<EqBand> bands, {this.builtIn = false})
    : bands = List.unmodifiable(_normalize(bands));
  final String name;
  final List<EqBand> bands;
  final bool builtIn;

  static List<EqBand> _normalize(List<EqBand> bands) => [
    for (var i = 0; i < eqBandCount; i++)
      i < bands.length ? bands[i] : EqBand(eqDefaultFrequencies[i]),
  ];

  Map<String, Object> toJson() => {
    'name': name,
    'bands': [for (final b in bands) b.toJson()],
  };

  /// Null si el JSON no describe un preset utilizable.
  static EqPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final bands = json['bands'];
    if (name is! String || name.trim().isEmpty || bands is! List) return null;
    if (bands.isEmpty || bands.length > eqBandCount) return null;
    return EqPreset(
      name.trim().length > 40 ? name.trim().substring(0, 40) : name.trim(),
      [for (final b in bands) EqBand.fromJson(b)],
    );
  }
}

final eqBuiltInPresets = <EqPreset>[
  EqPreset('Plano', eqFlatBands(), builtIn: true),
  EqPreset(
    'Graves',
    eqBandsWithGains([6, 3, 0, -1, -2, -2, -2, 0]),
    builtIn: true,
  ),
  EqPreset(
    'Vocal',
    eqBandsWithGains([-3, 2, 4, 2, -1, -2, -2, 0]),
    builtIn: true,
  ),
  EqPreset('Rock', eqBandsWithGains([4, 1, -2, 1, 3, 2, 1, 0]), builtIn: true),
];

/// Exporta presets propios como JSON (formato versionado).
String eqPresetsToJson(List<EqPreset> presets) =>
    const JsonEncoder.withIndent('  ').convert({
      'aurora_eq': 1,
      'presets': [for (final p in presets) p.toJson()],
    });

/// Lee un JSON exportado (uno o varios presets). Lanza FormatException si no
/// contiene ningún preset válido.
List<EqPreset> eqPresetsFromJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('El texto no es un JSON válido.');
  }
  final items = decoded is Map && decoded['presets'] is List
      ? decoded['presets'] as List
      : decoded is Map && decoded['bands'] != null
      ? [decoded]
      : decoded is List
      ? decoded
      : const [];
  final presets = [for (final item in items.take(50)) ?EqPreset.fromJson(item)];
  if (presets.isEmpty) {
    throw const FormatException('No se encontró ningún preset válido.');
  }
  return presets;
}

/// Coeficientes biquad normalizados (a0 = 1) de un filtro peaking RBJ.
/// Orden: b0, b1, b2, a1, a2.
List<double> peakingCoefficients(
  double sampleRate,
  double frequency,
  double gainDb,
  double q,
) {
  final a = math.pow(10, gainDb / 40).toDouble();
  // Por debajo de Nyquist, o el seno/coseno degeneran.
  final f = frequency.clamp(1, sampleRate * 0.49).toDouble();
  final w0 = 2 * math.pi * f / sampleRate;
  final alpha = math.sin(w0) / (2 * q);
  final cosW = math.cos(w0);
  final a0 = 1 + alpha / a;
  return [
    (1 + alpha * a) / a0,
    -2 * cosW / a0,
    (1 - alpha * a) / a0,
    -2 * cosW / a0,
    (1 - alpha / a) / a0,
  ];
}

/// Respuesta en dB de un filtro biquad en [frequency].
double biquadResponseDb(List<double> c, double frequency, double sampleRate) {
  final w = 2 * math.pi * frequency / sampleRate;
  final cos1 = math.cos(w), cos2 = math.cos(2 * w);
  final num =
      c[0] * c[0] +
      c[1] * c[1] +
      c[2] * c[2] +
      2 * (c[0] * c[1] + c[1] * c[2]) * cos1 +
      2 * c[0] * c[2] * cos2;
  final den =
      1 +
      c[3] * c[3] +
      c[4] * c[4] +
      2 * (c[3] + c[3] * c[4]) * cos1 +
      2 * c[4] * cos2;
  return 10 * math.log(math.max(num, 1e-30) / math.max(den, 1e-30)) / math.ln10;
}

/// Respuesta combinada (dB) de las bandas en [frequency].
double eqResponseDb(
  List<EqBand> bands,
  double frequency, [
  double sampleRate = eqSampleRate,
]) {
  var total = 0.0;
  for (final b in bands) {
    if (b.gainDb == 0) continue;
    total += biquadResponseDb(
      peakingCoefficients(sampleRate, b.frequency, b.gainDb, b.q),
      frequency,
      sampleRate,
    );
  }
  return total;
}

/// Curva de 20 Hz a 20 kHz en escala logarítmica, para dibujarla y calcular
/// el pico.
List<double> eqResponseCurve(List<EqBand> bands, {int points = 96}) => [
  for (var i = 0; i < points; i++)
    eqResponseDb(
      bands,
      eqMinHz * math.pow(eqMaxHz / eqMinHz, i / (points - 1)),
    ),
];

/// Ganancia lineal que compensa el pico de la curva para que el EQ no
/// recorte: 1 si la curva nunca supera 0 dB.
double eqAutoPreamp(List<EqBand> bands) {
  var peak = 0.0;
  for (final db in eqResponseCurve(bands, points: 128)) {
    if (db.isFinite) peak = math.max(peak, db);
  }
  return math.pow(10, -peak / 20).toDouble();
}
