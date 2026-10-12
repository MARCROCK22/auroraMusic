import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'artwork.dart';
import 'studio/home_introduction.dart';
import 'dj_panel.dart';
import 'horizontal_music_row.dart';
import 'playlist_shelf.dart';
import 'spotify_match_dialog.dart';

class HomeMusicPage extends StatelessWidget {
  const HomeMusicPage({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onDownloads,
    required this.onLikes,
    required this.onOpenPlaylist,
    this.onVinyl,
  });
  final AppController controller;
  final VoidCallback onSearch, onDownloads, onLikes;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final VoidCallback? onVinyl;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final recommendations = c.recommendations;
      final recommendedTracks = recommendations.map((r) => r.track).toList();
      final libraryIds = c.tracks.map((t) => t.id).toSet();
      final personalized =
          c.favoriteIds.any(libraryIds.contains) ||
          c.playlists.any((p) => p.trackIds.any(libraryIds.contains)) ||
          c.recentTracks.isNotEmpty;
      final text = MediaQuery.textScalerOf(context);
      final artists = <String, List<Track>>{};
      final albums = <(String, String), List<Track>>{};
      for (final track in c.tracks) {
        final artist = track.artist.trim();
        if (artist.isEmpty) continue;
        (artists[artist.toLowerCase()] ??= []).add(track);
        final album = track.album?.trim();
        if (album != null && album.isNotEmpty) {
          (albums[(artist.toLowerCase(), album.toLowerCase())] ??= []).add(
            track,
          );
        }
      }
      final artistGroups = artists.values.toList();
      final albumGroups = albums.values.toList();
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          StudioHomeIntroduction(
            controller: c,
            onSearch: onSearch,
            onVinyl: onVinyl ?? onSearch,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Descargas locales'),
                onPressed: onDownloads,
              ),
              ActionChip(
                avatar: const Icon(Icons.favorite_border, size: 18),
                label: const Text('Favoritos'),
                onPressed: onLikes,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (c.recentTracks.isNotEmpty)
            HorizontalMusicRow(
              key: const ValueKey('home-recent'),
              title: 'Tu música',
              subtitle: 'Reanudá tu escucha',
              itemCount: c.recentTracks.length,
              itemHeight: 220 + text.scale(72),
              itemBuilder: (context, index) => _TrackCard(
                track: c.recentTracks[index],
                actionLabel: 'Reanudar',
                onPlay: () =>
                    _play(context, c.recentTracks[index], c.recentTracks),
              ),
            ),
          const SizedBox(height: 28),
          if (recommendations.isNotEmpty)
            HorizontalMusicRow(
              key: const ValueKey('home-recommendations'),
              title: 'Para ti',
              subtitle: personalized
                  ? 'Basado en tus favoritos, listas y escucha reciente'
                  : 'Aún no hay señales personales; elegimos de tu biblioteca',
              itemCount: recommendations.length,
              itemHeight: 228 + text.scale(136),
              itemBuilder: (context, index) => _TrackCard(
                track: recommendations[index].track,
                reason: recommendations[index].reason,
                actionLabel: 'Reproducir',
                onPlay: () => _play(
                  context,
                  recommendations[index].track,
                  recommendedTracks,
                ),
              ),
            )
          else ...[
            Text('Para ti', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              c.tracks.isEmpty
                  ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                  : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
            ),
          ],
          const SizedBox(height: 16),
          DjPanel(controller: c, showRecommendations: false),
          if (c.discoveredRecommendations.isNotEmpty) ...[
            const SizedBox(height: 24),
            HorizontalMusicRow(
              title: 'Encontradas en YouTube',
              subtitle: 'Búsqueda solicitada por ti',
              itemCount: c.discoveredRecommendations.length,
              itemHeight: 220 + text.scale(72),
              itemBuilder: (context, index) => _TrackCard(
                track: c.discoveredRecommendations[index],
                actionLabel: 'Reproducir',
                onPlay: () => _play(
                  context,
                  c.discoveredRecommendations[index],
                  c.discoveredRecommendations,
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          if (c.playlists.isNotEmpty) ...[
            PlaylistShelf(
              controller: c,
              horizontal: true,
              onOpen: onOpenPlaylist,
            ),
            const SizedBox(height: 28),
          ],
          if (artistGroups.length > 1) ...[
            HorizontalMusicRow(
              key: const ValueKey('home-artists'),
              title: 'Tus artistas',
              itemCount: artistGroups.length,
              itemHeight: 228 + text.scale(120),
              itemBuilder: (context, index) {
                final tracks = artistGroups[index];
                final artist = tracks.first.artist.trim();
                return _GroupCard(
                  title: artist,
                  tracks: tracks,
                  artist: true,
                  tooltip: 'Escuchar artista $artist',
                  onPlay: () => _play(context, tracks.first, tracks),
                );
              },
            ),
            const SizedBox(height: 28),
          ],
          if (albumGroups.length > 1) ...[
            HorizontalMusicRow(
              key: const ValueKey('home-albums'),
              title: 'Álbumes de tu biblioteca',
              itemCount: albumGroups.length,
              itemHeight: 228 + text.scale(136),
              itemBuilder: (context, index) {
                final tracks = albumGroups[index];
                final album = tracks.first.album!.trim();
                final artist = tracks.first.artist.trim();
                return _GroupCard(
                  title: album,
                  subtitle: artist,
                  tracks: tracks,
                  tooltip: 'Escuchar álbum $album de $artist',
                  onPlay: () => _play(context, tracks.first, tracks),
                );
              },
            ),
            const SizedBox(height: 28),
          ],
          if (c.tracks.isNotEmpty)
            HorizontalMusicRow(
              key: const ValueKey('home-library'),
              title: 'Tu colección',
              subtitle:
                  '${c.tracks.length} canciones · ${c.playlists.length} listas',
              itemCount: c.tracks.length,
              itemHeight: 220 + text.scale(72),
              itemBuilder: (context, index) => _TrackCard(
                track: c.tracks[index],
                actionLabel: 'Escuchar',
                onPlay: () => _play(context, c.tracks[index], c.tracks),
              ),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: c.importFiles,
                icon: const Icon(Icons.add),
                label: const Text('Añadir música a tu biblioteca'),
              ),
            ),
        ],
      );
    },
  );

