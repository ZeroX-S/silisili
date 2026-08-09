#!/usr/bin/env bash
set -euo pipefail

PACKAGE=silisili-sailfish
EXPECTED_VERSION="${EXPECTED_VERSION:-1.0.0-7}"
APP_USER=defaultuser
APP_UID="$(id -u "$APP_USER")"
APP_RUNTIME_DIR="/run/user/$APP_UID"
APP_SESSION_BUS="unix:path=$APP_RUNTIME_DIR/dbus/user_bus_socket"
LAUNCHER=/usr/bin/silisili
REAL_APP=/usr/lib64/silisili/silisili.real
LIBDIR=/usr/lib64/silisili
DESKTOP=/usr/share/applications/cn.silisili.app.desktop
ICON_KEY=silisili-sailfish
LEGACY_CONFIG_DIR="/home/$APP_USER/.config/wiliwili"
CONFIG_DIR="/home/$APP_USER/.config/silisili"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-10}"
LOG_WAIT_SECONDS="${LOG_WAIT_SECONDS:-30}"
EVIDENCE="${EVIDENCE:-/var/lib/bonito-debug-evidence/silisili-$(date +%Y%m%d-%H%M%S)}"
app_pid=
step=initialization

fail() {
    echo "SILISILI_RUNTIME_FAIL[$step]: $*" >&2
    exit 1
}

pass() {
    echo "AUTO_PASS: $*"
}

manual() {
    echo "MANUAL_REQUIRED: $*"
}

find_app_pids() {
    local proc pid target uid

    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        target="$(readlink -f "$proc/exe" 2>/dev/null || true)"
        test "$target" = "$REAL_APP" || continue
        uid="$(awk '/^Uid:/ { print $2 }' "$proc/status" 2>/dev/null || true)"
        test "$uid" = "$APP_UID" || continue
        printf '%s\n' "$pid"
    done
}

stop_app() {
    local pid count

    for pid in $(find_app_pids); do
        kill -TERM "$pid" 2>/dev/null || true
    done
    count=0
    while test "$count" -lt 10 && test -n "$(find_app_pids)"; do
        sleep 1
        count=$((count + 1))
    done
    for pid in $(find_app_pids); do
        kill -KILL "$pid" 2>/dev/null || true
    done
}

read_cpu_ticks() {
    awk '{ print $14 + $15 }' "/proc/$1/stat"
}

read_rss_kb() {
    awk '/^VmRSS:/ { print $2 }' "/proc/$1/status"
}

read_fd_count() {
    # File descriptors can close while find is walking /proc. The count is a
    # runtime sample, so keep the observed output without treating that race as
    # an application failure under pipefail.
    find "/proc/$1/fd" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l || true
}

launch_desktop_path() {
    local log="$1"

    # Reproduce Lipstick's compositor-only environment. The ELF launcher must
    # replace these values before it executes the upstream GLFW application.
    su -s /bin/sh - "$APP_USER" -c \
        "env EGL_PLATFORM=hwcomposer HYBRIS_EGLPLATFORM=hwcomposer QT_QPA_PLATFORM=hwcomposer QT_QPA_FORCE_HWC2=1 '$LAUNCHER' > '$log' 2>&1 &"
}

wait_for_app() {
    local count=0 pid

    while test "$count" -lt 20; do
        pid="$(find_app_pids | tail -1)"
        if test -n "$pid" && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    return 1
}

wait_for_log_line() {
    local log="$1" marker="$2" count=0 line

    while test "$count" -lt "$LOG_WAIT_SECONDS"; do
        line="$(grep -F "$marker" "$log" | tail -1 || true)"
        if test -n "$line"; then
            printf '%s\n' "$line"
            return 0
        fi
        kill -0 "$app_pid" 2>/dev/null || return 1
        sleep 1
        count=$((count + 1))
    done
    return 1
}

display_state() {
    mcetool -N 2>/dev/null | awk -F: '/Display state:/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2
    }'
}

tklock_state() {
    mcetool -N 2>/dev/null | awk -F: '/Touchscreen\/Keypad lock:/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2
    }'
}

never_blank_state() {
    mcetool -N 2>/dev/null | awk -F: '/Display never blank:/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2
    }'
}

