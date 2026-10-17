import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/audio_backend.dart';
import '../core/models.dart';
import '../core/source_backend.dart';
import '../core/window_controls.dart';
import '../jam/jam_controller.dart';
import 'studio/studio_navigation.dart';
import 'studio/studio_transport.dart';
import 'studio/session_aside.dart';
import 'studio/downloads_studio_page.dart';
import 'lyrics_panel.dart';
import 'artwork.dart';
import 'dj_discovery_page.dart';
import 'home_music_page.dart';
import 'jam/jam_page.dart';
import 'playlist_shelf.dart';
import 'spotify_browser_panel.dart';
export 'artwork.dart';
import 'spotify_import_dialog.dart';
import 'spotify_match_dialog.dart';
import 'vinyl_player.dart';
import 'queue_panel.dart';
import 'offline_settings_panel.dart';
import '../youtube_music/youtube_music_page.dart';
import 'video_downloads_page.dart';
import 'artists_page.dart';
import '../audio/routed_music_audio.dart';
import '../audio_web/web_music_audio.dart';
import '../updater/update_controller.dart';
import '../updater/update_ui.dart';

const _sections = [
  'Inicio',
  'Buscar',
  'Biblioteca',
  'Descargas locales',
  'Modo Vinilo',
  'Cola de reproducción',
  'Letras',
  'Ajustes',
  'DJ',
  'Jam',
  'YouTube Music',
  'Descargar vídeos',
  'Artistas',
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
  Icons.explore_outlined,
  Icons.groups_outlined,
  Icons.music_video_outlined,
  Icons.video_file_outlined,
  Icons.mic_none_rounded,
];
const _primarySections = [0, 1, 8, 2, 3];

class AuroraShell extends ConsumerStatefulWidget {
  const AuroraShell({super.key});
  @override
  ConsumerState<AuroraShell> createState() => _AuroraShellState();
}

