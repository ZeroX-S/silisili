#!/bin/sh
set -eu

printf 'launch_diagnostic_begin=ready\n'
printf 'launch_diagnostic_package=%s\n' \
    "$(rpm -q silisili-native-devel 2>&1 || true)"
printf 'launch_diagnostic_verify='; rpm -V silisili-native-devel 2>&1 \
    | tr '\n' ',' || true; printf '\n'
printf 'launch_diagnostic_processes='; \
    pgrep -af '^/usr/bin/silisili-native' 2>/dev/null \
    | tr '\n' ',' || true; printf '\n'
printf '%s\n' 'launch_diagnostic_invoker_log_begin'
tail -300 /tmp/silisili-native-pip-shutdown-launch.log 2>/dev/null || true
printf '%s\n' 'launch_diagnostic_invoker_log_end'
printf '%s\n' 'launch_diagnostic_journal_begin'
journalctl -b --since '-5 min' --no-pager -o cat 2>/dev/null \
    | grep -E 'silisili-native|QML|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' \
    | tail -400 || true
printf '%s\n' 'launch_diagnostic_journal_end'
printf 'launch_diagnostic=ready\n'
