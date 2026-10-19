import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/window_controls.dart';
import 'terms_text.dart';

/// Cierra la aplicación de verdad (sin ocultarla a la bandeja).
void _quit() {
  if (Platform.isAndroid) {
    SystemNavigator.pop();
  } else {
    exit(0); // Nada que liberar: aún no arrancó audio, proxy ni red.
  }
}

/// Primer arranque: términos con Aceptar / Rechazar. Corre antes de iniciar
/// audio, proxy o red.
class TermsScreen extends StatefulWidget {
  const TermsScreen({
    super.key,
    required this.onAccept,
    this.onReject,
    this.hookWindow = true,
  });

  final Future<void> Function() onAccept;

  /// Por defecto cierra la app; los tests lo sustituyen.
  final VoidCallback? onReject;

  /// En Windows desactiva ocultar a bandeja para que la X cierre de verdad.
  /// La app real vuelve a empujar su ajuste (`pushCloseBehavior`) al iniciar.
  final bool hookWindow;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.hookWindow) WindowControls.invoke('setCloseToTray', false);
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Términos y condiciones',
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      children: [
                        Text(
                          'Versión $kTermsVersion · $kTermsDate',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(kTermsIntro, style: theme.textTheme.bodyMedium),
                        for (final section in kTermsSections) ...[
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: Text(
                              section.title,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(section.body, style: theme.textTheme.bodyMedium),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  // Wrap: a 320 px o con texto al 200% los botones bajan de fila.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : (widget.onReject ?? _quit),
                        child: const Text('Rechazar'),
                      ),
                      FilledButton(
                        onPressed: _busy ? null : _accept,
                        child: const Text('Aceptar'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
