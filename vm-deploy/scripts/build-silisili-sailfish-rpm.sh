#!/usr/bin/env bash
set -euo pipefail

umask 0022
export LC_ALL=C
export TZ=UTC
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1784764800}"
export SOURCE_DATE_EPOCH

PROJECT_ROOT="${PROJECT_ROOT:-/root/bonito-deploy}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/artifacts/generated-blobs/apps}"
PACKAGE_DIR="$PROJECT_ROOT/packaging/apps/silisili"
PATCH_PATH="$PROJECT_ROOT/patches/silisili-sailfish-mobile.patch"
MPV_PATCH_PATH="$PROJECT_ROOT/patches/mpv-libmpv-external-fbo-fence.patch"
SOURCE_ROOT="${UPSTREAM_SOURCE_ROOT:-/tmp/wiliwili-layout-source}"
BASE_RPM="${BASE_RPM:-$OUTPUT_DIR/wiliwili-sailfish-1.6.0-1.bonito4.aarch64.rpm}"
DEV_DEB_DIR="${DEV_DEB_DIR:-/tmp/silisili-debs}"
BUILD_JOBS="${BUILD_JOBS:-4}"
CC="${CC:-aarch64-linux-gnu-gcc}"

UPSTREAM_WILIWILI_COMMIT=88e5876bea9502d06f46a8656e3530684d3aaf7d
BOREALIS_COMMIT=5f08b286f3df737f3321d2247a6fe633fcead03c
BASE_RPM_SHA=cb7eef2534fd4cd78c7363a502d4771f881015ada27f61f5b6508076297dfb95
LIBSTDCXX_SHA=c5cf486565ca33f11a7841f6a8f67797c9c8a484a235c3cd36ca6b41328c67b2
LIBMPV_ORIGINAL_SHA=238f5e04bf4174e73b9a99794255f74215334cae7d87ae0c210958a8378cdbdf
LIBMPV_PATCHED_SHA=d00c6d043bfdd0a8eeb04ae4a857830441cab22e6921518ff94095396b94ee59
ICON_SOURCE_SHA=6661ac8ecd46f84adcae16e558b84632d35784ef86301ac38465568f59ce4289
ICON_MARK_SHA=27ce3c16fa071ec6a6654847503d017cf5c3d641624a80a69c347a2dc5914187
LOGO_SHA=aaab93a98faed7fee8b107e968f898ec28c8517d9da70f62ca4c2fd8a1c4fe3f
ICON_TEMPLATE_SHA=a626c13264226d0f8060d773d99038f72c598d879d8823b2fd9efb85268d2e9a
MPV_DEB=libmpv-dev_0.37.0-1ubuntu4_arm64.deb
MPV_DEB_SHA=7919bdb8d5908b23453b8f9eb9cbfb393aa0540d521c614cbc3016d0878fe3c4
CURL_DEB=libcurl4-openssl-dev_8.5.0-2ubuntu10.11_arm64.deb
CURL_DEB_SHA=452a4e98bb15714688c1a53387192c91e0a320d045a1306d4e1f696c0296e0db

for tool in apt-get cmake cpio dpkg-deb git ninja patchelf python3 readelf \
    rpm2cpio rpmbuild rpmspec sha256sum strip touch "$CC"; do
    command -v "$tool" >/dev/null || {
        echo "Missing build tool: $tool" >&2
        exit 1
    }
done
python3 -c 'from PIL import Image' >/dev/null

test "$(sha256sum "$BASE_RPM" | awk '{print $1}')" = "$BASE_RPM_SHA"
test "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" = "$UPSTREAM_WILIWILI_COMMIT"
test "$(git -C "$SOURCE_ROOT/library/borealis" rev-parse HEAD)" = "$BOREALIS_COMMIT"
test -z "$(git -C "$SOURCE_ROOT" status --porcelain --untracked-files=no)" || {
    echo "upstream wiliwili source tree is not clean" >&2
    exit 1
}
test -z "$(git -C "$SOURCE_ROOT/library/borealis" status --porcelain --untracked-files=no)" || {
    echo "Borealis source tree is not clean" >&2
    exit 1
}
test -f "$PATCH_PATH"
test -f "$MPV_PATCH_PATH"
grep -Fq 'gl->FenceSync && p->params.swap_buffers' "$MPV_PATCH_PATH"

work="$(mktemp -d /tmp/silisili-sailfish-build.XXXXXX)"
base_root="$work/base"
source_root="$work/source"
build_root="$work/build"
dev_root="$work/devroot"
deb_root="$work/debs"
stage="$work/stage"
topdir="$work/rpmbuild"
cleanup() {
    if test "${KEEP_WORK:-0}" = 1; then
        echo "Preserved build directory: $work"
    else
        find "$work" -depth -delete
    fi
}
trap cleanup EXIT

