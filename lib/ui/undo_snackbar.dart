import 'package:flutter/material.dart';

/// Muestra un SnackBar (con acción opcional) que SIEMPRE se cierra solo: Flutter
/// deja `persist = action != null` por defecto y el aviso no desaparecería.
void showUndoSnackBar(
  ScaffoldMessengerState? messenger,
  Widget content, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: content,
      duration: duration,
      persist: false,
      action: label == null
          ? null
          : SnackBarAction(label: label, onPressed: onAction ?? () {}),
    ),
  );
}
