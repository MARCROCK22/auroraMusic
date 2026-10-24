import 'package:flutter/material.dart';

const _navy = Color(0xff151b31);
const _mint = Color(0xff86e0c1);
const _coral = Color(0xffff5858);
const _butter = Color(0xfff2f2f2);

/// Marca de Aurora Music: tres barras de onda (menta, marfil, coral) sobre
/// tinta marino. [markScale] reduce la marca (icono adaptable de Android) y
/// [background] = false deja solo las barras.
class AuroraLogoPainter extends CustomPainter {
  const AuroraLogoPainter({this.background = true, this.markScale = 1});
  final bool background;
  final double markScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * .22)),
        Paint()..color = _navy,
      );
    }
    final m = s * markScale;
    final o = (s - m) / 2;
    final w = m * .17;
    // (centro x, alto, color) en fracciones de la marca.
    for (final (cx, h, c) in [
      (.27, .36, _mint),
      (.5, .66, _butter),
      (.73, .48, _coral),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(o + m * cx, s / 2),
            width: w,
            height: m * h,
          ),
          Radius.circular(w / 2),
        ),
        Paint()..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(AuroraLogoPainter old) =>
      old.background != background || old.markScale != markScale;
}

class AuroraLogo extends StatelessWidget {
  const AuroraLogo({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: const AuroraLogoPainter()),
  );
}
