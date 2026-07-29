# silisili v1.0

Release date: 2026-07-29

This is the first public release of `silisili`, a Sailfish OS port and modification of wiliwili 1.6.0. The project was developed with Vibe Coding and is distributed under GPL-3.0-or-later.

## Highlights

- Sailfish-style full-screen phone layout with persistent Home, Activity and Me navigation.
- Bilibili mobile information hierarchy without website-only App promotion controls.
- Touch-first video controls, page-stack Back behavior and aspect-correct portrait or landscape fullscreen.
- Complete comment pagination, pull-to-refresh and mobile-sized comment/recommendation tabs.
- Sailfish Maliit input method support for text and numeric fields, with touch Back and OK controls.
- Display blanking inhibition only while video is actively playing in the foreground.
- Renamed application identity, source namespace, configuration directory and Sailfish launcher assets.
- First-run private migration from an existing wiliwili configuration when no silisili configuration exists.

## Current package fixes

- Package revision `1.0.0-2` is rebuilt from the Sailfish OS 5.0.0.62 SDK
  and supports both Sailfish OS 5.0 and 5.1 from one AArch64 RPM.
- Private FFmpeg 5.1 with HTTPS, mpv, libplacebo, libass, curl, and OpenSSL are
  built on the 5.0 ABI; GCC 10 libstdc++ comes from Sailfish OS.
- The release gate enforces `GLIBC_2.30`, `GLIBCXX_3.4.28`, and
  `CXXABI_1.3.12` ceilings.
- Desktop window-fullscreen switches are hidden on Sailfish phones, preventing
  repeated toggles from shrinking the compositor surface into the top-left.
- Player OSD buttons, icons, time labels, and the seek target are enlarged for
  reliable phone touch operation.
- Two consecutive landscape enter/exit cycles on the tested phone kept the
  physical application window at 1080x2160 and restored the portrait layout
  without the previous top-left shrink.
- Live pages now use one Activity-level close path for both system Back and the player OSD Back button.
- The OSD Back touch target invokes its close action directly, including live layouts without an AppletFrame.
- Comment, episode and recommendation tabs use compact in-flow counters that cannot overlap their labels.

## Tested device

- Google Pixel 3a XL (`bonito`)
- Sailfish OS 5.1.0.11
- AArch64 package verified with `rpm -V`

Sailfish OS 5.0 compatibility is verified against the 5.0.0.62 SDK and ABI;
no 5.0 real-device test is claimed.

The complete SDK, ABI, runtime-library and phone regression record is in
[`docs/SAILFISH_5X_VALIDATION.md`](docs/SAILFISH_5X_VALIDATION.md).

## Download

```text
silisili-sailfish-1.0.0-2.aarch64.rpm
SHA-256: 8ec6612503596e026a5205618d564c592473a076ba30eee7a476ec1da1d4bee8
```

Source patch SHA-256:

```text
2f50d87181f42331955e1f332754ad9e8047662c31d1c29c219f2736dbd943e5  patches/silisili-sailfish-mobile.patch
```
