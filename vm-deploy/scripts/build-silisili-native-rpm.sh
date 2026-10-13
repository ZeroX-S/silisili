#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C
export TZ=UTC
TARGET="${SAILFISH_TARGET:-SailfishOS-5.0.0.62-aarch64}"
SDK_BIN="${SAILFISH_SDK_BIN:-/opt/sailfish-hadk/platform/sdks/sfossdk/usr/bin}"
SB2="${SAILFISH_SB2:-$SDK_BIN/sb2}"
TOOLING_NAME="${SAILFISH_TOOLING:-SailfishOS-5.0.0.62-i486}"
TOOLING_ROOT="${SAILFISH_TOOLING_ROOT:-/srv/mer/toolings/$TOOLING_NAME}"
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/silisili-native}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/silisili-native-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/silisili-native-artifacts}"
PACKAGE_DIR="$PROJECT_ROOT/packaging/apps/silisili-native"
CMAKE_PREFIX_ARGS=()
LINKER_FLAGS='-Wl,--build-id=sha1'
PRIVATE_RUNTIME_DIR=/usr/lib64/silisili-native
PATCHELF="${PATCHELF:-/parentroot/bin/patchelf}"
PATCHELF_LOADER="${PATCHELF_LOADER:-/parentroot/lib/ld-linux-aarch64.so.1}"
PATCHELF_LIBRARY_PATH="${PATCHELF_LIBRARY_PATH:-/parentroot/lib/aarch64-linux-gnu:/parentroot/usr/lib/aarch64-linux-gnu}"
RUNTIME_LIBRARY_PATTERNS=(
    'libcrypto.so*' 'libssl.so*' 'libcurl.so*'
    'libavcodec.so*' 'libavfilter.so*' 'libavformat.so*'
    'libavutil.so*' 'libswresample.so*' 'libswscale.so*'
    'libass.so*' 'libplacebo.so*' 'libmpv.so*'
)
RUNTIME_LICENSE_NAMES=(
    LICENSE.curl LICENSE.ffmpeg-LGPLv2.1 LICENSE.libass
    LICENSE.libplacebo LICENSE.mpv LICENSE.openssl-Apache-2.0
)

fail() { echo "Native Sailfish RPM build failed: $*" >&2; exit 1; }
target_run() { "$SB2" -t "$TARGET" "$@"; }
patchelf_run() {
    if "$PATCHELF" --version >/dev/null 2>&1; then
        "$PATCHELF" "$@"
    else
        "$PATCHELF_LOADER" --library-path "$PATCHELF_LIBRARY_PATH" \
            "$PATCHELF" "$@"
    fi
}

test -x "$SB2" || fail "missing sb2 at $SB2"
test -x "$TOOLING_ROOT/usr/bin/cmake" || fail "missing tooling CMake under $TOOLING_ROOT"
test -x "$PATCHELF" || fail "missing patchelf at $PATCHELF"
if ! "$PATCHELF" --version >/dev/null 2>&1; then
    test -x "$PATCHELF_LOADER" || fail "missing host ELF loader at $PATCHELF_LOADER"
fi
patchelf_run --version >/dev/null || fail "patchelf is not runnable in the SDK chroot"
for tool in rpmbuild rpmspec readelf; do
    target_run sh -lc "command -v $tool >/dev/null" || fail "missing target tool: $tool"
done
if test "${SAILFISH_CMAKE_GENERATOR:-}" = make; then
    test -x "$TOOLING_ROOT/usr/bin/make" || fail "missing tooling make"
    CMAKE_GENERATOR='Unix Makefiles'
    BUILD_COMMAND="$TOOLING_ROOT/usr/bin/make"
elif test "${SAILFISH_CMAKE_GENERATOR:-}" = ninja; then
    test -x "$TOOLING_ROOT/usr/bin/ninja" || fail "missing tooling ninja"
    CMAKE_GENERATOR=Ninja
    BUILD_COMMAND="$TOOLING_ROOT/usr/bin/ninja"
