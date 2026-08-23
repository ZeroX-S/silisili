#!/bin/sh
set -eu

pids="$(pidof silisili-native 2>/dev/null || true)"
printf 'silisili_stop_pre_pids=%s\n' "$pids"
if [ -n "$pids" ]; then
    kill -TERM $pids 2>/dev/null || true
    sleep 2
fi
pids="$(pidof silisili-native 2>/dev/null || true)"
if [ -n "$pids" ]; then
    kill -KILL $pids 2>/dev/null || true
    sleep 1
fi
printf 'silisili_stop_post_pids='
pidof silisili-native 2>/dev/null || true
printf '\nsilisili_stop=ready|visual_model=unused\n'
