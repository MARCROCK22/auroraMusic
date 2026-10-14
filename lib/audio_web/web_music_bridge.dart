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
  void Function(String message)? onFailure;
  void Function(Uri? uri)? onNavigation;

  Future<void> initialize();
  Widget buildView();
  Future<void> navigate(Uri uri);
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
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
          ? 'El acceso de Google requiere el navegador; su sesión es independiente.'
          : 'La página intentó salir de YouTube Music. Abre el sitio para revisar.',
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
      // private player API, ad skipping or cookie bridge.
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
                onFailure?.call('No se pudo cargar YouTube Music.');
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
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame == true) {
          onFailure?.call('No se pudo cargar la página oficial.');
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if (request.isForMainFrame == true) {
          onFailure?.call(
            'El sitio devolvió un error. Abre la página para revisar.',
          );
        }
      },
      onRenderProcessGone: (_, _) {
        _controller = null;
        onFailure?.call('La vista de audio se cerró. Vuelve a abrir Aurora.');
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
  }
}

/// Reads only public media properties/DOM. Never returns src, cookies or tokens.
const webMusicMediaScript = r'''
if (location.origin !== 'https://music.youtube.com') {
  return {status: 'website'};
}
if (action === 'search') {
  const query = new URL(location.href).searchParams.get('q');
  if (location.pathname !== '/search' || query !== expectedId) return {status:'waiting'};
  const rows = [...document.querySelectorAll('ytmusic-responsive-list-item-renderer')];
  const tracks = [];
  const seen = new Set();
  for (const row of rows) {
    let videoId;
    for (const anchor of row.querySelectorAll('a[href]')) {
      const url = new URL(anchor.getAttribute('href'), location.origin);
      const id = url.searchParams.get('v');
      if (url.origin === location.origin && url.pathname === '/watch' && /^[A-Za-z0-9_-]{11}$/.test(id || '')) {
        videoId = id;
        break;
      }
    }
    if (!videoId || seen.has(videoId)) continue;
    const columns = [...row.querySelectorAll('yt-formatted-string')];
    const title = (row.querySelector('.title')?.textContent || columns[0]?.textContent || '').trim().slice(0,500);
    if (!title) continue;
    const track = {videoId, title};
    const byline = columns.slice(1).flatMap(column => [...column.querySelectorAll('a[href]')]);
    const artist = byline.find(anchor => /(?:channel\/|browse\?id=UC)/.test(anchor.getAttribute('href') || ''));
    const album = byline.find(anchor => /(?:browse\?id=MPRE|browse\/MPRE)/.test(anchor.getAttribute('href') || ''));
    if (artist?.textContent.trim()) track.artist = artist.textContent.trim().slice(0,500);
    if (album?.textContent.trim()) track.album = album.textContent.trim().slice(0,500);
    const image = row.querySelector('img');
    if (image?.src) {
      const url = new URL(image.src, location.origin);
      if (url.protocol === 'https:' && !url.username && !url.password && /(^|\.)(ytimg\.com|ggpht\.com|googleusercontent\.com)$/.test(url.hostname)) {
        track.artworkUrl = url.href;
      }
    }
    const duration = row.querySelector('.fixed-columns')?.textContent?.match(/\b(?:\d+:)?\d{1,2}:\d{2}\b/);
    if (duration) track.durationSeconds = duration[0].split(':').reduce((total, part) => total * 60 + Number(part), 0);
    seen.add(videoId);
    tracks.push(track);
    if (tracks.length >= 50) break;
  }
  const noResults = !!document.querySelector('ytmusic-message-renderer');
  return tracks.length || noResults ? {status:'ready', tracks} : {status:'waiting'};
}
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
const media = findMedia(document);
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
const player = media.closest('.html5-video-player');
const adPlaying = () => !!document.querySelector('.ad-showing, .ad-interrupting');
let state = window.__auroraMediaObservation;
if (!state || state.generation !== generation || state.media !== media) {
  if (state) state.media.removeEventListener('ended', state.listener);
  state = {generation, media, ended: false};
  state.listener = () => {
    if (!adPlaying()) {
      state.ended = true;
      state.endedSnapshot = {...state.lastSnapshot, ended:true, playing:false, buffering:false};
    }
  };
  media.addEventListener('ended', state.listener);
  window.__auroraMediaObservation = state;
}
let status = 'ready';
try {
  if (action === 'play') {
    state.ended = false;
    state.endedSnapshot = null;
    await Promise.race([
      media.play(),
      new Promise((_, reject) => setTimeout(() => reject(new Error()), 4000))
    ]);
  } else if (action === 'pause') {
    media.pause();
  } else if (action === 'seek') {
    // Never seek an ad or an unrecognized player. Ad DOM detection is best effort.
    if (adPlaying() || !player) status = 'seekUnavailable';
    else if (Number.isFinite(value) && Number.isFinite(media.duration)) {
      media.currentTime = Math.max(0, Math.min(value, media.duration));
      state.ended = false;
      state.endedSnapshot = null;
    }
  } else if (action === 'volume' && Number.isFinite(value)) {
    media.volume = Math.max(0, Math.min(value, 1));
  }
} catch (error) {
  if (action === 'play') media.pause();
  status = action === 'play' && error.name === 'NotAllowedError' ? 'playBlocked' : 'commandFailed';
}
const metadata = navigator.mediaSession && navigator.mediaSession.metadata;
const text = selector => (document.querySelector(selector)?.textContent || '').trim().slice(0, 500);
const artwork = [...(metadata?.artwork || [])].sort((a, b) => {
  const width = image => {
    const declared = Math.max(0, ...(image.sizes || '').split(/\s+/).map(size => Number(size.split('x')[0]) || 0));
    if (declared > 0) return declared;
    try {
      const url = new URL(image.src, location.origin);
      const resize = url.pathname.match(/=[ws](\d+)(?:-|$)/);
      return Number(url.searchParams.get('width') || url.searchParams.get('w') || resize?.[1]) || 0;
    } catch (_) { return 0; }
  };
  return width(b) - width(a);
});
const imageSource = artwork[0]?.src || document.querySelector('ytmusic-player-bar img')?.src;
let artworkUrl;
if (imageSource) {
  const image = new URL(imageSource, location.origin);
  if (image.protocol === 'https:' && !image.username && !image.password && /(^|\.)(ytimg\.com|ggpht\.com|googleusercontent\.com)$/.test(image.hostname)) {
    artworkUrl = image.href;
  }
}
const snapshot = {
  status,
  videoId: pageId,
  generation,
  playing: !media.paused && !media.ended,
  buffering: !media.paused && media.readyState < 3,
  ended: state.ended || media.ended,
  adPlaying: adPlaying(),
  position: Number.isFinite(media.currentTime) ? media.currentTime : 0,
  duration: Number.isFinite(media.duration) ? media.duration : 0,
  volume: media.volume,
  mediaError: media.error ? media.error.code : 0,
  artworkUrl,
  title: (metadata?.title || text('ytmusic-player-bar .title')).slice(0, 500),
  artist: (metadata?.artist || text('ytmusic-player-bar .byline')).slice(0, 500)
};
state.lastSnapshot = snapshot;
return snapshot;
''';
