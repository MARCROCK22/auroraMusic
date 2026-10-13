import 'dart:async';

import 'package:adblocker_webview/adblocker_webview.dart';
import 'package:aurora_music/youtube_music/youtube_music_ad_blocker.dart';
import 'package:aurora_music/youtube_music/youtube_music_navigation.dart';
import 'package:aurora_music/youtube_music/youtube_music_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeMusicPlatform extends YouTubeMusicPlatform {
  FakeMusicPlatform({this.blocker}) {
    blocker?.addListener(update);
  }

  final YouTubeMusicAdBlocker? blocker;
  @override
  YouTubeMusicAdBlocker? get adBlocker => blocker;
  int builds = 0;
  int backCalls = 0;
  int forwardCalls = 0;
  int reloadCalls = 0;
  bool disposed = false;
  bool failReload = false;
  Completer<void>? initialization;
  Uri? initialUri;

  @override
  Future<void> initialize() async {
    await initialization?.future;
    ready = true;
    loading = false;
  }

  @override
  Widget buildView(Uri initialUri) {
    builds++;
    this.initialUri = initialUri;
    return const ColoredBox(
      key: ValueKey('fake-official-view'),
      color: Colors.black,
    );
  }

  void update() => notifyListeners();

  @override
  Future<void> goBack() async {
    backCalls++;
    canGoBack = false;
    canGoForward = true;
    notifyListeners();
  }

  @override
  Future<void> goForward() async {
    forwardCalls++;
    canGoForward = false;
    canGoBack = true;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    reloadCalls++;
    if (failReload) throw StateError('offline');
    error = null;
    notice = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    blocker?.removeListener(update);
    blocker?.dispose();
    super.dispose();
  }
}

class FakePageFilter extends AdBlockerWebviewControllerImpl {
  @override
  Future<void> initialize(FilterConfig config) async {}
  @override
  Future<void> dispose() async {}
}

Future<void> showPage(
  WidgetTester tester,
  FakeMusicPlatform platform, {
  GlobalKey<YouTubeMusicPageState>? pageKey,
  VoidCallback? onClosed,
  Uri? initialUri,
  Future<bool> Function(Uri)? openExternal,
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
      home: YouTubeMusicPage(
        key: pageKey,
        platform: platform,
        onClosed: onClosed,
        initialUri: initialUri,
        openExternal: openExternal ?? (_) async => true,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'ad filter toggle retains WebView and fits 320px enlarged layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final blocker = YouTubeMusicAdBlocker(controller: FakePageFilter());
      await blocker.initialize();
      final platform = FakeMusicPlatform(blocker: blocker)
        ..error = 'Sin conexión';
      await showPage(tester, platform, textScale: 2);
      expect(find.text('Filtro de anuncios'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(blocker.enabled, isFalse);
      expect(find.text('Desactivado'), findsOneWidget);
      expect(platform.builds, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('full-size fake website survives history and loading rebuilds', (
    tester,
  ) async {
    final platform = FakeMusicPlatform()..canGoBack = true;
    await showPage(tester, platform);
    expect(platform.initialUri, youtubeMusicHome);
    expect(find.byKey(const ValueKey('fake-official-view')), findsOneWidget);
    await tester.tap(find.byTooltip('Atrás'));
    await tester.pump();
    expect(platform.backCalls, 1);
    await tester.tap(find.byTooltip('Adelante'));
    await tester.pump();
    expect(platform.forwardCalls, 1);
    platform.loading = true;
    platform.progress = .4;
    platform.update();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(platform.builds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android back uses history before asking to close unknown playback',
    (tester) async {
      final platform = FakeMusicPlatform()..canGoBack = true;
      final key = GlobalKey<YouTubeMusicPageState>();
      var closed = 0;
      await showPage(tester, platform, pageKey: key, onClosed: () => closed++);
      await key.currentState!.handleBack();
      await tester.pump();
      expect(platform.backCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
      unawaited(key.currentState!.handleBack());
      await tester.pumpAndSettle();
      expect(find.text('¿Salir de YouTube Music?'), findsOneWidget);
      await tester.tap(find.text('Quedarme'));
      await tester.pumpAndSettle();
      expect(closed, 0);
      unawaited(key.currentState!.handleBack());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(closed, 1);
    },
  );

  testWidgets(
    'shell confirmExit is deduplicated and never closes the page itself',
    (tester) async {
      final platform = FakeMusicPlatform();
      final key = GlobalKey<YouTubeMusicPageState>();
      var closed = false;
      await showPage(
        tester,
        platform,
        pageKey: key,
        onClosed: () => closed = true,
      );
      final first = key.currentState!.confirmExit();
      final second = key.currentState!.confirmExit();
      expect(identical(first, second), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(closed, isFalse);
      expect(platform.builds, 1);
    },
  );

  testWidgets('network error retries and Google login opens only public home', (
    tester,
  ) async {
    final platform = FakeMusicPlatform()..error = 'Sin conexión';
    Uri? opened;
    await showPage(
      tester,
      platform,
      openExternal: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(find.text('Sin conexión'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(platform.reloadCalls, 1);
    expect(find.text('Sin conexión'), findsNothing);
    platform.notice = 'Google puede restringir el acceso desde esta vista.';
    platform.update();
    await tester.pump();
    await tester.tap(find.text('Abrir en navegador'));
    await tester.pump();
    expect(opened, youtubeMusicHome);
    expect(platform.builds, 1);
  });

  testWidgets(
    'failed command and unavailable browser surface recovery actions',
    (tester) async {
      final platform = FakeMusicPlatform()..failReload = true;
      await showPage(tester, platform, openExternal: (_) async => false);
      await tester.tap(find.byTooltip('Recargar'));
      await tester.pump();
      expect(find.textContaining('No se pudo completar'), findsOneWidget);
      platform.failReload = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(find.textContaining('No se pudo completar'), findsNothing);
      await tester.tap(find.byTooltip('Abrir en navegador'));
      await tester.pump();
      expect(find.textContaining('No se pudo completar'), findsOneWidget);
    },
  );

  testWidgets(
    '320px layout with enlarged text, errors and confirmation stays usable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = FakeMusicPlatform()
        ..error =
            'No se pudo cargar YouTube Music. Revisa tu conexión e inténtalo de nuevo.';
      await showPage(tester, platform, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar YouTube Music'));
      await tester.pumpAndSettle();
      expect(find.text('Quedarme'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rejects an unsafe initial URL without constructing native view',
    (tester) async {
      final platform = FakeMusicPlatform();
      await showPage(
        tester,
        platform,
        initialUri: Uri.parse('https://example.com'),
      );
      expect(platform.builds, 0);
      expect(find.textContaining('No se pudo abrir'), findsOneWidget);
    },
  );

  testWidgets('late initialization after removal never constructs a view', (
    tester,
  ) async {
    final done = Completer<void>();
    final platform = FakeMusicPlatform()..initialization = done;
    await showPage(tester, platform);
    await tester.pumpWidget(const SizedBox());
    done.complete();
    await tester.pump();
    expect(platform.builds, 0);
    expect(platform.disposed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
