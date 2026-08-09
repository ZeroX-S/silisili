#!/usr/bin/env bash
set -euo pipefail

PORT_ROOT="${PORT_ROOT:-/media/psf/bonito-port}"
TELNET="$PORT_ROOT/vm-deploy/scripts/telnet-cmd.sh"
PACKAGE="${PACKAGE:-silisili-sailfish-1.0.0-7.aarch64.rpm}"
PACKAGE_URL="${PACKAGE_URL:-http://192.168.2.20:18082/$PACKAGE}"
SCREENSHOT_URL="${SCREENSHOT_URL:-http://192.168.2.20:18103}"
APP_LOG=/tmp/silisili-5x-phone-test.log

phone() {
    bash "$TELNET" "$@"
}

case "${1:-}" in
status)
    phone \
        'date' \
        'cat /etc/sailfish-release' \
        'rpm -q --qf "%{VERSION}-%{RELEASE}\n" silisili-sailfish || true' \
        'rpm -q libstdc++ || true' \
        'ls -l /tmp/bonito-direct-touch /tmp/bonito-uinput-camera-key /tmp/bonito-key-inject 2>/dev/null || true' \
        'for p in /proc/[0-9]*; do x=$(readlink -f "$p/exe" 2>/dev/null || true); test "$x" = /usr/lib64/silisili/silisili.real && echo app_pid=${p##*/}; done'
    ;;
install)
    phone \
        "curl -fsS '$PACKAGE_URL' -o '/tmp/$PACKAGE'" \
        "rpm -Uvh --replacepkgs '/tmp/$PACKAGE'" \
        'rpm -V silisili-sailfish' \
        'rpm -q --qf "%{VERSION}-%{RELEASE}\n" silisili-sailfish' \
        'test ! -e /usr/lib64/silisili/libstdc++.so.6' \
        'test -e /usr/lib64/silisili/libavcodec.so.59' \
        'test -e /usr/lib64/silisili/libavformat.so.59' \
        'test -e /usr/lib64/silisili/libcurl.so.4' \
        'test -e /usr/lib64/silisili/libmpv.so.2'
    ;;
launch)
    phone \
        'mcetool --set-never-blank=enabled >/dev/null' \
        'mcetool --unblank-screen >/dev/null' \
        'mcetool --set-tklock-mode=unlocked >/dev/null' \
        'for p in /proc/[0-9]*; do x=$(readlink -f "$p/exe" 2>/dev/null || true); test "$x" = /usr/lib64/silisili/silisili.real && kill -TERM "${p##*/}"; done; sleep 3' \
        "su -s /bin/sh - defaultuser -c \"env EGL_PLATFORM=hwcomposer HYBRIS_EGLPLATFORM=hwcomposer QT_QPA_PLATFORM=hwcomposer QT_QPA_FORCE_HWC2=1 /usr/bin/silisili > '$APP_LOG' 2>&1 &\"" \
        'sleep 8' \
        'app=$(for p in /proc/[0-9]*; do x=$(readlink -f "$p/exe" 2>/dev/null || true); test "$x" = /usr/lib64/silisili/silisili.real && echo ${p##*/}; done | tail -1); test -n "$app"; echo app_pid=$app' \
        'top=$(runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket gdbus call --session --dest org.nemomobile.lipstick --object-path / --method org.nemomobile.compositor.privateTopmostWindowProcessId | tr -cd 0-9); echo top_pid=$top; test "$top" = "$app"'
    ;;
runtime)
    phone \
        'app=$(for p in /proc/[0-9]*; do x=$(readlink -f "$p/exe" 2>/dev/null || true); test "$x" = /usr/lib64/silisili/silisili.real && echo ${p##*/}; done | tail -1); test -n "$app"' \
        'grep -F /usr/lib64/libstdc++.so.6. /proc/$app/maps | head -1' \
        'grep -F /usr/lib64/silisili/libavcodec.so.59. /proc/$app/maps | head -1' \
        'grep -F /usr/lib64/silisili/libavformat.so.59. /proc/$app/maps | head -1' \
        'grep -F /usr/lib64/silisili/libmpv.so.2. /proc/$app/maps | head -1' \
        'grep -F /usr/lib64/silisili/libcurl.so.4. /proc/$app/maps | head -1' \
        'grep -F /usr/lib64/silisili/libssl.so.3 /proc/$app/maps | head -1' \
        "tail -160 '$APP_LOG' | grep -Ei 'Sailfish|SIGABRT|segmentation fault|core dumped|not responding|gpu fault|out of memory' | tail -80 || true"
    ;;
