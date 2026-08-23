#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_IP="${PHONE_IP:-192.168.2.15}"
PHONE_PORT="${PHONE_PORT:-2323}"

tmp_script="$(mktemp "${TMPDIR:-/tmp}/silisili-native-minimedia-boot-race.XXXXXX.sh")"
trap 'rm -f "$tmp_script"' EXIT HUP INT TERM

cat >"$tmp_script" <<'REMOTE_MINIMEDIA_BOOT_RACE'
#!/bin/sh
set -eu

package="$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel 2>/dev/null || true)"
if [ -z "$package" ]; then
    echo "native_minimedia_boot_race=blocked|reason=package-not-installed"
    exit 2
fi

verify="$(rpm -V silisili-native-devel 2>/dev/null || true)"
if [ -n "$verify" ]; then
    echo "$verify" | sed 's/^/rpm_verify_drift=/'
    echo "native_minimedia_boot_race=blocked|package=$package|reason=rpm-verify-drift"
    exit 3
fi

wrapper=/usr/libexec/silisili-native/silisili-native-minimedia-wrapper
if [ ! -x "$wrapper" ]; then
    echo "native_minimedia_boot_race=blocked|package=$package|reason=wrapper-missing"
    exit 4
fi
if ! grep -Fq 'startup already in progress' "$wrapper" \
        || ! grep -Fq '/run/silisili-native-minimedia.lock' "$wrapper" \
        || ! grep -Fq 'existing service already running; wrapper exits' "$wrapper"; then
    echo "native_minimedia_boot_race=blocked|package=$package|reason=wrapper-guard-missing"
    exit 5
fi
if ! systemctl cat silisili-native-minimedia.service 2>/dev/null \
        | grep -Fq 'After=local-fs.target droid-hal-init.service'; then
    echo "native_minimedia_boot_race=blocked|package=$package|reason=unit-ordering-missing"
    exit 6
fi

service_active="$(systemctl is-active silisili-native-minimedia.service 2>/dev/null || true)"
service_result="$(systemctl show -p Result --value silisili-native-minimedia.service 2>/dev/null || true)"
service_mainpid="$(systemctl show -p MainPID --value silisili-native-minimedia.service 2>/dev/null || true)"

minimedia_lines="$(pgrep -a -f '(/system/bin|/usr/libexec/droid-hybris/system/bin)/minimediaservice' 2>/dev/null || true)"
minimedia_count="$(printf '%s\n' "$minimedia_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
camera_lines="$(pgrep -a -f 'camera|jolla-camera|harbour-camera' 2>/dev/null || true)"
camera_count="$(printf '%s\n' "$camera_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
droid_hal_lines="$(pgrep -a -f 'droid-hal-init|droid-hal' 2>/dev/null || true)"
droid_hal_count="$(printf '%s\n' "$droid_hal_lines" | sed '/^$/d' | wc -l | tr -d ' ')"

echo "minimedia_processes_begin"
printf '%s\n' "$minimedia_lines"
echo "minimedia_processes_end"
echo "camera_processes_begin"
printf '%s\n' "$camera_lines"
echo "camera_processes_end"
echo "droid_hal_processes_begin"
printf '%s\n' "$droid_hal_lines"
echo "droid_hal_processes_end"
echo "silisili_minimedia_journal_begin"
journalctl -u silisili-native-minimedia.service -n 40 --no-pager 2>/dev/null || true
echo "silisili_minimedia_journal_end"

if [ "$minimedia_count" -gt 1 ]; then
    echo "native_minimedia_boot_race=blocked|package=$package|reason=duplicate-minimediaservice|processes=$minimedia_count|service=$service_active|result=$service_result|mainpid=$service_mainpid|camera_processes=$camera_count|droid_hal_processes=$droid_hal_count"
    exit 7
fi

echo "native_minimedia_boot_race=ready|package=$package|processes=$minimedia_count|service=$service_active|result=$service_result|mainpid=$service_mainpid|camera_processes=$camera_count|droid_hal_processes=$droid_hal_count|rpm_verify=clean|wrapper_guard=present|unit_after=droid-hal-init|visual_model=unused"
REMOTE_MINIMEDIA_BOOT_RACE
chmod 0755 "$tmp_script"

PHONE_IP="$PHONE_IP" PHONE_PORT="$PHONE_PORT" \
    python3 "$SCRIPT_DIR/run-phone-script.py" "$tmp_script" \
    --timeout "${PHONE_SCRIPT_TIMEOUT:-180}" \
    --line-delay "${PHONE_SCRIPT_LINE_DELAY:-0.0002}"
