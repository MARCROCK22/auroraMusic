import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:aurora_music/youtube_music/youtube_music_ad_blocker.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeFilterController extends AdBlockerWebviewControllerImpl {
  bool failInit = false;
  bool failMatch = false;
  int matches = 0;
  int initializations = 0;
  FilterConfig? config;

  @override
  Future<void> initialize(FilterConfig filterConfig) async {
    initializations++;
    config = filterConfig;
    if (failInit) throw StateError('Missing filter assets');
  }

  @override
  bool shouldBlockResource(String url) {
    matches++;
    if (failMatch) throw StateError('Matcher failed');
    return Uri.parse(url).host.endsWith('doubleclick.net');
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'package filter API loads bundled lists offline and matches an ad origin',
    () async {
      final blocker = YouTubeMusicAdBlocker();
      await blocker.initialize();
      expect(blocker.status, YouTubeMusicAdBlockStatus.ready);
      expect(
        blocker.shouldBlock(
          Uri.parse('https://ad.doubleclick.net/activity'),
          isTopLevel: false,
        ),
        isTrue,
      );
      expect(
        blocker.shouldBlock(
          Uri.parse('https://music.youtube.com/watch?v=example'),
          isTopLevel: false,
        ),
        isFalse,
      );
      blocker.dispose();
    },
  );

  test(
    'filters only ad resources, protects top-level/media/auth/CDN origins',
    () async {
      final filter = FakeFilterController();
      final blocker = YouTubeMusicAdBlocker(controller: filter);
      await blocker.initialize();
      expect(filter.config!.filterTypes, [
        FilterType.easyList,
        FilterType.adGuard,
      ]);
      expect(
        blocker.shouldBlock(
          Uri.parse('https://ad.doubleclick.net/activity'),
          isTopLevel: false,
        ),
        isTrue,
      );
      expect(
        blocker.shouldBlock(
          Uri.parse('https://ad.doubleclick.net/activity'),
          isTopLevel: true,
        ),
        isFalse,
      );
      for (final url in [
        'https://music.youtube.com/watch?v=example',
        'https://accounts.google.com/ServiceLogin',
        'https://consent.google.com/',
        'https://r1.googlevideo.com/videoplayback?signature=example',
        'https://i.ytimg.com/vi/example/default.jpg',
        'https://youtubei.googleapis.com/youtubei/v1/player',
        'https://lh3.googleusercontent.com/example',
        'https://yt3.ggpht.com/example',
        'https://www.gstatic.com/example',
        'data:text/plain,example',
        'https://user:secret@ad.doubleclick.net/',
      ]) {
        expect(
          blocker.shouldBlock(Uri.parse(url), isTopLevel: false),
          isFalse,
          reason: url,
        );
      }
      expect(
        filter.matches,
        1,
        reason: 'Protected URLs never enter the matcher or statistics',
      );
      blocker.setEnabled(false);
      expect(
        blocker.shouldBlock(
          Uri.parse('https://ad.doubleclick.net/'),
          isTopLevel: false,
        ),
        isFalse,
      );
      expect(filter.matches, 1);
      blocker.dispose();
    },
  );

  test('filter failure permits official website and can recover', () async {
    final filter = FakeFilterController()..failInit = true;
    final blocker = YouTubeMusicAdBlocker(controller: filter);
    await blocker.initialize();
    expect(blocker.status, YouTubeMusicAdBlockStatus.failed);
    expect(
      blocker.shouldBlock(
        Uri.parse('https://ad.doubleclick.net/'),
        isTopLevel: false,
      ),
      isFalse,
    );
    filter.failInit = false;
    await blocker.initialize();
    expect(blocker.status, YouTubeMusicAdBlockStatus.ready);
    filter.failMatch = true;
    expect(
      blocker.shouldBlock(
        Uri.parse('https://ad.doubleclick.net/'),
        isTopLevel: false,
      ),
      isFalse,
    );
    expect(blocker.status, YouTubeMusicAdBlockStatus.failed);
    blocker.dispose();
  });
}
