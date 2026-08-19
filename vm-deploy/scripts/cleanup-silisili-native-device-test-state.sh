#!/bin/sh
set -eu

settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf

for pid in $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true); do
    kill -TERM "$pid" 2>/dev/null || true
done
sleep 2
for pid in $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true); do
    kill -KILL "$pid" 2>/dev/null || true
done
rm -f /tmp/silisili-native-defaultuser.lock
if test -f "$settings"; then
    if grep -q '^backgroundPresentationMode=' "$settings"; then
        sed -i 's/^backgroundPresentationMode=.*/backgroundPresentationMode=cover/' "$settings"
    else
        printf 'backgroundPresentationMode=cover\n' >>"$settings"
    fi
    chown defaultuser:defaultuser "$settings" 2>/dev/null || true
fi
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
printf 'device_test_cleanup=ready|processes_after=%s|mode=cover|never_blank=disabled\n' \
    "$(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null | wc -l)"
