import 'package:flutter/material.dart';
import '../../app_controller.dart';
import '../../core/models.dart';
import '../artwork.dart';
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
  });
  final AppController controller;
  final VoidCallback onLyrics, onVinyl, onQueue, onOpenPlayer;
  @override
  State<StudioTransport> createState() => _StudioTransportState();
}

class _StudioTransportState extends State<StudioTransport> {
  double? _scrub;
  String? _scrubTrack;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final track = c.currentTrack;
      final colors = Theme.of(context).colorScheme;
      final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 1100 && !large;
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
                        c.adPlaying
                            ? 'Anuncio · tu canción sigue después'
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
                  onPressed: track == null
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
              IconButton(
                tooltip: 'Anterior',
                onPressed: track == null ? null : c.previous,
                icon: const Icon(StudioSymbols.skipPrevious, size: 18),
              ),
              _play(c),
              IconButton(
                tooltip: 'Siguiente',
                onPressed: track == null ? null : c.next,
                icon: const Icon(StudioSymbols.skipNext, size: 18),
              ),
              if (wide)
                IconButton(
                  tooltip: 'Repetir',
                  onPressed: track == null ? null : c.cycleRepeat,
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
          final progress = _progress(c);
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
                          width: 340,
                          child: Row(
                            children: [
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
                          IconButton(
                            tooltip: 'Siguiente',
                            onPressed: track == null ? null : c.next,
                            icon: const Icon(StudioSymbols.skipNext),
                          ),
                          IconButton(
                            tooltip: 'Letras',
                            onPressed: widget.onLyrics,
                            icon: const Icon(StudioSymbols.lyrics),
                          ),
                        ],
                      ),
                      progress,
                    ],
                  ),
          );
        },
      );
    },
  );
  Widget _play(AppController c) {
    final colors = Theme.of(context).colorScheme;
    final enabled = c.currentTrack != null && !c.jamPlaybackActive;
    return Container(
      decoration: BoxDecoration(
        color: enabled ? colors.primaryContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(2, 3))],
      ),
      child: IconButton(
        tooltip: c.audio.isPlaying ? 'Pausar' : 'Reproducir',
        onPressed: enabled ? c.togglePlayback : null,
        icon: c.busy
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

  Widget _progress(AppController c) {
    final duration = c.audio.duration.inMilliseconds;
    final position =
        (_scrubTrack == c.currentTrack?.id ? _scrub : null) ??
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
              onChangeStart: duration <= 0 || c.currentTrack == null
                  ? null
                  : (value) {
                      _scrubTrack = c.currentTrack!.id;
                    },
              onChanged: duration <= 0 || c.currentTrack == null
                  ? null
                  : (value) => setState(() => _scrub = value),
              onChangeEnd: duration <= 0 || c.currentTrack == null
                  ? null
                  : (value) {
                      if (_scrubTrack == c.currentTrack?.id) {
                        c.seek(Duration(milliseconds: value.toInt()));
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
