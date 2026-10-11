import 'package:aurora_music/import/spotify_import.dart';
import 'package:aurora_music/ui/spotify_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('previews playlist counts and lets the user choose lists', (
    tester,
  ) async {
    List<SpotifyImportPlaylist>? selected;
    const result = SpotifyImportResult(
      playlists: [
        SpotifyImportPlaylist(
          name: 'First',
          tracks: [SpotifyImportTrack(title: 'A', artist: 'Artist')],
        ),
        SpotifyImportPlaylist(
          name: 'Second',
          tracks: [
            SpotifyImportTrack(title: 'B', artist: 'Artist'),
            SpotifyImportTrack(title: 'C', artist: 'Artist'),
          ],
        ),
      ],
      skipped: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SpotifyImportDialog.show(
                context,
                result: result,
                onImport: (value) async => selected = value,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('2 canciones'), findsOneWidget);
    expect(find.textContaining('1 elementos omitidos'), findsOneWidget);
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importar 1 lista'));
    await tester.pumpAndSettle();

    expect(selected?.map((playlist) => playlist.name), ['Second']);
  });

  testWidgets('cancel closes the preview without importing', (tester) async {
    var imported = false;
    const result = SpotifyImportResult(
      playlists: [
        SpotifyImportPlaylist(
          name: 'Keep',
          tracks: [SpotifyImportTrack(title: 'Song', artist: 'Artist')],
        ),
      ],
      skipped: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => SpotifyImportDialog.show(
                context,
                result: result,
                onImport: (_) async => imported = true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(imported, isFalse);
    expect(find.text('Importar listas de Spotify'), findsNothing);
  });
}
