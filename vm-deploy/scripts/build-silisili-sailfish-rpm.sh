#!/usr/bin/env bash
set -euo pipefail

umask 0022
export LC_ALL=C
export TZ=UTC
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1785196800}"
export SOURCE_DATE_EPOCH

TARGET="${SAILFISH_TARGET:-SailfishOS-5.0.0.62-aarch64}"
TOOLING_NAME="${SAILFISH_TOOLING:-SailfishOS-5.0.0.62-i486}"
TOOLING="/srv/mer/toolings/$TOOLING_NAME"
PROJECT_ROOT="${PROJECT_ROOT:-$HOME/silisili-release}"
PACKAGE_DIR="$PROJECT_ROOT/packaging/apps/silisili"
RUNTIME_SOURCE_ROOT="${RUNTIME_SOURCE_ROOT:-$HOME/silisili-5x-work}"
PRIVATE_PREFIX="${PRIVATE_PREFIX:-$HOME/silisili-5x-build/prefix}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/silisili-5x-app-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/silisili-5x-artifacts}"
BUILD_JOBS="${BUILD_JOBS:-4}"
PRIVATE_RPATH=/usr/lib64/silisili

CMAKE="$TOOLING/usr/bin/cmake"
NINJA="$TOOLING/usr/bin/ninja"
RPMBUILD="${RPMBUILD:-/usr/bin/rpmbuild}"
RPMSPEC="${RPMSPEC:-/usr/bin/rpmspec}"

fail() {
    echo "Sailfish 5.x RPM build failed: $*" >&2
    exit 1
}

target_run() {
    sb2 -t "$TARGET" "$@"
}

cmake_run() {
    target_run "$CMAKE" "$@"
}

ninja_run() {
    target_run "$NINJA" "$@"
}

maximum_elf_version() {
    local root="$1" prefix="$2" elf newest maximum=

    while IFS= read -r -d '' elf; do
        readelf -h "$elf" >/dev/null 2>&1 || continue
        newest="$(readelf --version-info "$elf" 2>/dev/null |
            grep -oE "${prefix}_[0-9]+(\.[0-9]+)+" | sort -Vu | tail -1 || true)"
        test -n "$newest" || continue
        maximum="$(printf '%s\n%s\n' "$maximum" "$newest" |
            sed '/^$/d' | sort -V | tail -1)"
    done < <(find "$root" -type f -print0)
    printf '%s\n' "${maximum:-${prefix}_0}"
}

verify_version_ceiling() {
    local root="$1" prefix="$2" allowed="$3" maximum

    maximum="$(maximum_elf_version "$root" "$prefix")"
    test "$(printf '%s\n%s\n' "$maximum" "$allowed" | sort -V | tail -1)" = \
        "$allowed" || fail "payload requires $maximum, newer than $allowed"
    echo "$prefix ceiling passed: $maximum"
}

verify_needed() {
    local root="$1" elf needed private unknown=0

    while IFS= read -r -d '' elf; do
        readelf -h "$elf" >/dev/null 2>&1 || continue
        while IFS= read -r needed; do
            test -n "$needed" || continue
            private="$root/lib/$needed"
            test -e "$private" && continue
            case "$needed" in
                ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libgcc_s.so.1|libstdc++.so.6|libatomic.so.1|libz.so.1|libwebp.so.7|libdbus-1.so.3|libpulse.so.0|libfontconfig.so.1|libfreetype.so.6|libfribidi.so.0|libharfbuzz.so.0|libwayland-client.so.0|libwayland-cursor.so.0|libwayland-egl.so.1|libxkbcommon.so.0|libEGL.so.1|libGLESv2.so.2|libavcodec.so.59|libavfilter.so.8|libavformat.so.59|libavutil.so.57|libswresample.so.4|libswscale.so.6)
                    ;;
                *)
                    echo "Unknown NEEDED entry in ${elf#$root}: $needed" >&2
                    unknown=1
                    ;;
            esac
        done < <(readelf -d "$elf" 2>/dev/null |
            sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
    done < <(find "$root" -type f -print0)
    test "$unknown" -eq 0 || fail "unreviewed shared-library dependency"
}

for tool in git readelf rpm sb2 sed sort; do
    command -v "$tool" >/dev/null || fail "missing SDK tool: $tool"
done
test -x "$CMAKE" || fail "CMake is not installed in $TOOLING_NAME"
test -x "$NINJA" || fail "Ninja is not installed in $TOOLING_NAME"
test -x "$RPMBUILD" || fail "rpmbuild is not installed in the SDK"
test -x "$RPMSPEC" || fail "rpmspec is not installed in the SDK"
test -f "$PROJECT_ROOT/CMakeLists.txt" || fail "project source is missing: $PROJECT_ROOT"
test -f "$PACKAGE_DIR/silisili-sailfish.spec" || fail "RPM spec is missing"
test -f "$PRIVATE_PREFIX/include/mpv/client.h" || fail "private mpv headers are missing"
test -e "$PRIVATE_PREFIX/lib/libmpv.so.2" || fail "private mpv runtime is missing"
test -f "$PRIVATE_PREFIX/include/curl/curl.h" || fail "private curl headers are missing"
test -e "$PRIVATE_PREFIX/lib/libcurl.so.4" || fail "private curl runtime is missing"