wait_state() {
    local command="$1" expected="$2" count=0

    while test "$count" -lt 10; do
        test "$($command)" = "$expected" && return 0
        sleep 1
        count=$((count + 1))
    done
    return 1
}

topmost_window_pid() {
    runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR="$APP_RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$APP_SESSION_BUS" \
        gdbus call --session --dest org.nemomobile.lipstick --object-path / \
        --method org.nemomobile.compositor.privateTopmostWindowProcessId |
        tr -cd '0-9'
}

wait_for_topmost_window() {
    local expected="$1" count=0 current=

    while test "$count" -lt 15; do
        current="$(topmost_window_pid 2>/dev/null || true)"
        if test "$current" = "$expected"; then
            printf '%s\n' "$current"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    printf '%s\n' "$current"
    return 1
}

case "$EVIDENCE" in
    /var/lib/bonito-debug-evidence/*) ;;
    *) fail "evidence path must be below /var/lib/bonito-debug-evidence" ;;
esac

initial_display="$(display_state)"
initial_tklock="$(tklock_state)"
initial_never_blank="$(never_blank_state)"

restore_display() {
    set +e
    mcetool --set-never-blank="$initial_never_blank" >/dev/null 2>&1
    mcetool --set-tklock-mode="$initial_tklock" >/dev/null 2>&1
    if test "$initial_display" = off; then
        mcetool --blank-screen >/dev/null 2>&1
    else
        mcetool --unblank-screen >/dev/null 2>&1
    fi
}

finish() {
    local rc=$?

    trap - EXIT INT TERM
    restore_display
    if test "$rc" -ne 0 && test -d "$EVIDENCE"; then
        printf 'rc=%s\nstep=%s\n' "$rc" "$step" >"$EVIDENCE/FAILED"
    fi
    exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

rm -rf "$EVIDENCE"
install -d -o "$APP_USER" -g users -m0755 "$EVIDENCE"
install -d -o "$APP_USER" -g users -m0755 \
    "$EVIDENCE/static" "$EVIDENCE/launch-1" "$EVIDENCE/launch-2"

step=static-package-and-runtime
test "$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$PACKAGE")" = "$EXPECTED_VERSION" ||
    fail "unexpected installed package version"
rpm -V "$PACKAGE" >"$EVIDENCE/static/rpm-verify.txt" 2>&1 ||
    fail "rpm verification failed"
! rpm -qa | grep -Eq '^wiliwili-sailfish-[0-9]' ||
    fail "superseded wiliwili-sailfish package remains installed"
test ! -e /usr/bin/wiliwili || fail "legacy wiliwili executable remains"
test ! -e /usr/share/applications/cn.xfangfang.wiliwili.desktop ||
    fail "legacy wiliwili desktop entry remains"
/usr/bin/droid/verify-desktop-elf-launchers.sh \
    >"$EVIDENCE/static/desktop-elf.txt" 2>&1 || fail "desktop ELF gate failed"
grep -Fxq "Exec=$LAUNCHER" "$DESKTOP" || fail "desktop Exec target is wrong"
grep -Fxq "Icon=$ICON_KEY" "$DESKTOP" || fail "desktop icon key is wrong"
! grep -Fq 'Icon=cn.xfangfang.wiliwili' "$DESKTOP" || fail "legacy dotted icon key remains"
for size in 86 108 128 172; do
    test -r "/usr/share/icons/hicolor/${size}x${size}/apps/$ICON_KEY.png" ||
        fail "missing Sailfish ${size}px launcher icon"
done
for resource in keymap_xbox.ttf keymap_ps.ttf keymap_keyboard_swap.ttf; do
    test ! -e "/usr/share/silisili/resources/font/$resource" ||
        fail "controller-only resource remains: $resource"
done
test ! -e /usr/share/silisili/resources/gamecontrollerdb.txt ||
    fail "game controller mapping database remains"
for resource in hint_game_1.png hint_game_2.png; do
    test ! -e "/usr/share/silisili/resources/pictures/$resource" ||
        fail "controller-only hint remains: $resource"
done

readelf -h "$LAUNCHER" >"$EVIDENCE/static/launcher-elf.txt"
grep -Fq AArch64 "$EVIDENCE/static/launcher-elf.txt" ||
    fail "launcher is not AArch64 ELF"
grep -Fq 'Position-Independent Executable' "$EVIDENCE/static/launcher-elf.txt" ||
    fail "launcher is not PIE"
strings "$LAUNCHER" >"$EVIDENCE/static/launcher-strings.txt"
grep -Fxq "$REAL_APP" "$EVIDENCE/static/launcher-strings.txt" ||
    fail "launcher has the wrong real application path"
grep -Fxq HYBRIS_EGLPLATFORM "$EVIDENCE/static/launcher-strings.txt" ||
    fail "launcher does not replace the EGL platform"
grep -Fxq wayland "$EVIDENCE/static/launcher-strings.txt" ||
    fail "launcher does not select Wayland"

test "$(stat -c '%a' "$LIBDIR")" = 755 ||
    fail "private runtime directory is not mode 0755"
runuser -u "$APP_USER" -- test -x "$LAUNCHER" ||
    fail "defaultuser cannot execute the launcher"
runuser -u "$APP_USER" -- test -x "$REAL_APP" ||
    fail "defaultuser cannot execute the real application"
runuser -u "$APP_USER" -- test -r "$LIBDIR/libmpv.so.2" ||
    fail "defaultuser cannot read private libmpv"
runuser -u "$APP_USER" -- test -r "$LIBDIR/libcurl.so.4" ||
    fail "defaultuser cannot read private curl"
runuser -u "$APP_USER" -- test -r "$LIBDIR/libavformat.so.59" ||
    fail "defaultuser cannot read private FFmpeg"
test ! -e "$LIBDIR/libstdc++.so.6" || fail "private libstdc++ is packaged"

LD_LIBRARY_PATH="$LIBDIR" ldd "$REAL_APP" >"$EVIDENCE/static/ldd.txt" 2>&1 ||
    fail "ldd failed"
! grep -Eiq 'not found' "$EVIDENCE/static/ldd.txt" ||
    fail "runtime dependency is unresolved"
grep -Eq 'libstdc\+\+\.so\.6 => /usr/lib64/libstdc\+\+\.so\.6' \
    "$EVIDENCE/static/ldd.txt" || fail "Sailfish system libstdc++ is not resolved"
grep -Fq "libcurl.so.4 => $LIBDIR/libcurl.so.4" \
    "$EVIDENCE/static/ldd.txt" || fail "private curl is not resolved"
grep -Fq "libssl.so.3 => $LIBDIR/libssl.so.3" \
    "$EVIDENCE/static/ldd.txt" || fail "private OpenSSL is not resolved"
grep -Fq "libavformat.so.59 => $LIBDIR/libavformat.so.59" \
    "$EVIDENCE/static/ldd.txt" || fail "private FFmpeg is not resolved"

pulse_socket="/run/user/$APP_UID/pulse/native"
test -S "$pulse_socket" || fail "PulseAudio socket is unavailable"
runuser -u "$APP_USER" -- env XDG_RUNTIME_DIR="/run/user/$APP_UID" \
    PULSE_SERVER="unix:$pulse_socket" pactl info \
    >"$EVIDENCE/static/pulse-info.txt" 2>&1 || fail "PulseAudio is unreachable"
pass "package, ELF, ABI, permissions, linkage, and PulseAudio service checks"

step=network
if command -v curl >/dev/null; then
    runuser -u "$APP_USER" -- curl -fsS --max-time 20 \
        https://api.bilibili.com/x/web-interface/nav \
        >"$EVIDENCE/static/bilibili-network.json" 2>"$EVIDENCE/static/bilibili-network.err" ||
        fail "device cannot reach the Bilibili HTTPS API"
    grep -Eq '"code"[[:space:]]*:[[:space:]]*(-101|0)' \
        "$EVIDENCE/static/bilibili-network.json" ||
        fail "Bilibili API returned an unexpected response"
    pass "device network and TLS reached the Bilibili API"
else
    manual "system curl is unavailable; confirm homepage network loading"
fi

step=display-preparation
mcetool --set-never-blank=enabled >/dev/null
mcetool --unblank-screen >/dev/null
wait_state display_state on || fail "display did not reach on state"
mcetool --set-tklock-mode=unlocked >/dev/null
wait_state tklock_state unlocked || fail "touchscreen/keypad lock did not unlock"

step=cold-launch
stop_app
start="$(date '+%F %T')"
launch_start="$(date +%s)"
launch_desktop_path "$EVIDENCE/launch-1/application.log"
app_pid="$(wait_for_app || true)"
test -n "$app_pid" || fail "cold launch did not create the real application"
launch_elapsed="$(( $(date +%s) - launch_start ))"
sleep 3
kill -0 "$app_pid" 2>/dev/null || fail "application exited during cold launch"

if test -f "$LEGACY_CONFIG_DIR/wiliwili_config.json"; then
    test -f "$CONFIG_DIR/silisili_config.json" ||
        fail "legacy configuration was not migrated"
    test "$(stat -c '%U' "$CONFIG_DIR/silisili_config.json")" = "$APP_USER" ||
        fail "migrated configuration ownership is wrong"
    test "$(stat -c '%a' "$CONFIG_DIR/silisili_config.json")" = 600 ||
        fail "migrated configuration permissions are not private"
    pass "legacy configuration migrated without exposing its contents"
fi

mobile_scale_line="$(wait_for_log_line "$EVIDENCE/launch-1/application.log" \
    'Sailfish mobile window ' || true)"
test -n "$mobile_scale_line" || fail "Sailfish mobile scale diagnostics are missing"
printf '%s\n' "$mobile_scale_line" >"$EVIDENCE/launch-1/mobile-scale.txt"
mobile_baseline_line="$(wait_for_log_line "$EVIDENCE/launch-1/application.log" \
    'Sailfish mobile UI baseline: 427x240; fixed short edge: 427; video grids: portrait 1 landscape 3' || true)"
test -n "$mobile_baseline_line" || fail "Sailfish mobile baseline diagnostics are missing"
printf '%s\n' "$mobile_baseline_line" >"$EVIDENCE/launch-1/mobile-baseline.txt"
mobile_text_scale_line="$(wait_for_log_line "$EVIDENCE/launch-1/application.log" \
    'Sailfish mobile typography: native-client hierarchy; text factor 0.800; touch targets 48-56; visible icons 24-28' || true)"
test -n "$mobile_text_scale_line" || fail "Sailfish mobile text-scale diagnostics are missing"
printf '%s\n' "$mobile_text_scale_line" >"$EVIDENCE/launch-1/mobile-text-scale.txt"
adaptive_display_line="$(wait_for_log_line "$EVIDENCE/launch-1/application.log" \
    'Sailfish adaptive display: mode ' || true)"
test -n "$adaptive_display_line" || fail "Sailfish adaptive display diagnostics are missing"
printf '%s\n' "$adaptive_display_line" >"$EVIDENCE/launch-1/adaptive-display.txt"
logical_width="$(sed -n 's/.*content size: \([0-9][0-9.]*\)x\([0-9][0-9.]*\).*/\1/p' \
    "$EVIDENCE/launch-1/mobile-scale.txt")"
