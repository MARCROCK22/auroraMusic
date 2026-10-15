> **Reemplazado (v1.1.0, 2026-10-15).** El motor WebView descrito aquí fue sustituido por el motor InnerTube de solo audio con streaming nativo (Media3 en Android, SoLoud + FFmpeg en Windows). Se conserva como historial. Ver [README](../README.md) y [architecture.md](architecture.md).

# Aurora audio-only routing audit and controller integration

Audit date: 2026-10-13. Baseline: `139251b` (`Integrate web player navigation and preserve video downloads`). This branch implements the controller/source portion after the coordinator expanded ownership; the WebView engine and app/shell wiring are separate work. No live account, personal library, signed media URL, cookie, or actual device playback was inspected.

## Finding and smallest honest integration

The baseline implements a full-size official YouTube Music website, not an audio backend controlled by Aurora. `lib/main.dart` constructs `WebMusicSource(YtDlpSource(preferences))` and selects `MusicAudio` on Windows or `AndroidMusicAudio` on Android. The official website owns its own queue/session, while `AppController.queue` owns native playback. Merely hiding that website would leave Aurora without verified playback state, completion, seek, or pause control.

The smallest integration keeps `AppController.queue` and the existing `AudioBackend` contract. An independently validated routed backend receives an official watch-page identifier for YouTube items and delegates local files/direct non-YouTube media to the existing native backend. There is no second personal queue and no yt-dlp streaming, extraction, privileged-content scraping, or cookie transfer. Jam intentionally remains a separate shared-session queue that temporarily owns the same audio backend.

This branch introduces `WebMusicSource(delegate, audioOnly: true)` as opt-in; the default stays the legacy full-site mode. The source's `usesYouTubeWebAudio` flag is separate from `usesOfficialYouTubeMusic`. An official watch-page URL is an engine input identifier, **not a decoded audio URL**: wiring this mode directly to SoLoud, FFmpeg or ExoPlayer is invalid. Root must opt in only with the corresponding WebView/routed engine and present honest errors when ordinary page media is unavailable.

## Route inventory

| Entry / exact module | Baseline behavior | Audio mode behavior implemented here |
| --- | --- | --- |
| Startup, `lib/main.dart` | Native audio plus full-site `WebMusicSource` | Root must supply routed engine and opt into `audioOnly`; this worker does not edit bootstrap |
| Song/album/library/playlist taps, `lib/app_controller.dart`: `playTrack`, `_playTrack`, `_playCurrent` | Online YouTube navigates before mutating native queue; native context excludes online items | Online watch identifiers and local/direct sources share controller queue and persistence |
| Queue tap/enqueue, `playQueueAt`, `addToQueue` | Online YouTube opens website without selecting/enqueuing native item | Existing queue operations select and enqueue web items normally |
| Next/previous/shuffle/repeat/completion, controller transport methods | Ignores commands during website playback; native navigation skips online entries | Uses Aurora transport and playable items; backend completion must report real end and position |
| Historical local YouTube file, `_playCurrent`, `WebMusicSource.resolve` | Existing file wins; missing file falls back to website | Existing file still wins; missing file uses official watch identifier without extracting audio |
| Legacy `yt:<video-id>` with absent `pageUrl`, `_playCurrent` | Full-site navigation can rebuild ID | Valid ID reaches web backend; controller no longer rejects it just because `pageUrl` is absent |
| Search, `AppController.search`, `WebMusicSource.search` | Shared search covers native library; website performs independent online search | Saved playable metadata plus explicit HTTPS watch links, optionally merged with actual official-site metadata via callback; generic links remain labeled `YouTube Music` until actual public metadata arrives |
| Recommendations / personal DJ, `lib/app_controller.dart` and `lib/dj/recommendations.dart` | Native library recommendations; online discovery disabled in full-site mode | Saved playable metadata can seed personal DJ; remote discovery enabled only when a real metadata callback is supplied |
| Spotify imports/matches, `findSpotifyMatches`, `matchSpotifyTrack`, `importSpotifyMetadataMatch` | Full-site search/navigation; native queue isolated | Real saved candidates with matching identity or exact title/artist, plus optional official-site search candidates; explicit chosen match enters Aurora queue; unmatched Spotify item has no playable audio |
| YouTube playlist import, `AppController.importPlaylist`, `WebMusicSource.importPlaylist` | Opens full-site playlist; does not list tracks | Reports unsupported extraction; add individual watch links or use an existing saved Aurora playlist |
| Audio downloads, `canDownloadTrack`, `downloadTrack`, `WebMusicSource.download` | Official online audio rejected; direct HTTPS media downloaded without yt-dlp | Same restriction, including stale local paths; availability helper rejects pending Spotify and existing local files before jobs are created |
| Explicit video downloads, `lib/ui/video_downloads_page.dart`, `WebMusicSource.downloadVideo` | Delegates to yt-dlp utility | Preserved; no playback-source resolution is delegated |
| Jam, `lib/jam/jam_playback_bridge.dart` | Native files/direct streams synchronize; web track opens website with synchronization warning | Source can return watch identifier to routed backend; actual web seek/drift/background capability remains engine/device-dependent |
| Native controls, `lib/audio/media_controls.dart`, `lib/audio/android_music_audio.dart` | Windows binds supplied backend; Android controller checks concrete class | Controller uses common `mediaActions` and `updateTrackMetadata` APIs so a routed wrapper can forward native actions/metadata |
| Shell/mini-player/vinyl/lyrics, `lib/ui/aurora_shell.dart`, `lib/ui/studio/studio_transport.dart` | Hides Aurora transport for full-site section; all native transport/position/spectrum comes from `controller.audio` | Root must retain Aurora surfaces and mount engine independently; active-route EQ/FFT capability must be reported honestly |