tap)
    test "$#" -eq 3
    case "$2:$3" in *[!0-9:]*) exit 2 ;; esac
    phone "/tmp/bonito-direct-touch tap $2 $3" 'sleep 2'
    ;;
swipe)
    test "$#" -eq 7
    case "$2:$3:$4:$5:$6:$7" in *[!0-9:]*) exit 2 ;; esac
    phone "/tmp/bonito-direct-touch swipe $2 $3 $4 $5 $6 $7" 'sleep 2'
    ;;
player-fullscreen)
    phone \
        'sleep 5' \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-direct-touch tap 975 515' \
        'sleep 4'
    ;;
player-fullscreen-capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        'sleep 5' \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-direct-touch tap 975 515' \
        'sleep 3' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
player-fullscreen-cycle-capture)
    test "$#" -eq 3
    enter_name="$2"
    exit_name="$3"
    for name in "$enter_name" "$exit_name"; do
        case "$name" in
            *.png) ;;
            *) exit 2 ;;
        esac
        case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    done
    phone \
        'sleep 5' \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-direct-touch tap 975 515' \
        'sleep 3' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$enter_name'; echo enter_screenshot=\$shot" \
        '/tmp/bonito-uinput-camera-key back' \
        'sleep 3' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$exit_name'; echo exit_screenshot=\$shot"
    ;;
player-osd-capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
player-quality-capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        'sleep 5' \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-direct-touch tap 690 510' \
        'sleep 2' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
player-share-capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        'sleep 5' \
        '/tmp/bonito-direct-touch tap 850 840' \
        'sleep 2' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
player-settings-capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        '/tmp/bonito-direct-touch tap 540 280' \
        'sleep 1' \
        '/tmp/bonito-direct-touch tap 1030 50' \
        'sleep 2' \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
display-inhibit)
    phone \
        'mcetool --set-never-blank=disabled >/dev/null' \
        'mcetool --unblank-screen >/dev/null' \
        'sleep 45' \
        'state=$(mcetool -N 2>/dev/null | awk -F: '\''/Display state:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}'\''); never=$(mcetool -N 2>/dev/null | awk -F: '\''/Display never blank:/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}'\''); echo display_state=$state never_blank=$never; test "$state" = on; test "$never" = disabled'
    ;;
back)
    phone '/tmp/bonito-uinput-camera-key back' 'sleep 2'
    ;;
capture)
    test "$#" -eq 2
    name="$2"
    case "$name" in
        *.png) ;;
        *) exit 2 ;;
    esac
    case "$name" in *[!A-Za-z0-9._-]*) exit 2 ;; esac
    phone \
        '/tmp/bonito-uinput-camera-key screenshot' \
        'sleep 2' \
        "shot=\$(ls -1t /home/defaultuser/Pictures/Screenshots/*.png 2>/dev/null | head -1); test -n \"\$shot\"; curl -fsS -X PUT --data-binary @\"\$shot\" '$SCREENSHOT_URL/$name'; echo screenshot=\$shot"
    ;;
log)
    phone \
        "tail -260 '$APP_LOG' || true" \
        'journalctl --since "10 minutes ago" --no-pager | grep -Ei "silisili|SIGABRT|segmentation fault|core dumped|not responding|gpu fault|out of memory|oom-killer" | tail -160 || true'
    ;;
release)
    phone \
        'for p in /proc/[0-9]*; do x=$(readlink -f "$p/exe" 2>/dev/null || true); test "$x" = /usr/lib64/silisili/silisili.real && kill -TERM "${p##*/}"; done; sleep 3' \
        'mcetool --set-never-blank=disabled >/dev/null' \
        'mcetool --set-tklock-mode=unlocked >/dev/null' \
        'mcetool --unblank-screen >/dev/null'
    ;;
*)
    echo "Usage: $0 {status|install|launch|runtime|tap X Y|swipe X1 Y1 X2 Y2 MS STEPS|player-fullscreen|player-fullscreen-capture NAME.png|player-fullscreen-cycle-capture ENTER.png EXIT.png|player-osd-capture NAME.png|player-quality-capture NAME.png|player-share-capture NAME.png|player-settings-capture NAME.png|display-inhibit|back|capture NAME.png|log|release}" >&2
    exit 2
    ;;
esac
