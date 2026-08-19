#!/bin/sh
set -eu

# Recover direct evidence for the most recent PiP shutdown transaction when
# the transport client disconnects after the device-side probe has finished.

run_id=${1:-"pip-shutdown-$(date +%Y%m%d-%H%M%S)"}
expected_package=silisili-native-devel-1.1.0-1.45.aarch64
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf

fail() {
    reason=$1
    printf 'sailfish_test=failed|run=%s|reason=%s|evidence=journal-last-pip-shutdown\n' \
        "$run_id" "$reason"
    journalctl -b --no-pager -o short-monotonic 2>/dev/null \
        | grep -Ei 'native (api|live|network|playback session|system PiP|hardware video|application shutdown|cover video|player)|request (failed|error)|network (failed|error)|timeout|No data|SSL|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
        | tail -240 || true
    exit 1
}

test "$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)" = "$expected_package" || fail package-mismatch
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)" || fail rpm-verify
test -z "$(pgrep -f '^/usr/bin/silisili-native' || true)" || fail process-still-running
grep -Fxq 'backgroundPresentationMode=cover' "$settings" || fail mode-not-restored

shutdown_line=$(journalctl -b --no-pager -o short-monotonic 2>/dev/null \
    | grep -F 'native application shutdown: barrier complete systemPiPVisible false playbackActive false' \
    | tail -1)
test -n "$shutdown_line" || fail shutdown-barrier-missing
pid=$(printf '%s\n' "$shutdown_line" | sed -n 's/.*\[\([0-9][0-9]*\)\]:.*/\1/p')
test -n "$pid" || fail shutdown-pid-missing
events=$(journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true)

require_marker() {
    printf '%s\n' "$events" | grep -Fq "$1" || fail "$2"
}

require_marker 'native system PiP: shown over system interface' pip-shown-missing
require_marker 'native application shutdown test: close scheduled' close-not-scheduled
require_marker 'native application shutdown: main window close received systemPiPVisible true' close-state-missing
require_marker 'native application shutdown: system PiP released visible false' pip-release-missing
require_marker 'native application shutdown: playback resources released hardwareDecoder false mpvBackend false sharedTexture false' resources-not-released
require_marker 'native application shutdown: barrier complete systemPiPVisible false playbackActive false' barrier-missing
require_marker 'native player: persistent mpv instance destroyed' mpv-destroy-missing

decoder_generations=$(printf '%s\n' "$events" | grep -Fc \
    'native hardware video: OMX decoder started' || true)
balanced_generations=$(printf '%s\n' "$events" | grep -c \
    'native hardware video: created buffer references released.*balanced true' || true)
test "$decoder_generations" -ge 1 || fail decoder-generation-missing
test "$balanced_generations" -eq "$decoder_generations" || fail decoder-reference-imbalance
test -z "$(printf '%s\n' "$events" | grep -E \
    'created buffer references released.*balanced false|native hardware video: (direct pipeline failed|switching to software fallback|GPU fence backlog)|overlay QML error|QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)" \
    || fail negative-error-scan

printf 'native_pip_shutdown_postflight=ready|run=%s|package=%s|pid=%s|decoder_generations=%s|buffer_generations_balanced=%s|processes_after=0|overlay_after=0|playback_after=0|mode_restored=cover|rpm_verify=clean|visual_model=unused\n' \
    "$run_id" "$expected_package" "$pid" "$decoder_generations" "$balanced_generations"
printf 'sailfish_test=ready|run=%s|package=%s|pid=%s|checks=13/13\n' \
    "$run_id" "$expected_package" "$pid"
