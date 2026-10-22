import 'package:flutter/material.dart';

import '../../app_controller.dart';
import 'playlist_view_mode.dart';

/// Ajuste reutilizable: cómo se muestran las playlists. Guarda en preferencias.
class PlaylistViewModeTile extends StatelessWidget {
  const PlaylistViewModeTile({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    loadPlaylistViewMode(controller.preferences);
    return ValueListenableBuilder<PlaylistViewMode>(
      valueListenable: playlistViewMode,
      builder: (context, mode, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vista de playlists',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<PlaylistViewMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in PlaylistViewMode.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  savePlaylistViewMode(controller.preferences, s.first),
            ),
          ],
        ),
      ),
    );
  }
}
