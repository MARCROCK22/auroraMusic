import 'package:flutter/material.dart';
import '../app_controller.dart';
import 'artwork.dart';
import 'track_actions.dart';
import 'dj_filters_panel.dart';

class DjPanel extends StatelessWidget {
  const DjPanel({
    super.key,
    required this.controller,
    this.showRecommendations = true,
  });
  final bool showRecommendations;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final recommendations = c.recommendations;
    final filters = c.djFilters;
    final filtered =
        filters.artists.isNotEmpty ||
        filters.trackIds.isNotEmpty ||
        filters.genres.isNotEmpty ||
        filters.excludedArtists.isNotEmpty ||
        filters.excludedTrackIds.isNotEmpty ||
        filters.excludedGenres.isNotEmpty;
    final libraryIds = c.tracks.map((track) => track.id).toSet();
    final personalized =
        c.favoriteIds.any(libraryIds.contains) ||
        c.playlists.any(
          (playlist) => playlist.trackIds.any(libraryIds.contains),
        ) ||
        c.recentTracks.isNotEmpty;
    final contextTracks = recommendations
        .map((recommendation) => recommendation.track)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRecommendations)
          _sectionTitle(
            context,
            'Para ti',
            personalized
                ? 'Basado en tus favoritos, listas y escucha reciente'
                : 'Aún no hay señales personales; elegimos de tu biblioteca',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: c.refreshRecommendations,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar recomendaciones'),
            ),
          ],
        ),
        DjFiltersPanel(controller: c),

        if (showRecommendations && recommendations.isEmpty)
          _empty(
            context,
            Icons.auto_awesome_outlined,
            filtered
                ? 'No hay canciones para estos filtros'
                : 'Tu biblioteca está lista para crecer',
            filtered
                ? 'Amplía tu selección o quita los filtros del DJ para encontrar más canciones.'
                : 'Añade canciones reproducibles y aparecerán recomendaciones aquí.',
          )
        else if (showRecommendations)
          ...recommendations.map(
            (recommendation) => TrackActionsRegion(
              controller: c,
              track: recommendation.track,
              builder: (context, hot) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Artwork(
                  track: recommendation.track,
                  artworkContext: ArtworkContext.thumbnail,
                  radius: 8,
                ),
                title: Text(
                  recommendation.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${recommendation.track.artist} · ${recommendation.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    c.playTrack(recommendation.track, context: contextTracks),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reproducir ${recommendation.track.title}',
                      onPressed: () => c.playTrack(
                        recommendation.track,
                        context: contextTracks,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    TrackMenuButton(
                      controller: c,
                      track: recommendation.track,
                      quickAdd: true,
                      quickAddVisible: hot,
                    ),
                  ],
                ),
              ),
            ),
          ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: const Text('Incluir novedades de YouTube'),
          subtitle: const Text(
            'Hasta 2 búsquedas por recarga, guiadas por tu perfil.',
          ),
          value: c.personalDjIncludeDiscovery,
          onChanged: c.setPersonalDjIncludeDiscovery,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: c.personalDjActive
                ? c.stopPersonalDj
                : c.canStartPersonalDj
                ? () => c.startPersonalDj(
                    includeDiscovery: c.personalDjIncludeDiscovery,
                  )
                : null,
            icon: Icon(
              c.personalDjActive
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle,
            ),
            label: Text(
              c.personalDjActive
                  ? 'Detener DJ personal · sin voz'
                  : 'Iniciar DJ personal · sin voz',
            ),
          ),
        ),
        if (c.personalDjActive)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 8),
            child: Text(
              c.personalDjNextReason == null
                  ? 'El tema actual seguirá hasta terminar.'
                  : 'A continuación: ${c.personalDjNextReason}',
            ),
          ),
        if (c.personalDjError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'El DJ seguirá con tu biblioteca: ${c.personalDjError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                c.discoveringRecommendations || !c.canDiscoverRecommendations
                ? null
                : c.discoverRecommendations,
            icon: c.discoveringRecommendations
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
            label: Text(
              c.discoveringRecommendations
                  ? 'Buscando en YouTube…'
                  : c.discoveredRecommendations.isEmpty
                  ? 'Descubrir en YouTube'
                  : 'Actualizar descubrimiento',
            ),
          ),
        ),
        if (c.recommendationDiscoveryError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No se pudo buscar: ${c.recommendationDiscoveryError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (showRecommendations && c.discoveredRecommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle(
            context,
            'Encontradas en YouTube',
            'Búsqueda solicitada por ti',
          ),
          ...c.discoveredRecommendations.map(
            (track) => TrackActionsRegion(
              controller: c,
              track: track,
              builder: (context, hot) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Artwork(
                  track: track,
                  artworkContext: ArtworkContext.thumbnail,
                  radius: 8,
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} · Resultado de YouTube',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    c.playTrack(track, context: c.discoveredRecommendations),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reproducir ${track.title}',
                      onPressed: () => c.playTrack(
                        track,
                        context: c.discoveredRecommendations,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    TrackMenuButton(
                      controller: c,
                      track: track,
                      quickAdd: true,
                      quickAddVisible: hot,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  Widget _empty(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