logical_height="$(sed -n 's/.*content size: \([0-9][0-9.]*\)x\([0-9][0-9.]*\).*/\2/p' \
    "$EVIDENCE/launch-1/mobile-scale.txt")"
baseline_width="$(sed -n 's/.*baseline: \([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1/p' \
    "$EVIDENCE/launch-1/mobile-baseline.txt")"
baseline_height="$(sed -n 's/.*baseline: \([0-9][0-9]*\)x\([0-9][0-9]*\).*/\2/p' \
    "$EVIDENCE/launch-1/mobile-baseline.txt")"
test -n "$logical_width" && test -n "$logical_height" ||
    fail "could not parse Sailfish logical content dimensions"
test -n "$baseline_width" && test -n "$baseline_height" ||
    fail "could not parse Sailfish UI baseline dimensions"
test "$baseline_width" = 640 && test "$baseline_height" = 360 ||
    fail "Sailfish UI baseline is not fixed at 640x360"
awk -v width="$logical_width" -v height="$logical_height" \
    -v baseline_width="$baseline_width" -v baseline_height="$baseline_height" 'BEGIN {
    short_edge = width < height ? width : height
    expected = baseline_width > baseline_height ? baseline_width : baseline_height
    exit !(short_edge >= expected - 1 && short_edge <= expected + 1)
}' || fail "logical short edge does not match the selected baseline: ${logical_width}x${logical_height}"
pass "Sailfish profile preserved its selected logical short edge"

