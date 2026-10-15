> El reproductor de YouTube de Aurora vive ahora en `lib/audio_web/` (ver [docs/youtube_music_audio_engine.md](../../docs/youtube_music_audio_engine.md)); esta vista visible no se usa en la interfaz.

# Official YouTube Music view

`youtube_music_page.dart` exports `YouTubeMusicPage` and the test platform seam.

```dart
final musicPageKey = GlobalKey<YouTubeMusicPageState>();

YouTubeMusicPage(
  key: musicPageKey,
  initialUri: Uri.parse('https://music.youtube.com/'),
  onClosed: returnToAurora,
);

// Before shell navigation removes the visible page:
if (await musicPageKey.currentState?.confirmExit() ?? true) {
  returnToAurora();
}
```

`confirmExit()` returns a decision and never calls `onClosed` itself. Playback is
unknown, so it confirms conservatively; it does not run JavaScript to inspect or
change media. `handleBack()` traverses website history before confirming and
calling `onClosed`, or popping a route when no callback was supplied. Embedded
shells must supply `onClosed`, including for Android root-route exit handling.
Pause Aurora's native player before entering, in the shell/controller layer.

The visible view stays mounted through toolbar and loading updates. Remove it
when leaving; do not keep an invisible WebView playing. Search, queue,
account restrictions and playback belong to the official site. Background,
screen-off, hardware controls, sign-in and audible playback have **not** been
verified on real devices. Google accounts navigation offers an external browser
instead of attempting embedded sign-in. Browser and WebView profiles are separate;
opening the browser does not sign the embedded view in.

## Dependencies and platform setup

- `flutter_inappwebview: 6.1.5` (stable), Android implementation `1.1.3`, Windows
  implementation `0.6.0`; `url_launcher: 6.3.2`.
- Requested `adblocker_webview: 2.3.0`, filter manager/core `1.1.0`;
  its dependencies resolve to `webview_flutter 4.14.1`, Android `4.12.0`,
  WKWebView `3.25.1`, but its supplied WebView widget is not mounted.
- Android uses existing Internet permission, AndroidX, hardware acceleration and
  API 24 minimum; no manifest or Gradle changes were needed.
- Windows needs NuGet on `PATH`, Visual Studio's Flutter build tools and installed
  WebView2 Runtime. Its normal persistent profile lives in the app support
  directory's `youtube_music_webview` folder, outside the installed executable.
- Cookies and DOM storage use native defaults. No cookie export, user-agent
  override, TLS exception, user script, extraction or playback command is added.
- Only exact HTTPS origins `music.youtube.com`, `consent.youtube.com` and
  `consent.google.com` may navigate the visible top-level view. Google Accounts
  navigation is cancelled with an external-browser action; other origins and
  schemes are rejected. Frames/resources retain official website behavior
  except optional ad-resource filtering described below.
- Android's navigation override does not cover POST, so a main-frame-only request
  interceptor also blocks rejected origins; committed history and load callbacks
  add defensive checks for redirects. Native callbacks cannot guarantee that no
  byte is ever transferred during redirects before cancellation.

## Requested ad blocker

`adblocker_webview 2.3.0` is integrated through its exported
`AdBlockerWebviewControllerImpl` filter API. Its own Android/iOS-only widget
overwrites the native UA and injects fetch/XHR/CSS scripts, so this module uses
the package's bundled EasyList/AdGuard rule matching in InAppWebView's native
resource interception on Android and Windows instead. No cosmetic/script
injection or package WebView controller is used. Signed URLs/headers are never
logged; the native plugin's verbose debug callback logging is disabled.

The visible toggle enables/disables decisions for future resource requests
without reloading or replacing the WebView. Loading, active, disabled and failed
states are explicit; filter initialization/matching failure leaves the official
page usable without filtering. Toggle off and on to retry a failed filter load.
Official YouTube, Google media/auth/API/CDN origins are always protected,
including `googlevideo.com`, `youtube.com`, `googleapis.com`, `google.com`,
`ytimg.com`, `ggpht.com`, `googleusercontent.com` and `gstatic.com` and subdomains.
This is deliberately partial resource filtering; **YouTube in-stream/video ad
removal is not guaranteed**. Same-origin ads remain under the official site's
control. No account, access, login or background restriction is bypassed.

Windows plugin 0.6.0 labels every resource request `isForMainFrame=true`; the
module does not use that flag there for resource navigation policy or page error
classification. Windows `NavigationStarting` and committed-load/history checks
enforce top-level navigation; Android additionally filters main-frame POSTs.
Native interception behavior and blocker effectiveness still need device checks.

Primary references: [plugin and stable requirements](https://pub.dev/packages/flutter_inappwebview),
[Windows and Android setup](https://inappwebview.dev/docs/intro/),
[navigation and callback caveats](https://inappwebview.dev/docs/webview/in-app-webview/),
[external URL launching](https://pub.dev/packages/url_launcher/versions/6.3.2),
[requested blocker](https://pub.dev/packages/adblocker_webview/versions/2.3.0),
[Google embedded sign-in policy](https://developers.google.com/identity/protocols/oauth2/policies).

## Validation

Unit/widget tests use a fake platform and never contact YouTube:

```text
flutter test test/youtube_music_navigation_test.dart test/youtube_music_page_test.dart test/youtube_music_ad_blocker_test.dart
```

Worker validation: all 15 scoped tests pass; `flutter analyze --no-pub` reports no
issues. `flutter build bundle --debug --no-pub
--target=integration_test/youtube_music_webview_test.dart` compiles the integration
harness and module Dart bundle. This does not compile native plugins or prove
live playback. `flutter pub get` resolves/locks dependencies but exits during
native plugin link setup because this worker's Windows symlink support is not
enabled; NuGet was not on the worker's PATH. No global settings were changed.
Native Windows/APK packaging and opt-in live device observation remain untested.

The integration test is skipped by default. Run on a genuine Windows or Android
device with no real credentials:

```text
flutter test integration_test/youtube_music_webview_test.dart -d <device-id> --dart-define=RUN_YOUTUBE_MUSIC_WEBVIEW=true --dart-define=YOUTUBE_MUSIC_OBSERVATION_SECONDS=180
```

During that window, use only the official site to start media manually, listen in
foreground, switch apps, turn the screen off and return. Record device/OS/runtime,
official account or regional restrictions and audible interruptions separately.
The test records lifecycle events; these are **not** evidence of audible playback.
It does not inspect DOM, alter official media state, supply credentials or bypass
access/background restrictions.
