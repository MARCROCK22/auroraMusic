import 'package:flutter/material.dart';

import '../core/models.dart';
import '../metadata/spotify/spotify_browser_controller.dart';
import '../metadata/spotify/spotify_metadata_provider.dart';
import 'artwork.dart';

/// Metadata navigation only; audio matching belongs to the application.
class SpotifyBrowserPanel extends StatefulWidget {
  const SpotifyBrowserPanel({super.key, this.browser, required this.onQueue});
  final SpotifyBrowserController? browser;
  final Future<void> Function(Track) onQueue;

  @override
  State<SpotifyBrowserPanel> createState() => _SpotifyBrowserPanelState();
}

class _SpotifyBrowserPanelState extends State<SpotifyBrowserPanel> {
  late final _browser = widget.browser ?? SpotifyBrowserController();
  SpotifyMetadataEntity? _selectedEntity;
  void _openDetails(SpotifyMetadataEntity entity) {
    _selectedEntity = entity;
    _browser.openDetails(entity);
  }

  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    if (widget.browser == null) _browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _browser,
    builder: (context, _) => ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (query) => _browser.search(query),
            decoration: InputDecoration(
              labelText: 'Buscar metadatos de Spotify',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar en Spotify',
                onPressed: _browser.loading
                    ? null
                    : () => _browser.search(_query.text),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: SpotifyEntityType.values
                  .map(
                    (type) => ChoiceChip(
                      label: Text(_label(type)),
                      selected: _browser.type == type,
                      onSelected: _browser.loading
                          ? null
                          : (_) => _browser.search(_query.text, type: type),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            'Spotify aporta información. Para añadir a la cola, elige una coincidencia de YouTube.',
          ),
        ),
        if (_browser.loading || _browser.detailLoading)
          const LinearProgressIndicator(minHeight: 2),
        if (_browser.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_browser.error!),
                TextButton.icon(
                  onPressed: () => _browser.search(_query.text),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        if (_browser.detail == null && _browser.detailError != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_browser.detailError!),
                TextButton.icon(
                  onPressed: _selectedEntity == null
                      ? null
                      : () => _openDetails(_selectedEntity!),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar colección'),
                ),
              ],
            ),
          ),
        _browser.detail != null ? _details(context) : _results(context),
      ],
    ),
  );

  String _label(SpotifyEntityType type) => switch (type) {
    SpotifyEntityType.track => 'Canciones',
    SpotifyEntityType.artist => 'Artistas',
    SpotifyEntityType.album => 'Álbumes',
    SpotifyEntityType.playlist => 'Playlists',
  };

  Widget _results(BuildContext context) {
    if (_browser.items.isEmpty) {
      return _empty(
        context,
        _browser.loading
            ? 'Consultando Spotify…'
            : _browser.query.isEmpty
            ? 'Explora canciones, artistas y colecciones'
            : 'Sin resultados',
        'Busca por nombre y elige el tipo de resultado.',
      );
    }
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final item in _browser.items)
          ListTile(
            leading: _cover(item),
            title: Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.track == null
                  ? item.subtitle
                  : _trackDescription(item.track!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: item.track != null
                ? () => widget.onQueue(item.track!)
                : () => _openDetails(item),
            trailing: IconButton(
              tooltip: item.track != null
                  ? 'Elegir audio para ${item.name}'
                  : 'Ver ${item.name}',
              onPressed: item.track != null
                  ? () => widget.onQueue(item.track!)
                  : () => _openDetails(item),
              icon: Icon(
                item.track != null ? Icons.add_to_queue : Icons.chevron_right,
              ),
            ),
          ),
        if (_browser.page?.hasMore == true)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _browser.loading ? null : _browser.loadMore,
              child: const Text('Ver más resultados'),
            ),
          ),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final details = _browser.detail!;
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_browser.detailError != null) ...[
                Text(_browser.detailError!),
                TextButton.icon(
                  onPressed: () => _browser.openDetails(details.entity),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar colección'),
                ),
              ],
              TextButton.icon(
                onPressed: _browser.closeDetails,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver a los resultados'),
              ),
              _cover(details.entity, artworkContext: ArtworkContext.detail),
              const SizedBox(height: 12),
              Text(
                details.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (details.description.isNotEmpty) Text(details.description),
              Text('${details.total} canciones'),
            ],
          ),
        ),
        if (details.tracks.isEmpty && !_browser.loading)
          _empty(
            context,
            'Sin canciones disponibles',
            'Este resultado no incluye canciones consultables.',
          ),
        for (final track in details.tracks)
          ListTile(
            leading: Artwork(
              track: track,
              artworkContext: ArtworkContext.thumbnail,
              radius: 8,
            ),
            title: Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _trackDescription(track),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => widget.onQueue(track),
            trailing: IconButton(
              tooltip: 'Elegir audio para ${track.title}',
              onPressed: () => widget.onQueue(track),
              icon: const Icon(Icons.add_to_queue),
            ),
          ),
        if (details.hasMore)
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton(
              onPressed: _browser.detailLoading
                  ? null
                  : _browser.loadMoreDetails,
              child: const Text('Ver más canciones'),
            ),
          ),
      ],
    );
  }

  Widget _cover(
    SpotifyMetadataEntity item, {
    ArtworkContext artworkContext = ArtworkContext.thumbnail,
  }) => Artwork(
    track: Track(
      id: item.uri,
      title: item.name,
      artist: item.subtitle,
      artworkUrl: item.artworkUrl,
    ),
    artworkContext: artworkContext,
    radius: item.type == SpotifyEntityType.artist ? artworkContext.size : 8,
  );

  String _trackDescription(Track track) => [
    track.artist,
    if (track.album != null) track.album!,
    if (track.duration > Duration.zero)
      '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
    ...track.genres,
  ].where((value) => value.isNotEmpty).join(' · ');

  Widget _empty(BuildContext context, String title, String description) =>
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.manage_search, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
