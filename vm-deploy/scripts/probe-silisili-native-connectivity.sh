#!/bin/sh
set -eu

# Read-only connectivity gate for media probes. It changes no ConnMan state.

run_id=${1:-"connectivity-$(date +%Y%m%d-%H%M%S)"}
room_id=${SILISILI_LIVE_TEST_ROOM_ID:-23276452}
api_host=api.live.bilibili.com
api_url="https://$api_host/xlive/web-room/v2/index/getRoomPlayInfo?room_id=$room_id&no_playurl=1&platform=web"
payload=/tmp/silisili-native-connectivity-response.json
feed_payload=/tmp/silisili-native-connectivity-feed.json
candidate_payload=/tmp/silisili-native-connectivity-candidate.json
cleanup() {
    rm -f "$payload" "$feed_payload" "$candidate_payload"
}
trap cleanup EXIT HUP INT TERM

printf 'connectivity_begin=ready|run=%s|room=%s\n' "$run_id" "$room_id"
printf 'connectivity_ipv4='; ip -o -4 address show 2>/dev/null | tr '\n' ','; printf '\n'
printf 'connectivity_routes='; ip route show 2>/dev/null | tr '\n' ','; printf '\n'
if command -v connmanctl >/dev/null 2>&1; then
    printf 'connectivity_services='; connmanctl services 2>/dev/null | tr '\n' ','; printf '\n'
fi
printf 'connectivity_dns='; getent ahostsv4 "$api_host" 2>&1 | head -3 | tr '\n' ','; printf '\n'

if ! command -v curl >/dev/null 2>&1; then
    printf 'sailfish_test=blocked|run=%s|reason=curl-missing\n' "$run_id"
    exit 1
fi
http_result=$(curl --connect-timeout 5 --max-time 15 --silent --show-error \
    --output "$payload" --write-out '%{http_code}|%{remote_ip}|%{time_connect}|%{time_starttransfer}|%{time_total}' \
    "$api_url" 2>&1) || {
        printf 'sailfish_test=failed|run=%s|reason=https-request-failed|evidence=%s\n' \
            "$run_id" "$http_result"
        exit 1
    }
http_code=$(printf '%s' "$http_result" | cut -d'|' -f1)
test "$http_code" = 200 || {
    printf 'sailfish_test=failed|run=%s|reason=http-%s|evidence=%s\n' \
        "$run_id" "$http_code" "$http_result"
    exit 1
}
api_code=$(sed -n 's/.*"code":[[:space:]]*\(-*[0-9][0-9]*\).*/\1/p' "$payload" | head -1)
live_status=$(sed -n 's/.*"live_status":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$payload" | head -1)
bytes=$(wc -c <"$payload" | tr -d ' ')
printf 'connectivity_https=ready|run=%s|http=%s|remote=%s|connect_s=%s|first_byte_s=%s|total_s=%s|bytes=%s|api_code=%s|live_status=%s\n' \
    "$run_id" "$http_code" \
    "$(printf '%s' "$http_result" | cut -d'|' -f2)" \
    "$(printf '%s' "$http_result" | cut -d'|' -f3)" \
    "$(printf '%s' "$http_result" | cut -d'|' -f4)" \
    "$(printf '%s' "$http_result" | cut -d'|' -f5)" \
    "$bytes" "${api_code:-unknown}" "${live_status:-unknown}"

active_room=
if test "${live_status:-0}" = 1; then
    active_room=$room_id
else
    curl --connect-timeout 5 --max-time 15 --silent --show-error \
        --output "$feed_payload" \
        'https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getList?platform=web'
    candidates=$(grep -oE '"roomid":[0-9]+' "$feed_payload" 2>/dev/null \
        | cut -d: -f2 | awk '!seen[$0]++' | head -12 || true)
    for candidate in $candidates; do
        curl --connect-timeout 5 --max-time 15 --silent --show-error \
            --output "$candidate_payload" \
            "https://$api_host/xlive/web-room/v2/index/getRoomPlayInfo?room_id=$candidate&no_playurl=1&platform=web"
        candidate_status=$(sed -n 's/.*"live_status":[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
            "$candidate_payload" | head -1)
        if test "${candidate_status:-0}" = 1; then
            active_room=$candidate
            break
        fi
    done
fi
test -n "$active_room" || {
    printf 'sailfish_test=blocked|run=%s|reason=active-live-room-not-found\n' "$run_id"
    exit 1
}
printf 'connectivity_active_room=ready|run=%s|room=%s|requested_room_status=%s\n' \
    "$run_id" "$active_room" "${live_status:-unknown}"
trap - EXIT HUP INT TERM
cleanup
printf 'sailfish_test=ready|run=%s|package=none|pid=none|checks=6/6\n' "$run_id"
