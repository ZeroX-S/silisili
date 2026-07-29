#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-/root/bonito-deploy}"
APP_DIR="${APP_DIR:-$PROJECT_ROOT/artifacts/generated-blobs/apps}"
LISTEN1_RPM="${LISTEN1_RPM:-$APP_DIR/listen1-sailfish-2.33.0-1.bonito1.aarch64.rpm}"
SILISILI_EXPECTED_VERSION="${SILISILI_EXPECTED_VERSION:-1.0.0-2}"
SILISILI_RPM="${SILISILI_RPM:-$APP_DIR/silisili-sailfish-${SILISILI_EXPECTED_VERSION}.aarch64.rpm}"

fail() {
    echo "Ported app RPM verification failed: $*" >&2
    exit 1
}

extract_rpm() {
    local rpm="$1" destination="$2"
    mkdir -p "$destination"
    (cd "$destination" && rpm2cpio "$rpm" | cpio --quiet -idmu)
}

verify_rpm_container() {
    local rpm="$1"
    test -s "$rpm" || fail "missing RPM: $rpm"
    grep -Fq 'digests OK' <<<"$(rpm -K --nosignature "$rpm")" ||
        fail "RPM digest check failed: $rpm"
    test "$(rpm -qp --qf '%{ARCH}' "$rpm")" = aarch64 ||
        fail "RPM is not aarch64: $rpm"
    test -z "$(rpm -qp --scripts "$rpm")" ||
        fail "RPM contains installation scripts: $rpm"
}

verify_elf_versions() {
    local root="$1" allowed_glibc="$2" allowed_glibcxx="$3" allowed_cxxabi="$4"
    local elf max_glibc max_glibcxx max_cxxabi newest
    max_glibc=
    max_glibcxx=
    max_cxxabi=
    while IFS= read -r -d '' elf; do
        readelf -h "$elf" >/dev/null 2>&1 || continue
        newest="$(readelf --version-info "$elf" 2>/dev/null |
            grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -Vu | tail -1 || true)"
        if test -n "$newest"; then
            max_glibc="$(printf '%s\n%s\n' "$max_glibc" "$newest" | sed '/^$/d' | sort -V | tail -1)"
        fi
        newest="$(readelf --version-info "$elf" 2>/dev/null |
            grep -oE 'GLIBCXX_[0-9]+(\.[0-9]+)+' | sort -Vu | tail -1 || true)"
        if test -n "$newest"; then
            max_glibcxx="$(printf '%s\n%s\n' "$max_glibcxx" "$newest" | sed '/^$/d' | sort -V | tail -1)"
        fi
        newest="$(readelf --version-info "$elf" 2>/dev/null |
            grep -oE 'CXXABI_[0-9]+(\.[0-9]+)+' | sort -Vu | tail -1 || true)"
        if test -n "$newest"; then
            max_cxxabi="$(printf '%s\n%s\n' "$max_cxxabi" "$newest" | sed '/^$/d' | sort -V | tail -1)"
        fi
    done < <(find "$root" -type f -print0)

    test "$(printf '%s\n%s\n' "${max_glibc:-GLIBC_0}" "$allowed_glibc" | sort -V | tail -1)" = "$allowed_glibc" ||
        fail "payload requires newer than $allowed_glibc: $max_glibc"
    test "$(printf '%s\n%s\n' "${max_glibcxx:-GLIBCXX_0}" "$allowed_glibcxx" | sort -V | tail -1)" = "$allowed_glibcxx" ||
        fail "payload requires newer than $allowed_glibcxx: $max_glibcxx"
    test "$(printf '%s\n%s\n' "${max_cxxabi:-CXXABI_0}" "$allowed_cxxabi" | sort -V | tail -1)" = "$allowed_cxxabi" ||
        fail "payload requires newer than $allowed_cxxabi: $max_cxxabi"
    echo "ELF version ceiling passed: glibc=${max_glibc:-none} glibcxx=${max_glibcxx:-none} cxxabi=${max_cxxabi:-none}"
}

