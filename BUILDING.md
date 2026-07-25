# Building silisili

## Source layout

This repository is a complete source snapshot. Third-party source trees are vendored so the Sailfish-specific Borealis and GLFW changes are available without separate forks or Git submodules.

The application source is under `silisili/`. Sailfish package metadata is under `packaging/apps/silisili/`, and the complete source delta from upstream wiliwili 1.6.0 is `patches/silisili-sailfish-mobile.patch`.

## CMake build

The Sailfish build requires an AArch64 C/C++ cross-toolchain, CMake, Ninja, OpenSSL, curl, Wayland, EGL/GLES2, mpv and the remaining libraries listed by the top-level CMake files.

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

`vm-deploy/scripts/build-silisili-sailfish-rpm.sh` is the exact builder used for `v1.0`. It intentionally starts from clean wiliwili 1.6.0 and applies the published patch, then verifies every pinned input before assembling the package.

The script expects a Linux AArch64 cross-build environment with RPM tooling and these inputs:

- clean wiliwili commit `88e5876bea9502d06f46a8656e3530684d3aaf7d`
- Borealis commit `5f08b286f3df737f3321d2247a6fe633fcead03c`
- the validated base runtime RPM and development packages listed in `packaging/apps/silisili/UPSTREAM.md`
- Pillow for deterministic PNG generation

Set `PROJECT_ROOT`, `UPSTREAM_SOURCE_ROOT`, `BASE_RPM`, `DEV_DEB_DIR`, and `OUTPUT_DIR` as needed. The builder verifies the pinned SHA-256 values before using any input.

## Verification

The release was checked with:

```sh
PROJECT_ROOT=/path/to/project vm-deploy/scripts/verify-ported-app-rpms.sh
```

Runtime checks in `vm-deploy/scripts/verify-silisili-runtime.sh` require a Sailfish OS device and cover package integrity, launcher identity, responsive touch UI, input method integration, navigation, comments, video fullscreen behavior and playback display inhibition.
