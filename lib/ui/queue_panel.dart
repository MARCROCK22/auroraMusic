import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final player = _CurrentTrack(
          controller: controller,
          track: controller.currentTrack,
        );
        final queue = _QueueList(controller: controller, bounded: !narrow);
        if (narrow) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [player, const SizedBox(height: 28), queue],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 310, child: SingleChildScrollView(child: player)),
              const SizedBox(width: 24),
              Expanded(child: queue),
            ],
          ),
        );
      },
    ),
  );
}

class _CurrentTrack extends StatelessWidget {
  const _CurrentTrack({required this.controller, required this.track});
  final AppController controller;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final audio = controller.audio;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SONANDO AHORA',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Artwork(track: track),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            track?.title ?? 'Nada sonando',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(_time(audio.position)),
              Expanded(
                child: Slider(
                  semanticFormatterCallback: (value) =>
                      'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                  min: 0,
                  max:
                      (audio.duration.inMilliseconds > 0
                              ? audio.duration.inMilliseconds
                              : 1)
                          .toDouble(),
                  value: audio.position.inMilliseconds
                      .clamp(
                        0,
                        audio.duration.inMilliseconds > 0
                            ? audio.duration.inMilliseconds
                            : 1,
                      )
                      .toDouble(),
                  onChanged: track == null || audio.duration <= Duration.zero
                      ? null
                      : (value) => controller.seek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
              Text(_time(audio.duration)),
            ],
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: track == null ? null : controller.previous,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  tooltip: audio.isPlaying ? 'Pausar' : 'Reproducir',
                  onPressed: track == null ? null : controller.togglePlayback,
                  icon: Icon(audio.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: track == null ? null : controller.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({required this.controller, required this.bounded});
  final AppController controller;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final start = controller.queueIndex < 0 ? 0 : controller.queueIndex + 1;
    final upcoming = controller.queue.skip(start).toList();
    final heading = Row(
      children: [
        Expanded(
          child: Text(
            'A continuación',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Text(
          '${upcoming.length} canciones',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
    if (!bounded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 12),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay canciones en la cola')),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: upcoming.length,
              onReorder: (oldIndex, newIndex) =>
                  controller.reorderQueue(start + oldIndex, start + newIndex),
              itemBuilder: (context, index) =>
                  _tile(context, upcoming[index], start + index),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 12),
        if (upcoming.isEmpty)
          const Expanded(
            child: Center(child: Text('No hay canciones en la cola')),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              itemCount: upcoming.length,
              onReorder: (oldIndex, newIndex) =>
                  controller.reorderQueue(start + oldIndex, start + newIndex),
              itemBuilder: (context, index) =>
                  _tile(context, upcoming[index], start + index),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, Track track, int queueIndex) => ListTile(
    key: ValueKey('$queueIndex:${track.id}'),
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    leading: SizedBox(
      width: 48,
      height: 48,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: _Artwork(track: track),
      ),
    ),
    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_time(track.duration)),
        PopupMenuButton<String>(
          tooltip: 'Acciones de la pista',
          onSelected: (action) {
            if (action == 'remove') controller.removeFromQueue(queueIndex);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'remove', child: Text('Quitar de la cola')),
          ],
          icon: const Icon(Icons.more_vert),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.drag_handle),
      ],
    ),
    onTap: () => controller.playQueueAt(queueIndex),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});
  final Track? track;
  @override
  Widget build(BuildContext context) {
    final url = track?.artworkUrl;
    if (url == null || url.isEmpty) {
      return const ColoredBox(
        color: Color(0xff302923),
        child: Center(child: Icon(Icons.music_note)),
      );
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xff302923),
        child: Center(child: Icon(Icons.music_note)),
      ),
    );
  }
}

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
