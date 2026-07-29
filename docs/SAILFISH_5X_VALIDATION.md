# Sailfish OS 5.x validation

Validation completed on 2026-07-30 for package
`silisili-sailfish-1.0.0-2.aarch64.rpm`.

## Release identity

- RPM SHA-256:
  `8ec6612503596e026a5205618d564c592473a076ba30eee7a476ec1da1d4bee8`
- Source patch SHA-256:
  `2f50d87181f42331955e1f332754ad9e8047662c31d1c29c219f2736dbd943e5`
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
- Installed package `silisili-sailfish-1.0.0-2`
- Package integrity checked with `rpm -V`

The live process used Sailfish's system
`/usr/lib64/libstdc++.so.6.0.32` and loaded private `libavcodec`,
`libavformat`, `libmpv`, `libcurl`, and `libssl` from
`/usr/lib64/silisili`.

Desktop window-fullscreen controls were absent from both settings surfaces:

- [Application settings](screenshots/5x-test/23-interface-settings-no-window-fullscreen.png)
- [Player settings](screenshots/5x-test/26-player-settings-no-window-fullscreen.png)

The enlarged phone OSD is captured in
[the player OSD screenshot](screenshots/5x-test/25-enlarged-player-osd.png).

### Consecutive fullscreen cycles

Both cycles used the center of the enlarged fullscreen touch target at
physical coordinate `(1030, 535)`.

| Cycle | Enter evidence | Exit evidence | Runtime geometry |
| --- | --- | --- | --- |
| 1 | [Landscape](screenshots/5x-test/33-fullscreen-cycle-1-enter.png) | [Portrait full window](screenshots/5x-test/34-fullscreen-cycle-1-exit.png) | enter `1080x2160` physical / `1280x640` logical; exit `1080x2160` physical / `640x1280` logical |
| 2 | [Landscape](screenshots/5x-test/36-fullscreen-cycle-2-enter.png) | [Portrait full window](screenshots/5x-test/37-fullscreen-cycle-2-exit.png) | enter `1080x2160` physical / `1280x640` logical; exit `1080x2160` physical / `640x1280` logical |

The application PID remained stable across both cycles. The window never
changed from the 1080x2160 physical compositor surface and did not shrink into
the top-left. Final application and journal checks contained no SIGABRT,
segmentation fault, core dump, unresponsive-window report, GPU fault, or OOM
event.