The UI routes in home/library, `lib/ui/queue_panel.dart`, vinyl, studio downloads/session aside, Spotify matching and DJ already funnel personal playback through controller methods. Jam is the additional direct `source.resolve` / `audio.load` consumer. Existing native adapters accept concrete files/media URLs and cannot interpret official page identifiers themselves.

## Native initialization diagnosis and fix

At baseline, `AppController.initialize` placed these operations in one outer `try`, before `audio.initialize`:

1. Database reads (`readTracks`, favorites, playlists, downloads).
2. Legacy downloads-directory creation and destination-root migration/saves.
3. History decoding, preference restore, and queue restore.
4. Tool-directory configuration (this individual error is caught locally).

An exception in steps 1–3 skipped native initialization, listeners, media controls and update initialization. The outer `catch` stored an error, but `finally` still set `ready=true`, and `AuroraBootstrap._createController` returned the controller normally. A successful WebView launch did not prove native audio existed.

This branch separates library restoration from audio initialization. Audio initialization is attempted even if restoration fails; the restoration error remains visible. Successful audio initialization is retained across restoration retries, and completion/action subscriptions are not duplicated. If audio initialization fails, `ready=false`, playback does not call native load, and a retry can initialize successfully. `ready` now denotes successful backend initialization, not successful library restoration or guaranteed audibility.

Root must handle `ready=false` and expose startup retry: baseline bootstrap ignores that flag. Database failures may still prevent library operations/persistence even when native audio initialized; this fix does not pretend to repair database corruption.

The coordinator's idle guard in `openYouTubeMusic` remains: native pause runs only when `isPlaying || isBuffering`. It prevents an unnecessary command to an uninitialized idle backend, but is not an initialization fix. `AndroidMusicAudio.pause` invokes the native channel; `android/app/src/main/kotlin/com/aurora/aurora_music/AuroraAudioPlugin.kt` returns `AUDIO_NOT_INITIALIZED` whenever a non-initialize command arrives before the service exists. Conversely, current `MusicAudio.pause` calls SoLoud only when a handle exists, so a fresh idle Windows instance should not throw from that statement alone. The reported Windows `AudioNotInitialized` origin needs a sanitized stack/platform/error-code observation; this audit does not claim to reproduce that exact native exception.

Useful diagnostics are stage identifiers (`library_restore`, `audio_initialize`, `media_controls`, `tool_updates`), platform, success booleans, native error code and whether the backend was loaded/playing/buffering. Do not log exception paths from a user's library, page queries, request headers, cookies, account data or signed media locations. Regression fixtures use only synthetic metadata and temporary directories.

## Shared backend contract for root

`lib/core/audio_backend.dart` adds defaults:

```dart
Stream<String> get mediaActions => const Stream.empty();
Track? get currentTrackMetadata => null;
Future<void> updateTrackMetadata(Track track) async {}
```

Root owns the Android overrides/adapter and routed wrapper. The wrapper must expose native media actions even when the WebView route is selected, delegate platform metadata appropriately, and keep the active route's position, duration, buffering, errors, completion and capabilities coherent. Windows continues to use `MediaControls` on the supplied backend; Android uses `mediaActions`, so there should be no duplicate control owner.

