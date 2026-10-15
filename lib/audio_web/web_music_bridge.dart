import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../youtube_music/youtube_music_navigation.dart';
import '../youtube_music/youtube_music_ad_blocker.dart';

/// Device boundary. Fake implementations test Aurora without contacting a site.
abstract class WebMusicBridge {
  YouTubeMusicAdBlocker? get adBlocker => null;

  /// [siteAction] marks failures the user can only resolve on the site itself.
  void Function(String message, bool siteAction)? onFailure;
  void Function(Uri? uri)? onNavigation;

  Future<void> initialize();
  Widget buildView();
  Future<void> navigate(Uri uri);

  /// [timeout] bounds how long the page waits for real playback events.
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
    Duration timeout = const Duration(seconds: 20),
  });
  void dispose();
}

class NativeWebMusicBridge extends WebMusicBridge {
  @override
  final YouTubeMusicAdBlocker adBlocker = YouTubeMusicAdBlocker();
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  static Future<WebViewEnvironment>? _windowsEnvironment;
  Uri? _pending;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    PlatformInAppWebViewController.debugLoggingSettings = DebugLoggingSettings(
      enabled: false,
    );
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform)) {
      throw UnsupportedError('La vista de audio requiere Android o Windows.');
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        _environment = await (_windowsEnvironment ??= _createEnvironment());
      } catch (_) {
        _windowsEnvironment = null;
        rethrow;
      }
    }
    if (!_disposed) unawaited(adBlocker.initialize());
  }

  static Future<WebViewEnvironment> _createEnvironment() async {
    if (await WebViewEnvironment.getAvailableVersion() == null) {
      throw StateError('Instala Microsoft Edge WebView2 Runtime.');
    }
    final directory = await getApplicationSupportDirectory();
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: path.join(directory.path, 'youtube_music_webview'),
      ),
    );
  }

  bool _accept(Uri? uri) {
    // The initial empty native view has no provider request or autoplay.
    if (_pending == null && (uri == null || uri.toString() == 'about:blank')) {
      return true;
    }
    final policy = classifyYouTubeMusicNavigation(uri);
    if (policy == YouTubeMusicNavigation.allow) return true;
    onFailure?.call(
      policy == YouTubeMusicNavigation.signInInBrowser
          ? 'YouTube Music pidió iniciar sesión con Google. Aurora no abre ese '
                'acceso dentro de la app.'
          : 'YouTube Music intentó abrir otra página. Revisa el sitio.',
      true,
    );
    return false;
  }

  @override
  Widget buildView() {
    final initial = _pending;
    return InAppWebView(
      webViewEnvironment: _environment,
      initialUrlRequest: initial == null
          ? null
          : URLRequest(url: WebUri.uri(initial)),
      // Preserve native UA, TLS and cookies. Native Aurora buttons supply play
      // intent; allow their normal media commands without a WebView-only tap.
      // Generic filters protect media/auth origins. No media URL extraction,
      // private player API, PO token, UA override or cookie bridge.
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        mediaPlaybackRequiresUserGesture: false,
        useShouldOverrideUrlLoading: true,
        // Android 1.1.3 blocks its request thread waiting for the UI thread,
        // while CookieManager.flush on that UI thread waits for network work.
        // Keep Android request handling native to avoid that observed ANR.
        useShouldInterceptRequest:
            defaultTargetPlatform == TargetPlatform.windows,
        useOnRenderProcessGone: true,
        supportMultipleWindows: true,
      ),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: """
const hideAuroraVideo = () => {
  for (const video of document.querySelectorAll('video')) {
    if (video.style.visibility !== 'hidden') {
      video.style.setProperty('visibility', 'hidden', 'important');
    }
  }
};
new MutationObserver(hideAuroraVideo).observe(document, {childList:true, subtree:true});
hideAuroraVideo();
""",
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        if (_disposed) return;
        _controller = controller;
        if (_pending == initial || _pending == null) return;
        unawaited(
          controller
              .loadUrl(urlRequest: URLRequest(url: WebUri.uri(_pending!)))
              .catchError((Object _) {
                onFailure?.call('No se pudo cargar YouTube Music.', false);
              }),
        );
      },
      shouldOverrideUrlLoading: (controller, action) async {
        if (action.isForMainFrame == false) return NavigationActionPolicy.ALLOW;
        return _accept(action.request.url)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: defaultTargetPlatform == TargetPlatform.windows
          ? (controller, request) async {
              final topLevel =
                  defaultTargetPlatform == TargetPlatform.android &&
                  request.isForMainFrame == true;
              if (topLevel && !_accept(request.url)) {
                return WebResourceResponse(
                  statusCode: 403,
                  reasonPhrase: 'Navigation blocked',
                  contentType: 'text/plain',
                  contentEncoding: 'utf-8',
                  data: Uint8List(0),
                );
              }
              if (adBlocker.shouldBlock(request.url, isTopLevel: topLevel)) {
                return WebResourceResponse(
                  statusCode: 204,
                  reasonPhrase: 'No Content',
                  contentType: 'text/plain',
                  contentEncoding: 'utf-8',
                  data: Uint8List(0),
                );
              }
              return null;
            }
          : null,
      onCreateWindow: (controller, action) async {
        if (_accept(action.request.url)) {
          await controller.loadUrl(
            urlRequest: URLRequest(url: action.request.url),
          );
        }
        return false;
      },
      onLoadStart: (controller, uri) async {
        if (!_accept(uri)) await controller.stopLoading();
        onNavigation?.call(uri);
      },
      onUpdateVisitedHistory: (controller, uri, _) async {
        if (!_accept(uri)) await controller.stopLoading();
        onNavigation?.call(uri);
      },
      onLoadStop: (controller, uri) async {
        await controller.injectCSSCode(
          source: 'video { visibility: hidden !important; }',
        );
      },
      // Windows labels every resource as main frame; only the page itself counts.
      onReceivedError: (controller, request, error) {
        if (request.url.toString() == _pending?.toString()) {
          onFailure?.call(
            'No se pudo cargar YouTube Music. Revisa la conexión.',
            false,
          );
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if (request.url.toString() == _pending?.toString()) {
          onFailure?.call(
            'YouTube Music respondió con un error '
            '(HTTP ${response.statusCode ?? '?'}).',
            false,
          );
        }
      },
      onRenderProcessGone: (_, _) {
        _controller = null;
        onFailure?.call(
          'El reproductor de YouTube Music se cerró. Vuelve a abrir Aurora.',
          false,
        );
      },
    );
  }

  @override
  Future<void> navigate(Uri uri) async {
    if (_disposed) return;
    if (uri.scheme != 'https' || !_accept(uri)) {
      throw ArgumentError('Se requiere una página oficial.');
    }
    _pending = uri;
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
  }

  @override
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final controller = _controller;
    if (controller == null || _disposed) return null;
    // Arguments are serialized by the plugin, never interpolated into JS.
    final result = await controller.callAsyncJavaScript(
      functionBody: webMusicMediaScript,
      arguments: {
        'action': action,
        'expectedId': videoId,
        'generation': generation,
        'value': value,
        'timeoutMs': timeout.inMilliseconds,
      },
    );
    if (result?.error != null) throw StateError('Falló el puente de audio.');
    final data = result?.value;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  @override
  void dispose() {
    _disposed = true;
    onFailure = null;
    onNavigation = null;
    // The mounted native widget owns its controller's disposal.
    _controller = null;
    adBlocker.dispose();
    // Unmount the view first (WebMusicAudio.shutdown); a live WebView2
    // environment otherwise keeps the Windows process alive after closing.
    final environment = _environment;
    _environment = null;
    if (environment != null) {
      _windowsEnvironment = null;
      unawaited(environment.dispose().catchError((Object _) {}));
    }
  }
}

