import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/discovery_controller.dart';
import '../../dj/recommendations.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../dj_filters_panel.dart';
import '../dj_panel.dart';

const _ink = Slush.ink;

/// Verde saturado con el tono del fondo pastel (que deriva de la portada).
Color _screenGreen(BuildContext context) {
  final h = HSLColor.fromColor(Theme.of(context).scaffoldBackgroundColor);
  return HSLColor.fromAHSL(1, h.hue, .68, .66).toColor();
}

/// Pantalla «DJ AUROR» del tema Slush. La lógica vive en [discovery]; [wrap]
/// añade el gesto de deslizar a la tarjeta principal.
class SlushDj extends StatelessWidget {
  const SlushDj({
    super.key,
    required this.controller,
    required this.discovery,
    required this.onSearch,
    required this.wrap,
  });
  final AppController controller;
  final DjDiscoveryController discovery;
  final VoidCallback onSearch;
  final Widget Function(Track track, Widget child) wrap;

  @override
  Widget build(BuildContext context) {
    final rec = discovery.current;
    final errors = [?discovery.error, ?controller.recommendationDiscoveryError];
    return ColoredBox(
      color: _screenGreen(context),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final stack = rec == null
              ? _empty(context)
              : wrap(rec.track, _Stack(track: rec.track, reason: rec.reason));
          final skip = _RoundAction(
            key: const ValueKey('dj-discovery-skip'),
            color: Slush.orange,
            icon: Icons.close,
            label: 'OMITIR',
            onTap: rec == null || discovery.busy
                ? null
                : () => discovery.skip(rec.track),
          );
          final save = _RoundAction(
            key: const ValueKey('dj-discovery-add'),
            color: _ink,
            icon: Icons.favorite,
            label: discovery.busy ? 'GUARDANDO…' : 'GUARDAR',
            onTap: rec == null || discovery.busy
                ? null
                : () => discovery.accept(rec.track),
          );
          final counters = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ESTA SESIÓN',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              _Counter(discovery.added, 'guardadas'),
              const SizedBox(height: 6),
              _Counter(discovery.skipped, 'omitidas'),
            ],
          );
          final filters = _SlushFilters(
            controller: controller,
            onSearch: onSearch,
          );
          final body = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 150, child: counters),
                    skip,
                    const SizedBox(width: 12),
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: stack,
                      ),
                    ),
                    const SizedBox(width: 12),
                    save,
                    const SizedBox(width: 24),
                    SizedBox(width: 300, child: filters),
                  ],
                )
              : Column(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: stack,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 32,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [skip, save, counters],
                    ),
                    const SizedBox(height: 20),
                    filters,
                  ],
                );
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              FittedBox(
                fit: BoxFit.fitWidth,
                child: Text(
                  'AUROR',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontSize: 260,
                    height: .95,
                    letterSpacing: -6,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DjSessionCard(controller: controller),
              for (final e in errors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(e)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              body,
            ],
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: _cardDeco(Colors.white),
    child: Column(
      children: [
        Text(
          'No quedan canciones para esta selección',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Prueba otros filtros, busca novedades o añade canciones a tu biblioteca.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

BoxDecoration _cardDeco(Color color, [double r = 28]) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(r),
  border: Border.all(color: _ink, width: 2.5),
);

class _Stack extends StatelessWidget {
  const _Stack({required this.track, required this.reason});
  final Track track;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (track.album?.trim().isNotEmpty ?? false) track.album!,
      ...track.genres,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 28, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.rotate(
              angle: .1,
              child: DecoratedBox(decoration: _cardDeco(Slush.violet)),
            ),
          ),
          Positioned.fill(
            child: Transform.rotate(
              angle: .05,
              child: DecoratedBox(decoration: _cardDeco(Slush.yellow)),
            ),
          ),
          Container(
            key: const ValueKey('dj-discovery-card'),
            padding: const EdgeInsets.all(14),
            decoration: _cardDeco(Colors.white),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: _cardDeco(Slush.lilac, 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Artwork.fill(
                        track: track,
                        artworkContext: ArtworkContext.playerCompact,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  track.artist,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (track.duration > Duration.zero || meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        if (meta.isNotEmpty) meta,
                        if (track.duration > Duration.zero)
                          '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 10),
                _ReasonPill(reason),
              ],
            ),
          ),
          Positioned(
            top: -26,
            left: 36,
            child: Transform.rotate(
              angle: -.1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _ink, width: 2.5),
                  boxShadow: Slush.hardShadow,
                ),
                child: Text(
                  'DJ AUROR',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
              ),
            ),
          ),
          Positioned(
            top: -34,
            right: -10,
            child: Transform.rotate(
              angle: .25,
              child: const Stack(
                alignment: Alignment.center,
                children: [
                  Icon(Icons.bolt, size: 64, color: _ink),
                  Icon(Icons.bolt, size: 52, color: Slush.violet),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasonPill extends StatelessWidget {
  const _ReasonPill(this.reason);
  final String reason;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      color: Slush.lilac,
      shape: StadiumBorder(side: BorderSide(color: _ink, width: 2)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Text(
        reason.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ),
  );
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .5 : 1,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: _ink, width: 2.5),
                boxShadow: Slush.hardShadow,
              ),
              child: Icon(icon, size: 34, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SlushPill(label, color: Colors.white),
      ],
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const ShapeDecoration(
      color: Colors.white,
      shape: StadiumBorder(side: BorderSide(color: _ink, width: 2)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

/// Tarjeta «Filtros»: solo controles que existen en el DJ.
class _SlushFilters extends StatelessWidget {
  const _SlushFilters({required this.controller, required this.onSearch});
  final AppController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = c.djFilters;
    Future<void> set(DjFilters n) => c.setDjFilters(n);
    DjFilters copy({
      List<String>? excludedArtists,
      List<String>? excludedGenres,
      List<String>? excludedTrackIds,
    }) => DjFilters(
      artists: f.artists,
      trackIds: f.trackIds,
      genres: f.genres,
      excludedArtists: excludedArtists ?? f.excludedArtists,
      excludedTrackIds: excludedTrackIds ?? f.excludedTrackIds,
      excludedGenres: excludedGenres ?? f.excludedGenres,
    );
    final titles = {for (final t in c.tracks) t.id: t.title};
    final blocked = <(String, VoidCallback)>[
      for (final a in f.excludedArtists)
        (
          a,
          () => set(copy(excludedArtists: [...f.excludedArtists]..remove(a))),
        ),
      for (final g in f.excludedGenres)
        (g, () => set(copy(excludedGenres: [...f.excludedGenres]..remove(g)))),
      for (final id in f.excludedTrackIds)
        (
          titles[id] ?? id,
          () =>
              set(copy(excludedTrackIds: [...f.excludedTrackIds]..remove(id))),
        ),
    ];
    final artists =
        c.tracks
            .map((t) => t.artist)
            .where((a) => a.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final yt = c.personalDjIncludeDiscovery;
    final busy = c.discoveringRecommendations;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco(
        Colors.white,
        24,
      ).copyWith(boxShadow: Slush.hardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtros', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Switch(
                value: yt,
                onChanged: c.setPersonalDjIncludeDiscovery,
                trackColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? Slush.yellow
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Novedades de YouTube',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Bloqueados',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (blocked.isEmpty)
                const Text('Nada bloqueado.', style: TextStyle(fontSize: 12)),
              for (final b in blocked)
                InputChip(
                  label: Text(b.$1, style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: b.$2,
                  backgroundColor: Slush.lilac,
                  visualDensity: VisualDensity.compact,
                ),
              ActionChip(
                label: const Text('Bloquear artista'),
                avatar: const Icon(Icons.add, size: 14),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final sel = await DjFiltersPanel.choose(
                    context,
                    'Artistas bloqueados',
                    {for (final a in artists) a: a},
                    f.excludedArtists,
                  );
                  if (sel != null) await set(copy(excludedArtists: sel));
                },
              ),
              if (f.artists.length + f.trackIds.length + f.genres.length > 0 ||
                  blocked.isNotEmpty)
                ActionChip(
                  label: const Text('Quitar filtros'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => set(const DjFilters()),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Perfil local: ${c.tracks.length} canciones en tu biblioteca. '
            '${yt ? 'Con' : 'Sin'} recomendaciones de YouTube.',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || !c.canDiscoverRecommendations
                    ? null
                    : c.refreshRecommendations,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(busy ? 'BUSCANDO…' : 'ACTUALIZAR'),
              ),
              TextButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar música'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
