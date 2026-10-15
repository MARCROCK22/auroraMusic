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

/// Ordered by preference. Formats with `signatureCipher` are skipped, so extra
/// entries only help if their client returns plain `url`s.
const List<PlayerClient> defaultPlayerClients = [
  PlayerClient(
    name: 'VISIONOS',
    version: '0.1',
    id: 101,
    userAgent:
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/18.0 Safari/605.1.15',
    extraClient: {
      'osName': 'visionOS',
      'osVersion': '1.3.21O771',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
    },
  ),
];
