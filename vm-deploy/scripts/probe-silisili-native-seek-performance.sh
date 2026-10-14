#!/bin/sh
set -eu
run=${1:-seek-perf-$(date +%Y%m%d-%H%M%S)}
sample=${2:-reference}
profile=${3:-fast}
case "$run" in *[!A-Za-z0-9_-]*) exit 64;; esac
if test "$sample" = reference; then bvid=BV1P4ddBBEJF; cid=37630051884; quality=116; else bvid=BV1vHp96TErE; cid=42680649431; quality=80; fi
events=/tmp/silisili-perf-native-$run.log
journal=/tmp/silisili-perf-$run.events
pid=
package=$(rpm -q silisili-native-devel)
boot=$(cat /proc/sys/kernel/random/boot_id)
printf 'seek_perf_identity=ready|run=%s|package=%s|boot=%s\n' "$run" "$package" "$boot"
trap 'rc=$?; if test "$rc" -ne 0; then printf "sailfish_test=failed|run=%s|pid=%s|reason=seek-performance|evidence=%s\n" "$run" "$pid" "$events"; fi' EXIT
old=$(pidof silisili-native 2>/dev/null || true)
if test -n "$old"; then kill -TERM $old; sleep 2; fi
test -z "$(pidof silisili-native 2>/dev/null || true)"
rm -f "$events"
mcetool --set-tklock-mode=unlocked >/dev/null
mcetool --unblank-screen >/dev/null
runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket WAYLAND_DISPLAY=../../display/wayland-0 QT_QPA_PLATFORM=wayland SILISILI_NATIVE_TEST_PAGE=video-detail SILISILI_NATIVE_TEST_CONTENT_MODE=direct SILISILI_NATIVE_TEST_BVID="$bvid" SILISILI_NATIVE_TEST_CID="$cid" SILISILI_NATIVE_TEST_QUALITY="$quality" SILISILI_NATIVE_TEST_PERF_PROFILE="$profile" SILISILI_NATIVE_TEST_PERF_LOG="$events" /usr/bin/invoker --no-wait --type=silica-qt5 --id=cn.silisili.native --single-instance /usr/bin/silisili-native >/tmp/silisili-perf-launch.log 2>&1
sleep 1
pid=$(pidof silisili-native)
read_events() { journalctl -b "_PID=$pid" --no-pager -o short-monotonic >"$journal"; }
bus() { runuser -u defaultuser -- env XDG_RUNTIME_DIR=/run/user/100000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket gdbus call --session --dest org.mpris.MediaPlayer2.silisili --object-path /org/mpris/MediaPlayer2 --method "$@"; }
i=0
while test "$i" -lt 100; do
  read_events
  grep -q 'perf_start_ready.*audioReleased 1' "$events" 2>/dev/null && break
  test "$(pidof silisili-native 2>/dev/null || true)" = "$pid"
  sleep 0.2; i=$((i+1))
done
grep 'perf_start_ready.*audioReleased 1' "$events"
bus org.mpris.MediaPlayer2.Player.Pause >/dev/null
serial=0
for target in 90 14 120 30; do
  serial=$((serial+1))
  if test "$serial" = 3; then bus org.mpris.MediaPlayer2.Player.Play >/dev/null; fi
  bus org.mpris.MediaPlayer2.Player.SetPosition "/cn/silisili/track/${bvid}_$cid" "$((target * 1000000))" >/dev/null
  i=0
  while test "$i" -lt 100; do
    read_events
    if grep -q "perf_target serial $serial " "$events" \
       && grep -q "perf_texture target $target " "$events"; then break; fi
    test "$(pidof silisili-native 2>/dev/null || true)" = "$pid"
    sleep 0.1; i=$((i+1))
  done
  grep "perf_target serial $serial " "$events" | tail -1
  test "$i" -lt 100
  # The accepted image must match the target, independently of the audio clock.
  awk -v serial="$serial" -v target="$target" '
    /perf_target/ {
      for(i=1;i<=NF;i++) {if($i=="serial") s=$(i+1); if($i=="ptsUs") pts=$(i+1)}
      if(s==serial) {d=pts/1000000-target; if(d<0) d=-d; if(d>0.75) bad=1; found=1}
    } END {if(!found || bad) exit 1}
  ' "$events"
  sleep 0.2
done
# Repeated drags must coalesce to the latest target without reopening media.
if test "$profile" != baseline; then
  bus org.mpris.MediaPlayer2.Player.Pause >/dev/null
  for target in 90 14 120; do
    bus org.mpris.MediaPlayer2.Player.SetPosition "/cn/silisili/track/${bvid}_$cid" "$((target * 1000000))" >/dev/null
  done
  i=0
  while test "$i" -lt 100; do
    read_events
    grep -q 'perf_target serial 7 ' "$events" && break
    sleep 0.1; i=$((i+1))
  done
  test "$i" -lt 100
  awk '/perf_target serial 7 / {for(i=1;i<=NF;i++) if($i=="ptsUs") {pts=$(i+1);if(pts<119250000 || pts>120750000)bad=1;found=1}} END {if(!found || bad)exit 1}' "$events"
  test "$(grep -c 'perf_load' "$events")" -eq 1
  if grep -E 'perf_target.*generation [2-9]' "$events"; then exit 1; fi
  if grep -E 'same-quality decoder restart completed|switching to software fallback|ANOM_ABEND|TypeError|ReferenceError' "$journal"; then exit 1; fi
  bus org.mpris.MediaPlayer2.Player.Play >/dev/null
fi
read_events
awk '
 function clock() {text=$0;sub(/^\[[[:space:]]*/,"",text);sub(/\].*$/, "", text);return text+0}
 /perf_request/ {start=clock()}
 /perf_load/ {load=clock()}
 /perf_start_ready/ {ready=clock(); printf "startup_metric=requestMs:%.3f,loadMs:%.3f\n",(ready-start)*1000,(ready-load)*1000}
 /perf_seek_request/ {seek=clock()}
 /perf_target/ {
   for(i=1;i<=NF;i++) if($i=="serial") serial=$(i+1)
   if(serial>0) {ready=clock();printf "seek_metric=serial:%d,ms:%.3f\n",serial,(ready-seek)*1000}
 }
' "$events"
printf 'sailfish_test=ready|run=%s|sample=%s|package=%s|pid=%s|checks=seek-targets-pause-playing-latest-wins-single-load-no-restart|events=%s\n' "$run" "$sample" "$package" "$pid" "$events"
