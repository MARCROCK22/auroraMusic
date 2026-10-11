import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../lyrics/lyrics_service.dart';

Future<void> showLyrics(BuildContext context, AppController controller) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .86,
      child: LyricsPanel(controller: controller),
    ),
  );
}

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.controller,
    this.service,
    this.onClose,
  });
  final AppController controller;
  final LyricsService? service;
  final VoidCallback? onClose;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  late final LyricsService _service = widget.service ?? LyricsService();
  LyricsResult? _result;
  String? _error;
  bool _loading = false;
  String? _trackId;
  int _request = 0;
  int _lastActive = -1;
  final Map<int, GlobalKey> _lineKeys = {};
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  void _changed() {
    final track = widget.controller.currentTrack;
    if (track?.id == _trackId) return;
    _trackId = track?.id;
    _request++;
    _lastActive = -1;
    _lineKeys.clear();
    _loading = false;
    _result = null;
    _error = null;
    if (track != null) unawaited(_load(track));
    if (mounted) setState(() {});
  }

  Future<void> _load(Track track) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.load(
        track,
        widget.controller.supportDirectory,
      );
      if (!mounted ||
          request != _request ||
          widget.controller.currentTrack?.id != track.id) {
        return;
      }
      setState(() => _result = result);
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.controller.currentTrack?.id == track.id) {
        setState(() => _error = 'No se pudieron cargar las letras.');
      }
    } finally {
      if (mounted &&
          request == _request &&
          widget.controller.currentTrack?.id == track.id) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _import() async {
    final track = widget.controller.currentTrack;
    if (track == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.importFile(
        track,
        widget.controller.supportDirectory,
      );
      if (mounted &&
          request == _request &&
          widget.controller.currentTrack?.id == track.id &&
          result != null) {
        setState(() => _result = result);
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.controller.currentTrack?.id == track.id) {
        setState(() => _error = 'No se pudo importar el archivo.');
      }
    } finally {
      if (mounted &&
          request == _request &&
          widget.controller.currentTrack?.id == track.id) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.controller.currentTrack;
    final media = MediaQuery.of(context);
    final lines = _result?.lines ?? const <LyricLine>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 720;
        final color = Theme.of(context).colorScheme;
        final lyrics = Expanded(
          child: ListenableBuilder(
            listenable: widget.controller.audio,
            builder: (context, _) {
              final position = widget.controller.audio.position;
              final active = lines.lastIndexWhere(
                (line) => line.at <= position,
              );
              return _body(track, lines, active, position, media);
            },
          ),
        );
        final header = Row(
          children: [
            Expanded(
              child: Text(
                'Letras',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Importar archivo LRC o TXT',
              onPressed: _loading ? null : _import,
              icon: const Icon(Icons.file_open),
            ),
            IconButton(
              tooltip: 'Cerrar letras',
              onPressed:
                  widget.onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
          ],
        );
        final artwork = track == null
            ? const SizedBox.shrink()
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: desktop ? 260 : 72,
                  height: desktop ? 260 : 72,
                  child: _artwork(track),
                ),
              );
        final trackInfo = track == null
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color.onSurfaceVariant),
                  ),
                ],
              );
        if (desktop) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 310,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const SizedBox(height: 28),
                        artwork,
                        trackInfo,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 40),
                lyrics,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: [
              header,
              if (track != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      artwork,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '${track.title}\n${track.artist}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              lyrics,
            ],
          ),
        );
      },
    );
  }

  Widget _artwork(Track track) {
    final url = track.artworkUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(
        color: Color(0xff302923),
        child: Icon(Icons.music_note),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xff302923),
        child: Icon(Icons.music_note),
      ),
    );
  }

  Widget _body(
    Track? track,
    List<LyricLine> lines,
    int active,
    Duration pos,
    MediaQueryData media,
  ) {
    if (track == null) {
      return const Center(child: Text('No hay una pista en reproducción.'));
    }
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(semanticsLabel: 'Cargando letras'),
      );
    }
    if (_error != null) return _message(_error!, retry: () => _load(track));
    final result = _result;
    if (result == null || result.kind == LyricsKind.notFound) {
      return _message('No se encontraron letras.', retry: () => _load(track));
    }
    if (result.kind == LyricsKind.instrumental) {
      return const Center(child: Text('Pista instrumental'));
    }
    if (result.kind == LyricsKind.plain) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          result.text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Newsreader',
            fontSize: 24,
            height: 1.65,
          ),
        ),
      );
    }
    if (active >= 0 && active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _lineKeys[active]?.currentContext;
        if (mounted && context != null) {
          Scrollable.ensureVisible(
            context,
            duration: media.disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            alignment: .5,
          );
        }
      });
    }
    return ListView.builder(
      key: ValueKey(track.id),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final key = _lineKeys.putIfAbsent(index, GlobalKey.new);
        final highlighted = index == active;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Semantics(
            key: key,
            liveRegion: highlighted,
            child: Text(
              lines[index].text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Newsreader',
                fontSize: highlighted ? 34 : 25,
                height: 1.45,
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w400,
                color: highlighted
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _message(String value, {required VoidCallback retry}) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              TextButton.icon(
                onPressed: _import,
                icon: const Icon(Icons.file_open),
                label: const Text('Importar LRC o TXT'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