install -d -m0755 "$base_root" "$dev_root" "$deb_root" "$stage/lib" \
    "$stage/licenses" "$stage/icons" "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} \
    "$OUTPUT_DIR"
(cd "$base_root" && rpm2cpio "$BASE_RPM" | cpio --quiet -idmu)

copy_or_download_deb() {
    local package="$1" version="$2" filename="$3" expected_sha="$4"
    if test -f "$DEV_DEB_DIR/$filename"; then
        cp "$DEV_DEB_DIR/$filename" "$deb_root/$filename"
    else
        (cd "$deb_root" && apt-get download "$package=$version")
    fi
    test "$(sha256sum "$deb_root/$filename" | awk '{print $1}')" = "$expected_sha"
    dpkg-deb -x "$deb_root/$filename" "$dev_root"
}

copy_or_download_deb libmpv-dev 0.37.0-1ubuntu4 "$MPV_DEB" "$MPV_DEB_SHA"
copy_or_download_deb libcurl4-openssl-dev 8.5.0-2ubuntu10.11 "$CURL_DEB" "$CURL_DEB_SHA"
test -f "$dev_root/usr/include/mpv/client.h"
test -f "$dev_root/usr/include/aarch64-linux-gnu/curl/curl.h"
test -x "$dev_root/usr/bin/curl-config"

cp -a "$SOURCE_ROOT" "$source_root"
git -C "$source_root" apply --check "$PATCH_PATH"
git -C "$source_root" apply "$PATCH_PATH"
grep -Fq SILISILI_SAILFISH_MOBILE \
    "$source_root/library/borealis/library/lib/core/application.cpp"
grep -Fq 'dialog->setCursor(cursor + utf8len(preeditTextBuffer.data()));' \
    "$source_root/library/borealis/library/lib/platforms/glfw/glfw_ime.cpp"
grep -Fq 'dialog->setCountText(std::to_string(textBuffer.size()) + "/" +' \
    "$source_root/library/borealis/library/lib/platforms/glfw/glfw_ime.cpp"
! grep -Fq 'Sailfish Maliit commitString: bytes=' \
    "$source_root/library/borealis/library/lib/platforms/glfw/glfw_ime.cpp"
test "$(sha256sum "$source_root/resources/icon/icon.png" | awk '{print $1}')" = \
    "$ICON_SOURCE_SHA"
test "$(sha256sum "$source_root/resources/icon/silisili-mark.png" | awk '{print $1}')" = \
    "$ICON_MARK_SHA"
test "$(sha256sum "$source_root/resources/icon/silisili-logo.png" | awk '{print $1}')" = \
    "$LOGO_SHA"
test "$(sha256sum "$PACKAGE_DIR/sailfish-mediaplayer-template-150.png" | awk '{print $1}')" = \
    "$ICON_TEMPLATE_SHA"

export CFLAGS="-ffile-prefix-map=$source_root=/usr/src/silisili-1.0.0 -ffile-prefix-map=$work=/usr/src/silisili-build"
export CXXFLAGS="$CFLAGS"

cmake -S "$source_root" -B "$build_root" -G Ninja \
    -DPLATFORM_DESKTOP=ON \
    -DINSTALL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_RPATH=/usr/lib64/silisili \
    -DCMAKE_INSTALL_RPATH=/usr/lib64/silisili \
    -DCMAKE_EXE_LINKER_FLAGS=-Wl,--build-id=sha1 \
    -DGLFW_BUILD_WAYLAND=ON \
    -DGLFW_BUILD_X11=OFF \
    -DUSE_SYSTEM_CURL=ON \
    -DUSE_GLES2=ON \
    -DUSE_EGL=ON \
    -DBRLS_UNITY_BUILD=ON \
    -DCMAKE_UNITY_BUILD_BATCH_SIZE=16 \
    -DSILISILI_SAILFISH_MOBILE=ON \
    -DMPV_INCLUDE_DIR="$dev_root/usr/include" \
    -DMPV_LIBRARY_mpv="$base_root/usr/lib64/wiliwili/libmpv.so.2.5.0" \
    -DCURL_INCLUDE_DIR="$dev_root/usr/include/aarch64-linux-gnu" \
    -DCURL_LIBRARY=/usr/lib/aarch64-linux-gnu/libcurl.so.4 \
    -DCURL_CONFIG_EXECUTABLE="$dev_root/usr/bin/curl-config"
cmake --build "$build_root" --parallel "$BUILD_JOBS"

