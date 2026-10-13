import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/source_backend.dart';
import '../sources/yt_dlp_source.dart';

class VideoDownloadsPage extends StatefulWidget {
  const VideoDownloadsPage({
    super.key,
    required this.source,
    required this.supportDirectory,
  });

  final SourceBackend source;
  final Directory supportDirectory;

  @override
  State<VideoDownloadsPage> createState() => _VideoDownloadsPageState();
}

class _VideoDownload {
  _VideoDownload(this.id, this.url);
  final String id;
  final Uri url;
  double progress = 0;
  String? path;
  String? error;
  bool active = true;
}

class _VideoDownloadsPageState extends State<VideoDownloadsPage> {
  final _url = TextEditingController();
  final _jobs = <_VideoDownload>[];
  String? _validationError;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Uri? _validate(String value) {
    try {
      return YtDlpSource.validateVideoUrl(value);
    } on ArgumentError catch (error) {
      _validationError = error.message?.toString();
      return null;
    }
  }

  Future<void> _start() async {
    final uri = _validate(_url.text);
    if (uri == null) {
      setState(() {});
      return;
    }
    final id = uri.host == 'youtu.be'
        ? uri.pathSegments.single
        : uri.path == '/watch'
        ? uri.queryParameters['v']!
        : uri.pathSegments.last;
    final job = _VideoDownload(
      '$id-${DateTime.now().microsecondsSinceEpoch}',
      uri,
    );
    setState(() {
      _validationError = null;
      _jobs.insert(0, job);
      _url.clear();
    });
    final directory = Directory(
      p.join(widget.supportDirectory.path, 'downloads', 'videos'),
    );
    final destination = File(p.join(directory.path, '$id.video'));
    try {
      await directory.create(recursive: true);
      final root = await widget.supportDirectory.resolveSymbolicLinks();
      final actualDirectory = await directory.resolveSymbolicLinks();
      final relative = p.relative(actualDirectory, from: root);
      if (!p.isWithin(root, actualDirectory) ||
          relative == '..' ||
          relative.startsWith('..${p.separator}') ||
          await FileSystemEntity.type(destination.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        throw StateError('La carpeta o el archivo de destino no es seguro.');
      }
      final existing = await directory
          .list(followLinks: false)
          .where((entry) => p.basenameWithoutExtension(entry.path) == id)
          .isEmpty;
      if (!existing) throw StateError('Este video ya está descargado.');
      await widget.source.downloadVideo(
        uri,
        destination,
        jobId: job.id,
        onProgress: (value) {
          if (mounted && job.active)
            setState(() => job.progress = value.clamp(0, 1));
        },
      );
      if (!mounted) return;
      final matches = await directory
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File && p.basenameWithoutExtension(entry.path) == id,
          )
          .toList();
      setState(() {
        job.active = false;
        job.progress = 1;
        job.path = matches.length == 1 ? matches.single.path : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        job.active = false;
        job.error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _cancel(_VideoDownload job) async {
    try {
      await widget.source.cancel(job.id);
    } finally {
      if (mounted) setState(() => job.active = false);
    }
  }

  Future<void> _openFolder() async {
    final directory = p.join(
      widget.supportDirectory.path,
      'downloads',
      'videos',
    );
    if (Platform.isWindows) {
      await Directory(directory).create(recursive: true);
      await Process.start('explorer.exe', [directory], runInShell: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Descargas de video',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Descarga un video público de YouTube como archivo de video.',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _validationError = null),
          onSubmitted: (_) => _start(),
          decoration: InputDecoration(
            labelText: 'Enlace del video de YouTube',
            hintText: 'https://www.youtube.com/watch?v=…',
            errorText: _validationError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _url.text.trim().isEmpty ? null : _start,
            icon: const Icon(Icons.download),
            label: const Text('Descargar video'),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Text(
                'Carpeta: ${p.join(widget.supportDirectory.path, 'downloads', 'videos')}',
              ),
            ),
            if (Platform.isWindows)
              IconButton(
                tooltip: 'Abrir carpeta',
                onPressed: _openFolder,
                icon: const Icon(Icons.folder_open),
              ),
          ],
        ),
        const Divider(height: 24),
        if (_jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Text(
              'Tus videos descargados aparecerán aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ),
        for (final job in _jobs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.path == null
                        ? job.url.toString()
                        : p.basename(job.path!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  if (job.active) ...[
                    LinearProgressIndicator(
                      value: job.progress == 0 ? null : job.progress,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _cancel(job),
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      ),
                    ),
                  ] else if (job.error != null)
                    Text(job.error!, style: TextStyle(color: colors.error))
                  else
                    Text(
                      job.path ?? 'Video descargado',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
