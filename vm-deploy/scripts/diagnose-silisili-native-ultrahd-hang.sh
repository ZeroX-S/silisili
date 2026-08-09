#!/bin/sh
set -eu

printf 'ultrahd_diagnostic_stage=target\n'
ssu status 2>/dev/null || true
uname -a
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
    silisili-native-devel 2>/dev/null || true
printf 'lipstick_processes=%s\n' "$(pgrep -x lipstick 2>/dev/null | paste -sd, -)"

application_pids() {
    for process in /proc/[0-9]*; do
        executable=$(readlink "$process/exe" 2>/dev/null || true)
        case "$executable" in
            /usr/bin/silisili-native|"/usr/bin/silisili-native (deleted)")
                basename "$process"
                ;;
        esac
    done
}

set -- $(application_pids)
printf 'native_process_count=%s\n' "$#"
test "$#" -eq 1 || exit 0
pid=$1
printf 'native_pid=%s\n' "$pid"
printf 'native_starttime=%s\n' "$(awk '{print $22}' "/proc/$pid/stat")"
awk '/^(Name|State|Threads|VmPeak|VmSize|VmRSS|VmData|VmStk|VmExe|VmLib|voluntary_ctxt_switches|nonvoluntary_ctxt_switches):/ { print }' \
    "/proc/$pid/status"

topmost=$(runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
    gdbus call --session --dest org.nemomobile.lipstick --object-path / \
        --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
printf 'native_topmost_pid=%s\n' "${topmost:-unknown}"

printf 'ultrahd_diagnostic_stage=threads\n'
for task in /proc/"$pid"/task/*; do
    tid=${task##*/}
    name=$(cat "$task/comm" 2>/dev/null || true)
    wait_channel=$(cat "$task/wchan" 2>/dev/null || true)
    case "$name" in
        silisili-native|DroidDemux*|DroidPresent*|mpv/*|ao/*|vo/*)
            printf 'thread=%s|name=%s|wchan=%s\n' "$tid" "$name" "$wait_channel"
            ;;
    esac
done

printf 'ultrahd_diagnostic_stage=memory\n'
awk '/^(MemTotal|MemAvailable|SwapTotal|SwapFree|CmaTotal|CmaFree):/ { print }' /proc/meminfo

printf 'ultrahd_diagnostic_stage=journal\n'
events=$(journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true)
printf '%s\n' "$events" | grep -E \
    'native (resolver|player: (media load requested|load command submitted|file loaded|decoder state|video geometry|source frame rate|first frame|quality|state)|hardware video: (direct pipeline requested|OMX decoder started|direct pipeline failed|decoder EOS)|software video:|detail perf)|playurl' \
    | grep -Ev 'frame checkpoint|frame floor window|presentation swap cadence' \
    | tail -180 || true

printf 'ultrahd_diagnostic_stage=journal_cadence\n'
printf '%s\n' "$events" | grep -E \
    'native (app: build identity|resolver|player|hardware video|software video|detail perf|network)|playurl|quality|video-(params|codec)|cache|buffer|EGL|GL_|FBO|failed|error|timeout|ANOM_ABEND|Segmentation fault|Killed process|Out of memory' \
    | tail -80 || true

printf 'ultrahd_diagnostic_stage=journal_compact\n'
printf '%s\n' "$events" | grep -Ev \
    'shared-texture frame checkpoint|frame floor window|presentation swap cadence|display frame|frameSerial|sharedTextureFrame' \
    | tail -240 || true

printf 'ultrahd_diagnostic_stage=kernel\n'
dmesg 2>/dev/null | grep -Ei \
    'lowmemory|out of memory|killed process|kgsl|adreno|ion|gralloc|droidmedia|omx|fatal' \
    | tail -100 || true
binder_pending=$(dmesg 2>/dev/null | grep -c \
    "binder: $pid has pending async transaction" || true)
printf 'binder_pending_async_count=%s\n' "$binder_pending"

printf 'ultrahd_diagnostic=ready|pid=%s|topmost=%s|read_only=1|visual_model=unused\n' \
    "$pid" "${topmost:-unknown}"