visible_pid="$(wait_for_topmost_window "$app_pid" \
    2>"$EVIDENCE/launch-1/topmost-window.err" || true)"
printf 'expected_pid=%s\ntopmost_pid=%s\n' "$app_pid" "$visible_pid" \
    >"$EVIDENCE/launch-1/topmost-window.txt"
test "$visible_pid" = "$app_pid" ||
    fail "Lipstick topmost window does not belong to silisili"

step=cold-launch-runtime
app_environment="$(tr '\0' '\n' <"/proc/$app_pid/environ")"
printf '%s\n' "$app_environment" >"$EVIDENCE/launch-1/environment.txt"
printf '%s\n' "$app_environment" | grep -Fxq 'EGL_PLATFORM=wayland' ||
    fail "launcher did not replace EGL_PLATFORM"
printf '%s\n' "$app_environment" | grep -Fxq 'HYBRIS_EGLPLATFORM=wayland' ||
    fail "launcher did not replace HYBRIS_EGLPLATFORM"
printf '%s\n' "$app_environment" | grep -Fxq 'QT_QPA_PLATFORM=wayland' ||
    fail "launcher did not replace QT_QPA_PLATFORM"
if printf '%s\n' "$app_environment" |
    grep -Eq '^(EGL_PLATFORM|HYBRIS_EGLPLATFORM|QT_QPA_PLATFORM)=hwcomposer$'; then
    fail "application inherited compositor-only hwcomposer state"
