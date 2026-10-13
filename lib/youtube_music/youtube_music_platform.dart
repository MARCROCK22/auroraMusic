import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'youtube_music_ad_blocker.dart';
import 'youtube_music_navigation.dart';

/// Test seam for the native view; fake implementations never contact YouTube.
abstract class YouTubeMusicPlatform extends ChangeNotifier {
  bool ready = false;
  bool loading = true;
  bool canGoBack = false;
  bool canGoForward = false;
  double progress = 0;
  String? error;
  String? notice;

  YouTubeMusicAdBlocker? get adBlocker => null;

  Future<void> initialize();
  Widget buildView(Uri initialUri);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> navigateTo(Uri uri) async =>
      throw UnsupportedError('Navigation is unavailable.');
}

class NativeYouTubeMusicPlatform extends YouTubeMusicPlatform {
  NativeYouTubeMusicPlatform() {
    adBlocker.addListener(_changed);
  }

  @override
  final YouTubeMusicAdBlocker adBlocker = YouTubeMusicAdBlocker();
  InAppWebViewController? _controller;
  WebViewEnvironment? _environment;
  static Future<WebViewEnvironment>? _windowsEnvironment;
  bool _disposed = false;
  Uri _lastOfficialUri = youtubeMusicHome;
  Uri? _pendingNavigation;
  int _historyRevision = 0;

  @override
  Future<void> initialize() async {
    // Plugin debug callbacks include signed URLs and headers. Disable that
    // logger rather than letting sensitive website traffic reach app logs.
    PlatformInAppWebViewController.debugLoggingSettings = DebugLoggingSettings(
      enabled: false,
    );
    if (kIsWeb ||
        !const {
          TargetPlatform.android,
          TargetPlatform.windows,
        }.contains(defaultTargetPlatform)) {
      throw UnsupportedError(
        'YouTube Music está disponible en Android y Windows.',
      );
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
      throw StateError(
        'Instala Microsoft Edge WebView2 Runtime para abrir YouTube Music.',
      );
    }
    final directory = await getApplicationSupportDirectory();
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: path.join(directory.path, 'youtube_music_webview'),
      ),
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _rejected(Uri? uri) {
    notice =
        classifyYouTubeMusicNavigation(uri) ==
            YouTubeMusicNavigation.signInInBrowser
        ? 'Google puede restringir el acceso desde esta vista. Continúa en tu navegador; su sesión es independiente de Aurora.'
        : 'Esta vista solo permite páginas oficiales de YouTube Music y consentimiento de Google.';
    loading = false;
    _changed();
  }

  Future<void> _history() async {
    final revision = ++_historyRevision;
    final controller = _controller;
    if (controller == null || _disposed) return;
    try {
      final values = await Future.wait([
        controller.canGoBack(),
        controller.canGoForward(),
      ]);
      if (_disposed || revision != _historyRevision) return;
      canGoBack = values[0];
      canGoForward = values[1];
      _changed();
    } catch (_) {
      if (_disposed) return;
      canGoBack = false;
      canGoForward = false;
      _changed();
    }
  }

