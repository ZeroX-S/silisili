# Native Sailfish OS migration

## Baseline and scope

The migration starts from commit `099cfb763fd7cb04175b3a1fc12d0246ff3268a0` plus the complete uncommitted,
device-validated `1.0.0-7` working-tree state. The source tree is retained as a read-only baseline and the
legacy Borealis implementation remains in this copy for behaviour comparison.

The first native executable is built from `native/`. It is intentionally parallel-installable:

- stable package: `silisili-sailfish`, `/usr/bin/silisili`, `/usr/lib64/silisili/silisili.real`
- native development package: `silisili-native-devel`, `/usr/bin/silisili-native`
- stable configuration: `$XDG_CONFIG_HOME/silisili/silisili_config.json`
- native configuration: `$XDG_CONFIG_HOME/silisili-native/`

At first launch, the native app copies the stable configuration to `stable_config_snapshot.json` with owner-only
permissions. It never renames, deletes, or writes the stable file. `AccountService` parses the copied credentials
into a typed C++ boundary and supplies authenticated request headers and CSRF tokens without exposing cookies to QML.

The 0.7 application entry point also acquires a process-lifetime `QLockFile` before constructing the QML view. This
closes the race where package replacement or a second launcher could create two application processes and therefore
two VOD backends. It is distinct from playback-session sharing: the lock limits application processes, while
`PlaybackSession` coordinates one VOD backend inside the accepted process. The final 0.7 deliberate second-launch
gate retained one exact process, start time and backend; stale-lock crash recovery remains a separate hardening case.

## Architecture audit

The legacy target is a C++ monolith: CMake recursively compiles activities, views, API code and mpv integration,
then Borealis/GLFW owns windowing, navigation, input, orientation and rendering. Sailfish adaptations currently live
across Borealis, XML layouts, application activities and the packaging scripts. This makes a direct page-by-page
QML replacement inside the old executable unsafe.

The target architecture has four layers:

1. Silica presentation: `ApplicationWindow`, `Page`, `PageStack`, `SilicaListView`, menus, dialogs and Cover.
2. Qt models/controllers: stable QML-facing properties, roles, commands, loading/error state and lifecycle signals.
3. Domain adapters: account, feed, search, detail, comment, live and playback interfaces independent of Borealis.
4. Reused core: the existing Bilibili HTTP/result code and mpv/FFmpeg implementation, incrementally extracted behind
   adapters. The old activities remain compiled only by the legacy target until their feature parity is signed off.

`HomeFeedModel` defaults to the personalized recommendation endpoint and exposes popular as an explicit native
selection. The 0.7 Home page keeps the primary information architecture to one native four-item row: live,
recommended, popular and PGC. Recommended is selected on entry. Search, region, dynamic, messages and account live in
a `ContextMenu` opened by one “more” `BackgroundItem`, so secondary navigation does not permanently increase the
header height. The pull-down menu retains refresh and the compatibility overview. The model's QML role contract
remains the seam where a common `BilibiliClient`-backed adapter can replace the temporary per-model Qt Network
implementation.
Detail, comment and recommendation adapters are registered as QML types rather than global context singletons, so
each pushed detail `Page` owns isolated request and list state. This keeps native PageStack back navigation from
mutating the previous page when a related video is opened.

The VOD source adapter uses latest-wins request arbitration in 0.7. Every video, episode or quality selection advances
a serial and aborts the previous `QNetworkReply`; a late queued completion is ignored unless its serial is still
current. This prevents an older playurl from being published after `PlaybackSession` has already adopted a newer
media identity. Normal VOD and PGC entry are present in final device evidence; rapid-switch and delayed-network stress
are useful additional hardening beyond the checksum-closed release gate.

Authenticated timelines remain application-lifetime models while their presentation is fully native. The dynamic
adapter normalizes video, image/opus, repost, live and PGC payload variants into one stable role contract and keeps
the server offset for incremental insertion. The inbox adapter similarly normalizes reply, mention and like feeds,
retains each category's cursor semantics, and exposes complete message text to a pushed Silica detail page. Neither
read path exposes cookies to QML or performs account mutations.

