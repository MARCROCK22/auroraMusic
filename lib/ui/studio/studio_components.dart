import 'package:flutter/material.dart';

abstract final class StudioPalette {
  static const canvas = Color(0xff151312);
  static const well = Color(0xff100e0d);
  static const low = Color(0xff1d1b1a);
  static const panel = Color(0xff211f1e);
  static const high = Color(0xff2c2928);
  static const seam = Color(0xff373433);
  static const ink = Color(0xffe8e1df);
  static const muted = Color(0xffdfc0b3);
  static const parchment = Color(0xffa78b7f);
  static const orange = Color(0xffea6b29);
  static const peach = Color(0xffffb596);
  static const sleeve = BorderRadius.only(
    topLeft: Radius.circular(8),
    topRight: Radius.circular(2),
    bottomRight: Radius.circular(8),
    bottomLeft: Radius.circular(2),
  );
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.recessed = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool recessed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: recessed
            ? colors.surfaceContainerLowest
            : colors.surfaceContainerLow,
        borderRadius: StudioPalette.sleeve,
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(3, 4))],
      ),
      // Own Material so ink (hover/selected/focus) paints above the panel fill.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class StudioStamp extends StatelessWidget {
  const StudioStamp(this.text, {super.key, this.color, this.filled = false});
  final String text;
  final Color? color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = Text(
      text,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        letterSpacing: .5,
        color: color ?? colors.onSurfaceVariant,
      ),
    );
    return filled
        ? ColoredBox(
            color: colors.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: label,
            ),
          )
        : label;
  }
}

void showStudioPending(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature: función pendiente de implementar.')),
  );
}

String studioTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
