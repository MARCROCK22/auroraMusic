/// Single choke point: a raw YouTube/googlevideo URL must never reach a native
/// decoder. YouTube media only arrives through the loopback AudioProxy.
const _blockedHosts = [
  'youtube.com',
  'youtu.be',
  'googlevideo.com',
  'ytimg.com',
  'ggpht.com',
];

bool _blocked(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.+$'), '');
  return _blockedHosts.any((b) => h == b || h.endsWith('.$b'));
}

void assertNotRawYouTube(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.host.isNotEmpty) {
    if (_blocked(uri.host)) {
      throw StateError('URL de YouTube sin proxy bloqueada.');
    }
    return;
  }
  // Unparseable or host-less http-ish text: refuse if it names a blocked domain.
  final raw = text.toLowerCase();
  if (RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(raw) &&
      _blockedHosts.any(raw.contains)) {
    throw StateError('URL de YouTube sin proxy bloqueada.');
  }
}
