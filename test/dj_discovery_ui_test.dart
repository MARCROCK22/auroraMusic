import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/discovery_controller.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/ui/dj_discovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const a = Track(
  id: 'a',
  title: 'Primer tema',
  artist: 'Artista A',
  album: 'Primer álbum',
  genres: ['Jazz'],
  duration: Duration(minutes: 3, seconds: 15),
  pageUrl: 'https://youtu.be/a',
);
const b = Track(
  id: 'b',
  title: 'Segundo tema',
  artist: 'Artista B',
  pageUrl: 'https://youtu.be/b',
);
const c = Track(
  id: 'c',
  title: 'Tercer tema',
  artist: 'Artista C',
  pageUrl: 'https://youtu.be/c',
);

void main() {
  late AppController app;
  int searches = 0;

  setUp(() async {
    app = await createTestController(tracks: [a, b, c]);
    searches = 0;
  });
  tearDown(() => closeTestController(app));

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(700, 1000),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'Plus Jakarta Sans',
          ),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffe86927),
            brightness: Brightness.dark,
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('dj-review'),
              child: DjDiscoveryPage(
                controller: app,
                onSearch: () => searches++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'card uses available metadata and buttons save interest without playback',
    (tester) async {
      await mount(tester);
      expect(find.text(a.album!), findsOneWidget);
      expect(find.text('Jazz · 3:15'), findsOneWidget);
      expect(find.text('De tu biblioteca'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dj-discovery-add')));
      await tester.pumpAndSettle();
      expect(app.queue.map((track) => track.id), ['a']);
      expect(app.favoriteIds, contains('a'));
      expect(app.audio.isPlaying, isFalse);
      expect(find.text(b.title), findsOneWidget);
      expect(find.text(a.album!), findsNothing);
      await tester.tap(find.byKey(const ValueKey('dj-discovery-skip')));
      await tester.pumpAndSettle();
      expect(find.text(c.title), findsOneWidget);
      expect(app.favoriteIds, isNot(contains('b')));
      expect(app.queue, hasLength(1));
    },
  );

  testWidgets('horizontal swipes left omit and right add exactly once', (
    tester,
  ) async {
    await mount(tester);
    await tester.drag(
      find.byKey(const ValueKey('dj-discovery-card')),
      const Offset(-140, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text(b.title), findsOneWidget);
    expect(app.favoriteIds, isEmpty);
    await tester.drag(
      find.byKey(const ValueKey('dj-discovery-card')),
      const Offset(140, 0),
    );
    await tester.pumpAndSettle();
    expect(app.favoriteIds, {'b'});
    expect(app.queue.map((track) => track.id), ['b']);
    expect(find.text(c.title), findsOneWidget);
    expect(app.audio.isPlaying, isFalse);
  });

  testWidgets(
    'small horizontal, vertical and mostly vertical gestures do not decide',
    (tester) async {
      await mount(tester);
      for (final delta in [
        const Offset(40, 0),
        const Offset(0, -100),
        const Offset(90, -120),
      ]) {
        await tester.drag(
          find.byKey(const ValueKey('dj-discovery-card')),
          delta,
        );
        await tester.pumpAndSettle();
        expect(find.text(a.title), findsOneWidget);
        expect(app.queue, isEmpty);
        expect(app.favoriteIds, isEmpty);
      }
    },
  );

  testWidgets(
    'filtered empty state provides search and no pending metadata is queued',
    (tester) async {
      app.discoveredRecommendations = [
        const Track(
          id: 'pending',
          title: 'Pending',
          artist: 'Spotify',
          spotifyMatchPending: true,
          pageUrl: 'https://open.spotify.com/track/abc',
        ),
      ];
      await app.setDjFilters(const DjFilters(genres: ['Rock']));
      await mount(tester);
      expect(
        find.text('No quedan canciones para esta selección'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dj-discovery-add')), findsNothing);
      await tester.tap(find.text('Buscar música'));
      expect(searches, 1);
      expect(app.queue, isEmpty);
      expect((app.source as FakeSource).searchQueries, isEmpty);
    },
  );

  testWidgets(
    'reduced motion keeps drag transform still and still accepts choice',
    (tester) async {
      app.reducedMotion = true;
      await mount(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('dj-discovery-card'))),
      );
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      final transform = tester.widget<Transform>(
        find
            .descendant(
              of: find.byKey(const ValueKey('dj-discovery-card')),
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(transform.transform.storage[12], 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(app.queue.map((track) => track.id), ['a']);
    },
  );

  testWidgets('narrow layout and enlarged text stay scrollable', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 700), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dj-discovery-add')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dj-discovery-add')));
    await tester.pumpAndSettle();
    expect(app.queue, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('review screenshots show desktop and Android card layouts', (
    tester,
  ) async {
    for (final font in {
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    for (final size in [const Size(960, 1000), const Size(390, 844)]) {
      await mount(tester, size: size);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('dj-review')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final directory = Directory('build/ui-review/dj_discovery');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/card-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      });
      expect(tester.takeException(), isNull);
    }
  });

  test(
    'stale and concurrent actions target one card; skipped identities survive refresh',
    () async {
      final discovery = DjDiscoveryController(app);
      addTearDown(discovery.dispose);
      await Future.wait([discovery.accept(a), discovery.accept(a)]);
      discovery.skip(a);
      expect(discovery.added, 1);
      expect(discovery.skipped, 0);
      expect(app.queue, hasLength(1));
      discovery.skip(b);
      await app.refreshRecommendations();
      expect(discovery.current?.track.id, 'c');
    },
  );

  test('pending Spotify metadata is never a candidate', () {
    app.tracks = [];
    app.discoveredRecommendations = [
      const Track(
        id: 'pending',
        title: 'Pending',
        artist: 'Spotify',
        spotifyMatchPending: true,
        pageUrl: 'https://open.spotify.com/track/abc',
      ),
    ];
    final discovery = DjDiscoveryController(app);
    addTearDown(discovery.dispose);
    expect(discovery.current, isNull);
    expect(app.queue, isEmpty);
  });

  test(
    'session choices remember Spotify identity through new audio aliases',
    () {
      final original = a.copyWith(spotifyUri: 'spotify:track:abc');
      final alias = b.copyWith(spotifyUri: 'spotify:track:abc');
      app.tracks = [original];
      final discovery = DjDiscoveryController(app);
      addTearDown(discovery.dispose);
      discovery.skip(original);
      app.discoveredRecommendations = [alias];
      expect(discovery.current, isNull);
      expect(discovery.skipped, 1);
    },
  );

  test(
    'an already liked discovery card never unlikes or duplicates existing queue',
    () async {
      await app.toggleFavorite(a);
      await app.addToQueue(a);
      app.tracks = [a];
      app.discoveredRecommendations = [a];
      final discovery = DjDiscoveryController(app);
      addTearDown(discovery.dispose);
      expect(discovery.current?.track.id, 'a');
      await discovery.accept(a);
      expect(app.favoriteIds, {'a'});
      expect(app.queue, hasLength(1));
      expect(discovery.current, isNull);
    },
  );
}
