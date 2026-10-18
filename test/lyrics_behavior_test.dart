import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/ui/lyrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _track = Track(
  id: 'fixture-track',
  artist: 'Fixture Artist',
  title: 'Fixture Artist - Fixture Song (Official Video)',
  duration: Duration(seconds: 180),
  pageUrl: 'https://example.test/fixture-track',
);

class _CountingAudio extends FakeAudio {
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    await super.seek(value);
  }
}

class _ResponseClient extends Fake implements HttpClient {
  _ResponseClient(this.status, this.payload, this.onUri);

  final int status;
  final List<int> payload;
  final void Function(Uri uri) onUri;
  Duration? _connectionTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    onUri(url);
    final request = _ResponseRequest();
    request.response.status = status;
    request.response.payload = payload;
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _ResponseRequest extends Fake implements HttpClientRequest {
  final response = _Response();

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  int status = 200;
  List<int> payload = const [];

  @override
  int get statusCode => status;

  @override
  int get contentLength => payload.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(payload).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeferredLyrics extends LyricsService {
  final results = <String, Completer<LyricsResult>>{};

  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) => (results[track.id] ??= Completer<LyricsResult>()).future;
}

Future<Directory> _temporaryDirectory() =>
    Directory.systemTemp.createTemp('aurora_lyrics_behavior_');

String _payload({
  String artist = 'Fixture Artist',
  String title = 'Fixture Song',
  num duration = 180,
  String lyrics = '[00:01.00]fixture line one\n[00:02.00]fixture line two',
}) => jsonEncode({
  'artistName': artist,
  'trackName': title,
  'duration': duration,
  'syncedLyrics': lyrics,
  'plainLyrics': null,
});

void main() {
  group('LyricsService behavior', () {
    late Directory directory;
    final requestedUris = <Uri>[];

    setUp(() async {
      directory = await _temporaryDirectory();
      requestedUris.clear();
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test(
      'requests exact artist, cleaned title, and HTTPS LRCLIB endpoint',
      () async {
        final service = LyricsService(
          clientFactory: () =>
              _ResponseClient(200, utf8.encode(_payload()), requestedUris.add),
        );
        final result = await service.load(_track, directory);

        expect(result.kind, LyricsKind.synced);
        expect(requestedUris, isNotEmpty);
        expect(requestedUris.first.scheme, 'https');
        expect(requestedUris.first.host, 'lrclib.net');
        expect(requestedUris.first.path, '/api/get');
        expect(requestedUris.first.queryParameters, {
          'artist_name': 'Fixture Artist',
          'track_name': 'Fixture Song',
          'duration': '180',
        });
        service.dispose();
      },
    );

    for (final mismatch in [
      ('artist', _payload(artist: 'Another Artist')),
      ('title', _payload(title: 'Another Song')),
      ('duration', _payload(duration: 190)),
    ]) {
      test('rejects ${mismatch.$1} mismatch', () async {
        final service = LyricsService(
          clientFactory: () =>
              _ResponseClient(200, utf8.encode(mismatch.$2), requestedUris.add),
        );
        final result = await service.load(_track, directory);
        expect(result.kind, LyricsKind.notFound);
        service.dispose();
      });
    }

    test('rejects responses larger than the bounded payload', () async {
      final oversized = utf8.encode(_payload(lyrics: 'x' * (1024 * 1024)));
      final service = LyricsService(
        clientFactory: () => _ResponseClient(200, oversized, requestedUris.add),
      );

      await expectLater(service.load(_track, directory), throwsFormatException);
      service.dispose();
    });

    test('serves the cached result offline without a second request', () async {
      var requestCount = 0;
      final service = LyricsService(
        clientFactory: () => _ResponseClient(
          200,
          utf8.encode(_payload()),
          (_) => requestCount++,
        ),
      );
      final first = await service.load(_track, directory);
      service.dispose();

      final offline = LyricsService(
        clientFactory: () => throw StateError('Offline cache should be used'),
      );
      final second = await offline.load(_track, directory);
      expect(first.lines.map((line) => line.text), [
        'fixture line one',
        'fixture line two',
      ]);
      expect(second.lines.map((line) => line.text), [
        'fixture line one',
        'fixture line two',
      ]);
      expect(requestCount, 1);
      offline.dispose();
    });

    test('dispose cancels pending lookup and discards its result', () async {
      final gate = Completer<void>();
      final client = _PendingClient(gate);
      final service = LyricsService(clientFactory: () => client);
      final pending = service.load(_track, directory);
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      gate.complete();

      expect((await pending).kind, LyricsKind.notFound);
    });
  });

  group('LyricsPanel behavior', () {
    late AppController controller;
    late FakeAudio audio;
    late _DeferredLyrics service;

    setUp(() async {
      audio = _CountingAudio();
      controller = await createTestController(audio: audio);
      service = _DeferredLyrics();
    });

    Future<void> mount(
      WidgetTester tester, {
      double width = 360,
      double scale = 1,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: LyricsPanel(controller: controller, service: service),
          ),
        ),
      );
    }

    tearDown(() async {
      await closeTestController(controller);
      service.dispose();
    });

    testWidgets('seek advances the synced lyric highlight', (tester) async {
      await mount(tester);
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await audio.seek(const Duration(milliseconds: 1500));
      await tester.pump();
      service.results[_track.id]!.complete(
        const LyricsResult(
          LyricsKind.synced,
          lines: [
            LyricLine(Duration(seconds: 1), 'fixture first'),
            LyricLine(Duration(seconds: 2), 'fixture second'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester
            .widget<AnimatedDefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('fixture first'),
                    matching: find.byType(AnimatedDefaultTextStyle),
                  )
                  .first,
            )
            .style
            .fontWeight,
        FontWeight.w700,
      );

      await audio.seek(const Duration(seconds: 3));
      await tester.pump();
      expect(
        tester
            .widget<AnimatedDefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('fixture second'),
                    matching: find.byType(AnimatedDefaultTextStyle),
                  )
                  .first,
            )
            .style
            .fontWeight,
        FontWeight.w700,
      );
      expect(
        tester
            .widget<AnimatedDefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('fixture first'),
                    matching: find.byType(AnimatedDefaultTextStyle),
                  )
                  .first,
            )
            .style
            .fontWeight,
        FontWeight.w400,
      );
    });

