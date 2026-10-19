import 'package:flutter/material.dart';
import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../shortcuts/shortcut_service.dart';
import '../artwork.dart';
import '../jam/jam_session_panel.dart' show jamTrackAsTrack;
import '../jam/jam_widgets.dart';
import 'equalizer_panel.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

class StudioTransport extends StatefulWidget {
  const StudioTransport({
    super.key,
    required this.controller,
    required this.onLyrics,
    required this.onVinyl,
    required this.onQueue,
    required this.onOpenPlayer,
    this.jam,
    this.onJam,
    this.onStartJam,
    this.shortcuts,
  });
  final AppController controller;
  final VoidCallback onLyrics, onVinyl, onQueue, onOpenPlayer;

  /// Para mostrar el atajo actual en los tooltips.
  final ShortcutService? shortcuts;

  /// Con una Jam activa la barra refleja rol, modo y permisos de la sesión.
  final JamController? jam;
  final VoidCallback? onJam, onStartJam;
  @override
  State<StudioTransport> createState() => _StudioTransportState();
}

class _StudioTransportState extends State<StudioTransport> {
  double? _scrub;
  String? _scrubTrack;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller,
      ?widget.jam,
      ?widget.shortcuts,
    ]),
    builder: (context, _) {
      final c = widget.controller;
      final j = widget.jam;
      final eqShortcut = widget.shortcuts?.labelOf(ShortcutId.equalizer);
      final jamOn = j != null && j.active;
      // Con audio de Jam, la pista y los permisos salen de la sesión.
      final jamAudio = _jamAudio;
      final jamEntry = jamAudio
          ? j!.service.queue
                .where((e) => e.id == j.bridge.currentEntryId)
                .firstOrNull
          : null;
      final track = jamAudio
          ? (jamEntry == null ? null : jamTrackAsTrack(jamEntry.track))
          : c.currentTrack;
      final colors = Theme.of(context).colorScheme;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      return LayoutBuilder(
        builder: (context, constraints) {
          // Con Jam activa la píldora necesita sitio: el modo ancho empieza más tarde.
          final wide = constraints.maxWidth >= (jamOn ? 1350 : 1100) && !large;
          final info = Row(
            children: [
              if (track != null)
                Artwork(
                  track: track,
                  artworkContext: wide
                      ? ArtworkContext.transport
                      : ArtworkContext.thumbnailCompact,
                  radius: 2,
                )
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: StudioPalette.sleeve,
                    boxShadow: const [
                      BoxShadow(color: Colors.black, offset: Offset(2, 3)),
                    ],
                  ),
                  child: Icon(StudioSymbols.musicNote, color: colors.primary),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track?.title ?? 'Elige una canción',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (track != null)
                      Text(
                        c.adPlaying && !jamAudio
                            ? 'Anuncio · tu canción sigue después'
                            : jamAudio
                            ? '${track.artist} · Jam'
                            : track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (wide)
                IconButton(
                  tooltip: 'Favorito',
                  onPressed: track == null
                      ? null
                      : () => c.toggleFavorite(track),
                  icon: Icon(
                    track != null && c.favoriteIds.contains(track.id)
                        ? Icons.favorite
                        : StudioSymbols.favorite,
                    size: 20,
                    color: colors.primary,
                  ),
                ),
            ],
          );
          final transport = Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (wide)
                IconButton(
                  tooltip: 'Aleatorio',
                  onPressed: track == null || jamAudio
                      ? null
                      : () => c.setShuffle(!c.shuffle),
                  icon: Icon(
                    StudioSymbols.shuffle,
                    size: 18,
                    color: c.shuffle
                        ? colors.primaryContainer
                        : colors.onSurfaceVariant,
                  ),
                ),
              TransportPreviousButton(controller: c, jam: j, size: 18),
              _play(c),
              _next(c, 18, track != null),
              if (wide)
                IconButton(
                  tooltip: 'Repetir',
                  onPressed: track == null || jamAudio ? null : c.cycleRepeat,
                  icon: Icon(
                    StudioSymbols.repeat,
                    size: 18,
                    color: c.repeat == RepeatMode.off
                        ? colors.onSurfaceVariant
                        : colors.primaryContainer,
                  ),
                ),
            ],
          );
          final tight = constraints.maxWidth < 400;
          final progress = _progress(c, track != null);
          final jamControl = jamOn
              ? JamPill(
                  jam: j,
                  onTap: widget.onJam ?? () {},
                  compact: wide && constraints.maxWidth < 1500,
                )
              : IconButton(
                  tooltip: 'Iniciar una Jam',
                  onPressed: widget.onStartJam,
                  icon: const Icon(StudioSymbols.groups, size: 18),
                );
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 24 : 12,
              vertical: wide ? 8 : 6,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLowest,
              border: Border(
                top: BorderSide(color: colors.surfaceContainerHigh),
              ),
            ),
            child: wide
                ? SizedBox(
                    height: 80,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 280,
                          child: InkWell(
                            onTap: track == null ? null : widget.onOpenPlayer,
                            child: info,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              transport,
                              SizedBox(height: 32, child: progress),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: jamOn
                              ? (constraints.maxWidth < 1500 ? 660 : 700)
                              : 490,
                          child: Row(
                            children: [
                              jamControl,
                              TextButton.icon(
                                onPressed: widget.onLyrics,
                                icon: const Icon(
                                  StudioSymbols.lyrics,
                                  size: 16,
                                ),
                                label: const Text(
                                  'Letras',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Modo Vinilo',
                                onPressed: widget.onVinyl,
                                icon: const Icon(StudioSymbols.album, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Abrir cola',
                                onPressed: widget.onQueue,
                                icon: const Icon(
                                  StudioSymbols.queueMusic,
                                  size: 18,
                                ),
                              ),
                              TransportEqualizerButton(
                                controller: c,
                                shortcut: eqShortcut,
                              ),
                              const Icon(StudioSymbols.volumeUp, size: 16),
                              Expanded(
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 3,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 12,
                                    ),
                                  ),
                                  child: Slider(
                                    semanticFormatterCallback: (value) =>
                                        'Volumen ${(value * 100).round()} por ciento',
                                    value: c.audio.volume.clamp(0, 1),
                                    onChanged: c.setVolume,
                                  ),
                                ),
                              ),
                              Text(
                                '${(c.audio.volume * 100).round()}%',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: track == null ? null : widget.onOpenPlayer,
                              child: info,
                            ),
                          ),
                          _play(c),
                          _next(c, 24, track != null),
                          IconButton(
                            tooltip: 'Letras',
                            onPressed: widget.onLyrics,
                            icon: const Icon(StudioSymbols.lyrics),
                          ),
                          if (!jamOn && !tight) jamControl,
                          // Sin sitio (estrecho o texto grande) el EQ pasa al
                          // menú de desbordamiento, con «Iniciar una Jam» si
                          // tampoco cabe su botón.
                          if (!tight && !large)
                            TransportEqualizerButton(
                              controller: c,
                              shortcut: eqShortcut,
                              size: 24,
                            )
                          else
                            TransportOverflowMenu(
                              controller: c,
                              shortcut: eqShortcut,
                              onStartJam: jamOn || !tight
                                  ? null
                                  : widget.onStartJam,
                            ),
                        ],
                      ),
                      if (jamOn)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: jamControl,
                        ),
                      progress,
                    ],
                  ),
          );
        },
      );
    },
  );
  bool get _jamAudio => transportJamAudio(widget.controller, widget.jam);

  Widget _play(AppController c) =>
      TransportPlayButton(controller: c, jam: widget.jam);

  Widget _next(AppController c, double size, bool hasTrack) =>
      TransportNextButton(
        controller: c,
        jam: widget.jam,
        size: size,
        hasTrack: hasTrack,
      );

  Widget _progress(AppController c, bool hasTrack) {
    final j = widget.jam;
    final key = _jamAudio ? 'jam' : c.currentTrack?.id;
    final seekable = hasTrack && (!_jamAudio || j!.isHost);
    final duration = c.audio.duration.inMilliseconds;
    final position =
        (_scrubTrack == key ? _scrub : null) ??
        c.audio.position.inMilliseconds.toDouble();
    return Row(
      children: [
        Text(
          studioTime(Duration(milliseconds: position.toInt())),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const _StudioNeedle(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              semanticFormatterCallback: (value) =>
                  'Posición de reproducción ${Duration(milliseconds: value.round()).inSeconds} segundos',
              value: position.clamp(0, duration > 0 ? duration.toDouble() : 1),
              max: duration > 0 ? duration.toDouble() : 1,
              onChangeStart: duration <= 0 || !seekable
                  ? null
                  : (value) {
                      _scrubTrack = key;
                    },
              onChanged: duration <= 0 || !seekable
                  ? null
                  : (value) => setState(() => _scrub = value),
              onChangeEnd: duration <= 0 || !seekable
                  ? null
                  : (value) {
                      if (_scrubTrack == key) {
                        final to = Duration(milliseconds: value.toInt());
                        _jamAudio ? j!.seek(to) : c.seek(to);
                      }
                      setState(() {
                        _scrub = null;
                        _scrubTrack = null;
                      });
                    },
            ),
          ),
        ),
        Text(
          studioTime(c.audio.duration),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
        ),
      ],
    );
  }
}

