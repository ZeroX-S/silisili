#!/bin/sh
set -eu

runtime=/run/user/100000
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -z "$(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true)"
rm -f /tmp/silisili-native-defaultuser.lock
mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance /usr/bin/silisili-native \
    >/tmp/silisili-native-normal-launch.log 2>&1

attempt=0
pid=
while test "$attempt" -lt 80; do
    set -- $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true)
    if test "$#" -eq 1; then
        pid=$1
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$pid"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
printf 'silisili_normal_launch=ready|package=%s|pid=%s|starttime=%s|test_env=absent|rpm_verify=clean|visual_model=unused\n' \
    "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" \
    "$pid" "$(awk '{print $22}' "/proc/$pid/stat")"
