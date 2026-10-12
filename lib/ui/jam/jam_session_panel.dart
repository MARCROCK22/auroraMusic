import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../artwork.dart';

class JamSessionPanel extends StatefulWidget {
  const JamSessionPanel({super.key, required this.controller});
  final JamController controller;
  @override
  State<JamSessionPanel> createState() => _JamSessionPanelState();
}

class _JamSessionPanelState extends State<JamSessionPanel> {
  final _query = TextEditingController();
  double? _seekPreview;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _modeAndPlayer(widget.controller),
        const SizedBox(height: 24),
        _people(widget.controller),
        const SizedBox(height: 24),
        _queue(widget.controller),
        const SizedBox(height: 24),
        _addMusic(widget.controller),
      ],
    ),
  );
  Widget _modeAndPlayer(JamController c) {
    final s = c.service;
    final playback = s.playback;
    final entry = s.queue
        .where((entry) => entry.id == playback?.entryId)
        .firstOrNull;
    final duration = widget.controller.app.audio.duration.inMilliseconds;
    final position =
        (_seekPreview ??
                widget.controller.app.audio.position.inMilliseconds.toDouble())
            .clamp(0.0, duration > 0 ? duration.toDouble() : 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Modo de la sesión',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (s.isHost)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: JamMode.values
                .map(
                  (mode) => ChoiceChip(
                    selected: s.mode == mode,
                    label: Text(
                      mode == JamMode.queueOnly
                          ? 'Cola compartida'
                          : 'Reproducción sincronizada',
                    ),
                    onSelected: c.busy ? null : (_) => c.setMode(mode),
                  ),
                )
                .toList(),
          )
        else
          Text(
            s.mode == JamMode.queueOnly
                ? 'Cola compartida · el anfitrión decide qué suena'
                : 'Reproducción sincronizada · controles del anfitrión',
          ),
        if (!s.isHost && s.mode == JamMode.synchronized)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reproducir en este dispositivo'),
            value: c.bridge.enabled,
            onChanged: c.busy || !s.connected ? null : c.setListening,
            subtitle: const Text(
              'Aurora resolverá cada canción con tus propias fuentes de audio.',
            ),
          ),
        if (s.mode == JamMode.synchronized) ...[
          const SizedBox(height: 8),
          const Text(
            'Las versiones y los tiempos de carga pueden diferir. La sincronía es aproximada, con correcciones pequeñas y espaciadas.',
          ),
          if (s.roundTripMs != null) Text('Demora de red: ${s.roundTripMs} ms'),
        ],
        if (c.bridge.warning != null) ...[
          const SizedBox(height: 12),
          jamNotice(
            context,
            c.bridge.warning!,
            Icons.headphones_outlined,
            action: TextButton(
              onPressed: c.busy ? null : c.bridge.retry,
              child: const Text('Reintentar audio'),
            ),
          ),
        ],
        if (c.bridge.loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (entry != null) ...[
          const SizedBox(height: 16),
          Text(
            entry.track.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(entry.track.artist),
          if (s.isHost) ...[
            Wrap(
              spacing: 8,
              children: [
                IconButton(
                  tooltip: widget.controller.app.audio.isPlaying
                      ? 'Pausar Jam'
                      : 'Reproducir Jam',
                  onPressed: c.busy ? null : c.togglePlayback,
                  icon: Icon(
                    widget.controller.app.audio.isPlaying
                        ? Icons.pause_circle
                        : Icons.play_circle,
                  ),
                ),
                IconButton(
                  tooltip: 'Siguiente en la Jam',
                  onPressed: c.busy ? null : c.next,
                  icon: const Icon(Icons.skip_next),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${_duration(position.toInt())} / ${_duration(duration)}',
                  ),
                ),
              ],
            ),
            if (duration > 0)
              Slider(
                value: position,
                max: duration.toDouble(),
                label: _duration(position.toInt()),
                onChanged: c.busy
                    ? null
                    : (value) => setState(() => _seekPreview = value),
                onChangeEnd: (value) async {
                  await c.seek(Duration(milliseconds: value.toInt()));
                  if (mounted) setState(() => _seekPreview = null);
                },
              ),
          ] else
            Text(
              playback?.isPlaying == true
                  ? 'El anfitrión está reproduciendo'
                  : 'El anfitrión pausó la reproducción',
            ),
        ],
      ],
    );
  }

  Widget _people(JamController c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Participantes · ${c.service.participants.where((p) => p.connected).length}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      ...c.service.participants.map(
        (person) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            person.connected ? Icons.person_outline : Icons.person_off_outlined,
          ),
          title: Text(person.name),
          subtitle: Text(
            person.id == 'host'
                ? 'Anfitrión'
                : person.connected
                ? 'Conectado'
                : 'Desconectado',
          ),
          trailing: c.service.isHost && person.id != 'host'
              ? IconButton(
                  tooltip: 'Permisos de ${person.name}',
                  onPressed: () => _permissions(c, person),
                  icon: const Icon(Icons.tune),
                )
              : null,
        ),
      ),
    ],
  );
  Future<void> _permissions(JamController c, JamParticipant person) async {
    var permissions = person.permissions;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Permisos de ${person.name}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Todos pueden agregar canciones. Tú decides los demás controles.',
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Omitir canciones'),
                  value: permissions.skip,
                  onChanged: (value) => setDialogState(
                    () => permissions = JamPermissions(
                      skip: value!,
                      reorder: permissions.reorder,
                      remove: permissions.remove,
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reordenar la cola'),
                  value: permissions.reorder,
                  onChanged: (value) => setDialogState(
                    () => permissions = JamPermissions(
                      skip: permissions.skip,
                      reorder: value!,
                      remove: permissions.remove,
                    ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quitar canciones'),
                  value: permissions.remove,
                  onChanged: (value) => setDialogState(
                    () => permissions = JamPermissions(
                      skip: permissions.skip,
                      reorder: permissions.reorder,
                      remove: value!,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                c.setPermissions(person.id, permissions);
                Navigator.pop(context);
              },
              child: const Text('Guardar permisos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _queue(JamController c) {
    final s = c.service;
    final permissions = s.me?.permissions ?? const JamPermissions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Cola compartida · ${s.queue.length}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (!s.isHost && permissions.skip)
              TextButton.icon(
                onPressed: s.connected ? c.next : null,
                icon: const Icon(Icons.skip_next),
                label: const Text('Omitir'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (s.queue.isEmpty)
          jamNotice(
            context,
            'Agrega una canción desde tu biblioteca o búscala aquí. Todos verán la misma cola.',
            Icons.queue_music,
          ),
        ...s.queue.asMap().entries.map((item) {
          final entry = item.value;
          final track = Track(
            id: entry.track.key,
            title: entry.track.title,
            artist: entry.track.artist,
            artworkUrl: entry.track.artworkUrl,
          );
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Artwork(track: track, size: 44, radius: 8),
            title: Text(
              entry.track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${entry.track.artist}\nAgregada por ${s.participantName(entry.addedBy)}${entry.track.localOnly ? ' · archivo local' : ''}',
            ),
            trailing: PopupMenuButton<String>(
              tooltip: 'Acciones de ${entry.track.title}',
              enabled: s.connected,
              onSelected: (action) {
                switch (action) {
                  case 'play':
                    c.play(entry);
                  case 'up':
                    c.reorder(entry, item.key - 1);
                  case 'down':
                    c.reorder(entry, item.key + 1);
                  case 'remove':
                    c.remove(entry);
                }
              },
              itemBuilder: (_) => [
                if (s.isHost)
                  const PopupMenuItem(
                    value: 'play',
                    child: Text('Reproducir en la Jam'),
                  ),
                if (permissions.reorder && item.key > 0)
                  const PopupMenuItem(
                    value: 'up',
                    child: Text('Subir en la cola'),
                  ),
                if (permissions.reorder && item.key + 1 < s.queue.length)
                  const PopupMenuItem(
                    value: 'down',
                    child: Text('Bajar en la cola'),
                  ),
                if (permissions.remove)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Quitar de la cola'),
                  ),
                if (!s.isHost && !permissions.reorder && !permissions.remove)
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('Controles del anfitrión'),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _addMusic(JamController c) {
    final tracks = c.results.isEmpty && _query.text.trim().isEmpty
        ? widget.controller.app.tracks
        : c.results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Agregar música', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: c.search,
          decoration: InputDecoration(
            labelText: 'Buscar con tus fuentes de audio',
            suffixIcon: IconButton(
              tooltip: 'Buscar canciones',
              onPressed: c.searching ? null : () => c.search(_query.text),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (c.searching) const LinearProgressIndicator(),
        if (tracks.isEmpty && !c.searching)
          Text(
            _query.text.trim().isEmpty
                ? 'Tu biblioteca está vacía. Busca una canción para agregarla.'
                : 'No encontramos canciones para esta búsqueda.',
          ),
        ...tracks
            .take(20)
            .map(
              (track) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Artwork(track: track, size: 44, radius: 8),
                title: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(track.artist),
                trailing: IconButton(
                  tooltip: 'Agregar ${track.title} a la Jam',
                  onPressed: c.service.connected ? () => c.add(track) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ),
            ),
      ],
    );
  }

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

Widget jamNotice(
  BuildContext context,
  String message,
  IconData icon, {
  Widget? action,
}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Icon(icon, size: 22),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Text(message),
      ),
      ?action,
    ],
  ),
);
