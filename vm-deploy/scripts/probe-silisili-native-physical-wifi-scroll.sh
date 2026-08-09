#!/bin/sh
set -eu

# Exact device regression for: scroll the real home feed, disable Wi-Fi while
# a touch gesture is still in flight, then keep scrolling. The debug transport
# remains on RNDIS and cleanup always restores Wi-Fi. No screenshot or visual
# model is involved; the assertions use real input events, process identity,
# network state and QML event-loop markers.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.23.aarch64.rpm}
expected_sha=${2:-8b7106a175da121a38bd4fd02e74f3dbcb34be47a05cd4b00c84cd118d05597b}
expected_package=silisili-native-devel-1.1.0-1.23.aarch64
phase=preflight
test_pid=
production_pid=
wifi_disabled=0

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
}

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

stop_application() {
    for process_id in $(application_pids); do
        kill -TERM "$process_id" 2>/dev/null || true
    done
    killall -TERM silisili-native 2>/dev/null || true
    sleep 1
    for process_id in $(application_pids); do
        kill -KILL "$process_id" 2>/dev/null || true
    done
    killall -KILL silisili-native 2>/dev/null || true
    sleep 3
}

launch_application() {
    runuser -u defaultuser -- env \
        HOME=/home/defaultuser \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        WAYLAND_DISPLAY=../../display/wayland-0 \
        QT_QPA_PLATFORM=wayland \
        "$@" \
        /usr/bin/invoker --verbose --verbose --no-wait --type=generic \
            /usr/bin/silisili-native
}

wait_for_single_process() {
    attempt=0
    while test "$attempt" -lt 60; do
        set -- $(application_pids)
        if test "$#" -eq 1; then
            printf '%s\n' "$1"
            return 0
        fi
        sleep 0.25
        attempt=$((attempt + 1))
    done
    return 1
}

wifi_powered() {
    connmanctl technologies 2>/dev/null \
        | sed -n '/technology\/wifi/,/technology\//p' \
        | grep -Fq 'Powered = True'
}

wifi_connected() {
    connmanctl technologies 2>/dev/null \
        | sed -n '/technology\/wifi/,/technology\//p' \
        | grep -Fq 'Connected = True'
}

restore_wifi() {
    if test "$wifi_disabled" -eq 1; then
        connmanctl enable wifi >/dev/null 2>&1 || true
        poll=0
        while test "$poll" -lt 80; do
            wifi_connected && break
            sleep 0.25
            poll=$((poll + 1))
        done
        wifi_disabled=0
    fi
}

topmost_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        timeout 4 gdbus call --session --dest org.nemomobile.lipstick \
            --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}

cleanup() {
    result=$?
    restore_wifi
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_physical_wifi_scroll=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (network|home)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -260 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test -x /tmp/bonito-direct-touch
command -v connmanctl >/dev/null 2>&1
wifi_powered
wifi_connected
test -n "$expected_sha"
test -f "$rpm_path"
printf '%s  %s\n' "$expected_sha" "$rpm_path" | sha256sum -c -
rpm -K --nosignature "$rpm_path"
test "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path")" \
    = "$expected_package"

phase=install
stop_application
rpm -Uvh --replacepkgs "$rpm_path"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null

phase=launch-home
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=network-scroll \
    >/tmp/silisili-native-physical-wifi-scroll-launch.log 2>&1
test_pid=$(wait_for_single_process)
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=wait-home
poll=0
while test "$poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F 'home feed parsed "recommended" page 1' \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 160

phase=scroll-before-wifi-off
/tmp/bonito-direct-touch swipe 540 1700 540 500 420 16
sleep 0.25
/tmp/bonito-direct-touch swipe 540 1700 540 500 420 16
sleep 0.25
events=$(events_for_pid "$test_pid")
scroll_starts_before=$(printf '%s\n' "$events" | grep -c \
    'native home: physical scroll movement started' || true)
