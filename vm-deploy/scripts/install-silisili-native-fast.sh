#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_path="${1:-}"
if [[ -z "$package_path" || ! -f "$package_path" ]]; then
    printf 'usage: %s PATH_TO_RPM\n' "$0" >&2
    exit 64
fi

phone_ip="${PHONE_IP:-192.168.2.15}"
phone_port="${PHONE_PORT:-2323}"
# Keep the remote name independent of the caller-controlled local basename:
# it is only a transient transport location and is removed after verification.
remote_rpm="/tmp/silisili-native-devel-fast-install.rpm"
expected_nevra="$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$package_path" 2>/dev/null || true)"
expected_sha="$(shasum -a 256 "$package_path" | awk '{print $1}')"
[[ "$expected_nevra" == silisili-native-devel-*.aarch64 ]] || {
    printf 'fast_install=blocked|reason=unexpected-rpm|nevra=%s\n' "$expected_nevra" >&2
    exit 65
}

PHONE_IP="$phone_ip" PHONE_PORT="$phone_port" \
    python3 "$script_dir/send-phone-file-python.py" "$package_path" "$remote_rpm" \
    --mode 0644 --timeout "${PHONE_FILE_TIMEOUT:-240}" \
    --line-delay "${PHONE_FILE_LINE_DELAY:-0.0002}" \
    --suffix-delay "${PHONE_FILE_SUFFIX_DELAY:-0.05}"

tmp_script="$(mktemp "${TMPDIR:-/tmp}/silisili-native-fast-install.XXXXXX.sh")"
trap 'rm -f "$tmp_script"' EXIT HUP INT TERM
cat >"$tmp_script" <<EOF
#!/bin/sh
set -eu
remote_rpm='$remote_rpm'
expected_sha='$expected_sha'
expected_nevra='$expected_nevra'
actual_sha="\$(sha256sum "\$remote_rpm" | awk '{print \$1}')"
test "\$actual_sha" = "\$expected_sha"
rpm -Uvh --replacepkgs "\$remote_rpm"
test "\$(rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel)" = "\$expected_nevra"
test -z "\$(rpm -V silisili-native-devel 2>/dev/null || true)"
rm -f "\$remote_rpm"
printf 'native_fast_install=ready|nevra=%s|sha256=%s|rpm_verify=clean|visual_model=unused\\n' "\$expected_nevra" "\$expected_sha"
EOF
chmod 0755 "$tmp_script"
PHONE_IP="$phone_ip" PHONE_PORT="$phone_port" \
    python3 "$script_dir/run-phone-script.py" "$tmp_script" \
    --timeout "${PHONE_SCRIPT_TIMEOUT:-240}" \
    --line-delay "${PHONE_SCRIPT_LINE_DELAY:-0.0002}"
