import 'package:flutter/material.dart';

import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';

/// SnackBar con el estilo del tema: en Modern fondo navy, texto blanco, radio 8
/// y acción menta; en Atelier el predeterminado.
SnackBar auroraSnackBar(
  BuildContext context,
  Widget content, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  if (isBrasa(context)) {
    return SnackBar(
      content: DefaultTextStyle.merge(
        style: const TextStyle(color: Brasa.cream),
        child: content,
      ),
      duration: duration,
      persist: false,
      backgroundColor: Brasa.graphite,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      action: label == null
          ? null
          : SnackBarAction(
              label: label,
              textColor: Brasa.cream,
              onPressed: onAction ?? () {},
            ),
    );
  }
  final modern = isModern(context);
  return SnackBar(
    content: modern
        ? DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: content,
          )
        : content,
    duration: duration,
    persist: false,
    backgroundColor: modern ? Tracky.navy : null,
    behavior: modern ? SnackBarBehavior.floating : null,
    elevation: modern ? 0 : null,
    shape: modern
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
        : null,
    action: label == null
        ? null
        : SnackBarAction(
            label: label,
            textColor: modern ? Tracky.mint : null,
            onPressed: onAction ?? () {},
          ),
  );
}

/// Muestra un SnackBar (con acción opcional) que SIEMPRE se cierra solo: Flutter
/// deja `persist = action != null` por defecto y el aviso no desaparecería.
void showUndoSnackBar(
  ScaffoldMessengerState? messenger,
  Widget content, {
  String? label,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    auroraSnackBar(
      messenger.context,
      content,
      label: label,
      onAction: onAction,
      duration: duration,
    ),
  );
}