elif test -x "$TOOLING_ROOT/usr/bin/ninja"; then
    CMAKE_GENERATOR=Ninja
    BUILD_COMMAND="$TOOLING_ROOT/usr/bin/ninja"
else
    test -x "$TOOLING_ROOT/usr/bin/make" || fail "missing tooling build tool: ninja or make"
    CMAKE_GENERATOR='Unix Makefiles'
    BUILD_COMMAND="$TOOLING_ROOT/usr/bin/make"
fi
test -f "$PROJECT_ROOT/native/CMakeLists.txt" || fail "native source missing"
package_identity="$(target_run rpmspec -q --qf '%{VERSION}|%{RELEASE}\n' \
    "$PACKAGE_DIR/silisili-native.spec" | sed -n '1p')"
package_version="${package_identity%%|*}"
package_release="${package_identity#*|}"
test -n "$package_version" && test -n "$package_release" \
    || fail "could not resolve native package version/release"
grep -Fq "project(silisili-native VERSION $package_version " \
    "$PROJECT_ROOT/native/CMakeLists.txt" \
    || fail "CMake project version and RPM version differ"
if test -n "${SILISILI_MPV_PREFIX:-}"; then
    test -f "$SILISILI_MPV_PREFIX/include/mpv/client.h" || fail "missing libmpv headers under SILISILI_MPV_PREFIX"
    test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so" \
        || test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so.2" \
        || test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so.2.2.0" \
        || fail "missing libmpv library under SILISILI_MPV_PREFIX"
    CMAKE_PREFIX_ARGS+=("-DCMAKE_PREFIX_PATH=$SILISILI_MPV_PREFIX")
    # Resolve libmpv's private dependencies only while linking.  The RPM
    # must not retain this build prefix as a runtime library search path.
    LINKER_FLAGS="$LINKER_FLAGS -Wl,-rpath-link,$SILISILI_MPV_PREFIX/lib"
else
    fail "SILISILI_MPV_PREFIX must name the validated private media runtime"
fi

if test "${CLEAN_BUILD:-1}" = 1 && test -d "$BUILD_ROOT"; then
    find "$BUILD_ROOT" -mindepth 1 -depth -delete
elif test "${CLEAN_BUILD:-1}" = 0; then
    # Retain compiled objects but rebuild every packaging input from scratch.
    for packaging_root in "$BUILD_ROOT/stage" "$BUILD_ROOT/rpmbuild"; do
        test ! -d "$packaging_root" || find "$packaging_root" -mindepth 1 -depth -delete
    done
fi
build="$BUILD_ROOT/build"
stage="$BUILD_ROOT/stage"
topdir="$BUILD_ROOT/rpmbuild"
install -d -m0755 "$build" "$stage/lib" "$stage/licenses" "$OUTPUT_DIR" \
    "$stage/systemd" "$stage/libexec" \
    "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

target_run "$TOOLING_ROOT/usr/bin/cmake" -S "$PROJECT_ROOT/native" -B "$build" -G "$CMAKE_GENERATOR" \
    "-DCMAKE_MAKE_PROGRAM=$BUILD_COMMAND" \
    -DCMAKE_BUILD_TYPE=Release \
    "-DSILISILI_NATIVE_PACKAGE_RELEASE=$package_release" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    "-DCMAKE_BUILD_RPATH=$PRIVATE_RUNTIME_DIR" \
    "-DCMAKE_INSTALL_RPATH=$PRIVATE_RUNTIME_DIR" \
    -DCMAKE_SKIP_RPATH=OFF \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    "-DCMAKE_EXE_LINKER_FLAGS=$LINKER_FLAGS" "${CMAKE_PREFIX_ARGS[@]}"