case "$BUILD_ROOT" in
    "$HOME"/silisili-5x-app-build) ;;
    *) fail "BUILD_ROOT must remain the dedicated silisili-5x-app-build directory" ;;
esac
if test "${CLEAN_BUILD:-1}" = 1 && test -d "$BUILD_ROOT"; then
    find "$BUILD_ROOT" -mindepth 1 -depth -delete
fi

build_root="$BUILD_ROOT/build"
stage="$BUILD_ROOT/stage"
topdir="$BUILD_ROOT/rpmbuild"
install -d -m0755 "$build_root" "$stage/lib" "$stage/licenses" \
    "$stage/icons" "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    "$OUTPUT_DIR"

export CFLAGS="-ffile-prefix-map=$PROJECT_ROOT=/usr/src/silisili-1.0.0 -ffile-prefix-map=$BUILD_ROOT=/usr/src/silisili-build"
export CXXFLAGS="$CFLAGS"
export PKG_CONFIG_PATH="$PRIVATE_PREFIX/lib/pkgconfig"

cmake_run -S "$PROJECT_ROOT" -B "$build_root" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DPLATFORM_DESKTOP=ON \
    -DINSTALL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_RPATH="$PRIVATE_RPATH" \
    -DCMAKE_INSTALL_RPATH="$PRIVATE_RPATH" \
    -DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1 \
    -DGLFW_BUILD_WAYLAND=ON \
    -DGLFW_BUILD_X11=OFF \
    -DUSE_SYSTEM_CURL=ON \
    -DUSE_GLES2=ON \
    -DUSE_EGL=ON \
    -DBRLS_UNITY_BUILD=ON \
    -DCMAKE_UNITY_BUILD_BATCH_SIZE=16 \
    -DSILISILI_SAILFISH_MOBILE=ON \
    -DMPV_INCLUDE_DIR="$PRIVATE_PREFIX/include" \
    -DMPV_LIBRARY_mpv="$PRIVATE_PREFIX/lib/libmpv.so" \
    -DCURL_INCLUDE_DIR="$PRIVATE_PREFIX/include" \
    -DCURL_LIBRARY="$PRIVATE_PREFIX/lib/libcurl.so" \
    -DCURL_CONFIG_EXECUTABLE="$PRIVATE_PREFIX/bin/curl-config"
ninja_run -C "$build_root" -j"$BUILD_JOBS"

target_run gcc -Os -fPIE -pie -fno-ident -Wl,-z,relro,-z,now \
    -o "$stage/launcher" "$PACKAGE_DIR/launcher.c"
target_run strip --strip-unneeded "$stage/launcher"
install -m0755 "$build_root/silisili" "$stage/silisili"
target_run strip --strip-unneeded --remove-section=.note.gnu.build-id "$stage/silisili"

for pattern in \
    'libcrypto.so*' 'libssl.so*' 'libcurl.so*' \
    'libavcodec.so*' 'libavfilter.so*' 'libavformat.so*' \
    'libavutil.so*' 'libswresample.so*' 'libswscale.so*' \
    'libass.so*' 'libplacebo.so*' 'libmpv.so*'; do
    found=0
    for runtime in "$PRIVATE_PREFIX/lib"/$pattern; do
        test -e "$runtime" || continue
        cp -a "$runtime" "$stage/lib/"
        found=1
    done
    test "$found" -eq 1 || fail "missing private runtime pattern: $pattern"
done
chmod 0755 "$stage/lib"

cp -a "$PROJECT_ROOT/resources" "$stage/resources"
rm -f "$stage/resources/font/keymap_xbox.ttf" \
    "$stage/resources/font/keymap_ps.ttf" \
    "$stage/resources/font/keymap_keyboard_swap.ttf" \
    "$stage/resources/font/FREEWARE.txt" \
    "$stage/resources/gamecontrollerdb.txt" \
    "$stage/resources/pictures/hint_game_1.png" \
    "$stage/resources/pictures/hint_game_2.png"
cp -a "$PACKAGE_DIR/icons/hicolor" "$stage/icons/"
install -m0644 "$PACKAGE_DIR/silisili.desktop" "$stage/silisili.desktop"

install -m0644 "$PROJECT_ROOT/LICENSE" "$stage/licenses/LICENSE.silisili-GPLv3"
install -m0644 "$PROJECT_ROOT/library/borealis/LICENSE" "$stage/licenses/LICENSE.borealis"
install -m0644 "$PROJECT_ROOT/library/borealis/library/lib/extern/glfw/LICENSE.md" \
    "$stage/licenses/LICENSE.glfw"
install -m0644 "$PROJECT_ROOT/library/borealis/library/lib/extern/glfw/deps/wayland/surface-extension.xml" \
    "$stage/licenses/LICENSE.qt-wayland-surface-extension"
install -m0644 "$RUNTIME_SOURCE_ROOT/openssl/LICENSE.txt" \
    "$stage/licenses/LICENSE.openssl-Apache-2.0"
