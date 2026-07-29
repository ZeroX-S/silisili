# Sailfish OS 5.x validation

Validation completed on 2026-07-30 for package
`silisili-sailfish-1.0.0-3.aarch64.rpm`.

## Release identity

- RPM SHA-256:
  `532a16db5bc1e92fcc20e11ed562e954743a9f1a3c5f3a5d22b9f8c5d2447d9e`
- Source patch SHA-256:
  `92c0e665a77176ed5c386f4a9f2ec5020535fac92d124cc020bba8c6bcc84974`
- Build target: `SailfishOS-5.0.0.62-aarch64`
- Build tooling: `SailfishOS-5.0.0.62-i486`
- Package architecture: AArch64

## Sailfish OS 5.0 compatibility

The package, application and private runtime were built against the Sailfish
OS 5.0.0.62 SDK. The release gates reject any payload above these ceilings:

```text
GLIBC_2.30
GLIBCXX_3.4.28
CXXABI_1.3.12
```

The final payload uses no symbols newer than `GLIBC_2.30`, `GLIBCXX_3.4.26`,
or `CXXABI_1.3.11`. This is an SDK and ABI compatibility result; no Sailfish
OS 5.0 physical-device test is claimed.

## Sailfish OS 5.1 device regression

Device and package:

- Google Pixel 3a XL (`bonito`)
- Sailfish OS 5.1.0.11 (Pispala)
- Installed package `silisili-sailfish-1.0.0-3`
- Package integrity checked with `rpm -V`

The live process used Sailfish's system
`/usr/lib64/libstdc++.so.6.0.32` and loaded private `libavcodec`,
`libavformat`, `libmpv`, `libcurl`, and `libssl` from
`/usr/lib64/silisili`.

Desktop window-fullscreen controls were absent from both settings surfaces:

- [Application settings](screenshots/5x-test/23-interface-settings-no-window-fullscreen.png)
- [Player settings](screenshots/5x-test/26-player-settings-no-window-fullscreen.png)

### Phone component and popup audit

The phone layout uses a 640x1280 logical canvas on the 1080x2160 compositor
surface. Explicit focusable controls have no numeric width or height below 44
logical units. Key touch metrics are:

| Component | Logical size | Result |
| --- | --- | --- |
| Main header actions | 56x56 | Suitable |
| Player primary play/pause | 60x60 | Suitable |
| Player OSD secondary actions | 52-66 wide, 52 high | Suitable |
| Close button | 50x50 | Suitable |
| Dropdown rows | 64 high | Suitable |
| Dialog action rows | 72 high | Suitable |
| Dialog maximum | 608x1248 with 16-unit margin | On-screen |
| Dropdown maximum height | 73% of content height | On-screen |

Visual evidence:

- [Home/header/navigation](screenshots/5x-test/38-ui-home-1.0.0-3.png)
- [Player OSD buttons](screenshots/5x-test/39-player-osd-buttons-1.0.0-3.png)
- [Bounded quality dropdown](screenshots/5x-test/40-quality-dropdown-bounded-1.0.0-3.png)
- [Bounded share dialog](screenshots/5x-test/41-share-dialog-bounded-1.0.0-3.png)
- [Settings rows and controls](screenshots/5x-test/54-settings-component-sizes-1.0.0-3.png)

The runtime logged `Sailfish dialog bounds: 608x1248 within 640x1280`.
All captured files are 1080x2160, and no opened control crossed a screen edge.

### Sailfish page-stack pull Back

Back is a whole-page left-to-right pull rather than an edge-only gesture. A
short 89-unit logical pull was cancelled below the 179-unit threshold; a
415-unit pull committed and returned the player page to Home. A second commit
started at logical x=296, demonstrating that the gesture can begin near the
middle of the settings page:

- [Short pull remains on the player](screenshots/5x-test/43-page-back-short-swipe-cancelled.png)
- [Video-surface horizontal pull remains on the player](screenshots/5x-test/44-video-swipe-remains-player.png)
- [Committed page Back returns Home](screenshots/5x-test/45-page-back-committed-home.png)
- [Middle-of-page settings pull returns Home](screenshots/5x-test/55-whole-page-back-from-center.png)

The player only accepts page Back below its video surface, while embedded
fullscreen and live-player pages keep their dedicated media gestures. No page
Back marker was emitted for the horizontal video-surface test.

### Consecutive fullscreen cycles

Both cycles used the center of the enlarged fullscreen touch target at
physical coordinate `(1030, 535)`.

| Cycle | Enter evidence | Exit evidence | Runtime geometry |
| --- | --- | --- | --- |
| 1 | [Landscape](screenshots/5x-test/50-v3-long-fullscreen-cycle-1-enter.png) | [Portrait full window](screenshots/5x-test/51-v3-long-fullscreen-cycle-1-exit.png) | enter `1080x2160` physical / `1280x640` logical; exit `1080x2160` physical / `640x1280` logical |
| 2 | [Landscape](screenshots/5x-test/52-v3-long-fullscreen-cycle-2-enter.png) | [Portrait full window](screenshots/5x-test/53-v3-long-fullscreen-cycle-2-exit.png) | enter `1080x2160` physical / `1280x640` logical; exit `1080x2160` physical / `640x1280` logical |

The application PID remained stable across both cycles. The window never
changed from the 1080x2160 physical compositor surface and did not shrink into
the top-left. Final application and journal checks contained no SIGABRT,
segmentation fault, core dump, unresponsive-window report, GPU fault, or OOM
event.
