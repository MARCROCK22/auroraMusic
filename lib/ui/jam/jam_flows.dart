import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../studio/studio_components.dart';
import 'jam_qr_code.dart';
import 'jam_session_panel.dart';

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));

/// Inicia una Jam con un toque: en línea si hay servidor, si no en la red local.
/// Al terminar abre «Invitar»; [seed] añade esas canciones a la cola.
Future<void> startJamFlow(
  BuildContext context,
  JamController jam, {
  List<Track> seed = const [],
  String name = 'Anfitrión',
}) async {
  if (!jam.service.connected) {
    if (jam.remoteAvailable) {
      await jam.hostOnline(name);
    } else {
      await jam.loadAddresses();
      if (jam.addresses.isNotEmpty) await jam.host(jam.addresses.first, name);
    }
  }
  if (!context.mounted) return;
  if (!jam.service.connected) {
    _say(context, jam.error ?? 'No se pudo iniciar la Jam. Inténtalo de nuevo.');
    return;
  }
  for (final track in seed) {
    jam.add(track);
  }
  await showJamInviteSheet(context, jam);
}

Future<void> showJamInviteSheet(BuildContext context, JamController jam) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _InviteSheet(jam: jam),
    );

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.jam});
  final JamController jam;
  @override
  Widget build(BuildContext context) {
    final invite = jam.service.invite;
    final remote = invite?.isRemote == true;
    final colors = Theme.of(context).colorScheme;
    Future<void> copy(String text, String done) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _say(context, done);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invitar a la Jam', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Escanea el código QR o comparte el código. Todos pueden añadir canciones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (invite == null)
              const Text('Aún no hay una Jam activa.')
            else ...[
              JamQrCode(data: invite.encode(), size: 200),
              const SizedBox(height: 16),
              if (remote) ...[
                const StudioStamp('CÓDIGO'),
                SelectableText(
                  invite.code,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 32,
                    letterSpacing: 6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  invite.encode(),
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ] else
                Text(
                  'Red local · ${invite.endpoint}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (remote)
                    OutlinedButton.icon(
                      onPressed: () => copy(invite.code, 'Código copiado.'),
                      icon: const Icon(Icons.tag),
                      label: const Text('Copiar código'),
                    ),
                  FilledButton.icon(
                    onPressed: () => copy(
                      remote
                          ? 'Únete a mi Jam en Aurora: ${invite.encode()} (código ${invite.code})'
                          : invite.encode(),
                      'Invitación copiada. Compártela solo con quien quieras.',
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: Text(remote ? 'Compartir enlace' : 'Copiar invitación'),
                  ),
                ],
              ),
              if (!remote) ...[
                const SizedBox(height: 12),
                Text(
                  'Red local: los dispositivos deben estar en el mismo Wi-Fi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Panel de la Jam: lateral en escritorio, hoja inferior en móvil.
Future<void> showJamPanel(BuildContext context, JamController jam) {
  final wide = MediaQuery.sizeOf(context).width >= 900;
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, scroll) => JamSessionPanel(controller: jam, scroll: scroll),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar panel de la Jam',
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 440,
        height: double.infinity,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(child: JamSessionPanel(controller: jam)),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// «Añadir a la Jam» desde cualquier sitio (p. ej. menú ⋯ de una canción).
Future<void> addToJamFlow(
  BuildContext context,
  JamController jam,
  List<Track> tracks,
) async {
  if (!jam.service.connected) {
    await startJamFlow(context, jam, seed: tracks);
    return;
  }
  for (final track in tracks) {
    jam.add(track);
  }
  if (context.mounted) {
    _say(context, jam.error ?? 'Añadida a la Jam.');
  }
}
