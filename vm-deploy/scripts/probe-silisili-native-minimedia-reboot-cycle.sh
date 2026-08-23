#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
PHONE_IP="${PHONE_IP:-192.168.2.15}"
PHONE_PORT="${PHONE_PORT:-2323}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

setup_debug() {
    if [[ -x "$WORK_ROOT/vm-setup-sailfish-debug.sh" ]]; then
        PHONE_IP="$PHONE_IP" "$WORK_ROOT/vm-setup-sailfish-debug.sh" >/dev/null 2>&1 || true
    fi
}

port_open() {
    nc -z -w 2 "$PHONE_IP" "$PHONE_PORT" >/dev/null 2>&1
}

run_probe() {
    PHONE_IP="$PHONE_IP" PHONE_PORT="$PHONE_PORT" \
        "$SCRIPT_DIR/probe-silisili-native-minimedia-boot-race.sh"
}

send_reboot() {
    PHONE_IP="$PHONE_IP" PHONE_PORT="$PHONE_PORT" python3 - <<'PY_REBOOT'
import os
import socket
import time

host = os.environ.get("PHONE_IP", "192.168.2.15")
port = int(os.environ.get("PHONE_PORT", "2323"))
payload = (
    "stty -echo\n"
    "echo native_minimedia_reboot_cycle_reboot=requested\n"
    "sync\n"
    "(systemctl reboot || reboot -f || reboot) >/dev/null 2>&1 &\n"
    "exit\n"
).encode("utf-8")
with socket.create_connection((host, port), timeout=10) as sock:
    time.sleep(0.5)
    sock.sendall(payload)
    time.sleep(0.3)
PY_REBOOT
}

echo "native_minimedia_reboot_cycle=started|run=$RUN_ID|phone=$PHONE_IP:$PHONE_PORT"
setup_debug
echo "native_minimedia_reboot_cycle_pre_begin"
run_probe
echo "native_minimedia_reboot_cycle_pre_end"

send_reboot || {
    echo "native_minimedia_reboot_cycle=blocked|run=$RUN_ID|reason=reboot-command-send-failed"
    exit 2
}

down_seen=0
for attempt in $(seq 1 60); do
    if ! port_open; then
        down_seen=1
        echo "native_minimedia_reboot_cycle_port=down|run=$RUN_ID|attempt=$attempt"
        break
    fi
    sleep 2
done
if [[ "$down_seen" != 1 ]]; then
    echo "native_minimedia_reboot_cycle=blocked|run=$RUN_ID|reason=port-did-not-drop"
    exit 3
fi

up_seen=0
for attempt in $(seq 1 120); do
    if (( attempt == 1 || attempt % 5 == 0 )); then
        setup_debug
    fi
    if port_open; then
        up_seen=1
        echo "native_minimedia_reboot_cycle_port=up|run=$RUN_ID|attempt=$attempt"
        break
    fi
    sleep 3
done
if [[ "$up_seen" != 1 ]]; then
    echo "native_minimedia_reboot_cycle=blocked|run=$RUN_ID|reason=port-did-not-return"
    exit 4
fi

# Give systemd a short grace period after the debug shell returns so the
# minimedia compatibility unit and droid-hal-init reach their post-boot state.
sleep 8
setup_debug
echo "native_minimedia_reboot_cycle_post_begin"
run_probe
echo "native_minimedia_reboot_cycle_post_end"
echo "native_minimedia_reboot_cycle=ready|run=$RUN_ID|phone=$PHONE_IP:$PHONE_PORT|visual_model=unused"
