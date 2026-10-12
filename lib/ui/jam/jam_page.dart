import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app_controller.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../jam/jam_qr.dart';
import 'jam_qr_code.dart';
import 'jam_scanner_dialog.dart';
import 'jam_session_panel.dart';

class JamPage extends StatefulWidget {
  const JamPage({super.key, required this.controller, this.onControllerReady});
  final AppController controller;
  final ValueChanged<JamController>? onControllerReady;
  @override
  State<JamPage> createState() => _JamPageState();
}

class _JamPageState extends State<JamPage> {
  JamController? _jam;
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _address;
  String? _inputError;
  bool _creating = false, _joining = false, _readingImage = false;
  JamController get jam {
    if (_jam != null) return _jam!;
    final created = JamController(app: widget.controller)
      ..addListener(_changed);
    _jam = created;
    widget.onControllerReady?.call(created);
    return created;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _jam?.removeListener(_changed);
    _jam?.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String _participantName({bool host = false}) => _name.text.trim().isEmpty
      ? (host ? 'Anfitrión' : 'Invitado')
      : _name.text.trim();
  Future<void> _prepareHost() async {
    setState(() {
      _creating = true;
      _joining = false;
      _inputError = null;
    });
    await jam.loadAddresses();
    if (mounted && jam.addresses.isNotEmpty) {
      setState(() => _address = jam.addresses.first);
    }
  }

  Future<void> _join(String value) async {
    _inputError = null;
    await jam.join(value, _participantName());
    if (mounted && jam.service.connected) {
      _code.clear();
      setState(() {
        _joining = false;
        _creating = false;
      });
    }
  }

  Future<void> _scan() async {
    jam;
    if (!Platform.isAndroid) {
      await _readImage();
      return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const JamScannerDialog(),
    );
    if (code != null && mounted) await _join(code);
  }

  Future<void> _readImage() async {
    jam;
    setState(() {
      _readingImage = true;
      _inputError = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (result.isEmpty || !mounted) return;
      final selected = result.single;
      if (selected.path == null) {
        throw const JamException('La imagen QR debe pesar menos de ocho MiB.');
      }
      final file = File(selected.path!);
      if (await file.length() > jamMaxImageBytes) {
        throw const JamException('La imagen QR es demasiado grande.');
      }
      final value = await decodeJamQrImage(await file.readAsBytes());
      if (mounted) await _join(value);
    } catch (failure) {
      if (mounted) {
        _inputError = failure is JamException
            ? failure.message
            : 'No se pudo abrir la imagen QR.';
      }
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _jam;
    final session = c?.service;
    final active =
        session?.connected == true ||
        session?.connection == JamConnection.disconnected &&
            session?.invite != null;
    final busy = c?.busy == true || _readingImage;
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jam', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                active
                    ? 'Una cola para quienes están contigo.'
                    : 'Comparte una cola y escucha en compañía, dentro de tu red local.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (_inputError ?? c?.error ?? session?.error
                  case final String message) ...[
                _notice(message, Icons.info_outline),
                const SizedBox(height: 16),
              ],
              if (!active) ...[
                TextField(
                  controller: _name,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Tu nombre en la Jam (opcional)',
                    hintText: 'Se mostrará junto a las canciones que agregues',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : _prepareHost,
                      icon: const Icon(Icons.group_add_outlined),
                      label: const Text('Crear Jam'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () {
                              jam;
                              setState(() {
                                _joining = true;
                                _creating = false;
                              });
                            },
                      icon: const Icon(Icons.login),
                      label: const Text('Unirme a una Jam'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(
                        Platform.isAndroid
                            ? 'Escanear QR'
                            : 'Importar imagen QR',
                      ),
                    ),
                  ],
                ),
                if (_creating) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Crear una sesión local',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (c?.addresses.isNotEmpty == true) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _address,
                      items: c!.addresses
                          .map(
                            (address) => DropdownMenuItem(
                              value: address,
                              child: Text(address),
                            ),
                          )
                          .toList(),
                      onChanged: (address) =>
                          setState(() => _address = address),
                      decoration: const InputDecoration(
                        labelText: 'Dirección de red del anfitrión',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: busy || _address == null
                          ? null
                          : () async {
                              await jam.host(
                                _address!,
                                _participantName(host: true),
                              );
                              if (mounted && jam.service.isHost) {
                                setState(() => _creating = false);
                              }
                            },
                      child: const Text('Iniciar sesión local'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'El puerto se abre únicamente en la dirección privada elegida. Windows puede pedir autorización de firewall para redes privadas.',
                  ),
                ],
                if (_joining) ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: _code,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Invitación de Jam',
                      hintText: 'Pega la invitación copiada por el anfitrión',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: busy ? null : () => _join(_code.text),
                        child: const Text('Conectar'),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : _readImage,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Leer QR de una imagen'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                _notice(
                  'Ambos dispositivos deben estar en la misma red. Cada uno usa sus propias fuentes de audio; los archivos locales no se envían.',
                  Icons.wifi,
                ),
              ] else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: Icon(
                        session!.connected ? Icons.wifi : Icons.wifi_off,
                        size: 18,
                      ),
                      label: Text(
                        session.isHost
                            ? 'Anfitrión'
                            : session.connected
                            ? 'Conectado'
                            : 'Sin conexión',
                      ),
                    ),
                    if (session.invite != null) Text(session.invite!.endpoint),
                    if (!session.connected)
                      OutlinedButton.icon(
                        onPressed: busy ? null : c!.reconnect,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reconectar'),
                      ),
                    TextButton.icon(
                      onPressed: busy ? null : c!.leave,
                      icon: const Icon(Icons.logout),
                      label: Text(
                        session.isHost ? 'Cerrar Jam' : 'Salir de la Jam',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (session.isHost && session.invite != null) _invitation(c!),
                const SizedBox(height: 16),
                JamSessionPanel(controller: c!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(String message, IconData icon, {Widget? action}) =>
      jamNotice(context, message, icon, action: action);
  Widget _invitation(JamController c) => LayoutBuilder(
    builder: (context, constraints) {
      final invite = c.service.invite!;
      final description = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invita a quienes están cerca',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Abre Aurora en el otro dispositivo y escanea este código desde Jam.',
          ),
          const SizedBox(height: 12),
          Text(
            'Acceso válido hasta ${_time(invite.expiresAt)}. Al cerrar la sesión, este QR deja de funcionar.',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: invite.encode()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invitación copiada. Compártela solo con tus participantes.',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar invitación'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Usa una red de confianza: la conexión LAN y el QR de acceso no están cifrados.',
          ),
        ],
      );
      final qr = JamQrCode(data: invite.encode());
      return constraints.maxWidth < 640
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [qr, const SizedBox(height: 16), description],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                qr,
                const SizedBox(width: 24),
                Expanded(child: description),
              ],
            );
    },
  );
  String _time(DateTime value) =>
      '${value.toLocal().hour.toString().padLeft(2, '0')}:${value.toLocal().minute.toString().padLeft(2, '0')}';
}