The coordinator subsequently requested the optional source callback `Future<List<Track>> Function(String query, {int limit})? metadataSearch`. It is implemented without changing the default offline/link-only behavior. `SourceBackend.supportsOnlineMetadataSearch` becomes true only for audio mode with a supplied callback. Non-URL text can query the separate official-site metadata module; direct watch links bypass it, unrelated URLs do not become search queries, returned results are canonicalized/deduplicated/bounded and cannot inject local files or signed-media inputs. Controller search preserves saved matches if the website callback fails and reports the failure. Root owns that module's lifecycle and must mount/wire it separately so search never navigates the playback engine. DOM/site changes, login restrictions and unavailable results can make website metadata search fail; this branch's fake callbacks do not prove live search works.

For public page metadata, the controller only replaces a generic pasted-link title when `currentTrackMetadata.id` equals the current canonical `yt:<video-id>`. It rejects stale IDs and local routes, preserves identity/album/genres/Spotify flags, updates in-memory state before one database save, and ignores repeat callbacks after the placeholder has been replaced. Saved curated titles remain intact.

An acceptable engine contract must demonstrate real `load/play/pause/stop/seek`, loading/error/cancellation, reliable track-scoped completion, and native-to-web/web-to-native stop ordering. Track changes must invalidate stale media events and asynchronous page operations. A rejected `play()` promise, account/region/subscription/DRM gate, runtime absence or suspended page is a failure/limitation, not successful playback. Never expose extracted media URLs to native decoders. A hidden iframe, a mounted WebView, page load, lifecycle event or fake-backend test is insufficient evidence of an audio-only engine.

EQ and FFT remain native features unless the engine proves otherwise. Browser media may not expose either through the existing native mixer. Android background/lock-screen/Bluetooth/audio focus, Windows controls, signed-in access, seeking, audible playback and page lifecycle all need actual device validation. The existing `integration_test/youtube_music_webview_test.dart` observes only a visible full-site view with manual playback and explicitly cannot infer audible playback from lifecycle state; it does not validate the proposed audio-only bridge.

## Validation

`test/audio_only_routing_test.dart` uses no live YouTube access. It covers native initialization and recovery after both a database read failure and a downloads-directory obstruction, honest native-init failure, idle/active pause behavior, mixed web/local queue persistence, legacy IDs, completion/repeat, saved Spotify matching to web and local candidates, library/link search without yt-dlp, restricted inputs, download availability and stale/repeated public metadata. Pasted links have an empty artist until observed metadata supplies one.

Initial pre-change characterization plus existing routing/source tests passed 24 checks and reproduced the skipped-native-initialization state. Final validation:

```text
flutter test --no-pub test/audio_only_routing_test.dart test/web_music_routing_test.dart test/web_music_source_test.dart test/controller_test.dart test/queue_identity_test.dart test/jam_playback_bridge_test.dart test/jam_playback_isolation_test.dart test/android_music_audio_test.dart test/offline_settings_panel_test.dart
90 tests passed.

flutter test --no-pub test/audio_only_routing_test.dart test/web_music_source_test.dart test/web_music_routing_test.dart test/controller_test.dart test/dj_filters_test.dart test/recommendations_test.dart
93 tests passed after optional metadata callback integration.

C:/flutter/flutter/bin/dart.bat analyze lib/app_controller.dart lib/core/audio_backend.dart lib/core/source_backend.dart lib/sources/web_music_source.dart test/audio_only_routing_test.dart
No issues found.

git diff --check
Passed.
```

Full `flutter analyze --no-pub` reported one informational issue in root-owned `lib/audio/android_music_audio.dart`: add `@override` to `mediaActions`, which now inherits the common contract. No owned file has an analyzer issue; root's Android adapter change should resolve that annotation.

The first plain `flutter test` fetched the committed dependencies but stopped at Windows plugin symlink preflight (Developer Mode unavailable). `flutter test --no-pub` runs successfully after package resolution. This does not establish native package-build or hardware support. No production packages were added and `pubspec.lock` was not changed.

Checkpoint requested by coordinator for token renewal: base controller/source work is commit `5ef7877` on `kaz-py/research-aurora-audio-routing`; a following commit adds the metadata callback and this updated report. All owned changes are committed. Remaining work belongs to root/engine workers: merge commits, supply Android metadata adapter and routed backend, opt bootstrap into audio mode with honest retry, mount playback/metadata views, retain the existing full player and truthful capability/search/download UI, run complete integrated analysis/builds, and observe actual Windows/Android playback. No claim of successful live audio, live search, sign-in, background playback or hardware compatibility is made here.
