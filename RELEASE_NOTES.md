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

## Tested device

- Google Pixel 3a XL (`bonito`)
- Sailfish OS 5.1
- AArch64 package verified with `rpm -V`

## Download

```text
silisili-sailfish-1.0.0-1.aarch64.rpm
SHA-256: 351ddeaed154a5d6374ea8a5c59a6d95d9bf16be9defc4e668c36b9164e6870b
```

Source patch SHA-256:

```text
6ec211d9f4e51365acc20edd251d712a12f634b1a393afc54d16dcde4c3e8d47  patches/silisili-sailfish-mobile.patch
```
