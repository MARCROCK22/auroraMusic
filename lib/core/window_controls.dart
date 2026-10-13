import 'dart:io';
import 'package:flutter/services.dart';

/// Desktop title-bar operations stay outside widgets.
abstract final class WindowControls {
  static bool get supported => Platform.isWindows;
  static const _channel = MethodChannel('aurora/window');
  static void setCloseConfirmation(Future<bool> Function()? confirm) {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler(
      confirm == null
          ? null
          : (call) async {
              if (call.method == 'confirmClose') return confirm();
              throw MissingPluginException();
            },
    );
  }

  static Future<bool> guardClose(bool enabled) => invoke('guardClose', enabled);

  static Future<bool> invoke(String operation, [Object? arguments]) async {
    if (!Platform.isWindows) return false;
    try {
      await _channel.invokeMethod<void>(operation, arguments);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