verify_needed() {
    local root="$1" elf needed private unknown=0
    while IFS= read -r -d '' elf; do
        readelf -h "$elf" >/dev/null 2>&1 || continue
        while IFS= read -r needed; do
            test -n "$needed" || continue
            private="$root/usr/lib64/silisili/$needed"
            test -e "$private" && continue
            case "$needed" in
                ld-linux-aarch64.so.1|libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libgcc_s.so.1|libstdc++.so.6|libatomic.so.1|libz.so.1|libwebp.so.7|libcurl.so.4|libssl.so.3|libcrypto.so.3|libdbus-1.so.3|libpulse.so.0|libfontconfig.so.1|libfreetype.so.6|libfribidi.so.0|libharfbuzz.so.0|libwayland-client.so.0|libwayland-cursor.so.0|libwayland-egl.so.1|libxkbcommon.so.0|libEGL.so.1|libGLESv2.so.2|libavcodec.so.59|libavfilter.so.8|libavformat.so.59|libavutil.so.57|libswresample.so.4|libswscale.so.6|libQt6Core.so.6|libQt6Gui.so.6|libQt6Network.so.6|libQt6Qml.so.6|libQt6WebEngineCore.so.6|libQt6WebEngineQuick.so.6)
                    ;;
                *)
                    echo "Unknown NEEDED entry in ${elf#$root}: $needed" >&2
                    unknown=1
                    ;;
            esac
        done < <(readelf -d "$elf" 2>/dev/null |
            sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p')
    done < <(find "$root" -type f -print0)
    test "$unknown" -eq 0 || fail "unreviewed shared library dependency"
}

verify_silisili_linkage() {
    local root="$1" output
    output="$(readelf -d "$root/usr/lib64/silisili/silisili.real")"
    grep -Fq 'Shared library: [libstdc++.so.6]' <<<"$output" ||
        fail "silisili.real does not declare the Sailfish GNU C++ runtime"
    test ! -e "$root/usr/lib64/silisili/libstdc++.so.6" ||
        fail "silisili must not package a private GNU C++ runtime"
}

verify_sailfish_icons() {
    local root="$1" template="$2"
    python3 - "$root" "$template" <<'PY'
import sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1]) / "usr/share/icons/hicolor"
template = Image.open(sys.argv[2]).convert("RGBA")
if template.size != (150, 150):
    raise SystemExit(f"unexpected Sailfish template size: {template.size}")
name = "silisili-sailfish.png"
for size in (86, 108, 128, 172):
    path = root / f"{size}x{size}" / "apps" / name
    if not path.is_file():
        raise SystemExit(f"missing Sailfish icon: {path}")
    with Image.open(path) as image:
        if image.size != (size, size) or image.mode != "RGBA":
            raise SystemExit(f"invalid Sailfish icon format: {path} {image.size} {image.mode}")
        alpha = image.getchannel("A")
        bbox = alpha.getbbox()
        if bbox is None:
            raise SystemExit(f"Sailfish icon is fully transparent: {path}")
        expected = template.getchannel("A").resize((size, size), Image.Resampling.LANCZOS)
        if alpha.tobytes() != expected.tobytes():
            raise SystemExit(f"icon does not preserve the Sailfish media-player silhouette: {path}")

legacy = list(root.glob("*/apps/cn.xfangfang.wiliwili.*"))
legacy += list(root.glob("scalable/apps/cn.xfangfang.wiliwili.*"))
if legacy:
    raise SystemExit(f"legacy dotted wiliwili icon is still packaged: {legacy}")
if list(root.glob("*/apps/silisili-sailfish.svg")) or (root / "scalable/apps/silisili-sailfish.svg").exists():
    raise SystemExit("SVG silisili launcher icon is still packaged")
PY
}

verify_rpm_container "$LISTEN1_RPM"
verify_rpm_container "$SILISILI_RPM"
test "$(rpm -qp --qf '%{VERSION}-%{RELEASE}' "$SILISILI_RPM")" = \
    "$SILISILI_EXPECTED_VERSION" || fail "unexpected silisili package version"
test "$(rpm -qp --qf '%{NAME}' "$SILISILI_RPM")" = silisili-sailfish ||
    fail "unexpected silisili package name"
rpm -qp --provides "$SILISILI_RPM" | grep -Fxq 'wiliwili-sailfish = 1.6.0-1.bonito31' ||
    fail "legacy package compatibility provide is missing"
rpm -qp --obsoletes "$SILISILI_RPM" | grep -Fxq 'wiliwili-sailfish <= 1.6.0-1.bonito31' ||
    fail "legacy package replacement rule is missing"
