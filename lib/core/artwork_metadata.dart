/// Resolution hints from provider resize parameters and YouTube thumbnail names.
/// Unknown dimensions stay zero; they are never displayed as measured metadata.
int artworkWidthHint(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null) return 0;
  for (final name in ['width', 'w']) {
    final width = int.tryParse(uri.queryParameters[name] ?? '') ?? 0;
    if (width > 0 && width <= 16384) return width;
  }
  final resize = RegExp(r'=([ws])(\d+)(?:[-/]|$)').firstMatch(uri.path);
  if (resize != null) {
    final width = int.tryParse(resize.group(2)!) ?? 0;
    if (width > 0 && width <= 16384) return width;
  }
  final filename = uri.pathSegments.lastOrNull?.toLowerCase() ?? '';
  for (final entry in const {
    'maxresdefault': 1280,
    'sddefault': 640,
    'hqdefault': 480,
    'mqdefault': 320,
    'default': 120,
  }.entries) {
    if (filename.startsWith('${entry.key}.')) return entry.value;
  }
  return 0;
}
