import 'package:flutter/material.dart';

import '../listenbrainz/listenbrainz_service.dart';

/// Ajustes de ListenBrainz: opcional, apagado por defecto. El token se pega en
/// un campo oculto, se valida (solo se muestra el usuario) y se guarda en el
/// almacenamiento seguro del sistema.
class ListenBrainzSettingsPanel extends StatefulWidget {
  const ListenBrainzSettingsPanel({super.key, required this.service});
  final ListenBrainzService service;
  @override
  State<ListenBrainzSettingsPanel> createState() => _State();
}

class _State extends State<ListenBrainzSettingsPanel> {
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final value = _token.text;
    await widget.service.validateAndSave(value);
    if (mounted && widget.service.hasToken) _token.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final s = widget.service;
      final working = s.status == LbStatus.working;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacidad: si lo activas, Aurora publica en tu perfil de '
            'ListenBrainz lo que escuchas (artista, título, duración, hora de '
            'inicio y el nombre «Aurora»). Por defecto esos historiales son '
            'públicos en ListenBrainz salvo que lo cambies allí. También pide '
            'a ListenBrainz recomendaciones y novedades para tu cuenta. Está '
            'desactivado hasta que lo enciendas.',
          ),
          if (s.secureUnavailable) ...[
            const SizedBox(height: 8),
            const Text(
              'Este sistema no ofrece almacenamiento seguro para el token: '
              'ListenBrainz no está disponible.',
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enviar mi historial a ListenBrainz'),
            subtitle: Text(
              s.hasToken
                  ? 'Cuenta: ${s.username ?? '—'}. Al apagarlo se borra la cola pendiente.'
                  : 'Valida tu token para poder activarlo.',
            ),
            value: s.enabled,
            onChanged: s.secureUnavailable || working
                ? null
                : (v) => s.setEnabled(v),
          ),
          if (!s.hasToken) ...[
            TextField(
              controller: _token,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !s.secureUnavailable && !working,
              decoration: const InputDecoration(
                labelText: 'Token de usuario de ListenBrainz',
                helperText:
                    'Está en listenbrainz.org/settings. No se muestra ni se guarda en texto plano.',
                helperMaxLines: 3,
              ),
              onSubmitted: (_) => _validate(),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!s.hasToken)
                FilledButton.icon(
                  onPressed: s.secureUnavailable || working ? null : _validate,
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(working ? 'Validando…' : 'Validar'),
                ),
              if (s.hasToken || s.pending > 0)
                OutlinedButton.icon(
                  onPressed: working ? null : s.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión y borrar token y cola'),
                ),
            ],
          ),
          if (s.message != null) ...[
            const SizedBox(height: 8),
            Text(s.message!),
          ],
          if (s.pending > 0) ...[
            const SizedBox(height: 8),
            Text('${s.pending} escuchas pendientes de enviar.'),
          ],
        ],
      );
    },
  );
}
