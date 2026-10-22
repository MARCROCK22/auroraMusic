import 'listenbrainz_client.dart';

enum StatsRange {
  week('this_week', 'Semana'),
  month('this_month', 'Mes'),
  year('this_year', 'Año'),
  all('all_time', 'Todo');

  const StatsRange(this.api, this.label);
  final String api, label;
}

class StatItem {
  const StatItem(this.name, this.count, {this.subtitle});
  final String name;
  final int count;
  final String? subtitle;

  Map<String, Object?> toJson() => {'n': name, 'c': count, 's': subtitle};
  static StatItem fromJson(Map j) =>
      StatItem(j['n'] as String, j['c'] as int, subtitle: j['s'] as String?);
}

class ListenStats {
  const ListenStats({
    this.totalListens = 0,
    this.recordings = const [],
    this.artists = const [],
    this.releases = const [],
    this.activity = const [],
    this.hourly = const [],
    this.genres = const [],
    this.streakDays = 0,
  });
  final int totalListens;
  final List<StatItem> recordings, artists, releases, genres;

  /// Escuchas por tramo (día/mes según el rango), en orden cronológico.
  final List<int> activity;

  /// 24 posiciones (hora UTC) o vacío sin datos.
  final List<int> hourly;
  final int streakDays;

  StatItem? get topTrack => recordings.isEmpty ? null : recordings.first;
  StatItem? get topArtist => artists.isEmpty ? null : artists.first;
  StatItem? get topGenre => genres.isEmpty ? null : genres.first;

  /// Hora (UTC) con más escuchas, o null sin datos.
  int? get favoriteHour {
    if (hourly.isEmpty || hourly.every((v) => v == 0)) return null;
    var best = 0;
    for (var i = 1; i < hourly.length; i++) {
      if (hourly[i] > hourly[best]) best = i;
    }
    return best;
  }

  Map<String, Object?> toJson() => {
    't': totalListens,
    'r': [for (final i in recordings) i.toJson()],
    'a': [for (final i in artists) i.toJson()],
    'l': [for (final i in releases) i.toJson()],
    'act': activity,
    'h': hourly,
    'g': [for (final i in genres) i.toJson()],
    's': streakDays,
  };

  static ListenStats? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      List<StatItem> items(String k) => [
        for (final i in (j[k] as List)) StatItem.fromJson(i as Map),
      ];
      return ListenStats(
        totalListens: j['t'] as int,
        recordings: items('r'),
        artists: items('a'),
        releases: items('l'),
        activity: (j['act'] as List).cast<int>(),
        hourly: (j['h'] as List).cast<int>(),
        genres: items('g'),
        streakDays: j['s'] as int,
      );
    } on Object {
      return null;
    }
  }
}

/// Parseo de las respuestas de `/1/stats/user/<user>/…`. Tolerante: forma
/// inesperada => lista vacía.
class LbStatsParser {
  static Map? _payload(Object? json) =>
      json is Map && json['payload'] is Map ? json['payload'] as Map : null;

  static List<StatItem> _items(
    Object? json,
    String key,
    String nameKey, {
    String? subKey,
  }) {
    final list = _payload(json)?[key];
    if (list is! List) return const [];
    return [
      for (final i in list)
        if (i is Map && i[nameKey] is String && i['listen_count'] is int)
          StatItem(
            i[nameKey] as String,
            i['listen_count'] as int,
            subtitle: subKey == null ? null : i[subKey] as String?,
          ),
    ];
  }

  static List<StatItem> recordings(Object? j) =>
      _items(j, 'recordings', 'track_name', subKey: 'artist_name');
  static List<StatItem> artists(Object? j) =>
      _items(j, 'artists', 'artist_name');
  static List<StatItem> releases(Object? j) =>
      _items(j, 'releases', 'release_name', subKey: 'artist_name');

  /// MBID de cada grabación, en el mismo orden que [recordings].
  static List<String?> recordingMbids(Object? j) {
    final list = _payload(j)?['recordings'];
    if (list is! List) return const [];
    return [
      for (final i in list)
        if (i is Map && i['track_name'] is String && i['listen_count'] is int)
          i['recording_mbid'] as String?,
    ];
  }

