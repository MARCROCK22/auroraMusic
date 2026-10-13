import 'package:flutter/material.dart';

import '../core/models.dart';
import 'artwork.dart';
import 'studio/studio_components.dart';

/// Browse the artists represented by the tracks supplied by the caller.
class ArtistsPage extends StatefulWidget {
  const ArtistsPage({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onSearch,
  });

  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  final ValueChanged<String> onSearch;

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  _Artist? _selectedArtist;

  List<_Artist> _artists() {
    final groups = <String, List<Track>>{};
    for (final track in widget.tracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      (groups[name.toLowerCase()] ??= []).add(track);
    }
    final artists = groups.values.map(_Artist.new).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return artists;
  }

  @override
  Widget build(BuildContext context) {
    final artists = _artists();
    final selected = _selectedArtist;
    if (selected != null) {
      final current = artists
          .where((artist) => artist.key == selected.key)
          .firstOrNull;
      if (current == null) _selectedArtist = null;
      return current == null ? _artistList(artists) : _artistDetail(current);
    }
    return _artistList(artists);
  }

  Widget _artistList(List<_Artist> artists) {
    if (artists.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Artistas', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Todavía no hay artistas',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Busca música para encontrar artistas y añadir canciones a tu biblioteca.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => widget.onSearch(''),
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar música'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Artistas', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '${artists.length} ${artists.length == 1 ? 'artista' : 'artistas'} en tu biblioteca',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final artist in artists) ...[
          _ArtistTile(
            artist: artist,
            onTap: () => setState(() => _selectedArtist = artist),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _artistDetail(_Artist artist) {
    final cover =
        artist.tracks
            .where((track) => track.artworkUrl?.isNotEmpty == true)
            .firstOrNull ??
        artist.tracks.first;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _selectedArtist = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Todos los artistas'),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Artwork(track: cover, size: 176, radius: 88)),
        const SizedBox(height: 16),
        Text(
          artist.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          '${artist.tracks.length} ${artist.tracks.length == 1 ? 'canción' : 'canciones'}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        for (final track in artist.tracks)
          _TrackTile(track: track, onPlay: () => widget.onPlay(track)),
      ],
    );
  }
}

class _Artist {
  _Artist(this.tracks);

  final List<Track> tracks;
  String get name => tracks.first.artist.trim();
  String get key => name.toLowerCase();
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist, required this.onTap});

  final _Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover =
        artist.tracks
            .where((track) => track.artworkUrl?.isNotEmpty == true)
            .firstOrNull ??
        artist.tracks.first;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: StudioPalette.sleeve,
      child: InkWell(
        onTap: onTap,
        borderRadius: StudioPalette.sleeve,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Artwork(track: cover, size: 64, radius: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${artist.tracks.length} ${artist.tracks.length == 1 ? 'canción' : 'canciones'}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track, required this.onPlay});

  final Track track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: Artwork(track: track, size: 48, radius: 4),
    title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        if (track.album?.trim().isNotEmpty == true) track.album!.trim(),
        _duration(track.duration),
      ].join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: IconButton(
      tooltip: 'Reproducir ${track.title}',
      onPressed: onPlay,
      icon: const Icon(Icons.play_arrow_rounded),
    ),
    onTap: onPlay,
  );

  String _duration(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
