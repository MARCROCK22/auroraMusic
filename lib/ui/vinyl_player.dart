import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';

class VinylPlayer extends StatefulWidget {
  const VinylPlayer({super.key, required this.controller});
  final AppController controller;

  @override
  State<VinylPlayer> createState() => _VinylPlayerState();
}

class _VinylPlayerState extends State<VinylPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.audio.addListener(_syncRotation);
    widget.controller.addListener(_syncRotation);
  }

  @override
  void didUpdateWidget(covariant VinylPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.audio.removeListener(_syncRotation);
      oldWidget.controller.removeListener(_syncRotation);
      widget.controller.audio.addListener(_syncRotation);
      widget.controller.addListener(_syncRotation);
      _syncRotation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncRotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _syncRotation();
  }

  void _syncRotation() {
    if (!mounted) return;
    final motion =
        !widget.controller.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (widget.controller.audio.isPlaying && _foreground && motion) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.audio.removeListener(_syncRotation);
    widget.controller.removeListener(_syncRotation);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ListenableBuilder(
      listenable: widget.controller.audio,
      builder: (context, _) => _content(context),
    ),
  );

  Widget _content(BuildContext context) {
    final c = widget.controller;
    final track = c.currentTrack;
    final duration = c.audio.duration > Duration.zero
        ? c.audio.duration
        : track?.duration ?? Duration.zero;
    final pos = c.audio.position.inMilliseconds.clamp(
      0,
      math.max(0, duration.inMilliseconds),
    );
    final color = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final artSize = compact
            ? math.min(math.max(0.0, constraints.maxWidth - 36), 360.0)
            : math
                  .min(
                    (constraints.maxWidth - 300) * .58,
                    constraints.maxHeight - 48,
                  )
                  .clamp(0.0, 420.0);
        final record = SizedBox.square(
          dimension: artSize,
          child: Stack(
            children: [
              GestureDetector(
                onHorizontalDragUpdate: duration > Duration.zero
                    ? (details) => c.seek(
                        Duration(
                          milliseconds: (pos + details.delta.dx * 900)
                              .round()
                              .clamp(0, duration.inMilliseconds),
                        ),
                      )
                    : null,
                child: AnimatedBuilder(
                  animation: _rotation,
                  builder: (context, child) => Transform.rotate(
                    angle: _rotation.value * math.pi * 2,
                    child: child,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          key: const ValueKey('vinyl-disc'),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xff171514),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 26,
                                offset: Offset(0, 12),
                              ),
                            ],
                          ),
                          child: CustomPaint(painter: _GroovesPainter()),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          key: const ValueKey('vinyl-label'),
                          width: artSize * .38,
                          height: artSize * .38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.surfaceContainerHighest,
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: track == null
                              ? const Icon(Icons.music_note, size: 46)
                              : _Artwork(track: track),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          key: const ValueKey('vinyl-hole'),
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _TonearmPainter()),
                ),
              ),
            ],
          ),
        );
        final metadata = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track?.title ?? 'Nada sonando',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: color.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  _time(c.audio.position),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: Slider(
                    semanticFormatterCallback: (value) =>
                        'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                    min: 0,
                    max: math.max(1, duration.inMilliseconds).toDouble(),
                    value: pos.toDouble().clamp(
                      0,
                      math.max(1, duration.inMilliseconds).toDouble(),
                    ),
                    onChanged: duration > Duration.zero
                        ? (value) =>
                              c.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
                Text(
                  _time(duration),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: track == null ? null : c.previous,
                  icon: const Icon(Icons.skip_previous_rounded, size: 32),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: track == null ? null : c.togglePlayback,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(18),
                  ),
                  child: Icon(
                    c.audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: track == null ? null : c.next,
                  icon: const Icon(Icons.skip_next_rounded, size: 32),
                ),
              ],
            ),
          ],
        );
        final nextTracks = c.queue.skip(c.queueIndex + 1).take(3).toList();
        final nextUp = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A CONTINUACIÓN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            if (nextTracks.isEmpty)
              Text(
                'La cola está vacía',
                style: TextStyle(color: color.onSurfaceVariant),
              )
            else
              for (var i = 0; i < nextTracks.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 34,
                    height: 34,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: _Artwork(track: nextTracks[i]),
                    ),
                  ),
                  title: Text(
                    nextTracks[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    nextTracks[i].artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => c.playQueueAt(c.queueIndex + i + 1),
                ),
          ],
        );
        if (compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: record),
                const SizedBox(height: 20),
                metadata,
                const SizedBox(height: 24),
                nextUp,
              ],
            ),
          );
        }
        final compositionWidth = math.min(constraints.maxWidth - 48, 1100.0);
        final contextWidth = math.min(300.0, compositionWidth - 460);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SizedBox(
              width: compositionWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: contextWidth,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EDICIÓN DE LA BIBLIOTECA',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: color.primary,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 12),
                          metadata,
                          const SizedBox(height: 20),
                          nextUp,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(child: Center(child: record)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * .82, size.height * .12);
    final bend = Offset(size.width * .75, size.height * .20);
    final end = Offset(size.width * .58, size.height * .50);
    canvas.drawCircle(
      start,
      size.width * .045,
      Paint()..color = const Color(0xff363330),
    );
    canvas.drawLine(
      start,
      bend,
      Paint()
        ..color = const Color(0xffa49a88)
        ..strokeWidth = size.width * .018
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      bend,
      end,
      Paint()
        ..color = const Color(0xffc4bba9)
        ..strokeWidth = size.width * .014
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      end,
      size.width * .018,
      Paint()..color = const Color(0xffd97935),
    );
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) => false;
}

class _GroovesPainter extends CustomPainter {
  const _GroovesPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < 34; i++) {
      final r = radius * (.43 + i * .0088);
      paint.color = Colors.white.withValues(alpha: i.isEven ? .065 : .025);
      paint.strokeWidth = i % 5 == 0 ? 1.2 : .7;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GroovesPainter oldDelegate) => false;
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});
  final Track track;
  @override
  Widget build(BuildContext context) {
    final url = track.artworkUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(
        color: Color(0xff302923),
        child: Icon(Icons.music_note, size: 42),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xff302923),
        child: Icon(Icons.music_note, size: 42),
      ),
    );
  }
}

String _time(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
