import 'package:flutter/material.dart';

import 'update_controller.dart';

/// Render mínimo de Markdown (títulos, viñetas, **negrita**, `código`).
class MiniMarkdown extends StatelessWidget {
  const MiniMarkdown(this.text, {super.key});
  final String text;

  static final _inline = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');

  List<InlineSpan> _spans(String line, TextStyle? base) {
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in _inline.allMatches(line)) {
      if (m.start > i) out.add(TextSpan(text: line.substring(i, m.start)));
      out.add(
        TextSpan(
          text: m[1] ?? m[2],
          style: m[1] != null
              ? const TextStyle(fontWeight: FontWeight.w700)
              : const TextStyle(fontFamily: 'monospace'),
        ),
      );
      i = m.end;
    }
    if (i < line.length) out.add(TextSpan(text: line.substring(i)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        rows.add(const SizedBox(height: 6));
        continue;
      }
      final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      final b = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
      if (h != null) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(h[2]!, style: t.titleSmall),
          ),
        );
      } else {
        final style = t.bodyMedium;
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: b != null ? 12 : 0),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (b != null) const TextSpan(text: '•  '),
                  ..._spans(b != null ? b[1]! : line, style),
                ],
              ),
            ),
          ),
        );
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

Future<void> _showNotes(BuildContext context, UpdateController u) {
  final r = u.release!;
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Aurora ${r.version}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: MiniMarkdown(
            r.notes.isEmpty ? 'Sin notas de versión.' : r.notes,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

/// «Actualizar ahora»; si suena música pide confirmación (permite posponer).
Future<void> confirmAndInstall(
  BuildContext context,
  UpdateController u,
  bool Function() isPlaying,
) async {
  if (isPlaying()) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hay música sonando'),
        content: const Text(
          'Aurora se cerrará para actualizarse y la reproducción se detendrá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
  }
  await u.install();
}

/// Banner discreto bajo la barra superior.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.controller,
    required this.isPlaying,
  });
  final UpdateController controller;
  final bool Function() isPlaying;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final u = controller;
      final colors = Theme.of(context).colorScheme;
      final o = u.outcome;
      if (o != null) return _OutcomeBar(controller: u, outcome: o);
      if (!u.showBanner) return const SizedBox.shrink();
      if (u.phase == UpdatePhase.installing) {
        return Material(
          color: colors.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Instalando la actualización… Aurora se reiniciará sola.',
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
                const SizedBox(height: 4),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ),
          ),
        );
      }
      final busy = u.phase == UpdatePhase.downloading;
      return Material(
        color: colors.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Icon(
                    Icons.system_update_alt,
                    size: 18,
                    color: colors.onSecondaryContainer,
                  ),
                  Text(
                    busy
                        ? 'Descargando Aurora ${u.release!.version}…'
                        : 'Nueva versión ${u.release!.version}',
                    style: TextStyle(color: colors.onSecondaryContainer),
                  ),
                  TextButton(
                    onPressed: () => _showNotes(context, u),
                    child: const Text('Novedades'),
                  ),
                  if (!busy) ...[
                    FilledButton(
                      onPressed: () => confirmAndInstall(context, u, isPlaying),
                      child: Text(
                        u.error != null ? 'Reintentar' : 'Actualizar ahora',
                      ),
                    ),
                    TextButton(
                      onPressed: u.later,
                      child: const Text('Más tarde'),
                    ),
                    TextButton(
                      onPressed: u.skip,
                      child: const Text('Omitir esta versión'),
                    ),
                  ],
                ],
              ),
              if (busy)
                LinearProgressIndicator(value: u.progress, minHeight: 2),
              if (u.error != null)
                Text(u.error!, style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      );
    },
  );
}

class _OutcomeBar extends StatelessWidget {
  const _OutcomeBar({required this.controller, required this.outcome});
  final UpdateController controller;
  final UpdateOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final o = outcome;
    return Material(
      color: o.failed ? colors.errorContainer : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(
              o.failed
                  ? 'La actualización no se completó (${o.version}).'
                  : 'Actualizada a ${o.version}.',
            ),
            if (o.failed) ...[
              FilledButton(
                onPressed: controller.openInstaller,
                child: const Text('Abrir el instalador'),
              ),
              if (o.logPath != null)
                SelectableText(
                  'Registro: ${o.logPath}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            TextButton(
              onPressed: controller.dismissOutcome,
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sección de Ajustes → Actualizaciones.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key, required this.controller});
  final UpdateController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final u = controller;
      if (!u.supported) {
        return const Text(
          'Las actualizaciones automáticas no están disponibles aquí.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versión instalada: ${u.currentVersion}'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Buscar actualizaciones al iniciar'),
            subtitle: const Text('Como máximo una vez cada 6 horas.'),
            value: u.autoCheck,
            onChanged: u.setAuto,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Canal beta'),
            subtitle: const Text('Incluye versiones preliminares.'),
            value: u.beta,
            onChanged: u.setBeta,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: u.phase == UpdatePhase.checking ? null : u.check,
              icon: const Icon(Icons.refresh),
              label: Text(
                u.phase == UpdatePhase.checking
                    ? 'Buscando…'
                    : 'Buscar actualizaciones',
              ),
            ),
          ),
          if (u.info != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(u.info!),
            ),
          if (u.error != null && !u.showBanner)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                u.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
