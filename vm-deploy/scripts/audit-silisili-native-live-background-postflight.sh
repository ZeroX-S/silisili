#!/bin/sh
set -eu

# Audit the two most recent live sessions produced by the background
# presentation probe: first Cover, then system PiP.

run_id=${1:-"live-background-$(date +%Y%m%d-%H%M%S)"}
expected_package=silisili-native-devel-1.1.0-1.45.aarch64
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf

fail() {
    reason=$1
    printf 'sailfish_test=failed|run=%s|reason=%s|evidence=journal-last-two-live-sessions\n' \
        "$run_id" "$reason"
    for active_pid in $(pgrep -f '^/usr/bin/silisili-native' 2>/dev/null || true); do
        printf 'live_background_active_process=present|pid=%s|starttime=%s\n' \
            "$active_pid" "$(awk '{print $22}' "/proc/$active_pid/stat")"
        journalctl -b "_PID=$active_pid" --no-pager -o cat 2>/dev/null \
            | grep -E 'native (cover|live|playback session|system PiP|hardware video|player|application)|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
            | tail -300 || true
    done
    exit 1
}

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package" || fail package-mismatch
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)" || fail rpm-verify
test -z "$(pgrep -f '^/usr/bin/silisili-native' || true)" || fail process-still-running
grep -Fxq 'backgroundPresentationMode=cover' "$settings" || fail mode-not-restored

pids=$(journalctl -b --no-pager -o short-monotonic 2>/dev/null \
    | grep -F 'native playback session: live activated' \
    | sed -n 's/.*\[\([0-9][0-9]*\)\]:.*/\1/p' \
    | awk '!seen[$0]++' | tail -2)
set -- $pids
test "$#" -eq 2 || fail live-session-pids-missing
cover_pid=$1
pip_pid=$2
cover_events=$(journalctl -b "_PID=$cover_pid" --no-pager -o cat 2>/dev/null || true)
pip_events=$(journalctl -b "_PID=$pip_pid" --no-pager -o cat 2>/dev/null || true)

require_marker() {
    events=$1
    marker=$2
    reason=$3
    printf '%s\n' "$events" | grep -Fq "$marker" || fail "$reason"
}

require_marker "$cover_events" 'native system PiP: configurable background presentation ready mode "cover"' cover-mode-missing
require_marker "$pip_events" 'native system PiP: configurable background presentation ready mode "pip"' pip-mode-missing
for events in "$cover_events" "$pip_events"; do
    printf '%s\n' "$events" | grep -E \
        'native cover: idle logo ready (source QSize\(144, 56\)|source 144x56).* watermarks 40' \
        >/dev/null || fail idle-cover-semantics
    printf '%s\n' "$events" | grep -E \
        'native cover: active layout ready order resolution-video-title-progress-actions .* actions 3' \
        >/dev/null || fail active-cover-layout-semantics
    test "$(printf '%s\n' "$events" | grep -Fc 'native player: load command submitted' || true)" -eq 1 \
        || fail unexpected-media-load-count
done

require_marker "$cover_events" 'native cover video: scene graph shares persistent video texture true' cover-texture-share-missing
cover_lines=$(printf '%s\n' "$cover_events" \
    | grep -F 'native cover video: live shared-texture frame presented' || true)
test "$(printf '%s\n' "$cover_lines" | grep -c . || true)" -ge 2 || fail cover-frame-count
first_cover_serial=$(printf '%s\n' "$cover_lines" | head -1 \
    | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
last_cover_serial=$(printf '%s\n' "$cover_lines" | tail -1 \
    | sed -n 's/.* serial \([0-9][0-9]*\) .*/\1/p')
test -n "$first_cover_serial" && test "$last_cover_serial" -gt "$first_cover_serial" \
    || fail cover-frame-not-advancing

require_marker "$pip_events" 'native system PiP: shown over system interface' pip-shown-missing
require_marker "$pip_events" 'mediaKind "live"' pip-media-kind-missing
require_marker "$pip_events" 'native system PiP: foreground restore requested' pip-restore-missing
test "$(printf '%s\n' "$pip_events" | grep -Fc 'native system PiP: live shared-texture frame presented' || true)" -ge 2 \
    || fail pip-frame-count
test "$(printf '%s\n' "$pip_events" | grep -Fc 'native system PiP: frame swap window' || true)" -ge 2 \
    || fail pip-frame-swap-count
test -z "$(printf '%s\n' "$pip_events" | grep -F 'native system PiP: frame swap window' \
    | tail -2 | grep -F 'below45 true' || true)" || fail pip-frame-floor

all_events=$(printf '%s\n%s\n' "$cover_events" "$pip_events")
test -z "$(printf '%s\n' "$all_events" | grep -E \
    'native transport: pause requested true|native hardware video: in-place seek requested|native hardware video: (direct pipeline failed|switching to software fallback|external texture shader failed|EGLImage creation failed|GPU fence backlog)|overlay QML error|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)" \
    || fail negative-error-scan

printf 'native_live_background_postflight=ready|run=%s|package=%s|cover_pid=%s|cover_first_serial=%s|cover_last_serial=%s|pip_pid=%s|same_decoder_per_session=1|background_pause=0|fallback=0|processes_after=0|mode_restored=cover|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$cover_pid" "$first_cover_serial" \
    "$last_cover_serial" "$pip_pid"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s,%s|checks=18/18\n' \
    "$run_id" "$expected_package" "$cover_pid" "$pip_pid"
