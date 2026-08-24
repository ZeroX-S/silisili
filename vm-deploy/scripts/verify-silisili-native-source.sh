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
grep -Fxq 'src/appsettings.cpp' "$temporary/cmake-files" \
    || fail missing-app-settings-cmake-source
grep -Fxq 'src/appsettings.h' "$temporary/qmake-files" \
    || fail missing-app-settings-qmake-header
grep -Fxq 'src/systemcontrols.cpp' "$temporary/cmake-files" \
    || fail missing-system-controls-cmake-source
grep -Fxq 'src/systemcontrols.h' "$temporary/qmake-files" \
    || fail missing-system-controls-qmake-header
vm_build_wrapper="$PROJECT_ROOT/../vm-build-native-rpm.sh"
if test -f "$vm_build_wrapper"; then
    grep -Fq "'\$source_copy/src/appsettings.cpp'" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-app-settings-source
    grep -Fq "'\$source_copy/src/systemcontrols.cpp'" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-system-controls-source
    grep -Fq "moc_appsettings.cpp" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-app-settings-moc
    grep -Fq "moc_systemcontrols.cpp" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-system-controls-moc
    grep -Fq "appsettings.o" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-app-settings-object
    grep -Fq "systemcontrols.o" "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-system-controls-object
    grep -Fq 'silisili-native.privileges' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-privileges-stage
    grep -Fq 'libminimedia-audiosource-shim.so' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-minimedia-shim-stage
    grep -Fq 'silisili-native-minimedia-wrapper.sh' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-minimedia-wrapper-stage
    grep -Fq 'silisili-native-minimedia.service' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-minimedia-service-stage
    grep -Fq 'cover-action-pip.png' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-cover-pip-stage
    grep -Fq 'cover-action-cover.png' "$vm_build_wrapper" \
        || fail vm-build-wrapper-missing-cover-cover-stage
fi

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
grep -Fq 'After=local-fs.target droid-hal-init.service' \
    "$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native-minimedia.service" \
    || fail minimedia-service-droid-hal-ordering-missing

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
grep -Fq 'const int kAutomaticOriginalQuality = 10000;' \
    "$NATIVE_ROOT/src/liveresolver.cpp" \
    || fail live-automatic-original-request-missing
grep -Fq 'capabilityAwareCodecSelection' "$NATIVE_ROOT/src/liveresolver.cpp" \
    || fail live-capability-aware-codec-selection-missing
grep -Fq 'm_selectedQuality = selected.currentQuality;' \
    "$NATIVE_ROOT/src/liveresolver.cpp" \
    || fail live-server-current-quality-verification-missing
grep -Fq 'liveQualityCatalog(streams, descriptions,' \
    "$NATIVE_ROOT/src/liveresolver.cpp" \
    || fail live-supported-quality-catalog-missing
grep -Fq 'Q_PROPERTY(double sourceFrameRate READ sourceFrameRate' \
    "$NATIVE_ROOT/src/mpvvideoitem.h" \
    || fail live-actual-frame-rate-property-missing
grep -Fq 'label + QStringLiteral(" · ") + actual' \
    "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail live-actual-quality-label-missing
grep -Fq 'native live quality: actual stream ready' \
    "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-actual-quality-semantic-marker-missing
grep -Fq 'playbackSession.setSurfaceHighResolution(videoHost, true)' \
    "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-fullscreen-resolution-promotion-missing
grep -Fq 'nativeForcedOrientation === "landscape" ? 3 : 0' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail live-regression-orientation-still-portrait-locked
grep -Fq 'Q_PROPERTY(int presentedVideoWidth READ presentedVideoWidth' \
    "$NATIVE_ROOT/src/mpvvideoitem.h" \
    || fail final-presentation-viewport-property-missing
grep -Fq '"sourcePixelsPreserved", sourcePixelsPreserved' \
    "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-final-presentation-quality-gate-missing
grep -Fq 'native live quality: safe fallback requested' \
    "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail live-original-safe-fallback-missing

# Anonymous VOD/PGC starts at 720P (Bilibili qn=64). A signed-in cold start
# must retain 1080P without waiting for asynchronous /nav verification, and an
# explicit regression/user quality request must continue to override policy.
grep -Fq 'Q_PROPERTY(bool hasSessionCredentials READ hasSessionCredentials NOTIFY changed)' \
    "$NATIVE_ROOT/src/accountservice.h" \
    || fail account-session-credential-property-missing