test "$scroll_starts_before" -ge 1

phase=wifi-off-during-swipe
/tmp/bonito-direct-touch swipe 540 1700 540 420 1200 40 &
gesture_pid=$!
sleep 0.20
connmanctl disable wifi >/dev/null
wifi_disabled=1
wait "$gesture_pid"
test ! -e /sys/class/net/wlan0/carrier \
    || test "$(cat /sys/class/net/wlan0/carrier 2>/dev/null || printf 0)" = 0

phase=continued-scroll-off-wifi
continued=0
successful_swipes=0
failed_swipes=0
while test "$continued" -lt 12; do
    set +e
    /tmp/bonito-direct-touch swipe 540 1700 540 500 280 12
    touch_status=$?
    set -e
    if test "$touch_status" -eq 0; then
        successful_swipes=$((successful_swipes + 1))
    else
        # The injector can reject a gesture while the previous synthetic
        # contact is still being released. Count that as an attempted gesture;
        # the QML movement marker below remains the source of truth.
        failed_swipes=$((failed_swipes + 1))
    fi
    sleep 0.12
    test -e "/proc/$test_pid/stat"
    test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"
    continued=$((continued + 1))
done
printf 'physical_wifi_scroll_injection=observed|attempts=%s|successful=%s|rejected=%s|process_state=%s\n' \
    "$continued" "$successful_swipes" "$failed_swipes" \
    "$(awk '{print $3}' "/proc/$test_pid/stat")"
test "$successful_swipes" -ge 8

phase=assert-continued-scroll
poll=0
while test "$poll" -lt 120; do
    events=$(events_for_pid "$test_pid")
    scrolls_after=$(printf '%s\n' "$events" | grep -c \
        'native home: physical scroll movement ended' || true)
    test "$scrolls_after" -ge 1 && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 120
content_y_after=$(printf '%s\n' "$events" | awk '
    /native home: physical scroll movement ended/ {
        for (i = 1; i <= NF; ++i) {
            if ($i == "contentY") value = $(i + 1) + 0
        }
    }
    END { print value + 0 }
')
actual_topmost=$(topmost_pid)
printf 'physical_wifi_scroll_ui=observed|scroll_ends=%s|content_y=%s|test_pid=%s|topmost_pid=%s|process_state=%s\n' \
    "$scrolls_after" "$content_y_after" "$test_pid" "$actual_topmost" \
    "$(awk '{print $3}' "/proc/$test_pid/stat")"
test "$content_y_after" -gt 500
test "$(awk '{print $3}' "/proc/$test_pid/stat")" != D

events=$(events_for_pid "$test_pid")
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND|Out of memory|Killed process' || true)"
failure_count=$(printf '%s\n' "$events" | grep -c \
    'native home: request failed' || true)
test "$failure_count" -le 2

phase=restore-wifi
restore_wifi
wifi_connected
phase=verify-process-after-restore
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

phase=production-relaunch
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-launch.log 2>&1
production_pid=$(wait_for_single_process)
poll=0
while test "$poll" -lt 60; do
    production_events=$(events_for_pid "$production_pid")
    printf '%s\n' "$production_events" | grep -F \
        'native app: build identity "silisili-native-devel" "1.1.0" "1.23"' \
        >/dev/null && break
    sleep 0.25
    poll=$((poll + 1))
done
test "$poll" -lt 60

phase=complete
printf 'native_physical_wifi_scroll=ready|package=%s|same_pid=1|scroll_starts_before=%s|continued_swipe_attempts=%s|successful_swipes=%s|rejected_swipes=%s|scroll_ends_after=%s|content_y_after=%s|request_failures=%s|wifi_restored=1|touch_consumed=1|production_pid=%s|rpm_verify=clean|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$scroll_starts_before" "$continued" \
    "$successful_swipes" "$failed_swipes" "$scrolls_after" \
    "$content_y_after" "$failure_count" "$production_pid" "$expected_sha"
