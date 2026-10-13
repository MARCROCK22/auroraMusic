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

The library exposes `YoutubeDL.UpdateChannel.NIGHTLY`, but its built-in updater
downloads without SHA-256 verification and removes the current directory before
copying the new file. Its recovery installs the packaged default rather than
the previous updated file. See [the library update
API](https://github.com/yausername/youtubedl-android/blob/master/library/src/main/java/com/yausername/youtubedl_android/YoutubeDL.kt)
and [updater
implementation](https://github.com/yausername/youtubedl-android/blob/master/library/src/main/java/com/yausername/youtubedl_android/YoutubeDLUpdater.kt).

Use the official nightly `yt-dlp` zipimport asset with the same metadata,
checksum, idle guard and daily-check policy. Stage beside the active file,
retain a backup and replace only while native extraction is serialized.
Startup integrity validation must accept a persisted, verified nightly hash;
checking only the packaged hash would undo every runtime update on restart.
Keep the packaged resource as fallback without changing Python, QuickJS or
FFmpeg at runtime. Nightly updates do not change the bundled native runtime.

## HTTP failures and validation

A nightly update can repair extractor breakage but cannot promise to remove
YouTube access limits. HTTP 429 indicates service-side rate limiting; repeated
automatic retries make it worse. HTTP 403 on a media URL can require a fresh
extraction and the original extraction headers, cookies and network context.
Use a bounded retry and optional user-imported session only; do not expose
signed media URLs or cookie values in diagnostics. See the [official
FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#i-extracted-a-video-url-but-it-does-not-play-on-another-machine--in-my-web-browser)
and [YouTube cookie
guidance](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies).

`flutter test --no-pub test/ytdlp_updater_test.dart` covers installation,
persisted cadence, hash mismatch, rollback, locked files, initial/delayed busy
guards, concurrency, release URL validation, failed network checks, crash
recovery, corrupt backups and redirect rejection/limits offline.
`dart analyze lib/sources/ytdlp_updater.dart test/ytdlp_updater_test.dart` checks
the new Dart code. Real playback, native background controls and signed Android
release distribution need separate device/package validation.