/// Reads only public media properties/DOM. Never returns src, cookies or tokens.
/// Ads: the page mutes its own media element and clicks the site's own skip
/// button while the player shows an ad, and unmutes it afterwards.
const webMusicMediaScript = r'''
if (location.origin !== 'https://music.youtube.com') return {status: 'website'};
const pageId = new URL(location.href).searchParams.get('v');
const findMedia = root => {
  const direct = root.querySelector('video, audio');
  if (direct) return direct;
  for (const node of root.querySelectorAll('*')) {
    if (node.shadowRoot) {
      const nested = findMedia(node.shadowRoot);
      if (nested) return nested;
    }
  }
  return null;
};
const known = ['AbortError', 'NotAllowedError', 'NotSupportedError', 'InvalidStateError', 'TimeoutError', 'SecurityError', 'TypeError', 'RangeError'];
const errorName = error => known.includes(error && error.name) ? error.name : 'Error';
const adShowing = () => !!document.querySelector('.ad-showing, .ad-interrupting');
const skipAd = () => {
  for (const button of document.querySelectorAll('.ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-skip-ad-button')) {
    if (!button.disabled && button.getClientRects().length) { button.click(); return; }
  }
};
let media = findMedia(document);
if (!media) return {status: 'waiting'};
if (media.tagName === 'VIDEO') media.style.setProperty('visibility', 'hidden', 'important');
if (pageId !== expectedId) {
  const previous = window.__auroraMediaObservation;
  if (previous?.generation === generation && previous.endedSnapshot) {
    media.pause();
    return previous.endedSnapshot;
  }
  if (action !== 'snapshot') media.pause();
  return {status: 'differentTrack'};
}
const observe = element => {
  let state = window.__auroraMediaObservation;
  if (state && state.generation === generation && state.media === element) return state;
  if (state) for (const [name, listener] of state.listeners) state.media.removeEventListener(name, listener);
  state = {generation, media: element, ended: false, adMuted: false, pendingSeek: null};
  const handleAd = () => {
    if (adShowing()) {
      if (!state.adMuted) { state.adMuted = true; element.muted = true; }
      skipAd();
    } else if (state.adMuted) {
      state.adMuted = false;
      element.muted = false;
    }
  };
  state.handleAd = handleAd;
  state.listeners = [
    ['timeupdate', handleAd],
    ['playing', handleAd],
    ['loadedmetadata', () => {
      handleAd();
      if (state.pendingSeek !== null && !adShowing()) {
        element.currentTime = Math.max(0, Math.min(state.pendingSeek, element.duration || state.pendingSeek));
        state.pendingSeek = null;
      }
    }],
    ['ended', () => {
      if (!adShowing() && state.lastSnapshot) {
        state.ended = true;
        state.endedSnapshot = {...state.lastSnapshot, ended: true, playing: false, buffering: false};
      }
    }],
  ];
  for (const [name, listener] of state.listeners) element.addEventListener(name, listener);
  window.__auroraMediaObservation = state;
  return state;
};
let state = observe(media);
state.handleAd();
const waitFor = (element, events, accept) => {
  let fail;
  const promise = new Promise((resolve, reject) => {
    let done = false;
    const finish = (callback, value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      for (const name of events) element.removeEventListener(name, check);
      callback(value);
    };
    const check = () => { if (accept()) finish(resolve); };
    const timer = setTimeout(() => {
      const error = new Error('timeout');
      error.name = 'TimeoutError';
      finish(reject, error);
    }, timeoutMs);
    for (const name of events) element.addEventListener(name, check);
    fail = error => finish(reject, error);
  });
  return {promise, fail};
};
// Resolves on real playback events, never on the play() promise alone.
const startPlayback = element => {
  const wait = waitFor(element, ['playing', 'timeupdate'], () => !element.paused);
  const request = element.play();
  if (request) request.catch(wait.fail);
  return wait.promise;
};
let status = 'ready';
let failedName = null;
try {
  if (action === 'play') {
    state.ended = false;
    state.endedSnapshot = null;
    try {
      await startPlayback(media);
    } catch (error) {
      if (error.name !== 'AbortError') throw error;
      // The site replaced the source: wait for its new data, then retry once.
      media = findMedia(document) || media;
      state = observe(media);
      if (media.readyState < 2) await waitFor(media, ['loadeddata'], () => media.readyState >= 2).promise;
      await startPlayback(media);
    }
  } else if (action === 'pause') {
    media.pause();
  } else if (action === 'seek') {
    if (adShowing()) status = 'seekUnavailable';
    else if (Number.isFinite(value)) {
      state.ended = false;
      state.endedSnapshot = null;
      if (media.readyState >= 1 && Number.isFinite(media.duration)) {
        media.currentTime = Math.max(0, Math.min(value, media.duration));
      } else {
        state.pendingSeek = value;
      }
    }
  } else if (action === 'volume' && Number.isFinite(value)) {
    media.volume = Math.max(0, Math.min(value, 1));
  }
} catch (error) {
  failedName = errorName(error);
  if (action === 'play') media.pause();
  status = action === 'play' && failedName === 'NotAllowedError' ? 'playBlocked'
    : action === 'play' && failedName === 'TimeoutError' ? 'playTimeout'
    : 'commandFailed';
}
const snapshot = {
  status,
  action,
  errorName: failedName,
  videoId: pageId,
  generation,
  playing: !media.paused && !media.ended,
  buffering: !media.paused && media.readyState < 3,
  ended: state.ended || (media.ended && !adShowing()),
  adPlaying: adShowing(),
  position: Number.isFinite(media.currentTime) ? media.currentTime : 0,
  duration: Number.isFinite(media.duration) ? media.duration : 0,
  mediaError: media.error ? media.error.code : 0,
};
if (!snapshot.adPlaying) state.lastSnapshot = {...snapshot, status: 'ready', action: 'snapshot', errorName: null};
return snapshot;
''';
