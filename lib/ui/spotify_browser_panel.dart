import 'package:flutter/material.dart';

import '../core/models.dart';
import '../jam/jam_models.dart';
import 'jam/jam_widgets.dart';
import '../metadata/spotify/spotify_browser_controller.dart';
import '../metadata/spotify/spotify_metadata_provider.dart';
import 'artwork.dart';
import 'spotify_auto_add.dart';

/// Navegación de metadatos; el emparejado con YouTube es automático (adder).
class SpotifyBrowserPanel extends StatefulWidget {
  const SpotifyBrowserPanel({super.key, this.browser, required this.adder});
  final SpotifyBrowserController? browser;
  final SpotifyAutoAdder adder;

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

  SpotifyAutoAdder get _adder => widget.adder;

  /// Carga las páginas que falten (hasta el tope del lote) y añade todo.
  Future<void> _addAll({required bool toJam}) async {
    final first = _browser.detail;
    if (first == null) return;
    SpotifyMetadataDetails detail = first;
    while (detail.nextOffset != null &&
        detail.tracks.length < SpotifyAutoAdder.maxBatch) {
      await _browser.loadMoreDetails();
      final next = _browser.detail;
      if (next == null || next.tracks.length == detail.tracks.length) break;
      detail = next;
    }
    await _adder.addAll(detail.title, detail.tracks, toJam: toJam);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_browser, _adder]),
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
            'Toca una canción para reproducirla; Aurora encuentra la versión en YouTube y arma la cola con música parecida. Usa + para añadir a la cola.',
          ),
        ),
        if (_adder.batch != null) _batchCard(context, _adder.batch!),
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
              item.track == null ? item.subtitle : _describe(item.track!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: item.track != null
                ? () => _adder.play(item.track!)
                : () => _openDetails(item),
            trailing: item.track != null
                ? _trackActions(item.track!)
                : IconButton(
                    tooltip: 'Ver ${item.name}',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: () => _openDetails(item),
                    icon: const Icon(Icons.chevron_right),
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
              if (details.tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _adder.batch != null
                            ? null
                            : () => _addAll(toJam: false),
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Añadir todo a la cola'),
                      ),
                      if (_adder.jamAvailable)
                        OutlinedButton.icon(
                          onPressed: _adder.batch != null
                              ? null
                              : () => _addAll(toJam: true),
                          icon: const Icon(Icons.group_add_outlined),
                          label: const Text('Añadir todo a la Jam'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (details.tracks.isEmpty && !_browser.loading)
          _empty(
            context,
            'Sin canciones disponibles',
            'Este resultado no incluye canciones consultables.',
          ),
        for (final (i, track) in details.tracks.indexed)
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
              _describe(track),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () =>
                _adder.play(track, context: details.tracks.sublist(i + 1)),
            trailing: _trackActions(track),
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

  Widget _batchCard(BuildContext context, SpotifyBatchProgress b) => Semantics(
    liveRegion: true,
    label: 'Emparejando ${b.done} de ${b.total}',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buscando en YouTube · ${b.done}/${b.total}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: b.total == 0 ? null : b.done / b.total,
                  minHeight: 3,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _adder.cancelBatch,
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );

  /// «+» (cola) y ⋯ (a continuación, Jam, versión a mano). Mientras empareja
  /// muestra progreso; el toque en la fila es el que reproduce.
  Widget _trackActions(Track track) {
    const box = BoxConstraints(minWidth: 48, minHeight: 48);
    final busy = _adder.isBusy(track.id);
    final jam = _adder.jamAvailable;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (busy)
          Semantics(
            liveRegion: true,
            label: 'Buscando versión de ${track.title}',
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else
          IconButton(
            tooltip: 'Añadir a la cola: ${track.title}',
            constraints: box,
            onPressed: () => _adder.add(track),
            icon: const Icon(Icons.add_to_queue),
          ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Más opciones de ${track.title}',
          enabled: !busy,
          onSelected: (run) => run(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: () => _adder.add(track),
              child: const Text('Añadir a la cola'),
            ),
            if (!jam)
              PopupMenuItem(
                value: () => _adder.add(track, next: true),
                child: const Text('Reproducir a continuación'),
              ),
            if (jam)
              PopupMenuItem(
                value: () => _adder.add(track, toJam: true),
                child: const Text('Añadir a la Jam'),
              ),
            if (jam && _adder.jam?.call()?.isStaff == true)
              PopupMenuItem(
                value: () =>
                    _adder.add(track, toJam: true, jamMode: JamAddMode.playNow),
                child: const Text('Reproducir ahora en la Jam'),
              ),
            PopupMenuItem(
              value: () => _adder.manual(track),
              child: const Text('Elegir versión a mano…'),
            ),
          ],
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

  String _describe(Track track) => _adder.isBusy(track.id)
      ? 'Buscando versión… · ${_trackDescription(track)}'
      : _trackDescription(track);

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
