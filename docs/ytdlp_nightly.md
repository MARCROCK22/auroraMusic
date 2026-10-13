# yt-dlp nightly updates

Aurora packages the official nightly channel. Upstream recommends nightly for
regular users because site changes can break the monthly stable release;
`yt-dlp --update-to nightly` is the upstream command to switch channels.
Aurora manages installation itself to coordinate extraction and playback and
preserve the previous executable on failure. See the [official update
documentation](https://github.com/yt-dlp/yt-dlp#update).

## Reproducible package baseline

Both locks pin nightly `2026.10.10.233141`, generated from source commit
`897341241f2bfb2439fe0367f4c7c9ccd29a3828`.

| Target | Release asset | SHA-256 |
| --- | --- | --- |
| Android | `yt-dlp` | `f40b6a9e4c5786360953911cab5d2f87507626b8fb7bfee3f8f1c2e5cf341fae` |
| Windows x64 | `yt-dlp.exe` | `e7cafc44db8aa433da8dd78303b9157f2c1dd509c4cbfcd8418081b7e1d26a7a` |

These match the [official release
checksums](https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/2026.10.10.233141/SHA2-256SUMS).
Run `scripts/setup_android_ytdlp.ps1` or `scripts/setup_tools.ps1`; both verify
downloaded bytes against the committed hash before installation. Android also
validates the zipimport entry point and bundled EJS 0.8.0. Windows setup migrates
an existing stable lock to the committed nightly baseline. An explicit
`-YtDlpVersion latest` requests the current official nightly; release packaging
should retain the resulting exact version, source commit and checksum lock.
Nightly tags belong to `yt-dlp-nightly-builds`, so license downloads use the
source commit in the release body rather than a nonexistent tag in `yt-dlp`.

Retain `LICENSE` and `THIRD_PARTY_LICENSES.txt`. The Windows standalone
executable includes GPL components; its combined distribution is GPLv3+.
The zipimport executable includes MIT/ISC components. See the [upstream
licensing details](https://github.com/yt-dlp/yt-dlp#licensing).

## Windows runtime contract

`lib/sources/ytdlp_updater.dart` takes the installed executable, a persistent
state file and a synchronous `canUpdate` callback. `checkForUpdate()` returns
`updated`, `upToDate`, `deferred`, `throttled` or `failed`, plus a version or safe
error message. Every network check, including failures, consumes one persisted
24-hour allowance. A busy check consumes none. Concurrent calls for the same
executable share one future within the Dart isolate.

Await `recoverPendingInstallation()` at startup before permitting extraction.
It makes no network requests and bypasses the daily throttle. A durable pending
installation journal records the expected nightly hash/version/source commit
and previous executable hash before replacement. Recovery validates the active
file and version, commits a successful interrupted installation, or restores
the hash-verified backup. A failed recovery must block extraction until tools
are repaired. Normal update checks also run this recovery before throttling.

The caller must reject installation during playback, buffering, extraction,
downloads, shutdown or other work using the tools. It must wait for the current
update future before starting new extraction when `isInstalling` is true.
Network checks may run while the app is otherwise idle; the callback is checked
again immediately before setting the installation lock. Keep playback and
operation-start checks in the same isolate as this lock.

The updater reads only the official nightly API and exact release asset URLs,
requires a unique SHA-256 checksum, verifies downloaded bytes and Windows `MZ`
header, runs `--ignore-config --version`, and downloads notices from the exact
source commit. It stages beside the installed executable, copies the previous
executable, then renames the candidate over the destination on the same volume.
An installation or post-install validation failure restores the backup.
A copy of the previous file remains available until the journal clear or
successful installation commit is durable, including during recovery itself.
A Windows sharing violation leaves the existing file usable. If restoration
itself fails because another process locks the file, the backup is retained at
`yt-dlp.exe.aurora-previous`; the returned error identifies the recovery issue.

TLS verification stays enabled. Metadata, checksums and notices time out after
15 seconds; executable download after 3 minutes; version probes after 20
seconds. Responses are capped at 100 MiB and license notices at 1 MiB.
No cookies, tokens, custom repositories or shell commands participate in
updates. Protected installation directories can make automatic updates fail;
the old tool remains usable and a later check can retry.
Redirects are handled manually with a limit of five. HTTPS, the standard TLS
port and official GitHub hosts are checked before sending each request; an
untrusted destination is never contacted.

## Android integration

`AuroraYtDlpUpdater.kt` owns Android nightly installation. Aurora does not call
the library's built-in updater: it downloads without SHA-256 verification and
removes the current directory before copying the new file. Its recovery
installs the packaged default rather than the previous updated file. See [the library update
API](https://github.com/yausername/youtubedl-android/blob/master/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt)
and [updater
implementation](https://github.com/yausername/youtubedl-android/blob/master/library/src/main/java/com/yausername/youtubedl_android/YoutubeDLUpdater.kt).

Before the first native source operation, `MainActivity.initialize()` calls
`installBundle()` and then initializes the bundled Python/QuickJS and FFmpeg.
The updater verifies the APK resource against the bundled hash. An installed
file matching the persisted `installedHash`, with `installedVersion` at least
the bundled version, survives restarts. If those checks fail, initialization
can restore the hash-verified previous file or reinstall the packaged payload.
Only the interpreted `yt-dlp` payload changes at runtime; Python, QuickJS and
FFmpeg remain the native runtimes supplied in the APK.

The native `updateNightly` channel method uses the official nightly API and
requires exactly one `yt-dlp` and `SHA2-256SUMS` asset at the expected release
URLs. It validates the checksum, Python shebang and required zipimport/EJS
entries. Release metadata, checksums and notices are capped at 1 MiB; the
payload is capped at 32 MiB. Notices are downloaded from the release's exact
source commit before installation. HTTP uses normal TLS verification, manual
redirects to the official GitHub hosts, and 15-second connect/read timeouts.
Each response body also has a 90-second deadline.

Extraction holds the shared native source lock for reading. Installation takes
its write lock and rechecks `AuroraPlaybackService.playbackActive`; if extraction
or playback is active it defers replacement. The updater verifies the previous
file against its persisted hash, writes a synced backup, and commits the
previous hash/version and pending hash before replacing the target with
`Os.rename`. It runs a version probe through the bundled Python environment
before committing the new installed hash/version and source commit. Installation
failure attempts to restore the verified backup. The native state lives in
`aurora-ytdlp-nightly` preferences, and the interpreted files live under
`noBackupFilesDir/youtubedl-android/yt-dlp/`.

On both platforms, `YtDlpSource.initializeUpdates()` schedules a first check
after 20 seconds and subsequent opportunities every six hours. A persisted
24-hour allowance limits actual network checks, including failed checks. The
controller's idle check includes playing, buffering, busy work and Jam playback;
active source operations also defer checks. Status reports distinguish updates,
verified current versions, throttling, deferral and failure.

## HTTP failures and validation

A nightly update can repair extractor breakage but cannot promise to remove
YouTube access limits. `YouTubeRequestPolicy` permits at most two concurrent
source requests, spaces starts by at least one second, and queues at most eight
additional requests. Identical listing/resolution work shares an in-flight
future. Listing results have a five-minute cache; resolved audio retains the
extraction headers and is reused only with at least two minutes of cache life
remaining. These request limits are separate from the updater's daily allowance.

HTTP 429, verification/rate-limit responses and an unexplained HTTP 403 start a
1-minute cooldown. The cooldown timestamp is persisted across app restarts;
queued work rechecks it before starting. Aurora does not retry these denials,
switch clients/accounts/network routes, or recommend changing sessions to
bypass a restriction. Local music remains available during the cooldown.

A 403 alone is not evidence that a media URL expired. Refresh for a 403 requires
an elapsed `expire`/`expires` timestamp from the resolved URL; an internal cache
TTL is not expiration evidence. Other transient connection failures have a
separate bounded recovery path. Playback recovery permits at most two attempts,
waits two then four seconds, preserves the resume position, and cancels when
the queue occurrence or playback intent changes. A denial during recovery
stops further attempts. Eligible transient extraction failures permit one retry
after two seconds, still subject to request spacing and cooldown.

Do not expose signed media URLs or session values in diagnostics. The [official
FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#i-extracted-a-video-url-but-it-does-not-play-on-another-machine--in-my-web-browser)
explains why extracted URLs depend on their original headers and network
context, and identifies HTTP 429 as service-side rate limiting.

`flutter test --no-pub test/ytdlp_updater_test.dart` covers installation,
persisted cadence, hash mismatch, rollback, locked files, initial/delayed busy
guards, concurrency, release URL validation, failed network checks, crash
recovery, corrupt backups and redirect rejection/limits offline.
`dart analyze lib/sources/ytdlp_updater.dart test/ytdlp_updater_test.dart` checks
the new Dart code. Real playback, native background controls and signed Android
release distribution need separate device/package validation.
Android `NightlyIntegrityTest.kt` covers official checksum parsing, ambiguous
checksums, payload hash mismatches and missing Python/EJS entries. Those JVM
checks do not verify native filesystem crash recovery, preference commit
failures, version-probe cancellation or device playback during an update.
