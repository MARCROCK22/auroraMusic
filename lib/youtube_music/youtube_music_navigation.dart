/// Only these exact HTTPS origins may replace the visible official page.
/// Resource requests and subframes remain under the website's control.
enum YouTubeMusicNavigation { allow, signInInBrowser, block }

final youtubeMusicHome = Uri.parse('https://music.youtube.com/');

YouTubeMusicNavigation classifyYouTubeMusicNavigation(Uri? uri) {
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return YouTubeMusicNavigation.block;
  }
  if (uri.host == 'accounts.google.com') {
    // Use a normal browser rather than attempting embedded Google sign-in.
    return YouTubeMusicNavigation.signInInBrowser;
  }
  if (const {
    'music.youtube.com',
    'consent.youtube.com',
    'consent.google.com',
  }.contains(uri.host)) {
    return YouTubeMusicNavigation.allow;
  }
  return YouTubeMusicNavigation.block;
}