  static List<int> activity(Object? j) {
    final list = _payload(j)?['listening_activity'];
    if (list is! List) return const [];
    return [
      for (final i in list)
        if (i is Map && i['listen_count'] is int) i['listen_count'] as int,
    ];
  }

  /// Suma de todos los días de la semana por hora (24 posiciones).
  static List<int> hourly(Object? j) {
    final days = _payload(j)?['daily_activity'];
    if (days is! Map) return const [];
    final out = List.filled(24, 0);
    for (final day in days.values) {
      if (day is! List) continue;
      for (final e in day) {
        if (e is Map && e['hour'] is int && e['listen_count'] is int) {
          final h = e['hour'] as int;
          if (h >= 0 && h < 24) out[h] += e['listen_count'] as int;
        }
      }
    }
    return out;
  }

  static int listenCount(Object? j) {
    final c = _payload(j)?['count'];
    return c is int ? c : 0;
  }

  /// Días consecutivos con escuchas contando desde el final; el último tramo
  /// (día en curso) a cero no rompe la racha. Solo con tramos diarios.
  static int streak(List<int> perDay) {
    var n = 0;
    for (var i = perDay.length - 1; i >= 0; i--) {
      if (perDay[i] > 0) {
        n++;
      } else if (i != perDay.length - 1) {
        break;
      }
    }
    return n;
  }

  /// Géneros a partir de las etiquetas de las grabaciones top, ponderadas por
  /// escuchas. [tagsByMbid] sale de `recordingMetadata`.
  static List<StatItem> genres(
    List<StatItem> recs,
    List<String?> mbids,
    Map<String, List<String>> tagsByMbid,
  ) {
    final score = <String, int>{};
    for (var i = 0; i < recs.length && i < mbids.length; i++) {
      for (final t in tagsByMbid[mbids[i]] ?? const <String>[]) {
        final k = t.toLowerCase().trim();
        if (k.isNotEmpty) score[k] = (score[k] ?? 0) + recs[i].count;
      }
    }
    final sorted = score.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(5)) StatItem(e.key, e.value)];
  }
}

extension ListenBrainzStats on ListenBrainzClient {
  /// Estadísticas del usuario. El token solo viaja en la cabecera. Si una
  /// parte falla se devuelve el resto; el límite de peticiones se propaga.
  Future<ListenStats> userStats(
    String user,
    StatsRange range,
    String token,
  ) async {
    final u = Uri.encodeComponent(user);
    Future<Object?> get(String path) async {
      try {
        return await getJson(path, token);
      } on ListenBrainzRateLimited {
        rethrow;
      } on Object {
        return null;
      }
    }

    final r = range.api;
    final rec = await get('/1/stats/user/$u/recordings?range=$r&count=10');
    final art = await get('/1/stats/user/$u/artists?range=$r&count=5');
    final rel = await get('/1/stats/user/$u/releases?range=$r&count=5');
    final act = await get('/1/stats/user/$u/listening-activity?range=$r');
    final day = await get('/1/stats/user/$u/daily-activity?range=$r');
    final total = await get('/1/user/$u/listen-count');
    final recs = LbStatsParser.recordings(rec);
    final mbids = LbStatsParser.recordingMbids(rec);
    var genres = const <StatItem>[];
    final ids = [for (final m in mbids) ?m].take(10).toList();
    if (ids.isNotEmpty) {
      try {
        final meta = await recordingMetadata(ids, token);
        genres = LbStatsParser.genres(recs, mbids, {
          for (final t in meta)
            if (t.mbid != null) t.mbid!: t.tags,
        });
      } on ListenBrainzRateLimited {
        rethrow;
      } on Object {
        // sin etiquetas: el género queda como no disponible
      }
    }
    final activity = LbStatsParser.activity(act);
    return ListenStats(
      totalListens: LbStatsParser.listenCount(total),
      recordings: recs,
      artists: LbStatsParser.artists(art),
      releases: LbStatsParser.releases(rel),
      activity: activity,
      hourly: LbStatsParser.hourly(day),
      genres: genres,
      // listening-activity de semana/mes viene por día
      streakDays: range == StatsRange.week || range == StatsRange.month
          ? LbStatsParser.streak(activity)
          : 0,
    );
  }
}
