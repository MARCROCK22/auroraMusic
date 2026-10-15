/// Single choke point: a raw YouTube/googlevideo URL must never reach a native
/// decoder. YouTube media only arrives through the loopback AudioProxy.
const _blockedHosts = [
  'youtube.com',
  'youtu.be',
  'googlevideo.com',
  'ytimg.com',
  'ggpht.com',
];

void assertNotRawYouTube(String input) {
  final host = Uri.tryParse(input)?.host.toLowerCase() ?? '';
  if (_blockedHosts.any((h) => host == h || host.endsWith('.$h'))) {
    throw StateError('URL de YouTube sin proxy bloqueada.');
  }
}
