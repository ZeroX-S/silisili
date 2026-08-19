#!/bin/bash
set -euo pipefail

if test "$#" -ne 4; then
    echo 'usage: package-silisili-native-candidate.sh BINARY BASELINE_STAGE SPEC OUTPUT_DIR' >&2
    exit 64
fi

binary=$1
baseline_stage=$2
spec=$3
output_dir=$4

test -x "$binary"
test -d "$baseline_stage/lib"
test -f "$spec"
name=$(awk '$1 == "Name:" { print $2; exit }' "$spec")
version=$(awk '$1 == "Version:" { print $2; exit }' "$spec")
release=$(awk '$1 == "Release:" { print $2; exit }' "$spec")
arch=$(awk '$1 == "BuildArch:" { print $2; exit }' "$spec")
expected_nevra="$name-$version-$release.$arch"
work=$(mktemp -d "/home/builder/silisili-native-package-$release.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

install -d -m0755 "$work/stage" \
    "$work/rpmbuild/BUILD" "$work/rpmbuild/BUILDROOT" \
    "$work/rpmbuild/RPMS" "$work/rpmbuild/SOURCES" \
    "$work/rpmbuild/SPECS" "$work/rpmbuild/SRPMS" "$output_dir"
cp -a "$baseline_stage/." "$work/stage/"
install -m0755 "$binary" "$work/stage/silisili-native"

rpmbuild -bb \
    --define "_topdir $work/rpmbuild" \
    --define '_buildhost sailfish-native-build' \
    --define '_build_id_links none' \
    --define "stagingdir $work/stage" \
    "$spec"
rpm_path=$(find "$work/rpmbuild/RPMS" -type f \
    -name "$name-$version-$release.$arch.rpm" -print -quit)
test -n "$rpm_path"
output_path="$output_dir/$(basename "$rpm_path")"
install -m0644 "$rpm_path" "$output_path"
rpm -K --nosignature "$output_path"
actual_nevra=$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$output_path")
test "$actual_nevra" = "$expected_nevra"
sha=$(sha256sum "$output_path" | awk '{print $1}')
bytes=$(wc -c <"$output_path" | tr -d ' ')

trap - EXIT HUP INT TERM
rm -rf "$work"
printf 'native_candidate_package=ready|nevra=%s|bytes=%s|sha256=%s|path=%s\n' \
    "$actual_nevra" "$bytes" "$sha" "$output_path"
