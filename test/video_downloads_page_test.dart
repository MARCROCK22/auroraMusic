import 'dart:io';

import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:aurora_music/ui/video_downloads_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aurora/source');
  late YtDlpSource source;
  late Directory support;
  var requests = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    support = await Directory.systemTemp.createTemp('aurora-video-page-');
    requests = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'downloadVideo') {
        requests++;
        await File(
          '${call.arguments['directory']}/video.mp4',
        ).writeAsBytes([1, 2]);
      }
      return null;
    });
    source = YtDlpSource(
      await SharedPreferences.getInstance(),
      androidOverride: true,
    );
  });

  tearDown(() async {
    source.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await support.delete(recursive: true);
  });

  testWidgets('Music URLs show validation and never start a video download', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoDownloadsPage(source: source, supportDirectory: support),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/watch?v=abcdefghijk',
    );
    await tester.pump();
    await tester.tap(find.text('Descargar video'));
    await tester.pump();
    expect(find.text('Usa un enlace HTTPS público de un video de YouTube.'), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('a public video is staged and shown as completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoDownloadsPage(source: source, supportDirectory: support),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/watch?v=abcdefghijk',
    );
    await tester.pump();
    await tester.tap(find.text('Descargar video'));
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (find.text('abcdefghijk.mp4').evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pump();
    expect(requests, 1, reason: find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | '));
    expect(find.text('abcdefghijk.mp4'), findsOneWidget);
    expect(
      File('${support.path}/downloads/videos/abcdefghijk.mp4').existsSync(),
      isTrue,
    );
  });
}