  Future<void> _play(BuildContext context, Track track, List<Track> tracks) =>
      track.isPendingSpotifyMatch
      ? SpotifyMatchDialog.show(
          context,
          track: track,
          onSearch: () => controller.findSpotifyMatches(track),
          onSave: (match, {required play}) =>
              controller.matchSpotifyTrack(track.id, match, play: play),
        )
      : controller.playTrack(track, context: tracks);
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.tracks,
    required this.tooltip,
    required this.onPlay,
    this.subtitle,
    this.artist = false,
  });
  final String title, tooltip;
  final String? subtitle;
  final List<Track> tracks;
  final VoidCallback onPlay;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    final cover =
        tracks
            .where((track) => track.artworkUrl?.isNotEmpty == true)
            .firstOrNull ??
        tracks.first;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Artwork(track: cover, size: 176, radius: artist ? 88 : 8),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filled(
                      tooltip: tooltip,
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.track,
    required this.actionLabel,
    required this.onPlay,
    this.reason,
  });
  final Track track;
  final String actionLabel;
  final VoidCallback onPlay;
  final String? reason;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(track: track, size: 176, radius: 8),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: IconButton.filled(
                    tooltip: track.isPendingSpotifyMatch
                        ? 'Elegir audio para ${track.title}'
                        : '$actionLabel ${track.title}',
                    onPressed: onPlay,
                    icon: Icon(
                      track.isPendingSpotifyMatch
                          ? Icons.link
                          : Icons.play_arrow,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (reason != null) ...[
              const SizedBox(height: 8),
              Text(
                reason!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
