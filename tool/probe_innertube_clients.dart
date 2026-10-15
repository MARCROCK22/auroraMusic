// ignore_for_file: avoid_print
// Manual canary (not run in CI): resolves video ids with each client alone and
// prints the outcome. Usage: dart run tool/probe_innertube_clients.dart [id...]
import 'package:aurora_music/sources/stream/player_clients.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';

Future<void> main(List<String> args) async {
  final ids = args.isEmpty ? ['dQw4w9WgXcQ'] : args;
  for (final client in defaultPlayerClients) {
    // A fresh orchestrator per client: no cache, no bad-client ordering.
    for (final id in ids) {
      final orchestrator = StreamOrchestrator(clients: [client]);
      try {
        final ResolvedStream s = await orchestrator.resolve(id);
        print(
          '${client.name} $id OK itag=${s.itag} clen=${s.contentLength} '
          'mime=${s.mimeType} ttl=${s.expiresAt.difference(DateTime.now()).inMinutes}min (tail probe 2xx)',
        );
      } on StreamResolveException catch (e) {
        print('${client.name} $id FAIL ${e.kind.name}: ${e.message}');
      }
    }
  }
}
