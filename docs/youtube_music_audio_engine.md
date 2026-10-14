# Official Music WebView engine for Aurora's native audio interface

Updated 2026-10-13 for the latest requirement: preserve Aurora's native library,
artists, playlists, queue and player; stream through the official Music website
without visible video; keep yt-dlp for explicit downloads only.

## Implemented scope

[WebMusicAudio](../lib/audio_web/web_music_audio.dart) extends Aurora's
[AudioBackend](../lib/core/audio_backend.dart). It hosts `music.youtube.com` with
the installed `flutter_inappwebview` 6.1.5 plugin. JavaScript controls the page's
ordinary `HTMLMediaElement`: `play()`, `pause()`, `currentTime` and `volume`. Actual
media state, duration/progress, errors, public MediaSession/DOM metadata and the
`ended` event supply Aurora's state. No elapsed timer fabricates playback or
completion. Polling samples observed state every 500 ms; an event listener retains
the final snapshot if the website advances before the next poll.

The page remains mounted behind Aurora's widgets in a covered 1 × 1 Flutter host
with pointer, focus and semantics excluded. CSS hides video presentation without
removing its media element. Optional website access exposes consent, ordinary site
controls and errors, with video still hidden. Aurora remains the primary player.

**Hidden video presentation does not establish audio-only network transport.** The
website can download or decode audiovisual streams even when no video is displayed.
This prototype neither selects media formats nor intercepts media URLs/segments.
Do not claim reduced video bandwidth without measuring it. The official product's
audio mode and account entitlements remain website-owned.

This replaces the earlier feasibility report, whose whole-site/visible-player
constraints no longer match the request. Absence of a public Music API or IFrame
developer conditions was not used as proof that ordinary page media cannot be
bridged. This is an experimental website-DOM integration with no claim of a stable
provider contract; runtime observations determine its actual limitations.

## API for the integration owner

```dart
final web = WebMusicAudio();
await web.initialize();
// Mount once after initialize, in the same persistent shell slot.
final host = web.buildEngineView(showWebsite: false);
await web.load(const ResolvedAudio(
  input: 'https://music.youtube.com/watch?v=6geljA2OZSY',
));
await web.play(); // Triggered by a native Aurora user action.
```

| Contract | Behavior |
| --- | --- |
| `initialize()` | Android WebView or Windows WebView2; unsupported platforms fail explicitly. |
| `buildEngineView(showWebsite: false)` | Persistent hidden engine; toggle visibility in place, never move between tabs or mount twice. |
| `load(ResolvedAudio, start: ...)` | Exact HTTPS Music `/watch?v=` URL and 11-character ID only; no extra parameters, fragments, credentials, custom ports or headers. |
| `play/pause/seek/setVolume/stop` | Ordinary media commands; seek refused for detected ads or unrecognized player DOM. Stop pauses and unloads the watch page. |
| `isPlaying/isBuffering/position/duration/completed` | Observed media state, one completion per selected track; advertisements do not complete the queue entry. |
| `currentTrackMetadata/title/artist/artworkUrl` | Observed metadata, never fake provider songs; artwork accepts HTTPS image hosts only. |
| `needsWebsiteAccess/lastError` | Actionable consent, blocked play, timeout, navigation, renderer or media failures. |
| `adPlaying/adBlocker` | Best-effort DOM ad indication and existing protected-domain filter adapter; no in-stream advertisement-removal guarantee. |
| `supportsEqualizer/supportsVisualization` | Both false; EQ no-op and zero spectrum. No PCM is available to Aurora. |
| `refresh()` | Explicit sample and deterministic fake-bridge seam. |

The integration owner routes official Music watch inputs here, local/direct audio
to the existing native backend, and advances Aurora's actual queue on `completed`.
Controller, source, bootstrap and shell changes are outside this engine's ownership.
Source resolution must never fall back to yt-dlp streaming on a web failure.

Commands are serialized. Load generations reject stale results and cancel outdated
play/stop requests. Play waits at most 45 seconds by default. Pause while initial
volume/seek is pending cancels remaining play intent. Missing media, site changes
and failures stay explicit. Open shadow roots are searched; cross-origin iframes
or closed shadow roots would require another integration if the site adopts them.