install -m0644 "$RUNTIME_SOURCE_ROOT/curl/COPYING" "$stage/licenses/LICENSE.curl"
install -m0644 "$RUNTIME_SOURCE_ROOT/ffmpeg/COPYING.LGPLv2.1" \
    "$stage/licenses/LICENSE.ffmpeg-LGPLv2.1"
install -m0644 "$RUNTIME_SOURCE_ROOT/libass/COPYING" "$stage/licenses/LICENSE.libass"
install -m0644 "$RUNTIME_SOURCE_ROOT/libplacebo/LICENSE" "$stage/licenses/LICENSE.libplacebo"
install -m0644 "$RUNTIME_SOURCE_ROOT/mpv037/Copyright" "$stage/licenses/LICENSE.mpv"
install -m0644 "$PACKAGE_DIR/UPSTREAM.md" "$stage/licenses/UPSTREAM.md"

find "$stage/resources" "$stage/icons" "$stage/licenses" -type d \
    -exec chmod 0755 {} +
find "$stage/resources" "$stage/icons" "$stage/licenses" -type f \
    -exec chmod a+r {} +
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

readelf -h "$stage/launcher" | grep -Fq AArch64 || fail "launcher is not AArch64"
readelf -h "$stage/silisili" | grep -Fq AArch64 || fail "application is not AArch64"
readelf -d "$stage/silisili" | grep -Fq "$PRIVATE_RPATH" || fail "application RPATH is missing"
grep -aFq 'Sailfish mobile UI baseline: 640x360; fixed short edge: 640; video grids: portrait 2 landscape 4' \
    "$stage/silisili" || fail "Sailfish mobile UI marker is missing"
grep -aFq 'Sailfish Bilibili fullscreen layout:' "$stage/silisili" ||
    fail "fullscreen layout marker is missing"
grep -aFq 'Sailfish player controls: 56pt primary touch targets; 52pt secondary touch targets' \
    "$stage/silisili" || fail "mobile player control-size marker is missing"
grep -aFq 'Sailfish page back swipe: started at' "$stage/silisili" ||
    fail "Sailfish page-stack swipe marker is missing"
grep -aFq 'Sailfish dialog bounds:' "$stage/silisili" ||
    fail "Sailfish popup bounds marker is missing"
grep -aFq 'Sailfish input dialog: system IME with touch Back/OK toolbar' \
    "$stage/silisili" || fail "Sailfish input marker is missing"
grep -aFq 'Sailfish comments: appended page=' "$stage/silisili" ||
    fail "comment pagination marker is missing"
grep -aFq 'Sailfish navigation: persistent header and bottom Home/Dynamic/Mine tabs' \
    "$stage/silisili" || fail "mobile navigation marker is missing"
test ! -e "$stage/lib/libstdc++.so.6" || fail "private libstdc++ must not be packaged"
readelf -d "$stage/lib/libmpv.so.2" | grep -Fq 'libavcodec.so.59' ||
    fail "private mpv is not linked to private FFmpeg 5.1"
readelf -d "$stage/lib/libavformat.so.59" | grep -Fq 'libssl.so.3' ||
    fail "private FFmpeg HTTPS is not linked to private OpenSSL 3"
grep -aFq 'https' "$stage/lib/libavformat.so.59" ||
    fail "private FFmpeg lacks HTTPS protocol support"
readelf -d "$stage/lib/libcurl.so.4" | grep -Fq 'libssl.so.3' ||
    fail "private curl is not linked to private OpenSSL 3"
! readelf -d "$stage/lib/libplacebo.so.338" | grep -Fq libunwind ||
    fail "libplacebo unexpectedly requires libunwind"

while IFS= read -r -d '' elf; do
    readelf -h "$elf" >/dev/null 2>&1 || continue
    readelf -h "$elf" | grep -Fq AArch64 || fail "non-AArch64 ELF: $elf"
done < <(find "$stage" -type f -print0)
verify_needed "$stage"
verify_version_ceiling "$stage" GLIBC GLIBC_2.30
verify_version_ceiling "$stage" GLIBCXX GLIBCXX_3.4.28
verify_version_ceiling "$stage" CXXABI CXXABI_1.3.12

target_run "$RPMBUILD" -bb \
    --define "_topdir $topdir" \
    --define "_buildhost sailfish-5.0-sdk" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "stagingdir $stage" \
    "$PACKAGE_DIR/silisili-sailfish.spec"

package_version="$(target_run "$RPMSPEC" -q --qf '%{VERSION}-%{RELEASE}' \
    "$PACKAGE_DIR/silisili-sailfish.spec")"
rpm_path="$(find "$topdir/RPMS" -type f \
    -name "silisili-sailfish-${package_version}.aarch64.rpm" -print -quit)"
test -n "$rpm_path" || fail "rpmbuild did not produce the expected package"
install -m0644 "$rpm_path" "$OUTPUT_DIR/$(basename "$rpm_path")"
sha256sum "$OUTPUT_DIR/$(basename "$rpm_path")"
