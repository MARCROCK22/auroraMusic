import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aurora_music/audio/music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'support/soak_fixture.dart';

/// Standalone release entrypoint: writes durable evidence without VM service.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Aurora · prueba continua de audio')),
      ),
    ),
  );
  unawaited(_run());
}

Future<void> _run() async {
  const minutes = int.fromEnvironment('AURORA_SOAK_MINUTES', defaultValue: 30);
  const configuredLog = String.fromEnvironment('AURORA_SOAK_LOG');
  final log = File(
    configuredLog.isEmpty
        ? path.join(Directory.systemTemp.path, 'aurora_soak_$pid.jsonl')
        : configuredLog,
  );
  final audio = MusicAudio();
  File? fixture;
  var initialized = false;
  var result = 1;
  Future<void> record(Map<String, Object?> event) => log.writeAsString(
    '${jsonEncode(event)}\n',
    mode: FileMode.append,
    flush: true,
  );
  try {
    if (minutes < 1 || minutes > 350) throw ArgumentError.value(minutes);
    await record({
      'event': 'start',
      'minutes': minutes,
      'pid': pid,
      'time': DateTime.now().toUtc().toIso8601String(),
    });
    fixture = await createSoakFixture(minutes * 60 + 20);
    await audio.initialize();
    initialized = true;
    audio.setVolume(0.005);
    await audio.load(ResolvedAudio(input: fixture.path));
    await audio.play();
    final elapsed = Stopwatch()..start();
    await Future<void>.delayed(const Duration(seconds: 10));
    final baseline = ProcessInfo.currentRss;
    var maximum = baseline;
    var previous = audio.position;
    if (previous < const Duration(seconds: 8)) {
      throw StateError('El reloj de audio no inició correctamente');
    }
    while (elapsed.elapsed < Duration(minutes: minutes)) {
      await Future<void>.delayed(const Duration(seconds: 10));
      if (audio.lastError != null) throw StateError(audio.lastError!);
      if (!audio.isPlaying ||
          audio.isBuffering ||
          audio.position - previous < const Duration(seconds: 8)) {
        throw StateError('La reproducción dejó de avanzar');
      }
      previous = audio.position;
      final rss = ProcessInfo.currentRss;
      maximum = math.max(maximum, rss);
      await record({
        'event': 'sample',
        'elapsedSeconds': elapsed.elapsed.inSeconds,
        'positionMs': audio.position.inMilliseconds,
        'rss': rss,
        'maxRss': maximum,
        'baseline': baseline,
      });
    }
    await record({
      'event': 'complete',
      'minutes': minutes,
      'elapsedSeconds': elapsed.elapsed.inSeconds,
      'positionMs': audio.position.inMilliseconds,
      'maxRss': maximum,
      'maxGrowthBytes': maximum - baseline,
    });
    result = 0;
  } catch (error, stack) {
    await record({'event': 'failed', 'error': '$error', 'stack': '$stack'});
  } finally {
    if (initialized) {
      await audio.stop();
      audio.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (fixture != null) await fixture.parent.delete(recursive: true);
  }
  exit(result);
}
