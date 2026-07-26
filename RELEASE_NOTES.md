# silisili v1.0

Release date: 2026-07-26

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

- Live pages now use one Activity-level close path for both system Back and the player OSD Back button.
- The OSD Back touch target invokes its close action directly, including live layouts without an AppletFrame.
- Comment, episode and recommendation tabs use compact in-flow counters that cannot overlap their labels.

## Tested device

- Google Pixel 3a XL (`bonito`)
- Sailfish OS 5.1
- AArch64 package verified with `rpm -V`

## Download

```text
silisili-sailfish-1.0.0-1.aarch64.rpm
SHA-256: 97f852af49de3e02c8afce2fc2dfbbda5d3f4933b71602cd227eb12502445cde
```

Source patch SHA-256:

```text
8bddf70d3a888e0966a283781191cecc6b6a976d5cceb7906b7fbe6f8c4bed3d  patches/silisili-sailfish-mobile.patch
```
