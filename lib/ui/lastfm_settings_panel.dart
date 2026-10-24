import 'package:flutter/material.dart';

import '../lastfm/lastfm_service.dart';
import '../lastfm/scrobbler.dart';
import '../theme/brasa_theme.dart';

/// Ajustes de Last.fm: opcional, apagado por defecto. Cada usuario conecta su
/// cuenta con usuario y contraseña; la contraseña solo se envía para obtener la
/// sesión y no se guarda. La clave de sesión va al almacenamiento seguro.
class LastfmSettingsPanel extends StatefulWidget {
  const LastfmSettingsPanel({super.key, required this.service});
  final LastfmService service;
  @override
  State<LastfmSettingsPanel> createState() => _State();
}

class _State extends State<LastfmSettingsPanel> {
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  static String _tracking(Scrobbler sc) {
    final t = sc.tracking;
    if (t == null) return 'Ahora mismo no se sigue ninguna pista.';
    final need = sc.trackingThreshold;
    final state = sc.trackingCounted
        ? 'contada'
        : need == null
        ? 'demasiado corta para contar'
        : 'contará tras ${need.inSeconds} s escuchados';
    return 'Siguiendo: ${t.title} — ${t.artist} ($state).';
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    return d.inMinutes < 1 ? 'hace unos segundos' : 'hace ${d.inMinutes} min';
  }

  Future<void> _connect() async {
    final password = _password.text;
    await widget.service.connect(_user.text, password);
    if (!mounted) return;
    _password.clear(); // la contraseña no se queda en pantalla
    if (widget.service.hasSession) _user.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final s = widget.service;
      if (!s.configured) {
        return const Text('Last.fm no está configurado en esta compilación.');
      }
      final working = s.status == LfmStatus.working;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacidad: si lo activas, Aurora publica en tu perfil de '
            'Last.fm lo que escuchas (artista, título, álbum, duración y hora '
            'de inicio). Tu perfil de Last.fm puede ser público según lo que '
            'hayas elegido allí. También pide a Last.fm canciones similares '
            'para las recomendaciones. Tu contraseña solo se envía a Last.fm '
            'para iniciar sesión y no se guarda. Está desactivado hasta que '
            'lo enciendas.',
          ),
          if (s.secureUnavailable) ...[
            const SizedBox(height: 8),
            const Text(
              'Este sistema no ofrece almacenamiento seguro para la sesión: '
              'Last.fm no está disponible.',
            ),
          ],
          if (s.needsEnable) ...[
            const SizedBox(height: 8),
            const Text(
              'Cuenta conectada, pero el interruptor está apagado: no se envía '
              'ninguna escucha. Actívalo para empezar a publicar.',
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: isBrasa(context) ? Brasa.cream : null,
            activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
            title: const Text('Enviar mi historial a Last.fm'),
            subtitle: Text(
              s.connected
                  ? 'Cuenta: ${s.username ?? '—'}. Al apagarlo se borra la cola pendiente.'
                  : 'Conecta tu cuenta para poder activarlo.',
            ),
            value: s.enabled,
            onChanged: s.secureUnavailable || working
                ? null
                : (v) => s.setEnabled(v),
          ),
          if (!s.hasSession) ...[
            TextField(
              controller: _user,
              enabled: !s.secureUnavailable && !working,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Usuario de Last.fm',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              enabled: !s.secureUnavailable && !working,
              decoration: const InputDecoration(
                labelText: 'Contraseña de Last.fm',
                helperText: 'Solo se usa para iniciar sesión; no se guarda.',
                helperMaxLines: 2,
              ),
              onSubmitted: (_) => _connect(),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!s.hasSession)
                FilledButton.icon(
                  onPressed: s.secureUnavailable || working ? null : _connect,
                  icon: const Icon(Icons.login),
                  label: Text(working ? 'Conectando…' : 'Conectar'),
                ),
              if (s.hasSession || s.pending > 0)
                OutlinedButton.icon(
                  onPressed: working ? null : s.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Desconectar y borrar sesión y cola'),
                ),
            ],
          ),
          if (s.message != null) ...[
            const SizedBox(height: 8),
            Text(s.message!),
          ],
          if (s.active) ...[
            const SizedBox(height: 12),
            Text(_tracking(s.scrobbler)),
            const SizedBox(height: 4),
            Text(
              s.scrobbler.lastSentAt == null
                  ? 'Aún no se ha enviado ninguna escucha en esta sesión.'
                  : 'Enviadas esta sesión: ${s.scrobbler.sentCount}. '
                        'Último envío: ${_ago(s.scrobbler.lastSentAt!)}.',
            ),
            if (s.scrobbler.lastError != null) ...[
              const SizedBox(height: 4),
              Text('Último error: ${s.scrobbler.lastError}'),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: working ? null : s.scrobbler.flush,
              icon: const Icon(Icons.sync),
              label: const Text('Enviar pendientes ahora'),
            ),
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
