import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/audio_backend.dart';
import '../core/models.dart';
import 'lyrics_panel.dart';
import 'artwork.dart';
import 'dj_panel.dart';
import 'playlist_shelf.dart';
import 'spotify_browser_panel.dart';
export 'artwork.dart';
import 'spotify_import_dialog.dart';
import 'spotify_match_dialog.dart';
import 'vinyl_player.dart';
import 'queue_panel.dart';

const _sections = [
  'Inicio',
  'Buscar',
  'Biblioteca',
  'Descargas locales',
  'Modo Vinilo',
  'Cola de reproducción',
  'Letras',
  'Ajustes',
];
const _icons = [
  Icons.home_outlined,
  Icons.search,
  Icons.library_music_outlined,
  Icons.download_outlined,
  Icons.album_outlined,
  Icons.queue_music,
  Icons.lyrics_outlined,
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
  bool _spotifySearch = false;
  MusicPlaylist? _playlist;
  bool _likesSelected = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _submittedQuery = '';
  final List<String> _recentSearches = [];
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

  void _navigate(int value) {
    if (value != 0) {
      ref.read(controllerProvider).cancelRecommendationDiscovery();
    }
    setState(() {
      _section = value;
      _playlist = null;
      _likesSelected = false;
    });
  }

  void _submitSearch(AppController c, String query) {
    if (c.searching) return;
    setState(() => _submittedQuery = query.trim());
    final value = query.trim();
    if (value.isEmpty) return;
    setState(() {
      _submittedQuery = value;
      _recentSearches.remove(value);
      _recentSearches.insert(0, value);
      if (_recentSearches.length > 6) _recentSearches.removeLast();
    });
    c.search(value);
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
            final desktop = size.maxWidth >= 1200;
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
                          if (desktop &&
                              _section != 4 &&
                              _section != 5 &&
                              _section != 6 &&
                              _section != 7)
                            _nowPlayingPanel(c),
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
                      selectedIndex: _section.clamp(0, 3),
                      onDestinationSelected: _navigate,
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      destinations: List.generate(
                        4,
                        (i) => NavigationDestination(
                          icon: Icon(_icons[i]),
                          label: i == 3 ? 'Descargas' : _sections[i],
                          tooltip: _sections[i],
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
      width: wide ? 216 : 76,
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
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.graphic_eq, color: colors.primary, size: 26),
                if (wide) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Aurora',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++) _navItem(i, wide),
                  const Divider(indent: 20, endIndent: 20, height: 18),
                  for (var i = 4; i < 7; i++) _navItem(i, wide),
                  if (wide && c.playlists.isNotEmpty) ...[
                    const Divider(indent: 20, endIndent: 20, height: 18),
                    for (final playlist in c.playlists)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        leading: const Icon(Icons.queue_music, size: 18),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => setState(() {
                          _section = 2;
                          _playlist = playlist;
                        }),
                      ),
                  ],
                ],
              ),
            ),
          ),
          _navItem(7, wide),
        ],
      ),
    );
  }

  Widget _navItem(int index, bool wide) {
    final colors = Theme.of(context).colorScheme;
    final active = _section == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: _sections[index],
        child: Material(
          color: active
              ? colors.primary.withValues(alpha: .12)
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _navigate(index),
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: wide
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    _icons[index],
                    size: 19,
                    color: active ? colors.primary : colors.onSurfaceVariant,
                  ),
                  if (wide) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _sections[index],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
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
            tooltip: 'Buscar música',
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.search),
          ),
        if (!rail)
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => _navigate(7),
            icon: const Icon(Icons.tune),
          ),
        if (!rail)
          PopupMenuButton<int>(
            tooltip: 'Más vistas',
            icon: const Icon(Icons.more_horiz),
            onSelected: _navigate,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 4,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.album_outlined),
                  title: Text('Modo Vinilo'),
                ),
              ),
              PopupMenuItem(
                value: 5,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.queue_music),
                  title: Text('Cola de reproducción'),
                ),
              ),
              PopupMenuItem(
                value: 6,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lyrics_outlined),
                  title: Text('Letras'),
                ),
              ),
            ],
          ),
        if (rail)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Ctrl+K',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
        return VinylPlayer(controller: c);
      case 5:
        return QueuePanel(controller: c);
      case 6:
        return LyricsPanel(controller: c, onClose: () => _navigate(0));
      case 7:
        return _settings(c);
      default:
        return _home(c);
    }
  }

  Widget _home(AppController c) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        'Hola de nuevo',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ActionChip(
            avatar: const Icon(Icons.download_outlined, size: 18),
            label: const Text('Descargas locales'),
            onPressed: () => _navigate(3),
          ),
          ActionChip(
            avatar: const Icon(Icons.favorite_border, size: 18),
            label: const Text('Favoritos'),
            onPressed: () {
              setState(() {
                _section = 2;
                _likesSelected = true;
                _playlist = null;
              });
            },
          ),
          ActionChip(
            avatar: const Icon(Icons.search, size: 18),
            label: const Text('Encontrar música'),
            onPressed: () => _navigate(1),
          ),
        ],
      ),
      if (c.recentTracks.isNotEmpty &&
          MediaQuery.sizeOf(context).width >= 1200) ...[
        _featuredRecent(c, c.recentTracks.first),
        const SizedBox(height: 28),
      ],
      _sectionTitle(
        'Tu música',
        c.recentTracks.isEmpty ? 'Tu colección' : 'Reanudá tu escucha',
      ),
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
      DjPanel(controller: c),
      const SizedBox(height: 28),
      if (c.playlists.isNotEmpty) ...[
        PlaylistShelf(
          controller: c,
          onOpen: (playlist) => setState(() {
            _section = 2;
            _playlist = playlist;
            _likesSelected = false;
          }),
        ),
        const SizedBox(height: 28),
      ],
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
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  Widget _featuredRecent(AppController c, Track track) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth <= 520;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      return Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(3),
          bottomRight: Radius.circular(8),
          bottomLeft: Radius.circular(3),
        ),
        child: InkWell(
          onTap: () => c.playTrack(track, context: c.recentTracks),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 20),
            child: Row(
              children: [
                Artwork(track: track, size: compact ? 80 : 176, radius: 8),
                SizedBox(width: compact ? 12 : 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VUELVE A ESCUCHAR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      SizedBox(height: compact ? 8 : 20),
                      if (compact || scale >= 1.5)
                        IconButton.filled(
                          tooltip: 'Reproducir ${track.title}',
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          onPressed: () =>
                              c.playTrack(track, context: c.recentTracks),
                          icon: const Icon(Icons.play_arrow),
                        )
                      else
                        FilledButton.icon(
                          onPressed: () =>
                              c.playTrack(track, context: c.recentTracks),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Reproducir', softWrap: false),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _nowPlayingPanel(AppController c) {
    final track = c.currentTrack;
    final upcoming = c.queue.skip(c.queueIndex + 1).take(8).toList();
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border(
          left: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'AHORA SUENA',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          if (track == null)
            _empty(
              Icons.music_note_outlined,
              'Nada en reproducción',
              'Elige una canción de tu colección.',
            )
          else ...[
            Center(child: Artwork(track: track, size: 240, radius: 8)),
            const SizedBox(height: 16),
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: c.previous,
                  icon: const Icon(Icons.skip_previous),
                ),
                _playButton(c, size: 44),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: c.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'A continuación',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${upcoming.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            Text(
              'La cola está vacía',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final item in upcoming)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Artwork(track: item, size: 40, radius: 5),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  item.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => c.playQueueAt(c.queue.indexOf(item)),
              ),
        ],
      ),
    );
  }

  Widget _albumCard(AppController c, Track t) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => c.playTrack(t),
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Artwork(track: t, size: constraints.maxWidth, radius: 16),
          const SizedBox(height: 8),
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
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _searchPage(AppController c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Audio · YouTube'),
                selected: !_spotifySearch,
                onSelected: (_) => setState(() => _spotifySearch = false),
              ),
              ChoiceChip(
                label: const Text('Metadatos · Spotify'),
                selected: _spotifySearch,
                onSelected: (_) => setState(() => _spotifySearch = true),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: _spotifySearch
            ? SpotifyBrowserPanel(
                onQueue: (track) => SpotifyMatchDialog.show(
                  context,
                  track: track,
                  saveLabel: 'Añadir a la cola',
                  playLabel: 'Reproducir',
                  onSearch: () => c.findSpotifyMatches(track),
                  onSave: (match, {required play}) =>
                      c.importSpotifyMetadataMatch(track, match, play: play),
                ),
              )
            : _audioSearchPage(c),
      ),
    ],
  );

  Widget _audioSearchPage(AppController c) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Canción, artista o enlace',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.arrow_forward),
              onPressed: c.searching
                  ? null
                  : () => _submitSearch(c, _search.text),
            ),
            border: const OutlineInputBorder(),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasSidebar = constraints.maxWidth >= 900;
            final results = c.searchResults.isEmpty
                ? _empty(
                    Icons.travel_explore,
                    c.searching
                        ? 'Buscando tu próxima canción…'
                        : _submittedQuery.isNotEmpty &&
                              _submittedQuery == _search.text.trim()
                        ? 'Sin resultados'
                        : 'Encuentra algo que te mueva',
                    c.searching
                        ? 'La búsqueda puede tardar unos segundos.'
                        : _submittedQuery.isNotEmpty &&
                              _submittedQuery == _search.text.trim()
                        ? 'Prueba con otro título o artista, o pega un enlace directo.'
                        : 'Escribe un título, artista o pega un enlace compatible.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:
                        c.searchResults.length +
                        (c.hasMoreSearchResults ? 1 : 0),
                    itemBuilder: (_, i) => i == c.searchResults.length
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: OutlinedButton.icon(
                              onPressed: c.searching ? null : c.loadMoreSearch,
                              icon: const Icon(Icons.expand_more),
                              label: Text(
                                c.searching
                                    ? 'Buscando…'
                                    : 'Ver más resultados',
                              ),
                            ),
                          )
                        : _trackTile(c, c.searchResults[i], c.searchResults),
                  );
            if (!hasSidebar) return results;
            return Row(
              children: [
                SizedBox(
                  width: 220,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
                    children: [
                      Text(
                        'Búsquedas recientes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_recentSearches.isEmpty)
                        Text(
                          'Tus búsquedas aparecerán aquí.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        for (final query in _recentSearches)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.history, size: 18),
                            title: Text(
                              query,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              _search.text = query;
                              _submitSearch(c, query);
                            },
                          ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: results),
              ],
            );
          },
        ),
      ),
    ],
  );
  Widget _library(AppController c) {
    if (_playlist != null || _likesSelected) {
      final playlist = _likesSelected
          ? null
          : c.playlists.where((item) => item.id == _playlist!.id).firstOrNull;
      if (!_likesSelected && playlist == null) {
        return _empty(
          Icons.queue_music,
          'Esta lista ya no existe',
          'Selecciona otra lista de tu biblioteca.',
        );
      }
      final items = _likesSelected
          ? c.tracks.where((track) => c.favoriteIds.contains(track.id)).toList()
          : playlist!.trackIds
                .map(
                  (id) => c.tracks.where((track) => track.id == id).firstOrNull,
                )
                .whereType<Track>()
                .toList();
      return Column(
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _playlist = null;
                        _likesSelected = false;
                      }),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Todas las listas'),
                    ),
                    if (_likesSelected)
                      Text(
                        'Me gusta',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    FilledButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () => c.playTrack(items.first, context: items),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Reproducir'),
                    ),
                    if (playlist != null) ...[
                      OutlinedButton(
                        onPressed: () async {
                          final name = await _askText(
                            'Renombrar lista',
                            'Nombre',
                            initial: playlist.name,
                          );
                          if (name != null) c.renamePlaylist(playlist, name);
                        },
                        child: const Text('Renombrar'),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (await _confirm(
                            'Eliminar lista',
                            'Se eliminará «${playlist.name}». Tus archivos permanecerán en la biblioteca.',
                          )) {
                            c.deletePlaylist(playlist);
                            setState(() => _playlist = null);
                          }
                        },
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? _empty(
                    _likesSelected ? Icons.favorite_border : Icons.playlist_add,
                    _likesSelected
                        ? 'Aún no hay canciones que te gusten'
                        : 'Esta lista está esperando música',
                    _likesSelected
                        ? 'Marca una canción con Me gusta para verla aquí.'
                        : 'Añade canciones desde el menú de cualquier resultado o canción.',
                  )
                : playlist == null
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _trackTile(c, items[i], items),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) =>
                        c.reorderPlaylist(playlist, oldIndex, newIndex),
                    itemBuilder: (_, i) => _trackTile(
                      c,
                      items[i],
                      items,
                      key: ValueKey('${playlist.id}-${items[i].id}'),
                      playlist: playlist,
                    ),
                  ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tu biblioteca',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: c.busy ? null : () => _importSpotify(c),
                      icon: const Icon(Icons.library_add_outlined),
                      label: const Text('Importar de Spotify'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _createPlaylist(c),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear lista'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.favorite),
                title: const Text('Me gusta'),
                subtitle: Text('${c.favoriteIds.length} canciones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() {
                  _likesSelected = true;
                  _playlist = null;
                }),
              ),
              if (c.playlists.isEmpty)
                _empty(
                  Icons.queue_music,
                  'Una lista para cada momento',
                  'Crea una lista y reúne tus canciones favoritas.',
                ),
              if (c.playlists.isNotEmpty)
                PlaylistShelf(
                  controller: c,
                  onOpen: (playlist) => setState(() {
                    _likesSelected = false;
                    _playlist = playlist;
                  }),
                ),
            ],
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
      subtitle: Text(
        t.isPendingSpotifyMatch
            ? '${t.artist} · Elige una coincidencia de YouTube'
            : '${t.artist}${t.isLocal ? ' · Disponible sin conexión' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: t.isPendingSpotifyMatch
          ? () => _matchSpotify(c, t)
          : () => c.playTrack(t, context: items),
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
                case 'match':
                  _matchSpotify(c, t);
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
              if (t.isPendingSpotifyMatch)
                const PopupMenuItem(
                  value: 'match',
                  child: Text('Elegir coincidencia de YouTube'),
                ),
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

  Widget _downloads(AppController c) {
    final completed = c.downloads
        .where((job) => job.status == DownloadStatus.completed)
        .toList();
    final pending = c.downloads
        .where((job) => job.status != DownloadStatus.completed)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Carpeta de descargas',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        SelectableText(
          c.downloadsDirectoryPath,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Los cambios se aplican a las próximas descargas.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed:
                  c.canConfigureDownloadDirectory &&
                      !c.configuringDownloadDirectory
                  ? c.chooseDownloadDirectory
                  : null,
              icon: const Icon(Icons.drive_file_move_outline),
              label: Text(
                c.configuringDownloadDirectory
                    ? 'Abriendo selector…'
                    : 'Cambiar carpeta',
              ),
            ),
            OutlinedButton.icon(
              onPressed: c.openDownloadDirectory,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Abrir carpeta'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        if (completed.isNotEmpty) ...[
          _sectionTitle(
            'Disponibles sin conexión',
            '${completed.length} archivos',
          ),
          const SizedBox(height: 8),
          ...completed.map((job) => _downloadRow(c, job)),
          const SizedBox(height: 20),
        ],
        _sectionTitle('En cola', '${pending.length} descargas'),
        if (pending.isEmpty && completed.isEmpty)
          _empty(
            Icons.download_for_offline_outlined,
            'Aún no hay descargas',
            'Elige Descargar audio en el menú de una canción. Puedes configurar la carpeta de destino arriba.',
          )
        else if (pending.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No hay descargas pendientes.'),
          )
        else
          ...pending.map((job) => _downloadRow(c, job)),
        if (pending.isEmpty &&
            completed.isEmpty &&
            c.canConfigureDownloadDirectory)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: c.configuringDownloadDirectory
                  ? null
                  : c.chooseDownloadDirectory,
              icon: const Icon(Icons.drive_file_move_outline),
              label: const Text('Configurar carpeta'),
            ),
          ),
      ],
    );
  }

  Widget _downloadRow(AppController c, DownloadJob job) {
    final status = switch (job.status) {
      DownloadStatus.queued => 'En espera',
      DownloadStatus.downloading =>
        'Descargando · ${(job.progress * 100).round()} %',
      DownloadStatus.completed => 'Disponible sin conexión',
      DownloadStatus.failed => 'Descarga fallida',
      DownloadStatus.cancelled => 'Cancelada',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Artwork(track: job.track, size: 48, radius: 8),
      title: Text(
        job.track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(status),
          if (job.status == DownloadStatus.downloading)
            LinearProgressIndicator(value: job.progress.clamp(0, 1)),
          if (job.error != null)
            Text(
              job.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing:
          job.status == DownloadStatus.queued ||
              job.status == DownloadStatus.downloading
          ? IconButton(
              tooltip: 'Cancelar descarga',
              onPressed: () => c.cancelDownload(job),
              icon: const Icon(Icons.close),
            )
          : job.status == DownloadStatus.failed ||
                job.status == DownloadStatus.cancelled
          ? IconButton(
              tooltip: 'Reintentar descarga',
              onPressed: () => c.retryDownload(job),
              icon: const Icon(Icons.refresh),
            )
          : IconButton(
              tooltip: 'Eliminar archivo descargado',
              onPressed: () async {
                final confirmed = await _confirm(
                  'Eliminar descarga',
                  'Se eliminará el archivo descargado de «${job.track.title}». Tus favoritos y listas se conservarán. Si está reproduciéndose, se detendrá.',
                  confirmLabel: 'Eliminar archivo',
                );
                if (confirmed) await c.removeDownload(job);
              },
              icon: const Icon(Icons.delete_outline),
            ),
    );
  }

  Widget _settings(AppController c) {
    final sections = <({String title, String subtitle, List<Widget> children})>[
      (
        title: 'Almacenamiento y biblioteca',
        subtitle: 'Tu música y descargas en este dispositivo',
        children: [
          const Text('Carpeta de descargas'),
          const SizedBox(height: 8),
          SelectableText(c.downloadsDirectoryPath),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    c.canConfigureDownloadDirectory &&
                        !c.configuringDownloadDirectory
                    ? c.chooseDownloadDirectory
                    : null,
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text(
                  c.configuringDownloadDirectory
                      ? 'Abriendo selector…'
                      : 'Cambiar carpeta',
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.openDownloadDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Abrir carpeta'),
              ),
              OutlinedButton.icon(
                onPressed: c.importFiles,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Importar archivos'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('La carpeta se usa para las próximas descargas.'),
          if (c.source.supportsPlaybackCache) ...[
            const SizedBox(height: 20),
            Text(
              'Caché de reproducción',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Hasta 512 MB. Los archivos antiguos se limpian automáticamente. Tus descargas y la canción actual se conservan.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: c.busy || c.clearingPlaybackCache
                    ? null
                    : c.clearPlaybackCache,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  c.clearingPlaybackCache ? 'Limpiando…' : 'Limpiar caché',
                ),
              ),
            ),
            if (c.playbackCacheMessage != null) ...[
              const SizedBox(height: 8),
              Text(c.playbackCacheMessage!),
            ],
          ],
        ],
      ),
      (
        title: 'Reproducción experimental',
        subtitle: 'Descarga mientras se reproduce',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Descargar mientras se reproduce'),
            subtitle: Text(
              c.source.supportsExperimentalProgressivePlayback
                  ? 'Empieza antes; puede esperar en zonas aún no descargadas o fallar. La descarga completa sigue siendo la opción estable.'
                  : 'No disponible para esta fuente o plataforma.',
            ),
            value: c.experimentalProgressivePlayback,
            onChanged: c.source.supportsExperimentalProgressivePlayback
                ? c.setExperimentalProgressivePlayback
                : null,
          ),
        ],
      ),
      (
        title: 'Identidad y tema',
        subtitle: 'Ajusta la apariencia de Aurora',
        children: [
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
          Text(
            'Color de acento',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          const Text('Automático toma el color de la portada actual.'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'automatic': 'Automático',
                'terracotta': 'Terracota',
                'amber': 'Ámbar',
                'forest': 'Verde bosque',
                'purple': 'Morado',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: c.accentPalette == entry.key,
                  onSelected: (_) => c.setAccentPalette(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reducir movimiento'),
            subtitle: const Text('Una experiencia visual más tranquila.'),
            value: c.reducedMotion,
            onChanged: c.setReducedMotion,
          ),
        ],
      ),
      (
        title: 'Ecualizador',
        subtitle: c.eqEnabled
            ? 'Ecualizador activado'
            : 'Ecualizador desactivado',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar ecualizador'),
            value: c.eqEnabled,
            onChanged: c.setEqualizerEnabled,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Plano', 'Graves', 'Vocal', 'Rock']
                .map(
                  (name) => OutlinedButton(
                    onPressed: () => c.applyEqPreset(name),
                    child: Text(name),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final count = math.min(
                c.eqGains.length,
                c.audio.eqFrequencies.length,
              );
              final cellWidth = (constraints.maxWidth / count).clamp(
                38.0,
                76.0,
              );
              return Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      width: cellWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${c.eqGains[i].toStringAsFixed(1)} dB',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          SizedBox(
                            height: 120,
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: Slider(
                                label:
                                    '${_frequency(c.audio.eqFrequencies[i])}: ${c.eqGains[i].toStringAsFixed(1)} dB',
                                value: c.eqGains[i].clamp(-12, 12),
                                min: -12,
                                max: 12,
                                divisions: 48,
                                onChanged: c.eqEnabled
                                    ? (value) => c.setEqGain(i, value)
                                    : null,
                              ),
                            ),
                          ),
                          Text(
                            _frequency(c.audio.eqFrequencies[i]),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      (
        title: 'Sueño',
        subtitle: c.sleepRemaining == null
            ? 'Temporizador desactivado'
            : '${c.sleepRemaining!.inMinutes + 1} minutos restantes',
        children: [
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
        ],
      ),
      (
        title: 'Herramientas, sesión y diagnóstico',
        subtitle: 'Fuentes locales y utilidades opcionales',
        children: [
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
              if (defaultTargetPlatform != TargetPlatform.android)
                OutlinedButton.icon(
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
          const SizedBox(height: 16),
          Text(
            c.hasYouTubeSession
                ? 'Sesión de YouTube configurada'
                : 'Sesión de YouTube opcional sin importar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Importa un archivo cookies.txt en formato Netscape exportado por ti de tu sesión de YouTube. Aurora guarda una copia local. Puedes reemplazarla o eliminarla desde aquí. Una sesión no garantiza resolver límites de YouTube ni errores 429.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 12),
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
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Aurora · Tu biblioteca permanece en este dispositivo. Utiliza enlaces y contenido que tengas permiso para reproducir y guardar.',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ],
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        Widget card(int i) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: EdgeInsets.all(compact ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(sections[i].title, sections[i].subtitle),
                  const SizedBox(height: 14),
                  ...sections[i].children,
                ],
              ),
            ),
          ),
        );
        if (compact) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (var i = 0; i < sections.length; i++) card(i)],
          );
        }
        Widget column(int offset) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = offset; i < sections.length; i += 2) card(i),
            ],
          ),
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [column(0), const SizedBox(width: 20), column(1)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _miniPlayer(AppController c, bool wide) {
    final t = c.currentTrack!;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: [
                Text(
                  _time(c.audio.position),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Expanded(child: _seekBar(c, compact: true)),
                Text(
                  _time(c.audio.duration),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: Row(
              children: [
                if (!wide) ...[
                  InkWell(
                    onTap: () => _showPlayer(c),
                    borderRadius: BorderRadius.circular(8),
                    child: Artwork(track: t, size: 42, radius: 8),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _showPlayer(c),
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                  ),
                  const SizedBox(width: 12),
                  _playButton(c, size: 44),
                  IconButton(
                    tooltip: 'Siguiente',
                    onPressed: c.next,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    tooltip: 'Letras',
                    onPressed: c.currentTrack == null
                        ? null
                        : () => _showLyrics(c),
                    icon: const Icon(Icons.mic_none_outlined),
                  ),
                ] else ...[
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
                  SizedBox(
                    width: wide ? 140 : 44,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (wide)
                          IconButton(
                            tooltip: 'Anterior',
                            onPressed: c.previous,
                            icon: const Icon(Icons.skip_previous),
                          ),
                        _playButton(c, size: 44),
                        if (wide)
                          IconButton(
                            tooltip: 'Siguiente',
                            onPressed: c.next,
                            icon: const Icon(Icons.skip_next),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!wide)
                            IconButton(
                              tooltip: 'Siguiente',
                              onPressed: c.next,
                              icon: const Icon(Icons.skip_next),
                            ),
                          if (wide)
                            TextButton.icon(
                              onPressed: () => _showLyrics(c),
                              icon: const Icon(Icons.mic_none_outlined),
                              label: const Text('Letras'),
                            )
                          else
                            IconButton(
                              tooltip: 'Letras',
                              onPressed: c.currentTrack == null
                                  ? null
                                  : () => _showLyrics(c),
                              icon: const Icon(Icons.mic_none_outlined),
                            ),
                          if (wide) ...[
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
                              onPressed: () =>
                                  c.setVolume(c.audio.volume == 0 ? .7 : 0),
                              icon: Icon(
                                c.audio.volume == 0
                                    ? Icons.volume_off_outlined
                                    : Icons.volume_up_outlined,
                              ),
                            ),
                            SizedBox(
                              width: MediaQuery.sizeOf(context).width < 1200
                                  ? 60
                                  : 100,
                              child: Slider(
                                value: c.audio.volume.clamp(0, 1),
                                onChanged: c.setVolume,
                              ),
                            ),
                          ],
                        ],
                      ),
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
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
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
                          Column(
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
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Tooltip(
                                    message: 'Letras',
                                    child: TextButton.icon(
                                      onPressed: player.currentTrack == null
                                          ? null
                                          : () => _showLyrics(player),
                                      icon: const Icon(Icons.mic_none_outlined),
                                      label: const Text('Letras'),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Cola de reproducci\u00f3n',
                                    onPressed: () => _showQueue(player),
                                    icon: const Icon(Icons.queue_music),
                                  ),
                                ],
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

  Future<void> _showLyrics(AppController c) => showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => Dialog.fullscreen(child: LyricsPanel(controller: c)),
  );

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

  Future<void> _importSpotify(AppController c) async {
    c.clearError();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar datos de Spotify'),
        scrollable: true,
        content: const Text(
          '1. Exporta un CSV o solicita tus datos en Spotify → Cuenta → Privacidad. Usa el archivo Playlist*.json.\n\n'
          '2. Elige el archivo, revisa las listas y pulsa Importar.\n\n'
          '3. Toca una canción pendiente para elegir su versión de YouTube.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elegir archivo'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    final result = await c.pickSpotifyImport();
    if (!mounted) return;
    if (result == null) {
      if (c.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(c.error!)));
        c.clearError();
      }
      return;
    }
    await SpotifyImportDialog.show(
      context,
      result: result,
      onImport: c.importSpotifyPlaylists,
    );
    if (!mounted || c.error == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(c.error!)));
    c.clearError();
  }

  Future<void> _matchSpotify(AppController c, Track track) =>
      SpotifyMatchDialog.show(
        context,
        track: track,
        onSearch: () => c.findSpotifyMatches(track),
        onSave: (match, {required play}) =>
            c.matchSpotifyTrack(track.id, match, play: play),
      );

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
