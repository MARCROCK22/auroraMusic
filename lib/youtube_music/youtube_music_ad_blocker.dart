import 'dart:async';

import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:flutter/foundation.dart';

enum YouTubeMusicAdBlockStatus { loading, ready, failed }

/// Uses the requested package's filter API, never its UA-overriding/script widget.
/// Media and authentication origins are protected from generic filter rules.
class YouTubeMusicAdBlocker extends ChangeNotifier {
  YouTubeMusicAdBlocker({
    @visibleForTesting AdBlockerWebviewControllerImpl? controller,
  }) : _controller = controller ?? AdBlockerWebviewControllerImpl();

  final AdBlockerWebviewControllerImpl _controller;
  YouTubeMusicAdBlockStatus status = YouTubeMusicAdBlockStatus.loading;
  bool enabled = true;
  bool _disposed = false;
  Future<void>? _initializing;

  static const protectedDomains = {
    'youtube.com',
    'googlevideo.com',
    'ytimg.com',
    'ggpht.com',
    'googleusercontent.com',
    'gstatic.com',
    'googleapis.com',
    'google.com',
  };

  Future<void> initialize() => _initializing ??= _load().whenComplete(() {
    _initializing = null;
  });

  Future<void> _load() async {
    status = YouTubeMusicAdBlockStatus.loading;
    if (!_disposed) notifyListeners();
    try {
      await _controller.initialize(
        FilterConfig(
          filterTypes: [FilterType.easyList, FilterType.adGuard],
          allowedDomains: protectedDomains.toList(),
        ),
      );
      if (_disposed) {
        await _controller.dispose();
        return;
      }
      status = YouTubeMusicAdBlockStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = YouTubeMusicAdBlockStatus.failed;
    }
    if (!_disposed) notifyListeners();
  }

  void setEnabled(bool value) {
    if (_disposed || enabled == value) return;
    enabled = value;
    notifyListeners();
  }

  bool shouldBlock(Uri? uri, {required bool isTopLevel}) {
    if (_disposed ||
        !enabled ||
        status != YouTubeMusicAdBlockStatus.ready ||
        isTopLevel ||
        uri == null ||
        uri.userInfo.isNotEmpty ||
        !const {'https', 'http'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        protectedDomains.any(
          (domain) => uri.host == domain || uri.host.endsWith('.$domain'),
        )) {
      return false;
    }
    try {
      return _controller.shouldBlockResource(uri.toString());
    } catch (_) {
      // Fail open: never break the official website if the matcher fails.
      status = YouTubeMusicAdBlockStatus.failed;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_controller.dispose());
    super.dispose();
  }
}
