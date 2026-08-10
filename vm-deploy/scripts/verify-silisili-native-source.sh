#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
NATIVE_ROOT="$PROJECT_ROOT/native"
SPEC="$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.spec"
DESKTOP="$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.desktop"
PRIVILEGES="$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.privileges"
RELEASE_ASSET="$PROJECT_ROOT/packaging/apps/silisili-native/release-asset.sha256"

fail() {
    printf 'native_source_verify=failed|reason=%s\n' "$1" >&2
    exit 1
}

test -f "$SPEC" || fail missing-spec
test -f "$DESKTOP" || fail missing-desktop
test -f "$PRIVILEGES" || fail missing-mapplauncherd-privileges
test -f "$RELEASE_ASSET" || fail missing-release-asset-manifest
test -f "$NATIVE_ROOT/CMakeLists.txt" || fail missing-cmake
test -f "$NATIVE_ROOT/silisili-native.pro" || fail missing-qmake

spec_version="$(awk '$1 == "Version:" { print $2; exit }' "$SPEC")"
spec_release="$(awk '$1 == "Release:" { print $2; exit }' "$SPEC")"
cmake_version="$(sed -n 's/^project(silisili-native VERSION \([^ ]*\) .*/\1/p' \
    "$NATIVE_ROOT/CMakeLists.txt")"
qmake_version="$(awk '$1 == "VERSION" && $2 == "=" { print $3; exit }' \
    "$NATIVE_ROOT/silisili-native.pro")"
test -n "$spec_version" && test -n "$spec_release" || fail invalid-spec-version
test "$spec_version" = "$cmake_version" || fail spec-cmake-version-drift
test "$spec_version" = "$qmake_version" || fail spec-qmake-version-drift
release_asset_sha="$(awk 'NF == 2 { print $1; exit }' "$RELEASE_ASSET")"
release_asset_name="$(awk 'NF == 2 { print $2; exit }' "$RELEASE_ASSET")"
test "$release_asset_name" = \
    "silisili-native-devel-${spec_version}-${spec_release}.aarch64.rpm" \
    || fail release-asset-version-drift
printf '%s\n' "$release_asset_sha" | grep -Eq '^[0-9a-f]{64}$' \
    || fail invalid-release-asset-sha256

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

awk '
    /^add_executable\(silisili-native/ { capture = 1; next }
    capture && /^\)/ { capture = 0; next }
    capture && $1 ~ /^src\/.+\.(cpp|h)$/ { print $1 }
' "$NATIVE_ROOT/CMakeLists.txt" | sort -u >"$temporary/cmake-files"

awk '
    /^SOURCES[[:space:]]*\+=/ { capture = 1 }
    /^HEADERS[[:space:]]*\+=/ { capture = 1 }
    capture {
        for (i = 1; i <= NF; ++i) {
            value = $i
            sub(/\\$/, "", value)
            if (value ~ /^src\/.+\.(cpp|h)$/) print value
        }
        if ($NF !~ /\\$/) capture = 0
    }
' "$NATIVE_ROOT/silisili-native.pro" | sort -u >"$temporary/qmake-files"

find "$NATIVE_ROOT/src" -maxdepth 1 -type f \
    \( -name '*.cpp' -o -name '*.h' \) -print \
    | sed "s|$NATIVE_ROOT/||" \
    | sort -u >"$temporary/source-files"

cmp -s "$temporary/source-files" "$temporary/cmake-files" \
    || fail cmake-source-manifest-drift
cmp -s "$temporary/source-files" "$temporary/qmake-files" \
    || fail qmake-source-manifest-drift
grep -Fxq 'src/systempipcontroller.cpp' "$temporary/cmake-files" \
    || fail missing-system-pip-cmake-source
grep -Fxq 'src/systempipcontroller.h' "$temporary/qmake-files" \
    || fail missing-system-pip-qmake-header

qrc="$NATIVE_ROOT/qml/qml.qrc"
test -f "$qrc" || fail missing-qrc
sed -n 's|.*<file[^>]*>\([^<]*\)</file>.*|\1|p' "$qrc" \
    | while IFS= read -r resource; do
        test -f "$NATIVE_ROOT/qml/$resource" \
            || fail "missing-qrc-resource:$resource"
    done