grep -Fq 'Q_PROPERTY(int defaultPlaybackQuality READ defaultPlaybackQuality NOTIFY changed)' \
    "$NATIVE_ROOT/src/accountservice.h" \
    || fail account-default-playback-quality-property-missing
grep -Fq 'return (m_loggedIn || hasSessionCredentials()) ? 80 : 64;' \
    "$NATIVE_ROOT/src/accountservice.cpp" \
    || fail anonymous-default-playback-quality-not-720p
grep -Fq 'property int requestedInitialPlaybackQuality: 0' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail video-initial-quality-override-missing
grep -Fq '? requestedInitialPlaybackQuality : accountService.defaultPlaybackQuality' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail video-account-quality-policy-missing
grep -Fq '? requestedInitialPlaybackQuality : accountService.defaultPlaybackQuality' \
    "$NATIVE_ROOT/qml/pages/PgcDetailPage.qml" \
    || fail pgc-account-quality-policy-missing
grep -Fq 'requestedInitialPlaybackQuality: nativeTestQuality' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail explicit-test-quality-override-missing
grep -Fq 'accountService.defaultPlaybackQuality' \
    "$NATIVE_ROOT/qml/pages/HomePage.qml" \
    || fail home-default-quality-policy-missing
grep -Fq 'accountService.defaultPlaybackQuality' \
    "$NATIVE_ROOT/qml/pages/PlayerPage.qml" \
    || fail fullscreen-default-quality-policy-missing
if grep -Eq 'prepareVideo\([^\n]*,[[:space:]]*80\)|prefetchVideo\([^\n]*,[[:space:]]*80\)|playbackSession\.playVideo\([^\n]*,[[:space:]]*80\)' \
        "$NATIVE_ROOT/qml/pages/HomePage.qml" "$NATIVE_ROOT/qml/pages/PlayerPage.qml"; then
    fail vod-cold-start-quality-hard-coded-1080p
fi
grep -Fq 'native playback quality: initial policy' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail video-initial-quality-semantic-marker-missing
grep -Fq 'native playback quality: initial policy' \
    "$NATIVE_ROOT/qml/pages/PgcDetailPage.qml" \
    || fail pgc-initial-quality-semantic-marker-missing
grep -Fq 'native player: DASH response below 720P; retrying 720P progressive' \
    "$NATIVE_ROOT/src/playbackresolver.cpp" \
    || fail anonymous-dash-to-progressive-720p-fallback-missing
grep -Fq 'dashQuality < kProgressiveFallbackQuality' \
    "$NATIVE_ROOT/src/playbackresolver.cpp" \
    || fail anonymous-dash-720p-fallback-boundary-missing
if grep -Eq 'startPosition,[[:space:]]*80\)|initialCover,[[:space:]]*80\)' \
        "$NATIVE_ROOT/qml/pages/PgcDetailPage.qml"; then
    fail pgc-initial-quality-still-hard-coded-1080p
fi
anonymous_quality_probe="$PROJECT_ROOT/vm-deploy/scripts/probe-silisili-native-anonymous-default-quality.sh"
test -x "$anonymous_quality_probe" \
    || fail anonymous-default-quality-probe-missing
grep -Fq 'presentationAspectRetained' \
    "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail quality-switch-presentation-aspect-retention-missing
grep -Fq 'automaticOrientations: playbackSession.videoAspectRatio > 1.05' \
    "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-page-bypasses-retained-presentation-aspect
grep -Fq 'return currentAspect > 0.0 ? currentAspect : m_retainedVideoAspectRatio;' \
    "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail quality-switch-aspect-fallback-missing
grep -Fq 'playbackSession.mediaKind === "live"' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-live-state-missing
grep -Fq 'model: watermarkPlane.columns * watermarkPlane.rows' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-handheld-watermark-tiling-missing
grep -Fq 'readonly property int columns: 5' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-handheld-watermark-column-count-drift
grep -Fq 'readonly property int rows: 8' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-handheld-watermark-row-count-drift
grep -Fq 'source: "qrc:/qml/assets/cover-idle-logo.png"' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-idle-logo-missing
grep -Fq 'native cover: idle logo ready' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-idle-logo-semantic-marker-missing
test "$(sha256sum "$NATIVE_ROOT/qml/assets/cover-idle-logo.png" \
        | awk '{print $1}')" \
    = 1a06fa8e088984fb7ba40fed5c6bdb0ba22e73fa9a0a7524aa33c4d66ca19766 \
    || fail cover-idle-logo-payload-drift
