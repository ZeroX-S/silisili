# Building silisili

## Source layout

This repository is a complete source snapshot. Third-party source trees are vendored so the Sailfish-specific Borealis and GLFW changes are available without separate forks or Git submodules.

The application source is under `silisili/`. Sailfish package metadata is under `packaging/apps/silisili/`, and the complete source delta from upstream wiliwili 1.6.0 is `patches/silisili-sailfish-mobile.patch`.

## CMake build

The release build uses the Sailfish OS `5.0.0.62-aarch64` target and
`5.0.0.62-i486` tooling. Building against 5.0 is the compatibility baseline;
the resulting AArch64 package also runs on Sailfish OS 5.1.

```sh
cmake -S . -B build -G Ninja \
  -DPLATFORM_DESKTOP=ON \
  -DINSTALL=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DGLFW_BUILD_WAYLAND=ON \
  -DGLFW_BUILD_X11=OFF \
  -DUSE_GLES2=ON \
  -DUSE_EGL=ON \
  -DSILISILI_SAILFISH_MOBILE=ON
cmake --build build
```

## Reproducible Sailfish RPM

`vm-deploy/scripts/build-silisili-sailfish-5x-runtime.sh` builds the pinned
private runtime with the 5.0 SDK. It produces private OpenSSL 3.0.16, curl
8.9.1, FFmpeg 5.1.6 with HTTPS, libass 0.17.3, libplacebo 6.338.2, and mpv
0.37.0 libraries. All C++ code uses Sailfish GCC 10 libstdc++.

`vm-deploy/scripts/build-silisili-sailfish-rpm.sh` then rebuilds the complete
application with the same SDK and assembles `silisili-sailfish-1.0.0-2`.
Before packaging, it checks AArch64 identity, reviewed `DT_NEEDED` entries,
private RPATHs, and these Sailfish 5.0 ceilings:

```text
GLIBC_2.30
GLIBCXX_3.4.28
CXXABI_1.3.12
```

Run both scripts from the Sailfish SDK chroot. The runtime sources must be at
the pinned commits documented in `packaging/apps/silisili/UPSTREAM.md`:

- `SailfishOS-5.0.0.62-aarch64` target
- `SailfishOS-5.0.0.62-i486` tooling
- the complete silisili source tree
- pinned runtime source trees under `$HOME/silisili-5x-work`

The checked-in launcher PNGs are generated with
`packaging/apps/silisili/generate-launcher-icons.py`; Pillow is only needed
when regenerating those assets, not while compiling the RPM.

## Verification

The release was checked with:

```sh
PROJECT_ROOT=/path/to/project vm-deploy/scripts/verify-ported-app-rpms.sh
```

Runtime checks in `vm-deploy/scripts/verify-silisili-runtime.sh` require a Sailfish OS device and cover package integrity, launcher identity, responsive touch UI, input method integration, navigation, comments, video fullscreen behavior and playback display inhibition.
