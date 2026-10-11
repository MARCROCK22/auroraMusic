import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

class SpotifyMatchDialog extends StatefulWidget {
  const SpotifyMatchDialog({
    super.key,
    required this.track,
    required this.onSearch,
    required this.onSave,
  });

  final Track track;
  final Future<List<Track>> Function() onSearch;
  final Future<bool> Function(Track match, {required bool play}) onSave;

  static Future<void> show(
    BuildContext context, {
    required Track track,
    required Future<List<Track>> Function() onSearch,
    required Future<bool> Function(Track match, {required bool play}) onSave,
  }) => showDialog<void>(
    context: context,
    builder: (_) =>
        SpotifyMatchDialog(track: track, onSearch: onSearch, onSave: onSave),
  );

  @override
  State<SpotifyMatchDialog> createState() => _SpotifyMatchDialogState();
}

class _SpotifyMatchDialogState extends State<SpotifyMatchDialog> {
  List<Track> _matches = [];
  Track? _selected;
  Object? _searchError;
  String? _saveError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _searchError = null;
      _matches = [];
      _selected = null;
    });
    try {
      final matches = await widget.onSearch();
      if (mounted) setState(() => _matches = matches.take(3).toList());
    } catch (error) {
      if (mounted) setState(() => _searchError = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({required bool play}) async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (await widget.onSave(selected, play: play)) {
        if (mounted) Navigator.pop(context);
      } else if (mounted) {
        setState(() => _saveError = 'No se pudo guardar la coincidencia.');
      }
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: const Text('Elegir coincidencia de YouTube'),
      scrollable: true,
      content: SizedBox(
        width: math.min(size.width * .82, 520),
        height: math.min(size.height * .46, 350),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.track.title} · ${widget.track.artist}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(child: _content()),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                _saveError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _saving || _selected == null
              ? null
              : () => _save(play: false),
          child: const Text('Guardar'),
        ),
        FilledButton(
          onPressed: _saving || _selected == null
              ? null
              : () => _save(play: true),
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar y reproducir'),
        ),
      ],
    );
  }

  Widget _content() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_searchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No se pudo buscar en YouTube.'),
            TextButton.icon(
              onPressed: _search,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    if (_matches.isEmpty) {
      return const Center(child: Text('No se encontraron coincidencias.'));
    }
    return RadioGroup<Track>(
      groupValue: _selected,
      onChanged: (value) {
        if (_saving) return;
        setState(() {
          _selected = value;
          _saveError = null;
        });
      },
      child: ListView.builder(
        itemCount: _matches.length,
        itemBuilder: (context, index) {
          final match = _matches[index];
          final duration = match.duration.inSeconds;
          final length = duration == 0
              ? ''
              : ' · ${duration ~/ 60}:${(duration % 60).toString().padLeft(2, '0')}';
          return RadioListTile<Track>(
            contentPadding: EdgeInsets.zero,
            value: match,
            title: Text(
              match.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${match.artist}$length',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}
