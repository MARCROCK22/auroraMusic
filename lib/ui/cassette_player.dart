import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/slush_theme.dart';
import 'artwork.dart';

/// Casete realista con ligera perspectiva: carcasa de plástico negro, etiqueta
/// con la portada (franja del color de acento), ventana de cinta con bobinas
/// de 6 dientes que giran con [rotation] y cinta cuyo radio cambia con el
/// progreso. El acabado (_Skin) cambia por tema y sale de `ColorScheme.primary`
/// (ya adaptado a la portada).
class CassettePlayer extends StatelessWidget {
  const CassettePlayer({
    super.key,
    required this.controller,
    required this.track,
    required this.rotation,
    required this.size,
  });

  final AppController controller;
  final Track? track;
  final Animation<double> rotation;
  final double size;

  static const _skip = Duration(seconds: 10);

  void _skipBy(Duration delta) {
    final a = controller.audio;
    final total = a.duration > Duration.zero
        ? a.duration
        : track?.duration ?? Duration.zero;
    final ms = (a.position + delta).inMilliseconds;
    controller.seek(
      Duration(
        milliseconds: ms.clamp(
          0,
          total > Duration.zero ? total.inMilliseconds : ms.abs() + 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = size / 1.6;
    final enabled = track != null;
    final skin = _Skin.of(context, scheme);
    final small = TextStyle(
      fontFamily: skin.font,
      color: skin.ink.withValues(alpha: .8),
      fontSize: size * .028,
      fontWeight: FontWeight.w700,
    );
    return SizedBox(
      width: size,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('cassette-body'),
            width: size,
            height: height,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0008)
                ..rotateX(-.05)
                ..rotateY(-.06),
              child: ListenableBuilder(
                listenable: controller.audio,
                builder: (context, _) {
                  final a = controller.audio;
                  final total = a.duration > Duration.zero
                      ? a.duration
                      : track?.duration ?? Duration.zero;
                  final progress = total > Duration.zero
                      ? (a.position.inMilliseconds / total.inMilliseconds)
                            .clamp(0.0, 1.0)
                      : 0.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(painter: _ShellPainter(skin)),
                      ),
                      Positioned(
                        left: size * .1,
                        top: height * .07,
                        width: size * .8,
                        height: height * .62,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(size * .012),
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              border: skin.kind == _Kind.slush
                                  ? Border.all(color: Colors.black, width: 2.5)
                                  : null,
                              borderRadius: BorderRadius.circular(size * .012),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                track == null
                                    ? ColoredBox(color: scheme.surface)
                                    : Artwork.fill(
                                        track: track!,
                                        artworkContext: ArtworkContext.vinyl,
                                      ),
                                // Velo para legibilidad del rotulado.
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: skin.veil,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: size * .03,
                                  right: size * .03,
                                  top: height * .02,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            'SIDE A',
                                            maxLines: 1,
                                            style: small.copyWith(
                                              fontWeight: skin.heavy
                                                  ? FontWeight.w900
                                                  : FontWeight.w800,
                                              letterSpacing: size * .004,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              track?.artist ?? '',
                                              textAlign: TextAlign.end,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: small,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        track?.title ?? 'Sin pista',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: skin.font,
                                          color: skin.ink,
                                          fontSize: size * .05,
                                          fontWeight: FontWeight.w800,
                                          height: 1.05,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  height: height * .15,
                                  child: ColoredBox(
                                    color: scheme.primary,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: size * .03,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Flexible(
                                            flex: 3,
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                '90 MINUTES',
                                                style: TextStyle(
                                                  fontFamily: skin.font,
                                                  color: scheme.onPrimary,
                                                  fontSize: size * .055,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            flex: 2,
                                            child: Text(
                                              '45 min per side',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: small.copyWith(
                                                color: scheme.onPrimary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(painter: _WindowPainter(skin)),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const ValueKey('cassette-reels'),
                            painter: _ReelsPainter(
                              skin: skin,
                              rotation: rotation,
                              progress: progress,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: controller.audio,
            builder: (context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: enabled ? controller.previous : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  tooltip: 'Retroceder 10 s',
                  onPressed: enabled ? () => _skipBy(-_skip) : null,
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                IconButton.filled(
                  tooltip: controller.audio.isPlaying ? 'Pausa' : 'Reproducir',
                  onPressed: enabled ? controller.togglePlayback : null,
                  icon: Icon(
                    controller.audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Adelantar 10 s',
                  onPressed: enabled ? () => _skipBy(_skip) : null,
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: enabled ? controller.next : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Kind { atelier, modern, brasa, slush }

/// Acabado del casete por tema; todos los colores parten de `scheme.primary`.
class _Skin {
  _Skin({
    required this.kind,
    required this.shell,
    required this.base,
    required this.hole,
    required this.window,
    required this.windowEdge,
    required this.tick,
    required this.tape,
    required this.hub,
    required this.hubHole,
    required this.ink,
    required this.veil,
    required this.font,
    this.outline,
    this.radius = .035,
    this.dots = 0,
    this.screws = false,
    this.gloss = .12,
    this.inner = false,
    this.heavy = false,
  });

  final _Kind kind;
  final List<Color> shell; // 3 paradas
  final List<Color> base; // 2 paradas (zócalo)
  final List<Color> window; // 2 paradas
  final List<Color> veil; // 3 paradas sobre la portada
  final Color hole, windowEdge, tick, tape, hub, hubHole, ink;
  final String? font;
  final Color? outline;
  final double radius, dots, gloss;
  final bool screws, inner, heavy;

  @override
  bool operator ==(Object o) =>
      o is _Skin && o.kind == kind && o.shell[0] == shell[0];
  @override
  int get hashCode => Object.hash(kind, shell[0]);

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  static _Skin of(BuildContext context, ColorScheme scheme) {
    final p = scheme.primary;
    if (isSlush(context)) {
      final hsl = HSLColor.fromColor(p);
      final flat = hsl
          .withSaturation(hsl.saturation.clamp(.65, 1.0))
          .withLightness(.62)
          .toColor();
      final lift = _mix(flat, Colors.white, .25);
      return _Skin(
        kind: _Kind.slush,
        shell: [flat, flat, flat],
        base: [lift, lift],
        hole: Colors.black,
        window: const [Colors.white, Colors.white],
        windowEdge: Colors.black,
        tick: Colors.black,
        tape: const Color(0xFF1A1A1A),
        hub: Colors.white,
        hubHole: Colors.black,
        ink: Colors.black,
        veil: const [Color(0xE6FFFFFF), Color(0xB3FFFFFF), Color(0xCCFFFFFF)],
        font: 'Bagel Fat One',
        outline: Colors.black,
        radius: .05,
        gloss: 0,
        heavy: true,
      );
    }
    if (isModern(context)) {
      final shell = _mix(Colors.white, p, .28);
      return _Skin(
        kind: _Kind.modern,
        shell: [_mix(shell, Colors.white, .5), shell, _mix(shell, p, .25)],
        base: [_mix(shell, Colors.white, .3), _mix(shell, p, .15)],
        hole: _mix(p, Colors.black, .5).withValues(alpha: .35),
        window: [
          Colors.white.withValues(alpha: .55),
          Colors.white.withValues(alpha: .3),
        ],
        windowEdge: Colors.white.withValues(alpha: .8),
        tick: const Color(0xFF3A3A44),
        tape: _mix(p, Colors.black, .55),
        hub: Colors.white,
        hubHole: _mix(p, Colors.black, .35),
        ink: const Color(0xFF1E1E26),
        veil: const [Color(0xCCFFFFFF), Color(0x55FFFFFF), Color(0x88FFFFFF)],
        font: 'Inter',
        radius: .06,
        gloss: .35,
      );
    }
    if (isBrasa(context)) {
      const amber = Color(0xFFE0A24A);
      return _Skin(
        kind: _Kind.brasa,
        shell: [
          _mix(const Color(0xFF3A2E26), p, .08),
          const Color(0xFF2A221C),
          const Color(0xFF1B1613),
        ],
        base: const [Color(0xFF241D18), Color(0xFF17120F)],
        hole: const Color(0xFF0C0907),
        window: const [Color(0xFF0E0B09), Color(0xFF1C1612)],
        windowEdge: amber.withValues(alpha: .55),
        tick: amber.withValues(alpha: .8),
        tape: const Color(0xFF5A3A22),
        hub: const Color(0xFFEBD9BC),
        hubHole: const Color(0xFF120E0B),
        ink: const Color(0xFFF3E6CF),
        veil: const [Color(0xCC120E0B), Color(0x55120E0B), Color(0x99120E0B)],
        font: 'Inter',
        outline: amber.withValues(alpha: .5),
        gloss: .05,
      );
    }
    // Atelier: plástico crema y etiqueta de papel.
    final cream = _mix(const Color(0xFFEADFC4), p, .1);
    const wood = Color(0xFF8A7656);
    return _Skin(
      kind: _Kind.atelier,
      shell: [_mix(cream, Colors.white, .35), cream, _mix(cream, wood, .3)],
      base: [_mix(cream, wood, .15), _mix(cream, wood, .35)],
      hole: const Color(0xFF3A3024),
      window: const [Color(0xFF2A2118), Color(0xFF3B2F23)],
      windowEdge: wood,
      tick: const Color(0xFFEFE4CC),
      tape: const Color(0xFF4A2F1D),
      hub: const Color(0xFFF6F0E0),
      hubHole: const Color(0xFF2A2118),
      ink: const Color(0xFF2A2118),
      veil: const [Color(0xE6F6F0E0), Color(0x66F6F0E0), Color(0xB3F6F0E0)],
      font: 'Newsreader',
      dots: .05,
      screws: true,
      inner: true,
    );
  }
}

// Geometría compartida de la ventana de cinta (coordenadas del cuerpo).
Rect _windowRect(Size s) =>
    Rect.fromLTWH(s.width * .22, s.height * .24, s.width * .56, s.height * .27);

void _dots(Canvas c, Rect r, double step, double w, Color col) {
  final pts = <Offset>[];
  for (var y = r.top; y < r.bottom; y += step) {
    for (var x = r.left; x < r.right; x += step) {
      pts.add(Offset(x, y));
    }
  }
  c.drawPoints(
    ui.PointMode.points,
    pts,
    Paint()
      ..color = col
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round,
  );
}

void _screw(Canvas c, Offset o, double r) {
  c.drawCircle(
    o.translate(0, r * .25),
    r * 1.15,
    Paint()..color = Colors.black87,
  );
  c.drawCircle(
    o,
    r,
    Paint()
      ..shader = ui.Gradient.radial(
        o.translate(-r * .3, -r * .3),
        r * 1.4,
        const [Color(0xFFEDEDED), Color(0xFF8C8C8C), Color(0xFF4A4A4A)],
        const [0, .6, 1],
      ),
  );
  final slot = Paint()
    ..color = Colors.black87
    ..strokeWidth = r * .28
    ..strokeCap = StrokeCap.round;
  c.drawLine(o.translate(-r * .6, 0), o.translate(r * .6, 0), slot);
  c.drawLine(o.translate(0, -r * .6), o.translate(0, r * .6), slot);
}

class _ShellPainter extends CustomPainter {
  const _ShellPainter(this.skin);

  final _Skin skin;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final body = RRect.fromRectAndRadius(
      rect,
      Radius.circular(s.width * skin.radius),
    );
    final hard = skin.kind == _Kind.slush;
    // Sombra suave bajo el casete.
    final modern = skin.kind == _Kind.modern;
    canvas.drawRRect(
      body.shift(
        hard ? Offset(s.width * .02, s.width * .02) : Offset(0, s.height * .05),
      ),
      Paint()
        ..color = hard
            ? Colors.black
            : (modern ? skin.shell[2].withValues(alpha: .5) : Colors.black54)
        ..maskFilter = hard
            ? null
            : MaskFilter.blur(
                BlurStyle.normal,
                s.height * (modern ? .09 : .05),
              ),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          skin.shell,
          const [0, .5, 1],
        ),
    );
    canvas.save();
    canvas.clipRRect(body);
    // Textura de rejilla/puntitos.
    if (skin.dots > 0) {
      _dots(
        canvas,
        rect,
        s.width * .016,
        s.width * .006,
        Colors.black.withValues(alpha: skin.dots),
      );
    }
    // Brillo superior.
    if (skin.gloss > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, s.width, s.height * .5),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s.height * .5), [
            Colors.white.withValues(alpha: skin.gloss),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }
    // Zócalo inferior trapezoidal con textura.
    final base = Path()
      ..moveTo(s.width * .14, s.height)
      ..lineTo(s.width * .23, s.height * .71)
      ..lineTo(s.width * .77, s.height * .71)
      ..lineTo(s.width * .86, s.height)
      ..close();
    canvas.drawPath(
      base,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, s.height * .71),
          Offset(0, s.height),
          skin.base,
        ),
    );
    canvas.save();
    canvas.clipPath(base);
    if (skin.dots > 0) {
      _dots(
        canvas,
        base.getBounds(),
        s.width * .014,
        s.width * .005,
        Colors.black.withValues(alpha: skin.dots),
      );
    }
    canvas.restore();
    canvas.drawPath(
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hard ? 2.5 : 1.2
        ..color = skin.outline ?? Colors.white.withValues(alpha: .4),
    );
    // 2 círculos y 2 rectángulos redondeados.
    final hy = s.height * .9;
    final hole = Paint()..color = skin.hole;
    final lip = Paint()..color = Colors.white.withValues(alpha: hard ? 0 : .3);
    for (final x in [.30, .70]) {
      final o = Offset(s.width * x, hy);
      canvas.drawCircle(o.translate(0, 1), s.width * .022, lip);
      canvas.drawCircle(o, s.width * .022, hole);
    }
    for (final x in [.42, .58]) {
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(s.width * x, hy),
          width: s.width * .04,
          height: s.height * .06,
        ),
        Radius.circular(s.width * .008),
      );
      canvas.drawRRect(r.shift(const Offset(0, 1)), lip);
      canvas.drawRRect(r, hole);
    }
    // Sombra interior.
    if (skin.inner) {
      final outer = Path()
        ..addRect(rect.inflate(40))
        ..addRRect(body)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        outer,
        Paint()
          ..color = Colors.black.withValues(alpha: .35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * .02),
      );
    }
    canvas.restore();
    // Bisel.
    canvas.drawRRect(
      body.deflate(.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = hard ? 3 : 1.6
        ..shader = skin.outline != null
            ? null
            : ui.Gradient.linear(
                rect.topLeft,
                rect.bottomRight,
                [
                  Colors.white.withValues(alpha: .7),
                  Colors.transparent,
                  Colors.black.withValues(alpha: .35),
                ],
                const [0, .5, 1],
              )
        ..color = skin.outline ?? Colors.white,
    );
    // 5 tornillos Phillips.
    final r = s.width * .016;
    if (skin.screws) {
      for (final o in [
        Offset(s.width * .04, s.height * .07),
        Offset(s.width * .96, s.height * .07),
        Offset(s.width * .04, s.height * .93),
        Offset(s.width * .96, s.height * .93),
        Offset(s.width * .5, s.height * .78),
      ]) {
        _screw(canvas, o, r);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ShellPainter old) => old.skin != skin;
}

/// Ventana oscura redondeada, ventanita central y escala 100·50·0.
class _WindowPainter extends CustomPainter {
  const _WindowPainter(this.skin);

  final _Skin skin;

  @override
  void paint(Canvas canvas, Size s) {
    final w = _windowRect(s);
    final win = RRect.fromRectAndRadius(w, Radius.circular(w.height * .5));
    canvas.drawRRect(
      win.inflate(s.width * .008),
      Paint()..color = skin.kind == _Kind.slush ? Colors.black : skin.hole,
    );
    canvas.drawRRect(
      win,
      Paint()
        ..shader = ui.Gradient.linear(w.topCenter, w.bottomCenter, skin.window),
    );
    // Ventanita central.
    final mid = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(s.width * .5, w.center.dy - w.height * .08),
        width: s.width * .15,
        height: w.height * .5,
      ),
      Radius.circular(s.width * .006),
    );
    canvas.drawRRect(mid, Paint()..color = skin.hubHole.withValues(alpha: .6));
    canvas.drawRRect(
      mid,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = skin.windowEdge,
    );
    // Escala 100 · 50 · 0.
    final y = w.bottom - w.height * .13;
    final x0 = s.width * .43, x1 = s.width * .57;
    final tick = Paint()
      ..color = skin.tick
      ..strokeWidth = 1;
    for (var i = 0; i <= 10; i++) {
      final x = x0 + (x1 - x0) * i / 10;
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y - (i % 5 == 0 ? 4 : 2.5)),
        tick,
      );
    }
    for (final e in {'100': x0, '50': (x0 + x1) / 2, '0': x1}.entries) {
      final tp = TextPainter(
        text: TextSpan(
          text: e.key,
          style: TextStyle(
            color: skin.tick,
            fontFamily: skin.font,
            fontSize: s.width * .02,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(e.value - tp.width / 2, y + 1));
    }
    canvas.drawRRect(
      win,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = skin.kind == _Kind.slush ? 2.5 : 1.2
        ..color = skin.windowEdge,
    );
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) => old.skin != skin;
}

class _ReelsPainter extends CustomPainter {
  _ReelsPainter({
    required this.skin,
    required this.rotation,
    required this.progress,
  }) : super(repaint: rotation);

  final _Skin skin;
  final Animation<double> rotation;
  final double progress;

  @override
  void paint(Canvas canvas, Size s) {
    final w = _windowRect(s);
    final win = RRect.fromRectAndRadius(w, Radius.circular(w.height * .5));
    canvas.save();
    canvas.clipRRect(win);
    final cy = w.center.dy;
    final hubR = w.height * .27;
    final maxR = w.height * .5;
    final minR = hubR * 1.1;
    final left = Offset(s.width * .33, cy);
    final right = Offset(s.width * .67, cy);
    // El carrete de origen se vacía y el de destino se llena.
    final leftR = minR + (maxR - minR) * (1 - progress);
    final rightR = minR + (maxR - minR) * progress;
    final tape = Paint()..color = skin.tape;
    canvas.drawCircle(left, leftR, tape);
    canvas.drawCircle(right, rightR, tape);
    canvas.drawLine(
      left.translate(0, leftR),
      right.translate(0, rightR),
      Paint()
        ..color = skin.tape
        ..strokeWidth = 2.5,
    );
    final angle = rotation.value * math.pi * 2 * 4;
    for (final c in [left, right]) {
      canvas.drawCircle(c, hubR, Paint()..color = skin.hub);
      canvas.drawCircle(c, hubR * .62, Paint()..color = skin.hubHole);
      final tooth = Paint()
        ..color = skin.hub
        ..strokeWidth = hubR * .2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 6; i++) {
        final a = angle + i * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a));
        canvas.drawLine(c + d * hubR * .5, c + d * hubR * .7, tooth);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReelsPainter old) =>
      progress != old.progress || skin != old.skin;
}