class _StudioNeedle extends SliderComponentShape {
  const _StudioNeedle();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(4, 14);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 4, height: 14),
      Paint()..color = sliderTheme.thumbColor ?? Colors.white,
    );
    context.canvas.drawLine(
      center.translate(0, -6),
      center.translate(0, 6),
      Paint()
        ..color = StudioPalette.well
        ..strokeWidth = 1,
    );
  }
}

String _hint(String? shortcut) => shortcut == null ? '' : ' ($shortcut)';

/// ¿Suena audio de una Jam? Con Jam, pista y permisos salen de la sesión.
bool transportJamAudio(AppController c, JamController? jam) =>
    jam != null && jam.active && c.jamPlaybackActive;

/// Botones de transporte compartidos por la barra inferior y el panel de
/// letras: así ambos aplican las mismas reglas (cola, shuffle, Jam, permisos).
/// El padre se redibuja con el controlador y la Jam.
class TransportPlayButton extends StatelessWidget {
  const TransportPlayButton({
    super.key,
    required this.controller,
    this.jam,
    this.shortcut,
  });
  final AppController controller;
  final JamController? jam;
  final String? shortcut;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final j = jam;
    final jamAudio = transportJamAudio(c, jam);
    final enabled = jamAudio ? j!.canPause : c.currentTrack != null;
    return Container(
      decoration: BoxDecoration(
        color: enabled ? colors.primaryContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(2, 3))],
      ),
      child: IconButton(
        tooltip: jamAudio && !enabled
            ? 'Lo controla ${j!.hostName}'
            : '${c.audio.isPlaying ? 'Pausar' : 'Reproducir'}${_hint(shortcut)}',
        onPressed: !enabled
            ? null
            : jamAudio
            ? j!.togglePlayback
            : c.togglePlayback,
        icon: c.busy && !jamAudio
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                c.audio.isPlaying
                    ? StudioSymbols.pause
                    : StudioSymbols.playArrow,
                color: enabled ? colors.onPrimaryContainer : colors.outline,
                size: 22,
              ),
      ),
    );
  }
}