sili_requires="$(rpm -qp --requires "$SILISILI_RPM")"
grep -Fxq 'dbus-libs' <<<"$sili_requires" || fail "silisili D-Bus dependency missing"
grep -Fxq 'maliit-framework-wayland' <<<"$sili_requires" || fail "Maliit service dependency missing"
grep -Fxq 'jolla-keyboard' <<<"$sili_requires" || fail "Sailfish keyboard dependency missing"
sili_file_list="$(rpm -qpl "$SILISILI_RPM")"
! grep -Fxq '/usr/share/icons' <<<"$sili_file_list" ||
    fail "silisili RPM owns the shared /usr/share/icons directory"
grep -Eq '^/usr/share/icons/hicolor/[^/]+/apps/silisili-sailfish\.png$' \
    <<<"$sili_file_list" ||
    fail "silisili RPM contains no application icon files"

work="$(mktemp -d /tmp/ported-app-rpm-verify.XXXXXX)"
trap 'rm -rf "$work"' EXIT
listen_root="$work/listen1"
sili_root="$work/silisili"
extract_rpm "$LISTEN1_RPM" "$listen_root"
extract_rpm "$SILISILI_RPM" "$sili_root"

grep -Fq 'AArch64' <<<"$(readelf -h "$listen_root/usr/bin/listen1-sailfish")" ||
    fail "Listen1 launcher is not AArch64 ELF"
grep -Fxq 'Exec=/usr/bin/listen1-sailfish' \
    "$listen_root/usr/share/applications/listen1-sailfish.desktop" ||
    fail "Listen1 desktop entry does not target its ELF"
grep -Fq 'qrc:///qtwebchannel/qwebchannel.js' \
    "$listen_root/usr/share/listen1-sailfish/web/listen1.html" ||
    fail "Listen1 WebChannel bootstrap missing"
grep -Fq 'function isSailfish()' \
    "$listen_root/usr/share/listen1-sailfish/web/js/lowebutil.js" ||
    fail "Listen1 cookie adaptation missing"
grep -Fq 'class qq' "$listen_root/usr/share/listen1-sailfish/web/js/provider/qq.js" ||
    fail "Listen1 QQ provider missing"
test -f "$listen_root/usr/share/licenses/listen1-sailfish/LICENSE.extension" ||
    fail "Listen1 extension license missing"
grep -Fxq "  const client_id = '';" \
    "$listen_root/usr/share/listen1-sailfish/web/js/github.js" ||
    fail "GitHub OAuth client ID is not blank"
grep -Fxq "  const client_secret = '';" \
    "$listen_root/usr/share/listen1-sailfish/web/js/github.js" ||
    fail "GitHub OAuth client secret is not blank"
grep -Fxq "    apiKey: ''," \
    "$listen_root/usr/share/listen1-sailfish/web/js/lastfm.js" ||
    fail "Last.fm API key is not blank"
grep -Fxq "    apiSecret: ''," \
    "$listen_root/usr/share/listen1-sailfish/web/js/lastfm.js" ||
    fail "Last.fm API secret is not blank"

grep -Fq 'AArch64' <<<"$(readelf -h "$sili_root/usr/bin/silisili")" ||
    fail "silisili desktop launcher is not AArch64 ELF"
grep -Fq 'Position-Independent Executable' <<<"$(readelf -h "$sili_root/usr/bin/silisili")" ||
    fail "silisili desktop launcher is not PIE"
grep -Fq 'Shared library: [libc.so.6]' <<<"$(readelf -d "$sili_root/usr/bin/silisili")" ||
    fail "silisili desktop launcher does not use the system libc"
grep -aFq '/usr/lib64/silisili/silisili.real' "$sili_root/usr/bin/silisili" ||
    fail "silisili desktop launcher has the wrong real executable path"
grep -aFq 'HYBRIS_EGLPLATFORM' "$sili_root/usr/bin/silisili" ||
    fail "silisili desktop launcher does not replace the EGL platform"
grep -aFq 'wayland' "$sili_root/usr/bin/silisili" ||
    fail "silisili desktop launcher does not select Wayland"
grep -Fxq 'Exec=/usr/bin/silisili' \
    "$sili_root/usr/share/applications/cn.silisili.app.desktop" ||
    fail "silisili desktop entry does not target its ELF"
grep -Fxq 'Icon=silisili-sailfish' \
    "$sili_root/usr/share/applications/cn.silisili.app.desktop" ||
    fail "silisili desktop icon name is wrong"
! grep -Fq 'Icon=cn.xfangfang.wiliwili' \
    "$sili_root/usr/share/applications/cn.silisili.app.desktop" ||
    fail "legacy dotted wiliwili icon key remains"
