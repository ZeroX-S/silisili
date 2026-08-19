#!/bin/sh
set -eu

if test "$#" -ne 3; then
    echo 'usage: restore-silisili-native-known-good.sh RPM SHA256 NEVRA' >&2
    exit 64
fi

rpm_path=$1
expected_sha=$2
expected_nevra=$3
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf

test -f "$rpm_path"
printf '%s  %s\n' "$expected_sha" "$rpm_path" | sha256sum -c -
test "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path")" \
    = "$expected_nevra"

for pid in $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true); do
    kill -TERM "$pid" 2>/dev/null || true
done
sleep 2
for pid in $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true); do
    kill -KILL "$pid" 2>/dev/null || true
done
rm -f /tmp/silisili-native-defaultuser.lock

rpm -Uvh --oldpackage --replacepkgs "$rpm_path"
test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_nevra"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

if test -f "$settings"; then
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i 's/^backgroundPresentationMode=.*/backgroundPresentationMode=cover/' "$settings"
    else
        printf 'backgroundPresentationMode=cover\n' >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
fi
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true

printf 'native_known_good_restore=ready|package=%s|processes_after=%s|mode=cover|rpm_verify=clean|sha256=%s\n' \
    "$expected_nevra" \
    "$(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null | wc -l)" \
    "$expected_sha"