class TransportNextButton extends StatelessWidget {
  const TransportNextButton({
    super.key,
    required this.controller,
    this.jam,
    this.size = 18,
    this.shortcut,
    this.hasTrack,
  });
  final AppController controller;
  final JamController? jam;
  final double size;
  final String? shortcut;
  // Con audio de Jam la pista viene de la sesión, no del controlador.
  final bool? hasTrack;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final hasTrack = this.hasTrack ?? c.currentTrack != null;
    final j = jam;
    if (!transportJamAudio(c, jam)) {
      return IconButton(
        tooltip: 'Siguiente${_hint(shortcut)}',
        onPressed: hasTrack ? c.next : null,
        icon: Icon(StudioSymbols.skipNext, size: size),
      );
    }
    final votes = j!.service.rules.votes;
    return IconButton(
      tooltip: j.canSkip
          ? 'Siguiente${_hint(shortcut)}'
          : votes
          ? 'Votar para saltar'
          : 'Lo controla ${j.hostName}',
      onPressed: !hasTrack || (!j.canSkip && !votes)
          ? null
          : j.canSkip
          ? j.next
          : j.service.voteSkip,
      icon: Icon(
        j.canSkip ? StudioSymbols.skipNext : Icons.how_to_vote_outlined,
        size: size,
      ),
    );
  }
}

