import 'package:flutter/material.dart';
import '../core/models.dart';

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    required this.size,
    this.radius = 12,
  });
  final Track track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: colors.primary.withValues(alpha: .10),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * .35,
          color: colors.primary,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: track.artworkUrl == null
            ? placeholder
            : track.artworkUrl!.startsWith('asset:')
            ? Image.asset(
                track.artworkUrl!.substring(6),
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(48, 1024),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
              )
            : Image.network(
                track.artworkUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(48, 1024),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, image, progress) =>
                    progress == null ? image : placeholder,
              ),
      ),
    );
  }
}
