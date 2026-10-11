import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/spotify_match_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _spotifyTrack = Track(
  id: 'spotify-row',
  title: 'Original Song',
  artist: 'Original Artist',
  spotifyUri: 'spotify:track:abc',
  spotifyMatchPending: true,
);
const _youtubeTrack = Track(
  id: 'youtube-result',
  title: 'Possible video title',
  artist: 'Possible video artist',
  pageUrl: 'https://youtu.be/abcdefghijk',
);

Future<void> _open(
  WidgetTester tester, {
  required Future<List<Track>> Function() onSearch,
  required Future<bool> Function(Track, {required bool play}) onSave,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => SpotifyMatchDialog.show(
              context,
              track: _spotifyTrack,
              onSearch: onSearch,
              onSave: onSave,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel and source failure leave imported row untouched', (
    tester,
  ) async {
    var saved = false;
    await _open(
      tester,
      onSearch: () async => throw StateError('YouTube is unavailable'),
      onSave: (_, {required play}) async {
        saved = true;
        return true;
      },
    );

    expect(find.text('No se pudo buscar en YouTube.'), findsOneWidget);
    expect(find.textContaining('YouTube is unavailable'), findsNothing);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(saved, isFalse);
    expect(find.text('Elegir coincidencia de YouTube'), findsNothing);
  });

  testWidgets('requires explicit result and play choice', (tester) async {
    Track? savedMatch;
    bool? playChoice;
    await _open(
      tester,
      onSearch: () async => [_youtubeTrack],
      onSave: (match, {required play}) async {
        savedMatch = match;
        playChoice = play;
        return true;
      },
    );
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Possible video title'), findsOneWidget);
    await tester.tap(find.text('Possible video title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(savedMatch, same(_youtubeTrack));
    expect(playChoice, isFalse);
  });

  testWidgets('shows an empty result state without enabling save', (
    tester,
  ) async {
    await _open(
      tester,
      onSearch: () async => [],
      onSave: (_, {required play}) async => true,
    );
    expect(find.text('No se encontraron coincidencias.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('match dialog stays within a narrow screen at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
      tester,
      onSearch: () async => [_youtubeTrack],
      onSave: (_, {required play}) async => true,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