  Future<void> _checkCommittedUri(Uri? uri) async {
    if (_disposed || uri == null) return;
    if (classifyYouTubeMusicNavigation(uri) == YouTubeMusicNavigation.allow) {
      _lastOfficialUri = uri;
      await _history();
      return;
    }
    // Defense in depth for redirects/history changes without a navigation callback.
    await _controller?.stopLoading();
    _rejected(uri);
    await _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri.uri(_lastOfficialUri)),
    );
  }

  @override
  Widget buildView(Uri initialUri) {
    if (classifyYouTubeMusicNavigation(initialUri) !=
        YouTubeMusicNavigation.allow) {
      throw ArgumentError.value(
        initialUri,
        'initialUri',
        'Expected an official HTTPS origin',
      );
    }
    _lastOfficialUri = initialUri;
    return InAppWebView(
      webViewEnvironment: _environment,
      initialUrlRequest: URLRequest(url: WebUri.uri(initialUri)),
      // Keep the native UA, normal persistent profile, TLS and media policy.
      // No user scripts, cookie access or media commands are used.
      initialSettings: InAppWebViewSettings(
        isInspectable: kDebugMode,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        supportMultipleWindows: true,
        useOnRenderProcessGone: true,
      ),
      onWebViewCreated: (controller) {
        if (_disposed) return;
        _controller = controller;
        ready = true;
        _changed();
        final pending = _pendingNavigation;
        _pendingNavigation = null;
        if (pending != null) {
          unawaited(
            navigateTo(pending).catchError((Object _) {
              error = 'No se pudo abrir esa página de YouTube Music.';
              _changed();
            }),
          );
        }
      },
      shouldOverrideUrlLoading: (controller, action) async {
        if (action.isForMainFrame == false) return NavigationActionPolicy.ALLOW;
        final uri = action.request.url;
        if (classifyYouTubeMusicNavigation(uri) ==
            YouTubeMusicNavigation.allow) {
          return NavigationActionPolicy.ALLOW;
        }
        _rejected(uri);
        return NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (controller, request) async {
        // Android does not call shouldOverrideUrlLoading for POST navigations.
        // Apply top-level policy separately from optional ad-resource filtering.
        // Windows 0.6.0 marks EVERY intercepted resource as main frame. Its
        // NavigationStarting callback enforces top-level navigation separately.
        final androidMainFrame =
            defaultTargetPlatform == TargetPlatform.android &&
            request.isForMainFrame == true;
        if (androidMainFrame &&
            classifyYouTubeMusicNavigation(request.url) !=
                YouTubeMusicNavigation.allow) {
          _rejected(request.url);
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Navigation blocked',
            contentType: 'text/plain',
            contentEncoding: 'utf-8',
            headers: const {},
            data: Uint8List(0),
          );
        }
        if (adBlocker.shouldBlock(request.url, isTopLevel: androidMainFrame)) {
          return WebResourceResponse(
            statusCode: 204,
            reasonPhrase: 'No Content',
            contentType: 'text/plain',
            contentEncoding: 'utf-8',
            headers: const {},
            data: Uint8List(0),
          );
        }
        return null;
      },
      onCreateWindow: (controller, action) async {
        // Do not create a second/hidden WebView, including for Google sign-in.
        final uri = action.request.url;
        if (classifyYouTubeMusicNavigation(uri) ==
            YouTubeMusicNavigation.allow) {
          await controller.loadUrl(urlRequest: URLRequest(url: uri));
        } else {
          _rejected(uri);
        }
        return false;
      },
      onLoadStart: (controller, uri) async {
        if (_disposed) return;
        if (classifyYouTubeMusicNavigation(uri) !=
            YouTubeMusicNavigation.allow) {
          await controller.stopLoading();
          _rejected(uri);
          return;
        }
        loading = true;
        _lastOfficialUri = uri!;
        progress = 0;
        error = null;
        _changed();
      },
      onLoadStop: (controller, uri) async {
        if (_disposed) return;
        loading = false;
        progress = 1;
        _changed();
        await _checkCommittedUri(uri);
      },
      onProgressChanged: (controller, value) {
        if (_disposed) return;
        progress = value / 100;
        _changed();
      },
      onUpdateVisitedHistory: (controller, uri, isReload) =>
          _checkCommittedUri(uri),
      onReceivedError: (controller, request, failure) {
        if (!_isPageRequest(request) || _disposed) return;
        loading = false;
        error =
            'No se pudo cargar YouTube Music. Revisa tu conexión e inténtalo de nuevo.';
        _changed();
      },
      onReceivedHttpError: (controller, request, response) {
        if (!_isPageRequest(request) || _disposed) return;
        loading = false;
        error =
            'YouTube Music respondió con un error (${response.statusCode}). Puedes volver a intentar o abrir el navegador.';
        _changed();
      },
      onRenderProcessGone: (controller, detail) {
        if (_disposed) return;
        ready = false;
        loading = false;
        error =
            'La vista web se cerró. Sal de esta página y vuelve a abrirla, o continúa en tu navegador.';
        _changed();
      },
    );
  }

  @override
  Future<void> goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      await _history();
    }
  }

  bool _isPageRequest(WebResourceRequest request) =>
      defaultTargetPlatform == TargetPlatform.android
      ? request.isForMainFrame == true
      : request.url.toString() == _lastOfficialUri.toString();

  @override
  Future<void> goForward() async {
    final controller = _controller;
    if (controller != null && await controller.canGoForward()) {
      await controller.goForward();
      await _history();
    }
  }

  @override
  Future<void> navigateTo(Uri uri) async {
    if (_disposed) return;
    if (classifyYouTubeMusicNavigation(uri) != YouTubeMusicNavigation.allow) {
      throw ArgumentError('Usa una página oficial HTTPS de YouTube Music.');
    }
    _lastOfficialUri = uri;
    error = null;
    notice = null;
    loading = true;
    _changed();
    final controller = _controller;
    if (controller == null) {
      _pendingNavigation = uri;
      return;
    }
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
  }

  @override
  Future<void> reload() async {
    error = null;
    notice = null;
    loading = true;
    _changed();
    final controller = _controller;
    if (controller == null) return;
    if (classifyYouTubeMusicNavigation(await controller.getUrl()) ==
        YouTubeMusicNavigation.allow) {
      await controller.reload();
    } else {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(_lastOfficialUri)),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller = null;
    adBlocker.removeListener(_changed);
    adBlocker.dispose();
    // The native widget disposes its controller. The shared Windows environment
    // lives for the process, and its persistent profile remains on disk.
    super.dispose();
  }
}
