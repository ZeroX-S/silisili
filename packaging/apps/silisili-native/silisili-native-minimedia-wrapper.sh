#!/bin/sh
set -eu

shim=/usr/libexec/droid-hybris/system/lib/libsilisili-minimedia-audiosource-shim.so
binary=
for candidate in \
    /system/bin/minimediaservice \
    /usr/libexec/droid-hybris/system/bin/minimediaservice
do
    if test -x "$candidate"; then
        binary=$candidate
        break
    fi
done
test -n "$binary"

# A normally running adaptation service is preferable to this compatibility
# unit. Remain as a lightweight monitor so systemd does not start a duplicate.
existing="$(pgrep -f '(/system/bin|/usr/libexec/droid-hybris/system/bin)/minimediaservice' \
    | head -1 || true)"
if test -n "$existing"; then
    while kill -0 "$existing" 2>/dev/null; do sleep 30; done
    exit 0
fi

probe_log=/run/silisili-native-minimedia-probe.log
rm -f "$probe_log"
TREBLE_TESTING_OVERRIDE=true "$binary" 2>"$probe_log" &
probe_pid=$!
sleep 1
if kill -0 "$probe_pid" 2>/dev/null; then
    wait "$probe_pid"
    exit $?
fi
set +e
wait "$probe_pid"
probe_status=$?
set -e

missing_symbol=_ZN7android11AudioSource14setReadAudioCbEPFvPvES1_
if test -f "$shim" && file "$binary" | grep -Fq 'ELF 32-bit' \
        && grep -Fq "$missing_symbol" "$probe_log"; then
    echo "silisili minimedia: applying scoped Android 9 AudioSource ABI shim" >&2
    exec env LD_PRELOAD="$shim" TREBLE_TESTING_OVERRIDE=true "$binary"
fi

cat "$probe_log" >&2 || true
exit "$probe_status"