grep -Fq 'AArch64' <<<"$(readelf -h "$sili_root/usr/lib64/silisili/silisili.real")" ||
    fail "silisili.real is not AArch64 ELF"
grep -Fq '/usr/lib64/silisili' <<<"$(readelf -d "$sili_root/usr/lib64/silisili/silisili.real")" ||
    fail "silisili.real private RPATH missing"
! grep -Fq 'Build ID:' <<<"$(readelf -n "$sili_root/usr/lib64/silisili/silisili.real")" ||
    fail "silisili.real contains a non-reproducible build ID"
! grep -aFq '/app/share/wiliwili/resources/' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "silisili.real still contains its Flatpak resource prefix"
grep -aFq '/usr/share/silisili/resources/' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "silisili.real Sailfish resource prefix missing"
grep -aFq 'Sailfish mobile UI baseline: 640x360; fixed short edge: 640; video grids: portrait 2 landscape 4' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Sailfish mobile UI profile marker missing"
grep -aFq 'Sailfish mobile window' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Sailfish short-edge scaling marker missing"
grep -aFq 'Sailfish mobile: saved desktop window state ignored' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "saved window-state bypass marker missing"
grep -aFq 'Sailfish search: system IME; TV alphabet grid disabled' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Sailfish system-IME search marker missing"
grep -aFq 'Sailfish search: opening Wayland system IME' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "explicit system-IME action marker missing"
grep -aFq 'Sailfish pull-to-refresh: triggered at list top' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "phone pull-to-refresh marker missing"
! grep -aFq 'Sailfish EGL native-fence cleanup: signaled sync_file FDs' \
    "$sili_root/usr/lib64/silisili/silisili.real" || \
    fail "unsafe process-wide native-fence cleanup remains"
! grep -aFq 'anon_inode:sync_file' \
    "$sili_root/usr/lib64/silisili/silisili.real" || \
    fail "unsafe sync_file descriptor scanner remains"
! grep -aFq glfwGetX11Display "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "silisili.real still contains the X11 display path"
grep -Fq 'id="main/search"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "global main search control is missing"
grep -Fq 'SVG="@res/svg/header-search-dark.svg"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "global main search icon is missing"
grep -Fq 'sidebarPosition="bottom"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "bottom primary navigation is missing"
grep -Fq 'label="@i18n/silisili/navigation/home"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "Home primary navigation item is missing"
grep -Fq 'label="@i18n/silisili/navigation/dynamic"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "Dynamic primary navigation item is missing"
grep -Fq 'label="@i18n/silisili/navigation/mine"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "Mine primary navigation item is missing"
grep -Fq 'image="@res/icon/silisili-logo.png"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/main.xml" ||
    fail "silisili home word mark is missing"
test -f "$sili_root/usr/share/silisili/resources/icon/silisili-mark.png" ||
    fail "silisili launcher mark source is missing"
grep -Fq 'wiliwili 1.6.0' \
    "$sili_root/usr/share/silisili/resources/i18n/zh-Hans/silisili.json" ||
    fail "upstream attribution is missing from About"
grep -Fq 'Vibe Coding' \
    "$sili_root/usr/share/silisili/resources/i18n/zh-Hans/silisili.json" ||
    fail "Vibe Coding attribution is missing from About"
grep -aFq 'silisili-v1.0' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "silisili v1.0 build identity is missing"
grep -aFq 'Migrated legacy Sailfish configuration to silisili' \
    "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "legacy configuration migration marker is missing"
grep -Fq 'portraitSpanCount="2"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/home_recommends.xml" ||
    fail "portrait homepage grid adaptation is missing"
grep -Fq 'landscapeSpanCount="4"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/home_recommends.xml" ||
    fail "landscape homepage grid adaptation is missing"
grep -aFq 'Sailfish player touch: tap OSD; center double-tap play; release-to-seek; multi-touch cancellation' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "touch-first player marker missing"
grep -aFq 'Sailfish player navigation: touch-only; custom gamepad routes disabled' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "touch-only navigation marker missing"
grep -aFq 'Sailfish input dialog: system IME with touch Back/OK toolbar' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "touch input-toolbar marker missing"
grep -aFq 'Sailfish input IME activated after dialog open' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "post-open input-method marker missing"
grep -aFq 'Sailfish input IME activation retry after dialog open' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "input-method retry marker missing"
grep -aFq 'Sailfish Maliit peer connected:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Maliit peer marker missing"
grep -aFq 'Sailfish Maliit input activated: {} keyboard' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Maliit activation marker missing"
grep -aFq 'Sailfish Maliit input deactivated' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Maliit deactivation marker missing"
grep -aFq 'Sailfish responsive grid: configured={} portrait={} active={}' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "responsive grid fallback marker missing"
grep -aFq 'Sailfish dynamic layout: full-width feed; desktop creator rail hidden' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "full-width Dynamic marker missing"
grep -aFq 'Sailfish Bilibili detail layout: portrait' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "portrait player layout marker missing"
grep -Fq 'style="compact"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/player_activity.xml" || \
    fail "compact video-detail tab style missing"
