import 'package:flutter/material.dart';

import '../account/account_avatar.dart';
import '../app_controller.dart';
import '../lastfm/lastfm_service.dart';
import '../lastfm/lastfm_stats.dart';
import 'studio/studio_components.dart';

/// Perfil con estadísticas de escucha de Last.fm. Usa [StudioPanel] y el
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

  LastfmService? get _lb => widget.controller.lastfm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load({bool force = false}) {
    final lb = _lb;
    _future = lb != null && lb.connected
        ? lb.stats(_range, force: force)
        : null;
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
          const _Empty(text: 'Last.fm no está disponible en esta versión.')
        else
          ListenableBuilder(
            listenable: lb,
            builder: (context, _) {
              if (!lb.connected) {
                if (_future != null) _future = null;
                return _Empty(
                  text: !lb.configured
                      ? 'Last.fm no está configurado en esta compilación.'
                      : 'Conectar Last.fm: inicia sesión en Ajustes para ver tus estadísticas.',
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
        AccountAvatar(bytes: avatar, radius: 36),
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
                Text('Last.fm · $username', style: t.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => StudioPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Text(text, style: Theme.of(context).textTheme.bodyLarge)],
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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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

  @override
  Widget build(BuildContext context) {
    final s = stats;
    if (s.recordings.isEmpty && s.artists.isEmpty && s.totalListens == 0) {
      return const _Empty(text: 'Aún no hay escuchas en este rango.');
    }
    final tiles = [
      _Tile('Scrobbles', '${s.totalListens}', 'en toda tu cuenta'),
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
        if (s.recent.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopList('Escuchadas hace poco', [
            for (final r in s.recent) StatItem(r.title, 0, subtitle: r.artist),
          ]),
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
                  if (item.count > 0)
                    Text('${item.count}', style: t.labelMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
