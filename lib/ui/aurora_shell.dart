import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/audio_backend.dart';
import '../core/models.dart';

const _sections = ['Inicio', 'Buscar', 'Biblioteca', 'Descargas', 'Ajustes'];
const _icons = [
  Icons.home_outlined,
  Icons.search,
  Icons.library_music_outlined,
  Icons.download_outlined,
  Icons.tune,
];

class AuroraShell extends ConsumerStatefulWidget {
  const AuroraShell({super.key});
  @override
  ConsumerState<AuroraShell> createState() => _AuroraShellState();
}

class _AuroraShellState extends ConsumerState<AuroraShell>
    with WidgetsBindingObserver {
  int _section = 0;
  int _libraryTab = 0;
  MusicPlaylist? _playlist;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _submittedQuery = '';
  late final AudioBackend _audio;
  bool _playerOpen = false;
  bool _foreground = true;
  bool _analysisEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(controllerProvider).audio;
    _audio.setVisualizationEnabled(false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisualization();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncVisualization();
  }

  void _syncVisualization() {
    final c = ref.read(controllerProvider);
    final enabled =
        _playerOpen &&
        _foreground &&
        c.audio.isPlaying &&
        !c.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled != _analysisEnabled) {
      _analysisEnabled = enabled;
      _audio.setVisualizationEnabled(enabled);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_analysisEnabled) _audio.setVisualizationEnabled(false);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _navigate(int value) => setState(() {
    _section = value;
    _playlist = null;
  });

  void _submitSearch(AppController c, String query) {
    if (c.searching) return;
    setState(() => _submittedQuery = query.trim());
    c.search(query);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    ref.listen(
      controllerProvider.select((c) => (c.reducedMotion, c.audio.isPlaying)),
      (_, _) => _syncVisualization(),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _navigate(1);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _searchFocus.requestFocus(),
          );
        },
        const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
            c.togglePlayback,
        const SingleActivator(LogicalKeyboardKey.mediaTrackNext): c.next,
        const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
            c.previous,
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, size) {
            final wide = size.maxWidth >= 900;
            final rail = size.maxWidth >= 600;
            return Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          if (rail) _sidebar(c, wide),
                          Expanded(
                            child: Column(
                              children: [
                                _header(c, rail),
                                if (!c.ready || c.busy)
                                  const LinearProgressIndicator(minHeight: 2),
                                if (c.error != null) _errorBanner(c),
                                Expanded(child: _content(c)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.currentTrack != null) _miniPlayer(c, wide),
                  ],
                ),
              ),
              bottomNavigationBar: rail
                  ? null
                  : NavigationBar(
                      selectedIndex: _section,
                      onDestinationSelected: _navigate,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      destinations: List.generate(
                        5,
                        (i) => NavigationDestination(
                          icon: Icon(_icons[i]),
                          label: _sections[i],
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _sidebar(AppController c, bool wide) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: wide ? 220 : 84,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colors.outlineVariant.withValues(alpha: .35),
          ),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.graphic_eq, color: colors.primary, size: 30),
                if (wide) ...[
                  const SizedBox(width: 10),
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'aurora',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (int i = 0; i < _sections.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: Tooltip(
                message: _sections[i],
                child: Material(
                  color: _section == i
                      ? colors.primary.withValues(alpha: .12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _navigate(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: wide
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          Icon(
                            _icons[i],
                            color: _section == i
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                          if (wide) ...[
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _sections[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: _section == i
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (wide) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: Divider(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TUS LISTAS',
                      style: TextStyle(fontSize: 11, letterSpacing: 1.7),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Crear lista',
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _createPlaylist(c),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: c.playlists.length,
                itemBuilder: (_, i) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 26),
                  leading: const Icon(Icons.queue_music, size: 20),
                  title: Text(
                    c.playlists[i].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => setState(() {
                    _section = 2;
                    _playlist = c.playlists[i];
                  }),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(26),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt_outlined, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tu música. Tu espacio.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(AppController c, bool rail) => Padding(
    padding: EdgeInsets.fromLTRB(rail ? 32 : 20, 18, rail ? 32 : 20, 12),
    child: Row(
      children: [
        if (!rail) ...[
          Icon(Icons.graphic_eq, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            (_playlist == null
                    ? null
                    : c.playlists
                          .where((p) => p.id == _playlist!.id)
                          .firstOrNull
                          ?.name) ??
                _sections[_section],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'Importar archivos de audio',
          onPressed: c.ready ? c.importFiles : null,
          icon: const Icon(Icons.create_new_folder_outlined),
        ),
        if (_section != 1)
          IconButton(
            tooltip: 'Buscar música · Ctrl+K',
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.search),
          ),
      ],
    ),
  );

  Widget _errorBanner(AppController c) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cerrar aviso',
            onPressed: c.clearError,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    ),
  );

  Widget _content(AppController c) {
    switch (_section) {
      case 1:
        return _searchPage(c);
      case 2:
        return _library(c);
      case 3:
        return _downloads(c);
      case 4:
        return _settings(c);
      default:
        return _home(c);
    }
  }

  Widget _home(AppController c) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(24),
        ),
        child: LayoutBuilder(
          builder: (context, box) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'HECHO PARA ESCUCHAR',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'La música cambia.\nTu espacio también.',
                style: TextStyle(
                  fontSize: box.maxWidth < 400 ? 30 : 42,
                  height: 1.1,
                  letterSpacing: -1.3,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Un reproductor que toma el color de lo que escuchas.\nTus archivos y tus descubrimientos, en un mismo lugar.',
                style: TextStyle(height: 1.6),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => _navigate(1),
                    icon: const Icon(Icons.search),
                    label: const Text('Encontrar música'),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.ready ? c.importFiles : null,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Abrir archivos'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 32),
      _sectionTitle('Vuelve a escuchar', 'Tu historial reciente'),
      const SizedBox(height: 16),
      if (c.recentTracks.isEmpty)
        _empty(
          Icons.history,
          'Tu historia empieza aquí',
          'Busca una canción o abre tus archivos para comenzar.',
        )
      else
        SizedBox(
          height: 204 + MediaQuery.textScalerOf(context).scale(44),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: c.recentTracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, i) =>
                SizedBox(width: 164, child: _albumCard(c, c.recentTracks[i])),
          ),
        ),
      const SizedBox(height: 28),
      _sectionTitle(
        'Tu colección',
        '${c.tracks.length} canciones · ${c.playlists.length} listas',
      ),
      const SizedBox(height: 12),
      if (c.tracks.isNotEmpty)
        ...c.tracks.take(5).map((t) => _trackTile(c, t, c.tracks))
      else
        OutlinedButton.icon(
          onPressed: c.importFiles,
          icon: const Icon(Icons.add),
          label: const Text('Añadir música a tu biblioteca'),
        ),
    ],
  );

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _albumCard(AppController c, Track t) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => c.playTrack(t),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Artwork(track: t, size: 164, radius: 16),
        const SizedBox(height: 12),
        Text(
          t.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          t.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  Widget _searchPage(AppController c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Canción, artista o enlace',
            helperText: 'Pulsa Enter o la flecha para buscar',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.arrow_forward),
              onPressed: c.searching ? null : () => _submitSearch(c, _search.text),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onSubmitted: (query) => _submitSearch(c, query),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (c.searching) const LinearProgressIndicator(minHeight: 2),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _importPlaylist(c),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Importar una lista por enlace'),
          ),
        ),
      ),
      Expanded(
        child: c.searchResults.isEmpty
            ? _empty(
                Icons.travel_explore,
                c.searching
                    ? 'Buscando tu próxima canción…'
                    : _submittedQuery.isNotEmpty && _submittedQuery == _search.text.trim()
                    ? 'Sin resultados'
                    : 'Encuentra algo que te mueva',
                c.searching
                    ? 'La búsqueda puede tardar unos segundos.'
                    : _submittedQuery.isNotEmpty && _submittedQuery == _search.text.trim()
                    ? 'Prueba con otro título o artista, o pega un enlace directo.'
                    : 'Escribe un título, artista o pega un enlace compatible.',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount:
                    c.searchResults.length + (c.hasMoreSearchResults ? 1 : 0),
                itemBuilder: (_, i) => i == c.searchResults.length
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton.icon(
                          onPressed: c.searching ? null : c.loadMoreSearch,
                          icon: const Icon(Icons.expand_more),
                          label: Text(
                            c.searching ? 'Buscando…' : 'Ver más resultados',
                          ),
                        ),
                      )
                    : _trackTile(c, c.searchResults[i], c.searchResults),
              ),
      ),
    ],
  );

  Widget _library(AppController c) {
    if (_playlist != null) {
      final p = c.playlists.where((p) => p.id == _playlist!.id).firstOrNull;
      if (p == null) {
        return _empty(
          Icons.queue_music,
          'Esta lista ya no existe',
          'Selecciona otra lista de tu biblioteca.',
        );
      }
      final items = p.trackIds
          .map((id) => c.tracks.where((t) => t.id == id).firstOrNull)
          .whereType<Track>()
          .toList();
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _playlist = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Todas las listas'),
                ),
                FilledButton.icon(
                  onPressed: items.isEmpty
                      ? null
                      : () => c.playTrack(items.first, context: items),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Reproducir'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final name = await _askText(
                      'Renombrar lista',
                      'Nombre',
                      initial: p.name,
                    );
                    if (name != null) c.renamePlaylist(p, name);
                  },
                  child: const Text('Renombrar'),
                ),
                TextButton(
                  onPressed: () async {
                    if (await _confirm(
                      'Eliminar lista',
                      'Se eliminará «${p.name}». Tus archivos permanecerán en la biblioteca.',
                    )) {
                      c.deletePlaylist(p);
                      setState(() => _playlist = null);
                    }
                  },
                  child: const Text('Eliminar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? _empty(
                    Icons.playlist_add,
                    'Esta lista está esperando música',
                    'Añade canciones desde el menú de cualquier resultado o canción.',
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) =>
                        c.reorderPlaylist(p, oldIndex, newIndex),
                    itemBuilder: (_, i) => _trackTile(
                      c,
                      items[i],
                      items,
                      key: ValueKey('${p.id}-${items[i].id}'),
                      playlist: p,
                    ),
                  ),
          ),
        ],
      );
    }
    final items = switch (_libraryTab) {
      1 => c.tracks.where((t) => c.favoriteIds.contains(t.id)).toList(),
      3 => c.recentTracks,
      _ => c.tracks,
    };
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (final entry in [
                'Canciones',
                'Favoritos',
                'Listas',
                'Historial',
              ].asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _libraryTab == entry.key,
                    onSelected: (_) => setState(() => _libraryTab = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _libraryTab == 2
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: () => _createPlaylist(c),
                        icon: const Icon(Icons.add),
                        label: const Text('Crear lista'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (c.playlists.isEmpty)
                      _empty(
                        Icons.queue_music,
                        'Una lista para cada momento',
                        'Crea una lista y reúne tus canciones favoritas.',
                      ),
                    ...c.playlists.map(
                      (p) => ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(p.name),
                        subtitle: Text('${p.trackIds.length} canciones'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => setState(() => _playlist = p),
                      ),
                    ),
                  ],
                )
              : items.isEmpty
              ? _empty(
                  Icons.library_music_outlined,
                  'Todavía no hay canciones aquí',
                  'Importa archivos, guarda favoritos o descubre música en Buscar.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _trackTile(c, items[i], items),
                ),
        ),
      ],
    );
  }

  Widget _trackTile(
    AppController c,
    Track t,
    List<Track> items, {
    Key? key,
    MusicPlaylist? playlist,
  }) {
    final active = c.currentTrack?.id == t.id;
    final playlistIndex = playlist?.trackIds.indexOf(t.id) ?? -1;
    return ListTile(
      key: key,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selected: active,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: .06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: Artwork(track: t, size: 48, radius: 8),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => c.playTrack(t, context: items),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (MediaQuery.sizeOf(context).width >= 700)
            Text(
              _time(t.duration),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          PopupMenuButton<String>(
            tooltip: 'Opciones de ${t.title}',
            onSelected: (value) {
              switch (value) {
                case 'favorite':
                  c.toggleFavorite(t);
                case 'queue':
                  c.addToQueue(t);
                case 'download':
                  c.downloadTrack(t);
                case 'playlist':
                  _addToPlaylist(c, t);
                case 'remove':
                  if (playlist != null) c.removeFromPlaylist(playlist, t);
                case 'up':
                  if (playlist != null && playlistIndex > 0) {
                    c.reorderPlaylist(
                      playlist,
                      playlistIndex,
                      playlistIndex - 1,
                    );
                  }
                case 'down':
                  if (playlist != null &&
                      playlistIndex < playlist.trackIds.length - 1) {
                    c.reorderPlaylist(
                      playlist,
                      playlistIndex,
                      playlistIndex + 2,
                    );
                  }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'favorite',
                child: Text(
                  c.favoriteIds.contains(t.id)
                      ? 'Quitar de favoritos'
                      : 'Añadir a favoritos',
                ),
              ),
              const PopupMenuItem(
                value: 'queue',
                child: Text('Añadir a la cola'),
              ),
              const PopupMenuItem(
                value: 'playlist',
                child: Text('Añadir a una lista'),
              ),
              if (!t.isLocal)
                const PopupMenuItem(
                  value: 'download',
                  child: Text('Descargar audio'),
                ),
              if (playlist != null && playlistIndex > 0)
                const PopupMenuItem(
                  value: 'up',
                  child: Text('Subir en la lista'),
                ),
              if (playlist != null &&
                  playlistIndex < playlist.trackIds.length - 1)
                const PopupMenuItem(
                  value: 'down',
                  child: Text('Bajar en la lista'),
                ),
              if (playlist != null)
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Quitar de esta lista'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _downloads(AppController c) => c.downloads.isEmpty
      ? _empty(
          Icons.download_for_offline_outlined,
          'Música que te acompaña sin conexión',
          'En el menú de una canción, elige Descargar audio.',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: c.downloads.length,
          itemBuilder: (_, i) {
            final job = c.downloads[i];
            final status = switch (job.status) {
              DownloadStatus.queued => 'En espera',
              DownloadStatus.downloading =>
                'Descargando · ${(job.progress * 100).round()} %',
              DownloadStatus.completed => 'Disponible sin conexión',
              DownloadStatus.failed => 'Descarga fallida',
              DownloadStatus.cancelled => 'Cancelada',
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Artwork(track: job.track, size: 48),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.track.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  status,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          if (job.status == DownloadStatus.downloading ||
                              job.status == DownloadStatus.queued)
                            IconButton(
                              tooltip: 'Cancelar descarga',
                              onPressed: () => c.cancelDownload(job),
                              icon: const Icon(Icons.close),
                            ),
                          if (job.status == DownloadStatus.failed ||
                              job.status == DownloadStatus.cancelled)
                            IconButton(
                              tooltip: 'Reintentar descarga',
                              onPressed: () => c.retryDownload(job),
                              icon: const Icon(Icons.refresh),
                            ),
                          if (job.status == DownloadStatus.completed)
                            IconButton(
                              tooltip: 'Eliminar archivo descargado',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final confirmed = await _confirm(
                                  'Eliminar descarga',
                                  'Se eliminará el archivo descargado de «${job.track.title}». '
                                      'Tus favoritos y listas se conservarán. '
                                      'Si está reproduciéndose, se detendrá.',
                                  confirmLabel: 'Eliminar archivo',
                                );
                                if (confirmed) await c.removeDownload(job);
                              },
                            ),
                        ],
                      ),
                      if (job.status == DownloadStatus.downloading) ...[
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          value: job.progress.clamp(0, 1),
                        ),
                      ],
                      if (job.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              job.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

  Widget _settings(AppController c) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      _sectionTitle('A tu manera', 'El sonido y el espacio que prefieres'),
      const SizedBox(height: 20),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in {
            ThemeMode.system: 'Sistema',
            ThemeMode.dark: 'Oscuro',
            ThemeMode.light: 'Claro',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: c.themeMode == entry.key,
              onSelected: (_) => c.setThemeMode(entry.key),
            ),
        ],
      ),
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Colores adaptativos'),
        subtitle: const Text('El acento toma el color de la portada.'),
        value: c.adaptiveColors,
        onChanged: c.setAdaptiveColors,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reducir movimiento'),
        subtitle: const Text('Una experiencia visual más tranquila.'),
        value: c.reducedMotion,
        onChanged: c.setReducedMotion,
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.equalizer),
        title: const Text('Ecualizador'),
        subtitle: Text(c.eqEnabled ? 'Activado' : 'Desactivado'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showEq(c),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.bedtime_outlined),
        title: const Text('Temporizador de sueño'),
        subtitle: Text(
          c.sleepRemaining == null
              ? 'Desactivado'
              : '${c.sleepRemaining!.inMinutes + 1} minutos restantes',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _sleepTimer(c),
      ),
      const SizedBox(height: 24),
      const Divider(),
      const SizedBox(height: 24),
      _sectionTitle(
        'Fuentes y almacenamiento',
        'Reproducción local y extracción de audio',
      ),
      const SizedBox(height: 16),
      Text(
        defaultTargetPlatform == TargetPlatform.android
            ? 'Herramientas integradas en este dispositivo'
            : c.source.toolDirectory == null
            ? 'Configura la carpeta de herramientas para buscar y reproducir enlaces.'
            : 'Herramientas: ${c.source.toolDirectory}',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (defaultTargetPlatform != TargetPlatform.android) OutlinedButton.icon(
            onPressed: c.configureTools,
            icon: const Icon(Icons.folder_open),
            label: const Text('Carpeta de herramientas'),
          ),
          OutlinedButton.icon(
            onPressed: c.diagnosing ? null : c.runDiagnostics,
            icon: const Icon(Icons.health_and_safety_outlined),
            label: Text(
              c.diagnosing ? 'Comprobando…' : 'Comprobar configuración',
            ),
          ),
        ],
      ),
      if (c.diagnostics != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: SelectableText(c.diagnostics!),
        ),
      const SizedBox(height: 24),
      _sectionTitle(
        'Sesión de YouTube opcional',
        c.hasYouTubeSession
            ? 'Sesión configurada en este dispositivo'
            : 'Sin sesión importada',
      ),
      const SizedBox(height: 12),
      const Text(
        'Importa un archivo cookies.txt en formato Netscape exportado por ti de tu sesión de YouTube. '
        'Aurora guarda una copia local. Puedes reemplazarla al importar otra sesión '
        'o eliminarla desde aquí; el archivo que exportaste permanece intacto. '
        'Una sesión no garantiza resolver los límites de YouTube ni los errores 429.',
        style: TextStyle(height: 1.6),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          OutlinedButton.icon(
            onPressed: c.sessionBusy ? null : c.importYouTubeSession,
            icon: const Icon(Icons.person_outline),
            label: Text(
              c.sessionBusy
                  ? 'Procesando sesión…'
                  : c.hasYouTubeSession
                  ? 'Reemplazar sesión'
                  : 'Importar sesión',
            ),
          ),
          if (c.hasYouTubeSession)
            TextButton.icon(
              onPressed: c.sessionBusy ? null : c.clearYouTubeSession,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Eliminar sesión'),
            ),
        ],
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () async {
          if (await _confirm(
            'Limpiar caché',
            'Se eliminarán los archivos temporales. Tus descargas y listas se conservarán.',
          )) {
            c.clearCache();
          }
        },
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('Limpiar caché temporal'),
      ),
      const SizedBox(height: 32),
      const Text(
        'Aurora · Tu biblioteca permanece en este dispositivo.\nUtiliza enlaces y contenido que tengas permiso para reproducir y guardar.',
        style: TextStyle(fontSize: 12, height: 1.6),
      ),
    ],
  );

  Widget _miniPlayer(AppController c, bool wide) {
    final t = c.currentTrack!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        children: [
          _seekBar(c, compact: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _showPlayer(c),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        Artwork(track: t, size: wide ? 52 : 42, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (wide) ...[
                  IconButton(
                    tooltip: 'Anterior',
                    onPressed: c.previous,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  const SizedBox(width: 8),
                ],
                _playButton(c, size: 44),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: c.next,
                  icon: const Icon(Icons.skip_next),
                ),
                if (wide) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: 'Favorito',
                    onPressed: () => c.toggleFavorite(t),
                    icon: Icon(
                      c.favoriteIds.contains(t.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cola de reproducción',
                    onPressed: () => _showQueue(c),
                    icon: const Icon(Icons.queue_music),
                  ),
                  IconButton(
                    tooltip: 'Ecualizador',
                    onPressed: () => _showEq(c),
                    icon: const Icon(Icons.equalizer),
                  ),
                  IconButton(
                    tooltip: c.audio.volume == 0
                        ? 'Activar sonido'
                        : 'Silenciar',
                    onPressed: () => c.setVolume(c.audio.volume == 0 ? .7 : 0),
                    icon: Icon(
                      c.audio.volume == 0
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Slider(
                      value: c.audio.volume.clamp(0, 1),
                      onChanged: c.setVolume,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seekBar(AppController c, {bool compact = false}) {
    final length = c.audio.duration.inMilliseconds;
    final position = c.audio.position.inMilliseconds.clamp(
      0,
      math.max(0, length),
    );
    return Semantics(
      label: 'Posición de reproducción',
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: compact ? 2 : 3,
          thumbShape: RoundSliderThumbShape(
            enabledThumbRadius: compact ? 4 : 7,
          ),
          overlayShape: RoundSliderOverlayShape(
            overlayRadius: compact ? 8 : 18,
          ),
        ),
        child: Slider(
          value: position.toDouble(),
          max: math.max(1, length).toDouble(),
          onChanged: length > 0
              ? (v) => c.seek(Duration(milliseconds: v.round()))
              : null,
        ),
      ),
    );
  }

  Widget _playButton(AppController c, {double size = 64}) => SizedBox(
    width: size,
    height: size,
    child: IconButton.filled(
      tooltip: c.audio.isPlaying
          ? 'Pausar'
          : c.audio.isBuffering
          ? 'Cancelar carga de audio'
          : 'Reproducir',
      onPressed: c.currentTrack == null
          ? null
          : () {
              if (c.audio.isBuffering && !c.audio.isPlaying) {
                c.stopPlayback();
              } else {
                c.togglePlayback();
              }
            },
      icon: c.audio.isBuffering && !c.audio.isPlaying
          ? const SizedBox(
              width: 30,
              height: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  Icon(Icons.close, size: 16),
                ],
              ),
            )
          : Icon(
              c.audio.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: size * .6,
            ),
    ),
  );

  Future<void> _showPlayer(AppController c) async {
    _playerOpen = true;
    _syncVisualization();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final player = ref.watch(controllerProvider);
          final t = player.currentTrack;
          if (t == null) return const SizedBox.shrink();
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .92,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: _AmbientView(
                        values: player.audio.spectrum,
                        color: Theme.of(context).colorScheme.primary,
                        animated:
                            player.audio.isPlaying &&
                            !player.reducedMotion &&
                            !MediaQuery.disableAnimationsOf(context),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Cerrar reproductor',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.keyboard_arrow_down),
                              ),
                              const Expanded(
                                child: Text(
                                  'AHORA SUENA',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cola de reproducción',
                                onPressed: () => _showQueue(player),
                                icon: const Icon(Icons.queue_music),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          LayoutBuilder(
                            builder: (_, box) => Artwork(
                              track: t,
                              size: math.min(box.maxWidth, 330),
                              radius: 24,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            t.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.6,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t.artist,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SpectrumView(
                            values: player.audio.spectrum,
                            color: Theme.of(context).colorScheme.primary,
                            enabled:
                                player.audio.isPlaying &&
                                !player.reducedMotion &&
                                !MediaQuery.disableAnimationsOf(context),
                          ),
                          const SizedBox(height: 16),
                          _seekBar(player),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  _time(player.audio.position),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _time(player.audio.duration),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              IconButton(
                                tooltip: 'Aleatorio',
                                isSelected: player.shuffle,
                                onPressed: () =>
                                    player.setShuffle(!player.shuffle),
                                icon: const Icon(Icons.shuffle),
                              ),
                              IconButton(
                                tooltip: 'Anterior',
                                onPressed: player.previous,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 36,
                                ),
                              ),
                              _playButton(player),
                              IconButton(
                                tooltip: 'Siguiente',
                                onPressed: player.next,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  size: 36,
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'Repetición: ${player.repeat == RepeatMode.off
                                        ? 'desactivada'
                                        : player.repeat == RepeatMode.one
                                        ? 'una canción'
                                        : 'toda la cola'}',
                                isSelected: player.repeat != RepeatMode.off,
                                onPressed: player.cycleRepeat,
                                icon: Icon(
                                  player.repeat == RepeatMode.one
                                      ? Icons.repeat_one
                                      : Icons.repeat,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              IconButton(
                                tooltip: player.favoriteIds.contains(t.id)
                                    ? 'Quitar de favoritos'
                                    : 'Añadir a favoritos',
                                onPressed: () => player.toggleFavorite(t),
                                icon: Icon(
                                  player.favoriteIds.contains(t.id)
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Añadir a una lista',
                                onPressed: () => _addToPlaylist(player, t),
                                icon: const Icon(Icons.playlist_add),
                              ),
                              IconButton(
                                tooltip: 'Ecualizador',
                                onPressed: () => _showEq(player),
                                icon: const Icon(Icons.equalizer),
                              ),
                              IconButton(
                                tooltip: 'Temporizador de sueño',
                                onPressed: () => _sleepTimer(player),
                                icon: const Icon(Icons.bedtime_outlined),
                              ),
                              if (!t.isLocal)
                                IconButton(
                                  tooltip: 'Descargar audio',
                                  onPressed: () => player.downloadTrack(t),
                                  icon: const Icon(Icons.download_outlined),
                                ),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.volume_down_outlined),
                              Expanded(
                                child: Slider(
                                  value: player.audio.volume.clamp(0, 1),
                                  onChanged: player.setVolume,
                                ),
                              ),
                              const Icon(Icons.volume_up_outlined),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    _playerOpen = false;
    if (mounted) _syncVisualization();
  }

  Future<void> _showQueue(AppController c) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final player = ref.watch(controllerProvider);
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'A continuación',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar cola',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: player.queue.isEmpty
                    ? _empty(
                        Icons.queue_music,
                        'La cola está vacía',
                        'Añade canciones desde su menú.',
                      )
                    : ReorderableListView.builder(
                        itemCount: player.queue.length,
                        onReorder: player.reorderQueue,
                        itemBuilder: (_, i) => ListTile(
                          key: ValueKey('${player.queue[i].id}-$i'),
                          selected: i == player.queueIndex,
                          leading: Artwork(track: player.queue[i], size: 42),
                          title: Text(
                            player.queue[i].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            player.queue[i].artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => player.playQueueAt(i),
                          trailing: Padding(
                            padding: const EdgeInsets.only(right: 28),
                            child: PopupMenuButton<String>(
                              tooltip: 'Opciones de cola',
                              onSelected: (value) {
                                if (value == 'remove') {
                                  player.removeFromQueue(i);
                                }
                                if (value == 'up' && i > 0) {
                                  player.reorderQueue(i, i - 1);
                                }
                                if (value == 'down' &&
                                    i < player.queue.length - 1) {
                                  player.reorderQueue(i, i + 2);
                                }
                              },
                              itemBuilder: (_) => [
                                if (i > 0)
                                  const PopupMenuItem(
                                    value: 'up',
                                    child: Text('Subir'),
                                  ),
                                if (i < player.queue.length - 1)
                                  const PopupMenuItem(
                                    value: 'down',
                                    child: Text('Bajar'),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Quitar de la cola'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _showEq(AppController c) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final player = ref.watch(controllerProvider);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ecualizador',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar ecualizador',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activar ecualizador'),
                subtitle: const Text('Ajusta el sonido para tus auriculares.'),
                value: player.eqEnabled,
                onChanged: player.setEqualizerEnabled,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Plano', 'Graves', 'Vocal', 'Rock']
                    .map(
                      (name) => OutlinedButton(
                        onPressed: () => player.applyEqPreset(name),
                        child: Text(name),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 24),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (
                      int i = 0;
                      i <
                          math.min(
                            player.eqGains.length,
                            player.audio.eqFrequencies.length,
                          );
                      i++
                    )
                      SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            Text(
                              '${player.eqGains[i].toStringAsFixed(1)} dB',
                              style: const TextStyle(fontSize: 12),
                            ),
                            SizedBox(
                              height: 170,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  label:
                                      '${_frequency(player.audio.eqFrequencies[i])}: ${player.eqGains[i].toStringAsFixed(1)} dB',
                                  value: player.eqGains[i].clamp(-12, 12),
                                  min: -12,
                                  max: 12,
                                  divisions: 48,
                                  onChanged: player.eqEnabled
                                      ? (value) => player.setEqGain(i, value)
                                      : null,
                                ),
                              ),
                            ),
                            Text(
                              _frequency(player.audio.eqFrequencies[i]),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Desliza para ver todas las bandas. Plano restablece la ganancia.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _sleepTimer(AppController c) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Temporizador de sueño',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            for (final minutes in [0, 15, 30, 45, 60])
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(minutes == 0 ? 'Desactivar' : '$minutes minutos'),
                onTap: () => Navigator.pop(context, minutes),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (value != null) {
      c.setSleepTimer(value == 0 ? null : Duration(minutes: value));
    }
  }

  Future<void> _createPlaylist(AppController c) async {
    final name = await _askText('Crear lista', 'Nombre de la lista');
    if (name != null) c.createPlaylist(name);
  }

  Future<void> _addToPlaylist(AppController c, Track t) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .6, 420),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Añadir a una lista',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Crear una lista'),
              onTap: () => Navigator.pop(context, '__new__'),
            ),
            Expanded(
              child: ListView(
                children: c.playlists
                    .map(
                      (p) => ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(p.name),
                        onTap: () => Navigator.pop(context, p.id),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (id == '__new__') {
      final name = await _askText('Crear lista', 'Nombre de la lista');
      if (name != null) {
        await c.createPlaylist(name);
        final created = c.playlists.where((p) => p.name == name).lastOrNull;
        if (created != null) c.addToPlaylist(created, t);
      }
    } else if (id != null) {
      final p = c.playlists.where((p) => p.id == id).firstOrNull;
      if (p != null) c.addToPlaylist(p, t);
    }
  }

  Future<void> _importPlaylist(AppController c) async {
    final url = await _askText('Importar lista', 'Enlace de la lista');
    if (url != null) c.importPlaylist(url);
  }

  Future<String?> _askText(
    String title,
    String label, {
    String initial = '',
  }) async {
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          maxLength: label.contains('Enlace') ? 2048 : 120,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Dialog exit animation can still reference its controller.
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    return result;
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmLabel = 'Confirmar',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Widget _empty(IconData icon, String title, String message) => Center(
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

class _AmbientView extends StatefulWidget {
  const _AmbientView({
    required this.values,
    required this.color,
    required this.animated,
  });
  final ValueListenable<List<double>> values;
  final Color color;
  final bool animated;
  @override
  State<_AmbientView> createState() => _AmbientViewState();
}

class _AmbientViewState extends State<_AmbientView> {
  late _AmbientPainter _painter = _AmbientPainter(
    widget.values,
    widget.color,
    widget.animated,
  );

  @override
  void didUpdateWidget(_AmbientView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.color != oldWidget.color ||
        widget.animated != oldWidget.animated ||
        widget.values != oldWidget.values) {
      _painter = _AmbientPainter(
        widget.values,
        widget.color,
        widget.animated,
        energy: _painter.energy,
      );
    }
  }

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _painter);
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.values, this.color, this.animated, {this.energy = 0})
    : super(repaint: animated ? values : null);
  final ValueListenable<List<double>> values;
  final Color color;
  final bool animated;
  double energy;

  @override
  void paint(Canvas canvas, Size size) {
    final bins = values.value;
    final target = bins.isEmpty
        ? 0.0
        : bins.fold<double>(
                0,
                (sum, value) =>
                    sum + (value.isFinite ? value.clamp(0.0, 1.0) : 0),
              ) /
              bins.length;
    // Low pass the genuine FFT energy. The tint stays between 2 and 8 percent.
    energy += (target - energy) * .08;
    final opacity = animated ? .02 + energy.clamp(0.0, 1.0) * .06 : .025;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.animated != animated;
}

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    required this.size,
    this.radius = 12,
  });
  final Track track;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: colors.primary.withValues(alpha: .10),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: size * .35,
          color: colors.primary,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: track.artworkUrl == null
            ? placeholder
            : Image.network(
                track.artworkUrl!,
                fit: BoxFit.cover,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .ceil()
                    .clamp(48, 1024),
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, image, progress) =>
                    progress == null ? image : placeholder,
              ),
      ),
    );
  }
}

class SpectrumView extends StatelessWidget {
  const SpectrumView({
    super.key,
    required this.values,
    required this.color,
    required this.enabled,
  });
  final ValueListenable<List<double>> values;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: enabled
            ? ValueListenableBuilder<List<double>>(
                valueListenable: values,
                builder: (_, bins, _) =>
                    CustomPaint(painter: _SpectrumPainter(bins, color)),
              )
            : CustomPaint(
                painter: _SpectrumPainter(
                  const [],
                  color.withValues(alpha: .3),
                ),
              ),
      ),
    ),
  );
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.bins, this.color);
  final List<double> bins;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 32;
    final width = size.width / count;
    final paint = Paint()..color = color;
    for (int i = 0; i < count; i++) {
      final amplitude = bins.isEmpty
          ? 0.0
          : bins[(i * bins.length / count).floor().clamp(0, bins.length - 1)];
      final height = math.max(
        2.0,
        amplitude.isFinite ? amplitude.clamp(0.0, 1.0) * size.height : 2.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * width + 2,
            (size.height - height) / 2,
            math.max(1, width - 4),
            height,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.bins != bins || oldDelegate.color != color;
}

String _time(Duration value) {
  final seconds = math.max(0, value.inSeconds);
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _frequency(double value) => value >= 1000
    ? '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}k'
    : '${value.round()} Hz';