    testWidgets(
      'tapping synced lines seeks both ways without changing play state',
      (tester) async {
        await mount(tester);
        controller.queue = [_track];
        controller.queueIndex = 0;
        controller.notifyListeners();
        await controller.togglePlayback();
        service.results[_track.id]!.complete(
          const LyricsResult(
            LyricsKind.synced,
            lines: [
              LyricLine(Duration(seconds: 8), 'earlier lyric'),
              LyricLine(Duration(seconds: 16), 'later lyric'),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          find.text('Toca un verso para ir a ese momento'),
          findsOneWidget,
        );
        expect(find.text('0:08'), findsOneWidget);

        audio.isPlaying = true;
        audio.position = const Duration(seconds: 12);
        audio.notifyListeners();
        await tester.pump();
        await tester.tap(find.text('earlier lyric'));
        await tester.pump();
        expect(audio.position, const Duration(seconds: 8));
        expect(audio.isPlaying, isTrue);

        await tester.tap(find.text('later lyric'));
        await tester.pump();
        expect(audio.position, const Duration(seconds: 16));
        expect(audio.isPlaying, isTrue);

        await controller.pausePlayback();
        audio.position = const Duration(seconds: 12);
        audio.notifyListeners();
        await tester.pump();
        await tester.tap(find.text('earlier lyric'));
        await tester.pump();
        expect(audio.position, const Duration(seconds: 8));
        expect(audio.isPlaying, isFalse);
      },
    );

    testWidgets(
      'player controls seek, adjust volume, toggle playback, and close',
      (tester) async {
        var closed = false;
        await tester.binding.setSurfaceSize(const Size(320, 650));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: LyricsPanel(
                controller: controller,
                service: service,
                onClose: () => closed = true,
              ),
            ),
          ),
        );
        controller.queue = [_track];
        controller.queueIndex = 0;
        controller.notifyListeners();
        service.results[_track.id]!.complete(
          const LyricsResult(LyricsKind.plain, text: 'Plain lyric text'),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Volver'), findsOneWidget);
        expect(
          find.text('Estas letras no tienen marcas de tiempo.'),
          findsOneWidget,
        );
        expect(find.byTooltip('Reproducir'), findsOneWidget);
        expect(
          find.bySemanticsLabel('Posición de reproducción'),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Volumen'), findsOneWidget);

        await tester.tap(find.byTooltip('Reproducir'));
        await tester.pumpAndSettle();
        expect(audio.isPlaying, isTrue);
        await tester.tap(find.byTooltip('Pausar'));
        await tester.pumpAndSettle();
        expect(audio.isPlaying, isFalse);

        final progressSlider = find.byType(Slider).first;
        final countingAudio = audio as _CountingAudio;
        countingAudio.seeks.clear();
        await tester.drag(progressSlider, const Offset(45, 0));
        await tester.pump();
        expect(audio.position, greaterThan(Duration.zero));
        expect(audio.isPlaying, isFalse);
        expect(countingAudio.seeks, hasLength(1));

        final volumeSlider = find.byType(Slider).last;
        await tester.drag(volumeSlider, const Offset(-40, 0));
        await tester.pump();
        expect(audio.volume, lessThan(.75));

        await tester.tap(find.text('Volver'));
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('progress drag previews then commits only on release', (
      tester,
    ) async {
      await mount(tester);
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await controller.togglePlayback();
      await tester.pump();
      final countingAudio = audio as _CountingAudio;
      countingAudio.seeks.clear();

      final slider = find.byType(Slider).first;
      await tester.drag(slider, const Offset(90, 0));
      await tester.pump();
      expect(countingAudio.seeks, hasLength(1));
      expect(audio.position, greaterThan(Duration.zero));
      expect(audio.isPlaying, isTrue);
    });

    testWidgets('track change discards an unfinished progress preview', (
      tester,
    ) async {
      await mount(tester);
      const nextTrack = Track(
        id: 'next-fixture',
        artist: 'Fixture Artist',
        title: 'Next Fixture Song',
        duration: Duration(seconds: 180),
        pageUrl: 'https://example.test/next-fixture',
      );
      controller.queue = [_track, nextTrack];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await controller.togglePlayback();
      await tester.pump();
      final countingAudio = audio as _CountingAudio;
      countingAudio.seeks.clear();

      final slider = find.byType(Slider).first;
      final center = tester.getCenter(slider);
      final gesture = await tester.startGesture(center);
      for (var step = 1; step <= 5; step++) {
        await gesture.moveTo(
          center + Offset(step * 18, 0),
          timeStamp: Duration(milliseconds: step * 20),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(countingAudio.seeks, isEmpty);
      expect(audio.position, Duration.zero);
      expect(tester.widget<Slider>(slider).value, greaterThan(0));

      controller.queueIndex = 1;
      controller.notifyListeners();
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(countingAudio.seeks, isEmpty);
      expect(
        tester.widget<Slider>(slider).value,
        audio.position.inMilliseconds,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'discards stale track result and handles narrow enlarged text',
      (tester) async {
        await mount(tester, width: 320, scale: 2);
        final first = _track;
        const second = Track(
          id: 'second-fixture',
          artist: 'Fixture',
          title: 'Second Fixture Song',
          pageUrl: 'https://example.test/second-fixture',
        );
        controller.queue = [first, second];
        controller.queueIndex = 0;
        controller.notifyListeners();
        await tester.pump();
        controller.queueIndex = 1;
        controller.notifyListeners();
        await tester.pump();
        service.results[first.id]!.complete(
          const LyricsResult(LyricsKind.plain, text: 'stale fixture result'),
        );
        service.results[second.id]!.complete(
          const LyricsResult(LyricsKind.plain, text: 'current fixture result'),
        );
        await tester.pumpAndSettle();

        expect(find.text('stale fixture result'), findsNothing);
        expect(find.text('current fixture result'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('muestra «Buscando letra…» mientras carga', (tester) async {
      await mount(tester);
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('Buscando letra…'), findsOneWidget);
    });

    testWidgets('sin letra ofrece Reintentar y Buscar otra letra', (
      tester,
    ) async {
      await mount(tester);
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await tester.pump();
      service.results[_track.id]!.complete(
        const LyricsResult(LyricsKind.notFound),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin letra disponible'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Buscar otra letra'), findsOneWidget);
    });

    testWidgets('indica origen y si la letra es sincronizada o guardada', (
      tester,
    ) async {
      await mount(tester, width: 1100);
      controller.queue = [_track];
      controller.queueIndex = 0;
      controller.notifyListeners();
      await tester.pump();
      service.results[_track.id]!.complete(
        const LyricsResult(
          LyricsKind.synced,
          source: 'LRCLIB',
          lines: [LyricLine(Duration(seconds: 1), 'fixture first')],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('LRCLIB · SINCRONIZADA'), findsOneWidget);
    });
  });
}

class _PendingClient extends Fake implements HttpClient {
  _PendingClient(this.gate);
  final Completer<void> gate;
  Duration? _connectionTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    await gate.future;
    final request = _ResponseRequest();
    request.response.payload = utf8.encode(_payload());
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
