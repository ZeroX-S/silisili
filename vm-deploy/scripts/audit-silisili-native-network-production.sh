#!/bin/sh
set -eu

application_pids() {
    for process in /proc/[0-9]*; do
        executable=$(readlink "$process/exe" 2>/dev/null || true)
        case "$executable" in
            /usr/bin/silisili-native|"/usr/bin/silisili-native (deleted)")
                basename "$process"
                ;;
        esac
    done
}

set -- $(application_pids)
test "$#" -eq 1
pid=$1
starttime=$(awk '{print $22}' "/proc/$pid/stat")
package=$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' \
    silisili-native-devel)
test "$package" = silisili-native-devel-1.1.0-1.25.aarch64
test -z "$(rpm -V silisili-native-devel 2>/dev/null || true)"

events=$(journalctl -b "_PID=$pid" --no-pager -o cat 2>/dev/null || true)
printf '%s\n' "$events" | grep -Fq \
    'native app: build identity "silisili-native-devel" "1.1.0" "1.25"'
printf '%s\n' "$events" | grep -Fq 'native layout: application ready forced'
printf '%s\n' "$events" | grep -Fq 'home feed parsed "recommended" page 1'
test -z "$(printf '%s\n' "$events" | grep -E \
    'QML.*Error|TypeError|ReferenceError|Binding loop|Segmentation fault|ANOM_ABEND' || true)"
test -e "/proc/$pid/stat"
test "$(awk '{print $22}' "/proc/$pid/stat")" = "$starttime"

printf 'native_network_production=ready|package=%s|pid=%s|starttime=%s|home_feed=ready|rpm_verify=clean|visual_model=unused\n' \
    "$package" "$pid" "$starttime"
