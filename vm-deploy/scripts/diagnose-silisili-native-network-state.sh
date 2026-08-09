#!/bin/sh
set -eu

printf 'network_state_begin\n'
ip -o link show 2>/dev/null || true
ip -o -4 address show 2>/dev/null || true
ip route show 2>/dev/null || true
if command -v connmanctl >/dev/null 2>&1; then
    connmanctl technologies 2>/dev/null || true
    connmanctl services 2>/dev/null || true
fi
for process in /proc/[0-9]*; do
    executable=$(readlink "$process/exe" 2>/dev/null || true)
    case "$executable" in
        /usr/bin/silisili-native)
            printf 'silisili_process=%s|state=%s|starttime=%s\n' \
                "$(basename "$process")" \
                "$(awk '{print $3}' "$process/stat")" \
                "$(awk '{print $22}' "$process/stat")"
            ;;
    esac
done
if test -x /tmp/bonito-direct-touch; then
    set +e
    /tmp/bonito-direct-touch swipe 540 1700 540 500 280 12
    touch_status=$?
    set -e
    printf 'direct_touch_swipe_status=%s\n' "$touch_status"
fi
printf 'network_state_end\n'