grep -aFq 'Sailfish Bilibili detail layout: landscape' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "landscape player layout marker missing"
grep -aFq 'Sailfish Bilibili fullscreen layout:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "embedded fullscreen layout marker missing"
grep -aFq 'Sailfish embedded fullscreen state:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "single-view fullscreen marker missing"
grep -aFq 'Sailfish content orientation:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "video orientation marker missing"
grep -aFq 'Sailfish render orientation:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "application render-rotation marker missing"
grep -aFq 'renderRotation: {}' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "logical rotation-angle marker missing"
grep -aFq 'Sailfish compositor orientation request:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "compositor orientation marker missing"
grep -aFq 'Sailfish idle inhibitor:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Wayland idle-inhibitor marker missing"
grep -aFq 'Sailfish screen blanking inhibition:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "playback screen-inhibition marker missing"
grep -aFq 'Sailfish MCE blanking pause:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "MCE blanking-pause fallback marker missing"
grep -aFq 'Sailfish MCE blanking pause denied by display policy' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "MCE blanking-policy rejection marker missing"
! grep -aFq 'Sailfish Wayland surface transform:' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "obsolete Wayland buffer transform remains"
grep -aFq 'Sailfish comments: first page=' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "first-comment marker missing"
grep -aFq 'Sailfish comments: response request=' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "comment cursor response marker missing"
grep -aFq 'Sailfish comments: appended page=' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "comment append marker missing"
grep -aFq 'Sailfish comments: authenticated cookie=' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "comment cookie-selection marker missing"
grep -aFq '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "Sailfish system trust path missing"
grep -aFq 'qt_surface_extension' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "Qt Wayland surface-extension binding missing"
grep -aFq 'set_content_orientation_mask' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "Qt Wayland orientation request missing"
! grep -aFq 'Sailfish video viewport:' "$sili_root/usr/lib64/silisili/silisili.real" ||
    fail "obsolete media viewport remains"
grep -Fq 'aspectRatio="1.777778"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/player_activity.xml" ||
    fail "portrait 16:9 player declaration missing"
grep -Fq 'id="video/comment/recyclingGrid"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/player_activity.xml" ||
    fail "comment grid missing"
grep -Fq 'height="72"' "$sili_root/usr/share/silisili/resources/xml/views/video_view.xml" ||
    fail "compact mobile OSD declaration missing"
grep -Fq 'id="video/osd/back"' "$sili_root/usr/share/silisili/resources/xml/views/video_view.xml" ||
    fail "touch back control missing"
test -f "$sili_root/usr/share/silisili/resources/svg/bpx-svg-sprite-back.svg" ||
    fail "touch back icon missing"
! grep -Fq 'id="home/search"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/home_tab.xml" ||
    fail "obsolete overlapping home search control remains"
! grep -Fq 'height="100%"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/dynamic_tab.xml" ||
    fail "Dynamic page still collapses the primary bottom navigation"
! grep -Fq 'height="100%"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/mine_tab.xml" ||
    fail "Mine page still collapses the primary bottom navigation"
! grep -Fq 'text="y"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/home_tab.xml" ||
    fail "controller Y hint remains on the home search control"
! grep -Fq 'text="y"' \
    "$sili_root/usr/share/silisili/resources/xml/activity/search_activity.xml" ||
    fail "controller Y hint remains on the search results page"
MAIN_XML="$sili_root/usr/share/silisili/resources/xml/activity/main.xml" \
    python3 - <<'PY' || fail "main header or bottom navigation geometry is invalid"
import os
import xml.etree.ElementTree as ET

with open(os.environ["MAIN_XML"], encoding="utf-8") as source:
    xml = source.read().replace(
        "<brls:AppletFrame", '<brls:AppletFrame xmlns:brls="urn:borealis"', 1
    )
