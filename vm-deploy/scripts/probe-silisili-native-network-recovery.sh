#!/bin/sh
set -eu

# Run on the phone through the bounded debug-shell transport. The test injects
# one obsolete pagination connection inside the dedicated network-recovery
# page, then models 64 rapid scroll-triggered loadMore calls while the error is
# retained. It does not disable Wi-Fi, mobile data, RNDIS, Lipstick or the
# display compositor.

rpm_path=${1:-/tmp/silisili-native-devel-1.1.0-1.45.aarch64.rpm}
expected_sha=${2:-3ad7163a959f79a30de49cd6c3b5eb3205c6b402a6cd98ac690d940d7fa604f6}
expected_package=silisili-native-devel-1.1.0-1.45.aarch64
phase=preflight
test_pid=
production_pid=

events_for_pid() {
    journalctl -b "_PID=$1" --no-pager -o cat 2>/dev/null || true
}

application_pids() {
    for process in /proc/[0-9]*; do
        command=$(tr '\000' ' ' <"$process/cmdline" 2>/dev/null || true)
        case "$command" in
            /usr/bin/silisili-native*)
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
    sleep 4
}

launch_application() {
    runuser -u defaultuser -- env \
        HOME=/home/defaultuser \
        XDG_RUNTIME_DIR=/run/user/100000 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        WAYLAND_DISPLAY=../../display/wayland-0 \
        QT_QPA_PLATFORM=wayland \
        "$@" \
        /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
            --id=cn.silisili.native --single-instance \
            /usr/bin/silisili-native
}

cleanup() {
    result=$?
    mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
    if test "$result" -ne 0; then
        printf 'native_network_recovery=failed|phase=%s|test_pid=%s|production_pid=%s|visual_model=unused\n' \
            "$phase" "${test_pid:-none}" "${production_pid:-none}"
        test -z "${test_pid:-}" || events_for_pid "$test_pid" | grep -E \
            'native (network|home)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -240 || true
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

test -n "$expected_sha"
test -f "$rpm_path"
printf '%s  %s\n' "$expected_sha" "$rpm_path" | sha256sum -c -
rpm -K --nosignature "$rpm_path"
test "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path")" \
    = "$expected_package"
if rpm -q silisili-sailfish >/dev/null 2>&1; then
    stable_before=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
        silisili-sailfish)
else
    stable_before=not-installed
fi

phase=install
stop_application
# Development rebuilds intentionally keep the same RPM release while their
# payload changes. Always replace the package after validating the RPM hash;
# comparing only NEVRA can otherwise leave the previous binary installed and
# turn this regression into a false result.
rpm -Uvh --replacepkgs "$rpm_path"
phase=verify-package
test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package"
phase=verify-rpm
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
phase=verify-stable
if rpm -q silisili-sailfish >/dev/null 2>&1; then
    stable_after=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
        silisili-sailfish)
else
    stable_after=not-installed
fi
test "$stable_after" = "$stable_before"

phase=test-launch
mcetool --unblank-screen >/dev/null
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --set-never-blank=enabled >/dev/null
rm -f /tmp/silisili-native-defaultuser.lock
launch_application \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    SILISILI_NATIVE_TEST_PAGE=network-recovery \
    SILISILI_NATIVE_TEST_NETWORK_CHANGE_MS=40 \
    SILISILI_NATIVE_TEST_NETWORK_CHANGE_URL_CONTAINS='fresh_idx=2' \
    >/tmp/silisili-native-network-recovery-launch.log 2>&1

attempt=0
while test "$attempt" -lt 40; do
    set -- $(application_pids)
    if test "$#" -eq 1; then
        test_pid=$1
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$test_pid"
test_starttime=$(awk '{print $22}' "/proc/$test_pid/stat")

phase=pagination-request-release
abort_poll=0
while test "$abort_poll" -lt 30; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F \
        'native network: reply aborted for connectivity change reason "test-transition"' \
        >/dev/null && break
    sleep 0.1
    abort_poll=$((abort_poll + 1))
done
test "$abort_poll" -lt 30

phase=same-process-recovery
recovery_poll=0
while test "$recovery_poll" -lt 160; do
    events=$(events_for_pid "$test_pid")
    printf '%s\n' "$events" | grep -F 'native network recovery: ready loading false' \
        >/dev/null && break
    sleep 0.25
    recovery_poll=$((recovery_poll + 1))
done
test "$recovery_poll" -lt 160
test -e "/proc/$test_pid/stat"
test "$(awk '{print $22}' "/proc/$test_pid/stat")" = "$test_starttime"

events=$(events_for_pid "$test_pid")
printf '%s\n' "$events" | grep -Fq 'native network: test connectivity transition scheduled 40 ms'
printf '%s\n' "$events" | grep -Fq 'urlContains "fresh_idx=2"'
printf '%s\n' "$events" | grep -Fq 'native network recovery: initial page ready'
printf '%s\n' "$events" | grep -Fq 'native network recovery: pagination requested'
printf '%s\n' "$events" | grep -Fq 'native home: request failed serial 2 timeout false networkChanged true'
printf '%s\n' "$events" | grep -Fq 'native network recovery: continued scroll survived attempts 64 loading false errorRetained true'
printf '%s\n' "$events" | grep -Fq 'native network recovery: retry requested'
printf '%s\n' "$events" | grep -Fq 'home feed parsed "recommended" page 1'
printf '%s\n' "$events" | grep -Fq 'native network recovery: ready loading false'
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)"

phase=production-relaunch
stop_application
rm -f /tmp/silisili-native-defaultuser.lock
launch_application >/tmp/silisili-native-production-launch.log 2>&1
attempt=0
while test "$attempt" -lt 60; do
    set -- $(application_pids)
    if test "$#" -eq 1; then
        production_pid=$1
        grep -Fq '/usr/bin/silisili-native' "/proc/$production_pid/maps" \
            2>/dev/null && break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 60
test -e "/proc/$production_pid/stat"
rm -f "$rpm_path"

phase=complete
printf 'native_network_recovery=ready|package=%s|abort_polls=%s|recovery_polls=%s|same_pid=1|continued_scroll_attempts=64|offline_request_storm=0|fresh_request=ready|production_pid=%s|rpm_verify=clean|stable=%s|sha256=%s|visual_model=unused\n' \
    "$expected_package" "$abort_poll" "$recovery_poll" "$production_pid" \
    "$stable_before" "$expected_sha"