class TransportPreviousButton extends StatelessWidget {
  const TransportPreviousButton({
    super.key,
    required this.controller,
    this.jam,
    this.size = 18,
    this.shortcut,
  });
  final AppController controller;
  final JamController? jam;
  final double size;
  final String? shortcut;
  @override
  Widget build(BuildContext context) {
    final off =
        controller.currentTrack == null || transportJamAudio(controller, jam);
    return IconButton(
      tooltip: transportJamAudio(controller, jam)
          ? 'No disponible en una Jam'
          : 'Anterior${_hint(shortcut)}',
      onPressed: off ? null : controller.previous,
      icon: Icon(StudioSymbols.skipPrevious, size: size),
    );
  }
}

/// Mensaje común del botón y del menú de desbordamiento.
String _eqTooltip(AppController c, String? shortcut) {
  if (!c.eq.supported) {
    return c.webPlayback
        ? 'Ecualizador no disponible: el reproductor oficial de YouTube Music no lo admite'
        : 'Ecualizador no disponible: este dispositivo no lo admite';
  }
  return 'Ecualizador${c.eq.active ? ' (activo)' : ''}${_hint(shortcut)}';
}

/// Botón de ecualizador de la barra de reproducción: abre el panel compartido
/// en una hoja sin salir de la pantalla actual. Cada oyente tiene el suyo.
class TransportEqualizerButton extends StatelessWidget {
  const TransportEqualizerButton({
    super.key,
    required this.controller,
    this.shortcut,
    this.size = 18,
  });
  final AppController controller;
  final String? shortcut;
  final double size;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.eq,
    builder: (context, _) {
      final colors = Theme.of(context).colorScheme;
      final eq = controller.eq;
      return IconButton(
        tooltip: _eqTooltip(controller, shortcut),
        onPressed: eq.supported
            ? () => showEqualizerSheet(context, controller)
            : null,
        icon: Icon(
          StudioSymbols.equalizer,
          size: size,
          color: eq.active ? colors.primaryContainer : null,
        ),
      );
    },
  );
}

/// Menú «más acciones» para barras estrechas: lleva el ecualizador cuando no
/// cabe el botón.
class TransportOverflowMenu extends StatelessWidget {
  const TransportOverflowMenu({
    super.key,
    required this.controller,
    this.shortcut,
    this.onStartJam,
  });
  final AppController controller;
  final String? shortcut;

  /// Si no es null, se ofrece «Iniciar una Jam» en el menú.
  final VoidCallback? onStartJam;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.eq,
    builder: (context, _) => PopupMenuButton<void>(
      tooltip: 'Más acciones',
      icon: const Icon(Icons.more_vert),
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: controller.eq.supported,
          onTap: () => showEqualizerSheet(context, controller),
          child: Row(
            children: [
              Icon(
                StudioSymbols.equalizer,
                size: 20,
                color: controller.eq.active
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_eqTooltip(controller, shortcut))),
            ],
          ),
        ),
        if (onStartJam != null)
          PopupMenuItem<void>(
            onTap: onStartJam,
            child: const Row(
              children: [
                Icon(StudioSymbols.groups, size: 20),
                SizedBox(width: 12),
                Expanded(child: Text('Iniciar una Jam')),
              ],
            ),
          ),
      ],
    ),
  );
}
