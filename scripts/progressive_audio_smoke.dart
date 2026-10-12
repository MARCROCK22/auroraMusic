import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:aurora_music/sources/progressive_audio_relay.dart';

/// Offline decoder proof: `dart scripts/progressive_audio_smoke.dart <ffmpeg>`.
Future<void> main(List<String> args) async {
  if (args.length != 1 || !File(args.single).existsSync()) {
    throw ArgumentError('Pass the bundled ffmpeg executable path.');
  }
  final directory = await Directory.systemTemp.createTemp(
    'aurora-relay-smoke-',
  );
  final processes = <Process>[];
  ProgressiveAudioRelay? relay;
  Future<void>? writer;
  var cancelled = false;
  try {
    final fixture = File('${directory.path}/fixture.webm');
    final generated = await Process.run(args.single, [
      '-nostdin',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:sample_rate=48000',
      '-t',
      '12',
      '-c:a',
      'libopus',
      '-b:a',
      '128k',
      fixture.path,
    ], runInShell: false);
    if (generated.exitCode != 0) {
      throw StateError('Unable to generate WebM fixture.');
    }
    final bytes = await fixture.readAsBytes();
    final growing = File('${directory.path}/growing.webm');
    await growing.writeAsBytes(bytes.sublist(0, 4096));
    final completion = Completer<File>();
    relay = await ProgressiveAudioRelay.start(
      file: growing,
      completed: completion.future,
      expectedBytes: bytes.length,
      cancel: () async {
        cancelled = true;
      },
    );
    final activeRelay = relay;
    writer = () async {
      try {
        for (var offset = 4096; offset < bytes.length; offset += 4096) {
          await Future<void>.delayed(const Duration(milliseconds: 90));
          if (cancelled) return;
          await growing.writeAsBytes(
            bytes.sublist(offset, min(offset + 4096, bytes.length)),
            mode: FileMode.append,
          );
        }
        // The generated fixture has known audio and duration. Real source
        // additionally probes and fully decodes before calling publishTo.
        completion.complete(
          await activeRelay.publishTo(File('${directory.path}/trusted.audio')),
        );
      } catch (error, stack) {
        if (!completion.isCompleted) completion.completeError(error, stack);
      }
    }();
    await relay.waitUntilReady();

    Future<int> decode(int offset, {Completer<void>? first}) async {
      final process = await Process.start(args.single, [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        if (offset > 0) ...['-ss', '$offset'],
        '-i',
        activeRelay.uri.toString(),
        '-vn',
        '-f',
        'f32le',
        '-acodec',
        'pcm_f32le',
        '-ar',
        '48000',
        '-ac',
        '2',
        'pipe:1',
      ], runInShell: false);
      processes.add(process);
      final errors = process.stderr.drain<void>();
      var pcmBytes = 0;
      await for (final chunk in process.stdout) {
        pcmBytes += chunk.length;
        if (first != null && !first.isCompleted) first.complete();
        if (pcmBytes > 12 * 48000 * 8) {
          throw StateError('Unexpected PCM bound.');
        }
      }
      await errors;
      if (await process.exitCode != 0) {
        throw StateError('Decoder failed at $offset seconds.');
      }
      if (pcmBytes % 8 != 0) throw StateError('Unaligned PCM output.');
      return pcmBytes ~/ 8;
    }

    final first = Completer<void>();
    final full = decode(0, first: first);
    await first.future.timeout(const Duration(seconds: 3));
    if (completion.isCompleted) {
      throw StateError('Playback waited for the full download.');
    }
    stdout.writeln('PASS: PCM started before download completion.');
    final forwardFirst = Completer<void>();
    final forward = decode(9, first: forwardFirst);
    final backward = decode(1);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (forwardFirst.isCompleted) {
      throw StateError('Seek returned audio from the unavailable range.');
    }
    final frames = await Future.wait([
      full,
      forward,
      backward,
    ]).timeout(const Duration(seconds: 20));
    // Opus seeking can retain 1 ms of encoder delay (48 frames).
    if (frames[0] != 576000 ||
        (frames[1] - 144000).abs() > 48 ||
        (frames[2] - 528000).abs() > 48) {
      throw StateError('False EOF / wrong seek frame counts: $frames');
    }
    stdout.writeln(
      'PASS: full playback and forward/backward seeks produced $frames frames without false EOF.',
    );
  } finally {
    cancelled = true;
    for (final process in processes) {
      process.kill();
    }
    await relay?.dispose();
    await writer;
    await directory.delete(recursive: true);
  }
}
