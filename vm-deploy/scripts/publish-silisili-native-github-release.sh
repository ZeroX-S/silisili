#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPEC="$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.spec"
ASSET_MANIFEST="$PROJECT_ROOT/packaging/apps/silisili-native/release-asset.sha256"
DEFAULT_OUTPUT_DIR="$(cd "$PROJECT_ROOT/../.." && pwd)/outputs"

mode=check
repository="${GITHUB_REPOSITORY:-ZeroX-S/silisili}"
rpm_path=""
release_tag=""

fail() {
    printf 'native_github_release=failed|reason=%s\n' "$1" >&2
    exit 1
}

usage() {
    printf '%s\n' \
        "Usage: $0 [--check|--publish] [--rpm PATH] [--repo OWNER/REPO] [--tag TAG]" \
        "" \
        "--check    Validate the release asset and manifest without changing GitHub (default)." \
        "--publish  Require a clean, already-pushed commit, then create/update the prerelease." \
        "--rpm      AArch64 RPM path; defaults to the conversation output directory." \
        "--repo     GitHub repository; defaults to ZeroX-S/silisili." \
        "--tag      Release tag; defaults to native-vVERSION-RELEASE."
}

while (($#)); do
    case "$1" in
        --check)
            mode=check
            ;;
        --publish)
            mode=publish
            ;;
        --rpm)
            shift
            (($#)) || fail missing-rpm-path
            rpm_path=$1
            ;;
        --repo)
            shift
            (($#)) || fail missing-repository
            repository=$1
            ;;
        --tag)
            shift
            (($#)) || fail missing-release-tag
            release_tag=$1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown-argument:$1"
            ;;
    esac
    shift
done

test -f "$SPEC" || fail missing-spec
test -f "$ASSET_MANIFEST" || fail missing-release-asset-manifest

spec_version="$(awk '$1 == "Version:" { print $2; exit }' "$SPEC")"
spec_release="$(awk '$1 == "Release:" { print $2; exit }' "$SPEC")"
test -n "$spec_version" && test -n "$spec_release" || fail invalid-spec-version

expected_filename="silisili-native-devel-${spec_version}-${spec_release}.aarch64.rpm"
if test -z "$rpm_path"; then
    rpm_path="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}/$expected_filename"
fi
if test -z "$release_tag"; then
    release_tag="native-v${spec_version}-${spec_release}"
fi

manifest_sha="$(awk 'NF == 2 { print $1; exit }' "$ASSET_MANIFEST")"
manifest_filename="$(awk 'NF == 2 { print $2; exit }' "$ASSET_MANIFEST")"
test "$manifest_filename" = "$expected_filename" \
    || fail release-manifest-version-drift
printf '%s\n' "$manifest_sha" | grep -Eq '^[0-9a-f]{64}$' \
    || fail invalid-release-manifest-sha256
test -f "$rpm_path" || fail "missing-rpm:$rpm_path"
test "$(basename "$rpm_path")" = "$expected_filename" \
    || fail rpm-filename-version-drift

if command -v sha256sum >/dev/null 2>&1; then
    actual_sha="$(sha256sum "$rpm_path" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
    actual_sha="$(shasum -a 256 "$rpm_path" | awk '{print $1}')"
else
    fail missing-sha256-tool
fi
test "$actual_sha" = "$manifest_sha" || fail rpm-sha256-mismatch

if command -v rpm >/dev/null 2>&1; then
    rpm -K --nosignature "$rpm_path" | grep -Fq 'digests OK' \
        || fail rpm-digest-check-failed
    rpm_identity="$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$rpm_path")"
    test "$rpm_identity" = "silisili-native-devel-${spec_version}-${spec_release}.aarch64" \
        || fail rpm-nevra-mismatch
fi

bash "$SCRIPT_DIR/verify-silisili-native-source.sh" >/dev/null

if test "$mode" = check; then
    printf 'native_github_release=ready|mode=check|repo=%s|tag=%s|asset=%s|sha256=%s\n' \
        "$repository" "$release_tag" "$expected_filename" "$actual_sha"
    exit 0
fi

command -v gh >/dev/null 2>&1 || fail missing-gh-cli
gh auth status >/dev/null 2>&1 || fail github-auth-unavailable
test -z "$(git -C "$PROJECT_ROOT" status --porcelain)" \
    || fail worktree-not-clean

branch="$(git -C "$PROJECT_ROOT" branch --show-current)"
test -n "$branch" || fail detached-head
head_commit="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
git -C "$PROJECT_ROOT" fetch --quiet origin "$branch"
remote_commit="$(git -C "$PROJECT_ROOT" rev-parse "refs/remotes/origin/$branch")"
test "$head_commit" = "$remote_commit" || fail commit-not-pushed

remote_tag_commit="$(git -C "$PROJECT_ROOT" ls-remote --tags origin \
    "refs/tags/$release_tag" | awk 'NR == 1 { print $1 }')"
if test -n "$remote_tag_commit" && test "$remote_tag_commit" != "$head_commit"; then
    fail release-tag-points-to-different-commit
fi

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
checksum_asset="$temporary/${expected_filename}.sha256"
notes_file="$temporary/release-notes.md"
printf '%s  %s\n' "$actual_sha" "$expected_filename" >"$checksum_asset"

{
    printf '# SiliSili Native %s-%s\n\n' "$spec_version" "$spec_release"
    printf 'Sailfish OS AArch64 development build. The RPM was built and device-tested before publication.\n\n'
    printf -- '- Package: `%s`\n' "$expected_filename"
    printf -- '- SHA-256: `%s`\n' "$actual_sha"
    printf -- '- Source commit: `%s`\n\n' "$head_commit"
    printf 'Install on a developer-mode device:\n\n```sh\n'
    printf 'devel-su rpm -Uvh --replacepkgs %s\n' "$expected_filename"
    printf '```\n\nChanges:\n\n'
    awk '
        /^%changelog/ { in_changelog = 1; next }
        in_changelog && /^\*/ {
            if (entry_seen) exit
            entry_seen = 1
            next
        }
        entry_seen { print }
    ' "$SPEC"
} >"$notes_file"

release_title="SiliSili Native ${spec_version}-${spec_release}"
if gh release view "$release_tag" --repo "$repository" >/dev/null 2>&1; then
    gh release upload "$release_tag" "$rpm_path" "$checksum_asset" \
        --repo "$repository" --clobber
    gh release edit "$release_tag" --repo "$repository" \
        --title "$release_title" --notes-file "$notes_file" --prerelease
else
    gh release create "$release_tag" "$rpm_path" "$checksum_asset" \
        --repo "$repository" --target "$branch" --title "$release_title" \
        --notes-file "$notes_file" --prerelease
fi

release_url="$(gh release view "$release_tag" --repo "$repository" \
    --json url --jq .url)"
printf 'native_github_release=ready|mode=published|repo=%s|tag=%s|asset=%s|sha256=%s|url=%s\n' \
    "$repository" "$release_tag" "$expected_filename" "$actual_sha" "$release_url"
