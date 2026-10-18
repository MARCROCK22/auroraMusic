/// Limpieza de metadatos de YouTube y puntuación de candidatos de letras.
library;

enum LyricsConfidence { high, medium, low }

const _accents = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
};

/// Minúsculas, sin acentos latinos y solo letras/números (también kana, kanji…).
String normalizeLyricsKey(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

List<String> _tokens(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_accents[ch] ?? ch);
  }
  return b
      .toString()
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((t) => t.isNotEmpty)
      .toList();
}

final _noise = RegExp(
  r'official|oficial|video|vídeo|audio|lyric|letra|visuali[sz]er|\bhd\b|\bhq\b|\b4k\b|'
  r'remaster|\bmv\b|m/v|clip|subtitulad|sub\s*esp|explicit|feat\.?|\bft\.?|featuring|'
  r'\bwith\b|prod\.|topic|full\s*(song|album)|music|en vivo hd|\d{4}\s*(mix|version)',
  caseSensitive: false,
);

/// Artista principal para consultar: sin «- Topic», «VEVO» ni colaboradores.
String cleanArtist(String artist) {
  var a = artist
      .replaceAll(RegExp(r'\s*-\s*Topic\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*VEVO\s*$', caseSensitive: false), '')
      .replaceAll(
        RegExp(
          r'\s*(official|oficial)(\s+(channel|artist))?\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  a = a
      .split(
        RegExp(
          r'\s*(?:,|;|\bfeat\.?|\bft\.?|\bfeaturing\b)\s*',
          caseSensitive: false,
        ),
      )
      .first
      .trim();
  return a;
}

/// Título limpio: quita ruido de YouTube pero conserva «live», «remix», etc.
String cleanTitle(String title, {String artist = ''}) {
  var t = title.trim();
  // «Artista - Canción»
  final split = RegExp(r'^(.+?)\s+[-–—|]\s+(.+)$').firstMatch(t);
  if (split != null && artist.isNotEmpty) {
    final head = normalizeLyricsKey(split.group(1)!);
    final a = normalizeLyricsKey(cleanArtist(artist));
    if (a.isNotEmpty && (head == a || head.contains(a) || a.contains(head))) {
      t = split.group(2)!;
    }
  }
  t = t.replaceAllMapped(RegExp(r'\s*[\(\[【「][^\)\]】」]*[\)\]】」]'), (m) {
    return _noise.hasMatch(m.group(0)!) ? '' : m.group(0)!;
  });
  t = t
      .replaceAll(
        RegExp(
          r'\s*[-–—|]\s*(\d{4}\s+)?(remaster(ed)?|digital remaster|mono|stereo)(\s+(version|\d{4}))?\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'\s*[-–—|]\s*(official\s+)?(music\s+)?(video|audio|lyrics?|visuali[sz]er)(\s+\w+)*\s*$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(r'\s+(feat\.?|ft\.?|featuring)\s+.*$', caseSensitive: false),
        '',
      )
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
  return t.isEmpty ? title.trim() : t;
}

final _versionMarks = RegExp(
  r'\b(live|en vivo|remix|acoustic|ac[uú]stic[oa]|karaoke|instrumental|cover|sped up|slowed|nightcore|demo)\b',
  caseSensitive: false,
);

Set<String> _marks(String s) =>
    _versionMarks.allMatches(s).map((m) => m.group(1)!.toLowerCase()).toSet();

double _similarity(String a, String b) {
  final ka = normalizeLyricsKey(a), kb = normalizeLyricsKey(b);
  if (ka.isEmpty || kb.isEmpty) return 0;
  if (ka == kb) return 1;
  if (ka.contains(kb) || kb.contains(ka)) {
    return .8 *
        (ka.length < kb.length ? ka.length / kb.length : kb.length / ka.length)
            .clamp(.5, 1);
  }
  final ta = _tokens(a).toSet(), tb = _tokens(b).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  return ta.intersection(tb).length / ta.union(tb).length;
}

/// Resultado de evaluar un candidato contra la pista.
class LyricsMatch {
  const LyricsMatch(
    this.score, {
    required this.acceptable,
    required this.syncOk,
  });
  final double score;
  final bool acceptable;

  /// La duración coincide (±3 s o desconocida): se puede confiar en la sincronía.
  final bool syncOk;
  LyricsConfidence get confidence => score >= .85
      ? LyricsConfidence.high
      : score >= .7
      ? LyricsConfidence.medium
      : LyricsConfidence.low;
}

const syncToleranceSeconds = 3;

LyricsMatch scoreLyricsCandidate({
  required String wantedArtist,
  required String wantedTitle,
  required int wantedSeconds,
  required String artist,
  required String title,
  num? seconds,
}) {
  final titleScore = _similarity(cleanTitle(title), wantedTitle);
  // El artista pedido puede traer colaboradores: vale cualquiera de sus partes.
  final artistScore = [
    wantedArtist,
    ...wantedArtist.split(
      RegExp(r'\s*(?:,|&|;|\band\b|\by\b|\bx\b)\s*', caseSensitive: false),
    ),
  ].map((w) => _similarity(artist, w)).fold<double>(0, (a, b) => a > b ? a : b);
  final known = wantedSeconds > 0 && seconds != null && seconds > 0;
  final diff = known ? (seconds - wantedSeconds).abs() : 0;
  final durScore = !known
      ? .6
      : diff <= syncToleranceSeconds
      ? 1.0
      : diff <= 8
      ? .5
      : 0.0;
  var score = .45 * titleScore + .3 * artistScore + .25 * durScore;
  final wm = _marks(wantedTitle), cm = _marks(title);
  if (wm.length != cm.length || !wm.containsAll(cm)) score -= .3;
  final ok =
      titleScore >= .6 &&
      artistScore >= .5 &&
      score >= .65 &&
      (!known || diff <= 30);
  return LyricsMatch(
    score,
    acceptable: ok,
    syncOk: !known || diff <= syncToleranceSeconds,
  );
}