root = ET.fromstring(xml)
ids = {node.attrib.get("id"): node for node in root.iter() if node.attrib.get("id")}
assert ids["main/header"].attrib["height"] == "64"
assert ids["main/search"].attrib["width"] == "56"
assert ids["main/search"].attrib["height"] == "56"
assert ids["main/tabFrame"].attrib["sidebarPosition"] == "bottom"
assert not any(node.attrib.get("positionType") == "absolute" for node in root.iter())
PY
! grep -Fq 'positionType="absolute"' \
    "$sili_root/usr/share/silisili/resources/xml/fragment/settings_about.xml" ||
    fail "silisili About page contains overlapping absolute-position content"
grep -Fq 'Copyright (C) 2015 The Qt Company Ltd.' \
    "$sili_root/usr/share/licenses/silisili-sailfish/LICENSE.qt-wayland-surface-extension" ||
    fail "Qt Wayland surface-extension license missing"
grep -aFq 'glfw: Sailfish touch-first input; joystick and gamepad support disabled' \
    "$sili_root/usr/lib64/silisili/silisili.real" || fail "controller-disable marker missing"
for resource in keymap_xbox.ttf keymap_ps.ttf keymap_keyboard_swap.ttf; do
    test ! -e "$sili_root/usr/share/silisili/resources/font/$resource" ||
        fail "controller-only resource remains: $resource"
done
test ! -e "$sili_root/usr/share/silisili/resources/gamecontrollerdb.txt" ||
    fail "game controller mapping database remains"
for resource in hint_game_1.png hint_game_2.png; do
    test ! -e "$sili_root/usr/share/silisili/resources/pictures/$resource" ||
        fail "controller-only hint remains: $resource"
done
test -e "$sili_root/usr/lib64/silisili/libmpv.so.2" || fail "private libmpv missing"
test -e "$sili_root/usr/lib64/silisili/libplacebo.so.338" || fail "private libplacebo missing"
test -e "$sili_root/usr/lib64/silisili/libass.so.9" || fail "private libass missing"
test -e "$sili_root/usr/lib64/silisili/libcurl.so.4" || fail "private curl missing"
test -e "$sili_root/usr/lib64/silisili/libssl.so.3" || fail "private OpenSSL SSL missing"
test -e "$sili_root/usr/lib64/silisili/libcrypto.so.3" || fail "private OpenSSL crypto missing"
test "$(stat -c '%a' "$sili_root/usr/lib64/silisili")" = 755 ||
    fail "silisili private runtime directory is not mode 0755"
test ! -e "$sili_root/usr/lib64/silisili/libstdc++.so.6" ||
    fail "private libstdc++ must not be packaged"
test -e "$sili_root/usr/lib64/silisili/libavcodec.so.59" ||
    fail "private FFmpeg codec library is missing"
test -e "$sili_root/usr/lib64/silisili/libavformat.so.59" ||
    fail "private FFmpeg format library is missing"
readelf -d "$sili_root/usr/lib64/silisili/libmpv.so.2" | grep -Fq libavcodec.so.59 ||
    fail "libmpv is not linked to private FFmpeg 5.1"
readelf -d "$sili_root/usr/lib64/silisili/libavformat.so.59" | grep -Fq libssl.so.3 ||
    fail "private FFmpeg HTTPS is not linked to private OpenSSL 3"
grep -aFq 'https' "$sili_root/usr/lib64/silisili/libavformat.so.59" ||
    fail "private FFmpeg lacks HTTPS protocol support"
readelf -d "$sili_root/usr/lib64/silisili/libcurl.so.4" | grep -Fq libssl.so.3 ||
    fail "libcurl is not linked to private OpenSSL 3"
! grep -Fq libunwind <<<"$(readelf -d "$sili_root/usr/lib64/silisili/libplacebo.so.338")" ||
    fail "libplacebo unexpectedly requires libunwind"
test "$(find "$sili_root/usr/share/licenses/silisili-sailfish" -type f | wc -l)" -ge 10 ||
    fail "silisili license set is incomplete"
verify_sailfish_icons "$sili_root" \
    "$PROJECT_ROOT/packaging/apps/silisili/sailfish-mediaplayer-template-150.png"

verify_needed "$listen_root"
verify_needed "$sili_root"
verify_elf_versions "$listen_root" GLIBC_2.41 GLIBCXX_3.4.32 CXXABI_1.3.14
verify_elf_versions "$sili_root" GLIBC_2.30 GLIBCXX_3.4.28 CXXABI_1.3.12
verify_silisili_linkage "$sili_root"

echo "Ported app RPM verification passed"
