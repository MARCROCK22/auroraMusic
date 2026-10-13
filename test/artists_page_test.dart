import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/artists_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tracks = [
    Track(
      id: 'one',
      title: 'First Song',
      artist: 'Aurora',
      album: 'North',
      duration: Duration(minutes: 3, seconds: 12),
    ),
    Track(
      id: 'two',
      title: 'Second Song',
      artist: ' aurora ',
      duration: Duration(minutes: 4),
    ),
    Track(id: 'three', title: 'Other Song', artist: 'Borealis'),
    Track(id: 'ignored', title: 'Unknown', artist: '  '),
  ];

  testWidgets('groups real artists and plays a selected artist track', (
    tester,
  ) async {
    Track? played;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistsPage(
            tracks: tracks,
            onPlay: (track) => played = track,
            onSearch: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('2 artistas en tu biblioteca'), findsOneWidget);
    expect(find.text('2 canciones'), findsOneWidget);
    expect(find.text('Aurora'), findsOneWidget);
    expect(find.text('Borealis'), findsOneWidget);
    expect(find.text('Unknown'), findsNothing);

    await tester.tap(find.text('Aurora'));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsOneWidget);
    expect(find.text('Second Song'), findsOneWidget);
    expect(find.text('North · 3:12'), findsOneWidget);
    await tester.tap(find.byTooltip('Reproducir Second Song'));
    expect(played?.id, 'two');
  });

  testWidgets('empty state opens search', (tester) async {
    String? query;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistsPage(
            tracks: const [],
            onPlay: (_) {},
            onSearch: (value) => query = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Buscar música'));
    expect(query, '');
  });

  testWidgets('artist detail fits a narrow view with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: ArtistsPage(tracks: tracks, onPlay: (_) {}, onSearch: (_) {}),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aurora').first);
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
