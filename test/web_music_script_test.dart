import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/audio_web/web_music_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the page script against a minimal fake DOM in Node (skipped without
/// Node). Covers what a fake Dart bridge cannot: real event waiting, the
/// AbortError retry, ad mute/skip and seeking before metadata.
const _harness = r'''
class Media {
  constructor() {
    Object.assign(this, {listeners: {}, paused: true, ended: false, readyState: 4,
      currentTime: 0, duration: 200, volume: 1, muted: false, error: null,
      tagName: 'VIDEO', style: {setProperty() {}}, playImpl: null, plays: 0});
  }
  addEventListener(name, listener) { (this.listeners[name] ??= []).push(listener); }
  removeEventListener(name, listener) {
    this.listeners[name] = (this.listeners[name] || []).filter(item => item !== listener);
  }
  emit(name) { for (const listener of [...(this.listeners[name] || [])]) listener(); }
  play() {
    this.plays++;
    if (this.playImpl) return this.playImpl(this);
    this.paused = false;
    setTimeout(() => { this.currentTime += 0.25; this.emit('playing'); this.emit('timeupdate'); }, 5);
    return Promise.resolve();
  }
  pause() { this.paused = true; }
}
const page = {};
globalThis.window = globalThis;
globalThis.location = {origin: 'https://music.youtube.com', get href() { return page.href; }};
globalThis.document = {
  querySelector(selector) {
    if (selector === 'video, audio') return page.media;
    if (selector.includes('.ad-showing')) return page.ad ? {} : null;
    return null;
  },
  querySelectorAll(selector) {
    if (selector.includes('skip')) return page.skip ? [page.skip] : [];
    return [];
  },
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const script = new AsyncFunction('action', 'expectedId', 'generation', 'value', 'timeoutMs', SCRIPT);
const id = 'AAAAAAAAAAA';
let generation = 0;
const reset = () => {
  generation++;
  window.__auroraMediaObservation = undefined;
  Object.assign(page, {media: new Media(), ad: false, skip: null,
    href: `https://music.youtube.com/watch?v=${id}`});
};
const run = (action, value = null, timeoutMs = 1000) => script(action, id, generation, value, timeoutMs);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const results = {};
(async () => {
  reset();
  results.play = await run('play');

  reset();
  const first = page.media;
  first.playImpl = () => {
    const next = new Media();
    next.readyState = 1;
    page.media = next;
    setTimeout(() => { next.readyState = 4; next.emit('loadeddata'); }, 20);
    const error = new Error('replaced');
    error.name = 'AbortError';
    return Promise.reject(error);
  };
  results.abort = await run('play');
  results.abortRetried = page.media !== first && page.media.plays === 1;

  reset();
  page.media.playImpl = () => new Promise(() => {});
  results.timeout = await run('play', null, 50);
  results.timeoutPaused = page.media.paused;

  reset();
  page.media.playImpl = () => {
    const error = new Error('gesture');
    error.name = 'NotAllowedError';
    return Promise.reject(error);
  };
  results.blocked = await run('play');

  reset();
  page.media.playImpl = () => {
    const error = new Error('https://secret.example/token');
    error.name = 'WeirdSecretError';
    return Promise.reject(error);
  };
  results.failed = await run('play');

  reset();
  await run('snapshot');
  page.ad = true;
  page.skip = {disabled: false, clicks: 0, getClientRects() { return [1]; }, click() { this.clicks++; }};
  results.ad = await run('snapshot');
  results.adMuted = page.media.muted;
  results.adSkipClicks = page.skip.clicks;
  page.media.emit('ended');
  results.adEnded = (await run('snapshot')).ended;
  page.ad = false;
  page.media.emit('timeupdate');
  results.adRestored = !page.media.muted;

  reset();
  page.media.readyState = 0;
  page.media.duration = NaN;
  results.earlySeek = await run('seek', 42);
  results.earlySeekApplied = page.media.currentTime;
  page.media.readyState = 1;
  page.media.duration = 200;
  page.media.emit('loadedmetadata');
  results.lateSeekApplied = page.media.currentTime;

  reset();
  page.href = 'https://music.youtube.com/watch?v=BBBBBBBBBBB';
  results.different = await run('snapshot');

  location.origin = 'https://consent.youtube.com';
  results.website = await run('snapshot');
  console.log(JSON.stringify(results));
})().catch(error => { console.error(error); process.exit(1); });
''';

void main() {
  final hasNode = () {
    try {
      return Process.runSync('node', ['--version']).exitCode == 0;
    } catch (_) {
      return false;
    }
  }();

  test(
    'page script waits for playback, retries AbortError and handles ads',
    () async {
      final directory = await Directory.systemTemp.createTemp('aurora_js');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/harness.js');
      await file.writeAsString(
        _harness.replaceFirst('SCRIPT', jsonEncode(webMusicMediaScript)),
      );
      final run = await Process.run('node', [file.path]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      final r = jsonDecode(run.stdout as String) as Map<String, dynamic>;

      expect(r['play']['status'], 'ready');
      expect(r['play']['playing'], isTrue);

      expect(r['abort']['status'], 'ready');
      expect(r['abort']['playing'], isTrue);
      expect(r['abortRetried'], isTrue);

      expect(r['timeout']['status'], 'playTimeout');
      expect(r['timeout']['errorName'], 'TimeoutError');
      expect(r['timeoutPaused'], isTrue);

      expect(r['blocked']['status'], 'playBlocked');
      expect(r['failed']['status'], 'commandFailed');
      expect(r['failed']['errorName'], 'Error');
      expect(jsonEncode(r['failed']), isNot(contains('secret')));

      expect(r['ad']['adPlaying'], isTrue);
      expect(r['adMuted'], isTrue);
      expect(r['adSkipClicks'], 1);
      expect(r['adEnded'], isFalse);
      expect(r['adRestored'], isTrue);

      expect(r['earlySeek']['status'], 'ready');
      expect(r['earlySeekApplied'], 0);
      expect(r['lateSeekApplied'], 42);

      expect(r['different']['status'], 'differentTrack');
      expect(r['website']['status'], 'website');
    },
    skip: hasNode ? false : 'Node.js no está disponible',
  );
}
