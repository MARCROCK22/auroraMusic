import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../artwork.dart';
import 'playlist_view_mode.dart';

/// Portada de una playlist: mosaico de hasta 4 portadas, una sola, o una
/// ilustración con degradado e inicial cuando no hay pistas.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    required this.tracks,
    required this.size,
  });
  final MusicPlaylist playlist;
  final List<Track> tracks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final photo = playlist.photoPath;
    if (photo != null) {
      return PlaylistPhoto(
        path: photo,
        size: size,
        fallback: _generated(context),
      );
    }
    return _generated(context);
  }

  Widget _generated(BuildContext context) {
    if (tracks.length >= 4) {
      final h = size / 2;
      return SizedBox.square(
        dimension: size,
        child: Column(
          children: [
            for (var r = 0; r < 2; r++)
              Row(
                children: [
                  for (var c = 0; c < 2; c++)
                    Artwork(track: tracks[r * 2 + c], size: h, radius: 0),
                ],
              ),
          ],
        ),
      );
    }
    if (tracks.isNotEmpty) {
      return Artwork(track: tracks.first, size: size, radius: 0);
    }
    final base = playlistColor(playlist);
    final hsl = HSLColor.fromColor(base);
    final initial = playlist.name.trim().isEmpty
        ? '♪'
        : playlist.name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            hsl.withLightness((hsl.lightness + .12).clamp(0, 1)).toColor(),
            hsl
                .withHue((hsl.hue + 40) % 360)
                .withLightness((hsl.lightness - .14).clamp(0, 1))
                .toColor(),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _RingsPainter(),
        child: Center(
          child: Text(
            initial,
            style: TextStyle(
              fontFamily: 'Bagel Fat One',
              fontSize: size * .42,
              color: Colors.white.withValues(alpha: .88),
              shadows: const [Shadow(blurRadius: 8, color: Colors.black38)],
            ),
          ),
        ),
      ),
    );
  }
}

/// Foto elegida por el usuario; el borde toma el color del tema activo.
class PlaylistPhoto extends StatelessWidget {
  const PlaylistPhoto({
    super.key,
    required this.path,
    required this.size,
    this.radius = 0,
    this.fallback,
  });
  final String path;
  final double size;
  final double radius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          File(path),
          key: ValueKey('playlist-photo-$path'),
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: (size * 2).round().clamp(64, 1024),
          errorBuilder: (_, _, _) =>
              fallback ?? ColoredBox(color: scheme.surfaceContainerHigh),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .12);
    final c = Offset(size.width * .78, size.height * .22);
    for (var i = 1; i <= 5; i++) {
      canvas.drawCircle(c, size.width * .14 * i, p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
