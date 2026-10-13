#!/usr/bin/env bash
set -euo pipefail

target=${SAILFISH_50_TARGET:-SailfishOS-5.0.0.62-aarch64}
tooling=${SAILFISH_50_TOOLING:-SailfishOS-5.0.0.62-i486}
source_target=${SAILFISH_50_DROIDMEDIA_SOURCE_TARGET:-google-bonito-aarch64}
platform_root=${SAILFISH_PLATFORM_ROOT:-/opt/sailfish-hadk/platform}
sdk=${SAILFISH_SDK_CHROOT:-$platform_root/sdks/sfossdk/sdk-chroot}
target_root=$platform_root/targets/$target
tooling_root=$platform_root/toolings/$tooling
source_root=$platform_root/targets/$source_target
apply=0

if test "${1:-}" = --apply; then
    apply=1
elif test "$#" -ne 0; then
    printf 'usage: %s [--apply]\n' "$0" >&2
    exit 64
fi

fail() {
    printf 'sailfish_50_sdk=failed|target=%s|reason=%s\n' "$target" "$1" >&2
    exit 1
}

verify_hash() {
    expected=$1
    path=$2
    test -f "$path" || fail "missing-source:${path#$source_root/}"
    actual=$(sha256sum "$path" | awk '{print $1}')
    test "$actual" = "$expected" \
        || fail "source-hash-mismatch:${path#$source_root/}"
}

test -x "$sdk" || fail missing-sdk-chroot
test -d "$target_root" || fail missing-target-root
test -d "$tooling_root" || fail missing-tooling-root
test -d "$source_root" || fail missing-droidmedia-source-target

targets=$("$sdk" -u builder -m all /usr/bin/sdk-assistant target list 2>/dev/null)
printf '%s\n' "$targets" | grep -Fxq "$target" || fail target-not-registered
toolings=$("$sdk" -u builder -m all /usr/bin/sdk-assistant tooling list 2>/dev/null)
printf '%s\n' "$toolings" | grep -Fxq "$tooling" || fail tooling-not-registered

for required in \
    usr/include/qt5/QtCore/QString \
    usr/include/sailfishapp/sailfishapp.h \
    usr/lib64/libQt5Core.so \
    usr/lib64/libsailfishapp.so \
    usr/share/qt5/mkspecs/modules/qt_lib_core.pri; do
    test -e "$target_root/$required" || fail "missing-target-file:$required"
done

verify_hash 737f3d879bfd4af3345b25448c32e9f20c4888ff741f69fe10730d1ef16ea2e9 \
    "$source_root/usr/include/droidmedia/droidmedia.h"
verify_hash 1ac06ac1d65e6b7bddcf318f3ca3dc61e55ef96328a6fb6f1c139f29d4e3a69c \
    "$source_root/usr/include/droidmedia/droidmediacodec.h"
verify_hash 3edf604075e8be16146cb5ed1d55aae38fcef13c7a6c7cfa9eb40c8dccf875ef \
    "$source_root/usr/include/droidmedia/droidmediaconstants.h"
verify_hash 45fba2f93253d755acc319fc201c221bb80426cc00e4a826c6e677834ddc08d1 \
    "$source_root/usr/include/droidmedia/droidmediaconvert.h"
verify_hash 696984211cdade7a10afb89e27a5492d8c4c9a8fea75e90be7dbdd617ad87b8d \
    "$source_root/usr/include/droidmedia/droidmediacamera.h"
verify_hash 8e0c6057ad351de530b83eed715536eae39650b03277a829b0ce310f61fe645c \
    "$source_root/usr/include/droidmedia/droidmediarecorder.h"
verify_hash 1211d77ee11dbdfcf412ccd014d821c8be43b15196b8c22d7e3990ccad984f6d \
    "$source_root/usr/lib64/libdroidmedia.a"
verify_hash 3524112912a0c89be833f3a73cddc58f98264d2148ddc91ab24983eb02569e43 \
    "$source_root/usr/lib64/pkgconfig/droidmedia.pc"

droidmedia_ready=1
for required in \
    usr/include/droidmedia/droidmedia.h \
    usr/include/droidmedia/droidmediacodec.h \
    usr/include/droidmedia/droidmediaconstants.h \
    usr/include/droidmedia/droidmediaconvert.h \
    usr/include/droidmedia/droidmediacamera.h \
    usr/include/droidmedia/droidmediarecorder.h \
    usr/lib64/libdroidmedia.a \
    usr/lib64/pkgconfig/droidmedia.pc; do
    if test ! -f "$target_root/$required" \
            || ! cmp -s "$source_root/$required" "$target_root/$required"; then
        droidmedia_ready=0
    fi
done

if test "$droidmedia_ready" -ne 1; then
    if test "$apply" -ne 1; then
        printf 'sailfish_50_sdk=blocked|target=%s|reason=droidmedia-devel-not-provisioned|apply=--apply\n' \
            "$target"
        exit 2
    fi
    install -d -m0755 "$target_root/usr/include/droidmedia" \
        "$target_root/usr/lib64/pkgconfig"
    cp -a "$source_root/usr/include/droidmedia/." \
        "$target_root/usr/include/droidmedia/"
    install -m0644 "$source_root/usr/lib64/libdroidmedia.a" \
        "$target_root/usr/lib64/libdroidmedia.a"
    install -m0644 "$source_root/usr/lib64/pkgconfig/droidmedia.pc" \
        "$target_root/usr/lib64/pkgconfig/droidmedia.pc"
    chown -R builder:builder "$target_root/usr/include/droidmedia"
    chown builder:builder "$target_root/usr/lib64/libdroidmedia.a" \
        "$target_root/usr/lib64/pkgconfig/droidmedia.pc"
fi

qt_version=$("$sdk" -u builder -m all /usr/bin/sb2 -t "$target" \
    /usr/lib64/qt5/bin/qmake -query QT_VERSION 2>/dev/null | tail -1)
test "$qt_version" = 5.6.3 || fail "unexpected-qt-version:$qt_version"
droidmedia_version=$(PKG_CONFIG_SYSROOT_DIR="$target_root" \
    PKG_CONFIG_LIBDIR="$target_root/usr/lib64/pkgconfig" \
    /usr/bin/pkg-config --modversion droidmedia)
test "$droidmedia_version" = 0.20260522.0 \
    || fail "unexpected-droidmedia-version:$droidmedia_version"

printf 'sailfish_50_sdk=ready|target=%s|tooling=%s|qt=%s|droidmedia=%s|source=%s|lib_sha256=%s\n' \
    "$target" "$tooling" "$qt_version" "$droidmedia_version" "$source_target" \
    1211d77ee11dbdfcf412ccd014d821c8be43b15196b8c22d7e3990ccad984f6d
