import '../../shortcuts/shortcut_service.dart';
import 'package:flutter/material.dart';
import '../../app_controller.dart';
import '../../core/window_controls.dart';
import '../../core/models.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

class StudioTitleBar extends StatelessWidget {
  const StudioTitleBar({
    super.key,
    required this.onNavigate,
    required this.sessionText,
    this.activeSession = false,
  });
  final ValueChanged<int> onNavigate;
  final String sessionText;
  final bool activeSession;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      return Container(
        height: largeText ? 60 : 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLowest,
          border: Border(
            bottom: BorderSide(color: colors.surfaceContainerHigh),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onPanStart: (_) => WindowControls.invoke('drag'),
              onDoubleTap: () => WindowControls.invoke('maximize'),
              child: Row(
                children: [
                  Image.asset(
                    'assets/design_idea/inicio_aurora_music_player_00.png',
                    width: 42,
                    height: 32,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(width: 8),
                  if (constraints.maxWidth > (largeText ? 450 : 400))
                    Text(
                      'Aurora',
                      style: TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 24,
                        color: colors.primary,
                      ),
                    ),
                ],
              ),
            ),
            if (constraints.maxWidth > 850 && !largeText) ...[
              const SizedBox(width: 16),
              SizedBox(
                height: 14,
                child: VerticalDivider(color: colors.surfaceContainerHighest),
              ),
              const SizedBox(width: 12),
              for (final item in [
                (2, 'Biblioteca'),
                (4, 'Modo Vinilo'),
                (6, 'Estudio Analógico'),
              ]) ...[
                InkWell(
                  onTap: () => onNavigate(item.$1),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (item.$1 != 6)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('/'),
                  ),
              ],
            ],
            // Zona vacía de la barra: arrastra la ventana y doble clic maximiza.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => WindowControls.invoke('drag'),
                onDoubleTap: () => WindowControls.invoke('maximize'),
                child: const SizedBox.expand(),
              ),
            ),
            if (constraints.maxWidth > 700 && !largeText)
              InkWell(
                onTap: () => onNavigate(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  color: colors.surfaceContainer,
                  child: Row(
                    children: [
                      Icon(
                        StudioSymbols.wifiTethering,
                        size: 14,
                        color: activeSession
                            ? colors.primaryContainer
                            : colors.outline,
                      ),
                      const SizedBox(width: 4),
                      StudioStamp(sessionText),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.circle,
                        size: 6,
                        color: activeSession
                            ? colors.primaryContainer
                            : colors.outline,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 16),
            IconButton.filled(
              tooltip: 'Perfil y ajustes',
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size(32, 32),
                padding: const EdgeInsets.all(6),
              ),
              onPressed: () => onNavigate(7),
              icon: const Icon(StudioSymbols.person, size: 18),
            ),
            if (WindowControls.supported) ...[
              const SizedBox(width: 12),
              for (final item in [
                ('minimize', StudioSymbols.minimize, 'Minimizar'),
                (
                  'maximize',
                  StudioSymbols.checkBoxOutlineBlank,
                  'Maximizar o restaurar',
                ),
                ('close', StudioSymbols.close, 'Cerrar ventana'),
              ])
                IconButton(
                  tooltip: item.$3,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (!await WindowControls.invoke(item.$1) &&
                        context.mounted) {
                      showStudioPending(context, 'Control de ventana Windows');
                    }
                  },
                  icon: Icon(item.$2, size: 15),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    super.key,
    required this.controller,
    required this.selected,
    required this.onNavigate,
    required this.onPlaylist,
    this.shortcuts,
  });
  final ShortcutService? shortcuts;
  final AppController controller;
  final int selected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<MusicPlaylist> onPlaylist;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(right: BorderSide(color: colors.surfaceContainerHigh)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'CONSOLA PRINCIPAL'),
                  const SizedBox(height: 12),
                  _nav(
                    context,
                    0,
                    'Inicio',
                    'Inicio',
                    StudioSymbols.home,
                    shortcuts?.labelOf(ShortcutId.home) ?? 'Ctrl+1',
                  ),
                  _nav(
                    context,
                    1,
                    'Búsqueda',
                    'Buscar',
                    StudioSymbols.search,
                    shortcuts?.labelOf(ShortcutId.search) ?? 'Ctrl+2',
                  ),
                  _nav(context, 8, 'DJ', 'DJ', StudioSymbols.explore, ''),
                  _nav(
                    context,
                    12,
                    'Artistas',
                    'Artistas',
                    Icons.mic_none_rounded,
                    '',
                  ),
                  if (controller.usesOfficialYouTubeMusic ||
                      controller.usesYouTubeWebAudio)
                    _nav(
                      context,
                      10,
                      'Acceso a YouTube Music',
                      'Acceso a YouTube Music',
                      Icons.music_video_outlined,
                      '',
                    ),
                  _nav(
                    context,
                    2,
                    'Biblioteca',
                    'Biblioteca',
                    StudioSymbols.libraryMusic,
                    shortcuts?.labelOf(ShortcutId.library) ?? 'Ctrl+3',
                  ),
                  _nav(
                    context,
                    3,
                    'Descargas',
                    'Descargas locales',
                    StudioSymbols.downloadDone,
                    shortcuts?.labelOf(ShortcutId.downloads) ?? 'Ctrl+4',
                  ),
                  if (controller.usesOfficialYouTubeMusic ||
                      controller.usesYouTubeWebAudio)
                    _nav(
                      context,
                      11,
                      'Descargar vídeos',
                      'Descargar vídeos',
                      Icons.video_file_outlined,
                      '',
                    ),
                  const SizedBox(height: 20),
                  Tooltip(
                    message: controller.downloadsDirectoryPath,
                    child: Container(
                      color: colors.surfaceContainerLowest,
                      padding: const EdgeInsets.all(5),
                      child: Row(
                        children: [
                          const Icon(StudioSymbols.folder, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              controller.downloadsDirectoryPath.replaceAll(
                                '\\',
                                '/',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const Icon(Icons.circle, size: 6),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _label(context, 'FIDELIDAD & EXPERIENCIA'),
                  const SizedBox(height: 12),
                  _nav(
                    context,
                    4,
                    'Modo Vinilo',
                    'Modo Vinilo',
                    StudioSymbols.album,
                    shortcuts?.labelOf(ShortcutId.vinyl) ?? 'Ctrl+I',
                  ),
                  _nav(
                    context,
                    6,
                    'Letras Dinámicas',
                    'Letras',
                    StudioSymbols.lyrics,
                    shortcuts?.labelOf(ShortcutId.lyrics) ?? 'Ctrl+L',
                  ),
                  _nav(
                    context,
                    7,
                    'Ecualizador',
                    'Ecualizador',
                    StudioSymbols.equalizer,
                    'EQ',
                    active: false,
                  ),
                  _nav(
                    context,
                    7,
                    'Modo Foco / Sueño',
                    'Modo Foco / Sueño',
                    StudioSymbols.bedtime,
                    'Zz',
                    active: false,
                  ),
                  _nav(context, 9, 'Jam', 'Jam', StudioSymbols.groups, ''),
                  _nav(
                    context,
                    5,
                    'Cola de reproducción',
                    'Cola de reproducción',
                    StudioSymbols.queueMusic,
                    '',
                  ),
                  const SizedBox(height: 20),
                  _label(context, 'ÁNIMOS & COLECCIONES'),
                  const SizedBox(height: 12),
                  for (final playlist in controller.playlists)
                    TextButton(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: colors.onSurfaceVariant,
                      ),
                      onPressed: () => onPlaylist(playlist),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            color: colors.onSurfaceVariant,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (controller.playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Aún no hay colecciones',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  _nav(
                    context,
                    7,
                    'Ajustes',
                    'Ajustes',
                    StudioSymbols.settings,
                    '',
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: colors.surfaceContainerLowest,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StudioStamp('SINCRONIZACIÓN DAC · NO MEDIDA'),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: controller.audio.isBuffering ? null : 0,
                  minHeight: 4,
                  color: colors.primaryContainer,
                ),
                const SizedBox(height: 6),
                Text(
                  controller.audio.isBuffering
                      ? 'Preparando buffer'
                      : 'Motor de reproducción listo',
                  style: TextStyle(fontSize: 10, color: colors.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String value) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: StudioStamp(value, color: Theme.of(context).colorScheme.outline),
  );
  Widget _nav(
    BuildContext context,
    int index,
    String label,
    String tooltip,
    IconData icon,
    String shortcut, {
    bool? active,
  }) {
    final colors = Theme.of(context).colorScheme;
    final chosen = active ?? selected == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: chosen ? colors.surfaceContainer : colors.surfaceContainerLow,
          child: InkWell(
            onTap: () => onNavigate(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                border: chosen
                    ? Border(
                        left: BorderSide(
                          color: colors.primaryContainer,
                          width: 2,
                        ),
                      )
                    : null,
                boxShadow: chosen
                    ? const [
                        BoxShadow(
                          color: Color(0xff0a0908),
                          offset: Offset(1, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: chosen ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: chosen
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (shortcut.isNotEmpty &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                    StudioStamp(
                      shortcut,
                      filled: true,
                      color: colors.outlineVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
