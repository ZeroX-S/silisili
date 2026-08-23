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

lockdir=/run/silisili-native-minimedia.lock
lockpid="$lockdir/pid"

acquire_lock() {
    while true; do
        if mkdir "$lockdir" 2>/dev/null; then
            printf '%s\n' "$$" >"$lockpid"
            return 0
        fi
        if test -f "$lockpid"; then
            holder="$(sed -n '1p' "$lockpid" 2>/dev/null || true)"
            if test -n "$holder" && ! kill -0 "$holder" 2>/dev/null; then
                rm -rf "$lockdir"
                continue
            fi
        fi
        return 1
    done
}

cleanup_lock() {
    rm -rf "$lockdir"
}

if ! acquire_lock; then
    echo "silisili minimedia: startup already in progress; wrapper exits" >&2
    exit 0
fi
trap cleanup_lock EXIT HUP INT TERM

# A normally running adaptation service is preferable to this compatibility
# unit. Remain as a lightweight monitor so systemd does not start a duplicate.
for _ in 1 2 3 4 5; do
    existing="$(pgrep -f '(/system/bin|/usr/libexec/droid-hybris/system/bin)/minimediaservice' \
        | head -1 || true)"
    if test -n "$existing"; then
        echo "silisili minimedia: existing service already running; wrapper exits" >&2
        exit 0
    fi
    sleep 1
done

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