Playback uses a separate application-lifetime seam:

- one application-level `MpvVideoItem` fronts the shared VOD libmpv/OpenGL backend and retains playback state across
  inline, full-page and compact host changes;
- `PlaybackResolver` owns authenticated VOD source and quality resolution;
- `PlaybackSession` owns media identity, state preservation, lifecycle policy and surface claiming;
- inline detail, full-page player and compact player claim or release the same video item. Media-state notification
  (`changed`) is separate from host-only notification (`surfaceChanged`), so a surface claim no longer synchronously
  re-evaluates the `wantsPlaybackSurface` binding that initiated it. Release is delayed by 220 ms, allowing the
  incoming page or a returning owner behind a native Dialog to claim the item without a fallback reparent;
- quality and danmaku Dialogs carry a `playbackSurfaceOwner` token and inherit the owning player's resolved
  `allowedOrientations`, preserving the player host and its portrait/landscape policy while the Dialog is open.
  Final 0.7 device-verified this behavior for the quality Dialog at 2160×1080 landscape; the danmaku Dialog remains
  code-audited under the same implementation and was not separately captured;
- the system Cover is intentionally a static native card. It reads title, cover art, progress, duration and quality
  from the shared VOD session and sends play/pause/stop actions, but never reparents the live framebuffer into the
  Cover window;
- ordinary and PGC detail pages keep that inline surface fixed below the native `PageHeader`; metadata, episodes,
  comments and recommendations scroll in a clipped `SilicaFlickable` beneath it;
- the fixed inline player leaves a thin passive progress line visible after controls fade. When controls are shown,
  a native `Slider` supplies precise seek and time feedback. `PlayerGestureArea` maps horizontal drag to seek, the
  left vertical area to brightness and the right vertical area to volume while preserving the PageStack back corridor;
- full-page VOD and live players derive the default orientation set from mpv video geometry, retain follow-device and
  explicit portrait/landscape overrides, and hide controls after about 3.2 seconds of uninterrupted playback;
- `DanmakuModel` parses Bilibili protobuf segments (with a legacy XML fallback), while `DanmakuOverlay` owns the
  Silica/Qt Quick presentation and follows the shared playback clock.

Detail pages deliberately render only three main comments as a preview. They show the complete server total and reply
counts and provide pull-down/button entries into a dedicated `SilicaListView` comments page. That page retains cursor
pagination, pinned replies, reply threads and the native posting Dialog. Limiting the embedded preview is a layout and
startup policy, not a three-comment API limit.

The live player currently uses the same `MpvVideoItem` type and gesture component but a separate per-page instance.
This isolates live reconnect work from the verified VOD session; convergence can happen after live danmaku and
background policy are defined.

## Build and verification

The minimum build target remains `SailfishOS-5.0.0.62-aarch64`:

```sh
PROJECT_ROOT=$HOME/silisili-native \
  bash vm-deploy/scripts/build-silisili-native-rpm.sh
```

The package may be installed alongside `silisili-sailfish-1.0.0-7`. Compatibility with Sailfish OS 5.0 means only
SDK/ABI compatibility until a real Sailfish OS 5.0 device run is recorded. The regression device remains Pixel 3a XL
on Sailfish OS 5.1.0.11.

Final 0.7 package verification on the Pixel 3a XL:

- clean full-build NEVRA `silisili-native-devel-1.1.0-0.7.aarch64`, SHA-256
  `a97c1b3cdcdf5d28fb5766d4e0e60c8cccdb006724713a0abb36c2bc3bc1573a`, build time `1785699348`
  (`2026-08-03 03:35:48 +0800`); the exact phone payload hash matched and `rpm -V` was clean;
