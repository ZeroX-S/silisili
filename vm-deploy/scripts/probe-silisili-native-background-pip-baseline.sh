#!/bin/sh
set -eu

run_id="${SILISILI_PIP_RUN_ID:-pip-baseline-$(date +%Y%m%dT%H%M%S)}"
printf 'pip_baseline_run_id=%s\n' "$run_id"
printf 'pip_baseline_uname=%s\n' "$(uname -a)"
if [ -r /etc/sailfish-release ]; then
    sailfish_version="$(sed -n 's/^VERSION_ID=//p' /etc/sailfish-release | tr -d '"' | head -n 1)"
else
    sailfish_version=unknown
fi
printf 'pip_baseline_sailfish=%s\n' "${sailfish_version:-unknown}"

package_identity="$(rpm -q --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n' silisili-native-devel 2>/dev/null || :)"
printf 'pip_baseline_package=%s\n' "${package_identity:-not-installed}"
printf 'pip_baseline_stable_package=%s\n' "$(rpm -q --qf '%{NAME}|%{VERSION}|%{RELEASE}|%{ARCH}\n' silisili-sailfish 2>/dev/null || :)"
printf 'pip_baseline_incoming_sha=%s\n' "$(sha256sum /tmp/silisili-native-devel-1.1.0-1.11.aarch64.rpm 2>/dev/null | awk '{print $1}' || :)"
printf 'pip_baseline_touch_tool=%s\n' "$(test -x /tmp/bonito-direct-touch && printf present || printf absent)"
printf 'pip_baseline_app_pids=%s\n' "$(pgrep -x silisili-native 2>/dev/null | paste -sd, - || :)"
printf 'pip_baseline_lipstick_pids=%s\n' "$(pgrep -x lipstick 2>/dev/null | paste -sd, - || :)"
printf 'pip_baseline_minimedia=%s\n' "$(systemctl is-active silisili-native-minimedia.service 2>/dev/null || :)"

if command -v gdbus >/dev/null 2>&1; then
    methods="$(runuser -u defaultuser -- gdbus introspect --session \
        --dest org.nemomobile.lipstick --object-path / 2>/dev/null \
        | sed -n 's/^[[:space:]]*\([A-Za-z][A-Za-z0-9_]*\)();$/\1/p' \
        | sort -u | paste -sd, - || :)"
else
    methods=unavailable
fi
printf 'pip_baseline_lipstick_methods=%s\n' "${methods:-none}"

privilege_dir=/usr/share/mapplauncherd/privileges.d
if [ -d "$privilege_dir" ]; then
    printf 'pip_baseline_privilege_dir=present\n'
    find "$privilege_dir" -maxdepth 1 -type f -print \
        | sed 's|.*/||' | sort | head -n 20 \
        | sed 's/^/pip_baseline_privilege_entry=/'
else
    printf 'pip_baseline_privilege_dir=absent\n'
fi

printf 'pip_baseline=ready|run_id=%s|mutation=none|visual_model=unused\n' "$run_id"