fi
if printf '%s\n' "$app_environment" | grep -q '^QT_QPA_FORCE_HWC2='; then
    fail "application inherited QT_QPA_FORCE_HWC2"
fi
if printf '%s\n' "$app_environment" | grep -q '^LD_PRELOAD='; then
    fail "application inherited LD_PRELOAD"
fi

grep -Fq '/usr/lib64/libstdc++.so.6.' "/proc/$app_pid/maps" ||
    fail "Sailfish system libstdc++ is not mapped"
grep -Fq "$LIBDIR/libmpv.so.2." "/proc/$app_pid/maps" ||
    fail "private libmpv is not mapped"
grep -Fq "$LIBDIR/libcurl.so.4." "/proc/$app_pid/maps" ||
    fail "private curl is not mapped"
grep -Fq "$LIBDIR/libavcodec.so.59." "/proc/$app_pid/maps" ||
    fail "private FFmpeg codec library is not mapped"
grep -Fq "$LIBDIR/libavformat.so.59." "/proc/$app_pid/maps" ||
    fail "private FFmpeg format library is not mapped"
grep -Fq '/usr/lib64/libhybris/eglplatform_wayland.so' "/proc/$app_pid/maps" ||
    fail "Wayland EGL platform is not mapped"
grep -Fq '/dev/kgsl-3d0' "/proc/$app_pid/maps" ||
    fail "Adreno GPU device is not mapped"

step=cold-launch-sampling
ticks_before="$(read_cpu_ticks "$app_pid")"
rss_before="$(read_rss_kb "$app_pid")"
fd_before="$(read_fd_count "$app_pid")"
sleep "$SAMPLE_SECONDS"
kill -0 "$app_pid" 2>/dev/null || fail "application exited during sampling"
ticks_after="$(read_cpu_ticks "$app_pid")"
rss_after="$(read_rss_kb "$app_pid")"
fd_after="$(read_fd_count "$app_pid")"
test "$rss_after" -gt 0 && test "$rss_after" -lt 524288 ||
    fail "application RSS is outside the 0-512 MiB guard: ${rss_after}kB"