# The desktop Exec target remains a small deterministic AArch64 PIE ELF.
"$CC" -Os -fPIE -pie -fno-ident -Wl,-z,relro,-z,now \
    -o "$stage/launcher" "$PACKAGE_DIR/launcher.c"
strip --strip-unneeded "$stage/launcher"

# Stage the rebuilt responsive application and the already validated media runtime.
install -m0755 "$build_root/silisili" "$stage/silisili"
patchelf --set-rpath /usr/lib64/silisili "$stage/silisili"
# This linker emits a different build-id for otherwise byte-identical output.
# Removing only that note makes clean rebuilds reproducible.
strip --strip-unneeded --remove-section=.note.gnu.build-id "$stage/silisili"
for runtime in "$base_root/usr/lib64/wiliwili/"*; do
    test "$(basename "$runtime")" = wiliwili.real && continue
    cp -a "$runtime" "$stage/lib/"
done
chmod 0755 "$stage/lib"

# The validated private mpv predates the external-FBO guard now present in
# upstream mpv. Apply the equivalent single AArch64 branch only after checking
# the complete input and original instruction; keep all media ABI dependencies
# byte-identical and remove the stale build ID after changing executable code.
libmpv="$stage/lib/libmpv.so.2.5.0"
test "$(sha256sum "$libmpv" | awk '{print $1}')" = "$LIBMPV_ORIGINAL_SHA"
LIBMPV_PATH="$libmpv" python3 - <<'PY'
import os
from pathlib import Path

path = Path(os.environ["LIBMPV_PATH"])
data = bytearray(path.read_bytes())
offset = 0x146D14
expected = bytes.fromhex("42 02 00 b4")  # cbz x2, fence_block_end
replacement = bytes.fromhex("12 00 00 14")  # b fence_block_end
actual = bytes(data[offset:offset + len(expected)])
if actual != expected:
    raise SystemExit(f"unexpected libmpv instruction at {offset:#x}: {actual.hex()}")
data[offset:offset + len(replacement)] = replacement
path.write_bytes(data)
PY
strip --remove-section=.note.gnu.build-id "$libmpv"
test "$(sha256sum "$libmpv" | awk '{print $1}')" = "$LIBMPV_PATCHED_SHA"
! readelf -n "$libmpv" | grep -Fq 'Build ID:'

cp -a "$source_root/resources" "$stage/resources"
# Phone builds retain the keyboard/IME font only. Controller mappings and
# controller-specific prompt fonts must not reach the RPM payload.
rm -f "$stage/resources/font/keymap_xbox.ttf" \
    "$stage/resources/font/keymap_ps.ttf" \
    "$stage/resources/font/keymap_keyboard_swap.ttf" \
    "$stage/resources/font/FREEWARE.txt" \
    "$stage/resources/gamecontrollerdb.txt" \
    "$stage/resources/pictures/hint_game_1.png" \
    "$stage/resources/pictures/hint_game_2.png"
cp -a "$base_root/usr/share/icons/hicolor" "$stage/icons/"
cp -a "$base_root/usr/share/licenses/wiliwili-sailfish/." "$stage/licenses/"
install -m0644 "$PACKAGE_DIR/UPSTREAM.md" "$stage/licenses/UPSTREAM.md"
install -m0644 \
    "$source_root/library/borealis/library/lib/extern/glfw/deps/wayland/surface-extension.xml" \
    "$stage/licenses/LICENSE.qt-wayland-surface-extension"
install -m0644 "$PACKAGE_DIR/silisili.desktop" "$stage/silisili.desktop"

# Keep the official Sailfish media-player silhouette and replace only its
# center glyph with the new SiliSili mark.
find "$stage/icons/hicolor" -type f \
    -name 'cn.xfangfang.wiliwili.*' -delete
find "$stage/icons/hicolor" -type f \
    \( -name 'wiliwili-sailfish.*' -o -name 'silisili-sailfish.*' \) -delete
find "$stage/icons/hicolor/scalable" -depth -type d -empty -delete 2>/dev/null || true
ICON_MARK="$source_root/resources/icon/silisili-mark.png" \
ICON_TEMPLATE="$PACKAGE_DIR/sailfish-mediaplayer-template-150.png" \
ICON_ROOT="$stage/icons/hicolor" \
python3 - <<'PY'
import os
from pathlib import Path
from PIL import Image, ImageDraw

mark = Image.open(os.environ["ICON_MARK"]).convert("RGBA")
template = Image.open(os.environ["ICON_TEMPLATE"]).convert("RGBA")
if template.size != (150, 150):
    raise SystemExit(f"unexpected Sailfish template size: {template.size}")

