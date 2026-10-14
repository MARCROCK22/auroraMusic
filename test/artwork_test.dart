import 'dart:async';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingClient extends Fake implements HttpClient {
  final response = Completer<HttpClientRequest>();

  @override
  Future<HttpClientRequest> getUrl(Uri url) => response.future;
}

void main() {
  const track = Track(id: 'cover', title: 'Record', artist: 'Artist');
  final square = find.descendant(
    of: find.byType(Artwork),
    matching: find.byType(AspectRatio),
  );

  Future<void> mount(
    WidgetTester tester,
    Widget artwork, {
    double dpr = 1,
    double? width,
    double? height,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          devicePixelRatio: dpr,
          textScaler: const TextScaler.linear(2),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(width: width, height: height, child: artwork),
          ),
        ),
      ),
    ),
  );

  tearDown(() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('contexts keep square covers within both parent bounds', (
    tester,
  ) async {
    for (final variant in ArtworkContext.values) {
      await mount(
        tester,
        Artwork(track: track, artworkContext: variant),
        width: 100,
        height: 70,
      );
      final side = variant.size < 70 ? variant.size : 70.0;
      expect(tester.getSize(square), Size.square(side));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('fill uses bounded square and supports a circular vinyl clip', (
    tester,
  ) async {
    await mount(
      tester,
      const ClipOval(child: Artwork.fill(track: track)),
      width: 92,
      height: 92,
    );
    expect(tester.getSize(square), const Size.square(92));
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy explicit size remains compatible', (tester) async {
    const artwork = Artwork(track: track, size: 123);
    expect(artwork.size, 123);
    await mount(tester, artwork);
    expect(tester.getSize(square), const Size.square(123));
  });

  testWidgets('network decode uses rendered side times DPR without a ceiling', (
    tester,
  ) async {
    debugNetworkImageHttpClientProvider = _PendingClient.new;
    for (final dpr in [1.0, 2.0, 4.0]) {
      await mount(
        tester,
        Artwork(
          track: track.copyWith(artworkUrl: 'https://example.test/$dpr.png'),
          artworkContext: ArtworkContext.player,
        ),
        dpr: dpr,
        width: 300,
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as ResizeImage).width, (300 * dpr).ceil());
      expect(image.fit, BoxFit.cover);
      expect(image.filterQuality, FilterQuality.high);
      expect(image.excludeFromSemantics, isTrue);
      expect(tester.getSize(square), const Size.square(300));
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    }
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('loading and failed HTTPS retain the same square placeholder', (
    tester,
  ) async {
    final client = _PendingClient();
    debugNetworkImageHttpClientProvider = () => client;
    await mount(
      tester,
      Artwork(
        track: track.copyWith(artworkUrl: 'https://example.test/fail.png'),
      ),
    );
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.getSize(square), const Size.square(48));
    client.response.completeError(const SocketException('Image unavailable'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.getSize(square), const Size.square(48));
    expect(tester.takeException(), isNull);
    debugNetworkImageHttpClientProvider = null;
  });

  testWidgets('asset loading uses the same cover fit and DPI decode sizing', (
    tester,
  ) async {
    await mount(
      tester,
      Artwork(
        track: track.copyWith(
          artworkUrl:
              'asset:assets/design_idea/inicio_aurora_music_player_00.png',
        ),
        artworkContext: ArtworkContext.card,
      ),
      dpr: 2,
      width: 100,
    );
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.imageProvider, isA<AssetImage>());
    expect(resized.width, 200);
    expect(image.fit, BoxFit.cover);
    expect(image.filterQuality, FilterQuality.high);
    await tester.runAsync(
      () => precacheImage(image.image, tester.element(find.byType(Image))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.music_note_rounded), findsNothing);
    expect(tester.getSize(square), const Size.square(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed asset keeps the reserved square', (tester) async {
    await mount(
      tester,
      Artwork(track: track.copyWith(artworkUrl: 'asset:missing-artwork.png')),
    );
    final image = tester.widget<Image>(find.byType(Image));
    await tester.runAsync(
      () => precacheImage(
        image.image,
        tester.element(find.byType(Image)),
        onError: (_, _) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.getSize(square), const Size.square(48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty artwork URL falls back without starting a request', (
    tester,
  ) async {
    await mount(tester, Artwork(track: track.copyWith(artworkUrl: '  ')));
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(tester.getSize(square), const Size.square(48));
  });

  testWidgets('narrow row retains space for text enlarged to 200 percent', (
    tester,
  ) async {
    await mount(
      tester,
      const Row(
        children: [
          Artwork(track: track, artworkContext: ArtworkContext.thumbnailDetail),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'A long album title and artist name',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      width: 288,
    );
    expect(tester.getSize(square), const Size.square(64));
    expect(tester.takeException(), isNull);
  });
}