- stable `silisili-sailfish-1.0.0-7.aarch64` remained installed and stable configuration SHA-256 stayed
  `06cfd2fed5f36d558b98e1de43b598cc59f64b0098bf125e726dee97313bdb97`;
- the second-launch single-instance gate retained the same exact process, process start time and VOD backend;
- inline VOD playback showed passive progress/native controls and passed seek, brightness and volume;
- a real 12-item PGC feed and episode playback passed seek, brightness and volume;
- real 1920×1080 live playback passed DVR seek, brightness and volume;
- a 16:9 VOD selected 2160×1080 landscape, hid controls while playing and returned through the PageStack corridor
  to portrait detail; its quality Dialog remained 2160×1080 landscape and displayed 720P/360P;
- three foreground/Cover cycles retained the same PID, start time, backend and load count;
- the runtime error scan was clean; after inline VOD was paused, `mcetool` immediately reported display on,
  never-blank disabled and blank-inhibit disabled, then an independent check 40 seconds later reported display off
  with both policies still disabled. Final 0.7 paused-playback automatic blanking therefore passed.

Quick QML/player rebuilds remain iteration aids; the checksum above belongs to the clean full build. Compatibility
with Sailfish OS 5.0 remains an SDK/ABI claim only, not a physical-device claim.

## Milestone 1 verification record

Verified on 2026-07-31 on Pixel 3a XL running Sailfish OS 5.1.0.11:

- built against the Sailfish OS 5.0.0.62 AArch64 target; resulting ELF requires at most `GLIBC_2.17`,
  `GLIBCXX_3.4` and `CXXABI_1.3`;
- installed beside `silisili-sailfish-1.0.0-7.aarch64`; `rpm -V silisili-native-devel` passed and both
  executable paths remained present;
- Lipstick reported the native executable PID as the topmost window process;
- loaded the real popular feed (`HTTP 200`, Bilibili `code: 0`) and rendered covers, titles, owners and counts;
- opened a video placeholder page, returned with the native PageStack swipe gesture, and minimized the app with
  the Sailfish edge gesture to reveal its system Cover;
- stable configuration SHA-256 remained
  `06cfd2fed5f36d558b98e1de43b598cc59f64b0098bf125e726dee97313bdb97` before and after launch; the native
  snapshot was created mode `0600` in its separate namespace.

This is a 5.0 SDK/ABI compatibility claim only. No Sailfish OS 5.0 physical-device claim is made.

## Native content and playback migration record

Verified on 2026-07-31 on the same Sailfish OS 5.1.0.11 device:

- native Maliit search returns real video results and opens real detail metadata;
- native region ranking, authenticated mixed dynamic feed, categorized reply/mention/like inbox and restored
  account page render real API data;
- dynamic offset pagination appended 26 to 46 cards, while reply-message cursor pagination appended 20 to 32 and
  native message detail pages retained the full source text;
- detail pages render real comments and recommendations; opening a related item pushes an independently backed
  detail page, and the inset horizontal return gesture restores the original page and its scroll position;
- comment pagination uses `/x/v2/reply/main`; the dedicated all-comments page appended three cursor pages from 21
  to 60 visible main comments out of 9549 total entries without replacing earlier pages, and root items open complete
  `/x/v2/reply/reply` threads;
- one VOD mpv instance moves between inline detail, full-page playback, the application compact player and Cover;
- timed danmaku loaded from the protobuf segment endpoint and rendered over inline playback; a longer video fetched
  segment two as playback crossed the six-minute boundary;
- full-page seek, brightness and volume gestures ran on device while the left 28 percent remained available to the
  native PageStack return gesture;
- the live feed, a real live stream and its native quality Dialog ran on device;
- the real PGC feed, season detail, complete episode list, PGC playurl resolver, fixed inline playback, common
  full-page player and timed danmaku ran on device, while the common comments page kept playback in the compact surface;
- QR generation/polling uses a softly loaded Sailfish 5.1 system QR renderer; no renderer is redistributed, and a
  fallback page remains available when that plugin is absent;
