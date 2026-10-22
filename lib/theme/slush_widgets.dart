import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'slush_theme.dart';

/// Pegatina de estrella dentada con texto («NUEVO», «EN VIVO»), girada.
class SlushSticker extends StatelessWidget {
  const SlushSticker(
    this.label, {
    super.key,
    this.color = Slush.yellow,
    this.size = 84,
    this.angle = -.2,
  });
  final String label;
  final Color color;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BurstPainter(color),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Bagel Fat One',
              fontSize: size * .17,
              color: Slush.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path();
    const points = 14;
    for (var i = 0; i < points * 2; i++) {
      final r = size.width / 2 * (i.isEven ? 1 : .82);
      final a = math.pi * i / points;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = Slush.ink,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.color != color;
}

/// Píldora con relleno de color y contorno negro (etiquetas de estado).
class SlushPill extends StatelessWidget {
  const SlushPill(this.label, {super.key, this.color = Slush.mint});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: color,
      shape: const StadiumBorder(side: BorderSide(color: Slush.ink, width: 2)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Slush.ink,
        ),
      ),
    ),
  );
}

/// Pantalla Slush: fondo de color plano propio y titular gigante («COLA»,
/// «JAM»). El contenido ocupa el resto.
class SlushScreen extends StatelessWidget {
  const SlushScreen({
    super.key,
    required this.color,
    required this.title,
    required this.child,
  });
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 96, height: .9),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// Onda azul decorativa con borde negro, para fondos de cabecera.
class SlushWave extends StatelessWidget {
  const SlushWave({super.key, this.height = 140});
  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _WavePainter()),
    ),
  );
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(0, h * .7);
    path.cubicTo(w * .25, h * 1.1, w * .4, -h * .1, w * .65, h * .4);
    path.cubicTo(w * .8, h * .7, w * .92, h * .2, w, h * .3);
    final stroke = h * .3;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..color = Slush.ink,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Slush.blue,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}
