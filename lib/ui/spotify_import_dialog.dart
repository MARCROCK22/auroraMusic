import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../import/spotify_import.dart';

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({
    super.key,
    required this.result,
    required this.onImport,
  });

  final SpotifyImportResult result;
  final Future<void> Function(List<SpotifyImportPlaylist>) onImport;

  static Future<void> show(
    BuildContext context, {
    required SpotifyImportResult result,
    required Future<void> Function(List<SpotifyImportPlaylist>) onImport,
  }) => showDialog<void>(
    context: context,
    builder: (_) => SpotifyImportDialog(result: result, onImport: onImport),
  );

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.result.playlists.length; i++) i,
  };
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final playlists = widget.result.playlists;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Importar listas de Spotify'),
      scrollable: true,
      content: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width * .78, 520),
        height: math.min(MediaQuery.sizeOf(context).height * .45, 360),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Elige listas del archivo Spotify Account Data (JSON) o CSV. Se copian los nombres y datos de canciones; el audio no se importa.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: playlists.isEmpty
                  ? const Center(
                      child: Text('No se encontraron canciones importables.'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _selected.contains(index),
                          onChanged: _importing
                              ? null
                              : (selected) => setState(() {
                                  if (selected == true) {
                                    _selected.add(index);
                                  } else {
                                    _selected.remove(index);
                                  }
                                }),
                          title: Text(
                            playlist.name.isEmpty
                                ? 'Lista sin nombre'
                                : playlist.name,
                          ),
                          subtitle: Text('${playlist.tracks.length} canciones'),
                        );
                      },
                    ),
            ),
            if (widget.result.skipped > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${widget.result.skipped} elementos omitidos (podcasts, archivos locales o datos incompletos).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _importing || _selected.isEmpty
              ? null
              : () async {
                  setState(() => _importing = true);
                  final selected = [
                    for (var i = 0; i < playlists.length; i++)
                      if (_selected.contains(i)) playlists[i],
                  ];
                  try {
                    await widget.onImport(selected);
                    if (context.mounted) Navigator.pop(context);
                  } finally {
                    if (mounted) setState(() => _importing = false);
                  }
                },
          child: _importing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Importar ${_selected.length} '
                  '${_selected.length == 1 ? 'lista' : 'listas'}',
                ),
        ),
      ],
    );
  }
}
