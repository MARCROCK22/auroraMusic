import 'package:aurora_music/audio/music_audio.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'YouTube stream stays on the same song beyond two minutes',
    (tester) async {
      final passed = await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final source = YtDlpSource(await SharedPreferences.getInstance());
        final audio = MusicAudio();
        var completions = 0;
        final subscription = audio.completed.listen((_) => completions++);
        try {
          await source.configureToolDirectory(
            const String.fromEnvironment('AURORA_TOOLS'),
          );
          final tracks = await source.search(
            const String.fromEnvironment('AURORA_SAMPLE_URL'),
            limit: 1,
          );
          final resolved = await source.resolve(tracks.single);
          expect(resolved.duration, greaterThan(const Duration(seconds: 150)));
          await audio.initialize();
          audio.setVolume(0);
          const initialPosition = Duration(
            milliseconds: int.fromEnvironment('AURORA_INITIAL_POSITION_MS'),
          );
          await audio.load(
            resolved,
            ffmpegExecutable: source.ffmpegExecutable,
            start: initialPosition,
          );
          await audio.play();
          final deadline = DateTime.now().add(const Duration(seconds: 160));
          while (audio.position <
              initialPosition + const Duration(seconds: 130)) {
            expect(audio.lastError, isNull);
            expect(completions, 0);
            expect(audio.isPlaying, isTrue);
            if (DateTime.now().isAfter(deadline)) {
              fail('Online playback did not reach 130 seconds');
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(completions, 0);
          expect(audio.lastError, isNull);
          if (const bool.fromEnvironment('AURORA_CHECK_EOF')) {
            final ended = audio.completed.first;
            await audio.seek(resolved.duration - const Duration(seconds: 3));
            await ended.timeout(const Duration(seconds: 20));
            expect(completions, 1);
            expect(audio.lastError, isNull);
          }
          return true;
        } finally {
          await subscription.cancel();
          await audio.stop();
          audio.dispose();
          source.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      });
      expect(passed, isTrue);
    },
    skip: !const bool.fromEnvironment('AURORA_ONLINE_SMOKE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
