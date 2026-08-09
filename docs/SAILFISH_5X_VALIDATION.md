# Sailfish OS 5.x validation

Validation completed on 2026-07-31 for package
`silisili-sailfish-1.0.0-7.aarch64.rpm`.

## Release identity

- RPM SHA-256:
  `db88e1f206c4ee519219df76b1a5be0125a5c2893709b90fb2b34227765e1ed5`
- Source patch SHA-256:
  `44ee2f7321761806cdd66c1449cbb3ea38bc64761df1f50be4d8c8ca35c9420e`
- Build target: `SailfishOS-5.0.0.62-aarch64`
- Build tooling: `SailfishOS-5.0.0.62-i486`
- Package architecture: AArch64

## Sailfish OS 5.0 compatibility

The package, application and private runtime were built against the Sailfish
OS 5.0.0.62 SDK. The release gates reject payloads above these ceilings:

```text
GLIBC_2.30
GLIBCXX_3.4.28
CXXABI_1.3.12
```

The final payload uses no symbols newer than `GLIBC_2.30`, `GLIBCXX_3.4.26`,
or `CXXABI_1.3.11`. This confirms Sailfish OS 5.0 SDK and ABI compatibility;
no Sailfish OS 5.0 physical-device test is claimed.

## Sailfish OS 5.1 device regression

- Google Pixel 3a XL (`bonito`)
- Sailfish OS 5.1.0.11 (Pispala)
- Installed package `silisili-sailfish-1.0.0-7`
- Package integrity checked with `rpm -V`

The live process used Sailfish's system `/usr/lib64/libstdc++.so.6.0.32` and
loaded private `libavcodec`, `libavformat`, `libmpv`, `libcurl`, and `libssl`
from `/usr/lib64/silisili`.

Final startup diagnostics on the device were:

```text
Sailfish mobile typography: native-client hierarchy; text factor 0.800; touch targets 48-56; visible icons 24-28
Sailfish adaptive display: mode 1080x2160 physical 69x137mm rawDpi 397.6 baseline 427x240 source physical
Sailfish mobile window 1080x2160, content size: 427x854 windowScale: 2.529274 renderRotation: 0
```

### Native-client proportions and popup audit

The application uses a 427x854 logical portrait canvas on the 1080x2160
compositor surface (`windowScale=2.529274`). Mobile-web measurements remain a
content-density cross-check, but no longer determine the whole layout. The
phone UI instead separates native-client roles: body text is about 16pt,
supporting text 12-14pt, bottom navigation about 12pt, visible icons 24-28pt,
and touch targets 48-56pt. Video subtitles and user-configurable danmaku remain
content settings. Explicit dense feeds retain two portrait columns; fallback
grids use one portrait column and up to three landscape columns.

The 160-unit settings sidebar leaves 267 logical units for content. Page,
dialog and dropdown padding is 16-20 units; dropdown rows are 56 units high.
The player uses a 56-unit top overlay, 72-unit bottom overlay, 48-unit seek
target and 24-unit seek thumb. The title is a single-line regular-weight label
at about 15pt after the mobile text factor; the viewer count is about 10.4pt.
The title reserves 58 units for Back and 112 units for Cast/Settings, so it
truncates before the controls instead of drawing below them.

At startup the Wayland monitor mode and physical millimetres are validated.
Panels in the tested 62-78 mm phone class keep the exact 427 baseline. Smaller
or larger credible panels receive a bounded 400-640 logical-short-edge
correction; the 96-DPI GLFW placeholder and implausible data use the 427
resolution fallback. This keeps aspect-ratio reflow independent from control
physical sizing and avoids trusting bad EDID/output metadata.

| Component | Logical size or bound | Result |
| --- | --- | --- |
| Main header actions | 52x52; 24 icon | Suitable |
| Player primary play/pause | 56x56; 28 icon | Suitable |
| Player OSD secondary actions | 48-52 high; 24 icon | Suitable |
| Close button | 48x48; about 27 icon | Suitable |
| Seek thumb / target | 24 / 48 | Suitable |
| Dropdown rows | 56 high | Suitable |
| Settings sidebar | 160 wide; 56 rows | Suitable |
| Dialog maximum | 395x822 with 16-unit margin | On-screen |
| Dropdown maximum height | 73% of content height | On-screen |

Visual evidence:

- [Home/header/navigation](screenshots/5x-test/90-home-1.0.0-7-native-proportions.png)
- [Settings components](screenshots/5x-test/91-settings-1.0.0-7-native-proportions.png)
- [Bounded settings dropdown](screenshots/5x-test/92-settings-popup-1.0.0-7-native-proportions.png)
- [Player OSD buttons and typography](screenshots/5x-test/93-player-osd-1.0.0-7-native-proportions.png)
- [Bounded quality dropdown](screenshots/5x-test/94-player-quality-1.0.0-7-native-proportions.png)
- [Bounded live error dialog](screenshots/5x-test/65-live-player-1.0.0-4-1.5x.png)

All captures are 1080x2160. No opened component crossed a screen edge.

### Live Back conflict and inset-edge navigation

The application page gesture may start only within the first 36 logical units
at the left. The compositor reserves the outermost physical edge for Sailfish
task navigation; the verified application gesture therefore started just
inside it at physical x=80 (logical x=32). A middle-of-page horizontal live
gesture did not navigate. The inset-edge pull committed at 344 logical units,
then invoked exactly one `LiveActivity: close requested` and returned to the
live list. The OSD Back button used the same single close path.

- [Middle live swipe remains in the player](screenshots/5x-test/66-live-nonedge-swipe-stays.png)
- [Inset-edge Back returns to the live list](screenshots/5x-test/69-live-inset-edge-return.png)
- [OSD Back returns to the live list](screenshots/5x-test/70-live-button-returned.png)

A separate system-edge task-switch test minimized the application. Selecting
its task card restored the full 1080x2160 surface; it did not remain shrunk in
the top-left.

### Quality switch state

Normal-video and live quality changes snapshot the current playing or paused
state and apply it once when the replacement media file loads. Device logs
confirmed both cases:

```text
MPV quality switch: preserve playing state for next file
MPV quality switch: restored playing state
MPV quality switch: preserve paused state for next file
MPV quality switch: restored paused state
```

The final installed candidate was retested while playing (720P to 480P) and
while paused (720P to 480P). Both states were restored after
`MPV_EVENT_FILE_LOADED`.

### Consecutive fullscreen cycles

Both cycles used the center of the enlarged fullscreen touch target.

| Cycle | Enter evidence | Exit evidence | Runtime geometry |
| --- | --- | --- | --- |
| 1 | [Landscape](screenshots/5x-test/95-fullscreen-round1-enter-1.0.0-7.png) | [Portrait full window](screenshots/5x-test/96-fullscreen-round1-exit-1.0.0-7.png) | enter 1080x2160 physical / 854x427 logical; exit 1080x2160 physical / 427x854 logical |
| 2 | [Landscape](screenshots/5x-test/97-fullscreen-round2-enter-1.0.0-7.png) | [Portrait full window](screenshots/5x-test/98-fullscreen-round2-exit-1.0.0-7.png) | enter 1080x2160 physical / 854x427 logical; exit 1080x2160 physical / 427x854 logical |

The application PID remained stable across both cycles. The window stayed on
the 1080x2160 physical compositor surface and did not shrink into the top-left.
Final application and journal checks contained no SIGABRT, segmentation fault,
core dump, unresponsive-window report, GPU fault, or OOM event.