bbox = mark.getchannel("A").getbbox()
if bbox is None:
    raise SystemExit("silisili mark has no visible pixels")
mark = mark.crop(bbox)
scale = min(90 / mark.width, 40 / mark.height)
mark = mark.resize((round(mark.width * scale), round(mark.height * scale)), Image.Resampling.LANCZOS)

master = template.copy()
# The stock play triangle is fully contained by this area of the solid inner circle.
ImageDraw.Draw(master).rectangle((54, 46, 106, 104), fill=(255, 166, 163, 255))
master.alpha_composite(mark, ((150 - mark.width) // 2, (150 - mark.height) // 2))
root = Path(os.environ["ICON_ROOT"])

for size in (16, 24, 32, 48, 64, 86, 108, 128, 172, 256):
    canvas = master.resize((size, size), Image.Resampling.LANCZOS)
    output = root / f"{size}x{size}" / "apps" / "silisili-sailfish.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output, format="PNG", optimize=False, compress_level=9)
PY

find "$stage/resources" "$stage/icons" "$stage/licenses" -type d \
    -exec chmod 0755 {} +
find "$stage/resources" "$stage/icons" "$stage/licenses" -type f \
    -exec chmod a+r {} +
find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

# Verify the complete assembled payload before invoking rpmbuild.
readelf -h "$stage/launcher" | grep -F 'AArch64' >/dev/null
readelf -h "$stage/launcher" | grep -F 'Position-Independent Executable' >/dev/null
readelf -h "$stage/silisili" | grep -F 'AArch64' >/dev/null
readelf -d "$stage/silisili" | grep -F '/usr/lib64/silisili' >/dev/null
grep -aFq 'Sailfish mobile UI baseline: 640x360; fixed short edge: 640; video grids: portrait 2 landscape 4' \
    "$stage/silisili"
grep -aFq 'Sailfish mobile window' "$stage/silisili"
grep -aFq 'Sailfish mobile: saved desktop window state ignored' "$stage/silisili"
grep -aFq 'Sailfish search: system IME; TV alphabet grid disabled' "$stage/silisili"
grep -aFq 'Sailfish search: opening Wayland system IME' "$stage/silisili"
grep -aFq 'Sailfish input dialog: system IME with touch Back/OK toolbar' "$stage/silisili"
grep -aFq 'Sailfish input IME activated after dialog open' "$stage/silisili"
grep -aFq 'Sailfish input IME activation retry after dialog open' "$stage/silisili"
grep -aFq 'Sailfish Maliit peer connected:' "$stage/silisili"
grep -aFq 'Sailfish Maliit input activated: {} keyboard' "$stage/silisili"
grep -aFq 'Sailfish Maliit input deactivated' "$stage/silisili"
grep -aFq 'Sailfish navigation: persistent header and bottom Home/Dynamic/Mine tabs' \
    "$stage/silisili"
grep -aFq 'Sailfish responsive grid: configured={} portrait={} active={}' "$stage/silisili"
grep -aFq 'Sailfish dynamic layout: full-width feed; desktop creator rail hidden' \
    "$stage/silisili"
grep -aFq 'Sailfish pull-to-refresh: triggered at list top' "$stage/silisili"
! grep -aFq 'Sailfish EGL native-fence cleanup: signaled sync_file FDs' "$stage/silisili"
! grep -aFq 'anon_inode:sync_file' "$stage/silisili"
grep -aFq 'Sailfish player touch: tap OSD; center double-tap play; release-to-seek; multi-touch cancellation' \
    "$stage/silisili"
grep -aFq 'Sailfish player navigation: touch-only; custom gamepad routes disabled' \
    "$stage/silisili"
grep -aFq 'Sailfish Bilibili detail layout: portrait' "$stage/silisili"
grep -aFq 'Sailfish Bilibili detail layout: landscape' "$stage/silisili"
grep -aFq 'Sailfish Bilibili fullscreen layout:' "$stage/silisili"
grep -aFq 'Sailfish embedded fullscreen state:' "$stage/silisili"
grep -aFq 'Sailfish content orientation:' "$stage/silisili"
grep -aFq 'Sailfish compositor orientation request:' "$stage/silisili"
! grep -aFq 'Sailfish Wayland surface transform:' "$stage/silisili"
grep -aFq 'Sailfish comments: first page=' "$stage/silisili"
grep -aFq 'Sailfish comments: response request=' "$stage/silisili"
grep -aFq 'Sailfish comments: appended page=' "$stage/silisili"
grep -aFq 'Sailfish comments: authenticated cookie=' "$stage/silisili"
grep -aFq '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' "$stage/silisili"
grep -aFq 'qt_surface_extension' "$stage/silisili"
grep -aFq 'set_content_orientation_mask' "$stage/silisili"
! grep -aFq 'Sailfish video viewport:' "$stage/silisili"
grep -Fq 'aspectRatio="1.777778"' "$stage/resources/xml/activity/player_activity.xml"
grep -Fq 'style="compact"' "$stage/resources/xml/activity/player_activity.xml"
grep -Fq 'height="72"' "$stage/resources/xml/views/video_view.xml"
grep -Fq 'id="video/osd/back"' "$stage/resources/xml/views/video_view.xml"
test -f "$stage/resources/svg/bpx-svg-sprite-back.svg"
grep -Fq 'id="main/search"' "$stage/resources/xml/activity/main.xml"
grep -Fq 'SVG="@res/svg/header-search-dark.svg"' \
    "$stage/resources/xml/activity/main.xml"
grep -Fq 'sidebarPosition="bottom"' "$stage/resources/xml/activity/main.xml"
grep -Fq 'label="@i18n/silisili/navigation/home"' "$stage/resources/xml/activity/main.xml"
grep -Fq 'image="@res/icon/silisili-logo.png"' "$stage/resources/xml/activity/main.xml"
grep -Fq 'wiliwili 1.6.0' "$stage/resources/i18n/zh-Hans/silisili.json"
grep -Fq 'Vibe Coding' "$stage/resources/i18n/zh-Hans/silisili.json"
! grep -Fq 'id="home/search"' "$stage/resources/xml/fragment/home_tab.xml"
! grep -Fq 'height="100%"' "$stage/resources/xml/fragment/dynamic_tab.xml"
! grep -Fq 'height="100%"' "$stage/resources/xml/fragment/mine_tab.xml"
! grep -Fq 'text="y"' "$stage/resources/xml/fragment/home_tab.xml"
! grep -Fq 'text="y"' "$stage/resources/xml/activity/search_activity.xml"
MAIN_XML="$stage/resources/xml/activity/main.xml" python3 - <<'PY'
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
grep -Fq 'Copyright (C) 2015 The Qt Company Ltd.' \
    "$stage/licenses/LICENSE.qt-wayland-surface-extension"
grep -aFq 'glfw: Sailfish touch-first input; joystick and gamepad support disabled' \
    "$stage/silisili"
grep -aFq 'Sailfish render orientation:' "$stage/silisili"
grep -aFq 'renderRotation: {}' "$stage/silisili"
test ! -e "$stage/resources/font/keymap_xbox.ttf"
test ! -e "$stage/resources/font/keymap_ps.ttf"
test ! -e "$stage/resources/font/keymap_keyboard_swap.ttf"
test ! -e "$stage/resources/gamecontrollerdb.txt"
test ! -e "$stage/resources/pictures/hint_game_1.png"
test ! -e "$stage/resources/pictures/hint_game_2.png"
! grep -aFq glfwGetX11Display "$stage/silisili"
! grep -Fq 'Build ID:' <<<"$(readelf -n "$stage/silisili")"
test "$(sha256sum "$stage/lib/libstdc++.so.6.0.34" | awk '{print $1}')" = \
    "$LIBSTDCXX_SHA"
test "$(readlink "$stage/lib/libstdc++.so.6")" = libstdc++.so.6.0.34
test "$(sha256sum "$stage/lib/libmpv.so.2.5.0" | awk '{print $1}')" = \
    "$LIBMPV_PATCHED_SHA"
readelf -d "$stage/lib/libmpv.so.2.5.0" | grep -F 'libplacebo.so.338' >/dev/null
! grep -Fq 'libunwind.so.8' <<<"$(readelf -d "$stage/lib/libplacebo.so.338")"

rpmbuild -bb \
    --define "_topdir $topdir" \
    --define "_buildhost bonito-build" \
    --define "use_source_date_epoch_as_buildtime 1" \
    --define "clamp_mtime_to_source_date_epoch 1" \
    --define "stagingdir $stage" \
    "$PACKAGE_DIR/silisili-sailfish.spec"

package_version="$(rpmspec -q --qf '%{VERSION}-%{RELEASE}' "$PACKAGE_DIR/silisili-sailfish.spec")"
rpm_path="$(find "$topdir/RPMS" -type f \
    -name "silisili-sailfish-${package_version}.aarch64.rpm" -print -quit)"
test -n "$rpm_path"
install -m0644 "$rpm_path" "$OUTPUT_DIR/$(basename "$rpm_path")"
sha256sum "$OUTPUT_DIR/$(basename "$rpm_path")"