## Browser/session boundary

[The HTML media standard](https://html.spec.whatwg.org/multipage/media.html#media-elements)
defines the ordinary media controls/state used here.
[The plugin's JavaScript documentation](https://inappwebview.dev/docs/webview/javascript/communication/)
describes script evaluation; the plugin serializes command arguments rather than
interpolating track IDs or values into script text.

Native UA, TLS verification and normal component cookies remain intact. Native
Aurora play actions use `mediaPlaybackRequiresUserGesture: false` so that a
WebView-only tap is not also required; this does not grant login, Premium or DRM
access. `NotAllowedError` is distinguished from other failures. Failed/timed-out
play is paused and surfaced for recovery.

Windows checks runtime availability and reuses the existing application-support
`youtube_music_webview` profile.
[Microsoft documents this folder](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder)
as storage for component cookies/site data; it does not transfer external-browser
login. Android uses normal app WebView storage. Consent HTTPS origins may load;
embedded Google account navigation is rejected by the existing navigation policy,
with an explanation that browser sessions are independent.

No cookie/token export, UA spoofing, login/Premium/DRM bypass, private player API,
media URL extraction, native YouTube ExoPlayer, automatic download, ad skip or
forced private audio-mode setting is implemented. Existing generic filters protect
media/authentication origins and are not repurposed to block video segments.
Advertisement DOM detection is best effort, not a provider guarantee.

## Verification and reproducible device probe

At this checkpoint ten unit/widget tests pass using the public
[WebMusicBridge](../lib/audio_web/web_music_bridge.dart) fake seam. Coverage includes
input validation, commands/metadata, bounded missing media, failure/recovery, ad
completion isolation, stale responses, artwork validation, stop cancellation,
pause-during-play cancellation and persistent hidden/visible mounting. Fake state
validates Aurora behavior, not successful website playback or audible output.

```powershell
flutter test --no-pub test/audio_only_engine_test.dart
flutter analyze --no-pub lib/audio_web test/audio_only_engine_test.dart
```

Prior observations preserved in the root `RETOMAR_AURORA.md` used the older
whole-page Android x86_64 API 36 emulator build with WebView 134.0.6998.135. The
official song `6geljA2OZSY` exposed a real VIDEO element, title "Que Se Mueran",
artist "Romeo Santos", duration 251 seconds, readyState 4, paused true and
currentTime 0. A bridge play attempt with the prior default gesture configuration
returned `playBlocked`, mediaError 0. This measures element access and gesture
blocking; it does not establish successful playback in the new engine.

The latest gesture setting must be tested after rebuilding the integrated app.
The coordinator owns all device mutations/builds; this worker did not reinstall,
navigate media, change debugger forwarding or run another app. On the coordinator's
existing debug Music target, the sanitized probe is:

```powershell
python test/audio_only_engine_cdp_probe.py --port 9223
python test/audio_only_engine_cdp_probe.py --port 9223 --run-bridge --action snapshot
python test/audio_only_engine_cdp_probe.py --port 9223 --run-bridge --action play
python test/audio_only_engine_cdp_probe.py --port 9223 --run-bridge --action pause
python test/audio_only_engine_cdp_probe.py --port 9223 --run-bridge --action seek --value 30
python test/audio_only_engine_cdp_probe.py --port 9223 --run-bridge --action volume --value 0.5
```

Requires a loopback ADB/CDP forward, existing Python `websocket-client`, and exactly
one official Music target. Default mode is read-only; `--run-bridge` explicitly
permits shipped CSS/listener code and the chosen ordinary command. Avoid play/seek
on another person's active queue. Output excludes media URLs, credentials and raw
evaluation exceptions.

After integration verify increasing currentTime, pause/resume, seek and transitions
through actual Aurora UI controls; CDP play alone does not prove Flutter wiring.
Observe foreground/background/screen-off, local↔web switching and search while
playing. A headless `-no-audio` emulator cannot establish audible output. Windows
runtime, physical-device sound, Bluetooth, background service/session controls,
provider accounts/regions, completed songs and audio-only network bytes remain
unverified at this worker checkpoint; do not report them as shipped or universal.
