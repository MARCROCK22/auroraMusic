import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../app_controller.dart';
import '../core/source_backend.dart';
import '../sources/innertube_source.dart';
import 'follow_repository.dart';
import 'follow_service.dart';

/// Artistas seguidos y novedades. Se crea con el controlador ya iniciado.
final followServiceProvider = ChangeNotifierProvider<FollowService>((ref) {
  final c = ref.read(controllerProvider);
  final source = c.source;
  return FollowService(
    repository: FollowRepository(c.database),
    fetchArtist: (id) => source is InnerTubeSource
        ? source.artistPage(id)
        : Future.error(StateError('La fuente no ofrece páginas de artista.')),
    findArtist: (name) async =>
        (await source.searchPage(name, SearchKind.artists)).entries,
  );
});

/// Punto de enganche del DJ: claves de artistas seguidos para
/// `followedArtistBonus` (ver docs/follow_artists.md).
final followedArtistKeysProvider = Provider<Set<String>>(
  (ref) => ref.watch(followServiceProvider).followedArtistKeys,
);
