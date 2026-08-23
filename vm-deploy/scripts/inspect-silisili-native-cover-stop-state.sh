#!/bin/sh
set -eu

runtime=/run/user/100000
pid=$(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true)
set -- $pid
test "$#" -eq 1
pid=$1

top_pid=$(runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    gdbus call --session --dest org.nemomobile.lipstick --object-path / \
        --method org.nemomobile.compositor.privateTopmostWindowProcessId \
    2>/dev/null | grep -oE '[0-9]+' | tail -1 || true)
display_state=$(mcetool -q 2>/dev/null \
    | sed -n 's/^[[:space:]]*Display state:[[:space:]]*//p' | head -1)
lock_state=$(mcetool -q 2>/dev/null \
    | sed -n 's/^[[:space:]]*Touchscreen lock mode:[[:space:]]*//p' | head -1)

printf 'native_cover_stop_state=ready|package=%s|pid=%s|starttime=%s|top_pid=%s|display=%s|lock=%s|rpm_verify=%s|visual_model=unused\n' \
    "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" \
    "$pid" "$(awk '{print $22}' "/proc/$pid/stat")" "${top_pid:-none}" \
    "${display_state:-unknown}" "${lock_state:-unknown}" \
    "$(test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)" && printf clean || printf changed)"
journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null \
    | grep -E 'native cover: (stop action handled|eligibility changed|presentation state ready|idle action icons cleared|active layout ready)|QML|TypeError|ReferenceError|Binding loop|Cannot assign|Cannot override|Unable to assign' \
    | tail -40 || true
