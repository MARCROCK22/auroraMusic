import 'package:flutter/foundation.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'recommendations.dart';

/// Session-only card choices. Skipping is not a recorded playback event.
class DjDiscoveryController extends ChangeNotifier {
  DjDiscoveryController(this.app) {
    app.addListener(_changed);
  }

  final AppController app;
  final Set<String> _seen = {};
  TrackRecommendation? _pending;
  TrackRecommendation? _failed;
  bool _disposed = false;
  bool get busy => _pending != null;
  String? error;
  int added = 0;
  int skipped = 0;

  TrackRecommendation? get current {
    if (_pending != null) return _pending;
    final candidates = [
      ?_failed,
      ...app.recommendations,
      for (final track in app.discoveredRecommendations)
        TrackRecommendation(
          track: track,
          reason: 'Novedad del proveedor de audio',
        ),
    ];
    for (final candidate in candidates) {
      final track = candidate.track;
      if (!track.isPendingSpotifyMatch &&
          (track.isLocal || track.pageUrl != null) &&
          app.djFilters.permits(track) &&
          !recommendationTrackKeys(track).any(_seen.contains)) {
        return candidate;
      }
    }
    return null;
  }

  bool _isCurrent(Track track) => !busy && current?.track.id == track.id;

  void skip(Track track) {
    if (!_isCurrent(track)) return;
    _seen.addAll(recommendationTrackKeys(track));
    _failed = null;
    skipped++;
    error = null;
    _changed();
  }

  Future<void> accept(Track track) async {
    if (!_isCurrent(track)) return;
    _pending = current;
    error = null;
    _changed();
    try {
      // A right swipe expresses interest; never toggle an existing like off.
      if (!app.favoriteIds.contains(track.id)) await app.toggleFavorite(track);
      if (!app.favoriteIds.contains(track.id)) {
        throw StateError('Favorite could not be saved');
      }
      await app.addToQueue(track);
      _seen.addAll(recommendationTrackKeys(track));
      _failed = null;
      added++;
    } catch (_) {
      _failed = _pending;
      error = 'No pudimos guardar esta elección. Intenta de nuevo.';
    } finally {
      _pending = null;
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    app.removeListener(_changed);
    super.dispose();
  }
}
