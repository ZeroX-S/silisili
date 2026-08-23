#!/bin/sh
set -eu

expected_package=${SILISILI_IDLE_COLD_EXPECTED_PACKAGE:-silisili-native-devel-1.1.0-1.56.aarch64}
run_id=${SILISILI_IDLE_COLD_RUN_ID:-"idle-cold-$(date +%Y%m%d-%H%M%S)"}
upload_url=${SILISILI_IDLE_COLD_UPLOAD_URL:-http://192.168.2.20:18103}
upload_name=${SILISILI_IDLE_COLD_NAME:-silisili-cover-idle-cold.png}
runtime=/run/user/100000

application_pids() {
    pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true
}

top_pid() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR="$runtime" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
            --method org.nemomobile.compositor.privateTopmostWindowProcessId \
        2>/dev/null | grep -oE '[0-9]+' | tail -1
}

for process_id in $(application_pids); do
    kill -TERM "$process_id" 2>/dev/null || true
done
attempt=0
while test "$attempt" -lt 20 && test -n "$(application_pids)"; do
    sleep 0.25
    attempt=$((attempt + 1))
done
for process_id in $(application_pids); do
    kill -KILL "$process_id" 2>/dev/null || true
done
rm -f /tmp/silisili-native-defaultuser.lock

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" = "$expected_package"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
test -x /tmp/bonito-direct-touch
test -x /tmp/bonito-uinput-camera-key

mcetool --unblank-screen >/dev/null 2>&1 || true
mcetool --set-tklock-mode=unlocked >/dev/null 2>&1 || true
mcetool --set-never-blank=enabled >/dev/null 2>&1 || true

runuser -u defaultuser -- env \
    HOME=/home/defaultuser \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    WAYLAND_DISPLAY=../../display/wayland-0 \
    QT_QPA_PLATFORM=wayland \
    SILISILI_NATIVE_FORCE_ORIENTATION=portrait \
    /usr/bin/invoker --verbose --verbose --no-wait --type=silica-qt5 \
        --id=cn.silisili.native --single-instance /usr/bin/silisili-native \
    >"/tmp/silisili-native-$run_id.log" 2>&1

pid=
attempt=0
while test "$attempt" -lt 80; do
    set -- $(application_pids)
    if test "$#" -eq 1; then
        pid=$1
        break
    fi
    sleep 0.25
    attempt=$((attempt + 1))
done
test -n "$pid"
starttime=$(awk '{print $22}' "/proc/$pid/stat")

attempt=0
while test "$attempt" -lt 80; do
    test "$(top_pid || true)" = "$pid" && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80
sleep 1
/tmp/bonito-direct-touch swipe 3 1080 900 1080 500 25
attempt=0
while test "$attempt" -lt 80; do
    test "$(top_pid || true)" != "$pid" && break
    sleep 0.25
    attempt=$((attempt + 1))
done
test "$attempt" -lt 80

events=$(journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true)
printf '%s\n' "$events" | grep -F \
    'native cover: idle action icons cleared actions 0' \
    | grep -F 'pauseEmpty true' \
    | grep -F 'presentationEmpty true' \
    | grep -F 'closeEmpty true' >/dev/null

started=$(date +%s)
/tmp/bonito-uinput-camera-key screenshot
sleep 2
shot=$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1)
test -n "$shot"
test "$(stat -c %Y "$shot")" -ge "$started"
test "$(head -c 8 "$shot" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a
curl -fsS -X PUT --data-binary @"$shot" "$upload_url/$upload_name" >/dev/null

test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"
mcetool --set-never-blank=disabled >/dev/null 2>&1 || true
printf 'native_idle_cover_cold=ready|run=%s|package=%s|pid=%s|starttime=%s|actions=0|background=physical-gesture|name=%s|bytes=%s|sha256=%s|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$starttime" "$upload_name" \
    "$(wc -c <"$shot")" "$(sha256sum "$shot" | awk '{print $1}')"