class _AuroraShellState extends ConsumerState<AuroraShell>
    with WidgetsBindingObserver {
  int _section = 0;
  bool _jamVisited = false;
  bool _musicVisited = false;
  bool _videosVisited = false;
  bool _navigationPending = false;
  Uri? _musicUri;
  final _musicKey = GlobalKey<YouTubeMusicPageState>();
  JamController? _jam;
  bool _spotifySearch = false;
  MusicPlaylist? _playlist;
  bool _likesSelected = false;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final AudioBackend _audio;
  bool _playerOpen = false;
  bool _foreground = true;
  bool _analysisEnabled = false;
  late final UpdateController _updates;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(controllerProvider).audio;
    _updates = UpdateController(ref.read(controllerProvider).preferences)
      ..start();
    WindowControls.setCloseConfirmation(_confirmWindowClose);
    _guardWebClose();
    _audio.setVisualizationEnabled(false);
  }

  /// The hidden official player, when it initialized.
  WebMusicAudio? get _webAudio {
    final audio = _audio;
    return audio is RoutedMusicAudio &&
            audio.web is WebMusicAudio &&
            audio.webInitializationError == null
        ? audio.web as WebMusicAudio
        : null;
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
        c.audio.supportsVisualization &&
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

  // With the web engine mounted every close passes through _confirmWindowClose.
  void _guardWebClose() =>
      WindowControls.guardClose(_section == 10 || _webAudio != null);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WindowControls.setCloseConfirmation(null);
    WindowControls.guardClose(false);
    _jam?.removeListener(_jamChanged);
    if (_analysisEnabled) _audio.setVisualizationEnabled(false);
    _updates.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _jamChanged() {
    if (mounted) setState(() {});
  }

  void _jamCreated(JamController controller) {
    if (identical(_jam, controller)) return;
    _jam?.removeListener(_jamChanged);
    _jam = controller;
    _jam?.addListener(_jamChanged);
    _jamChanged();
  }

  Future<void> _navigate(int value, {bool fromRequest = false}) async {
    if (value == 10 &&
        !fromRequest &&
        ref.read(controllerProvider).usesOfficialYouTubeMusic) {
      ref.read(controllerProvider).openYouTubeMusic();
      return;
    }
    if (_navigationPending) return;
    _navigationPending = true;
    try {
      if (_section == 10 &&
          value != 10 &&
          !(await _musicKey.currentState?.confirmExit() ?? true)) {
        return;
      }
      if (!mounted) return;
      if (value != 0 && value != 8) {
        ref.read(controllerProvider).cancelRecommendationDiscovery();
      }
      setState(() {
        _section = value;
        if (value == 9) _jamVisited = true;
        _musicVisited = value == 10;
        if (value == 11) _videosVisited = true;
        _playlist = null;
        _likesSelected = false;
      });
      _guardWebClose();
      if (value != 10 && ref.read(controllerProvider).youtubeMusicActive) {
        ref.read(controllerProvider).closeYouTubeMusic();
      }
    } finally {
      _navigationPending = false;
    }
  }

  void _closeMusic() {
    WindowControls.guardClose(false);
    ref.read(controllerProvider).closeYouTubeMusic();
    setState(() {
      _musicVisited = false;
      _musicUri = null;
      _section = 0;
    });
  }

  Future<bool> _confirmWindowClose() async {
    final close = await _musicKey.currentState?.confirmExit() ?? true;
    // Release WebView2 before the window goes so the process can exit.
    if (close) await _webAudio?.shutdown();
    return close;
  }

  Future<void> _openLibrary({
    MusicPlaylist? playlist,
    bool likes = false,
  }) async {
    await _navigate(2);
    if (!mounted || _section != 2) return;
    setState(() {
      _playlist = playlist;
      _likesSelected = likes;
    });
  }

  void _submitSearch(AppController c, String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    c.search(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    ref.listen(controllerProvider.select((c) => c.youtubeMusicRequest), (
      _,
      uri,
    ) {
      if (uri == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(controllerProvider).clearYouTubeMusicRequest();
        setState(() => _musicUri = uri);
        _navigate(10, fromRequest: true);
      });
    });
    ref.listen(
      controllerProvider.select((c) => (c.reducedMotion, c.audio.isPlaying)),
      (_, _) => _syncVisualization(),
    );
    final web = _webAudio;
    final shell = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _navigate(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _navigate(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _navigate(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _navigate(3),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            _navigate(4),
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): () =>
            _navigate(6),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          _navigate(1);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _searchFocus.requestFocus(),
          );
        },
        if (_section != 10)
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause):
              c.togglePlayback,
        if (_section != 10)
          const SingleActivator(LogicalKeyboardKey.mediaTrackNext): c.next,
        if (_section != 10)
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
                    if (rail || WindowControls.supported)
                      StudioTitleBar(
                        onNavigate: _navigate,
                        sessionText: _jam?.service.connected == true
                            ? 'SESIÓN ESTUDIO · ${_jam!.service.invite?.endpoint ?? 'LOCAL'}'
                            : 'SESIÓN ESTUDIO · SIN JAM',
                        activeSession: _jam?.service.connected == true,
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (rail) _sidebar(c, wide),
                          Expanded(
                            child: Column(
                              children: [
                                if (!wide || ![0, 3, 6].contains(_section))
                                  _header(c, rail),
                                if (!c.ready || c.busy)
                                  const LinearProgressIndicator(minHeight: 2),
                                if (c.error != null) _errorBanner(c),
                                UpdateBanner(
                                  controller: _updates,
                                  isPlaying: () => c.audio.isPlaying,
                                ),
                                Expanded(child: _content(c)),
                              ],
                            ),
                          ),
                          if (desktop &&
                              !c.jamPlaybackActive &&
                              _section != 3 &&
                              _section != 4 &&
                              _section != 5 &&
                              _section != 6 &&
                              _section != 7 &&
                              _section != 10 &&
                              _section != 11)
                            StudioSessionAside(
                              controller: c,
                              jam: _jam,
                              onJam: () => _navigate(9),
                              onQueue: () => _navigate(
                                _jam?.service.connected == true ? 9 : 5,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_section == 10 && c.usesOfficialYouTubeMusic)
                      const SizedBox.shrink()
                    else if (c.jamPlaybackActive)
                      _jamPlaybackBar()
                    else
                      StudioTransport(
                        controller: c,
                        onLyrics: () => _showLyrics(c),
                        onVinyl: () => _navigate(4),
                        onQueue: () => _navigate(5),
                        onOpenPlayer: () => _showPlayer(c),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: rail
                  ? null
                  : NavigationBar(
                      selectedIndex: math.max(
                        0,
                        _primarySections.indexOf(_section),
                      ),
                      onDestinationSelected: (index) =>
                          _navigate(_primarySections[index]),
                      labelBehavior:
                          NavigationDestinationLabelBehavior.onlyShowSelected,
                      destinations: List.generate(
                        _primarySections.length,
                        (i) => NavigationDestination(
                          icon: Icon(_icons[_primarySections[i]]),
                          label: _primarySections[i] == 3
                              ? 'Descargas'
                              : _sections[_primarySections[i]],
                          tooltip: _sections[_primarySections[i]],
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
    if (web == null) return shell;
    return ListenableBuilder(
      listenable: web,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [shell, ..._webEngineLayers(web)],
      ),
    );
  }

  /// The official player is always mounted at the same tree position (so it
  /// keeps playing) and covered. It is shown only as a sheet when the site
  /// itself asks the user for consent, sign-in or a verification.
  List<Widget> _webEngineLayers(WebMusicAudio web) {
    final visible = web.showingWebsite;
    final colors = Theme.of(context).colorScheme;
    return [
      Positioned.fill(
        child: IgnorePointer(
          ignoring: !visible,
          child: ColoredBox(
            color: visible ? Colors.black54 : Colors.transparent,
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: visible ? 72 : 0,
        right: visible ? 0 : null,
        bottom: visible ? 0 : null,
        width: visible ? null : 1,
        height: visible ? null : 1,
        child: web.buildEngineView(),
      ),
      if (visible)
        Positioned(
          left: 0,
          right: 0,
          top: 16,
          height: 56,
          child: Material(
            color: colors.surfaceContainerHigh,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Resuelve el aviso de YouTube Music y pulsa Listo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      web.setWebsiteVisible(false);
                      final c = ref.read(controllerProvider);
                      c.clearError();
                      unawaited(c.resumePlayback());
                    },
                    child: const Text('Listo'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Widget _sidebar(AppController c, bool wide) {
    if (wide) {
      return StudioSidebar(
        controller: c,
        selected: _section,
        onNavigate: _navigate,
        onPlaylist: (playlist) => _openLibrary(playlist: playlist),
      );
    }
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
                  for (final i in _primarySections) _navItem(i, wide),
                  const Divider(indent: 20, endIndent: 20, height: 18),
                  for (final i in [12, 10, 11, 9, 4, 5, 6]) _navItem(i, wide),
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
                        onTap: () => _openLibrary(playlist: playlist),
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
                value: 12,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.mic_none_rounded),
                  title: Text('Artistas'),
                ),
              ),
              PopupMenuItem(
                value: 11,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.video_file_outlined),
                  title: Text('Descargar vídeos'),
                ),
              ),
              PopupMenuItem(
                value: 9,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Jam'),
                ),
              ),
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
          if (_webAudio?.needsWebsiteAccess == true)
            TextButton(
              onPressed: () => _webAudio?.setWebsiteVisible(true),
              child: const Text('Revisar sitio'),
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

  Widget _content(AppController c) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(offstage: [9, 10, 11].contains(_section), child: _page(c)),
      if (_musicVisited && c.usesOfficialYouTubeMusic)
        YouTubeMusicPage(
          key: _musicKey,
          initialUri: _musicUri,
          onClosed: _closeMusic,
        ),
      if (_videosVisited)
        Offstage(
          offstage: _section != 11,
          child: VideoDownloadsPage(
            key: const ValueKey('video-downloads-page'),
            source: c.source,
            supportDirectory: c.supportDirectory,
          ),
        ),
      if (_jamVisited)
        Offstage(
          key: const ValueKey('jam-session'),
          offstage: _section != 9,
          child: TickerMode(
            enabled: _section == 9,
            child: JamPage(
              key: const ValueKey('persistent-jam-page'),
              controller: c,
              onControllerReady: _jamCreated,
            ),
          ),
        ),
    ],
  );

  Widget _page(AppController c) {
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
      case 8:
        return DjDiscoveryPage(controller: c, onSearch: () => _navigate(1));
      case 12:
        return ArtistsPage(
          tracks: c.tracks,
          onPlay: c.playTrack,
          onSearch: (query) {
            _search.text = query;
            _navigate(1);
            if (query.isNotEmpty) _submitSearch(c, query);
          },
        );
      case 9:
      case 10:
      case 11:
        return const SizedBox.shrink();
      default:
        return _home(c);
    }
  }

  Widget _home(AppController c) => HomeMusicPage(
    onSearchQuery: (query) {
      _search.text = query;
      _spotifySearch = false;
      _navigate(1);
      _submitSearch(c, query);
    },
    controller: c,
    onSearch: () => _navigate(1),
    onDownloads: () => _navigate(3),
    onVinyl: () => _navigate(4),
    onLikes: () => setState(() {
      _section = 2;
      _likesSelected = true;
      _playlist = null;
    }),
    onOpenPlaylist: (playlist) => setState(() {
      _section = 2;
      _playlist = playlist;
      _likesSelected = false;
    }),
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

  Widget _jamPlaybackBar() => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          const Icon(Icons.groups_outlined),
          const Text('Reproducción controlada desde Jam'),
          TextButton(
            onPressed: () => _navigate(9),
            child: const Text('Abrir Jam'),
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
                label: Text(
                  c.usesOfficialYouTubeMusic
                      ? 'Biblioteca local'
                      : 'Audio · YouTube',
                ),
                selected: !_spotifySearch,
                onSelected: (_) => setState(() => _spotifySearch = false),
              ),
              ChoiceChip(
                label: const Text('Metadatos · Spotify'),
                selected: _spotifySearch,
                onSelected: (_) => setState(() => _spotifySearch = true),
              ),
              if (c.usesOfficialYouTubeMusic)
                ActionChip(
                  label: const Text('YouTube Music'),
                  avatar: const Icon(Icons.music_video_outlined),
                  onPressed: () => _navigate(10),
                ),
            ],
          ),
        ),
      ),
      Expanded(
        child: _spotifySearch
            ? SpotifyBrowserPanel(
                onQueue: (track) => c.usesOfficialYouTubeMusic
                    ? Future<void>.sync(
                        () => c.openYouTubeMusic(
                          Uri.https('music.youtube.com', '/search', {
                            'q': '${track.title} ${track.artist}',
                          }),
                        ),
                      )
                    : SpotifyMatchDialog.show(
                        context,
                        track: track,
                        saveLabel: 'Añadir a la cola',
                        playLabel: 'Reproducir',
                        onSearch: () => c.findSpotifyMatches(track),
                        onSave: (match, {required play}) =>
                            c.importSpotifyMetadataMatch(
                              track,
                              match,
                              play: play,
                            ),
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
            labelText: c.usesOfficialYouTubeMusic
                ? 'Buscar en tu biblioteca'
                : c.usesYouTubeWebAudio
                ? 'Canción, artista o enlace de YouTube Music'
                : 'Canción, artista o enlace',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              tooltip: 'Buscar',
              icon: const Icon(Icons.arrow_forward),
              onPressed: () => _submitSearch(c, _search.text),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (query) => _submitSearch(c, query),
          onChanged: (_) => setState(() {}),
        ),
      ),
      if (!c.usesOfficialYouTubeMusic && !c.usesYouTubeWebAudio)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final (kind, label) in const [
                  (SearchKind.songs, 'Canciones'),
                  (SearchKind.albums, 'Álbumes'),
                  (SearchKind.artists, 'Artistas'),
                  (SearchKind.videos, 'Vídeos'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: c.searchKind == kind,
                    onSelected: (_) => c.setSearchKind(kind),
                  ),
              ],
            ),
          ),
        ),
      if (c.searching) const LinearProgressIndicator(minHeight: 2),
      if (c.usesYouTubeWebAudio)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(
            'Busca canciones o pega el enlace de una canción. '
            'El streaming usa WebView; yt-dlp solo se usa para descargar vídeos.',
          ),
        ),
      if (!c.usesOfficialYouTubeMusic && !c.usesYouTubeWebAudio)
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
            final results = c.searchDetail != null
                ? _searchDetail(c, c.searchDetail!)
                : _searchFocus.hasFocus && _search.text.trim().isEmpty
                ? _recentSearchList(c)
                : _searchResults(c);
            if (!hasSidebar) return results;
            return Row(
              children: [
                SizedBox(width: 220, child: _recentSearchList(c)),
                const VerticalDivider(width: 1),
                Expanded(child: results),
              ],
            );
          },
        ),
      ),
    ],
  );

  Widget _recentSearchList(AppController c) {
    final recent = c.recentSearches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Búsquedas recientes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (recent.isNotEmpty)
              TextButton(
                onPressed: c.clearRecentSearches,
                child: const Text('Borrar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Text(
            'Tus búsquedas aparecerán aquí.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final query in recent)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 18),
              title: Text(query, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Quitar de recientes',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => c.removeRecentSearch(query),
              ),
              onTap: () {
                _search.text = query;
                _searchFocus.unfocus();
                _submitSearch(c, query);
              },
            ),
      ],
    );
  }

  Widget _searchResults(AppController c) {
    final entries =
        c.searchKind == SearchKind.albums || c.searchKind == SearchKind.artists;
    final count = entries ? c.searchEntries.length : c.searchResults.length;
    if (count == 0) {
      if (c.searchError != null && !c.searching) {
        return Column(
          children: [
            Expanded(
              child: _empty(
                Icons.error_outline,
                'No se pudo buscar',
                c.searchError!,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () => c.search(c.searchQuery),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ),
          ],
        );
      }
      final done = c.searchQuery.isNotEmpty && !c.searching;
      return _empty(
        Icons.travel_explore,
        c.searching
            ? 'Buscando tu próxima canción…'
            : done
            ? 'Sin resultados'
            : 'Encuentra algo que te mueva',
        c.searching
            ? 'La búsqueda puede tardar unos segundos.'
            : done
            ? 'Prueba con otro título o artista, o pega un enlace directo.'
            : 'Escribe un título, artista o pega un enlace compatible.',
      );
    }
    final hasFooter = c.hasMoreSearchResults || c.searchError != null;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: count + (hasFooter ? 1 : 0),
      itemBuilder: (_, i) {
        if (i < count) {
          return entries
              ? _entryTile(c, c.searchEntries[i])
              : _trackTile(c, c.searchResults[i], c.searchResults);
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (c.searchError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No se pudieron cargar más resultados: ${c.searchError}',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (c.hasMoreSearchResults)
                OutlinedButton.icon(
                  onPressed: c.searchLoadingMore ? null : c.loadMoreSearch,
                  icon: const Icon(Icons.expand_more),
                  label: Text(c.searchLoadingMore ? 'Cargando…' : 'Cargar más'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _entryTile(AppController c, SearchEntry entry) => ListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    leading: Artwork(
      track: Track(
        id: 'entry:${entry.browseId}',
        title: entry.title,
        artist: entry.subtitle,
        artworkUrl: entry.artworkUrl,
      ),
      artworkContext: ArtworkContext.thumbnail,
      radius: entry.kind == SearchKind.artists ? 28 : 8,
    ),
    title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      entry.subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => c.openSearchEntry(entry),
  );

  Widget _searchDetail(AppController c, SearchEntry entry) {
    final tracks = c.searchDetailTracks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Volver a los resultados',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => c.openSearchEntry(null),
              ),
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        if (c.searchDetailLoading) const LinearProgressIndicator(minHeight: 2),
        if (tracks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    onPressed: () => c.playTrack(tracks.first, context: tracks),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Reproducir todo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      for (final track in tracks) {
                        await c.addToQueue(track);
                      }
                    },
                    icon: const Icon(Icons.queue_music),
                    label: const Text('Añadir a la cola'),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: tracks.isNotEmpty
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tracks.length,
                  itemBuilder: (_, i) => _trackTile(c, tracks[i], tracks),
                )
              : c.searchDetailLoading
              ? _empty(Icons.album_outlined, 'Cargando…', entry.title)
              : _empty(
                  c.searchDetailError != null
                      ? Icons.error_outline
                      : Icons.music_off_outlined,
                  c.searchDetailError != null
                      ? 'No se pudo cargar'
                      : 'Sin canciones',
                  c.searchDetailError ?? 'Este resultado no tiene canciones.',
                ),
        ),
      ],
    );
  }

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
      leading: Artwork(
        track: t,
        artworkContext: ArtworkContext.thumbnail,
        radius: 8,
      ),
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
            ? '${t.artist} · ${c.usesOfficialYouTubeMusic ? 'Buscar en YouTube Music' : 'Elige una coincidencia de YouTube'}'
            : c.requiresOfficialYouTubeMusic(t)
            ? '${t.artist} · Abrir reproductor oficial'
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
                case 'next':
                  c.playNext(t);
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
              if (t.isPendingSpotifyMatch && !c.usesOfficialYouTubeMusic)
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
                value: 'next',
                child: Text('Reproducir a continuación'),
              ),
              const PopupMenuItem(
                value: 'playlist',
                child: Text('Añadir a una lista'),
              ),
              if (c.canDownloadTrack(t))
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

  Widget _downloads(AppController c) => DownloadsStudioPage(controller: c);

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
        title: 'Actualizaciones',
        subtitle: 'Nuevas versiones desde GitHub Releases',
        children: [UpdateSettings(controller: _updates)],
      ),
      (
        title: 'Música sin conexión',
        subtitle: 'Descargas explícitas y archivos locales',
        children: [
          if (c.usesOfficialYouTubeMusic) ...[
            const Text(
              'Los archivos locales y las descargas existentes siguen disponibles. YouTube Music reproduce en su página oficial; Aurora no descarga sus canciones.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _navigate(3),
              icon: const Icon(Icons.offline_pin_outlined),
              label: const Text('Gestionar archivos locales'),
            ),
            OutlinedButton.icon(
              onPressed: () => _navigate(11),
              icon: const Icon(Icons.video_file_outlined),
              label: const Text('Descargar vídeos con yt-dlp'),
            ),
          ] else
            OfflineSettingsPanel(
              controller: c,
              onManage: () => _navigate(3),
              onSearch: () => _navigate(1),
            ),
          if (c.usesYouTubeWebAudio) ...[
            const SizedBox(height: 12),
            const Text(
              'YouTube Music se escucha con los controles de Aurora mediante '
              'WebView. Las canciones locales siguen usando su motor nativo. '
              'La descarga de vídeos es una acción separada.',
            ),
            OutlinedButton.icon(
              onPressed: () => _navigate(11),
              icon: const Icon(Icons.video_file_outlined),
              label: const Text('Descargar vídeos con yt-dlp'),
            ),
          ],
        ],
      ),
      if (c.source.supportsExperimentalProgressivePlayback)
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
        subtitle: c.webPlayback
            ? 'El ecualizador aplica a archivos locales, no a YouTube Music'
            : !c.audio.supportsEqualizer
            ? 'El dispositivo no ofrece un ecualizador compatible'
            : c.eqEnabled
            ? 'Ecualizador activado'
            : 'Ecualizador desactivado',
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar ecualizador'),
            value: c.eqEnabled,
            onChanged: c.audio.supportsEqualizer ? c.setEqualizerEnabled : null,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Plano', 'Graves', 'Vocal', 'Rock']
                .map(
                  (name) => OutlinedButton(
                    onPressed: c.audio.supportsEqualizer
                        ? () => c.applyEqPreset(name)
                        : null,
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
        title: c.usesOfficialYouTubeMusic || c.usesYouTubeWebAudio
            ? 'Descargador de vídeos y diagnóstico'
            : 'Herramientas, sesión y diagnóstico',
        subtitle: 'Fuentes locales y utilidades opcionales',
        children: [
          Text(
            defaultTargetPlatform == TargetPlatform.android
                ? 'Herramientas integradas en este dispositivo'
                : c.source.toolDirectory == null
                ? 'Configura la carpeta de herramientas para las descargas explícitas de vídeos.'
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
              OutlinedButton.icon(
                onPressed:
                    c.source.updatingTools ||
                        c.busy ||
                        c.audio.isPlaying ||
                        c.audio.isBuffering
                    ? null
                    : c.source.checkForUpdates,
                icon: const Icon(Icons.system_update_alt),
                label: Text(
                  c.source.updatingTools
                      ? 'Comprobando nightly…'
                      : 'Comprobar yt-dlp nightly',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Nightly se comprueba automáticamente como máximo cada 24 horas, cuando no se reproduce música. Python, QuickJS y FFmpeg en Android se actualizan con la app.',
          ),
          if (c.source.toolUpdateMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.source.toolUpdateMessage!),
            ),
          if (c.diagnostics != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(c.diagnostics!),
            ),
          const SizedBox(height: 16),
          if (!c.usesOfficialYouTubeMusic && !c.usesYouTubeWebAudio)
            Text(
              c.hasYouTubeSession
                  ? 'Sesión de YouTube configurada'
                  : 'Sesión de YouTube opcional sin importar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          if (!c.usesOfficialYouTubeMusic && !c.usesYouTubeWebAudio)
            const Text(
              'Importa un archivo cookies.txt en formato Netscape exportado por ti de tu sesión de YouTube. Aurora guarda una copia local. Puedes reemplazarla o eliminarla desde aquí. Una sesión no garantiza resolver límites de YouTube ni errores 429.',
              style: TextStyle(height: 1.6),
            ),
          const SizedBox(height: 12),
          if (!c.usesOfficialYouTubeMusic && !c.usesYouTubeWebAudio)
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
                          Artwork(
                            track: t,
                            artworkContext: ArtworkContext.player,
                            radius: 24,
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
                            player.adPlaying
                                ? 'Anuncio · tu canción sigue después'
                                : t.artist,
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
                              if (player.canDownloadTrack(t))
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
                          leading: Artwork(
                            track: player.queue[i],
                            artworkContext: ArtworkContext.thumbnailCompact,
                          ),
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
                onChanged: player.audio.supportsEqualizer
                    ? player.setEqualizerEnabled
                    : null,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ['Plano', 'Graves', 'Vocal', 'Rock']
                    .map(
                      (name) => OutlinedButton(
                        onPressed: player.audio.supportsEqualizer
                            ? () => player.applyEqPreset(name)
                            : null,
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
      c.usesOfficialYouTubeMusic
      ? Future<void>.sync(
          () => c.openYouTubeMusic(
            Uri.https('music.youtube.com', '/search', {
              'q': '${track.title} ${track.artist}',
            }),
          ),
        )
      : SpotifyMatchDialog.show(
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