target_run "$BUILD_COMMAND" -C "$build" -j"${BUILD_JOBS:-4}"
install -m0755 "$build/silisili-native" "$stage/silisili-native"
target_run strip --strip-unneeded "$stage/silisili-native"
install -m0644 "$PACKAGE_DIR/silisili-native.desktop" "$stage/silisili-native.desktop"
install -m0644 "$PACKAGE_DIR/silisili-native.privileges" "$stage/silisili-native.privileges"

minimedia_shim="${SILISILI_MINIMEDIA_SHIM:-}"
test -n "$minimedia_shim" && test -f "$minimedia_shim" \
    || fail "SILISILI_MINIMEDIA_SHIM must name the built ARM compatibility shim"
file "$minimedia_shim" | grep -Fq 'ELF 32-bit' \
    || fail "minimedia compatibility shim is not ELF32"
readelf -h "$minimedia_shim" | grep -Fq 'soft-float ABI' \
    || fail "minimedia compatibility shim is not ARM soft-float ABI"
readelf -Ws "$minimedia_shim" | grep -Fq \
    '_ZN7android11AudioSource14setReadAudioCbEPFvPvES1_' \
    || fail "minimedia compatibility symbol is missing"
if readelf -d "$minimedia_shim" | grep -q NEEDED; then
    fail "minimedia compatibility shim must not depend on glibc"
fi
install -m0755 "$minimedia_shim" "$stage/libexec/libminimedia-audiosource-shim.so"
install -m0755 "$PACKAGE_DIR/silisili-native-minimedia-wrapper.sh" \
    "$stage/libexec/silisili-native-minimedia-wrapper"
install -m0644 "$PACKAGE_DIR/silisili-native-minimedia.service" \
    "$stage/systemd/silisili-native-minimedia.service"

for pattern in "${RUNTIME_LIBRARY_PATTERNS[@]}"; do
    found=0
    for runtime in "$SILISILI_MPV_PREFIX/lib"/$pattern; do
        test -e "$runtime" || continue
        cp -a "$runtime" "$stage/lib/"
        found=1
    done
    test "$found" -eq 1 || fail "missing private runtime pattern: $pattern"
done
chmod 0755 "$stage/lib"

# The source prefix is shared with the stable package build and its dependency
# libraries carry /usr/lib64/silisili as their original RPATH.  Leaving that
# path in a development RPM makes libmpv silently load the stable package's
# FFmpeg instead of the bundled native runtime.  Rewrite every copied ELF
# dependency to the parallel-installable directory so the V4L2-M2M-enabled
# libavcodec is the one the process actually maps.
while IFS= read -r -d '' runtime; do
    # Keep DT_RPATH instead of converting it to DT_RUNPATH.  Sailfish 5.0's
    # older binutils cannot process the section-table layout produced by
    # patchelf 0.18 during the conversion, while the forced-RPATH layout is
    # accepted by both the SDK tools and the phone loader.
    patchelf_run --force-rpath --set-rpath "$PRIVATE_RUNTIME_DIR" "$runtime"
    target_run readelf -d "$runtime" | grep -Eq \
        "(RPATH|RUNPATH).*${PRIVATE_RUNTIME_DIR}" \
        || fail "private runtime RPATH rewrite failed: $runtime"
    # Strip each bundled dependency once, sequentially, before rpmbuild.  The
    # Sailfish find-debuginfo helper otherwise edits these already-built
    # libraries concurrently and corrupts the expanded patchelf string table.
    "$TOOLING_ROOT/opt/cross/bin/aarch64-meego-linux-gnu-strip" \
        --strip-unneeded "$runtime" \
        || fail "private runtime strip failed: $runtime"
    rpath_probe="$stage/.rpath-probe-$(basename "$runtime").debug"
    "$TOOLING_ROOT/opt/cross/bin/aarch64-meego-linux-gnu-objcopy" \
        --only-keep-debug "$runtime" "$rpath_probe" \
        || fail "private runtime is incompatible with Sailfish binutils: $runtime"
    rm -f "$rpath_probe"
