#!/bin/sh
set -eu

# Read-only baseline for Sailfish deployment and regression transactions.

run_id=${1:-manual}
rpm_path=${2:-/tmp/silisili-native-devel-1.1.0-1.56.aarch64.rpm}

run_bounded() {
    limit=$1
    shift
    "$@" &
    command_pid=$!
    (
        sleep "$limit"
        kill -TERM "$command_pid" 2>/dev/null || exit 0
        sleep 1
        kill -KILL "$command_pid" 2>/dev/null || true
    ) &
    watchdog_pid=$!
    if wait "$command_pid"; then
        command_rc=0
    else
        command_rc=$?
    fi
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    return "$command_rc"
}

printf 'device_preflight_begin=ready|run=%s\n' "$run_id"
printf 'device_os='; tr '\n' ' ' </etc/os-release; printf '\n'
printf 'device_kernel=%s\n' "$(uname -a)"
printf 'device_ssu='; run_bounded 8 ssu status 2>&1 | tr '\n' ' ' || true; printf '\n'
printf 'device_packages='; rpm -q silisili-native-devel silisili-sailfish 2>&1 | tr '\n' ','; printf '\n'
printf 'device_package_verify='; run_bounded 30 rpm -V silisili-native-devel 2>&1 | tr '\n' ',' || true; printf '\n'
printf 'device_app_processes='; pgrep -af '^/usr/bin/silisili-native' 2>/dev/null | tr '\n' ',' || true; printf '\n'
printf 'device_compositor='; pgrep -af lipstick 2>/dev/null | tr '\n' ',' || true; printf '\n'
top_pid=$(run_bounded 8 runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR=/run/user/100000 \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
        --method org.nemomobile.compositor.privateTopmostWindowProcessId \
    2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
printf 'device_topmost_pid=%s\n' "${top_pid:-unknown}"
if test -x /tmp/bonito-direct-touch; then
    printf 'device_touch_injector=ready|path=/tmp/bonito-direct-touch\n'
else
    printf 'device_touch_injector=absent|path=/tmp/bonito-direct-touch\n'
fi
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
if test -f "$settings"; then
    mode=$(sed -n 's/^backgroundPresentationMode=//p' "$settings" | tail -1)
    content_columns=$(sed -n 's/^contentColumns=//p' "$settings" | tail -1)
    font_size_mode=$(sed -n 's/^fontSizeMode=//p' "$settings" | tail -1)
    printf 'device_settings=ready|path=%s|background_mode=%s|content_columns=%s|font_size_mode=%s\n' \
        "$settings" "${mode:-unset}" "${content_columns:-unset}" \
        "${font_size_mode:-unset}"
else
    printf 'device_settings=absent|path=%s\n' "$settings"
fi
printf 'device_disk_tmp='; df -Pk /tmp | tail -1 | tr -s ' '; printf '\n'
printf 'device_disk_home='; df -Pk /home | tail -1 | tr -s ' '; printf '\n'
if test -f "$rpm_path"; then
    printf 'device_candidate_rpm=present|path=%s|bytes=%s|sha256=%s|nevra=%s\n' \
        "$rpm_path" \
        "$(wc -c <"$rpm_path" | tr -d ' ')" \
        "$(sha256sum "$rpm_path" | awk '{print $1}')" \
        "$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path" 2>&1)"
else
    printf 'device_candidate_rpm=absent|path=%s\n' "$rpm_path"
fi
printf 'device_preflight=ready|run=%s|checks=13/13\n' "$run_id"
