import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../artwork.dart';
import '../jam/jam_qr_code.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

class StudioSessionAside extends StatelessWidget {
  const StudioSessionAside({
    super.key,
    required this.controller,
    required this.onJam,
    required this.onQueue,
    this.jam,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onJam, onQueue;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final session = jam?.service;
    final connected = session?.connected == true;
    final colors = Theme.of(context).colorScheme;
    final personal = c.queue.skip(c.queueIndex + 1).take(3).toList();
    final shared = connected
        ? session!.queue
              .where((e) => e.id != jam!.bridge.currentEntryId)
              .take(3)
              .toList()
        : null;
    return SizedBox(
      width: 340,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 24, 24),
        children: [
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: connected
                          ? colors.primaryContainer
                          : colors.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        connected
                            ? 'Sesión Compartida Activa'
                            : 'Sesión Compartida',
                        style: const TextStyle(
                          fontFamily: 'Newsreader',
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    StudioStamp(
                      connected
                          ? '${session!.participants.where((p) => p.connected).length} OYENTES'
                          : 'SIN JAM',
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cualquier invitado conectado a la misma red local puede escanear desde Aurora y agregar temas a la cola.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                StudioPanel(
                  recessed: true,
                  padding: const EdgeInsets.all(16),
                  child: connected && session?.invite != null && session!.isHost
                      ? Row(
                          children: [
                            JamQrCode(data: session.invite!.encode(), size: 96),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const StudioStamp('ENLACE DIRECTO WEBSOCKET'),
                                  const SizedBox(height: 8),
                                  Text(
                                    session.invite!.endpoint,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Acceso temporal en el QR',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(
                                        text: session.invite!.encode(),
                                      ),
                                    ),
                                    icon: const Icon(
                                      StudioSymbols.share,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'Copiar invitación',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              StudioSymbols.wifiTethering,
                              size: 40,
                              color: colors.primary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              connected
                                  ? 'Participas en ${session!.invite?.endpoint ?? 'una Jam local'}'
                                  : 'Crea una Jam para mostrar aquí su código QR.',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: onJam,
                              icon: const Icon(StudioSymbols.groups, size: 16),
                              label: Text(
                                connected
                                    ? 'Abrir Jam'
                                    : 'Crear o unirse a Jam',
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                StudioStamp(
                  connected
                      ? (session!.mode.name == 'synchronized'
                            ? 'MODO: REPRODUCCIÓN SINCRONIZADA'
                            : 'MODO: COLA COMPARTIDA')
                      : 'SESIÓN TEMPORAL EN TU RED LOCAL',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(StudioSymbols.queueMusic, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'En Cola (Próximas ${shared?.length ?? personal.length})',
                        style: const TextStyle(
                          fontFamily: 'Newsreader',
                          fontSize: 16,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onQueue,
                      child: const Text(
                        'Ver todo',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((shared?.isEmpty ?? personal.isEmpty))
                  const Text(
                    'La cola está vacía',
                    style: TextStyle(fontSize: 12),
                  ),
                if (shared != null)
                  for (final (index, entry) in shared.indexed)
                    _queueItem(
                      context,
                      Track(
                        id: entry.track.key,
                        title: entry.track.title,
                        artist: entry.track.artist,
                        artworkUrl: entry.track.artworkUrl,
                        duration: Duration(
                          milliseconds: entry.track.durationMs,
                        ),
                      ),
                      index,
                      'Por ${session!.participantName(entry.addedBy)}',
                      onJam,
                    )
                else
                  for (final (index, track) in personal.indexed)
                    _queueItem(
                      context,
                      track,
                      index,
                      track.artist,
                      () => c.playQueueAt(c.queue.indexOf(track)),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(StudioSymbols.tune, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: StudioStamp('FILTRO DE VÁLVULA & CINTA'),
                    ),
                    StudioStamp(
                      c.eqEnabled ? 'EQ ACTIVO' : 'EQ INACTIVO',
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  c.webPlayback
                      ? 'El ecualizador aplica a archivos locales, no a YouTube Music.'
                      : c.audio.supportsEqualizer
                      ? 'Ecualizador real · simulación de válvula y cinta pendiente'
                      : 'El dispositivo no ofrece un ecualizador compatible.',
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final index in [0, 3, 6].where(
                      (i) =>
                          i < c.audio.eqFrequencies.length &&
                          i < c.eqGains.length,
                    ))
                      Expanded(
                        child: Column(
                          children: [
                            StudioStamp(
                              '${c.audio.eqFrequencies[index].round()} Hz',
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 112,
                              width: 44,
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 8,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 6,
                                    ),
                                  ),
                                  child: Slider(
                                    value: c.eqGains[index].clamp(-12, 12),
                                    min: -12,
                                    max: 12,
                                    onChanged: (value) {
                                      if (!c.eqEnabled) {
                                        c.setEqualizerEnabled(true);
                                      }
                                      c.setEqGain(index, value);
                                    },
                                    semanticFormatterCallback: (value) =>
                                        '${value.toStringAsFixed(1)} decibelios',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            StudioStamp(
                              '${c.eqGains[index].toStringAsFixed(1)} dB',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Ecualizador',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: c.eqEnabled,
                  onChanged: c.audio.supportsEqualizer
                      ? c.setEqualizerEnabled
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _queueItem(
    BuildContext context,
    Track track,
    int index,
    String subtitle,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              StudioStamp((index + 1).toString().padLeft(2, '0')),
              const SizedBox(width: 8),
              Artwork(
                track: track,
                artworkContext: ArtworkContext.thumbnailCompact,
                radius: 2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StudioStamp(
                track.duration > Duration.zero
                    ? studioTime(track.duration)
                    : '—',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
