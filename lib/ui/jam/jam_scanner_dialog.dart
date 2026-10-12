import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Constructed only after the user taps Scan. No camera request during app startup.
class JamScannerDialog extends StatefulWidget {
  const JamScannerDialog({super.key});
  @override
  State<JamScannerDialog> createState() => _JamScannerDialogState();
}

class _JamScannerDialogState extends State<JamScannerDialog> {
  final _scanner = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;
  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Escanear QR de Jam',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar cámara',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  if (_finished) return;
                  final code = capture.barcodes
                      .map((barcode) => barcode.rawValue)
                      .whereType<String>()
                      .firstOrNull;
                  if (code != null && code.length <= 2048) {
                    _finished = true;
                    Navigator.pop(context, code);
                  }
                },
                errorBuilder: (_, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.no_photography_outlined, size: 40),
                      SizedBox(height: 16),
                      Text(
                        'No se pudo abrir la cámara. Puedes importar una imagen QR o pegar la invitación.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Apunta al código que muestra el anfitrión.'),
          ),
        ],
      ),
    ),
  );
}
