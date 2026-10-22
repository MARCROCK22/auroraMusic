import 'package:flutter/material.dart';

import '../lyrics/lyrics_service.dart';

/// Letras minimalistas de Brasa: solo la línea actual y sus vecinas,
/// centradas y con mucho aire, sin fondos ni marcas de tiempo.
class BrasaLyricsList extends StatelessWidget {
  const BrasaLyricsList({
    super.key,
    required this.lines,
    required this.active,
    required this.onSeek,
    required this.fontFamily,
    this.animate = true,
  });
  final List<LyricLine> lines;
  final int active;
  final void Function(LyricLine line) onSeek;
  final String fontFamily;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget row(int i, {required bool current}) {
      if (i < 0 || i >= lines.length) return const SizedBox(height: 24);
      final line = lines[i];
      return Semantics(
        liveRegion: current,
        label: line.text,
        child: InkWell(
          onTap: () => onSeek(line),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: current ? 30 : 16,
                height: 1.35,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                color: current ? c.onSurface : c.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: AnimatedSwitcher(
          duration: animate ? const Duration(milliseconds: 260) : Duration.zero,
          child: Column(
            key: ValueKey(active),
            mainAxisSize: MainAxisSize.min,
            children: [
              row(active - 1, current: false),
              if (active >= 0) row(active, current: true),
              row(active + 1, current: false),
            ],
          ),
        ),
      ),
    );
  }
}
