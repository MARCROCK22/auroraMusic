import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/playlist_views/playlist_cover.dart';
import '../ui/playlist_views/playlist_photo_menu.dart';
import '../ui/playlist_views/playlist_view_mode.dart';
import 'brasa_theme.dart';

/// Sección «PLAYLISTS» de la barra lateral Brasa: cabecera + crear, buscador
/// (solo con listas suficientes) y lista con scroll propio.
class BrasaSidebarPlaylists extends StatefulWidget {
  const BrasaSidebarPlaylists({
    super.key,
    required this.controller,
    required this.onPlaylist,
    this.onCreate,
  });
  final AppController controller;
  final ValueChanged<MusicPlaylist> onPlaylist;
  final VoidCallback? onCreate;

  @override
  State<BrasaSidebarPlaylists> createState() => _BrasaSidebarPlaylistsState();
}

class _BrasaSidebarPlaylistsState extends State<BrasaSidebarPlaylists> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = [...widget.controller.playlists];
    // «Me gusta» siempre primero.
    all.sort((a, b) {
      int rank(MusicPlaylist p) =>
          p.name.trim().toLowerCase() == 'me gusta' ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(q)).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Brasa.obsidian,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'PLAYLISTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: Brasa.steel,
                    ),
                  ),
                ),
                if (widget.onCreate != null)
                  IconButton(
                    tooltip: 'Crear lista',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add, size: 20, color: Brasa.cloud),
                  ),
              ],
            ),
          ),
          if (all.length > 5)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(fontSize: 13, color: Brasa.cream),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar en listas',
                  hintStyle: const TextStyle(fontSize: 13, color: Brasa.steel),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: Brasa.steel,
                  ),
                  filled: true,
                  fillColor: Brasa.graphite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      all.isEmpty ? 'Aún no hay listas' : 'Sin resultados',
                      style: const TextStyle(fontSize: 12, color: Brasa.steel),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final p = list[i];
                      final n = p.trackIds.length;
                      return PlaylistPhotoMenu(
                        controller: widget.controller,
                        playlist: p,
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            hoverColor: Brasa.graphite,
                            onTap: () => widget.onPlaylist(p),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: PlaylistCover(
                                      playlist: p,
                                      tracks: playlistCoverTracks(
                                        widget.controller,
                                        p,
                                      ),
                                      size: 44,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Brasa.cream,
                                          ),
                                        ),
                                        Text(
                                          n == 1 ? '1 canción' : '$n canciones',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Brasa.steel,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
