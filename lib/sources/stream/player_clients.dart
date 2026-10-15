/// An InnerTube client identity used for `player` requests.
class PlayerClient {
  const PlayerClient({
    required this.name,
    required this.version,
    required this.id,
    required this.userAgent,
    this.extraClient = const {},
  });

  final String name;
  final String version;

  /// Numeric X-YouTube-Client-Name.
  final int id;
  final String userAgent;

  /// Extra `context.client` fields (os/device).
  final Map<String, Object?> extraClient;
}

/// Ordered by preference; filled in by the orchestrator module.
const List<PlayerClient> defaultPlayerClients = [];
