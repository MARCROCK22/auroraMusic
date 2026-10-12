import 'dart:io';
import 'package:flutter/services.dart';

/// Desktop title-bar operations stay outside widgets.
abstract final class WindowControls {
  static bool get supported => Platform.isWindows;
  static const _channel = MethodChannel('aurora/window');
  static Future<bool> invoke(String operation) async {
    if (!Platform.isWindows) return false;
    try {
      await _channel.invokeMethod<void>(operation);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