grep -Fq 'Exec=/usr/bin/silisili-native' "$DESKTOP" || fail invalid-desktop-exec
grep -Fq 'X-Nemo-Application-Type=generic' "$DESKTOP" \
    || fail invalid-sailfish-application-type
grep -Fq '[X-Sailjail]' "$DESKTOP" || fail missing-sailjail-section
grep -Fq 'Sandboxing=Disabled' "$DESKTOP" \
    || fail system-pip-sandbox-still-enabled
grep -Fxq '/usr/bin/silisili-native,' "$PRIVILEGES" \
    || fail invalid-mapplauncherd-privileges
grep -Fq 'QStringLiteral("notification")' "$NATIVE_ROOT/src/systempipcontroller.cpp" \
    || fail system-pip-notification-category-missing
grep -Fq 'setWaylandRegion(m_view, QRegion(), false)' \
    "$NATIVE_ROOT/src/systempipcontroller.cpp" \
    || fail system-pip-empty-opaque-region-missing
grep -Fq 'setWaylandRegion(m_view, m_inputRegion, true)' \
    "$NATIVE_ROOT/src/systempipcontroller.cpp" \
    || fail system-pip-input-region-missing
grep -Fq 'LINK_FLAGS "-pie"' "$NATIVE_ROOT/CMakeLists.txt" \
    || fail privileged-system-pip-not-pie

# PlaybackSession is the one presentation/session owner, while source
# acquisition and transport semantics remain explicitly split by media kind.
# These source gates prevent a later live-page shortcut from silently bringing
# back a second player, an independent background policy, or VOD-only
# operations on a non-seekable live stream.
grep -Fq 'enum MediaKind {' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-media-kind-missing
grep -Fq 'VideoOnDemand,' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-vod-kind-missing
grep -Fq 'PgcOnDemand,' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-pgc-kind-missing
grep -Fq 'LiveStream' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-live-kind-missing
grep -Fq 'PlaybackResolver *m_vodResolver;' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-vod-resolver-missing
grep -Fq 'LiveResolver *m_liveResolver;' "$NATIVE_ROOT/src/playbacksession.h" \
    || fail playback-session-live-resolver-missing
grep -Fq 'm_vodResolver->resolve(' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-vod-routing-missing
grep -Fq 'm_liveResolver->resolve(' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-routing-missing
grep -Fq 'native live transport: seek ignored' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-seek-boundary-missing
grep -Fq 'leaveLiveSourceForOnDemand("video")' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-to-vod-cancel-missing
grep -Fq 'leaveLiveSourceForOnDemand("pgc")' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-to-pgc-cancel-missing
grep -Fq 'm_player->setSpeed(1.0);' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-speed-reset-missing
grep -Fq 'if (live()) return;' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-speed-boundary-missing
grep -Fq 'if (!m_active || live() || !m_player' "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail playback-session-live-history-boundary-missing
grep -Fq 'void LiveResolver::cancel()' "$NATIVE_ROOT/src/liveresolver.cpp" \
    || fail live-resolver-cancel-missing
grep -Fq 'playbackSession.playLive(' "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-page-session-entry-missing
grep -Fq 'playbackSession.requestQuality(' "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-page-session-quality-missing
if grep -Eq 'liveResolver\.(resolve|sourceUrl|selectedQuality|qualities)' \
        "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml"; then
    fail live-page-bypasses-playback-session
fi
if grep -Eq 'MpvVideoItem[[:space:]]*\{' "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml"; then
    fail live-page-local-player-regression
fi
grep -Fq 'playbackSession.mediaKind === "live"' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-live-state-missing
if grep -Eq 'SILISILI_NATIVE_(TEST|FORCE_ORIENTATION)' "$DESKTOP"; then
    fail test-hook-enabled-in-desktop
fi

printf 'native_source_verify=ready|version=%s|release=%s|sources=%s|qrc_resources=%s|cmake_qmake=aligned|desktop=production|playback_session=vod-pgc-live-separated|background_presentation=shared|system_pip=notification-configurable|release_asset=declared|visual_model=unused\n' \
    "$spec_version" "$spec_release" \
    "$(wc -l <"$temporary/source-files" | tr -d ' ')" \
    "$(sed -n 's|.*<file[^>]*>\([^<]*\)</file>.*|\1|p' "$qrc" | wc -l | tr -d ' ')"