done < <(find "$stage/lib" -type f -name '*.so*' -print0)

# The runtime prefix contains only installed libraries.  Reuse the already
# shipped 0.33 license payload for these unchanged private runtime components,
# so every development RPM remains self-contained and auditable.
runtime_license_rpm="${SILISILI_RUNTIME_LICENSE_RPM:-$OUTPUT_DIR/silisili-native-devel-1.1.0-0.33.aarch64.rpm}"
test -f "$runtime_license_rpm" || fail "missing runtime license source RPM: $runtime_license_rpm"
license_extract_root="$stage/runtime-license-extract"
install -d -m0755 "$license_extract_root"
target_run sh -lc "cd '$license_extract_root' && rpm2cpio '$runtime_license_rpm' | cpio -idm --quiet './usr/share/licenses/silisili-native-devel/*'"
for license_name in "${RUNTIME_LICENSE_NAMES[@]}"; do
    license_source="$license_extract_root/usr/share/licenses/silisili-native-devel/$license_name"
    test -f "$license_source" || fail "runtime license missing from source RPM: $license_name"
    install -m0644 "$license_source" "$stage/licenses/$license_name"
done
install -m0644 "$PROJECT_ROOT/LICENSE" "$stage/licenses/LICENSE.silisili-GPLv3"
install -m0644 "$PROJECT_ROOT/library/QR-Code-generator/Readme.markdown" \
    "$stage/licenses/LICENSE.qrcodegen-MIT"
install -m0644 "$PACKAGE_DIR/NOTICE.RooTheater" "$stage/licenses/NOTICE.RooTheater"
install -m0644 "$PACKAGE_DIR/NOTICE.ScreenTapShotLipstick" \
    "$stage/licenses/NOTICE.ScreenTapShotLipstick"
find "$stage/licenses" -type f -exec chmod a+r {} +

icon_source="$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native-devel.png"
test -f "$icon_source" || fail "native icon asset missing"
install -m0644 "$icon_source" "$stage/silisili-native-devel.png"
cover_pip_icon="$PROJECT_ROOT/native/qml/assets/cover-action-pip.png"
cover_cover_icon="$PROJECT_ROOT/native/qml/assets/cover-action-cover.png"
test -f "$cover_pip_icon" || fail "Cover PiP icon asset missing"
test -f "$cover_cover_icon" || fail "Cover mode icon asset missing"
install -m0644 "$cover_pip_icon" "$stage/silisili-native-cover-pip.png"
install -m0644 "$cover_cover_icon" "$stage/silisili-native-cover-cover.png"
readelf -h "$stage/silisili-native" | grep -Fq AArch64 || fail "binary is not AArch64"
readelf -h "$stage/silisili-native" | grep -Eq 'Type:.*DYN' \
    || fail "privileged mapplauncherd application is not PIE/ET_DYN"
readelf -d "$stage/silisili-native" | grep -Eq "(RPATH|RUNPATH).*${PRIVATE_RUNTIME_DIR}" \
    || fail "private runtime RPATH is missing"
grep -aFq 'Sailfish.Silica' "$stage/silisili-native" || fail "Silica QML resource missing"

target_run rpmbuild -bb --define "_topdir $topdir" --define "stagingdir $stage" "$PACKAGE_DIR/silisili-native.spec"
version="$(target_run rpmspec -q --qf '%{VERSION}-%{RELEASE}\n' "$PACKAGE_DIR/silisili-native.spec" | sed -n '1p')"
rpm_path="$topdir/RPMS/aarch64/silisili-native-devel-${version}.aarch64.rpm"
target_run test -f "$rpm_path" || fail "expected RPM not produced: $rpm_path"
target_run install -m0644 "$rpm_path" "$OUTPUT_DIR/$(basename "$rpm_path")"
target_run sha256sum "$OUTPUT_DIR/$(basename "$rpm_path")"
