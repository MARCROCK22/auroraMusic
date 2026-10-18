import 'package:flutter/material.dart';

/// Interaction-state tokens (hover, selected, pressed, focus, disabled) derived
/// from the scheme and the artwork accent, so every component shares them.
@immutable
class AuroraStates extends ThemeExtension<AuroraStates> {
  const AuroraStates({
    required this.hover,
    required this.selected,
    required this.pressed,
    required this.focusRing,
    required this.selectedBar,
    required this.onSelected,
    required this.disabledText,
    required this.tertiaryText,
  });

  /// Translucent overlays: paint them over any surface.
  final Color hover, selected, pressed;
  final Color focusRing, selectedBar, onSelected;
  final Color disabledText, tertiaryText;

  factory AuroraStates.from(ColorScheme s) {
    final dark = s.brightness == Brightness.dark;
    // Keep the selected tint at a similar brightness for any accent: very
    // bright ones wash out text, very dark ones disappear.
    var tint = s.primary;
    if (dark) {
      final hsl = HSLColor.fromColor(s.primary);
      var l = hsl.lightness.clamp(.45, .6);
      tint = hsl.withLightness(l).toColor();
      while (tint.computeLuminance() > .22 && l > .25) {
        l -= .02;
        tint = hsl.withLightness(l).toColor();
      }
    }
    return AuroraStates(
      hover: Color.lerp(
        s.onSurface,
        s.primary,
        .3,
      )!.withValues(alpha: dark ? .13 : .13),
      selected: tint.withValues(alpha: dark ? .31 : .25),
      pressed: s.primary.withValues(alpha: dark ? .34 : .32),
      focusRing: s.primary,
      selectedBar: Color.lerp(s.primary, s.onSurface, dark ? .35 : .3)!,
      onSelected: s.onSurface,
      disabledText: Color.lerp(s.surface, s.onSurfaceVariant, .8)!,
      tertiaryText: s.onSurfaceVariant,
    );
  }

  static AuroraStates of(BuildContext context) =>
      Theme.of(context).extension<AuroraStates>() ??
      AuroraStates.from(Theme.of(context).colorScheme);

  @override
  AuroraStates copyWith() => this;

  @override
  AuroraStates lerp(AuroraStates? other, double t) => other ?? this;
}

/// Row decoration: selected tint + 3 px accent bar (not only colour), hover tint.
Color auroraRowFill(
  BuildContext context, {
  bool selected = false,
  bool hovered = false,
}) {
  final st = AuroraStates.of(context);
  return selected ? st.selected : (hovered ? st.hover : Colors.transparent);
}

ShapeBorder auroraSelectedShape(BuildContext context, {double radius = 12}) =>
    _BarShape(AuroraStates.of(context).selectedBar, radius);

class _BarShape extends RoundedRectangleBorder {
  _BarShape(this.bar, double r) : super(borderRadius: BorderRadius.circular(r));
  final Color bar;
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    super.paint(canvas, rect, textDirection: textDirection);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 2, rect.top + 8, 3, rect.height - 16),
        const Radius.circular(2),
      ),
      Paint()..color = bar,
    );
  }
}
