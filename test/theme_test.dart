import 'dart:math';

import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

void main() {
  test('all artwork hue buckets preserve readable text and action contrast', () {
    for (final brightness in Brightness.values) {
      for (var hue = 0; hue < 360; hue += 15) {
        final scheme = auroraTheme(brightness, HSLColor.fromAHSL(1, hue + 7.5, .65, .65).toColor()).colorScheme;
        expect(contrast(scheme.onSurface, scheme.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onSurfaceVariant, scheme.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(scheme.onPrimary, scheme.primary), greaterThanOrEqualTo(4.5), reason: '$brightness hue $hue button');
        expect(contrast(scheme.primary, scheme.surface), greaterThanOrEqualTo(4.5), reason: '$brightness hue $hue accent text');
      }
    }
  });
}
