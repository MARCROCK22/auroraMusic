# YouTube Music audio-only engine: feasibility and integration boundary

Reviewed 2026-10-13 against Aurora commit `139251b` and the primary documentation linked below.

## Decision

**No supported implementation was identified that satisfies all the requested constraints simultaneously:** native Aurora screens, cards, artists and queue; YouTube Music streaming through a WebView; no whole-site interface; no visible video; no hidden/disguised YouTube player; and no bypass of sign-in, access, DRM or paid features. Android and Windows can host web playback, but the missing component is a documented YouTube Music audio-only playback API usable by Aurora, not a Flutter WebView implementation.

This is a limitation of the documented integration routes reviewed, not proof that audio-only playback is technologically impossible or that no separately negotiated partner integration could exist. No `lib/audio_web/` backend, fake playback implementation, or experimental test was added. A fake test could validate commands invented by Aurora; it could not establish that YouTube supports those commands or authorizes this mode.

The corrected requirement does **not** mean Aurora should replace its interface with the official site, crop that site down to album art, or quietly use a hidden video iframe. The previous whole-site implementation is not acceptance of this corrected requirement.

## What YouTube actually documents

### YouTube Music's own audio mode

[YouTube Music Help: audio-only or video mode](https://support.google.com/youtubemusic/answer/6313574?hl=en) describes listening without loading video. Music audio mode requires YouTube Music Premium or YouTube Premium; podcasts have a separate exception, with content/region qualifications. Its instructions select **Song/Video** or **Audio/Video** inside the official app, and configure the app's data-saving settings. The article offers Android and iOS instructions, not an embeddable developer contract. Where only a music video exists, the official product can play that content in its own audio mode.

**Inference:** possession of a Premium subscription alone does not expose that setting as a third-party audio API. This article does not document an audio-mode URL parameter, a JavaScript control interface for `music.youtube.com`, an audio SDK, native queue synchronization, or a Windows WebView entitlement guarantee. Selecting songs with still artwork also does not establish audio-only transport.

### Public playback and metadata APIs

The [IFrame Player API](https://developers.google.com/youtube/iframe_api_reference) controls an embedded **video** player. It exposes cue/load, play/pause/stop, seek, volume, time/duration, and player events. The [documented parameters](https://developers.google.com/youtube/player_parameters) do not provide an audio-only switch: `controls=0` hides controls, and `playsinline=1` affects presentation; neither selects an audio stream. An audio-looking video can still be audiovisual playback.

The [YouTube Data API overview](https://developers.google.com/youtube/v3/getting-started) documents metadata/resources such as videos, playlists and search results. Those resources are not an audio playback endpoint. Native search/cards could use documented metadata subject to its requirements, but that does not solve audio playback or provide complete YouTube Music artist/catalog parity. No public Music audio-only backend was found in the reviewed official API references; unofficial website endpoints are not a supported substitute.

### Why an invisible iframe is excluded

[Developer Policies, III.D.7 and III.E.6–9](https://developers.google.com/youtube/terms/developer-policies) prohibit undocumented API use without permission, blocking/modifying player functionality, separating audio/video components, promoting those components separately, and background playback from a player absent from the user's viewed page/tab/screen. III.E.5 also prohibits interfering with YouTube-served advertisements. These requirements apply to the API-client route; they are not a claim that YouTube's own Premium app cannot provide audio mode.

A headless, offscreen, zero-size, transparent, clipped, or artwork-covered YouTube video player would not become an audio-only API. Intercepting media URLs and feeding a native decoder, deleting the video element, blocking video segments, spoofing a client, or forcing the website's private audio-mode state also has no supported basis under this task. None is implemented or recommended here.

The [Required Minimum Functionality](https://developers.google.com/youtube/terms/required-minimum-functionality) requires at least a 200×200 embedded player, adequate controls, and genuine app identification through `Referer` or the documented equivalent. These are requirements for a visible embedding route, not a way to unlock audio mode. A truthful Aurora app identifier must never be replaced with another app or the official site's identity.

## Android and Windows support actually present

[The pinned `flutter_inappwebview` 6.1.5 release](https://pub.dev/packages/flutter_inappwebview/versions/6.1.5) supports Android and Windows. Aurora's lockfile resolves Android `1.1.3`, Windows `0.6.0`, and platform interface `1.3.0+1`. The maintainer also documents [headless views](https://inappwebview.dev/docs/webview/headless-in-app-webview/) on both platforms. This technical capability does not authorize a hidden YouTube player.

| Platform | Verified host capability | What it does not establish |
| --- | --- | --- |
| Android | Published plugin source uses `android.webkit.WebView`; web settings include the media user-gesture policy. Native JavaScript evaluation/bridges support ordinary web applications. | Music Premium account access, a Music audio API, or reliable playback through screen lock/background execution. |
| Windows | Published plugin source uses Microsoft Edge WebView2; `WindowsInAppWebViewController` implements JavaScript evaluation/handlers and `WindowsHeadlessInAppWebView` exists. Aurora creates a persistent WebView environment after checking runtime availability. | Audio-only Music transport, Premium session transfer from Edge, native queue events from the Music website, or unrestricted embedding. |

Source inspection used the installed, versioned Pub archives, not assumptions about the plugin's current `main` branch: [Android 1.1.3 source archive](https://pub.dev/api/archives/flutter_inappwebview_android-1.1.3.tar.gz), [Windows 0.6.0 source archive](https://pub.dev/api/archives/flutter_inappwebview_windows-0.6.0.tar.gz). Relevant package files include Android `webview/in_app_webview/InAppWebView.java`, Windows `windows/in_app_webview/in_app_webview.cpp`, and Windows `lib/src/in_app_webview/in_app_webview_controller.dart` and `headless_in_app_webview.dart`.

YouTube explicitly documents Android embedding and its [WebView Media Integrity integration](https://developers.google.com/youtube/iframe_api_reference#android-webview-media-integrity-api-integration). That verifies an embedding application's identity/integrity; it is not an audio entitlement. Availability still depends on content, browser/runtime, service response and user interaction. IFrame errors include unavailable/private content, disabled embedding, and missing client identification; autoplay can be blocked. No successful live playback or universal unblock is claimed.

### Sessions, UA and authentication

The existing [native platform adapter](../lib/youtube_music/youtube_music_platform.dart) keeps the native UA and normal media/TLS defaults, disables plugin debug logs that could reveal signed traffic, and creates Windows storage at the application-support `youtube_music_webview` directory. [Microsoft's user-data-folder documentation](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder) explains that this folder contains cookies and site storage. Its session is independent of the user's external Edge/Chrome profile.

Android uses app WebView storage, independent of an external browser; it should not be described as a separate profile per widget. [Android's process-global configuration](https://developer.android.com/reference/androidx/webkit/ProcessGlobalConfig) sets a data directory before WebView initialization and explains distinct-process storage. Aurora currently does not configure a second Android WebView profile. Session separation from a browser does not require exporting its cookies into Aurora.

The adapter rejects embedded account navigation and tells users that the browser session is separate. Google's [native-app OAuth documentation](https://developers.google.com/identity/protocols/oauth2/native-app#disallowed_useragent) documents rejection of disallowed embedded user agents. Opening the supported external flow does not automatically authenticate Aurora's WebView. Do not copy cookies/tokens, change UA, impersonate a permitted client, or guarantee that the site will accept the embedded session.

The installed [ad-filter adapter](../lib/youtube_music/youtube_music_ad_blocker.dart) uses `adblocker_webview` 2.3.0's filter API and protects media/authentication origins; it is not an audio engine. Resource filtering must not be repurposed to remove video or change entitlements. A future official embedding design must ensure it does not interfere with YouTube-served ads; its current presence is not evidence of compliance or of audio-only support.

## Aurora contract: where integration is blocked

| Existing file/symbol | Current contract and consequence |
| --- | --- |
| [AudioBackend](../lib/core/audio_backend.dart), line 4 | Decoder-facing state/commands: `load(ResolvedAudio)`, play/pause/stop/seek/volume, duration/position/buffering/error and `completed`. Equalizer/visualization capabilities default to true. |
| [ResolvedAudio](../lib/core/models.dart), line 114 | A playable input plus ordinary headers/duration/completion validation, not an opaque website page or YouTube track ID. |
| [SourceBackend](../lib/core/source_backend.dart), line 20 | `resolve(Track)` returns that decoder input; download/cancel are separate methods. |
| [AppController](../lib/app_controller.dart), `openYouTubeMusic`/`_routeToYouTubeMusic` | Current remote YouTube selection navigates the official site; its queue/session belong to that site, not Aurora. `_playCurrent` otherwise resolves input and calls `audio.load` then `audio.play` (around lines 959–983). |
| [WebMusicSource](../lib/sources/web_music_source.dart), `resolve`/`_nativeUri` | Allows local/direct non-YouTube inputs and rejects YouTube decoder extraction. It exposes no audio-only Music engine. |
| [YouTubeMusicPlatform](../lib/youtube_music/youtube_music_platform.dart), line 13 | Navigation/browser-loading interface, with `buildView`, back/forward/reload/navigation. No track playback, time/ended/buffering bridge or native queue ownership. |
| [Bootstrap](../lib/main.dart), `_createController` | Instantiates the existing native audio decoder and `WebMusicSource(YtDlpSource(...))`; not a WebView audio backend. |

**Integration result:** there is no supported `YouTubeMusicAudioBackend` contract to consume. Do not return a watch-page URL as `ResolvedAudio`, forge `isPlaying`/duration/completion events, make elapsed-time timers stand in for website events, or restore streaming through `YtDlpSource.resolve`. The requested download-only yt-dlp boundary must be implemented explicitly by the integration owner; this research does not change it. Preserve existing library data, track metadata, playlists and queue rather than deleting unsupported items.

If a documented, authorized Music audio integration becomes available, it must accept a track identity without extracting credentials/media, report actual ready/buffering/playing/paused/ended/error events, cancel stale load requests, and fail honestly on unsupported accounts/content. A website-owning controller would require a deliberate contract separate from `ResolvedAudio`, with equalizer/PCM visualization disabled unless specifically supported. Adding that abstraction now would pretend the provider half exists.

## Minimal viable alternatives

| Alternative | Native Aurora experience | Constraint that changes |
| --- | --- | --- |
| Keep existing playback for local files, explicit downloads already on disk, and authorized direct audio sources | Keeps Aurora cards, artists, queue, transport controls and no visible video; existing backends suffice. | Does not supply live YouTube Music streaming. |
| Open an official Music song/playlist in the external app/browser, with its own supported audio-mode selection where available | Keeps Aurora's library/navigation, but playback and queue are owned by the official product; no promised queue synchronization. | Playback leaves Aurora. Music audio mode depends on entitlement and product availability. |
| Visible official YouTube embedded player surrounded by native Aurora UI | The documented controls/events can drive a native queue, subject to embedding/player requirements; no whole-site page is required. | Requires visible video. **Rejected by the current requirement; do not implement without a changed requirement.** |

There is no documented option in this review that preserves **all** constraints and supplies live YouTube Music audio streaming. Choosing a different audio provider or obtaining a documented partner contract could change that conclusion; adding another WebView package would not.

## Verification and remaining work

This is a documentation-only investigation: inspected Aurora contracts, pinned plugin source and official online references. No YouTube sign-in, cookie access, live media requests, DRM experiments, device/background/Bluetooth checks, or application data changes were performed. Dart tests, analysis and native builds were not run because no executable code changed; fake playback tests were deliberately omitted because they cannot verify the external limitation.

The coordinator can restore native UI/queue preservation and keep yt-dlp behind explicit download actions independently of this report. Live YouTube Music audio-only integration remains unavailable under the reviewed public contract and constraints; it must not be reported as shipped. Provider-specific hardware verification is still required for any subsequently chosen supported implementation.