step=cold-launch-evidence
{
    echo "pid=$app_pid"
    echo "launch_elapsed_seconds=$launch_elapsed"
    echo "sample_seconds=$SAMPLE_SECONDS"
    echo "cpu_ticks_delta=$((ticks_after - ticks_before))"
    echo "rss_before_kb=$rss_before"
    echo "rss_after_kb=$rss_after"
    echo "fd_before=$fd_before"
    echo "fd_after=$fd_after"
    awk '/^(Name|State|Pid|Uid|Threads|VmPeak|VmSize|VmRSS|VmSwap):/ { print }' \
        "/proc/$app_pid/status"
} >"$EVIDENCE/launch-1/process.txt"
cp "/proc/$app_pid/maps" "$EVIDENCE/launch-1/maps.txt"
find "/proc/$app_pid/fd" -mindepth 1 -maxdepth 1 -type l -exec readlink {} \; \
    >"$EVIDENCE/launch-1/fds.txt" 2>/dev/null || true
ss -tnp 2>&1 | awk -v marker="pid=$app_pid," \
    'NR == 1 || index($0, marker) != 0' \
    >"$EVIDENCE/launch-1/tcp-sockets.txt" || true
pass "cold desktop-path launch created a visible Lipstick window and survived ${SAMPLE_SECONDS}s with Wayland EGL and private runtime"

step=second-launch
stop_app
launch_desktop_path "$EVIDENCE/launch-2/application.log"
app_pid="$(wait_for_app || true)"
test -n "$app_pid" || fail "second launch did not create the real application"
sleep 5
kill -0 "$app_pid" 2>/dev/null || fail "application exited during second launch"
kill -STOP "$app_pid"
sleep 1
test "$(awk '/^State:/ { print $2 }' "/proc/$app_pid/status")" = T ||
    fail "diagnostic background stop did not take effect"
kill -CONT "$app_pid"
sleep 2
case "$(awk '/^State:/ { print $2 }' "/proc/$app_pid/status")" in
    R|S) ;;
    *) fail "application did not resume after diagnostic continue" ;;
esac
pass "second launch and diagnostic process resume"

step=anomaly-scan
journalctl --since "$start" --no-pager >"$EVIDENCE/journal.txt" 2>&1 || true
journalctl -k --since "$start" --no-pager >"$EVIDENCE/kernel.txt" 2>&1 || true
if grep -Eiq 'segmentation fault|core dumped|ANOM_ABEND|SIGABRT|Wayland display got fatal error|not responding|gpu fault|out of memory|oom-killer' \
    "$EVIDENCE/journal.txt" "$EVIDENCE/kernel.txt"; then
    fail "crash, hang, GPU, or memory anomaly detected in the test window"
fi
pass "no crash, ANR, GPU fault, or OOM in the test window"

step=complete
if grep -Eq "ESTAB.*pid=$app_pid," "$EVIDENCE/launch-1/tcp-sockets.txt"; then
    echo "AUTO_OBSERVED: application opened an established TCP connection"
else
    manual "confirm the silisili homepage loads Bilibili content"
fi
manual "confirm Chinese text renders without boxes"
manual "confirm portrait grids use 2 columns and landscape grids use 4 columns with readable text and enlarged touch targets"
manual "confirm every text and numeric input opens the system keyboard and shows working touch Back and OK controls without an alphabet grid or Y hint"
manual "confirm Home, Activity, and Me use the fixed bottom navigation and nested pages return through the activity stack"
manual "confirm horizontal seek previews while dragging, commits only on release, and a canceled gesture does not seek"
manual "confirm a second finger cancels the active gesture without triggering tap, seek, or changing the video viewport"
manual "confirm portrait detail uses a full-width 16:9 player above metadata/comments and landscape uses a video-only surface without overlay misalignment"
manual "confirm an anonymous video's first two comment pages each append 20 ordinary replies instead of ending after three"
manual "confirm the application surface fills the entire 1080x2160 display without desktop window margins"
manual "confirm fullscreen selects landscape for horizontal video and portrait for vertical video without stretching"
manual "confirm the upper-left Back control exits fullscreen first and then returns to the previous page"
manual "confirm video, PulseAudio sound, A/V sync, and seeking"
manual "send the app to the background and return; confirm the frame and playback recover"
manual "rotate portrait/landscape and confirm bottom navigation, 2/4-column grids, stable multi-touch IDs, and full-screen layout"

echo "AUTO_RESULT=PASS pid=$app_pid evidence=$EVIDENCE"
echo "The second application launch remains running for manual acceptance."
