import 'package:flutter/material.dart';

import '../core/desktop_shell.dart';
import '../core/window_controls.dart';
import '../theme/brasa_theme.dart';

/// Ajustes de ventana de Windows: comportamiento de la X e inicio con Windows.
class DesktopSettingsTiles extends StatefulWidget {
  const DesktopSettingsTiles({super.key, required this.shell});
  final DesktopShell shell;

  @override
  State<DesktopSettingsTiles> createState() => _DesktopSettingsTilesState();
}

class _DesktopSettingsTilesState extends State<DesktopSettingsTiles> {
  late bool _tray = widget.shell.closeToTray;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    WindowControls.query('getAutostart').then((v) {
      if (mounted) setState(() => _autostart = v);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: isBrasa(context) ? Brasa.cream : null,
        activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
        title: const Text('Al cerrar con X: minimizar a la bandeja'),
        subtitle: Text(
          _tray
              ? 'La X siempre oculta Aurora en la bandeja (suene o no la música). Alt+F4 y «Salir» de la bandeja siempre cierran.'
              : 'La X cierra Aurora. Alt+F4 siempre cierra.',
        ),
        value: _tray,
        onChanged: (v) {
          setState(() => _tray = v);
          widget.shell.setCloseToTray(v);
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: isBrasa(context) ? Brasa.cream : null,
        activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
        title: const Text('Iniciar con Windows'),
        value: _autostart,
        onChanged: (v) async {
          final ok = await WindowControls.invoke('setAutostart', v);
          if (ok && mounted) setState(() => _autostart = v);
        },
      ),
    ],
  );
}