- a gesture beginning at the physical outer edge remains a Sailfish system minimize gesture and reveals the Cover;
- the stable package stays installed and its configuration SHA-256 remains unchanged.

Verified on 2026-08-02, development package 1.1.0-0.6 added lifecycle-aware Cover playback. The final full-build RPM
has SHA-256 `e6492f5218f132e1d970ef82582ce84f1c51b34b2e3e18163aa0dd9aba937adc`. While minimized, a real VOD advanced
from 49 to 117 seconds; Cover pause held 250 seconds across two captures and resume advanced to 270 seconds. Active
foreground playback kept the display on after 45 seconds, while pause/end allowed it to turn off after 40–45 seconds;
the system-wide never-blank and blank-inhibit switches remained disabled.

## 0.7 final migration record

The clean full-build 0.7 package completed checksum, install and runtime closure on 2026-08-03 on the same Pixel 3a XL
with Sailfish OS 5.1.0.11. Earlier iterative screenshots remain useful design-history evidence; the captures named
`final-0.7` below came from the checksum-closed package:

- the Home page opened on real recommendation content with the compact live/recommended/popular/PGC row, and the
  secondary ContextMenu opened search and region without turning into a persistent Android/iOS-style navigation bar;
- ordinary detail playback remained fixed above independently scrolling content; final captures show
  [passive progress](screenshots/5x-test/native-inline-passive-final-0.7.png) and the
  [native Slider/control layer](screenshots/5x-test/native-inline-controls-final-0.7.png). The three-comment preview,
  complete-comments entry and dedicated comments page retain their 0.7 device evidence;
- the common full-page player selected 2160×1080 landscape for a 16:9 VOD, continued playing with controls hidden,
  and returned through the reserved PageStack corridor to portrait detail after media-state and `surfaceChanged`
  notifications were separated: [playing](screenshots/5x-test/native-fullscreen-playing-controls-hidden-final-0.7.png),
  [returned detail](screenshots/5x-test/native-fullscreen-page-return-final-0.7.png);
- the full player's native quality Dialog remained 2160×1080 landscape and exposed both 720P and 360P:
  [landscape quality Dialog](screenshots/5x-test/native-landscape-quality-final-0.7.png). The danmaku-settings Dialog
  retains code-audited orientation inheritance but was not separately screenshot-verified;
- the `native-fullscreen-edge-return-0.7.png` capture shows the system launcher after a physical outer-edge gesture.
  It is evidence for Sailfish system minimize behavior, not for PageStack back navigation;
- the static Cover continued to show art, title, progress and quality with native pause/stop actions; three round
  trips retained the same process/backend/load, while earlier 0.6 captures retain the timed advance/pause proof;
- the application `QLockFile` passed deliberate double launch, and the final artifact includes latest-wins playurl
  arbitration;
- final inline VOD, a [12-item real PGC feed](screenshots/5x-test/native-pgc-feed-final-0.7.png) with
  [real PGC playback](screenshots/5x-test/native-pgc-inline-passive-final-0.7.png), and a
  [real live feed](screenshots/5x-test/native-live-feed-final-0.7.png) with
  [1920×1080 playback](screenshots/5x-test/native-live-player-final-0.7.png) each passed their applicable
  seek/brightness/volume paths; live used DVR seek;
- runtime error scan was clean. Immediately after pausing inline VOD, `mcetool` reported `Display state: on`,
  `Display never blank: disabled` and `Blank inhibit: disabled`; an independent check 40 seconds later reported
  `Display state: off` while both policies remained disabled. Final 0.7 paused-playback automatic blanking passed;
  the 0.6 active-foreground and end-of-file timing remains complementary power evidence.

A real QR account switch, an accepted logout, live danmaku/reconnect and the remaining message/dynamic variants are
still migration work. The legacy implementation remains in the tree as the functional comparison target until each
acceptance gate is device-verified. See `NATIVE_DEVICE_VALIDATION.md` for the current package and screenshot record.
