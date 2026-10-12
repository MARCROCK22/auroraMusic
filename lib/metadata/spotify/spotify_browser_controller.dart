import 'package:flutter/foundation.dart';
import '../../core/models.dart';
import 'spotify_metadata_provider.dart';

/// Owns metadata UI state; playback and matching remain in Aurora's controller.
class SpotifyBrowserController extends ChangeNotifier {
  SpotifyBrowserController({SpotifyMetadataProvider? provider})
    : _provider = provider ?? SpotifyMetadataProvider();
  final SpotifyMetadataProvider _provider;
  String query = '';
  SpotifyEntityType type = SpotifyEntityType.track;
  SpotifyMetadataPage? page;
  SpotifyMetadataDetails? detail;
  bool loading = false;
  bool detailLoading = false;
  String? error;
  String? detailError;
  int _searchGeneration = 0;
  int _detailGeneration = 0;
  bool _disposed = false;
  List<SpotifyMetadataEntity> get items => page?.items ?? const [];

  Future<void> search(String value, {SpotifyEntityType? type}) async {
    final generation = ++_searchGeneration;
    query = value.trim();
    this.type = type ?? this.type;
    page = null;
    detail = null;
    _detailGeneration++;
    detailLoading = false;
    detailError = null;
    error = null;
    loading = query.isNotEmpty;
    _notify();
    if (!loading) return;
    try {
      final result = await _provider.search(query, type: this.type);
      if (!_disposed && generation == _searchGeneration) page = result;
    } catch (failure) {
      if (!_disposed && generation == _searchGeneration) {
        error = _message(failure);
      }
    } finally {
      if (!_disposed && generation == _searchGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    final current = page;
    if (loading || current?.nextOffset == null || _disposed) return;
    final generation = _searchGeneration;
    loading = true;
    error = null;
    _notify();
    try {
      final result = await _provider.search(
        query,
        type: type,
        offset: current!.nextOffset!,
      );
      if (!_disposed && generation == _searchGeneration) {
        final seen = <String>{};
        page = SpotifyMetadataPage(
          items: [
            ...current.items,
            ...result.items,
          ].where((entity) => seen.add(entity.uri)).toList(),
          total: result.total,
          offset: 0,
          nextOffset: result.nextOffset,
        );
      }
    } catch (failure) {
      if (!_disposed && generation == _searchGeneration) {
        error = _message(failure);
      }
    } finally {
      if (!_disposed && generation == _searchGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> openDetails(SpotifyMetadataEntity entity) async {
    final generation = ++_detailGeneration;
    detail = null;
    detailLoading = true;
    detailError = null;
    _notify();
    try {
      final result = await _provider.details(entity);
      if (!_disposed && generation == _detailGeneration) detail = result;
    } catch (failure) {
      if (!_disposed && generation == _detailGeneration) {
        detailError = _message(failure);
      }
    } finally {
      if (!_disposed && generation == _detailGeneration) {
        detailLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadMoreDetails() async {
    final current = detail;
    if (detailLoading || current?.nextOffset == null || _disposed) return;
    final generation = _detailGeneration;
    detailLoading = true;
    detailError = null;
    _notify();
    try {
      final result = await _provider.details(
        current!.entity,
        offset: current.nextOffset!,
      );
      if (!_disposed && generation == _detailGeneration) {
        final seen = <String>{};
        detail = SpotifyMetadataDetails(
          entity: result.entity,
          description: result.description,
          tracks: <Track>[
            ...current.tracks,
            ...result.tracks,
          ].where((track) => seen.add(track.id)).toList(),
          total: result.total,
          nextOffset: result.nextOffset,
        );
      }
    } catch (failure) {
      if (!_disposed && generation == _detailGeneration) {
        detailError = _message(failure);
      }
    } finally {
      if (!_disposed && generation == _detailGeneration) {
        detailLoading = false;
        _notify();
      }
    }
  }

  void closeDetails() {
    _detailGeneration++;
    detail = null;
    detailLoading = false;
    detailError = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _message(Object failure) => failure is SpotifyMetadataException
      ? failure.message
      : 'No se pudieron cargar los metadatos de Spotify.';
  @override
  void dispose() {
    _disposed = true;
    _provider.close();
    super.dispose();
  }
}
