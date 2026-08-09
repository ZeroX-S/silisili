# silisili v1.0

Release date: 2026-07-31

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

- Package revision `1.0.0-7` is rebuilt from the Sailfish OS 5.0.0.62 SDK
  and supports both Sailfish OS 5.0 and 5.1 from one AArch64 RPM.
- Private FFmpeg 5.1 with HTTPS, mpv, libplacebo, libass, curl, and OpenSSL are
  built on the 5.0 ABI; GCC 10 libstdc++ comes from Sailfish OS.
- The release gate enforces `GLIBC_2.30`, `GLIBCXX_3.4.28`, and
  `CXXABI_1.3.12` ceilings.
- Desktop window-fullscreen switches are hidden on Sailfish phones, preventing
  repeated toggles from shrinking the compositor surface into the top-left.
- Player OSD buttons use 48-56pt touch targets with 24-28pt visible icons; the
  title, viewer count, time labels, seek thumb and 56/72pt top/bottom overlays
  are balanced as separate native-client visual levels.
- Mobile-web typography is retained only as a content-density reference. The
  complete UI now follows Android/iOS client conventions: roughly 16pt body,
  12-14pt supporting text, 12pt bottom navigation, 24-28pt visible icons, and
  48-56pt touch targets. Explicit dense feeds retain two portrait columns.
- The settings sidebar is reduced to 160 logical units and phone padding is
  tightened to 16 units, leaving usable width for values without shrinking
  their touch rows.
- Resolution and aspect ratio continue to use the live short edge. Credible
  Wayland panel millimetres add a bounded physical-size/DPI correction; missing
  or placeholder data falls back to the tested 427 baseline.
- Nested pages and modal activities support a left-to-right Back pull from a
  narrow inset-left-edge start zone. It remains available over live video,
  while ordinary horizontal media gestures that start elsewhere are isolated.
- Dialogs keep a safe margin, dropdowns use the live phone width, and 56-unit
  rows keep every opened option on-screen.
- Two consecutive landscape enter/exit cycles on the tested phone kept the
  physical application window at 1080x2160 and restored the portrait layout
  without the previous top-left shrink.
- Live pages now use one Activity-level close path for both system Back and the player OSD Back button.
- The OSD Back touch target invokes its close action directly, including live layouts without an AppletFrame.
- Normal-video and live-stream quality changes preserve the current playing or
  paused state when the replacement media file loads.
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
silisili-sailfish-1.0.0-7.aarch64.rpm
SHA-256: db88e1f206c4ee519219df76b1a5be0125a5c2893709b90fb2b34227765e1ed5
```

Source patch SHA-256:

```text
44ee2f7321761806cdd66c1449cbb3ea38bc64761df1f50be4d8c8ca35c9420e  patches/silisili-sailfish-mobile.patch
```
