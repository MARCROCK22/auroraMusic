import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../listenbrainz/lb_stats.dart';
import '../listenbrainz/listenbrainz_service.dart';
import 'studio/studio_components.dart';

/// Perfil con estadísticas de escucha de ListenBrainz. Usa [StudioPanel] y el
/// `ColorScheme`/`TextTheme` del tema activo (Atelier, Brasa o Modern).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  StatsRange _range = StatsRange.month;
  Future<ListenStats>? _future;

  ListenBrainzService? get _lb => widget.controller.listenBrainz;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool force = false}) {
    final lb = _lb;
    _future = lb != null && lb.active ? lb.stats(_range, force: force) : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final lb = _lb;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _Header(controller: c, username: lb?.username),
        const SizedBox(height: 20),
        if (lb == null)
          const _Empty(text: 'ListenBrainz no está disponible en esta versión.')
        else
          ListenableBuilder(
            listenable: lb,
            builder: (context, _) {
              if (!lb.active) {
                if (_future != null) _future = null;
                return _Empty(
                  text: lb.hasToken
                      ? 'ListenBrainz está desactivado. Actívalo para ver tus estadísticas.'
                      : 'Conecta ListenBrainz con tu token para ver tus estadísticas.',
                  action: lb.needsEnable
                      ? FilledButton(
                          key: const ValueKey('profile-enable-lb'),
                          onPressed: () async {
                            await lb.setEnabled(true);
                            setState(_load);
                          },
                          child: const Text('Activar ListenBrainz'),
                        )
                      : null,
                );
              }
              _future ??= lb.stats(_range);
              return _Stats(
                range: _range,
                future: _future!,
                onRange: (r) => setState(() {
                  _range = r;
                  _load();
                }),
                onRefresh: () => setState(() => _load(force: true)),
              );
            },
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, this.username});
  final AppController controller;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = controller.profileName;
    final avatar = controller.profileAvatar;
    return Row(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundImage: avatar == null ? null : MemoryImage(avatar),
          child: avatar == null
              ? Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: t.headlineSmall,
                )
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Tu perfil' : name,
                style: t.headlineMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (username != null)
                Text('ListenBrainz · $username', style: t.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => StudioPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyLarge),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.range,
    required this.future,
    required this.onRange,
    required this.onRefresh,
  });
  final StatsRange range;
  final Future<ListenStats> future;
  final ValueChanged<StatsRange> onRange;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<StatsRange>(
                key: const ValueKey('profile-range'),
                showSelectedIcon: false,
                segments: [
                  for (final r in StatsRange.values)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {range},
                onSelectionChanged: (s) => onRange(s.first),
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ListenStats>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return const _Empty(
                text:
                    'No se pudieron cargar las estadísticas. Inténtalo de nuevo más tarde.',
              );
            }
            return StatsView(stats: snap.data!);
          },
        ),
      ],
    );
  }
}

/// Contenido de las estadísticas (público para pruebas).
class StatsView extends StatelessWidget {
  const StatsView({super.key, required this.stats});
  final ListenStats stats;

  String _hour(int h) => '${h.toString().padLeft(2, '0')}:00 UTC';

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s.recordings.isEmpty && s.artists.isEmpty && s.totalListens == 0) {
      return const _Empty(text: 'Aún no hay escuchas en este rango.');
    }
    final hour = s.favoriteHour;
    final tiles = [
      _Tile(
        'Canción más escuchada',
        s.topTrack?.name ?? 'Sin datos',
        s.topTrack == null
            ? null
            : '${s.topTrack!.subtitle ?? ''} · ${s.topTrack!.count} escuchas',
      ),
      _Tile(
        'Artista más escuchado',
        s.topArtist?.name ?? 'Sin datos',
        s.topArtist == null ? null : '${s.topArtist!.count} escuchas',
      ),
      _Tile(
        'Género principal',
        s.topGenre?.name ?? 'No disponible',
        s.topGenre == null ? 'Sin etiquetas en tus canciones top' : null,
      ),
      _Tile('Total de escuchas', '${s.totalListens}', 'en toda tu cuenta'),
      if (s.streakDays > 0)
        _Tile('Racha', '${s.streakDays} días', 'seguidos con escuchas'),
      if (hour != null) _Tile('Hora favorita', _hour(hour), null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [for (final t in tiles) SizedBox(width: 260, child: t)],
        ),
        if (s.recordings.isNotEmpty) ...[
          const SizedBox(height: 20),
          _TopList('Top canciones', s.recordings),
        ],
        if (s.artists.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopList('Top artistas', s.artists),
        ],
        if (s.releases.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopList('Top álbumes', s.releases),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.detail);
  final String label, value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium),
          const SizedBox(height: 6),
          Text(
            value,
            style: t.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (detail != null)
            Text(
              detail!,
              style: t.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _TopList extends StatelessWidget {
  const _TopList(this.title, this.items);
  final String title;
  final List<StatItem> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleMedium),
          const SizedBox(height: 8),
          for (final (i, item) in items.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 28, child: Text('${i + 1}')),
                  Expanded(
                    child: Text(
                      item.subtitle == null
                          ? item.name
                          : '${item.name} — ${item.subtitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text('${item.count}', style: t.labelMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
