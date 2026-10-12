import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../artwork.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

/// Native translation of the reference's editorial header and master sleeve.
class StudioHomeIntroduction extends StatelessWidget {
  const StudioHomeIntroduction({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onVinyl,
    this.onSearchQuery,
  });
  final AppController controller;
  final VoidCallback onSearch, onVinyl;
  final ValueChanged<String>? onSearchQuery;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final track =
        c.currentTrack ??
        c.recentTracks.firstOrNull ??
        c.tracks.where((t) => !t.isPendingSpotifyMatch).firstOrNull;
    final now = TimeOfDay.now().format(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            StudioStamp(
              '● CALIBRACIÓN DE SEÑAL · VÁLVULAS CALIENTES',
              color: colors.primary,
            ),
            const StudioStamp('LATENCIA DAC: NO MEDIDA // MOTOR AURORA'),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 20,
          runSpacing: 8,
          children: [
            Text(
              'Madrugada acústica',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontStyle: FontStyle.italic,
                fontSize: MediaQuery.sizeOf(context).width <= 400
                    ? 28
                    : MediaQuery.sizeOf(context).width < 600
                    ? 38
                    : 56,
              ),
            ),
            StudioStamp(now, filled: true, color: colors.primary),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'La resonancia del recinto está optimizada a 432Hz. El flujo analógico simula la atenuación natural de cinta magnética Studer A800.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.tertiary),
        ),
        const SizedBox(height: 4),
        const StudioStamp(
          'TEXTO DE REFERENCIA · SIMULACIÓN ANALÓGICA PENDIENTE',
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _mood(
                context,
                StudioSymbols.waterDrop,
                'Tarde Lluviosa',
                () => showStudioPending(context, 'Ánimos de escucha'),
              ),
              _mood(
                context,
                StudioSymbols.graphicEq,
                'Cinta Magnética',
                () => showStudioPending(context, 'Simulación de cinta'),
              ),
              _mood(context, StudioSymbols.nightlife, 'Improvisación Jazz', () {
                _searchMood('jazz');
              }),
              _mood(
                context,
                StudioSymbols.psychology,
                'Enfoque Profundo',
                () => showStudioPending(context, 'Perfil de enfoque'),
              ),
              _mood(context, StudioSymbols.acUnit, 'Acústica Nórdica', () {
                _searchMood('acústica nórdica');
              }),
            ],
          ),
        ),
        const SizedBox(height: 36),
        if (track != null)
          _master(context, track)
        else
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
                const SizedBox(height: 20),
                Text(
                  'Tu historia empieza aquí',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Busca una canción o abre tus archivos para comenzar.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(StudioSymbols.search),
                  label: const Text('ENCONTRAR MÚSICA'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 40),
        const StudioStamp('CAJA DE DISCOS // ROTACIÓN RECIENTE'),
        const SizedBox(height: 4),
        Text(
          'Crate Digger: Archivos en Rotación',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }

  void _searchMood(String query) {
    if (onSearchQuery != null) {
      onSearchQuery!(query);
    } else {
      onSearch();
      controller.search(query);
    }
  }

  Widget _mood(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(right: 4, bottom: 4),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      onPressed: action,
      icon: Icon(icon, size: 16),
      label: Text(label),
    ),
  );

  Widget _master(BuildContext context, Track track) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final albumTracks = track.album?.trim().isNotEmpty == true
        ? c.tracks
              .where(
                (t) =>
                    t.album == track.album &&
                    t.artist == track.artist &&
                    !t.isPendingSpotifyMatch,
              )
              .toList()
        : [track];
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioStamp(track.artist.toUpperCase(), color: colors.primary),
        const SizedBox(height: 8),
        Text(
          track.album?.trim().isNotEmpty == true ? track.album! : track.title,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        StudioPanel(
          recessed: true,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notas de producción y edición',
                style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  color: colors.tertiary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aurora todavía no dispone de notas de estudio para esta selección.',
              ),
              const SizedBox(height: 16),
              StudioStamp(
                '${albumTracks.length} PISTAS // ${track.isLocal ? 'ARCHIVO LOCAL' : 'FUENTE DE AUDIO EXISTENTE'}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: c.jamPlaybackActive
              ? null
              : () => c.playTrack(track, context: albumTracks),
          icon: const Icon(StudioSymbols.playArrow, size: 18),
          label: Text(
            track.album == null
                ? 'REPRODUCIR SELECCIÓN'
                : 'REPRODUCIR PISTAS DISPONIBLES',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: c.jamPlaybackActive
                  ? null
                  : () async {
                      if (c.currentTrack?.id != track.id) {
                        await c.playTrack(track, context: albumTracks);
                      }
                      if (context.mounted) onVinyl();
                    },
              icon: const Icon(StudioSymbols.album, size: 18),
              label: const Text('Girar en Modo Vinilo'),
            ),
            IconButton.filledTonal(
              tooltip: 'Guardar en favoritos',
              onPressed: () => c.toggleFavorite(track),
              icon: Icon(
                c.favoriteIds.contains(track.id)
                    ? StudioSymbols.favorite
                    : StudioSymbols.bookmarkAdd,
              ),
            ),
          ],
        ),
      ],
    );
    return StudioPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                StudioSymbols.verified,
                color: colors.primaryContainer,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final size = wide
                  ? constraints.maxWidth * .4
                  : constraints.maxWidth.clamp(0.0, 300.0);
              final sleeve = Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      borderRadius: StudioPalette.sleeve,
                      boxShadow: [
                        BoxShadow(color: Colors.black, offset: Offset(4, 6)),
                      ],
                    ),
                    child: Artwork(track: track, size: size, radius: 8),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StudioStamp(
                      track.isLocal
                          ? 'ARCHIVO LOCAL'
                          : 'METADATOS · AUDIO EXTERNO',
                      filled: true,
                    ),
                  ),
                ],
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        sleeve,
                        const SizedBox(width: 24),
                        Expanded(child: info),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(child: sleeve),
                        const SizedBox(height: 28),
                        info,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}
