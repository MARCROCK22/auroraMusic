import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'artwork.dart';
import 'horizontal_music_row.dart';

class PlaylistShelf extends StatelessWidget {
  const PlaylistShelf({
    super.key,
    required this.controller,
    required this.onOpen,
    this.horizontal = false,
  });
  final bool horizontal;
  final AppController controller;
  final ValueChanged<MusicPlaylist> onOpen;

  @override
  Widget build(BuildContext context) {
    final cards = controller.playlists.map((playlist) {
      final tracks = controller.tracks
          .where((t) => playlist.trackIds.contains(t.id))
          .take(4)
          .toList();
      return SizedBox(
        width: 160,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onOpen(playlist),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tracks.isEmpty)
                    SizedBox.square(
                      dimension: ArtworkContext.cardCompact.size,
                      child: const Icon(Icons.queue_music, size: 48),
                    )
                  else if (tracks.length < 4)
                    Artwork(
                      track: tracks.first,
                      artworkContext: ArtworkContext.cardCompact,
                      radius: 8,
                    )
                  else
                    Wrap(
                      children: tracks
                          .map(
                            (t) => Artwork(
                              track: t,
                              artworkContext: ArtworkContext.mosaic,
                              radius: 0,
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.trackIds.length} canciones',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
    if (horizontal) {
      return HorizontalMusicRow(
        title: 'Hechas por ti',
        itemCount: cards.length,
        itemWidth: 160,
        itemHeight: 180 + MediaQuery.textScalerOf(context).scale(108),
        itemBuilder: (_, index) => cards[index],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hechas por ti', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 16, children: cards),
      ],
    );
  }
}
