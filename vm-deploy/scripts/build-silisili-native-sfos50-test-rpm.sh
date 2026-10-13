#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
project_root=$(cd "$script_dir/../.." && pwd)
workspace_root=$(cd "$project_root/../.." && pwd)
output_dir=${OUTPUT_DIR:-$workspace_root/outputs/sailfish-5.0}
spec_release=$(awk '$1 == "Release:" { print $2; exit }' "$project_root/packaging/apps/silisili-native/silisili-native.spec")
package_release=${PACKAGE_RELEASE_OVERRIDE:-$spec_release.sf50test1}
host_builder=${SAILFISH_50_HOST_BUILDER:-$script_dir/build-silisili-native-vm-rpm.sh}

test -x "$host_builder"
"$script_dir/prepare-sailfish-5.0-sdk.sh" --apply
install -d -m0755 "$output_dir"

arm-linux-gnueabihf-gcc \
    -march=armv7-a -mfloat-abi=softfp \
    -fPIC -fvisibility=hidden -nostdlib -nodefaultlibs \
    -shared -Wl,--hash-style=both \
    -Wl,-soname,libminimedia-audiosource-shim.so \
    "$project_root/packaging/apps/silisili-native/minimediaservice-audiosource-shim.c" \
    -o "$output_dir/libminimedia-audiosource-shim.so"

TARGET=SailfishOS-5.0.0.62-aarch64 \
OUTPUT_DIR="$output_dir" \
BUILD_ROOT=/home/builder/silisili-native-sfos50-test-build \
SOURCE_COPY=/home/builder/silisili-native-sfos50-test-source \
WORK_ROOT=/home/builder/silisili-native-sfos50-test-package \
SYSROOT=/home/builder/silisili-native-sfos50-test-sysroot \
MEDIA_COPY=/home/builder/silisili-native-sfos50-test-media \
PACKAGE_RELEASE_OVERRIDE="$package_release" \
GLIBC_CEILING=GLIBC_2.30 \
GLIBCXX_CEILING=GLIBCXX_3.4.28 \
CXXABI_CEILING=CXXABI_1.3.12 \
REUSE_OBJECTS=0 \
    "$host_builder"

rpm_path="$output_dir/silisili-native-devel-1.1.0-$package_release.aarch64.rpm"
test -f "$rpm_path"
rpm_sha256=$(sha256sum "$rpm_path" | awk '{print $1}')
printf '%s  %s\n' "$rpm_sha256" "$(basename "$rpm_path")" \
    >"$rpm_path.sha256"
printf 'silisili_sfos50_build=ready|target=%s|package=%s|bytes=%s|sha256=%s|device_validation=pending\n' \
    SailfishOS-5.0.0.62-aarch64 \
    "silisili-native-devel-1.1.0-$package_release.aarch64" \
    "$(stat -c %s "$rpm_path")" \
    "$rpm_sha256"
