import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import 'artwork.dart';
import 'horizontal_music_row.dart';
import 'playlist_views/playlist_cassettes.dart';
import 'playlist_views/playlist_cover.dart';
import 'playlist_views/playlist_crate.dart';
import 'playlist_views/playlist_photo_menu.dart';
import 'playlist_views/playlist_view_mode.dart';

enum _PlaylistSort {
  recent('Más recientes'),
  az('A-Z'),
  za('Z-A');

  const _PlaylistSort(this.label);
  final String label;
}

class PlaylistShelf extends StatefulWidget {
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
  State<PlaylistShelf> createState() => _PlaylistShelfState();
}

class _PlaylistShelfState extends State<PlaylistShelf> {
  String _query = '';
  _PlaylistSort _sort = _PlaylistSort.recent;

  AppController get controller => widget.controller;
  bool get horizontal => widget.horizontal;
  ValueChanged<MusicPlaylist> get onOpen => widget.onOpen;

  @override
  void initState() {
    super.initState();
    loadPlaylistViewMode(controller.preferences);
  }

  List<MusicPlaylist> _visible() {
    final q = _query.trim().toLowerCase();
    final list = controller.playlists
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    // Sin fecha en el modelo: «recientes» = últimas añadidas primero.
    return switch (_sort) {
      _PlaylistSort.recent => list.reversed.toList(),
      _PlaylistSort.az => list..sort(_byName),
      _PlaylistSort.za => (list..sort(_byName)).reversed.toList(),
    };
  }

  static int _byName(MusicPlaylist a, MusicPlaylist b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  Widget _controls() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Buscar playlist',
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_PlaylistSort>(
          tooltip: 'Ordenar playlists',
          icon: const Icon(Icons.sort_rounded),
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            for (final s in _PlaylistSort.values)
              PopupMenuItem(value: s, child: Text(s.label)),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<PlaylistViewMode>(
        valueListenable: playlistViewMode,
        builder: (context, mode, _) => _build(context, mode),
      );

  Widget _build(BuildContext context, PlaylistViewMode mode) {
    final brasa = isBrasa(context);
    final visible = _visible();
    if (mode != PlaylistViewMode.normal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tus playlists', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (!horizontal) _controls(),
          if (mode == PlaylistViewMode.cassettes)
            PlaylistCassettes(
              controller: controller,
              playlists: visible,
              onOpen: onOpen,
            )
          else
            PlaylistCrate(
              controller: controller,
              playlists: visible,
              onOpen: onOpen,
            ),
        ],
      );
    }
    final List<Widget> cards = visible.map<Widget>((playlist) {
      final tracks = controller.tracks
          .where((t) => playlist.trackIds.contains(t.id))
          .take(4)
          .toList();
      final modern = isModern(context);
      Widget? photo(double size, double radius) => playlist.photoPath == null
          ? null
          : PlaylistPhoto(
              path: playlist.photoPath!,
              size: size,
              radius: radius,
            );
      if (brasa) {
        return SizedBox(
          width: 180,
          child: BrasaTile(
            cover:
                photo(156, 6) ??
                (tracks.isEmpty
                    ? const SizedBox.square(
                        dimension: 156,
                        child: Icon(Icons.queue_music, size: 48),
                      )
                    : tracks.length < 4
                    ? Artwork(
                        track: tracks.first,
                        artworkContext: ArtworkContext.card,
                        radius: 6,
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Wrap(
                          children: [
                            for (final t in tracks)
                              Artwork(
                                track: t,
                                artworkContext: ArtworkContext.mosaic,
                                size: 78,
                                radius: 0,
                              ),
                          ],
                        ),
                      )),
            title: playlist.name,
            subtitle: '${playlist.trackIds.length} canciones',
            tooltip: 'Abrir ${playlist.name}',
            icon: Icons.play_arrow_rounded,
            onPlay: () => onOpen(playlist),
          ),
        );
      }
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (playlist.photoPath != null)
            photo(ArtworkContext.cardCompact.size, 12)!
          else if (tracks.isEmpty)
            SizedBox.square(
              dimension: ArtworkContext.cardCompact.size,
              child: const Icon(Icons.queue_music, size: 48),
            )
          else if (tracks.length < 4)
            Artwork(
              track: tracks.first,
              artworkContext: ArtworkContext.cardCompact,
              radius: 12,
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Wrap(
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
            ),
          const SizedBox(height: 12),
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: -.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${playlist.trackIds.length} canciones',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
      if (modern) {
        return SizedBox(
          width: 160,
          child: ModernCard(
            padding: const EdgeInsets.all(12),
            onTap: () => onOpen(playlist),
            child: body,
          ),
        );
      }
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
                  if (playlist.photoPath != null)
                    photo(ArtworkContext.cardCompact.size, 8)!
                  else if (tracks.isEmpty)
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
    for (var i = 0; i < cards.length; i++) {
      cards[i] = PlaylistPhotoMenu(
        controller: controller,
        playlist: visible[i],
        child: cards[i],
      );
    }
    if (horizontal) {
      return HorizontalMusicRow(
        title: 'Tus playlists',
        itemCount: cards.length,
        itemWidth: brasa ? 180 : 160,
        itemHeight: 180 + MediaQuery.textScalerOf(context).scale(108),
        itemBuilder: (_, index) => cards[index],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tus playlists', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _controls(),
        Wrap(spacing: 16, runSpacing: 16, children: cards),
      ],
    );
  }
}