grep -Fq 'source: "qrc:/qml/assets/cover-handheld-watermark.png"' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-supplied-handheld-artwork-missing
test "$(sha256sum "$NATIVE_ROOT/qml/assets/cover-handheld-watermark.png" \
        | awk '{print $1}')" \
    = 107e18e4ffa838395d5ef8f606f1db50eb73eba523fc021f6c8476b6d9e5760e \
    || fail cover-handheld-artwork-payload-drift
test "$(sha256sum "$NATIVE_ROOT/qml/assets/cover-action-pip.png" \
        | awk '{print $1}')" \
    = 24cf9e092bf0cdcaa08d73ec0ea1d07ed86998fc4190173f3b267846bdf48704 \
    || fail cover-pip-icon-payload-drift
test "$(sha256sum "$NATIVE_ROOT/qml/assets/cover-action-cover.png" \
        | awk '{print $1}')" \
    = bfe0ad5fdecc3a234f66b24d0455c9cdb0134842806f26eb900e4c29d98350ce \
    || fail cover-mode-icon-payload-drift
grep -Fq 'id: resolutionLabel' "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-resolution-first-layout-missing
grep -Fq 'id: titleMarquee' "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-single-line-marquee-missing
grep -Fq 'width: parent.width * cover.progressRatio' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-progress-indicator-missing
grep -Fq 'spacing: distributedGap' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-balanced-distribution-missing
grep -Fq '(height - fixedContentHeight - videoHeight) / 3' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-balanced-gap-formula-drift
grep -Fq 'Math.abs(occupiedHeight - height) <= 1' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-balanced-height-invariant-missing
grep -Fq 'playbackCover.balancedDistribution' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-balanced-runtime-marker-missing
resolution_line=$(grep -nF 'id: resolutionLabel' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" | cut -d: -f1)
video_line=$(grep -nF 'id: artwork' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" | cut -d: -f1)
title_line=$(grep -nF 'id: titleClip' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" | cut -d: -f1)
progress_line=$(grep -nF 'id: progressBlock' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" | cut -d: -f1)
test "$resolution_line" -lt "$video_line" \
    && test "$video_line" -lt "$title_line" \
    && test "$title_line" -lt "$progress_line" \
    || fail cover-active-layout-order-drift
test "$(grep -Fc 'CoverAction {' \
        "$NATIVE_ROOT/qml/cover/CoverPage.qml")" -eq 3 \
    || fail cover-action-count-drift
grep -Fq 'readonly property bool hasPlayback:' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-page-aware-playback-state-missing
grep -Fq 'typeof currentApplicationPage.coverPlaybackPage !== "undefined"' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-page-context-guard-missing
grep -Fq 'readonly property bool compactPlaybackActive:' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-compact-playback-state-missing
grep -Fq 'playbackSession.active && playbackSession.compact' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-compact-session-guard-missing
grep -Fq 'playbackPageActive || compactPlaybackActive' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-page-compact-eligibility-missing
grep -Fq 'readonly property bool coverCompactPlaybackActive:' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail application-cover-compact-state-missing
grep -Fq 'coverPlaybackPageActive || coverCompactPlaybackActive' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail application-cover-page-compact-eligibility-missing
grep -Fq 'nativeTestContentMode === "home-cover"' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail compact-home-cover-test-route-missing
if grep -Fq 'enabled: cover.hasPlayback' \
        "$NATIVE_ROOT/qml/cover/CoverPage.qml"; then
    fail cover-action-unsupported-enabled-property-regression
fi
grep -Fq 'cover: Qt.resolvedUrl("cover/CoverPage.qml")' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail cover-single-action-list-lifetime-missing
if grep -Fq 'IdleCoverPage.qml' "$NATIVE_ROOT/qml/qml.qrc"; then
    fail cover-idle-object-tree-regression
fi
grep -Fq 'native cover: idle action icons cleared' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-idle-icon-clear-semantic-marker-missing
test "$(grep -Fc ': ""' "$NATIVE_ROOT/qml/cover/CoverPage.qml")" -ge 3 \
    || fail cover-idle-empty-icon-sources-missing
test -x "$SCRIPT_DIR/probe-silisili-native-cover-stop-actions.sh" \
    || fail cover-stop-actions-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-compact-cover-context.sh" \
    || fail compact-cover-context-probe-not-executable
test "$(grep -Fc 'visible: !cover.hasPlayback' \
        "$NATIVE_ROOT/qml/cover/CoverPage.qml")" -eq 2 \
    || fail cover-idle-artwork-state-drift
grep -Fq 'visible: cover.hasPlayback' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-playback-content-state-missing
grep -Fq 'native cover: presentation state ready' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-presentation-state-marker-missing
grep -Fq 'native cover: stop action handled' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-stop-action-semantic-marker-missing
grep -Fq 'window: cover.Window.window' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-action-window-lifetime-binding-missing
for playback_page in VideoDetailPage.qml PlayerPage.qml PgcDetailPage.qml \
        LivePlayerPage.qml; do
    grep -Fq 'readonly property bool coverPlaybackPage: true' \
        "$NATIVE_ROOT/qml/pages/$playback_page" \
        || fail cover-playback-page-marker-missing
done
if grep -Fq 'enabled: playbackSession.active' \
        "$NATIVE_ROOT/qml/cover/CoverPage.qml"; then
    fail cover-actions-session-only-regression
fi
if grep -Fq 'homeFeed.refresh()' "$NATIVE_ROOT/qml/cover/CoverPage.qml"; then
    fail cover-idle-content-action-regression
fi
grep -Fq 'native cover: background presentation toggle handled' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-pip-toggle-semantic-marker-missing
grep -Fq 'systemPipController.setBackgroundPlaybackMode(next)' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-pip-toggle-control-missing
grep -Fq 'file:///usr/share/icons/hicolor/86x86/apps/silisili-native-cover-pip.png' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-pip-toggle-icon-missing
grep -Fq 'file:///usr/share/icons/hicolor/86x86/apps/silisili-native-cover-cover.png' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-mode-toggle-icon-missing
grep -Fq 'silisili-native-cover-pip.png' \
    "$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.spec" \
    || fail cover-pip-icon-rpm-payload-missing
grep -Fq 'silisili-native-cover-cover.png' \
    "$PROJECT_ROOT/packaging/apps/silisili-native/silisili-native.spec" \
    || fail cover-mode-icon-rpm-payload-missing
grep -Fq 'stage/silisili-native-cover-pip.png' \
    "$PROJECT_ROOT/vm-deploy/scripts/build-silisili-native-rpm.sh" \
    || fail cover-pip-icon-stage-missing
grep -Fq 'stage/silisili-native-cover-cover.png' \
    "$PROJECT_ROOT/vm-deploy/scripts/build-silisili-native-rpm.sh" \
    || fail cover-mode-icon-stage-missing
grep -Fq 'anchors.bottomMargin: Theme.itemSizeSmall + Theme.paddingSmall' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-action-safe-area-missing
grep -Fq 'native cover: active layout ready' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-active-layout-semantic-marker-missing
grep -Fq 'property string lastLayoutProbeSignature: ""' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-active-layout-log-dedup-state-missing
grep -Fq 'signature === cover.lastLayoutProbeSignature' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-active-layout-log-dedup-guard-missing
grep -Fq 'Component.onCompleted: reportReadiness()' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-idle-cached-logo-readiness-missing
grep -Fq '&& !coverLayoutProbe.running' \
    "$NATIVE_ROOT/qml/cover/CoverPage.qml" \
    || fail cover-layout-probe-edge-trigger-missing
if grep -Fq 'coverLayoutProbe.restart()' \
        "$NATIVE_ROOT/qml/cover/CoverPage.qml"; then
    fail cover-layout-probe-progress-starvation-regression
fi
grep -Fq 'Q_PROPERTY(int contentColumns READ contentColumns' \
    "$NATIVE_ROOT/src/appsettings.h" \
    || fail content-column-setting-property-missing
grep -Fq 'QSettings().value(QString::fromLatin1(kContentColumnsKey), 2)' \
    "$NATIVE_ROOT/src/appsettings.cpp" \
    || fail content-column-default-not-two
grep -Fq 'Q_PROPERTY(bool continueInAppMiniPlayer READ continueInAppMiniPlayer' \
    "$NATIVE_ROOT/src/appsettings.h" \
    || fail mini-player-policy-setting-property-missing
grep -Fq 'Q_PROPERTY(int fontSizeMode READ fontSizeMode' \
    "$NATIVE_ROOT/src/appsettings.h" \
    || fail font-size-mode-setting-property-missing
grep -Fq 'Q_INVOKABLE int scaledFontSize' \
    "$NATIVE_ROOT/src/appsettings.h" \
    || fail font-size-scaling-helper-missing
grep -Fq 'appSettings.fontSizeMode)' \
    "$NATIVE_ROOT/qml/pages/PlaybackPresentationPage.qml" \
    || fail font-size-binding-dependency-missing
if grep -RE 'appSettings\.scaledFontSize\([^,)]*\)' "$NATIVE_ROOT/qml" >/dev/null; then
    fail font-size-untracked-binding-regression
fi
grep -Fq 'appSettings.fontSizeMode = currentIndex' \
    "$NATIVE_ROOT/qml/pages/PlaybackPresentationPage.qml" \
    || fail font-size-mode-control-missing
grep -Fq 'appSettings.scaledFontSize' "$NATIVE_ROOT/qml/pages/HomePage.qml" \
    || fail home-font-scaling-missing
grep -Fq 'appSettings.scaledFontSize' "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail detail-font-scaling-missing
grep -Fq 'SilicaGridView {' "$NATIVE_ROOT/qml/pages/HomePage.qml" \
    || fail home-configurable-grid-missing
grep -Fq 'SilicaGridView {' "$NATIVE_ROOT/qml/pages/LiveFeedPage.qml" \
    || fail live-configurable-grid-missing
grep -Fq 'appSettings.contentColumns === 2 ? 2 : 1' \
    "$NATIVE_ROOT/qml/pages/HomePage.qml" \
    || fail home-column-setting-binding-missing
grep -Fq 'appSettings.contentColumns === 2 ? 2 : 1' \
    "$NATIVE_ROOT/qml/pages/LiveFeedPage.qml" \
    || fail live-column-setting-binding-missing
grep -Fq 'appSettings.continueInAppMiniPlayer = checked' \
    "$NATIVE_ROOT/qml/pages/PlaybackPresentationPage.qml" \
    || fail mini-player-policy-control-missing
grep -Fq 'native compact player: page exit stopped playback' \
    "$NATIVE_ROOT/src/playbacksession.cpp" \
    || fail mini-player-disabled-stop-boundary-missing
grep -Fq 'playbackSession.liveRoomId === roomId' \
    "$NATIVE_ROOT/qml/pages/LivePlayerPage.qml" \
    || fail live-compact-restore-without-reload-missing
grep -Fq 'returnSurfaceOwner: page' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail fullscreen-return-surface-owner-missing
grep -Fq 'Q_PROPERTY(double brightnessPercent READ brightnessPercent' \
    "$NATIVE_ROOT/src/systemcontrols.h" \
    || fail system-brightness-property-missing
grep -Fq 'Q_PROPERTY(double volumePercent READ volumePercent' \
    "$NATIVE_ROOT/src/systemcontrols.h" \
    || fail system-volume-property-missing
grep -Fq 'restorePlaybackSession' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-control-restore-missing
grep -Fq 'native system controls: playback session restored' \
    "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-control-restore-marker-missing
grep -Fq 'pactl' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-volume-pulseaudio-route-missing
grep -Fq 'sink-input-by-media-role:x-maemo' \
    "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-volume-stream-restore-media-entry-missing
grep -Fq 'QDBusConnection::connectToPeer' \
    "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-volume-stream-restore-peer-route-missing
grep -Fq 'writePulseStreamRestoreVolume' \
    "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-volume-stream-restore-write-missing
grep -Fq '/pulse/native' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-volume-runtime-socket-missing
grep -Fq 'mcetool' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-brightness-mcetool-route-missing
grep -Fq -- '--set-display-brightness=' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-brightness-mcetool-write-missing
grep -Fq '/sys/class/backlight' "$NATIVE_ROOT/src/systemcontrols.cpp" \
    || fail system-brightness-backlight-route-missing
grep -Fq 'systemControls.beginPlaybackSession();' "$NATIVE_ROOT/src/main.cpp" \
    || fail system-controls-playback-save-hook-missing
grep -Fq 'systemControls.restorePlaybackSession' "$NATIVE_ROOT/src/main.cpp" \
    || fail system-controls-playback-restore-hook-missing
if grep -Fq 'm_foregroundRefreshTimer.start();' "$NATIVE_ROOT/src/playbacksession.cpp"; then
    fail foreground-refresh-double-pulse-regression
fi
grep -Fq 'systemPipController.setBackgroundPlaybackMode("cover")' \
    "$NATIVE_ROOT/qml/SystemPipWindow.qml" \
    || fail pip-close-returns-to-cover-missing
grep -Fq 'native compact player: close stop handled' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail compact-close-stop-marker-missing
grep -A12 -F 'native compact player: close stop handled' \
    "$NATIVE_ROOT/qml/main.qml" \
    | grep -Fq 'playbackSession.stop()' \
    || fail compact-close-stop-route-missing
grep -Fq 'native compact player: close stop completed' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail compact-close-stop-state-marker-missing
if grep -R -Fq 'dismissCompactSurface' "$NATIVE_ROOT"; then
    fail obsolete-compact-dismiss-surface-route-present
fi
grep -Fq 'id: compactDragArea' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail compact-full-surface-drag-area-missing
grep -Fq 'drag.target: compactPlayer' \
    "$NATIVE_ROOT/qml/main.qml" \
    || fail compact-drag-target-missing
if grep -Fq 'PlayerGestureArea {' "$NATIVE_ROOT/qml/main.qml"; then
    fail compact-player-gesture-area-regression
fi
if grep -Fq 'systemController: systemControls' "$NATIVE_ROOT/qml/main.qml"; then
    fail compact-system-controls-route-regression
fi
grep -A5 -F 'text: commentData.messageText' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    | grep -Fq 'Theme.fontSizeSmall,' \
    || fail detail-comment-body-small-font-missing
grep -A5 -F 'text: messageText' \
    "$NATIVE_ROOT/qml/pages/CommentsPage.qml" \
    | grep -Fq 'Theme.fontSizeSmall,' \
    || fail comments-page-body-small-font-missing
grep -A5 -F 'text: rootMessage' \
    "$NATIVE_ROOT/qml/pages/ReplyThreadPage.qml" \
    | grep -Fq 'Theme.fontSizeSmall,' \
    || fail reply-root-body-small-font-missing
grep -A5 -F 'text: messageText' \
    "$NATIVE_ROOT/qml/pages/ReplyThreadPage.qml" \
    | grep -Fq 'Theme.fontSizeSmall,' \
    || fail reply-child-body-small-font-missing
grep -Fq 'systemController: systemControls' \
    "$NATIVE_ROOT/qml/pages/VideoDetailPage.qml" \
    || fail video-detail-system-controls-route-missing
grep -Fq 'systemController: systemControls' \
    "$NATIVE_ROOT/qml/pages/PgcDetailPage.qml" \
    || fail pgc-detail-system-controls-route-missing
grep -Fq 'systemController.setBrightnessPercent' \
    "$NATIVE_ROOT/qml/components/PlayerGestureArea.qml" \
    || fail gesture-system-brightness-route-missing
grep -Fq 'systemController.setVolumePercent' \
    "$NATIVE_ROOT/qml/components/PlayerGestureArea.qml" \
    || fail gesture-system-volume-route-missing
if grep -Fq 'controller.setBrightness' \
        "$NATIVE_ROOT/qml/components/PlayerGestureArea.qml"; then
    fail gesture-local-brightness-regression
fi
if grep -Fq 'controller.setVolume' \
        "$NATIVE_ROOT/qml/components/PlayerGestureArea.qml"; then
    fail gesture-local-volume-regression
fi
test -x "$SCRIPT_DIR/probe-silisili-native-system-controls.sh" \
    || fail system-controls-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-system-controls-transaction.sh" \
    || fail system-controls-transaction-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-volume-gesture.sh" \
    || fail system-volume-gesture-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-compact-system-controls.sh" \
    || fail compact-system-controls-negative-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-compact-close-stop.sh" \
    || fail compact-close-stop-probe-not-executable
grep -Fq 'native compact player: close stop completed' \
    "$SCRIPT_DIR/probe-silisili-native-compact-close-stop.sh" \
    || fail compact-close-stop-probe-state-gate-missing
grep -Fq 'native cover: idle action icons cleared actions 0' \
    "$SCRIPT_DIR/probe-silisili-native-compact-close-stop.sh" \
    || fail compact-close-stop-probe-cover-idle-gate-missing
test -x "$SCRIPT_DIR/stop-silisili-native-app.sh" \
    || fail native-stop-helper-not-executable
test "$(grep -Fc '/tmp/bonito-direct-touch swipe 540 2157 540 1257 500 25' \
        "$PROJECT_ROOT/vm-deploy/scripts/probe-silisili-native-live-background-presentation.sh")" \
    -eq 2 || fail landscape-background-gesture-probe-drift
if grep -Eq 'SILISILI_NATIVE_(TEST|FORCE_ORIENTATION)' "$DESKTOP"; then
    fail test-hook-enabled-in-desktop
fi

# Droidmedia grants buffer_created() an extra strong reference and requires
# clients returning true to release it with droid_media_buffer_destroy(). The
# user-data marker also prevents the adaptation from granting another reference
# on every reuse of the same gralloc slot. Keep the stop/restart GPU drain as a
# separate guard for frames whose EGL fence has not yet been polled.
grep -Fq 'droid_media_buffer_set_user_data(buffer, this);' \
    "$NATIVE_ROOT/src/droidvideodecoder.cpp" \
    || fail droidmedia-created-buffer-user-data-missing
grep -Fq 'droid_media_buffer_destroy(*buffer);' \
    "$NATIVE_ROOT/src/droidvideodecoder.cpp" \
    || fail droidmedia-created-buffer-destroy-missing
grep -Fq '"buffer-queue-release-post-worker"' \
    "$NATIVE_ROOT/src/droidvideodecoder.cpp" \
    || fail droidmedia-buffer-release-callback-unbalanced
grep -Fq 'deferredUntilWorkersExit' \
    "$NATIVE_ROOT/src/droidvideodecoder.cpp" \
    || fail droidmedia-buffer-release-worker-race-guard-missing
grep -Fq 'drainDeferredHardwareBuffers("stall-restart")' \
    "$NATIVE_ROOT/src/mpvvideoitem.cpp" \
    || fail droidmedia-stall-restart-gpu-drain-missing

# A privileged notification QQuickView must not keep the process alive after
# the primary task is closed. The order is intentional: hide/release PiP,
# stop the session, then destroy decoder/mpv/GL while Qt is still alive.
grep -Fq 'native application shutdown: main window close received' \
    "$NATIVE_ROOT/src/main.cpp" \
    || fail main-window-close-barrier-missing
grep -Fq 'systemPipController.shutdown();' "$NATIVE_ROOT/src/main.cpp" \
    || fail system-pip-application-shutdown-missing
grep -Fq 'playbackVideo.shutdown();' "$NATIVE_ROOT/src/main.cpp" \
    || fail playback-application-shutdown-missing
grep -Fq 'm_view->releaseResources();' \
    "$NATIVE_ROOT/src/systempipcontroller.cpp" \
    || fail system-pip-scenegraph-release-missing
grep -Fq 'native application shutdown: playback resources released' \
    "$NATIVE_ROOT/src/mpvvideoitem.cpp" \
    || fail playback-resource-release-marker-missing
test -x "$SCRIPT_DIR/probe-silisili-native-pip-shutdown.sh" \
    || fail pip-shutdown-probe-not-executable
test -x "$SCRIPT_DIR/probe-silisili-native-vod-cover-layout.sh" \
    || fail vod-cover-layout-probe-not-executable
grep -Fq 'SILISILI_COVER_TEST_BVID:-BV1P4ddBBEJF' \
    "$SCRIPT_DIR/probe-silisili-native-vod-cover-layout.sh" \
    || fail vod-cover-layout-fixed-source-missing
grep -Fq 'native cover video: live shared-texture frame presented' \
    "$SCRIPT_DIR/probe-silisili-native-vod-cover-layout.sh" \
    || fail vod-cover-layout-frame-advance-gate-missing
grep -Fq 'occupied_height=$2' \
    "$SCRIPT_DIR/probe-silisili-native-vod-cover-layout.sh" \
    || fail vod-cover-layout-runtime-geometry-gate-missing

printf 'native_source_verify=ready|version=%s|release=%s|sources=%s|qrc_resources=%s|cmake_qmake=aligned|desktop=production|playback_session=vod-pgc-live-separated|background_presentation=shared|droidmedia_buffer_refs=balanced|system_pip=notification-configurable-shutdown-safe|release_asset=declared|visual_model=unused\n' \
    "$spec_version" "$spec_release" \
    "$(wc -l <"$temporary/source-files" | tr -d ' ')" \
    "$(sed -n 's|.*<file[^>]*>\([^<]*\)</file>.*|\1|p' "$qrc" | wc -l | tr -d ' ')"
