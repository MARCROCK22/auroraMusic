import 'package:flutter/material.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../studio/studio_components.dart';

/// Permisos y etiquetas derivados de la sesión; los usa la barra, el chip y el panel.
extension JamUi on JamController {
  bool get isStaff => role != JamRole.guest;
  bool get listeningTogether => service.mode == JamMode.synchronized;
  int get peopleCount => service.participants.where((p) => p.connected).length;
  String get code => service.invite?.code ?? '';
  String get roleLabel => switch (role) {
    JamRole.host => 'Host',
    JamRole.coHost => 'Co-host',
    JamRole.guest => 'Invitado',
  };
  String get modeLabel => listeningTogether ? 'Escuchando' : 'Solo añadir';
}

String jamRoleLabel(JamRole role) => switch (role) {
  JamRole.host => 'Host',
  JamRole.coHost => 'Co-host',
  JamRole.guest => 'Invitado',
};

/// Avatar con la inicial; el color sale del nombre para ser estable entre pantallas.
class JamAvatar extends StatelessWidget {
  const JamAvatar({super.key, required this.name, this.size = 28, this.muted});
  final String name;
  final double size;
  final bool? muted;
  static const _tones = [
    StudioPalette.orange,
    StudioPalette.peach,
    StudioPalette.parchment,
    StudioPalette.muted,
    Color(0xff8fb996),
    Color(0xff9db4d6),
  ];
  @override
  Widget build(BuildContext context) {
    final tone = _tones[name.codeUnits.fold(0, (a, b) => a + b) % _tones.length];
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tone,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            width: 2,
          ),
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: StudioPalette.canvas,
            fontSize: size * .45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class JamAvatarStack extends StatelessWidget {
  const JamAvatarStack({
    super.key,
    required this.names,
    this.size = 24,
    this.max = 4,
  });
  final List<String> names;
  final double size;
  final int max;
  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final step = size * .7;
    return SizedBox(
      width: step * (shown.length + (extra > 0 ? 1 : 0)) + size * .3,
      height: size,
      child: Stack(
        children: [
          for (final (i, name) in shown.indexed)
            Positioned(
              left: i * step,
              child: JamAvatar(name: name, size: size),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: StudioPalette.high,
                  shape: BoxShape.circle,
                  border: Border.all(color: StudioPalette.well, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(fontSize: size * .38, color: StudioPalette.ink),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Píldora de la barra inferior y del chip: avatares + «Jam · N» + rol/modo.
class JamPill extends StatelessWidget {
  const JamPill({
    super.key,
    required this.jam,
    required this.onTap,
    this.compact = false,
  });
  final JamController jam;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final names = [
      for (final p in jam.service.participants)
        if (p.connected) p.name,
    ];
    final label =
        'Jam · ${jam.peopleCount} ${jam.peopleCount == 1 ? 'persona' : 'personas'}';
    return Semantics(
      button: true,
      label: '$label, ${jam.roleLabel}, ${jam.modeLabel}. Abrir panel de la Jam',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Abrir la Jam',
        child: Material(
          color: colors.surfaceContainerHigh,
          shape: StadiumBorder(
            side: BorderSide(color: colors.primaryContainer.withAlpha(120)),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    JamAvatarStack(names: names, size: 22, max: compact ? 2 : 3),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            compact ? 'Jam · ${jam.peopleCount}' : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!compact)
                            Text(
                              '${jam.roleLabel} · ${jam.modeLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
