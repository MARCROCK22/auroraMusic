import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../dj/discovery_controller.dart';
import '../dj/dj_modes.dart';
import 'artwork.dart';
import 'dj_filters_panel.dart';

class DjDiscoveryPage extends StatefulWidget {
  const DjDiscoveryPage({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final AppController controller;
  final VoidCallback onSearch;

  @override
  State<DjDiscoveryPage> createState() => _DjDiscoveryPageState();
}

class _DjDiscoveryPageState extends State<DjDiscoveryPage> {
  late DjDiscoveryController _discovery;
  int? _pointer;
  Offset? _start;
  Offset _delta = Offset.zero;
  double _verticalTravel = 0;
  Track? _dragTrack;

  @override
  void initState() {
    super.initState();
    _discovery = DjDiscoveryController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant DjDiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _discovery.dispose();
      _discovery = DjDiscoveryController(widget.controller);
    }
  }

  @override
  void dispose() {
    _discovery.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      widget.controller.reducedMotion ||
      MediaQuery.disableAnimationsOf(context);

  void _resetDrag() {
    _pointer = null;
    _start = null;
    _dragTrack = null;
    _delta = Offset.zero;
    _verticalTravel = 0;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _discovery,
    builder: (context, _) {
      final c = widget.controller;
      final recommendation = _discovery.current;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Descubre tu próxima canción',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'A la izquierda, omitir. A la derecha, guardar en favoritos y añadir a la cola. Tú decides qué escuchar.',
          ),
          const SizedBox(height: 24),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: recommendation == null
                  ? _empty()
                  : _card(recommendation.track, recommendation.reason),
            ),
          ),
          const SizedBox(height: 16),
          if (_discovery.added + _discovery.skipped > 0)
            Text(
              '${_discovery.added} añadidas · ${_discovery.skipped} omitidas en esta sesión',
              textAlign: TextAlign.center,
            ),
          if (_discovery.error != null) _error(_discovery.error!),
          if (c.recommendationDiscoveryError != null)
            _error(c.recommendationDiscoveryError!),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: c.discoveringRecommendations
                    ? null
                    : c.canDiscoverRecommendations
                    ? c.refreshRecommendations
                    : null,
                icon: c.discoveringRecommendations
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.explore_outlined),
                label: Text(
                  c.discoveringRecommendations
                      ? 'Buscando novedades…'
                      : 'Buscar novedades',
                ),
              ),
              TextButton.icon(
                onPressed: widget.onSearch,
                icon: const Icon(Icons.search),
                label: const Text('Buscar música'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in DjMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: c.djMode == mode,
                  onSelected: (_) => c.setDjMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DjFiltersPanel(controller: c),
        ],
      );
    },
  );

  Widget _error(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        const Icon(Icons.error_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ],
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        Icon(
          Icons.explore_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
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

  Widget _card(Track track, String reason) => Listener(
    key: const ValueKey('dj-discovery-card'),
    onPointerDown: (event) {
      if (_pointer != null || _discovery.busy) return;
      _pointer = event.pointer;
      _start = event.position;
      _dragTrack = track;
      _verticalTravel = 0;
    },
    onPointerMove: (event) {
      if (_pointer != event.pointer || _start == null) return;
      setState(() {
        _delta = event.position - _start!;
        _verticalTravel = math.max(_verticalTravel, _delta.dy.abs());
      });
    },
    onPointerCancel: (_) => setState(_resetDrag),
    onPointerUp: (event) {
      if (_pointer != event.pointer) return;
      final choice = _dragTrack;
      final dx = _delta.dx;
      final horizontal = dx.abs() >= 80 && dx.abs() > _verticalTravel * 1.5;
      setState(_resetDrag);
      if (!horizontal || choice == null) return;
      if (dx < 0) {
        _discovery.skip(choice);
      } else {
        _discovery.accept(choice);
      }
    },
    child: Transform.translate(
      offset: _reduceMotion
          ? Offset.zero
          : Offset(_delta.dx.clamp(-20, 20).toDouble(), 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Artwork(
                    track: track,
                    artworkContext: ArtworkContext.playerCompact,
                    radius: 12,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  track.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  track.artist,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (track.album?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 8),
                  Text(track.album!),
                ],
                if (track.genres.isNotEmpty ||
                    track.duration > Duration.zero) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      ...track.genres,
                      if (track.duration > Duration.zero)
                        '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                    ].join(' · '),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  reason,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('dj-discovery-skip'),
                      onPressed: _discovery.busy
                          ? null
                          : () => _discovery.skip(track),
                      icon: const Icon(Icons.close),
                      label: const Text('Omitir'),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('dj-discovery-add'),
                      onPressed: _discovery.busy
                          ? null
                          : () => _discovery.accept(track),
                      icon: const Icon(Icons.favorite_border),
                      label: Text(
                        _discovery.busy ? 'Guardando…' : 'Añadir y seguir',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
