#!/bin/bash
set -euo pipefail

if test "${SILISILI_RELINK_INSIDE_SB2:-0}" != 1; then
    sdk_bin=${SAILFISH_SDK_BIN:-/opt/sailfish-hadk/platform/sdks/sfossdk/usr/bin}
    sb2=${SAILFISH_SB2:-$sdk_bin/sb2}
    sdk_root=$(cd "$sdk_bin/../.." && pwd)
    test -x "$sb2"
    exec /usr/bin/env QEMU_LD_PREFIX="$sdk_root" \
        "$sb2" -t "${SAILFISH_TARGET:-SailfishOS-5.1.0.11-aarch64}" \
        -m sdk-build /usr/bin/env SILISILI_RELINK_INSIDE_SB2=1 \
        SILISILI_MPV_PREFIX="${SILISILI_MPV_PREFIX:-}" \
        /bin/bash "$0" "$@"
fi

# Run inside the Sailfish SDK chroot. Reuse a device-validated CMake object's
# unchanged C++ graph only when the candidate src tree is byte-identical, then
# rebuild the release-bearing main object and the complete QML resource object.

if test "$#" -ne 4; then
    echo 'usage: relink-silisili-native-qml-candidate.sh BASELINE_NATIVE BUILD_DIR RELEASE CANDIDATE_NATIVE' >&2
    exit 64
fi

baseline_native=$1
build_dir=$2
package_release=$3
candidate_native=$4

test -d "$baseline_native/src"
test -d "$baseline_native/qml"
test -f "$build_dir/CMakeCache.txt"
test -d "$candidate_native/src"
test -d "$candidate_native/qml"
test -n "$package_release"
test -n "${SILISILI_MPV_PREFIX:-}"
test -f "$SILISILI_MPV_PREFIX/include/mpv/client.h"
test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so" \
    || test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so.2" \
    || test -e "$SILISILI_MPV_PREFIX/lib/libmpv.so.2.2.0"

diff -qr "$baseline_native/src" "$candidate_native/src"
cp -a "$candidate_native/qml/." "$baseline_native/qml/"

cmake -S "$baseline_native" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$SILISILI_MPV_PREFIX" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_RPATH=/usr/lib64/silisili-native \
    -DCMAKE_INSTALL_RPATH=/usr/lib64/silisili-native \
    -DCMAKE_SKIP_RPATH=OFF \
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
    "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1 -Wl,-rpath-link,$SILISILI_MPV_PREFIX/lib" \
    -DSILISILI_NATIVE_PACKAGE_RELEASE="$package_release"

cd "$build_dir"
target_makefile=CMakeFiles/silisili-native.dir/build.make
main_object=CMakeFiles/silisili-native.dir/src/main.cpp.o
qrc_source=silisili-native_autogen/CCBC4FUR7J/qrc_qml.cpp
qrc_object=CMakeFiles/silisili-native.dir/silisili-native_autogen/CCBC4FUR7J/qrc_qml.cpp.o

rm -f "$main_object" "$qrc_source" "$qrc_object"
make -f "$target_makefile" "$qrc_source"
make -f "$target_makefile" "$main_object" "$qrc_object"
/bin/sh CMakeFiles/silisili-native.dir/link.txt

test -x silisili-native
readelf -h silisili-native | grep -Fq AArch64
readelf -h silisili-native | grep -Fq 'Position-Independent Executable'
readelf -d silisili-native \
    | grep -E '(RPATH|RUNPATH).*\[/usr/lib64/silisili-native\]' >/dev/null
strings silisili-native | grep -Fxq "$package_release"
printf 'native_qml_relink=ready|release=%s|cpp_source_diff=clean|main_rebuilt=1|qrc_rebuilt=1|runtime_path=/usr/lib64/silisili-native\n' \
    "$package_release"
